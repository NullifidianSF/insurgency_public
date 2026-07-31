#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define INS_SPECIAL1 (1 << 17)
#define PF_DEPLOY_BIPOD (1 << 1)
#define STANCE_PRONE 2
#define UPGRADE_SLOT_SCOPE 0
#define UPGRADE_SLOT_UNDERBARREL 6
#define UPGRADE_BIPOD 211
#define UPGRADE_GRIPPOD 212

static const float SCOPE_SCAN_INTERVAL = 0.50;
static const float MAX_WALL_DISTANCE = 38.0;
static const float MAX_WALL_NORMAL_Z = 0.70;

static const char g_sIntegratedBipodWeapons[][] = {
	"rpk",
	"m240",
	"m249",
	"m60",
	"mg42",
	"mk46",
	"pecheneg",
	"KACStonerA1"
};

float ga_fPlayerNextScopeScanAt[MAXPLAYERS + 1] = {0.0, ...};

public Plugin myinfo = {
	name        = "scopeglitch",
	author      = "Nullifidian",
	description = "Prevents scoped bipod wall-clipping exploits by automatically retracting deployed bipods near obstructions.",
	version     = "1.1.0",
	url         = "https://steamcommunity.com/id/Nullifidian/"
};

// Simple, self-contained validity check (no external include needed)
static bool IsHumanAlive(int client)
{
	return (1 <= client <= MaxClients)
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& IsPlayerAlive(client);
}

public void OnMapStart()
{
	for (int client = 1; client <= MaxClients; client++) {
		ga_fPlayerNextScopeScanAt[client] = 0.0;
	}
}

public void OnClientPostAdminCheck(int client)
{
	ga_fPlayerNextScopeScanAt[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
	ga_fPlayerNextScopeScanAt[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsHumanAlive(client)) {
		return Plugin_Continue;
	}

	if (GetEntProp(client, Prop_Send, "m_iCurrentStance") != STANCE_PRONE) {
		return Plugin_Continue;
	}

	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon <= MaxClients || !IsValidEntity(iWeapon)) {
		return Plugin_Continue;
	}

	if (!WeaponHasScopedBipod(iWeapon)) {
		return Plugin_Continue;
	}

	int iPlayerFlags = GetEntProp(client, Prop_Send, "m_iPlayerFlags");
	if ((iPlayerFlags & PF_DEPLOY_BIPOD) == 0) {
		return Plugin_Continue;
	}

	float now = GetGameTime();
	if (now < ga_fPlayerNextScopeScanAt[client]) {
		return Plugin_Continue;
	}
	ga_fPlayerNextScopeScanAt[client] = now + SCOPE_SCAN_INTERVAL;

	if (!IsWallTooClose(client, angles) || (buttons & INS_SPECIAL1) != 0) {
		return Plugin_Continue;
	}

	buttons |= INS_SPECIAL1;
	return Plugin_Changed;
}

static bool WeaponHasScopedBipod(int weapon)
{
	if (!HasEntProp(weapon, Prop_Send, "m_upgradeSlots")) {
		return false;
	}

	int iUpgradeSlotCount = GetEntPropArraySize(weapon, Prop_Send, "m_upgradeSlots");
	if (iUpgradeSlotCount <= UPGRADE_SLOT_SCOPE) {
		return false;
	}

	// Slot 0 contains the optic upgrade; -1 means iron sights.
	if (GetEntProp(weapon, Prop_Send, "m_upgradeSlots", 4, UPGRADE_SLOT_SCOPE) == -1) {
		return false;
	}

	char sWeapon[64];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));

	for (int i = 0; i < sizeof(g_sIntegratedBipodWeapons); i++) {
		if (StrContains(sWeapon, g_sIntegratedBipodWeapons[i], false) != -1) {
			return true;
		}
	}

	if (iUpgradeSlotCount <= UPGRADE_SLOT_UNDERBARREL) {
		return false;
	}

	int iUnderbarrel = GetEntProp(weapon, Prop_Send, "m_upgradeSlots", 4, UPGRADE_SLOT_UNDERBARREL);
	return iUnderbarrel == UPGRADE_BIPOD || iUnderbarrel == UPGRADE_GRIPPOD;
}

static bool IsWallTooClose(int client, const float angles[3])
{
	float origin[3];
	float direction[3];
	float end[3];
	GetClientEyePosition(client, origin);

	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(direction, MAX_WALL_DISTANCE);
	AddVectors(origin, direction, end);

	TR_TraceRayFilter(origin, end, MASK_PLAYERSOLID, RayType_EndPoint, Point_Trace_Filter, client);

	if (!TR_DidHit()) {
		return false;
	}

	// Ignore floors and ceilings so looking sharply up or down does not retract the bipod.
	float normal[3];
	TR_GetPlaneNormal(INVALID_HANDLE, normal);
	return FloatAbs(normal[2]) < MAX_WALL_NORMAL_Z;
}

static bool Point_Trace_Filter(int entity, int mask, any data)
{
	// Skip self and other players.
	return entity != data && (entity < 1 || entity > MaxClients);
}
