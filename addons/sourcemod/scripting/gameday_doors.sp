#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = {
	name		= "gameday_doors",
	author		= "Nullifidian",
	description	= "Open all locked doors/shutters in 'game_day_coop_ws' map",
	version		= "1.0",
	url			= ""
};

public void OnPluginStart() {
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void OnMapStart() {
	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	if (!StrEqual(sMap, "game_day_coop_ws")) {
		ServerCommand("sm plugins unload disabled/gameday_doors");
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	OpenDoors();
}

void OpenDoors() {
	int iEnt = INVALID_ENT_REFERENCE;
	while ((iEnt = FindEntityByClassname(iEnt, "func_door")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(iEnt, "Open");
	}
}