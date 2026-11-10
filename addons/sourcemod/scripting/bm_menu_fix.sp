#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.7"
#define HIDEHUD_MISCSTATUS (1 << 6)

public Plugin myinfo = {
	name = "[BM] Menu Fix",
	author = "Nullifidian & Codex",
	description = "Fixes invisible SourceMod menus before the player's first spawn.",
	version = PLUGIN_VERSION
};

Handle g_CheckTimer;
bool g_LateLoad;
bool g_Waiting[MAXPLAYERS + 1];
bool g_Changed[MAXPLAYERS + 1];
int g_LastWritten[MAXPLAYERS + 1];
float g_PlayingSince[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_LateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	if (GetEngineVersion() != Engine_Insurgency)
		SetFailState("This plugin is for Insurgency 2014.");

	if (!g_LateLoad)
		return;

	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client))
			TrackClient(client);
	}
}

public void OnMapEnd() {
	// SourceMod deletes the timer; clear our stored handle as well.
	g_CheckTimer = null;
}

public void OnClientPutInServer(int client) {
	TrackClient(client);
}

void TrackClient(int client) {
	g_Waiting[client] = false;
	g_Changed[client] = false;
	g_PlayingSince[client] = -1.0;
	if (IsFakeClient(client))
		return;

	g_Waiting[client] = true;
	if (g_CheckTimer == null)
		g_CheckTimer = CreateTimer(0.25, Timer_CheckVisibility, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client) {
	bool wasWaiting = g_Waiting[client];
	g_Waiting[client] = false;
	g_Changed[client] = false;
	if (wasWaiting)
		StopTimerIfIdle();
}

bool IsPlaying(int client) {
	// Joining can briefly report alive before entering the viewpoint state.
	return IsPlayerAlive(client) && GetClientTeam(client) >= 2
		&& GetEntProp(client, Prop_Send, "m_iObserverMode") == 0
		&& GetEntityMoveType(client) == MOVETYPE_WALK;
}

bool HasWaitingClients() {
	for (int client = 1; client <= MaxClients; client++) {
		if (g_Waiting[client])
			return true;
	}
	return false;
}

void StopCheckTimer() {
	if (g_CheckTimer != null) {
		delete g_CheckTimer;
		g_CheckTimer = null;
	}
}

void StopTimerIfIdle() {
	if (!HasWaitingClients())
		StopCheckTimer();
}

public Action Timer_CheckVisibility(Handle timer) {
	float now = GetGameTime();
	for (int client = 1; client <= MaxClients; client++) {
		if (!g_Waiting[client])
			continue;
		if (!IsClientInGame(client)) {
			g_Waiting[client] = false;
			g_Changed[client] = false;
			continue;
		}
		if (IsPlaying(client)) {
			if (g_PlayingSince[client] < 0.0)
				g_PlayingSince[client] = now;
			else if (now - g_PlayingSince[client] >= 1.0) {
				g_Waiting[client] = false;
				g_Changed[client] = false;
			}
			continue;
		}
		g_PlayingSince[client] = -1.0;
		if (!HasEntProp(client, Prop_Send, "m_iHideHUD"))
			continue;

		int flags = GetEntProp(client, Prop_Send, "m_iHideHUD");
		if ((flags & HIDEHUD_MISCSTATUS) == 0)
			continue;

		flags &= ~HIDEHUD_MISCSTATUS;
		SetEntProp(client, Prop_Send, "m_iHideHUD", flags);
		g_LastWritten[client] = flags;
		g_Changed[client] = true;
	}

	if (!HasWaitingClients()) {
		g_CheckTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void OnPluginEnd() {
	StopCheckTimer();
	for (int client = 1; client <= MaxClients; client++) {
		if (!g_Waiting[client] || !g_Changed[client] || !IsClientInGame(client) || IsPlaying(client))
			continue;
		if (!HasEntProp(client, Prop_Send, "m_iHideHUD"))
			continue;

		// Restore only if the game has left our last written flags unchanged.
		int flags = GetEntProp(client, Prop_Send, "m_iHideHUD");
		if (flags == g_LastWritten[client])
			SetEntProp(client, Prop_Send, "m_iHideHUD", flags | HIDEHUD_MISCSTATUS);
	}
}
