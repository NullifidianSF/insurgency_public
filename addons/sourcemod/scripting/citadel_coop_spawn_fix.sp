// IMPORTANT!!! TO LOAD THIS PLUGIN ONLY ON THE citadel_coop MAP, FOLLOW THESE STEPS:
//
// 1. Place the compiled plugin into:
//    .../addons/sourcemod/plugins/disabled/citadel_coop_spawn_fix.smx
//
// 2. Create a config file named `server_citadel_coop.cfg` in the same directory as `server.cfg`.
//
// 3. Add the following line to `server_citadel_coop.cfg`:
//    sm plugins load disabled/citadel_coop_spawn_fix.smx
//
// This setup ensures the plugin is automatically loaded only when the map is `citadel_coop`.
//
// The plugin disables incorrectly placed security spawn points on the citadel_coop map.
// The mapper forgot to place an `ins_spawnzone` in a specific area, which causes players
// to spawn too close to bots or too far from the action.

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_SECURITY 2
#define BAD_SPAWN_COUNT 16

static bool g_bAllowedMap = false;
static const float g_fBadSpawns[BAD_SPAWN_COUNT][3] =
{
	{552.0, 2144.0, -670.672973},
	{524.0, 2144.0, -670.672973},
	{544.0, 2228.0, -670.672973},
	{508.0, 2228.0, -670.672973},
	{476.0, 2224.0, -670.672973},
	{480.0, 2144.0, -670.672973},
	{440.0, 2140.0, -670.672973},
	{440.0, 2224.0, -670.672973},
	{408.0, 2140.0, -670.672973},
	{380.0, 2140.0, -670.672973},
	{400.0, 2224.0, -670.672973},
	{364.0, 2224.0, -670.672973},
	{332.0, 2220.0, -670.672973},
	{336.0, 2140.0, -670.672973},
	{296.0, 2136.0, -670.672973},
	{296.0, 2220.0, -670.672973}
};

public Plugin myinfo = {
	name = "citadel_coop_spawn_fix",
	author = "Nullifidian and GPT",
	description = "Disables improperly placed security spawns on citadel_coop.",
	version = "1.3"
};

public void OnPluginStart() {
	HookEvent("round_start", Event_RoundStart_Pre, EventHookMode_Pre);
}

public void OnMapStart() {
	char sMapName[64];
	GetCurrentMap(sMapName, sizeof(sMapName));
	g_bAllowedMap = strcmp(sMapName, "citadel_coop", false) == 0;
	if (!g_bAllowedMap) {
		CreateTimer(1.0, Timer_UnloadSelf, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_UnloadSelf(Handle timer) {
	ServerCommand("sm plugins unload disabled/citadel_coop_spawn_fix");
	return Plugin_Stop;
}

public Action Event_RoundStart_Pre(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bAllowedMap)
		return Plugin_Continue;

	DisableBadSecSpawns();
	return Plugin_Continue;
}

void DisableBadSecSpawns() {
	int ent = -1;
	float vOrigin[3];

	while ((ent = FindEntityByClassname(ent, "ins_spawnpoint")) != -1) {
		// Only check active security team spawnpoints
		if (GetEntProp(ent, Prop_Data, "m_iTeamNum") != TEAM_SECURITY) {
			continue;
		}

		if (GetEntProp(ent, Prop_Data, "m_iDisabled") == 1) {
			continue;
		}

		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", vOrigin);
		for (int i = 0; i < BAD_SPAWN_COUNT; i++) {
			if (vOrigin[0] == g_fBadSpawns[i][0]
			 && vOrigin[1] == g_fBadSpawns[i][1]
			 && vOrigin[2] == g_fBadSpawns[i][2]) {
				AcceptEntityInput(ent, "Disable");
				break;
			}
		}
	}
}
