#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

// Replaces nameclasstag.sp, nickblacklist.sp and blank_name_fix.sp.
// Original authors: ChatGPT (class tags / blank names), Nullifidian (blacklist).
// Unload those three plugins before loading this one.
#define PLUGIN_VERSION "2.0.0"
#define CLASS_CHANGE_TAG_DELAY 0.50
#define TEAM_SECURITY 2

public Plugin myinfo = {
	name = "Player Names",
	author = "ChatGPT, Nullifidian",
	description = "Class tags, nickname blacklist and blank-name replacement.",
	version = PLUGIN_VERSION,
	url = ""
};

ConVar g_cvTheaterOverride;
int g_iClassMedic1 = -1;
int g_iClassMedic2 = -1;
int g_iClassMG1 = 6;
int g_iClassMG2 = 14;
int g_iClassVIP = 7;

Handle g_hClassTimer[MAXPLAYERS + 1];
bool g_bHasBaseName[MAXPLAYERS + 1];
bool g_bApplyQueued[MAXPLAYERS + 1];
char g_sBaseName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char g_sClassTag[MAXPLAYERS + 1][8];
char g_sLastApplied[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char g_sLogFilePath[PLATFORM_MAX_PATH];

static const char g_sBlacklist[][32] = {
	"funpay.com",
	"nalog.ru",
	"RustCases",
	"keydrop",
	"csgorun",
	"TradeSkinsFast",
	"Farmskins",
	"csgocases",
	"Chefcases",
	"hellcase",
	"csgoempire",
	"Key-Drop",
	"g4skins",
	"banditcamp",
	"TF2EASY",
	"TRADEIT",
	"Society.gg",
	"CASEDROP",
	"csgolive",
	"BUYSKINS",
	"gmod-best",
	"tasty-drop",
	"CSidling",
	"PTRunners",
	"gocase",
	"CSGOFAST",
	"CaseOpening",
	"GGDROP.GG",
	"RustChance.com",
	"DasokolGoDota2",
	".com",
	".gg"
};

public void OnPluginStart() {
	g_cvTheaterOverride = FindConVar("mp_theater_override");
	if (g_cvTheaterOverride != null)
		g_cvTheaterOverride.AddChangeHook(ConVarChanged_Theater);

	// Keep the original blacklist log destination and entry format.
	BuildPath(Path_SM, g_sLogFilePath, sizeof(g_sLogFilePath), "logs/nickblacklist.log");
	HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_pick_squad", Event_PlayerPickSquad, EventHookMode_Post);
	DetectTheaterAndSetupClasses();

	// Next-frame initialization also supports loading on an occupied server.
	RequestFrame(Frame_InitializePlayers);
}

public void OnConfigsExecuted() {
	DetectTheaterAndSetupClasses();
	RequestFrame(Frame_InitializePlayers);
}

public void OnMapEnd() {
	for (int client = 1; client <= MaxClients; client++) {
		delete g_hClassTimer[client];
		g_bApplyQueued[client] = false;
		g_sClassTag[client][0] = '\0';
		// Retain the full base name for clients continuing to the next map.
	}
}

public void OnClientConnected(int client) {
	ResetClient(client);
}

public void OnClientDisconnect(int client) {
	ResetClient(client);
}

void ResetClient(int client) {
	delete g_hClassTimer[client];
	g_bHasBaseName[client] = false;
	g_bApplyQueued[client] = false;
	g_sBaseName[client][0] = '\0';
	g_sClassTag[client][0] = '\0';
	g_sLastApplied[client][0] = '\0';
}

bool IsHumanInGame(int client) {
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

public void OnClientPutInServer(int client) {
	if (!IsHumanInGame(client))
		return;

	// Clean joins before GameVox captures the name in OnClientPostAdminCheck.
	StoreBaseNameIfNeeded(client);
	ApplyName(client);
}

public void Frame_InitializePlayers(any data) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsHumanInGame(client))
			continue;

		StoreBaseNameIfNeeded(client);
		// Do not bypass a pending class-selection settling delay.
		if (g_hClassTimer[client] == null)
			DetectClassTag(client);
		ApplyName(client);
	}
}

public void Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsHumanInGame(client))
		return;

	char newName[MAX_NAME_LENGTH];
	event.GetString("newname", newName, sizeof(newName));
	// Match the actual expected name instead of consuming an ignore counter.
	// This preserves the untruncated base when our own tagged rename comes back.
	if (g_sLastApplied[client][0] != '\0' && StrEqual(newName, g_sLastApplied[client]))
		return;

	g_sLastApplied[client][0] = '\0';
	// Capture the latest requested name now; only the native rename is deferred.
	StoreCleanBaseName(client, newName);
	QueueApply(client);
}

void QueueApply(int client) {
	if (g_bApplyQueued[client])
		return;

	g_bApplyQueued[client] = true;
	RequestFrame(Frame_ApplyName, GetClientSerial(client));
}

public void Frame_ApplyName(any serial) {
	int client = GetClientFromSerial(serial);
	if (client == 0)
		return;

	g_bApplyQueued[client] = false;
	if (IsHumanInGame(client))
		ApplyName(client);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsHumanInGame(client) || event.GetBool("disconnect"))
		return;

	delete g_hClassTimer[client];
	if (event.GetInt("team") != TEAM_SECURITY) {
		g_sClassTag[client][0] = '\0';
		QueueApply(client);
	} else {
		ScheduleClassRefresh(client);
	}
}

public void Event_PlayerPickSquad(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsHumanInGame(client))
		ScheduleClassRefresh(client);
}

void ScheduleClassRefresh(int client) {
	delete g_hClassTimer[client];
	// Insurgency can emit player_pick_squad before m_iPlayerClass changes.
	g_hClassTimer[client] = CreateTimer(CLASS_CHANGE_TAG_DELAY, Timer_RefreshClass,
		GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RefreshClass(Handle timer, any serial) {
	int client = GetClientFromSerial(serial);
	if (client == 0)
		return Plugin_Stop;

	g_hClassTimer[client] = null;
	if (IsHumanInGame(client)) {
		DetectClassTag(client);
		ApplyName(client);
	}
	return Plugin_Stop;
}

public void ConVarChanged_Theater(ConVar convar, const char[] oldValue, const char[] newValue) {
	DetectTheaterAndSetupClasses();
	for (int client = 1; client <= MaxClients; client++)
		if (IsHumanInGame(client))
			ScheduleClassRefresh(client);
}

void DetectTheaterAndSetupClasses() {
	g_iClassMedic1 = -1;
	g_iClassMedic2 = -1;
	g_iClassMG1 = 6;
	g_iClassMG2 = 14;
	g_iClassVIP = 7;

	char theater[128];
	if (g_cvTheaterOverride != null)
		g_cvTheaterOverride.GetString(theater, sizeof(theater));

	if (StrContains(theater, "medic", false) != -1) {
		g_iClassMedic1 = 6;
		g_iClassMedic2 = 14;
		g_iClassMG1 = 4;
		g_iClassMG2 = 12;
	}
}

void DetectClassTag(int client) {
	g_sClassTag[client][0] = '\0';
	if (GetClientTeam(client) != TEAM_SECURITY)
		return;

	int resource = GetPlayerResourceEntity();
	if (resource == -1)
		return;

	int slot = GetEntProp(resource, Prop_Send, "m_iPlayerClass", 4, client);
	if ((g_iClassMedic1 != -1 && slot == g_iClassMedic1)
	 || (g_iClassMedic2 != -1 && slot == g_iClassMedic2))
		strcopy(g_sClassTag[client], sizeof(g_sClassTag[]), "MEDIC");
	else if (slot == g_iClassMG1 || slot == g_iClassMG2)
		strcopy(g_sClassTag[client], sizeof(g_sClassTag[]), "MG");
	else if (slot == g_iClassVIP)
		strcopy(g_sClassTag[client], sizeof(g_sClassTag[]), "VIP");
}

void StoreBaseNameIfNeeded(int client) {
	if (g_bHasBaseName[client])
		return;

	char name[MAX_NAME_LENGTH];
	if (GetClientName(client, name, sizeof(name)))
		StoreCleanBaseName(client, name);
}

void StoreCleanBaseName(int client, const char[] original) {
	char cleaned[MAX_NAME_LENGTH];
	strcopy(cleaned, sizeof(cleaned), original[GetBaseNameOffset(original)]);

	bool removed;
	for (int i = 0; i < sizeof(g_sBlacklist); i++)
		if (ReplaceString(cleaned, sizeof(cleaned), g_sBlacklist[i], "", false) > 0)
			removed = true;

	if (removed)
		TrimString(cleaned);

	// Removing advertising can expose a formerly embedded class prefix.
	int offset = GetBaseNameOffset(cleaned);
	for (int i = 0; ; i++) {
		cleaned[i] = cleaned[offset + i];
		if (cleaned[i] == '\0')
			break;
	}

	if (IsBlankName(cleaned))
		FormatEx(cleaned, sizeof(cleaned), "Player#%d", GetClientUserId(client));

	strcopy(g_sBaseName[client], sizeof(g_sBaseName[]), cleaned);
	g_bHasBaseName[client] = true;

	if (removed) {
		char auth[32] = "STEAM_ID_PENDING";
		if (IsClientAuthorized(client))
			GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		LogToFile(g_sLogFilePath, "changed [%s] %s's nick to %s", auth, original, cleaned);
	}
}

void ApplyName(int client) {
	StoreBaseNameIfNeeded(client);
	if (!g_bHasBaseName[client])
		return;

	char wanted[MAX_NAME_LENGTH];
	if (g_sClassTag[client][0] == '\0')
		strcopy(wanted, sizeof(wanted), g_sBaseName[client]);
	else
		FormatEx(wanted, sizeof(wanted), "[%s] %s", g_sClassTag[client], g_sBaseName[client]);

	// Formatting may truncate a multibyte character at the name limit.
	int length = strlen(wanted);
	int tail = length - 1;
	while (tail > 0 && (wanted[tail] & 0xC0) == 0x80)
		tail--;
	if (tail >= 0 && GetCharBytes(wanted[tail]) > length - tail)
		wanted[tail] = '\0';

	char current[MAX_NAME_LENGTH];
	GetClientName(client, current, sizeof(current));
	if (StrEqual(current, wanted))
		return;

	strcopy(g_sLastApplied[client], sizeof(g_sLastApplied[]), wanted);
	// The only rename call in the plugin. Never block the resulting event.
	SetClientName(client, wanted);
}

int GetBaseNameOffset(const char[] name) {
	static const char prefixes[][] = {
		"[MEDIC]",
		"[MG]",
		"[VIP]"
	};

	int offset;
	bool found;
	// Match nameclasstag's leading-prefix rules, including stacked tags.
	do {
		found = false;
		for (int i = 0; i < sizeof(prefixes); i++) {
			if (StrContains(name[offset], prefixes[i], false) != 0)
				continue;

			offset += strlen(prefixes[i]);
			while (name[offset] == ' ' || name[offset] == '\t')
				offset++;

			found = true;
			break;
		}
	} while (found);

	return offset;
}

bool IsBlankName(const char[] name) {
	int length = strlen(name);
	int offset;
	while (offset < length) {
		int codepoint = ReadCodePoint(name, length, offset);
		// Invalid UTF-8 is left alone rather than guessing that it is invisible.
		if (codepoint < 0 || !IsBlankCodePoint(codepoint))
			return false;
	}

	return true;
}

int ReadCodePoint(const char[] text, int length, int &offset) {
	int first = text[offset++] & 0xFF;
	if (first < 0x80)
		return first;

	int remaining;
	int codepoint;
	int minimum;
	if (first >= 0xC2 && first <= 0xDF) {
		remaining = 1;
		codepoint = first & 0x1F;
		minimum = 0x80;
	} else if (first >= 0xE0 && first <= 0xEF) {
		remaining = 2;
		codepoint = first & 0x0F;
		minimum = 0x800;
	} else if (first >= 0xF0 && first <= 0xF4) {
		remaining = 3;
		codepoint = first & 0x07;
		minimum = 0x10000;
	} else {
		return -1;
	}

	if (offset + remaining > length)
		return -1;

	for (int i = 0; i < remaining; i++) {
		int next = text[offset++] & 0xFF;
		if ((next & 0xC0) != 0x80)
			return -1;

		codepoint = (codepoint << 6) | (next & 0x3F);
	}

	if (codepoint < minimum || codepoint > 0x10FFFF
	 || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
		return -1;

	return codepoint;
}

bool IsBlankCodePoint(int codepoint) {
	// ASCII whitespace/control characters and common Unicode blank-name tricks.
	// Visible names containing these characters are never edited.
	if (codepoint <= 0x20 || (codepoint >= 0x7F && codepoint <= 0xA0))
		return true;

	if ((codepoint >= 0x2000 && codepoint <= 0x200F)
	 || (codepoint >= 0x2028 && codepoint <= 0x202F)
	 || (codepoint >= 0x2060 && codepoint <= 0x206F)
	 || (codepoint >= 0xFE00 && codepoint <= 0xFE0F)
	 || (codepoint >= 0xE0000 && codepoint <= 0xE007F)
	 || (codepoint >= 0xE0100 && codepoint <= 0xE01EF))
		return true;

	switch (codepoint) {
		case 0x00AD, 0x034F, 0x061C, 0x115F, 0x1160, 0x1680,
			0x180E, 0x205F, 0x2800, 0x3000, 0x3164, 0xFEFF, 0xFFA0:
			return true;
	}

	return false;
}
