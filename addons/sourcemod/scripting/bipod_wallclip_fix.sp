#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PF_DEPLOY_BIPOD (1 << 1)
#define STANCE_PRONE 2
#define BIPOD_CAPABILITY 1
#define GAMEDATA_FILE "insurgency-bm.games"

static const float BIPOD_SCAN_INTERVAL = 0.50;
static const float MAX_WALL_DISTANCE = 38.0;
static const float MAX_WALL_NORMAL_Z = 0.70;

float ga_fPlayerNextBipodScanAt[MAXPLAYERS + 1] = {0.0, ...};
int ga_iBipodWeaponRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
bool ga_bWeaponSupportsBipod[MAXPLAYERS + 1] = {false, ...};

GameData g_hGameData = null;
Handle g_hSupportsBipod = null;
Handle g_hSetBipodState = null;

public Plugin myinfo = {
	name        = "bipod_wallclip_fix",
	author      = "Nullifidian",
	description = "Prevents bipod wall-clipping exploits by automatically retracting deployed bipods near obstructions.",
	version     = "1.0.2",
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
	ga_fPlayerNextBipodScanAt[client] = 0.0;
	ga_iBipodWeaponRef[client] = INVALID_ENT_REFERENCE;
	ga_bWeaponSupportsBipod[client] = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!IsHumanAlive(client))
		return Plugin_Continue;

	if (GetEntProp(client, Prop_Send, "m_iCurrentStance") != STANCE_PRONE)
		return Plugin_Continue;

	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon <= MaxClients || !IsValidEntity(iWeapon))
		return Plugin_Continue;

	if (ga_iBipodWeaponRef[client] != EntIndexToEntRef(iWeapon))
		CacheWeaponBipodCapability(client);

	if (!ga_bWeaponSupportsBipod[client])
		return Plugin_Continue;

	int iPlayerFlags = GetEntProp(client, Prop_Send, "m_iPlayerFlags");
	if ((iPlayerFlags & PF_DEPLOY_BIPOD) == 0)
		return Plugin_Continue;

	float now = GetGameTime();
	if (now < ga_fPlayerNextBipodScanAt[client])
		return Plugin_Continue;
	ga_fPlayerNextBipodScanAt[client] = now + BIPOD_SCAN_INTERVAL;

	if (!IsWallTooClose(client, angles))
		return Plugin_Continue;

	SDKCall(g_hSetBipodState, client, false);
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
