#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_SECURITY		2
#define MAX_CONTROLPOINTS	20
#define INVALID_CP_INDEX	-1

static int		g_iOR = -1;
static int		g_iNumCP = 0;
static float	ga_fCPPos[MAX_CONTROLPOINTS][3];

static int		g_iMobileRef  = INVALID_ENT_REFERENCE;
static int		g_iPrevActive = INVALID_CP_INDEX;

static float	g_fOriginalPos[3];
static bool		g_bHaveOriginalPos;
static bool		g_bAllowedMap = false;

bool g_bLateLoad;

public Plugin myinfo =
{
	name		= "de_mirage_csco_pb4_fix",
	author		= "Nullifidian + ChatGPT",
	description	= "Move the Security spawn zone to the captured objective so Security players can buy equipment.",
	version		= "1.0.2"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent("round_start", 				Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_start_pre_entity",		Event_RoundStartPreEntity);
	HookEvent("controlpoint_captured",		Event_Obj, EventHookMode_PostNoCopy);
	HookEvent("object_destroyed",			Event_Obj, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
	char map[64];
	GetCurrentMap(map, sizeof map);
	g_bAllowedMap = StrEqual(map, "de_mirage_csco_pb4", false);
	if (!g_bAllowedMap) {
		CreateTimer(1.0, Timer_UnloadSelf, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	if (g_bLateLoad) {
		ResetState(true);
		CacheOR();
		BuildCPPositions();
	}

	FindSpawnZone();
}

public void OnMapEnd()
{
	ResetState(true);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bAllowedMap)
		return Plugin_Continue;

	ResetState(false);
	CacheOR();
	BuildCPPositions();
	FindSpawnZone();
	return Plugin_Continue;
}

public Action Event_RoundStartPreEntity(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bAllowedMap)
		return Plugin_Continue;

	TeleZoneToOriginalPos();
	return Plugin_Continue;
}

static void TeleZoneToOriginalPos()
{
	if (!g_bHaveOriginalPos)
		return;

	int ent = EntRefToEntIndex(g_iMobileRef);
	if (ent <= MaxClients || !IsValidEntity(ent))
		return;

	TeleportEntity(ent, g_fOriginalPos, NULL_VECTOR, NULL_VECTOR);
}

public Action Event_Obj(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bAllowedMap)
		return Plugin_Continue;

	if (!CacheOR() || !BuildCPPositions())
		return Plugin_Continue;

	int active = GetEntProp(g_iOR, Prop_Send, "m_nActivePushPointIndex");
	if (active < 0 || active >= g_iNumCP)
		active = g_iPrevActive;

	if (active >= 0 && active < g_iNumCP) {
		MoveMobileTo(ga_fCPPos[active]);
		g_iPrevActive = active;
	}

	return Plugin_Continue;
}

static void ResetState(bool hard)
{
	g_iMobileRef  = INVALID_ENT_REFERENCE;
	g_iPrevActive = INVALID_CP_INDEX;

	if (hard) {
		g_iOR = -1;
		g_iNumCP = 0;
		for (int i = 0; i < MAX_CONTROLPOINTS; i++)
			ga_fCPPos[i][0] = ga_fCPPos[i][1] = ga_fCPPos[i][2] = 0.0;

		g_bHaveOriginalPos = false;
		g_fOriginalPos[0] = g_fOriginalPos[1] = g_fOriginalPos[2] = 0.0;
	}
}

static bool CacheOR()
{
	if (g_iOR > MaxClients && IsValidEntity(g_iOR))
		return true;

	g_iOR = FindEntityByClassname(-1, "ins_objective_resource");
	return (g_iOR > MaxClients && IsValidEntity(g_iOR));
}

static bool BuildCPPositions()
{
	if (g_iOR <= MaxClients || !IsValidEntity(g_iOR))
		return false;

	int n = GetEntProp(g_iOR, Prop_Send, "m_iNumControlPoints");
	if (n < 0) n = 0;
	if (n > MAX_CONTROLPOINTS) n = MAX_CONTROLPOINTS;
	g_iNumCP = n;

	for (int i = 0; i < g_iNumCP; i++)
		GetEntPropVector(g_iOR, Prop_Send, "m_vCPPositions", ga_fCPPos[i], i);

	if (g_iPrevActive >= g_iNumCP)
		g_iPrevActive = INVALID_CP_INDEX;

	return (g_iNumCP > 0);
}

static void FindSpawnZone()
{
	g_iMobileRef = INVALID_ENT_REFERENCE;

	int ent = -1;
	int team;
	char name[64];

	while ((ent = FindEntityByClassname(ent, "ins_spawnzone")) != -1) {
		team = -1;
		if (HasEntProp(ent, Prop_Send, "m_iTeamNum"))			team = GetEntProp(ent, Prop_Send, "m_iTeamNum");
		else if (HasEntProp(ent, Prop_Data, "m_iTeamNum"))	team = GetEntProp(ent, Prop_Data, "m_iTeamNum");
		if (team != TEAM_SECURITY)
			continue;

		name[0] = '\0';
		if (HasEntProp(ent, Prop_Data, "m_iName"))			GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof name);
		else if (HasEntProp(ent, Prop_Send, "m_iName"))	GetEntPropString(ent, Prop_Send, "m_iName", name, sizeof name);

		if (strcmp(name, "spawnzone1") != 0)
			continue;

		GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_fOriginalPos);
		g_bHaveOriginalPos = true;

		g_iMobileRef = EntIndexToEntRef(ent);
		break;
	}
}

static void MoveMobileTo(const float where[3])
{
	int m = EntRefToEntIndex(g_iMobileRef);
	if (m <= MaxClients || !IsValidEntity(m)) {
		FindSpawnZone();
		m = EntRefToEntIndex(g_iMobileRef);
		if (m <= MaxClients || !IsValidEntity(m))
			return;
	}

	// Safety: keep it on Security, and temporarily disable while moving.
	if (HasEntProp(m, Prop_Send, "m_iTeamNum")) SetEntProp(m, Prop_Send, "m_iTeamNum", TEAM_SECURITY);
	if (HasEntProp(m, Prop_Data, "m_iTeamNum")) SetEntProp(m, Prop_Data, "m_iTeamNum", TEAM_SECURITY);

	AcceptEntityInput(m, "Disable");
	TeleportEntity(m, where, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(m, "Enable");
}

public Action Timer_UnloadSelf(Handle timer)
{
	ServerCommand("sm plugins unload disabled/de_mirage_csco_pb4_fix");
	return Plugin_Stop;
}

public void OnPluginEnd()
{
	TeleZoneToOriginalPos();
}
