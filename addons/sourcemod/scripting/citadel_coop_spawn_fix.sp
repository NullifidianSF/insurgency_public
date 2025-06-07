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

public Plugin myinfo = {
	name = "citadel_coop_spawn_fix",
	author = "Nullifidian",
	description = "Disables improperly placed security spawns on citadel_coop.",
	version = "1.0"
};

public void OnPluginStart() {
	HookEvent("round_start", Event_RoundStart_Pre, EventHookMode_Pre);
}

public Action Event_RoundStart_Pre(Event event, const char[] name, bool dontBroadcast) {
	DisableBadSecSpawns();
	return Plugin_Continue;
}

void DisableBadSecSpawns() {
	int ent = MaxClients + 1;
	float vOrigin[3];

	// List of bad spawnpoint locations to disable
	char sBadSpawns[][] = {
		"552.000000 2144.000000 -670.672973",
		"524.000000 2144.000000 -670.672973",
		"544.000000 2228.000000 -670.672973",
		"508.000000 2228.000000 -670.672973",
		"476.000000 2224.000000 -670.672973",
		"480.000000 2144.000000 -670.672973",
		"440.000000 2140.000000 -670.672973",
		"440.000000 2224.000000 -670.672973",
		"408.000000 2140.000000 -670.672973",
		"380.000000 2140.000000 -670.672973",
		"400.000000 2224.000000 -670.672973",
		"364.000000 2224.000000 -670.672973",
		"332.000000 2220.000000 -670.672973",
		"336.000000 2140.000000 -670.672973",
		"296.000000 2136.000000 -670.672973",
		"296.000000 2220.000000 -670.672973"
	};

	char sBuffer[64];

	while ((ent = FindEntityByClassname(ent, "ins_spawnpoint")) != -1) {
		// Only check active security team spawnpoints
		if (GetEntProp(ent, Prop_Data, "m_iTeamNum") != 2) {
			continue;
		}

		if (GetEntProp(ent, Prop_Data, "m_iDisabled") == 1) {
			continue;
		}

		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", vOrigin);
		FormatEx(sBuffer, sizeof(sBuffer), "%f %f %f", vOrigin[0], vOrigin[1], vOrigin[2]);

		for (int i = 0; i < sizeof(sBadSpawns); i++) {
			if (strcmp(sBadSpawns[i], sBuffer, false) == 0) {
				AcceptEntityInput(ent, "Disable");
				break;
			}
		}
	}
}