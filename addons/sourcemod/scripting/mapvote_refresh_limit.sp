#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo = {
	name = "mapvote_refresh_limit",
	author = "Nullifidian",
	description = "Limit how many times a player can vote for map refresh",
	version = "1.6"
};

int		iRefreshCount[MAXPLAYERS + 1],
		iPlayerCount = 0,
		iVoteSerial = 0;

int		iLastRefreshVote[MAXPLAYERS + 1] = {-1, ...};

ConVar	cvMaxRefreshAllowed,
		cvMinPlayers,
		cvDebug;

UserMsg g_umMapVoteEnd,
		g_umMapVoteStart;

float	fCooldown[MAXPLAYERS + 1] = {-1.0, ...};

public void OnPluginStart() {
	cvMaxRefreshAllowed = CreateConVar("sm_refreshlimit", "2.0", "Maximum times player can vote for map refresh.", _, true, 0.0, false);
	cvMinPlayers = CreateConVar("sm_refreshminplayers", "2.0", "Disable refresh limit if only X or less number of players in game.", _, true, 0.0, false);
	cvDebug = CreateConVar("sm_refreshlimit_debug", "0", "Log native map-vote results. 0 = disabled, 1 = enabled.", _, true, 0.0, true, 1.0);

	HookEvent("game_end", Event_GameEnd, EventHookMode_PostNoCopy);
	AddCommandListener(MapvoteListener, "mapvote");

	g_umMapVoteEnd = GetUserMessageId("MapVoteEnd");
	if (g_umMapVoteEnd != INVALID_MESSAGE_ID)
		HookUserMessage(g_umMapVoteEnd, UserMsg_MapVoteEnd);
	else
		LogError("[Map Refresh Limit] Could not find the MapVoteEnd user message. Native refresh-result debug is unavailable.");

	g_umMapVoteStart = GetUserMessageId("MapVoteStart");
	if (g_umMapVoteStart != INVALID_MESSAGE_ID)
		HookUserMessage(g_umMapVoteStart, UserMsg_MapVoteStart);
	else
		LogError("[Map Refresh Limit] Could not find the MapVoteStart user message. Per-vote refresh tracking is unavailable.");

	AutoExecConfig(true, "mapvote_refresh_limit");
}

public void OnClientPostAdminCheck(int client) {
	if (client < 1 || client > MaxClients)
		return;
	iRefreshCount[client] = 0;
	fCooldown[client] = -1.0;
	iLastRefreshVote[client] = -1;
}

public Action MapvoteListener(int client, const char[] cmd, int argc) {
/*
	# > -1 = map
	-1 = replay
	-2 = random
	-3 = refresh
*/
	if (iPlayerCount <= cvMinPlayers.IntValue) {
		return Plugin_Continue;
	}
	if (argc < 1)
		return Plugin_Continue;

	char option[3];
	GetCmdArg(1, option, sizeof(option));
	bool selectingRefresh = StrEqual(option, "-3", false);
	bool hadSelectedRefresh = iLastRefreshVote[client] == iVoteSerial;

	if (!selectingRefresh) {
		if (!hadSelectedRefresh)
			return Plugin_Continue;

		iRefreshCount[client]--;
		iLastRefreshVote[client] = -1;
		fCooldown[client] = -1.0;
		if (cvDebug.BoolValue)
			LogMessage("[Map Refresh Limit] %N changed away from refresh for vote %i. Allowance returned.", client, iVoteSerial);
		return Plugin_Continue;
	}

	if (hadSelectedRefresh)
		return Plugin_Continue;

	float Time = GetEngineTime();
	if (fCooldown[client] != -1.0 && fCooldown[client] > Time)
		return Plugin_Handled;
	
	fCooldown[client] = Time + 2.0;
	if (iRefreshCount[client] >= cvMaxRefreshAllowed.IntValue) {
		PrintToChat(client,"\x07e32d2d You are not allowed to vote for refresh more than %i time%s.", cvMaxRefreshAllowed.IntValue, cvMaxRefreshAllowed.IntValue > 1 ? "s" : "");
		return Plugin_Handled;
	}

	iRefreshCount[client]++;
	iLastRefreshVote[client] = iVoteSerial;
	return Plugin_Continue;
}

public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	iPlayerCount = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			iPlayerCount++;
		}
	}
}

public Action UserMsg_MapVoteStart(UserMsg msgId, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	iVoteSerial++;
	if (cvDebug.BoolValue)
		LogMessage("[Map Refresh Limit] Native MapVoteStart detected: vote %i.", iVoteSerial);

	return Plugin_Continue;
}

public Action UserMsg_MapVoteEnd(UserMsg msgId, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	int result = msg.ReadShort();
	if (!cvDebug.BoolValue)
		return Plugin_Continue;

	if (result == -3)
		LogMessage("[Map Refresh Limit] Native MapVoteEnd result: -3 (refresh won, selection is being refreshed).");
	else
		LogMessage("[Map Refresh Limit] Native MapVoteEnd result: %i.", result);

	return Plugin_Continue;
}
