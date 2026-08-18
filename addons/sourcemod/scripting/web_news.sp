/**
 * Web News v1.0.21
 * Downloads public and staff news once per map and presents it through !news.
 * Requires the SteamWorks extension.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <SteamWorks>

#define WEB_NEWS_VERSION "1.0.21"
// Edit this to the folder containing your news files. It must end with a slash.
#define WEB_NEWS_URL "https://botmassacre.com/news/"
// Edit these file names if your web-server news files use different names.
#define WEB_NEWS_MEDIC_FILE "news.txt"
#define WEB_NEWS_NON_MEDIC_FILE "news_nomedic.txt"
#define WEB_NEWS_ADMIN_FILE "admin_news.txt"
// Use different public cookie names for any server that has a unique public news feed.
#define WEB_NEWS_MEDIC_READ_COOKIE "web_news_last_read_medic_date"
#define WEB_NEWS_NON_MEDIC_READ_COOKIE "web_news_last_read_nomedic_date"
// Limits: each file must be <= 16,383 bytes; only the first 512 wrapped display lines are stored.
// The panel uses five stored lines of up to 56 characters per page.
#define NEWS_BODY_MAX 16384
#define NEWS_INPUT_LINE_MAX 256
#define NEWS_DISPLAY_LINE_CHARS 56
#define NEWS_DISPLAY_LINE_SIZE (NEWS_DISPLAY_LINE_CHARS + 1)
#define NEWS_LINES_PER_PAGE 5
#define NEWS_MAX_LINES 512
#define NEWS_RETRY_DELAY 600.0
#define NEWS_ADVERT_MIN_DELAY 900.0
#define NEWS_ADVERT_MAX_DELAY 2700.0
#define NEWS_DATE_LENGTH 11
#define NEWS_ANNOUNCEMENT_STATE_FILE "data/web_news_last_announcement.txt"
#define NEWS_UNREAD_DAYS 7

enum NewsType
{
	News_Public = 0,
	News_Admin
};

ArrayList g_PublicLines;
ArrayList g_AdminLines;
ArrayList g_PublicPageStarts;
ArrayList g_AdminPageStarts;
ConVar g_cvTheaterOverride;

bool g_bPublicLoaded;
bool g_bAdminLoaded;
bool g_bPublicInFlight;
bool g_bAdminInFlight;
bool g_bPublicRetryScheduled;
bool g_bAdminRetryScheduled;
bool g_bFetchedThisMap;
bool g_bLatestPublicNewsIsRecent;
bool g_bLatestAdminNewsIsRecent;

Handle g_hPublicRetry;
Handle g_hAdminRetry;
Handle g_hNewsAdvert;

NewsType g_ViewType[MAXPLAYERS + 1];
int g_iViewPage[MAXPLAYERS + 1];
bool g_bHasSpawned[MAXPLAYERS + 1];
bool g_bClientUnreadNewsNotified[MAXPLAYERS + 1];
bool g_bClientUnreadAdminNewsNotified[MAXPLAYERS + 1];
char g_sLatestPublicNewsDate[NEWS_DATE_LENGTH];
char g_sLatestAdminNewsDate[NEWS_DATE_LENGTH];
char g_sLastAnnouncedNewsDate[NEWS_DATE_LENGTH];
Cookie g_hLastReadMedicNewsCookie;
Cookie g_hLastReadNonMedicNewsCookie;
Cookie g_hLastReadAdminNewsCookie;

public Plugin myinfo =
{
	name = "Web News",
	author = "Nullifidian & Codex",
	description = "Displays map-start news downloaded from a web server.",
	version = WEB_NEWS_VERSION,
	url = ""
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_news", Command_News, "Shows the latest server news.");
	RegAdminCmd("sm_news_reload", Command_ReloadNews, ADMFLAG_ROOT, "Reloads the public and admin news files.");
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	g_cvTheaterOverride = FindConVar("mp_theater_override");

	g_PublicLines = new ArrayList(NEWS_DISPLAY_LINE_SIZE);
	g_AdminLines = new ArrayList(NEWS_DISPLAY_LINE_SIZE);
	g_PublicPageStarts = new ArrayList();
	g_AdminPageStarts = new ArrayList();
	g_hLastReadMedicNewsCookie = RegClientCookie(WEB_NEWS_MEDIC_READ_COOKIE, "Last medic-news date opened by this player.", CookieAccess_Private);
	g_hLastReadNonMedicNewsCookie = RegClientCookie(WEB_NEWS_NON_MEDIC_READ_COOKIE, "Last non-medic-news date opened by this player.", CookieAccess_Private);
	g_hLastReadAdminNewsCookie = RegClientCookie("web_news_last_read_admin_date", "Last admin-news date opened by this player.", CookieAccess_Private);
	LoadLastNewsAnnouncement();

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client))
			g_bHasSpawned[client] = true;
	}
}

public void OnMapStart()
{
	g_bFetchedThisMap = false;
	g_bPublicRetryScheduled = false;
	g_bAdminRetryScheduled = false;
	g_hPublicRetry = null;
	g_hAdminRetry = null;
	delete g_hNewsAdvert;
	ScheduleNewsAdvert();
}

public void OnConfigsExecuted()
{
	if (g_bFetchedThisMap)
		return;

	g_bFetchedThisMap = true;
	RequestAllNews();
}

public void OnPluginEnd()
{
	delete g_hNewsAdvert;
	delete g_PublicLines;
	delete g_AdminLines;
	delete g_PublicPageStarts;
	delete g_AdminPageStarts;
}

public Action Command_News(int client, int args)
{
	if (client < 1 || !IsClientInGame(client))
		return Plugin_Handled;
	if (!g_bHasSpawned[client])
	{
		ReplyToCommand(client, "[News] You need to spawn at least once before opening the news panel.");
		return Plugin_Handled;
	}

	ShowNewsMenu(client);
	return Plugin_Handled;
}

public Action Command_ReloadNews(int client, int args)
{
	ReloadNews();
	ReplyToCommand(client, "[News] News reload started.");
	return Plugin_Handled;
}

static void ReloadNews()
{
	CancelNewsRetry(News_Public);
	CancelNewsRetry(News_Admin);
	RequestAllNews();
}

public void OnClientPutInServer(int client)
{
	g_bHasSpawned[client] = false;
	g_bClientUnreadNewsNotified[client] = false;
	g_bClientUnreadAdminNewsNotified[client] = false;
}

public void OnClientDisconnect(int client)
{
	g_bHasSpawned[client] = false;
	g_bClientUnreadNewsNotified[client] = false;
	g_bClientUnreadAdminNewsNotified[client] = false;
}

public void OnClientCookiesCached(int client)
{
	if (IsClientInGame(client) && !IsFakeClient(client) && g_bHasSpawned[client])
	{
		NotifyClientOfUnreadNews(client);
		NotifyClientOfUnreadAdminNews(client);
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
	{
		g_bHasSpawned[client] = true;
		NotifyClientOfUnreadNews(client);
		NotifyClientOfUnreadAdminNews(client);
	}
}

static void RequestAllNews()
{
	RequestNews(News_Public);
	RequestNews(News_Admin);
}

static void RequestNews(NewsType type)
{
	char url[1024];
	GetNewsUrl(type, url, sizeof(url));

	if (url[0] == '\0')
	{
		PrintToServer("[Web News] %s news URL is empty; download skipped.", type == News_Public ? "Public" : "Admin");
		return;
	}

	if (!LibraryExists("SteamWorks"))
	{
		PrintToServer("[Web News] SteamWorks is unavailable; cannot download %s news.", type == News_Public ? "public" : "admin");
		HandleNewsFailure(type);
		return;
	}

	if (IsNewsInFlight(type))
		return;

	SetNewsInFlight(type, true);
	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
	if (request == null)
	{
		PrintToServer("[Web News] Could not create the %s news request.", type == News_Public ? "public" : "admin");
		SetNewsInFlight(type, false);
		HandleNewsFailure(type);
		return;
	}

	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 15);
	if (type == News_Public)
		SteamWorks_SetHTTPCallbacks(request, OnPublicNewsResponse);
	else
		SteamWorks_SetHTTPCallbacks(request, OnAdminNewsResponse);

	if (!SteamWorks_SendHTTPRequest(request))
	{
		PrintToServer("[Web News] Could not send the %s news request.", type == News_Public ? "public" : "admin");
		CloseHandle(request);
		SetNewsInFlight(type, false);
		HandleNewsFailure(type);
	}
}

public void OnPublicNewsResponse(Handle request, bool failure, bool successful, EHTTPStatusCode status)
{
	ProcessNewsResponse(request, News_Public, failure, successful, status);
}

public void OnAdminNewsResponse(Handle request, bool failure, bool successful, EHTTPStatusCode status)
{
	ProcessNewsResponse(request, News_Admin, failure, successful, status);
}

static void ProcessNewsResponse(Handle request, NewsType type, bool failure, bool successful, EHTTPStatusCode status)
{
	SetNewsInFlight(type, false);

	if (failure || !successful || status != k_EHTTPStatusCode200OK)
	{
		PrintToServer("[Web News] %s news download failed (failure=%d, success=%d, HTTP=%d).", type == News_Public ? "Public" : "Admin", failure, successful, status);
		CloseHandle(request);
		HandleNewsFailure(type);
		return;
	}

	int bodySize;
	if (!SteamWorks_GetHTTPResponseBodySize(request, bodySize) || bodySize < 0 || bodySize >= NEWS_BODY_MAX)
	{
		PrintToServer("[Web News] %s news response is invalid or exceeds %d bytes.", type == News_Public ? "Public" : "Admin", NEWS_BODY_MAX - 1);
		CloseHandle(request);
		HandleNewsFailure(type);
		return;
	}

	char body[NEWS_BODY_MAX];
	if (bodySize > 0 && !SteamWorks_GetHTTPResponseBodyData(request, body, bodySize))
	{
		PrintToServer("[Web News] Could not read the %s news response.", type == News_Public ? "public" : "admin");
		CloseHandle(request);
		HandleNewsFailure(type);
		return;
	}
	body[bodySize] = '\0';

	BuildNewsLines(type, body);
	SetNewsLoaded(type, true);
	CancelNewsRetry(type);
	if (type == News_Public)
		UpdatePublicNewsNotifications();
	else
		UpdateAdminNewsNotifications();
	PrintToServer("[Web News] %s news downloaded (%d display lines).", type == News_Public ? "Public" : "Admin", GetNewsLines(type).Length);
	CloseHandle(request);
}

static void HandleNewsFailure(NewsType type)
{
	if (IsNewsRetryScheduled(type))
		return;

	SetNewsRetryScheduled(type, true);
	SetNewsRetryTimer(type, CreateTimer(NEWS_RETRY_DELAY, Timer_RetryNews, view_as<any>(type)));
	PrintToServer("[Web News] %s news will retry once in 10 minutes.", type == News_Public ? "Public" : "Admin");
}

public Action Timer_RetryNews(Handle timer, any data)
{
	NewsType type = view_as<NewsType>(data);
	SetNewsRetryTimer(type, null);
	RequestNews(type);
	return Plugin_Stop;
}

static void ScheduleNewsAdvert()
{
	if (g_hNewsAdvert == null)
		g_hNewsAdvert = CreateTimer(GetRandomFloat(NEWS_ADVERT_MIN_DELAY, NEWS_ADVERT_MAX_DELAY), Timer_NewsAdvert);
}

public Action Timer_NewsAdvert(Handle timer)
{
	g_hNewsAdvert = null;
	PrintToChatAll("\x04[News]\x01 Type \x03/news\x01 to read the latest server news.");
	ScheduleNewsAdvert();
	return Plugin_Stop;
}

static void BuildNewsLines(NewsType type, const char[] body)
{
	ArrayList lines = GetNewsLines(type);
	ArrayList pageStarts = GetNewsPageStarts(type);
	lines.Clear();
	pageStarts.Clear();
	pageStarts.Push(0);

	char inputLine[NEWS_INPUT_LINE_MAX];
	int inputLength = 0;
	int bodyLength = strlen(body);
	int pageUsed = 0;
	ArrayList datedBlock = new ArrayList(NEWS_DISPLAY_LINE_SIZE);

	for (int i = 0; i < bodyLength; i++)
	{
		if (body[i] == '\r')
			continue;

		if (body[i] == '\n')
		{
			inputLine[inputLength] = '\0';
			ProcessNewsInputLine(lines, pageStarts, datedBlock, inputLine, pageUsed);
			inputLength = 0;
			continue;
		}

		inputLine[inputLength++] = body[i];
		if (inputLength == sizeof(inputLine) - 1)
		{
			inputLine[inputLength] = '\0';
			ProcessNewsInputLine(lines, pageStarts, datedBlock, inputLine, pageUsed);
			inputLength = 0;
		}
	}

	if (inputLength > 0)
	{
		inputLine[inputLength] = '\0';
		ProcessNewsInputLine(lines, pageStarts, datedBlock, inputLine, pageUsed);
	}

	if (datedBlock.Length > 0)
		AddNewsBlock(lines, pageStarts, datedBlock, pageUsed);
	delete datedBlock;
}

static void ProcessNewsInputLine(ArrayList lines, ArrayList pageStarts, ArrayList datedBlock, const char[] input, int &pageUsed)
{
	if (IsNewsDateLine(input))
	{
		if (datedBlock.Length > 0)
		{
			AddNewsBlock(lines, pageStarts, datedBlock, pageUsed);
			datedBlock.Clear();
		}

		WrapNewsLine(datedBlock, input);
		return;
	}

	if (input[0] == '\0')
	{
		if (datedBlock.Length > 0)
		{
			AddNewsBlock(lines, pageStarts, datedBlock, pageUsed);
			datedBlock.Clear();
		}

		// A separator after a full page must not become an empty page of its own.
		if (pageUsed < NEWS_LINES_PER_PAGE)
		{
			ArrayList blankBlock = new ArrayList(NEWS_DISPLAY_LINE_SIZE);
			blankBlock.PushString(" ");
			AddNewsBlock(lines, pageStarts, blankBlock, pageUsed);
			delete blankBlock;
		}
		return;
	}

	if (datedBlock.Length > 0)
	{
		WrapNewsLine(datedBlock, input);
		return;
	}

	ArrayList block = new ArrayList(NEWS_DISPLAY_LINE_SIZE);
	WrapNewsLine(block, input);
	AddNewsBlock(lines, pageStarts, block, pageUsed);
	delete block;
}

static void WrapNewsLine(ArrayList wrappedLines, const char[] input)
{
	int inputLength = strlen(input);
	if (inputLength == 0)
	{
		wrappedLines.PushString(" ");
		return;
	}

	int start = 0;
	while (start < inputLength)
	{
		int end = start + NEWS_DISPLAY_LINE_CHARS;
		if (end >= inputLength)
		{
			char finalLine[NEWS_DISPLAY_LINE_SIZE];
			strcopy(finalLine, sizeof(finalLine), input[start]);
			wrappedLines.PushString(finalLine);
			break;
		}

		int split = end;
		while (split > start && input[split] != ' ' && input[split] != '\t')
			split--;
		if (split == start)
			split = end;

		char displayLine[NEWS_DISPLAY_LINE_SIZE];
		int copyLength = split - start;
		for (int i = 0; i < copyLength; i++)
			displayLine[i] = input[start + i];
		displayLine[copyLength] = '\0';
		wrappedLines.PushString(displayLine);

		start = split;
		while (start < inputLength && (input[start] == ' ' || input[start] == '\t'))
			start++;
	}
}

static void AddNewsBlock(ArrayList lines, ArrayList pageStarts, ArrayList block, int &pageUsed)
{
	if (block.Length == 0 || lines.Length >= NEWS_MAX_LINES)
		return;

	if (pageUsed > 0 && (block.Length > NEWS_LINES_PER_PAGE || pageUsed + block.Length > NEWS_LINES_PER_PAGE))
	{
		pageStarts.Push(lines.Length);
		pageUsed = 0;
	}

	char line[NEWS_DISPLAY_LINE_SIZE];
	for (int i = 0; i < block.Length && lines.Length < NEWS_MAX_LINES; i++)
	{
		if (pageUsed == NEWS_LINES_PER_PAGE)
		{
			pageStarts.Push(lines.Length);
			pageUsed = 0;
		}

		block.GetString(i, line, sizeof(line));
		lines.PushString(line);
		pageUsed++;
	}
}

static bool IsNewsDateLine(const char[] line)
{
	return strlen(line) == 10
		&& IsCharNumeric(line[0]) && IsCharNumeric(line[1])
		&& line[2] == '/'
		&& IsCharNumeric(line[3]) && IsCharNumeric(line[4])
		&& line[5] == '/'
		&& IsCharNumeric(line[6]) && IsCharNumeric(line[7])
		&& IsCharNumeric(line[8]) && IsCharNumeric(line[9]);
}

static void UpdatePublicNewsNotifications()
{
	g_bLatestPublicNewsIsRecent = false;
	g_sLatestPublicNewsDate[0] = '\0';

	char latestDate[NEWS_DATE_LENGTH];
	if (!GetFirstNewsDate(News_Public, latestDate, sizeof(latestDate)))
		return;

	strcopy(g_sLatestPublicNewsDate, sizeof(g_sLatestPublicNewsDate), latestDate);
	if (!IsNewsDateWithinLastDays(latestDate, NEWS_UNREAD_DAYS))
		return;

	g_bLatestPublicNewsIsRecent = true;
	if (IsNewsDateToday(latestDate) && !StrEqual(g_sLastAnnouncedNewsDate, latestDate))
	{
		PrintToChatAll("\x04[News]\x01 New server news is available. Type \x03/news\x01 to read it.");
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client) && !IsFakeClient(client))
				g_bClientUnreadNewsNotified[client] = true;
		}

		strcopy(g_sLastAnnouncedNewsDate, sizeof(g_sLastAnnouncedNewsDate), latestDate);
		SaveLastNewsAnnouncement();
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
			NotifyClientOfUnreadNews(client);
	}
}

static void UpdateAdminNewsNotifications()
{
	g_bLatestAdminNewsIsRecent = false;
	g_sLatestAdminNewsDate[0] = '\0';

	char latestDate[NEWS_DATE_LENGTH];
	if (!GetFirstNewsDate(News_Admin, latestDate, sizeof(latestDate)))
		return;

	strcopy(g_sLatestAdminNewsDate, sizeof(g_sLatestAdminNewsDate), latestDate);
	if (!IsNewsDateWithinLastDays(latestDate, NEWS_UNREAD_DAYS))
		return;

	g_bLatestAdminNewsIsRecent = true;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
			NotifyClientOfUnreadAdminNews(client);
	}
}

static bool GetFirstNewsDate(NewsType type, char[] date, int maxLength)
{
	char line[NEWS_DISPLAY_LINE_SIZE];
	ArrayList lines = GetNewsLines(type);
	for (int i = 0; i < lines.Length; i++)
	{
		lines.GetString(i, line, sizeof(line));
		if (IsNewsDateLine(line))
		{
			strcopy(date, maxLength, line);
			return true;
		}
	}

	return false;
}

static void NotifyClientOfUnreadNews(int client)
{
	if (!g_bHasSpawned[client] || !g_bLatestPublicNewsIsRecent || g_bClientUnreadNewsNotified[client])
		return;
	if (!AreClientCookiesCached(client))
		return;

	char lastReadDate[NEWS_DATE_LENGTH];
	GetClientCookie(client, GetPublicNewsReadCookie(), lastReadDate, sizeof(lastReadDate));
	if (!IsNewsDateNewer(g_sLatestPublicNewsDate, lastReadDate))
		return;

	PrintToChat(client, "\x04[News]\x01 New server news is available. Type \x03/news\x01 to read it.");
	g_bClientUnreadNewsNotified[client] = true;
}

static void MarkLatestPublicNewsRead(int client)
{
	if (g_sLatestPublicNewsDate[0] == '\0' || !AreClientCookiesCached(client))
		return;

	SetClientCookie(client, GetPublicNewsReadCookie(), g_sLatestPublicNewsDate);
	g_bClientUnreadNewsNotified[client] = true;
}

static void NotifyClientOfUnreadAdminNews(int client)
{
	if (!CanReadAdminNews(client) || !g_bHasSpawned[client] || !g_bLatestAdminNewsIsRecent || g_bClientUnreadAdminNewsNotified[client])
		return;
	if (!AreClientCookiesCached(client))
		return;

	char lastReadDate[NEWS_DATE_LENGTH];
	GetClientCookie(client, g_hLastReadAdminNewsCookie, lastReadDate, sizeof(lastReadDate));
	if (!IsNewsDateNewer(g_sLatestAdminNewsDate, lastReadDate))
		return;

	PrintToChat(client, "\x04[Admin News]\x01 You have unread admin news. Type \x03/news\x01 to read it.");
	g_bClientUnreadAdminNewsNotified[client] = true;
}

static void MarkLatestAdminNewsRead(int client)
{
	if (g_sLatestAdminNewsDate[0] == '\0' || !AreClientCookiesCached(client))
		return;

	SetClientCookie(client, g_hLastReadAdminNewsCookie, g_sLatestAdminNewsDate);
	g_bClientUnreadAdminNewsNotified[client] = true;
}

static bool IsNewsDateToday(const char[] date)
{
	char today[NEWS_DATE_LENGTH];
	FormatTime(today, sizeof(today), "%d/%m/%Y");
	return StrEqual(date, today);
}

static bool IsNewsDateWithinLastDays(const char[] date, int maximumAge)
{
	int day;
	int month;
	int year;
	if (!ParseNewsDate(date, day, month, year))
		return false;

	char today[NEWS_DATE_LENGTH];
	FormatTime(today, sizeof(today), "%d/%m/%Y");
	int todayDay;
	int todayMonth;
	int todayYear;
	if (!ParseNewsDate(today, todayDay, todayMonth, todayYear))
		return false;

	int age = DateToDayNumber(todayDay, todayMonth, todayYear) - DateToDayNumber(day, month, year);
	return age >= 0 && age <= maximumAge;
}

static bool IsNewsDateNewer(const char[] candidate, const char[] previous)
{
	int candidateDay;
	int candidateMonth;
	int candidateYear;
	if (!ParseNewsDate(candidate, candidateDay, candidateMonth, candidateYear))
		return false;

	int previousDay;
	int previousMonth;
	int previousYear;
	if (!ParseNewsDate(previous, previousDay, previousMonth, previousYear))
		return true;

	return DateToDayNumber(candidateDay, candidateMonth, candidateYear) > DateToDayNumber(previousDay, previousMonth, previousYear);
}

static bool ParseNewsDate(const char[] date, int &day, int &month, int &year)
{
	if (!IsNewsDateLine(date))
		return false;

	day = (date[0] - '0') * 10 + (date[1] - '0');
	month = (date[3] - '0') * 10 + (date[4] - '0');
	year = (date[6] - '0') * 1000 + (date[7] - '0') * 100 + (date[8] - '0') * 10 + (date[9] - '0');
	return month >= 1 && month <= 12 && day >= 1 && day <= DaysInNewsMonth(month, year);
}

static int DateToDayNumber(int day, int month, int year)
{
	int previousYear = year - 1;
	int total = previousYear * 365 + previousYear / 4 - previousYear / 100 + previousYear / 400;
	for (int i = 1; i < month; i++)
		total += DaysInNewsMonth(i, year);
	return total + day;
}

static int DaysInNewsMonth(int month, int year)
{
	switch (month)
	{
		case 2:
			return IsNewsLeapYear(year) ? 29 : 28;
		case 4, 6, 9, 11:
			return 30;
	}

	return 31;
}

static bool IsNewsLeapYear(int year)
{
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

static void LoadLastNewsAnnouncement()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), NEWS_ANNOUNCEMENT_STATE_FILE);

	File file = OpenFile(path, "r");
	if (file == null)
		return;

	file.ReadLine(g_sLastAnnouncedNewsDate, sizeof(g_sLastAnnouncedNewsDate));
	TrimString(g_sLastAnnouncedNewsDate);
	if (!IsNewsDateLine(g_sLastAnnouncedNewsDate))
		g_sLastAnnouncedNewsDate[0] = '\0';
	delete file;
}

static void SaveLastNewsAnnouncement()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), NEWS_ANNOUNCEMENT_STATE_FILE);

	File file = OpenFile(path, "w");
	if (file == null)
	{
		PrintToServer("[Web News] Could not save the last news announcement date.");
		return;
	}

	file.WriteLine("%s", g_sLastAnnouncedNewsDate);
	delete file;
}

static bool GetNewsPageDate(ArrayList lines, int start, int end, char[] date, int maxLength, bool &continued)
{
	char line[NEWS_DISPLAY_LINE_SIZE];
	for (int i = start; i < end; i++)
	{
		lines.GetString(i, line, sizeof(line));
		if (IsNewsDateLine(line))
		{
			strcopy(date, maxLength, line);
			continued = false;
			return true;
		}
	}

	for (int i = start - 1; i >= 0; i--)
	{
		lines.GetString(i, line, sizeof(line));
		if (IsNewsDateLine(line))
		{
			strcopy(date, maxLength, line);
			continued = true;
			return true;
		}
	}

	return false;
}

static void ShowNewsMenu(int client)
{
	Panel panel = new Panel();
	panel.SetTitle("Server News");
	panel.DrawItem("Read latest news");
	if (CanReadAdminNews(client))
		panel.DrawItem("Read admin news");
	panel.DrawItem("Exit");
	if (CanReloadNews(client))
	{
		panel.DrawText(" ");
		panel.CurrentKey = 5;
		panel.DrawItem("Reload news files");
	}
	panel.Send(client, MenuHandler_NewsMenu, MENU_TIME_FOREVER);
	delete panel;
}

public int MenuHandler_NewsMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action != MenuAction_Select || client < 1 || !IsClientInGame(client))
		return 0;

	if (selection == 1)
	{
		MarkLatestPublicNewsRead(client);
		ShowNewsPanel(client, News_Public, 0);
	}
	else if (selection == 2 && CanReadAdminNews(client))
	{
		MarkLatestAdminNewsRead(client);
		ShowNewsPanel(client, News_Admin, 0);
	}
	else if (selection == 5 && CanReloadNews(client))
	{
		ReloadNews();
		PrintToChat(client, "\x04[News]\x01 News reload started.");
	}

	return 0;
}

static void ShowNewsPanel(int client, NewsType type, int page)
{
	if (!IsNewsLoaded(type))
	{
		PrintToChat(client, "\x04[News]\x01 This news is currently unavailable.");
		return;
	}

	ArrayList lines = GetNewsLines(type);
	ArrayList pageStarts = GetNewsPageStarts(type);
	int pageCount = pageStarts.Length;
	if (page < 0)
		page = 0;
	if (page >= pageCount)
		page = pageCount - 1;

	g_ViewType[client] = type;
	g_iViewPage[client] = page;

	int start = pageStarts.Get(page);
	int end = page < pageCount - 1 ? pageStarts.Get(page + 1) : lines.Length;
	char prefix[32];
	strcopy(prefix, sizeof(prefix), type == News_Public ? "Server News" : "Admin News");
	char title[64];
	char date[11];
	bool continued;
	if (GetNewsPageDate(lines, start, end, date, sizeof(date), continued))
	{
		if (continued)
			Format(title, sizeof(title), "%s - %s (continued)", prefix, date);
		else
			Format(title, sizeof(title), "%s - %s", prefix, date);
	}
	else
		strcopy(title, sizeof(title), prefix);

	Panel panel = new Panel();
	panel.SetTitle(title);

	char line[NEWS_DISPLAY_LINE_SIZE];
	bool drewNewsText = false;
	for (int i = start; i < end; i++)
	{
		lines.GetString(i, line, sizeof(line));
		if (IsNewsDateLine(line))
			continue;
		panel.DrawText(line);
		drewNewsText = true;
	}
	if (!drewNewsText)
		panel.DrawText("There are no announcements.");

	panel.DrawText(" ");
	panel.DrawItem("Next page", page < pageCount - 1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	panel.DrawItem("Previous page", page > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	panel.DrawItem("Back");
	panel.Send(client, MenuHandler_NewsPanel, MENU_TIME_FOREVER);
	delete panel;
}

public int MenuHandler_NewsPanel(Menu menu, MenuAction action, int client, int selection)
{
	if (action != MenuAction_Select || client < 1 || !IsClientInGame(client))
		return 0;

	NewsType type = g_ViewType[client];
	int page = g_iViewPage[client];
	int pageCount = GetNewsPageStarts(type).Length;

	if (selection == 1 && page < pageCount - 1)
	{
		ShowNewsPanel(client, type, page + 1);
		return 0;
	}

	if (selection == 2 && page > 0)
	{
		ShowNewsPanel(client, type, page - 1);
		return 0;
	}

	if (selection == 3)
		ShowNewsMenu(client);
	return 0;
}

static bool CanReadAdminNews(int client)
{
	return CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK, true);
}

static bool CanReloadNews(int client)
{
	return CheckCommandAccess(client, "sm_news_reload", ADMFLAG_ROOT, true);
}

static void GetNewsUrl(NewsType type, char[] url, int maxLength)
{
	if (type == News_Public)
	{
		if (UsesMedicTheater())
			Format(url, maxLength, "%s%s", WEB_NEWS_URL, WEB_NEWS_MEDIC_FILE);
		else
			Format(url, maxLength, "%s%s", WEB_NEWS_URL, WEB_NEWS_NON_MEDIC_FILE);
	}
	else
		Format(url, maxLength, "%s%s", WEB_NEWS_URL, WEB_NEWS_ADMIN_FILE);
}

static Cookie GetPublicNewsReadCookie()
{
	return UsesMedicTheater() ? g_hLastReadMedicNewsCookie : g_hLastReadNonMedicNewsCookie;
}

static bool UsesMedicTheater()
{
	if (g_cvTheaterOverride == null)
		g_cvTheaterOverride = FindConVar("mp_theater_override");
	if (g_cvTheaterOverride == null)
		return false;

	char theaterOverride[PLATFORM_MAX_PATH];
	g_cvTheaterOverride.GetString(theaterOverride, sizeof(theaterOverride));
	return StrContains(theaterOverride, "medic", false) != -1;
}

static ArrayList GetNewsLines(NewsType type)
{
	return type == News_Public ? g_PublicLines : g_AdminLines;
}

static ArrayList GetNewsPageStarts(NewsType type)
{
	return type == News_Public ? g_PublicPageStarts : g_AdminPageStarts;
}

static bool IsNewsLoaded(NewsType type)
{
	return type == News_Public ? g_bPublicLoaded : g_bAdminLoaded;
}

static void SetNewsLoaded(NewsType type, bool value)
{
	if (type == News_Public)
		g_bPublicLoaded = value;
	else
		g_bAdminLoaded = value;
}

static bool IsNewsInFlight(NewsType type)
{
	return type == News_Public ? g_bPublicInFlight : g_bAdminInFlight;
}

static void SetNewsInFlight(NewsType type, bool value)
{
	if (type == News_Public)
		g_bPublicInFlight = value;
	else
		g_bAdminInFlight = value;
}

static bool IsNewsRetryScheduled(NewsType type)
{
	return type == News_Public ? g_bPublicRetryScheduled : g_bAdminRetryScheduled;
}

static void SetNewsRetryScheduled(NewsType type, bool value)
{
	if (type == News_Public)
		g_bPublicRetryScheduled = value;
	else
		g_bAdminRetryScheduled = value;
}

static void SetNewsRetryTimer(NewsType type, Handle timer)
{
	if (type == News_Public)
		g_hPublicRetry = timer;
	else
		g_hAdminRetry = timer;
}

static void CancelNewsRetry(NewsType type)
{
	Handle timer = type == News_Public ? g_hPublicRetry : g_hAdminRetry;
	if (timer != null)
		delete timer;

	SetNewsRetryTimer(type, null);
	SetNewsRetryScheduled(type, false);
}
