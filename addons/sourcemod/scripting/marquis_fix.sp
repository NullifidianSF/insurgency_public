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
#define PILLAR_FIX_COUNT 12

static bool g_bAllowedMap = false;
static int g_iFixPropRefs[PILLAR_FIX_COUNT] = {INVALID_ENT_REFERENCE, ...};

static const float g_fFixPos[PILLAR_FIX_COUNT][3] =
{
	{1864.787475, -1895.421264, -532.979675},
	{1632.064331, -1895.469238, -511.531677},
	{1630.227539, -2532.191894, -511.565612},
	{1863.292968, -2530.488769, -511.533416},
	{1862.405761, -3169.086181, -511.199005},
	{1630.651733, -3171.158691, -513.229003},
	{1632.238281, -1895.667724, -373.768676},
	{1864.429077, -1895.548217, -373.960235},
	{1862.816894, -2532.062988, -376.438415},
	{1630.847778, -2532.614501, -374.677093},
	{1862.753784, -3170.952880, -375.584991},
	{1630.522094, -3170.762939, -376.307800}
};

static const float g_fFixAng[PILLAR_FIX_COUNT][3] =
{
	{0.0, 90.0, 0.0},
	{0.0, 90.0, 0.0},
	{0.0, 90.0, 0.0},
	{0.0, 90.0, 0.0},
	{0.0, 90.0, 0.0},
	{0.0, 90.0, 0.0},
	{0.0, 0.0, 0.0},
	{0.0, 0.0, 0.0},
	{0.0, 0.0, 0.0},
	{0.0, 0.0, 0.0},
	{0.0, 0.0, 0.0},
	{0.0, 0.0, 0.0}
};

static const char g_sFixModel[PILLAR_FIX_COUNT][] =
{
	"models/props_paris/metro_pillarplug_01.mdl",
	"models/props_paris/metro_pillarplug_01.mdl",
	"models/props_paris/metro_pillarplug_01.mdl",
	"models/props_paris/metro_pillarplug_01.mdl",
	"models/props_paris/metro_pillarplug_01.mdl",
	"models/props_paris/metro_pillarplug_01.mdl",
	"models/props_paris/metro_pillar_01.mdl",
	"models/props_paris/metro_pillar_01.mdl",
	"models/props_paris/metro_pillar_01.mdl",
	"models/props_paris/metro_pillar_01.mdl",
	"models/props_paris/metro_pillar_01.mdl",
	"models/props_paris/metro_pillar_01.mdl"
};

public Plugin myinfo = {
	name = "marquis_fix",
	author = "Nullifidian and GPT",
	description = "Spawns invisible solid pillars within non-solid pillars.",
	version = "1.4"
};

public void OnPluginStart() {
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void OnMapStart() {
	char sMapName[64];
	GetCurrentMap(sMapName, sizeof(sMapName));
	g_bAllowedMap = strcmp(sMapName, "marquis", false) == 0;

	for (int i = 0; i < PILLAR_FIX_COUNT; i++)
		g_iFixPropRefs[i] = INVALID_ENT_REFERENCE;

	if (!g_bAllowedMap) {
		CreateTimer(1.0, Timer_UnloadSelf, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	PrecacheModel("models/props_paris/metro_pillarplug_01.mdl", true);
	PrecacheModel("models/props_paris/metro_pillar_01.mdl", true);
}

public Action Timer_UnloadSelf(Handle timer) {
	ServerCommand("sm plugins unload disabled/marquis_fix");
	return Plugin_Stop;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bAllowedMap)
		return Plugin_Continue;

	RemoveAllFixProps();
	for (int i = 0; i < PILLAR_FIX_COUNT; i++)
		CreateProp(i);

	return Plugin_Continue;
}

static void RemoveAllFixProps()
{
	for (int i = 0; i < PILLAR_FIX_COUNT; i++)
	{
		int ent = EntRefToEntIndex(g_iFixPropRefs[i]);
		g_iFixPropRefs[i] = INVALID_ENT_REFERENCE;
		if (ent > MaxClients && IsValidEntity(ent))
		{
			if (!AcceptEntityInput(ent, "Kill"))
				RemoveEntity(ent);
		}
	}
}

void CreateProp(int index) {
	int prop = CreateEntityByName("prop_dynamic_override");
	if (prop != -1) {
		DispatchKeyValue(prop, "physdamagescale", "0.0");
		DispatchKeyValue(prop, "model", g_sFixModel[index]);
		DispatchKeyValue(prop, "solid", "6");
		TeleportEntity(prop, g_fFixPos[index], g_fFixAng[index], NULL_VECTOR);
		DispatchKeyValue(prop, "disableshadows", "1");
		DispatchKeyValue(prop, "disableshadowdepth", "1");
		SetEntityRenderMode(prop, RENDER_NONE);

		if (!DispatchSpawn(prop))
		{
			if (!AcceptEntityInput(prop, "Kill"))
				RemoveEntity(prop);
			return;
		}
		SetEntityMoveType(prop, MOVETYPE_NONE);
		SetEntProp(prop, Prop_Data, "m_takedamage", DAMAGE_NO);
		g_iFixPropRefs[index] = EntIndexToEntRef(prop);
	}
}

public void OnPluginEnd()
{
	RemoveAllFixProps();
}
