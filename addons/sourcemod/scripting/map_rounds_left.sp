#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <insurgencydy>
#include <SteamWorks>

public Plugin myinfo = {
	name		= "map_rounds_left",
	author		= "Nullifidian",
	description	= "Prints how many rounds & objectives left",
	version		= "1.1.2",
	url			= "https://steamcommunity.com/id/Nullifidian/"
};

int		g_iMaxRounds,
		g_iRoundNow,
		g_iMaxObj,
		g_iActiveObj,
		g_iTimerObjRound;
		
Handle	ga_hTimer[MAXPLAYERS+1];

char	g_sMapTag[64],
		g_sMapName[64];

public void OnPluginStart() {
	RegConsoleCmd("round", Cmd_Rounds_Left, "Prints how many rounds & objectives left");
	RegConsoleCmd("objective", Cmd_Rounds_Left, "Prints how many rounds & objectives left");
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("object_destroyed", ObjEvents_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", ObjEvents_NoCopy, EventHookMode_PostNoCopy);
	HookConVarChange(FindConVar("mp_maxrounds"), ConVarChanged);
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

public void Event_RoundStart(Event event, char[] name, bool dontBroadcast) {
	CreateTimer(0.1, Timer_RoundStart);
	g_iRoundNow = GameRules_GetProp("m_iRoundPlayedCount") + 1;
	g_iTimerObjRound = -1;
}

public void Event_RoundEnd(Event event, char[] name, bool dontBroadcast) {
	if (g_iRoundNow == g_iMaxRounds) {
		FormatEx(g_sMapTag, sizeof(g_sMapTag), "%s MapEnd", g_sMapName);
	}
	g_iTimerObjRound = -1;
}

public void ObjEvents_NoCopy(Event event, char[] name, bool dontBroadcast) {
	g_iTimerObjRound = g_iRoundNow;
	CreateTimer(1.0, TimerR_MonitorCA, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client) {
	if (!IsFakeClient(client)) {
		ga_hTimer[client] = CreateTimer(60.0, Timer_NewPlayer, client);
	}
}

public void OnClientDisconnect(int client) {
	delete ga_hTimer[client];
}

public Action Cmd_Rounds_Left(int client, int args) {
	PrintToChat(client,
	"\x070088cc[BM]\x01 Round: \x070088cc%d\x01/\x070088cc%d\x01 | Objective: \x070088cc%s\x01/\x070088cc%s",
	g_iRoundNow, g_iMaxRounds, ConvertNumberToLetter(g_iActiveObj), ConvertNumberToLetter(g_iMaxObj));
	return Plugin_Handled;
}

void ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_iMaxRounds = StringToInt(newValue);
}

Action Timer_RoundStart(Handle timer) {
	g_iActiveObj = 1;
	if (g_iMaxObj < 1) {
		g_iMaxObj = Ins_ObjectiveResource_GetProp("m_iNumControlPoints");
	}
	UpdateMapTag();
	return Plugin_Stop;
}

Action TimerR_MonitorCA(Handle timer) {
	if (g_iTimerObjRound != g_iRoundNow) {
		KillTimer(timer);
	}
	else if (!Ins_InCounterAttack()) {
		if (g_iMaxObj > g_iActiveObj || g_iMaxObj == 0) {
			g_iActiveObj++;
		}
		UpdateMapTag();
		KillTimer(timer);
	}
	return Plugin_Continue;
}

Action Timer_NewPlayer(Handle timer, int client) {
	PrintToChat(client,
	"\x070088cc[BM]\x01 Round: \x070088cc%d\x01/\x070088cc%d\x01 | Objective: \x070088cc%s\x01/\x070088cc%s\n[BM]\x01 Use !round command in chat to see this info",
	g_iRoundNow, g_iMaxRounds, ConvertNumberToLetter(g_iActiveObj), ConvertNumberToLetter(g_iMaxObj));
	ga_hTimer[client] = null;
	return Plugin_Stop;
}

char[] ConvertNumberToLetter(int number) {
	char letter[4] = "n/a";
	switch (number) {
		case 1: letter = "A";
		case 2: letter = "B";
		case 3: letter = "C";
		case 4: letter = "D";
		case 5: letter = "E";
		case 6: letter = "F";
		case 7: letter = "G";
		case 8: letter = "H";
		case 9: letter = "I";
		case 10: letter = "J";
		case 11: letter = "K";
		case 12: letter = "L";
		case 13: letter = "M";
		case 14: letter = "N";
		case 15: letter = "O";
		case 16: letter = "P";
	}
	return letter;
}

void UpdateMapTag() {
	FormatEx(g_sMapTag, sizeof(g_sMapTag), "%s %d/%d %s/%s", g_sMapName, g_iRoundNow, g_iMaxRounds, ConvertNumberToLetter(g_iActiveObj), ConvertNumberToLetter(g_iMaxObj));
}

Action TimerR_AddTag(Handle timer) {
	if (strlen(g_sMapTag) > 1) {
		SteamWorks_SetMapName(g_sMapTag);
	}
	return Plugin_Continue;
}