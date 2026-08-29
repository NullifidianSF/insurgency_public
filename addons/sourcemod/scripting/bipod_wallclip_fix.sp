#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PF_DEPLOY_BIPOD (1 << 1)
#define STANCE_PRONE 2
#define BIPOD_CAPABILITY 1
#define GAMEDATA_FILE "insurgency-bm.games"

static const float BIPOD_SCAN_INTERVAL = 1.0;
static const float MAX_WALL_DISTANCE = 38.0;
static const float MAX_WALL_NORMAL_Z = 0.70;

int ga_iBipodWeaponRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
bool ga_bWeaponSupportsBipod[MAXPLAYERS + 1] = {false, ...};

GameData g_hGameData = null;
Handle g_hSupportsBipod = null;
Handle g_hSetBipodState = null;
Handle g_hBipodScanTimer = null;

public Plugin myinfo = {
	name        = "bipod_wallclip_fix",
	author      = "Nullifidian",
	description = "Prevents bipod wall-clipping exploits by automatically retracting deployed bipods near obstructions.",
	version     = "1.0.3",
	url         = "https://steamcommunity.com/id/Nullifidian/"
};

static bool IsHumanAlive(int client) {
	return (1 <= client <= MaxClients)
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& IsPlayerAlive(client);
}

public void OnPluginStart() {
	g_hGameData = LoadGameConfigFile(GAMEDATA_FILE);
	if (g_hGameData == null)
		SetFailState("[bipod_wallclip_fix] Missing gamedata: addons/sourcemod/gamedata/%s.txt", GAMEDATA_FILE);

	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(g_hGameData, SDKConf_Virtual, "CINSWeapon::SupportsBipod")
		|| !PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain)
		|| !PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain))
		SetFailState("[bipod_wallclip_fix] Missing CINSWeapon bipod capability offset in %s.txt", GAMEDATA_FILE);

	g_hSupportsBipod = EndPrepSDKCall();
	if (g_hSupportsBipod == null)
		SetFailState("[bipod_wallclip_fix] Could not create CINSWeapon bipod capability SDKCall.");

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(g_hGameData, SDKConf_Signature, "CINSPlayer::SetBipodState")
		|| !PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain))
		SetFailState("[bipod_wallclip_fix] Missing CINSPlayer::SetBipodState signature in %s.txt", GAMEDATA_FILE);

	g_hSetBipodState = EndPrepSDKCall();
	if (g_hSetBipodState == null)
		SetFailState("[bipod_wallclip_fix] Could not create CINSPlayer::SetBipodState SDKCall.");

	g_hBipodScanTimer = CreateTimer(BIPOD_SCAN_INTERVAL, Timer_BipodScan, _, TIMER_REPEAT);
	HookEvent("weapon_deploy", Event_WeaponDeploy, EventHookMode_Post);
	RequestFrame(Frame_InitialiseExistingClients);
}

public void OnMapStart() {
	for (int client = 1; client <= MaxClients; client++)
		ResetClientState(client);
}

public void OnClientPostAdminCheck(int client) {
	ResetClientState(client);
}

public void OnClientDisconnect(int client) {
	ResetClientState(client);
}

public void OnPluginEnd() {
	delete g_hBipodScanTimer;
	delete g_hSetBipodState;
	delete g_hSupportsBipod;
	delete g_hGameData;
}

public void Event_WeaponDeploy(Event event, const char[] name, bool dontBroadcast) {
	RequestFrame(Frame_CacheDeployedWeapon, event.GetInt("userid"));
}

void Frame_InitialiseExistingClients(any data) {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsHumanAlive(client))
			CacheWeaponBipodCapability(client);
	}
}

void Frame_CacheDeployedWeapon(any data) {
	int client = GetClientOfUserId(data);
	if (IsHumanAlive(client))
		CacheWeaponBipodCapability(client);
}

static void ResetClientState(int client) {
	ga_iBipodWeaponRef[client] = INVALID_ENT_REFERENCE;
	ga_bWeaponSupportsBipod[client] = false;
}

public Action Timer_BipodScan(Handle timer) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsHumanAlive(client))
			continue;

		if (GetEntProp(client, Prop_Send, "m_iCurrentStance") != STANCE_PRONE)
			continue;

		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (weapon <= MaxClients || !IsValidEntity(weapon))
			continue;

		if (ga_iBipodWeaponRef[client] != EntIndexToEntRef(weapon))
			CacheWeaponBipodCapability(client);

		if (!ga_bWeaponSupportsBipod[client])
			continue;

		if ((GetEntProp(client, Prop_Send, "m_iPlayerFlags") & PF_DEPLOY_BIPOD) == 0)
			continue;

		float angles[3];
		GetClientEyeAngles(client, angles);
		if (IsWallTooClose(client, angles))
			SDKCall(g_hSetBipodState, client, false);
	}

	return Plugin_Continue;
}

static void CacheWeaponBipodCapability(int client) {
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon <= MaxClients || !IsValidEntity(weapon)) {
		ga_iBipodWeaponRef[client] = INVALID_ENT_REFERENCE;
		ga_bWeaponSupportsBipod[client] = false;
		return;
	}

	ga_iBipodWeaponRef[client] = EntIndexToEntRef(weapon);
	ga_bWeaponSupportsBipod[client] = SDKCall(g_hSupportsBipod, weapon, BIPOD_CAPABILITY);
}

static bool IsWallTooClose(int client, const float angles[3]) {
	float origin[3];
	float direction[3];
	float end[3];
	GetClientEyePosition(client, origin);

	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(direction, MAX_WALL_DISTANCE);
	AddVectors(origin, direction, end);

	TR_TraceRayFilter(origin, end, MASK_PLAYERSOLID, RayType_EndPoint, Point_Trace_Filter, client);

	if (!TR_DidHit())
		return false;

	float normal[3];
	TR_GetPlaneNormal(INVALID_HANDLE, normal);
	return FloatAbs(normal[2]) < MAX_WALL_NORMAL_Z;
}

static bool Point_Trace_Filter(int entity, int mask, any data) {
	return entity != data && (entity < 1 || entity > MaxClients);
}
