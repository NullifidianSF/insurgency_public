#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_NAME		"bot_grenade"
#define PLUGIN_AUTHOR	"Nullifidian"
#define PLUGIN_DESC		"Make bots less accurate with grenades by scaling projectile velocity"
#define PLUGIN_VERSION	"1.8"

ConVar g_cMin;
ConVar g_cMax;
ConVar g_cFilter;
ConVar g_cDebug;

float g_fMin = 0.70;
float g_fMax = 1.30;
char  g_sFilter[32];
bool  g_bDebug = false;

public Plugin myinfo = {
	name		= PLUGIN_NAME,
	author		= PLUGIN_AUTHOR,
	description	= PLUGIN_DESC,
	version		= PLUGIN_VERSION,
	url			= ""
};

public void OnPluginStart() {
	g_cMin = CreateConVar(
		"sm_botgrenade_min",
		"0.70",
		"Min RNG value for grenade velocity multiplier (0.05 .. 3.00).",
		FCVAR_NOTIFY,
		true, 0.05,
		true, 3.00
	);

	g_cMax = CreateConVar(
		"sm_botgrenade_max",
		"1.30",
		"Max RNG value for grenade velocity multiplier (0.05 .. 4.00).",
		FCVAR_NOTIFY,
		true, 0.05,
		true, 4.00
	);

	g_cFilter = CreateConVar(
		"sm_botgrenade_filter",
		"grenade",
		"Substring that the projectile classname must contain to be affected (empty = any).",
		FCVAR_NONE
	);

	g_cDebug = CreateConVar(
		"sm_botgrenade_debug",
		"0",
		"Enable debug logging (0/1).",
		FCVAR_NONE,
		true, 0.0,
		true, 1.0
	);

	g_cMin.AddChangeHook(OnConVarChanged);
	g_cMax.AddChangeHook(OnConVarChanged);
	g_cFilter.AddChangeHook(OnConVarChanged);
	g_cDebug.AddChangeHook(OnConVarChanged);

	HookEvent("grenade_thrown", Event_GrenadeThrown, EventHookMode_Post);
	AutoExecConfig(true, PLUGIN_NAME);
	CacheCvars();
}

public void OnConfigsExecuted() { CacheCvars(); }

public void CacheCvars() {
	g_fMin = g_cMin.FloatValue;
	g_fMax = g_cMax.FloatValue;

	if (g_fMin > g_fMax) {
		float t = g_fMin;
		g_fMin = g_fMax;
		g_fMax = t;
	}

	g_cFilter.GetString(g_sFilter, sizeof g_sFilter);
	g_bDebug = (g_cDebug.IntValue != 0);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) { CacheCvars(); }

public Action Event_GrenadeThrown(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int ent = event.GetInt("entityid");

	if (ent < 1 || client < 1 || !IsClientInGame(client) || !IsFakeClient(client))
		return Plugin_Continue;

	if (g_sFilter[0] != '\0') {
		char cls[64];
		if (!GetEntityClassname(ent, cls, sizeof cls))
			return Plugin_Continue;

		if (StrContains(cls, g_sFilter, false) == -1)
			return Plugin_Continue;
	}

	RequestFrame(Frame_SetGrenadeVel, EntIndexToEntRef(ent));
	return Plugin_Continue;
}

void Frame_SetGrenadeVel(int entRef) {
	int ent = EntRefToEntIndex(entRef);
	if (ent <= 0 || !IsValidEntity(ent))
		return;

	float vel[3];
	if (!GetEntPropVector(ent, Prop_Data, "m_vecVelocity", vel))
		return;

	float mult = GetRandomFloat(g_fMin, g_fMax);

	if (g_bDebug) {
		float speed = SquareRoot(vel[0]*vel[0] + vel[1]*vel[1] + vel[2]*vel[2]);
		LogMessage("[bot_grenade] ent %d pre-speed=%.1f mult=%.3f", ent, speed, mult);
	}

	vel[0] *= mult;
	vel[1] *= mult;
	vel[2] *= mult;

	TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, vel);

	if (g_bDebug) {
		float speed2 = SquareRoot(vel[0]*vel[0] + vel[1]*vel[1] + vel[2]*vel[2]);
		LogMessage("[bot_grenade] ent %d post-speed=%.1f", ent, speed2);
	}
}