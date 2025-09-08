#pragma semicolon 1 
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <SteamWorks>

public Plugin myinfo = {
	name		= "map_rounds_left",
	author		= "Nullifidian",
	description	= "Prints how many rounds & objectives left",
	version		= "1.1.5",
	url			= "https://steamcommunity.com/id/Nullifidian/"
};

static const char ga_Letters[][] = {
	"n/a","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P"
};

int g_iObjResEntity = -1;
char g_sObjResNetClass[32];

int g_iMaxRounds;
int g_iRoundNow;
int g_iMaxObj;
int g_iActiveObj;
int g_iTimerObjRound;

Handle ga_hTimer[MAXPLAYERS + 1];

char g_sMapTag[64];
char g_sMapName[64];

static const char GC_EXT_DISPLAY_NAME[] = "SteamWorks Extension";
ConVar g_cvConLogFile = null;
char g_szConLogOld[PLATFORM_MAX_PATH];
char g_szConLogTmp[PLATFORM_MAX_PATH];
bool g_bExtReloadProbePending = false;

bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	if (!g_bLateLoad)
		CreateTimer(2.0, Timer_ReloadSW);

	RegConsoleCmd("round",		Cmd_Rounds_Left, "Prints how many rounds & objectives left");

	HookEvent("round_start",			Event_RoundStart,	EventHookMode_PostNoCopy);
	HookEvent("round_end",				Event_RoundEnd,		EventHookMode_PostNoCopy);
	HookEvent("object_destroyed",		ObjEvents_NoCopy,	EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured",	ObjEvents_NoCopy,	EventHookMode_PostNoCopy);

	HookConVarChange(FindConVar("mp_maxrounds"), ConVarChanged);

	g_cvConLogFile = FindConVar("con_logfile");
}

public void OnMapStart() {
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));
	g_iMaxRounds = GetConVarInt(FindConVar("mp_maxrounds"));
	g_iActiveObj = 0;
	g_iMaxObj = 0;
	g_iRoundNow = 0;

	FormatEx(g_sMapTag, sizeof(g_sMapTag), "%s MapStart", g_sMapName);
	CreateTimer(0.1, TimerR_AddTag, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd() {
	g_iObjResEntity = -1;
	g_sObjResNetClass[0] = '\0';
}

public void Event_RoundStart(Event event, char[] name, bool dontBroadcast) {
	CreateTimer(0.1, Timer_RoundStart);
	g_iRoundNow = GameRules_GetProp("m_iRoundPlayedCount") + 1;
	g_iTimerObjRound = -1;
}

public void Event_RoundEnd(Event event, char[] name, bool dontBroadcast) {
	if (g_iRoundNow == g_iMaxRounds) FormatEx(g_sMapTag, sizeof(g_sMapTag), "%s MapEnd", g_sMapName);
	g_iTimerObjRound = -1;
}

public void ObjEvents_NoCopy(Event event, char[] name, bool dontBroadcast) {
	g_iTimerObjRound = g_iRoundNow;
	CreateTimer(1.0, TimerR_MonitorCA, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client) {
	if (!IsFakeClient(client)) ga_hTimer[client] = CreateTimer(60.0, Timer_NewPlayer, client);
}

public void OnClientDisconnect(int client) {
	delete ga_hTimer[client];
}

public Action Cmd_Rounds_Left(int client, int args) {
	if (client == 0) return Plugin_Handled;
	PrintToChat(client, "\x070088cc[BM]\x01 Round: \x070088cc%d\x01/\x070088cc%d\x01 | Objective: \x070088cc%s\x01/\x070088cc%s",
		g_iRoundNow, g_iMaxRounds, ga_Letters[LetterIndex(g_iActiveObj)], ga_Letters[LetterIndex(g_iMaxObj)]);
	return Plugin_Handled;
}

void ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) { g_iMaxRounds = StringToInt(newValue); }

Action Timer_RoundStart(Handle timer) {
	g_iActiveObj = 1;
	if (g_iMaxObj < 1) g_iMaxObj = ObjectiveResource_GetProp("m_iNumControlPoints");
	UpdateMapTag();
	return Plugin_Stop;
}

Action TimerR_MonitorCA(Handle timer) {
	if (g_iTimerObjRound != g_iRoundNow) KillTimer(timer);
	else if (!InCounterAttack()) {
		if (g_iMaxObj > g_iActiveObj || g_iMaxObj == 0) g_iActiveObj++;
		UpdateMapTag();
		KillTimer(timer);
	}
	return Plugin_Continue;
}

Action Timer_NewPlayer(Handle timer, int client) {
	PrintToChat(client, "\x070088cc[BM]\x01 Round: \x070088cc%d\x01/\x070088cc%d\x01 | Objective: \x070088cc%s\x01/\x070088cc%s\n[BM]\x01 Use !round command in chat to see this info",
		g_iRoundNow, g_iMaxRounds, ga_Letters[LetterIndex(g_iActiveObj)], ga_Letters[LetterIndex(g_iMaxObj)]);
	ga_hTimer[client] = null;
	return Plugin_Stop;
}

void UpdateMapTag() {
	FormatEx(g_sMapTag, sizeof(g_sMapTag), "%s %d/%d %s/%s",
		g_sMapName, g_iRoundNow, g_iMaxRounds, ga_Letters[LetterIndex(g_iActiveObj)], ga_Letters[LetterIndex(g_iMaxObj)]);
}

Action TimerR_AddTag(Handle timer) {
	if (strlen(g_sMapTag) > 1) SteamWorks_SetMapName(g_sMapTag);
	return Plugin_Continue;
}

int OR_Cache(bool force = false) {
	if (force || g_iObjResEntity < 1 || !IsValidEntity(g_iObjResEntity)) {
		g_iObjResEntity = FindEntityByClassname(-1, "ins_objective_resource");
		if (g_iObjResEntity > 0) GetEntityNetClass(g_iObjResEntity, g_sObjResNetClass, sizeof(g_sObjResNetClass));
		else g_sObjResNetClass[0] = '\0';
	} else {
		char cls[32];
		GetEntityClassname(g_iObjResEntity, cls, sizeof(cls));
		if (!StrEqual(cls, "ins_objective_resource", false)) return OR_Cache(true);
	}
	return g_iObjResEntity;
}

int ObjectiveResource_GetProp(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1) return GetEntData(g_iObjResEntity, offs + (size * element));
	}
	return -1;
}

bool InCounterAttack() {
	return view_as<bool>(GameRules_GetProp("m_bCounterAttack"));
}

Action Timer_ReloadSW(Handle timer) {
	if (!g_cvConLogFile || g_bExtReloadProbePending) return Plugin_Stop;

	strcopy(g_szConLogTmp, sizeof(g_szConLogTmp), "console_sm_exts_list_tmp.log");
	g_cvConLogFile.GetString(g_szConLogOld, sizeof(g_szConLogOld));

	SetConVarString(g_cvConLogFile, g_szConLogTmp, true, true);
	g_bExtReloadProbePending = true;
	ServerCommand("sm exts list");

	CreateTimer(0.5, Timer_ParseExtsList, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

static int ParseIndexFromLine(const char[] line, const char[] displayName) {
	if (StrContains(line, displayName, false) == -1) return -1;

	int lb = FindCharInString(line, '[', false);
	int rb = FindCharInString(line, ']', false);
	if (lb == -1 || rb == -1 || rb <= lb+1) return -1;

	char numbuf[8];
	int len = rb - lb - 1;
	if (len >= sizeof(numbuf)) len = sizeof(numbuf) - 1;
	strcopy(numbuf, len + 1, line[lb + 1]);
	TrimString(numbuf);

	int idx = StringToInt(numbuf);
	return (idx > 0) ? idx : -1;
}

Action Timer_ParseExtsList(Handle timer) {
	if (g_cvConLogFile) SetConVarString(g_cvConLogFile, g_szConLogOld, true, true);

	int foundIdx = -1;
	Handle f = OpenFile(g_szConLogTmp, "r");
	if (f != null) {
		char line[256];
		while (!IsEndOfFile(f) && ReadFileLine(f, line, sizeof(line))) {
			int idx = ParseIndexFromLine(line, GC_EXT_DISPLAY_NAME);
			if (idx > 0) {
				foundIdx = idx;
				break;
			}
		}
		CloseHandle(f);
	}

	DeleteFile(g_szConLogTmp);
	g_bExtReloadProbePending = false;
	if (foundIdx > 0) ServerCommand("sm exts reload %d", foundIdx);
	return Plugin_Stop;
}

int LetterIndex(int n) { return (n >= 1 && n <= 16) ? n : 0; }