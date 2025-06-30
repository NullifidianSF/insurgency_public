// IMPORTANT!!! TO LOAD THIS PLUGIN ONLY ON THE marquis MAP, FOLLOW THESE STEPS:
//
// 1. Place the compiled plugin into:
//    .../addons/sourcemod/plugins/disabled/marquis_fix.smx
//
// 2. Create a config file named `server_marquis.cfg` in the same directory as `server.cfg`.
//
// 3. Add the following line to `server_marquis.cfg`:
//    sm plugins load disabled/marquis_fix.smx
//
// This setup ensures the plugin is automatically loaded only when the map is `marquis`.

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>


#define DAMAGE_NO 0
#define DAMAGE_EVENTS_ONLY 1
#define DAMAGE_YES 2
#define DAMAGE_AIM 3

public Plugin myinfo = {
	name = "marquis_fix",
	author = "Nullifidian",
	description = "Spawns invisible solid pillars within non-solid pillars.",
	version = "1.0"
};

public void OnPluginStart() {
	HookEvent("round_start", Event_RoundStart);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	CreateProp({1864.787475, -1895.421264, -532.979675}, {0.000000, 90.000000, 0.000000}, "models/props_paris/metro_pillarplug_01.mdl");
	CreateProp({1632.064331, -1895.469238, -511.531677}, {0.000000, 90.000000, 0.000000}, "models/props_paris/metro_pillarplug_01.mdl");
	CreateProp({1630.227539, -2532.191894, -511.565612}, {0.000000, 90.000000, 0.000000}, "models/props_paris/metro_pillarplug_01.mdl");
	CreateProp({1863.292968, -2530.488769, -511.533416}, {0.000000, 90.000000, 0.000000}, "models/props_paris/metro_pillarplug_01.mdl");
	CreateProp({1862.405761, -3169.086181, -511.199005}, {0.000000, 90.000000, 0.000000}, "models/props_paris/metro_pillarplug_01.mdl");
	CreateProp({1630.651733, -3171.158691, -513.229003}, {0.000000, 90.000000, 0.000000}, "models/props_paris/metro_pillarplug_01.mdl");

	CreateProp({1632.238281, -1895.667724, -373.768676}, {0.000000, 0.000000, 0.000000}, "models/props_paris/metro_pillar_01.mdl");
	CreateProp({1864.429077, -1895.548217, -373.960235}, {0.000000, 0.000000, 0.000000}, "models/props_paris/metro_pillar_01.mdl");
	CreateProp({1862.816894, -2532.062988, -376.438415}, {0.000000, 0.000000, 0.000000}, "models/props_paris/metro_pillar_01.mdl");
	CreateProp({1630.847778, -2532.614501, -374.677093}, {0.000000, 0.000000, 0.000000}, "models/props_paris/metro_pillar_01.mdl");
	CreateProp({1862.753784, -3170.952880, -375.584991}, {0.000000, 0.000000, 0.000000}, "models/props_paris/metro_pillar_01.mdl");
	CreateProp({1630.522094, -3170.762939, -376.307800}, {0.000000, 0.000000, 0.000000}, "models/props_paris/metro_pillar_01.mdl");
	return Plugin_Continue;
}

void CreateProp(float vPos[3], float vAng[3], char[] sModel) {
	int prop = CreateEntityByName("prop_dynamic_override");
	if (prop != -1) {
		DispatchKeyValue(prop, "physdamagescale", "0.0");
		DispatchKeyValue(prop, "model", sModel);
		DispatchKeyValue(prop, "solid", "6");
		TeleportEntity(prop, vPos, vAng, NULL_VECTOR);
		DispatchKeyValue(prop, "disableshadows", "1");
		DispatchKeyValue(prop, "disableshadowdepth", "1");
		SetEntityRenderMode(prop, RENDER_TRANSCOLOR);
		SetEntityRenderColor(prop, 255, 255, 255, 0);

		DispatchSpawn(prop);
		SetEntityMoveType(prop, MOVETYPE_NONE);
		SetEntProp(prop, Prop_Data, "m_takedamage", DAMAGE_NO);
	}
}