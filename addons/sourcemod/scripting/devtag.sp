#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PL_VERSION  "1.2"
#define ADM_ACCESS "sm_devtag"
#define GAMEDATA_FILE "insurgency-bm.games"

GameData g_hGameData = null;
int g_iDeveloperFlagOffset = -1;
int g_iDeveloperStatusOffset = -1;

bool ga_bDevTag[MAXPLAYERS + 1] = {true, ...};
bool ga_bIsAdmin[MAXPLAYERS + 1] = {false, ...};
bool ga_bCapturedOriginal[MAXPLAYERS + 1] = {false, ...};
int ga_iOriginalDeveloperFlag[MAXPLAYERS + 1] = {0, ...};
int ga_iOriginalDeveloperStatus[MAXPLAYERS + 1] = {0, ...};

public Plugin myinfo = {
	name = "devtag",
	author = "Nullifidian",
	description = "Enable INS developer tag through the engine developer state",
	version = PL_VERSION,
	url = ""
};

public void OnPluginStart() {
	g_hGameData = LoadGameConfigFile(GAMEDATA_FILE);
	if (g_hGameData == null)
		SetFailState("[devtag] Missing gamedata: addons/sourcemod/gamedata/%s.txt", GAMEDATA_FILE);

	g_iDeveloperFlagOffset = g_hGameData.GetOffset("CINSPlayer::DeveloperFlag");
	g_iDeveloperStatusOffset = g_hGameData.GetOffset("CINSPlayer::DeveloperStatus");
	if (g_iDeveloperFlagOffset < 0 || g_iDeveloperStatusOffset < 0)
		SetFailState("[devtag] Missing CINSPlayer developer-state offsets in %s.txt", GAMEDATA_FILE);

	RegAdminCmd("sm_devtag", Cmd_DevTag, ADMFLAG_KICK, "Toggle your dev tag");

	HookEvent("player_pick_squad", Event_PlayerPickSquad_Post, EventHookMode_Post);
}

public void OnPluginEnd() {
	for (int client = 1; client <= MaxClients; client++)
		RestoreOriginalDeveloperState(client);

	delete g_hGameData;
}

public void OnMapStart() {
	for (int client = 1; client <= MaxClients; client++)
		ga_bCapturedOriginal[client] = false;
	RequestFrame(Frame_InitialiseExistingClients);
}

public void OnClientPostAdminCheck(int client) {
	if (!IsRealClient(client))
		return;

	ga_bIsAdmin[client] = CheckCommandAccess(client, ADM_ACCESS, ADMFLAG_KICK);
	if (ga_bIsAdmin[client])
		RequestFrame(Frame_ApplyDeveloperState, GetClientUserId(client));
}

public void OnClientDisconnect(int client) {
	if (client < 1 || client > MaxClients)
		return;

	ga_bDevTag[client] = true;
	ga_bIsAdmin[client] = false;
	ga_bCapturedOriginal[client] = false;
	ga_iOriginalDeveloperFlag[client] = 0;
	ga_iOriginalDeveloperStatus[client] = 0;
}

public void Event_PlayerPickSquad_Post(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsRealClient(client) && ga_bIsAdmin[client])
		RequestFrame(Frame_ApplyDeveloperState, GetClientUserId(client));
}

void Frame_InitialiseExistingClients(any data) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsRealClient(client))
			continue;

		ga_bIsAdmin[client] = CheckCommandAccess(client, ADM_ACCESS, ADMFLAG_KICK);
		if (ga_bIsAdmin[client])
			ApplyDeveloperState(client);
	}
}

void Frame_ApplyDeveloperState(any data) {
	int client = GetClientOfUserId(data);
	if (IsRealClient(client) && ga_bIsAdmin[client])
		ApplyDeveloperState(client);
}

static bool IsRealClient(int client) {
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

static void ApplyDeveloperState(int client) {
	if (!IsRealClient(client) || !ga_bIsAdmin[client])
		return;

	if (!ga_bCapturedOriginal[client]) {
		ga_iOriginalDeveloperFlag[client] = GetEntData(client, g_iDeveloperFlagOffset, 1);
		ga_iOriginalDeveloperStatus[client] = GetEntData(client, g_iDeveloperStatusOffset, 1);
		ga_bCapturedOriginal[client] = true;
	}

	int enabled = ga_bDevTag[client] ? 1 : 0;
	SetEntData(client, g_iDeveloperFlagOffset, enabled, 1, true);
	SetEntData(client, g_iDeveloperStatusOffset, enabled, 1, true);
}

static void RestoreOriginalDeveloperState(int client) {
	if (!ga_bCapturedOriginal[client] || !IsRealClient(client))
		return;

	SetEntData(client, g_iDeveloperFlagOffset, ga_iOriginalDeveloperFlag[client], 1, true);
	SetEntData(client, g_iDeveloperStatusOffset, ga_iOriginalDeveloperStatus[client], 1, true);
	ga_bCapturedOriginal[client] = false;
}

public Action Cmd_DevTag(int client, int args) {
	if (!IsRealClient(client) || !ga_bIsAdmin[client])
		return Plugin_Handled;

	ga_bDevTag[client] = !ga_bDevTag[client];
	ApplyDeveloperState(client);

	ReplyToCommand(client, "DevTag: %s", ga_bDevTag[client] ? "ON" : "OFF");
	return Plugin_Handled;
}
