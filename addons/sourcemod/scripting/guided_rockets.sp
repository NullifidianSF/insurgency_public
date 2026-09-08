#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>

#define PL_VERSION "1.8.14"
#define FIREMODE_SOUND "weapons/m16a4/handling/m16_fireselect.wav"
#define BTN_ATTACK1 (1 << 0)
#define BTN_JUMP (1 << 1)
#define BTN_RELOAD (1 << 11)
#define BTN_FIREMODE (1 << 12)
#define BTN_AIM (1 << 18)
#define BTN_AIM_TOGGLE (1 << 27)
#define BTN_PRONE (1 << 3)
#define BTN_DUCK_TOGGLE (1 << 24)
#define BTN_STANCE_TOGGLE (1 << 29)
#define STANCE_CROUCH 1
#define STANCE_PRONE 2
#define GAMEDATA_FILE "insurgency-bm.games"
#define AIM_INTERVAL 0.10
#define AIM_DISTANCE 16384.0
#define DEG_TO_RAD 0.0174532925
#define AIM_DOT_MATERIAL "materials/sprites/glow01.vmt"
#define CAMERA_ICON_RPG "materials/vgui/inventory/weapon_rpg7.vmt"
#define CAMERA_ICON_AT4 "materials/vgui/inventory/weapon_at4.vmt"
#define CAMERA_ICON_SIZE 10.0
#define CAMERA_ICON_DISTANCE 256.0

enum RocketMode {
	Rocket_Normal,
	Rocket_Guided,
	Rocket_Camera
};

static const char g_sModeNames[][] = {"Normal", "Guided", "Guided with camera"};

DynamicDetour g_hFlight;
DynamicDetour g_hKeepLauncher;
DynamicDetour g_hRadiusDamage;
int g_iRadiusDamageDepth;
int g_iRadiusDamageCalls;
int g_iBodyDamageRedirects;
int g_iBlastCameraRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int g_iBlastUserId[MAXPLAYERS + 1];
GlobalForward g_hGuidanceChanged;
ConVar g_cvEnabled;
ConVar g_cvGuidedEnabled;
ConVar g_cvCameraEnabled;
ConVar g_cvTurnRate;
ConVar g_cvMaxTime;
ConVar g_cvSpeed;
ConVar g_cvMaxVelocity;
ConVar g_cvAimDot;
ConVar g_cvCameraBack;
ConVar g_cvCameraUp;
ConVar g_cvCameraEndDelay;
ConVar g_cvDamageDebug;
bool g_bDamageDebug;
bool g_bDamageDebugHooked[MAXPLAYERS + 1];
float g_fDebugCameraAt[MAXPLAYERS + 1] = {-1.0, ...};
float g_fDebugUntil[MAXPLAYERS + 1];
float g_fDebugCameraPos[MAXPLAYERS + 1][3];
float g_fDebugRocketPos[MAXPLAYERS + 1][3];
int g_iDebugRocketRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int g_iAimDotModel;
int g_iDotAttempts;
int g_iDotSent;
int g_iDotRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
float g_fDotExpires[MAXPLAYERS + 1];
Handle g_hWatchdog;
bool g_bEnabled;
bool g_bGuidedEnabled;
bool g_bCameraEnabled;
bool g_bAimDot;
bool g_bLateLoad;
RocketMode g_eSelectedMode[MAXPLAYERS + 1];
bool g_bCameraFlight[MAXPLAYERS + 1];
int g_iCameraRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int g_iCameraIndex[MAXPLAYERS + 1];
int g_iOriginalCameraDraw[MAXPLAYERS + 1] = {-1, ...};
int g_iCameraIconRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
float g_fIconTestEndAt[MAXPLAYERS + 1];
int g_iCameraIconRPGModel;
int g_iCameraIconAT4Model;
int g_iCameraUpdates;
float g_fCameraAim[MAXPLAYERS + 1][3];
float g_fCameraBack;
float g_fCameraUp;
float g_fCameraEndDelay;
float g_fCameraEndAt[MAXPLAYERS + 1];
bool g_bFireModeHeld[MAXPLAYERS + 1];
bool g_bAimHeld[MAXPLAYERS + 1];
float g_fTurnRate;
float g_fMaxTime;
float g_fSpeed;
int g_iRocketRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int g_iLauncherRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int g_iRocketIndex[MAXPLAYERS + 1];
int g_iLauncherIndex[MAXPLAYERS + 1];
float g_fStarted[MAXPLAYERS + 1];
float g_fLastUpdate[MAXPLAYERS + 1];
float g_fNextAim[MAXPLAYERS + 1];
float g_fAimPoint[MAXPLAYERS + 1][3];
int g_iAttached;
int g_iSteered;
int g_iKept;

public Plugin myinfo = {
	name = "Guided RPG / AT4 Rockets",
	author = "Nullifidian, OpenAI",
	description = "Players cycle Normal, Guided and Rocket camera RPG/AT4 shots with FIRE MODE, without extra ammo",
	version = PL_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax) {
	g_bLateLoad = late;
	RegPluginLibrary("bm_guided_rockets");
	CreateNative("GuidedRockets_IsClientGuiding", Native_IsClientGuiding);
	g_hGuidanceChanged = new GlobalForward("GuidedRockets_OnGuidanceChanged", ET_Ignore, Param_Cell, Param_Cell);
	return APLRes_Success;
}

public any Native_IsClientGuiding(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	return IsLivingHuman(client) && (g_iRocketIndex[client] != 0 || g_fCameraEndAt[client] > 0.0);
}

void NotifyGuidanceChanged(int client, bool active) {
	if (g_hGuidanceChanged == null)
		return;
	Call_StartForward(g_hGuidanceChanged);
	Call_PushCell(client);
	Call_PushCell(active);
	Call_Finish();
}

public void OnPluginStart() {
	g_cvEnabled = CreateConVar("sm_guidedrockets_enable", "1", "Allow humans to cycle Normal/Guided/Rocket camera RPG/AT4 shots with FIRE MODE. Normal by default. Bots unchanged. 0 disables and releases current guidance.", _, true, 0.0, true, 1.0);
	g_cvGuidedEnabled = CreateConVar("sm_guidedrockets_guided_enable", "1", "Allow Guided mode without a remote camera. 0 skips this mode and immediately releases its active rockets. Camera mode is independent; the master enable must also be 1.", _, true, 0.0, true, 1.0);
	g_cvCameraEnabled = CreateConVar("sm_guidedrockets_camera_enable", "1", "Allow Guided with camera mode. 0 skips this mode and immediately ends active camera guidance and camera linger. Guided mode is independent; the master enable must also be 1.", _, true, 0.0, true, 1.0);
	g_cvTurnRate = CreateConVar("sm_guidedrockets_turn_rate", "360", "Maximum guidance turn rate in degrees per second. Does not change rocket speed.", _, true, 1.0, true, 720.0);
	g_cvMaxTime = CreateConVar("sm_guidedrockets_max_time", "20", "Maximum guidance seconds per rocket. After this, the rocket continues unguided and native empty-launcher removal resumes.", _, true, 1.0, true, 60.0);
	g_cvSpeed = CreateConVar("sm_guidedrockets_speed", "800", "Flight speed in units/second while guided. 0 preserves native/rpg-speed-plugin speed. Positive values enforce at least 1 unit/s, capped at sv_maxvelocity. Takes effect on flight updates; stops overriding when guidance ends.", _, true, 0.0, true, 100000.0);
	g_cvAimDot = CreateConVar("sm_guidedrockets_dot", "1", "Show a laser aim dot only to the shooter during guidance, on surfaces hit by the existing aim trace. No dot in open sky. 0 disables.", _, true, 0.0, true, 1.0);
	g_cvMaxVelocity = FindConVar("sv_maxvelocity");
	g_cvCameraBack = CreateConVar("sm_guidedrockets_camera_back", "32", "Rocket camera distance behind the rocket in units. Nearby walls shorten the offset.", _, true, 4.0, true, 200.0);
	g_cvCameraUp = CreateConVar("sm_guidedrockets_camera_up", "10", "Rocket camera offset above the rocket in units, relative to its flight direction.", _, true, 0.0, true, 100.0);
	g_cvCameraEndDelay = CreateConVar("sm_guidedrockets_camera_end_delay", "1.0", "Seconds to keep the camera at its last position when the rocket stops or is removed. 0 exits immediately. AIM, weapon switching and death still exit immediately.", _, true, 0.0, true, 5.0);
	g_cvDamageDebug = CreateConVar("sm_guidedrockets_debug_damage", "0", "Log damage/deaths during rocket-camera use and for 2 seconds afterward to SourceMod logs. Diagnostic only; does not change damage.", _, true, 0.0, true, 1.0);
	g_cvDamageDebug.AddChangeHook(OnDamageDebugChanged);
	g_bDamageDebug = g_cvDamageDebug.BoolValue;
	g_cvEnabled.AddChangeHook(OnSettingsChanged);
	g_cvGuidedEnabled.AddChangeHook(OnSettingsChanged);
	g_cvCameraEnabled.AddChangeHook(OnSettingsChanged);
	g_cvTurnRate.AddChangeHook(OnSettingsChanged);
	g_cvMaxTime.AddChangeHook(OnSettingsChanged);
	g_cvSpeed.AddChangeHook(OnSettingsChanged);
	g_cvAimDot.AddChangeHook(OnSettingsChanged);
	g_cvCameraBack.AddChangeHook(OnSettingsChanged);
	g_cvCameraUp.AddChangeHook(OnSettingsChanged);
	g_cvCameraEndDelay.AddChangeHook(OnSettingsChanged);
	CacheSettings();

	GameData gameData = new GameData(GAMEDATA_FILE);
	if (gameData == null)
		SetFailState("[Guided Rockets] Missing gamedata: %s.txt", GAMEDATA_FILE);

	g_hFlight = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity);
	g_hKeepLauncher = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Bool, ThisPointer_CBaseEntity);
	bool flightResolved = g_hFlight.SetFromConf(gameData, SDKConf_Signature, "CBaseRocketMissile::AccelerateThink");
	bool keepResolved = g_hKeepLauncher.SetFromConf(gameData, SDKConf_Signature, "CINSWeaponRocketBase::ShouldRemoveOnDeplete");
	g_hRadiusDamage = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Ignore);
	g_hRadiusDamage.AddParam(HookParamType_ObjectPtr);
	g_hRadiusDamage.AddParam(HookParamType_VectorPtr);
	g_hRadiusDamage.AddParam(HookParamType_Float);
	g_hRadiusDamage.AddParam(HookParamType_Int);
	g_hRadiusDamage.AddParam(HookParamType_CBaseEntity);
	g_hRadiusDamage.AddParam(HookParamType_Bool);
	g_hRadiusDamage.AddParam(HookParamType_Bool);
	bool radiusResolved = g_hRadiusDamage.SetFromConf(gameData, SDKConf_Signature, "CINSRules::RadiusDamage");
	delete gameData;
	if (!flightResolved || !keepResolved)
		SetFailState("[Guided Rockets] Missing rocket flight or launcher depletion signature in %s.txt", GAMEDATA_FILE);
	if (!g_hFlight.Enable(Hook_Post, Detour_Flight_Post) || !g_hKeepLauncher.Enable(Hook_Post, Detour_KeepLauncher_Post))
		SetFailState("[Guided Rockets] Could not enable native rocket detours.");
	if (!radiusResolved || !g_hRadiusDamage.Enable(Hook_Pre, Detour_RadiusDamage_Pre)
		|| !g_hRadiusDamage.Enable(Hook_Post, Detour_RadiusDamage_Post))
		SetFailState("[Guided Rockets] Could not resolve/enable CINSRules::RadiusDamage in %s.txt", GAMEDATA_FILE);

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	RegAdminCmd("sm_guidedrockets_status", Command_Status, ADMFLAG_ROOT, "Show guided rocket settings, counts and your linked rocket/launcher.");
	RegAdminCmd("sm_guidedrockets_dottest", Command_DotTest, ADMFLAG_ROOT, "Show a shooter-only aiming glow for 3 seconds without firing a rocket. Aim at a nearby wall.");
	RegAdminCmd("sm_guidedrockets_icontest", Command_IconTest, ADMFLAG_ROOT, "Show a launcher icon above yourself for 10 seconds without firing: [rpg|at4|off]. Defaults to rpg.");
	if (g_bLateLoad)
		for (int client = 1; client <= MaxClients; client++)
			if (IsClientInGame(client))
				OnClientPutInServer(client);

	AutoExecConfig(true, "guided_rockets");
}

public void OnPluginEnd() {
	ResetGuidance();
	delete g_hFlight;
	delete g_hKeepLauncher;
	delete g_hRadiusDamage;
	delete g_hGuidanceChanged;
}

public void OnMapStart() {
	ResetGuidance();
	PrecacheSound(FIREMODE_SOUND, true);
	for (int client = 1; client <= MaxClients; client++) {
		g_eSelectedMode[client] = Rocket_Normal;
		g_bFireModeHeld[client] = false;
		g_bAimHeld[client] = false;
		g_fDebugCameraAt[client] = -1.0;
		g_fDebugUntil[client] = 0.0;
	}
	g_iAimDotModel = PrecacheModel(AIM_DOT_MATERIAL, true);
	g_iCameraIconRPGModel = PrecacheModel(CAMERA_ICON_RPG, true);
	g_iCameraIconAT4Model = PrecacheModel(CAMERA_ICON_AT4, true);
	if (g_iCameraIconRPGModel <= 0 || g_iCameraIconAT4Model <= 0)
		LogError("[Guided Rockets] Could not precache one or both launcher camera icons.");
	if (g_iAimDotModel <= 0)
		LogError("[Guided Rockets] Could not precache %s; aiming dot unavailable.", AIM_DOT_MATERIAL);
	g_iAttached = 0;
	g_iSteered = 0;
	g_iKept = 0;
	g_iDotAttempts = 0;
	g_iDotSent = 0;
	g_iCameraUpdates = 0;
	g_iRadiusDamageCalls = 0;
	g_iBodyDamageRedirects = 0;
}

public void OnMapEnd() {
	ResetGuidance();
}

void ResetGuidance() {
	delete g_hWatchdog;
	for (int client = 1; client <= MaxClients; client++)
		StopGuidance(client);
}

public MRESReturn Detour_RadiusDamage_Pre(DHookParam hParams) {
	g_iRadiusDamageCalls++;
	if (g_iRadiusDamageDepth++ != 0)
		return MRES_Ignored;

	for (int client = 1; client <= MaxClients; client++) {
		g_iBlastCameraRef[client] = INVALID_ENT_REFERENCE;
		g_iBlastUserId[client] = 0;
		if (g_iCameraIndex[client] == 0 || !IsLivingHuman(client))
			continue;
		int camera = EntRefToEntIndex(g_iCameraRef[client]);
		if (camera <= MaxClients || !IsValidEntity(camera)
			|| GetEntPropEnt(client, Prop_Send, "m_hViewEntity") != camera)
			continue;

		g_iBlastCameraRef[client] = g_iCameraRef[client];
		g_iBlastUserId[client] = GetClientUserId(client);
		// Native BodyTarget uses EyePosition. Clear only its server-side view reference;
		// do not call SetClientViewEntity, which would switch the client's actual camera.
		SetEntPropEnt(client, Prop_Send, "m_hViewEntity", -1);
		g_iBodyDamageRedirects++;
		if (g_bDamageDebug) {
			float eye[3];
			GetClientEyePosition(client, eye);
			LogMessage("[Rocket Damage] BLAST body targeting userid=%d eye=(%.1f %.1f %.1f) saved camera=%d", g_iBlastUserId[client], eye[0], eye[1], eye[2], camera);
		}
	}
	return MRES_Ignored;
}

public MRESReturn Detour_RadiusDamage_Post(DHookParam hParams) {
	if (g_iRadiusDamageDepth <= 0 || --g_iRadiusDamageDepth != 0)
		return MRES_Ignored;

	for (int client = 1; client <= MaxClients; client++) {
		int cameraRef = g_iBlastCameraRef[client];
		int userId = g_iBlastUserId[client];
		g_iBlastCameraRef[client] = INVALID_ENT_REFERENCE;
		g_iBlastUserId[client] = 0;
		// Death, disconnect or guidance cleanup may have ended this session inside RadiusDamage.
		if (cameraRef == INVALID_ENT_REFERENCE || !IsLivingHuman(client)
			|| GetClientUserId(client) != userId || g_iCameraRef[client] != cameraRef)
			continue;
		int camera = EntRefToEntIndex(cameraRef);
		if (camera > MaxClients && IsValidEntity(camera) && g_iCameraIndex[client] == camera
			&& GetEntPropEnt(client, Prop_Send, "m_hViewEntity") == -1)
			SetEntPropEnt(client, Prop_Send, "m_hViewEntity", camera);
	}
	return MRES_Ignored;
}

public void OnClientPutInServer(int client) {
	StopGuidance(client);
	g_fDebugCameraAt[client] = -1.0;
	g_fDebugUntil[client] = 0.0;
	UpdateDamageDebugHooks(client);
	g_eSelectedMode[client] = Rocket_Normal;
	g_bFireModeHeld[client] = false;
	g_bAimHeld[client] = false;
	if (!IsFakeClient(client))
		SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
}

public void OnClientDisconnect(int client) {
	StopGuidance(client);
	g_fDebugCameraAt[client] = -1.0;
	g_fDebugUntil[client] = 0.0;
	g_bDamageDebugHooked[client] = false;
	g_eSelectedMode[client] = Rocket_Normal;
	g_bFireModeHeld[client] = false;
	g_bAimHeld[client] = false;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (ShouldLogCameraDamage(client)) {
		char weaponName[64];
		event.GetString("weapon", weaponName, sizeof(weaponName));
		LogMessage("[Rocket Damage] DEATH victim=%N userid=%d attacker_userid=%d weapon=%s", client, event.GetInt("userid"), event.GetInt("attacker"), weaponName);
	}
	if (client > 0)
		StopGuidance(client);
}

public void OnWeaponSwitchPost(int client, int weapon) {
	if ((g_iRocketIndex[client] != 0 || g_fCameraEndAt[client] > 0.0) && weapon != EntRefToEntIndex(g_iLauncherRef[client]))
		StopGuidance(client);
	if (g_bEnabled && IsLivingHuman(client) && IsLauncherWeapon(weapon))
		ShowRocketModeHint(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	bool aimHeld = (buttons & (BTN_AIM | BTN_AIM_TOGGLE)) != 0;
	bool aimPressed = aimHeld && !g_bAimHeld[client];
	g_bAimHeld[client] = aimHeld;
	Action result = Plugin_Continue;
	// Require a fresh press so aiming while firing does not immediately release the rocket.
	if (aimPressed && (g_iRocketIndex[client] != 0 || g_fCameraEndAt[client] > 0.0) && IsLivingHuman(client)) {
		g_bFireModeHeld[client] = (buttons & BTN_FIREMODE) != 0;
		StopGuidance(client);
		buttons &= ~(BTN_AIM | BTN_AIM_TOGGLE);
		PrintHintText(client, "Rocket guidance released");
		return Plugin_Changed;
	}
	if (g_bCameraFlight[client] && g_iCameraIndex[client] != 0 && IsLivingHuman(client)) {
		g_fCameraAim[client][0] = angles[0];
		g_fCameraAim[client][1] = angles[1];
		g_fCameraAim[client][2] = 0.0;
		vel[0] = 0.0;
		vel[1] = 0.0;
		vel[2] = 0.0;
		buttons &= ~(BTN_ATTACK1 | BTN_RELOAD | BTN_JUMP | BTN_PRONE | BTN_DUCK_TOGGLE | BTN_STANCE_TOGGLE);
		result = Plugin_Changed;
	}
	bool fireModeHeld = (buttons & BTN_FIREMODE) != 0;
	bool fireModePressed = fireModeHeld && !g_bFireModeHeld[client];
	g_bFireModeHeld[client] = fireModeHeld;
	if (!fireModePressed)
		return result;
	if (!g_bEnabled || !IsLivingHuman(client))
		return result;
	if (!IsLauncherWeapon(GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")))
		return result;

	RocketMode previousMode = g_eSelectedMode[client];
	do
		g_eSelectedMode[client] = view_as<RocketMode>((view_as<int>(g_eSelectedMode[client]) + 1) % 3);
	while (!IsRocketModeEnabled(g_eSelectedMode[client]));
	ShowRocketModeHint(client);
	if (g_eSelectedMode[client] != previousMode)
		EmitSoundToClient(client, FIREMODE_SOUND);
	return result;
}

bool IsLauncherWeapon(int weapon) {
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return false;
	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));
	return StrEqual(classname, "weapon_rpg7") || StrEqual(classname, "weapon_at4");
}

void ShowRocketModeHint(int client) {
	if (!g_bEnabled || (!g_bGuidedEnabled && !g_bCameraEnabled))
		PrintHintText(client, "Rocket type: Normal\nGuidance modes are disabled");
	else if (g_eSelectedMode[client] == Rocket_Camera)
		PrintHintText(client, "Rocket type: %s\nPress FIRE MODE to change\nWarning: camera steering can be unreliable while prone", g_sModeNames[g_eSelectedMode[client]]);
	else
		PrintHintText(client, "Rocket type: %s\nPress FIRE MODE to change", g_sModeNames[g_eSelectedMode[client]]);
}

bool IsRocketModeEnabled(RocketMode mode) {
	if (mode == Rocket_Normal)
		return true;
	return g_bEnabled && (mode == Rocket_Camera ? g_bCameraEnabled : g_bGuidedEnabled);
}

public void OnSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	CacheSettings();
	if (!g_bEnabled)
		ResetGuidance();
	else if (!g_bAimDot)
		for (int client = 1; client <= MaxClients; client++)
			RemoveAimDot(client);
	if (convar == g_cvEnabled || convar == g_cvGuidedEnabled || convar == g_cvCameraEnabled)
		for (int client = 1; client <= MaxClients; client++) {
			if ((g_iRocketIndex[client] != 0 || g_iCameraIndex[client] != 0 || g_fCameraEndAt[client] > 0.0)
				&& !IsRocketModeEnabled(g_bCameraFlight[client] ? Rocket_Camera : Rocket_Guided))
				StopGuidance(client);
			if (!IsRocketModeEnabled(g_eSelectedMode[client]))
				g_eSelectedMode[client] = Rocket_Normal;
			if (IsLivingHuman(client) && IsLauncherWeapon(GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")))
				ShowRocketModeHint(client);
		}
}

public void OnDamageDebugChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_bDamageDebug = convar.BoolValue;
	for (int client = 1; client <= MaxClients; client++) {
		g_fDebugCameraAt[client] = -1.0;
		g_fDebugUntil[client] = 0.0;
		if (IsClientInGame(client))
			UpdateDamageDebugHooks(client);
	}
}

void UpdateDamageDebugHooks(int client) {
	bool enable = g_bDamageDebug && !IsFakeClient(client);
	if (enable == g_bDamageDebugHooked[client])
		return;
	g_bDamageDebugHooked[client] = enable;
	if (enable) {
		SDKHook(client, SDKHook_OnTakeDamage, OnCameraDamage);
		SDKHook(client, SDKHook_OnTakeDamagePost, OnCameraDamagePost);
	}
	else {
		SDKUnhook(client, SDKHook_OnTakeDamage, OnCameraDamage);
		SDKUnhook(client, SDKHook_OnTakeDamagePost, OnCameraDamagePost);
	}
}

bool ShouldLogCameraDamage(int client) {
	return g_bDamageDebug && client >= 1 && client <= MaxClients && IsClientInGame(client)
		&& (g_iCameraIndex[client] != 0 || (g_fDebugUntil[client] > 0.0 && GetGameTime() <= g_fDebugUntil[client]));
}

void DescribeDamageEntity(int entity, char[] text, int length) {
	if (entity >= 1 && entity <= MaxClients && IsClientInGame(entity))
		FormatEx(text, length, "%N(client %d, userid %d)", entity, entity, GetClientUserId(entity));
	else if (entity >= 0 && IsValidEntity(entity)) {
		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));
		FormatEx(text, length, "%s(%d)", classname, entity);
	}
	else
		FormatEx(text, length, "invalid(%d)", entity);
}

public Action OnCameraDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (!ShouldLogCameraDamage(victim))
		return Plugin_Continue;
	char attackerText[128], inflictorText[128], weaponText[128];
	DescribeDamageEntity(attacker, attackerText, sizeof(attackerText));
	DescribeDamageEntity(inflictor, inflictorText, sizeof(inflictorText));
	DescribeDamageEntity(weapon, weaponText, sizeof(weaponText));
	float body[3], eye[3];
	GetClientAbsOrigin(victim, body);
	GetClientEyePosition(victim, eye);
	LogMessage("[Rocket Damage] PRE t=%.3f victim=%N userid=%d hp=%d damage=%.2f type=0x%X attacker=%s inflictor=%s weapon=%s", GetGameTime(), victim, GetClientUserId(victim), GetClientHealth(victim), damage, damagetype, attackerText, inflictorText, weaponText);
	LogMessage("[Rocket Damage] body=(%.1f %.1f %.1f) eye=(%.1f %.1f %.1f) view=%d camera=%d linger=%.2f", body[0], body[1], body[2], eye[0], eye[1], eye[2], GetEntPropEnt(victim, Prop_Send, "m_hViewEntity"), g_iCameraIndex[victim], g_fCameraEndAt[victim]);
	if (g_fDebugCameraAt[victim] >= 0.0)
		LogMessage("[Rocket Damage] last sample age=%.3f rocket_ref=%d rocket=(%.1f %.1f %.1f) camera=(%.1f %.1f %.1f) body-to-rocket=%.1f body-to-camera=%.1f", GetGameTime() - g_fDebugCameraAt[victim], g_iDebugRocketRef[victim], g_fDebugRocketPos[victim][0], g_fDebugRocketPos[victim][1], g_fDebugRocketPos[victim][2], g_fDebugCameraPos[victim][0], g_fDebugCameraPos[victim][1], g_fDebugCameraPos[victim][2], GetVectorDistance(body, g_fDebugRocketPos[victim]), GetVectorDistance(body, g_fDebugCameraPos[victim]));
	// DamagePosition is supplied by the damage source, not necessarily the explosion origin.
	LogMessage("[Rocket Damage] damagePosition=(%.1f %.1f %.1f) force=(%.1f %.1f %.1f)", damagePosition[0], damagePosition[1], damagePosition[2], damageForce[0], damageForce[1], damageForce[2]);
	if (inflictor > MaxClients && IsValidEntity(inflictor)) {
		float source[3];
		GetEntPropVector(inflictor, Prop_Data, "m_vecAbsOrigin", source);
		LogMessage("[Rocket Damage] inflictor origin=(%.1f %.1f %.1f) body-distance=%.1f eye-distance=%.1f", source[0], source[1], source[2], GetVectorDistance(body, source), GetVectorDistance(eye, source));
	}
	return Plugin_Continue;
}

public void OnCameraDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype) {
	if (ShouldLogCameraDamage(victim))
		LogMessage("[Rocket Damage] POST t=%.3f victim=%N userid=%d hp=%d alive=%d damage=%.2f type=0x%X attacker=%d inflictor=%d", GetGameTime(), victim, GetClientUserId(victim), GetClientHealth(victim), IsPlayerAlive(victim), damage, damagetype, attacker, inflictor);
}

void CacheSettings() {
	g_bEnabled = g_cvEnabled.BoolValue;
	g_bGuidedEnabled = g_cvGuidedEnabled.BoolValue;
	g_bCameraEnabled = g_cvCameraEnabled.BoolValue;
	g_fTurnRate = g_cvTurnRate.FloatValue;
	g_fMaxTime = g_cvMaxTime.FloatValue;
	g_fSpeed = g_cvSpeed.FloatValue;
	g_bAimDot = g_cvAimDot.BoolValue;
	g_fCameraBack = g_cvCameraBack.FloatValue;
	g_fCameraUp = g_cvCameraUp.FloatValue;
	g_fCameraEndDelay = g_cvCameraEndDelay.FloatValue;
}

float GetGuidedSpeed() {
	float speed = g_fSpeed;
	if (speed <= 0.0)
		return 0.0;
	if (speed < 1.0)
		speed = 1.0;
	if (g_cvMaxVelocity != null) {
		float limit = g_cvMaxVelocity.FloatValue;
		if (limit > 0.0 && speed > limit)
			speed = limit;
	}
	return speed;
}

// Optional global forward from rpg_rocket_speed: both detour orders use the same magnitude.
public Action RPGSpeed_OnApply(int rocket, float &speed) {
	if (!g_bEnabled || g_fSpeed <= 0.0 || rocket <= MaxClients || !IsValidEntity(rocket))
		return Plugin_Continue;
	int client = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
	if (client < 1 || client > MaxClients || g_iRocketIndex[client] != rocket || !ValidateGuidance(client))
		return Plugin_Continue;
	speed = GetGuidedSpeed();
	return Plugin_Changed;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (g_bEnabled && (g_bGuidedEnabled || g_bCameraEnabled)
		&& (StrEqual(classname, "rocket_rpg7") || StrEqual(classname, "rocket_at4")))
		SDKHook(entity, SDKHook_SpawnPost, OnRocketSpawnPost);
}

public void OnRocketSpawnPost(int rocket) {
	if (!g_bEnabled || !IsValidEntity(rocket))
		return;

	// Native CreateDetonator sets m_hOwnerEntity before RocketMissile calls Spawn.
	int client = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
	if (!IsLivingHuman(client))
		return;

	int launcher = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (launcher <= MaxClients || !IsValidEntity(launcher))
		return;

	char rocketClass[32], weaponClass[32];
	GetEntityClassname(rocket, rocketClass, sizeof(rocketClass));
	GetEntityClassname(launcher, weaponClass, sizeof(weaponClass));
	if (!(StrEqual(rocketClass, "rocket_rpg7") && StrEqual(weaponClass, "weapon_rpg7"))
		&& !(StrEqual(rocketClass, "rocket_at4") && StrEqual(weaponClass, "weapon_at4")))
		return;
	if (GetEntPropEnt(launcher, Prop_Send, "m_hOwnerEntity") != client)
		return;

	StopGuidance(client);
	// Sample the selection at spawn; later button presses only change the next shot.
	if (!IsRocketModeEnabled(g_eSelectedMode[client]))
		g_eSelectedMode[client] = Rocket_Normal;
	if (g_eSelectedMode[client] == Rocket_Normal)
		return;
	g_bCameraFlight[client] = g_eSelectedMode[client] == Rocket_Camera;
	if (g_bCameraFlight[client]) {
		GetClientEyeAngles(client, g_fCameraAim[client]);
		g_fCameraAim[client][2] = 0.0;
	}
	g_iRocketRef[client] = EntIndexToEntRef(rocket);
	g_iLauncherRef[client] = EntIndexToEntRef(launcher);
	g_iRocketIndex[client] = rocket;
	g_iLauncherIndex[client] = launcher;
	g_fStarted[client] = GetGameTime();
	g_fLastUpdate[client] = g_fStarted[client];
	g_fNextAim[client] = 0.0;
	g_iAttached++;
	if (g_hWatchdog == null)
		g_hWatchdog = CreateTimer(0.1, Timer_Watchdog, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	NotifyGuidanceChanged(client, true);
	if (g_bCameraFlight[client])
		RequestFrame(Frame_StartRocketCamera, g_iRocketRef[client]);
	else
		PrintHintText(client, "Rocket guidance: move mouse to steer\nPress AIM or switch weapon to release");
}

public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients)
		return;
	for (int client = 1; client <= MaxClients; client++) {
		if (g_iCameraIndex[client] == entity) {
			// Already being destroyed: restore the view without removing this entity twice.
			g_iCameraRef[client] = INVALID_ENT_REFERENCE;
			StopGuidance(client);
		}
		else if (g_iRocketIndex[client] == entity) {
			if (!BeginCameraLinger(client))
				StopGuidance(client);
		}
		else if (g_iLauncherIndex[client] == entity)
			StopGuidance(client);
	}
}

void StopGuidance(int client) {
	if (g_bDamageDebug && g_iCameraIndex[client] != 0) {
		g_fDebugUntil[client] = GetGameTime() + 2.0;
		LogMessage("[Rocket Damage] Camera end client=%d userid=%d t=%.3f", client, IsClientInGame(client) ? GetClientUserId(client) : 0, GetGameTime());
	}
	bool wasGuiding = g_iRocketIndex[client] != 0 || g_fCameraEndAt[client] > 0.0;
	g_fCameraEndAt[client] = 0.0;
	g_iRocketRef[client] = INVALID_ENT_REFERENCE;
	g_iLauncherRef[client] = INVALID_ENT_REFERENCE;
	g_iRocketIndex[client] = 0;
	g_iLauncherIndex[client] = 0;
	g_bCameraFlight[client] = false;
	RemoveRocketCamera(client);
	RemoveCameraIcon(client);
	RemoveAimDot(client);
	if (wasGuiding)
		NotifyGuidanceChanged(client, false);
}

void RemoveRocketCamera(int client) {
	int camera = EntRefToEntIndex(g_iCameraRef[client]);
	int cameraIndex = g_iCameraIndex[client];
	g_iCameraRef[client] = INVALID_ENT_REFERENCE;
	g_iCameraIndex[client] = 0;
	if (cameraIndex != 0 && IsClientInGame(client)) {
		int viewEntity = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
		if (viewEntity == cameraIndex || viewEntity <= 0) {
			SetEntPropEnt(client, Prop_Send, "m_hViewEntity", -1);
			SetClientViewEntity(client, client);
		}
	}
	if (g_iOriginalCameraDraw[client] != -1) {
		if (IsClientInGame(client) && HasEntProp(client, Prop_Send, "m_bShouldDrawPlayerWhileUsingViewEntity")
			&& GetEntProp(client, Prop_Send, "m_bShouldDrawPlayerWhileUsingViewEntity") == 1)
			SetEntProp(client, Prop_Send, "m_bShouldDrawPlayerWhileUsingViewEntity", g_iOriginalCameraDraw[client]);
		g_iOriginalCameraDraw[client] = -1;
	}
	if (camera > MaxClients && IsValidEntity(camera))
		RemoveEntity(camera);
}

public void Frame_StartRocketCamera(any rocketRef) {
	int rocket = EntRefToEntIndex(rocketRef);
	if (rocket <= MaxClients || !IsValidEntity(rocket))
		return;
	int client = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
	if (!IsLivingHuman(client) || g_iRocketRef[client] != rocketRef || !g_bCameraFlight[client])
		return;
	if (!ValidateGuidance(client)) {
		StopGuidance(client);
		return;
	}
	int viewEntity = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
	if (viewEntity > 0 && viewEntity != client) {
		StopGuidance(client);
		PrintHintText(client, "Rocket camera unavailable: another camera is active.");
		return;
	}

	// Defer camera creation until the native rocket spawn has completed.
	int camera = CreateEntityByName("info_target");
	if (camera == -1) {
		StopGuidance(client);
		PrintHintText(client, "Could not create rocket camera. Rocket released.");
		return;
	}
	g_iCameraRef[client] = EntIndexToEntRef(camera);
	g_iCameraIndex[client] = camera;
	// info_target: transmit to clients (1), including outside the player's PVS (2).
	DispatchKeyValue(camera, "spawnflags", "3");
	if (!DispatchSpawn(camera)) {
		StopGuidance(client);
		return;
	}
	GetClientEyeAngles(client, g_fCameraAim[client]);
	g_fCameraAim[client][2] = 0.0;
	float velocity[3], cameraAngles[3];
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", velocity);
	if (GetVectorLength(velocity) >= 1.0)
		GetVectorAngles(velocity, cameraAngles);
	else
		for (int axis = 0; axis < 3; axis++)
			cameraAngles[axis] = g_fCameraAim[client][axis];
	UpdateRocketCamera(client, rocket, cameraAngles);
	if (HasEntProp(client, Prop_Send, "m_bShouldDrawPlayerWhileUsingViewEntity")) {
		g_iOriginalCameraDraw[client] = GetEntProp(client, Prop_Send, "m_bShouldDrawPlayerWhileUsingViewEntity");
		SetEntProp(client, Prop_Send, "m_bShouldDrawPlayerWhileUsingViewEntity", 1);
	}
	// Keep the player's networked view handle in sync with the engine view override.
	SetEntPropEnt(client, Prop_Send, "m_hViewEntity", camera);
	SetClientViewEntity(client, camera);
	CreateCameraIcon(client);
	PrintHintText(client, "Rocket camera: move mouse to steer\nPress AIM or switch weapon to exit");
}

void RemoveCameraIcon(int client) {
	int sprite = EntRefToEntIndex(g_iCameraIconRef[client]);
	g_iCameraIconRef[client] = INVALID_ENT_REFERENCE;
	g_fIconTestEndAt[client] = 0.0;
	if (sprite > MaxClients && IsValidEntity(sprite))
		RemoveEntity(sprite);
}

void UpdateCameraIcon(int client) {
	int sprite = EntRefToEntIndex(g_iCameraIconRef[client]);
	if (sprite <= MaxClients || !IsValidEntity(sprite))
		return;
	float position[3], viewOffset[3];
	// EyePosition follows m_hViewEntity; this marker must stay on the physical body.
	GetClientAbsOrigin(client, position);
	GetEntPropVector(client, Prop_Data, "m_vecViewOffset", viewOffset);
	AddVectors(position, viewOffset, position);
	position[2] += 20.0;
	TeleportEntity(sprite, position, NULL_VECTOR, NULL_VECTOR);
}

void CreateCameraIcon(int client) {
	RemoveCameraIcon(client);
	int launcher = EntRefToEntIndex(g_iLauncherRef[client]);
	if (launcher <= MaxClients || !IsValidEntity(launcher))
		return;
	char classname[32];
	GetEntityClassname(launcher, classname, sizeof(classname));
	CreateLauncherIcon(client, StrEqual(classname, "weapon_at4"));
}

bool CreateLauncherIcon(int client, bool at4) {
	RemoveCameraIcon(client);
	if ((at4 ? g_iCameraIconAT4Model : g_iCameraIconRPGModel) <= 0)
		return false;
	int sprite = CreateEntityByName("env_sprite");
	if (sprite == -1)
		return false;
	g_iCameraIconRef[client] = EntIndexToEntRef(sprite);
	if (at4)
		DispatchKeyValue(sprite, "model", CAMERA_ICON_AT4);
	else
		DispatchKeyValue(sprite, "model", CAMERA_ICON_RPG);
	DispatchKeyValue(sprite, "spawnflags", "1");
	DispatchKeyValue(sprite, "rendermode", "1");
	DispatchKeyValue(sprite, "renderamt", "255");
	DispatchKeyValue(sprite, "rendercolor", "255 255 255");
	DispatchKeyValue(sprite, "disableshadows", "1");
	DispatchKeyValue(sprite, "disableshadowdepth", "1");
	if (!DispatchSpawn(sprite)) {
		RemoveCameraIcon(client);
		return false;
	}
	SetEntPropEnt(sprite, Prop_Send, "m_hOwnerEntity", client);
	// World-space sizing avoids the coarse network precision of tiny texture multipliers.
	SetEntProp(sprite, Prop_Send, "m_bWorldSpaceScale", 1);
	SetEntPropFloat(sprite, Prop_Send, "m_flSpriteScale", CAMERA_ICON_SIZE);
	SDKHook(sprite, SDKHook_SetTransmit, OnCameraIconTransmit);
	AcceptEntityInput(sprite, "DisableShadow");
	UpdateCameraIcon(client);
	return true;
}

public Action OnCameraIconTransmit(int sprite, int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Handled;
	float eye[3], position[3];
	int view = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
	if (view > MaxClients && IsValidEntity(view))
		GetEntPropVector(view, Prop_Data, "m_vecAbsOrigin", eye);
	else if (view > 0 && view <= MaxClients && IsClientInGame(view))
		GetClientEyePosition(view, eye);
	else
		GetClientEyePosition(client, eye);
	GetEntPropVector(sprite, Prop_Data, "m_vecAbsOrigin", position);
	return GetVectorDistance(eye, position, true) <= CAMERA_ICON_DISTANCE * CAMERA_ICON_DISTANCE
		? Plugin_Continue : Plugin_Handled;
}

void UpdateRocketCamera(int client, int rocket, const float angles[3]) {
	int camera = EntRefToEntIndex(g_iCameraRef[client]);
	if (camera <= MaxClients || !IsValidEntity(camera))
		return;
	float origin[3], direction[3], up[3], position[3], target[3], look[3], viewAngles[3];
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsOrigin", origin);
	GetAngleVectors(angles, direction, NULL_VECTOR, up);
	for (int axis = 0; axis < 3; axis++) {
		position[axis] = origin[axis] - direction[axis] * g_fCameraBack + up[axis] * g_fCameraUp;
		target[axis] = origin[axis] + direction[axis] * 64.0;
	}
	float mins[3] = {-4.0, -4.0, -4.0};
	float maxs[3] = {4.0, 4.0, 4.0};
	Handle trace = TR_TraceHullFilterEx(origin, position, mins, maxs, MASK_SOLID, Trace_Camera, client);
	if (TR_StartSolid(trace) || TR_AllSolid(trace)) {
		for (int axis = 0; axis < 3; axis++)
			position[axis] = origin[axis];
	}
	else if (TR_DidHit(trace))
		TR_GetEndPosition(position, trace);
	delete trace;
	MakeVectorFromPoints(position, target, look);
	GetVectorAngles(look, viewAngles);
	TeleportEntity(camera, position, viewAngles, NULL_VECTOR);
	if (g_bDamageDebug) {
		g_fDebugCameraAt[client] = GetGameTime();
		g_iDebugRocketRef[client] = g_iRocketRef[client];
		for (int axis = 0; axis < 3; axis++) {
			g_fDebugCameraPos[client][axis] = position[axis];
			g_fDebugRocketPos[client][axis] = origin[axis];
		}
	}
	g_iCameraUpdates++;
}

public bool Trace_Camera(int entity, int contentsMask, any client) {
	return entity != g_iCameraIndex[client] && Trace_Aim(entity, contentsMask, client);
}

void RemoveAimDot(int client) {
	int sprite = EntRefToEntIndex(g_iDotRef[client]);
	g_iDotRef[client] = INVALID_ENT_REFERENCE;
	g_fDotExpires[client] = 0.0;
	if (sprite > MaxClients && IsValidEntity(sprite))
		RemoveEntity(sprite);
}

bool IsLivingHuman(int client) {
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client);
}

bool HasValidCameraSession(int client) {
	if (!g_bEnabled || !g_bCameraEnabled || !g_bCameraFlight[client] || !IsLivingHuman(client))
		return false;
	int camera = EntRefToEntIndex(g_iCameraRef[client]);
	int launcher = EntRefToEntIndex(g_iLauncherRef[client]);
	if (camera <= MaxClients || launcher <= MaxClients || !IsValidEntity(camera) || !IsValidEntity(launcher))
		return false;
	return GetEntPropEnt(client, Prop_Send, "m_hViewEntity") == camera
		&& GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == launcher
		&& GetEntPropEnt(launcher, Prop_Send, "m_hOwnerEntity") == client;
}

bool BeginCameraLinger(int client) {
	if (g_fCameraEndDelay <= 0.0 || g_fCameraEndAt[client] > 0.0 || !HasValidCameraSession(client))
		return false;
	float now = GetGameTime();
	if (now - g_fStarted[client] >= g_fMaxTime)
		return false;
	g_fCameraEndAt[client] = now + g_fCameraEndDelay;
	g_iRocketRef[client] = INVALID_ENT_REFERENCE;
	g_iRocketIndex[client] = 0;
	RemoveAimDot(client);
	return true;
}

bool ValidateCameraLinger(int client) {
	return g_fCameraEndDelay > 0.0 && GetGameTime() < g_fCameraEndAt[client] && HasValidCameraSession(client);
}

bool ValidateGuidance(int client) {
	if (!g_bEnabled || !IsLivingHuman(client) || g_iRocketIndex[client] == 0)
		return false;
	if (!IsRocketModeEnabled(g_bCameraFlight[client] ? Rocket_Camera : Rocket_Guided))
		return false;
	int rocket = EntRefToEntIndex(g_iRocketRef[client]);
	int launcher = EntRefToEntIndex(g_iLauncherRef[client]);
	if (rocket <= MaxClients || launcher <= MaxClients || !IsValidEntity(rocket) || !IsValidEntity(launcher))
		return false;
	if (g_iCameraIndex[client] != 0 && (EntRefToEntIndex(g_iCameraRef[client]) == INVALID_ENT_REFERENCE
		|| GetEntPropEnt(client, Prop_Send, "m_hViewEntity") != g_iCameraIndex[client]))
		return false;
	return GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == launcher
		&& GetEntPropEnt(launcher, Prop_Send, "m_hOwnerEntity") == client
		&& GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity") == client
		&& GetGameTime() - g_fStarted[client] < g_fMaxTime;
}

public Action Timer_Watchdog(Handle timer) {
	bool active;
	for (int client = 1; client <= MaxClients; client++) {
		if (g_fIconTestEndAt[client] > 0.0) {
			if (!IsLivingHuman(client) || GetGameTime() >= g_fIconTestEndAt[client]
				|| EntRefToEntIndex(g_iCameraIconRef[client]) == INVALID_ENT_REFERENCE)
				RemoveCameraIcon(client);
			else {
				UpdateCameraIcon(client);
				active = true;
			}
		}
		if (g_iDotRef[client] != INVALID_ENT_REFERENCE) {
			if (!g_bAimDot || !IsLivingHuman(client) || GetGameTime() >= g_fDotExpires[client]
				|| EntRefToEntIndex(g_iDotRef[client]) == INVALID_ENT_REFERENCE)
				RemoveAimDot(client);
			else
				active = true;
		}
		if (g_fCameraEndAt[client] > 0.0) {
			if (ValidateCameraLinger(client)) {
				UpdateCameraIcon(client);
				active = true;
			}
			else
				StopGuidance(client);
			continue;
		}
		if (g_iRocketIndex[client] == 0)
			continue;
		if (!ValidateGuidance(client)) {
			StopGuidance(client);
			continue;
		}
		if (g_iCameraIconRef[client] != INVALID_ENT_REFERENCE)
			UpdateCameraIcon(client);
		float velocity[3];
		GetEntPropVector(g_iRocketIndex[client], Prop_Data, "m_vecAbsVelocity", velocity);
		if (GetVectorLength(velocity) < 1.0) {
			if (BeginCameraLinger(client))
				active = true;
			else
				StopGuidance(client);
			continue;
		}
		active = true;
	}
	if (!active) {
		g_hWatchdog = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public MRESReturn Detour_KeepLauncher_Post(int weapon, DHookReturn result) {
	if (!g_bEnabled || weapon <= MaxClients || !IsValidEntity(weapon))
		return MRES_Ignored;
	int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	if (client < 1 || client > MaxClients || g_iLauncherIndex[client] != weapon)
		return MRES_Ignored;
	// Keep the empty launcher through the linger so native auto-switch does not end the view early.
	if (!(g_fCameraEndAt[client] > 0.0 ? ValidateCameraLinger(client) : ValidateGuidance(client))) {
		StopGuidance(client);
		return MRES_Ignored;
	}
	if (!result.Value)
		return MRES_Ignored;
	g_iKept++;
	result.Value = false;
	return MRES_Override;
}

public MRESReturn Detour_Flight_Post(int rocket) {
	if (!g_bEnabled || rocket <= MaxClients || !IsValidEntity(rocket))
		return MRES_Ignored;
	int client = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
	if (client < 1 || client > MaxClients || g_iRocketIndex[client] != rocket)
		return MRES_Ignored;
	if (!ValidateGuidance(client)) {
		StopGuidance(client);
		return MRES_Ignored;
	}

	float now = GetGameTime();
	float elapsed = now - g_fLastUpdate[client];
	g_fLastUpdate[client] = now;
	if (elapsed <= 0.0)
		return MRES_Ignored;
	if (elapsed > 0.1)
		elapsed = 0.1;
	if (!g_bCameraFlight[client] && now >= g_fNextAim[client]) {
		UpdateAimPoint(client);
		g_fNextAim[client] = now + AIM_INTERVAL;
	}

	float velocity[3], origin[3], desired[3], direction[3], angles[3];
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", velocity);
	float speed = GetVectorLength(velocity);
	if (speed < 1.0) {
		if (!BeginCameraLinger(client))
			StopGuidance(client);
		return MRES_Ignored;
	}
	GetEntPropVector(rocket, Prop_Data, "m_vecAbsOrigin", origin);
	if (g_bCameraFlight[client])
		GetAngleVectors(g_fCameraAim[client], desired, NULL_VECTOR, NULL_VECTOR);
	else {
		MakeVectorFromPoints(origin, g_fAimPoint[client], desired);
		if (NormalizeVector(desired, desired) < 1.0)
			return MRES_Ignored;
	}
	NormalizeVector(velocity, direction);
	TurnTowards(direction, desired, g_fTurnRate * DEG_TO_RAD * elapsed);
	GetVectorAngles(direction, angles);
	if (g_fSpeed > 0.0)
		speed = GetGuidedSpeed();
	ScaleVector(direction, speed);
	// Native collision, damage and think scheduling remain unchanged.
	TeleportEntity(rocket, NULL_VECTOR, angles, direction);
	if (g_bCameraFlight[client])
		UpdateRocketCamera(client, rocket, angles);
	g_iSteered++;
	return MRES_Ignored;
}

bool UpdateAimPoint(int client, float dotLife = 0.2) {
	float eye[3], angles[3], direction[3], endpoint[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	for (int axis = 0; axis < 3; axis++)
		endpoint[axis] = eye[axis] + direction[axis] * AIM_DISTANCE;
	Handle trace = TR_TraceRayFilterEx(eye, endpoint, MASK_SHOT, RayType_EndPoint, Trace_Aim, client);
	TR_GetEndPosition(g_fAimPoint[client], trace);
	bool sent = ShowAimDot(client, trace, dotLife);
	delete trace;
	return sent;
}

bool ShowAimDot(int client, Handle trace, float life) {
	g_iDotAttempts++;
	if (!g_bAimDot || g_iAimDotModel <= 0 || !TR_DidHit(trace) || TR_StartSolid(trace) || TR_AllSolid(trace)
		|| (TR_GetSurfaceFlags(trace) & (SURF_SKY | SURF_SKY2D)) != 0) {
		RemoveAimDot(client);
		return false;
	}

	float position[3], normal[3];
	TR_GetPlaneNormal(trace, normal);
	// Offset only the visual from the surface; keep the actual guidance target unchanged.
	for (int axis = 0; axis < 3; axis++)
		position[axis] = g_fAimPoint[client][axis] + normal[axis] * 2.0;
	int sprite = EntRefToEntIndex(g_iDotRef[client]);
	if (sprite == INVALID_ENT_REFERENCE) {
		sprite = CreateEntityByName("env_sprite");
		if (sprite == -1)
			return false;
		DispatchKeyValue(sprite, "model", AIM_DOT_MATERIAL);
		DispatchKeyValue(sprite, "spawnflags", "1");
		DispatchKeyValue(sprite, "scale", "0.6");
		DispatchKeyValue(sprite, "rendermode", "5");
		DispatchKeyValue(sprite, "rendercolor", "255 0 0");
		DispatchKeyValue(sprite, "renderamt", "255");
		DispatchKeyValueVector(sprite, "origin", position);
		g_iDotRef[client] = EntIndexToEntRef(sprite);
		SDKHook(sprite, SDKHook_SetTransmit, OnAimDotTransmit);
		if (!DispatchSpawn(sprite)) {
			RemoveAimDot(client);
			return false;
		}
		SetEntPropEnt(sprite, Prop_Send, "m_hOwnerEntity", client);
		SetEntityRenderMode(sprite, RENDER_TRANSADD);
		SetEntityRenderColor(sprite, 255, 0, 0, 255);
	}
	TeleportEntity(sprite, position, NULL_VECTOR, NULL_VECTOR);
	g_fDotExpires[client] = GetGameTime() + life;
	if (g_hWatchdog == null)
		g_hWatchdog = CreateTimer(0.1, Timer_Watchdog, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	g_iDotSent++;
	return true;
}

public Action OnAimDotTransmit(int sprite, int client) {
	if (!IsLivingHuman(client) || EntRefToEntIndex(g_iDotRef[client]) != sprite)
		return Plugin_Handled;
	return g_bAimDot && GetGameTime() < g_fDotExpires[client] ? Plugin_Continue : Plugin_Handled;
}

public Action Command_IconTest(int client, int args) {
	if (!IsLivingHuman(client)) {
		ReplyToCommand(client, "[Guided Rockets] Run this alive in game.");
		return Plugin_Handled;
	}
	if (g_iRocketIndex[client] != 0 || g_iCameraIndex[client] != 0 || g_fCameraEndAt[client] > 0.0) {
		ReplyToCommand(client, "[Guided Rockets] Release rocket guidance before testing the icon.");
		return Plugin_Handled;
	}
	char type[16] = "rpg";
	if (args > 0)
		GetCmdArg(1, type, sizeof(type));
	if (StrEqual(type, "off", false)) {
		RemoveCameraIcon(client);
		ReplyToCommand(client, "[Guided Rockets] Test icon removed.");
		return Plugin_Handled;
	}
	bool at4 = StrEqual(type, "at4", false);
	if (args > 1 || (!at4 && !StrEqual(type, "rpg", false))) {
		ReplyToCommand(client, "[Guided Rockets] Usage: sm_guidedrockets_icontest [rpg|at4|off]");
		return Plugin_Handled;
	}
	if (!CreateLauncherIcon(client, at4)) {
		ReplyToCommand(client, "[Guided Rockets] Could not create the test icon. Check material precaching and entity availability.");
		return Plugin_Handled;
	}
	g_fIconTestEndAt[client] = GetGameTime() + 10.0;
	if (g_hWatchdog == null)
		g_hWatchdog = CreateTimer(0.1, Timer_Watchdog, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	ReplyToCommand(client, "[Guided Rockets] %s icon above you for 10 seconds. Use third person to see it yourself.", at4 ? "AT4" : "RPG");
	return Plugin_Handled;
}

public Action Command_DotTest(int client, int args) {
	if (!IsLivingHuman(client)) {
		ReplyToCommand(client, "[Guided Rockets] Run this alive in game while aiming at a nearby wall.");
		return Plugin_Handled;
	}
	if (UpdateAimPoint(client, 3.0))
		ReplyToCommand(client, "[Guided Rockets] Created a 3-second red dot at your aim point, visible only to you.");
	else
		ReplyToCommand(client, "[Guided Rockets] Dot not sent. Check sm_guidedrockets_dot 1 and aim at a solid non-sky surface. Sprite index: %d.", g_iAimDotModel);
	return Plugin_Handled;
}

public bool Trace_Aim(int entity, int contentsMask, any client) {
	if (entity == client || entity == g_iRocketIndex[client] || entity == g_iLauncherIndex[client])
		return false;
	if (entity > MaxClients && IsValidEntity(entity) && HasEntProp(entity, Prop_Send, "m_hOwnerEntity"))
		return GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") != client;
	return true;
}

void TurnTowards(float direction[3], const float desired[3], float maxAngle) {
	float dot = GetVectorDotProduct(direction, desired);
	if (dot > 1.0)
		dot = 1.0;
	else if (dot < -1.0)
		dot = -1.0;
	float angle = ArcCosine(dot);
	if (angle <= maxAngle) {
		for (int axis = 0; axis < 3; axis++)
			direction[axis] = desired[axis];
		return;
	}

	float tangent[3];
	for (int axis = 0; axis < 3; axis++)
		tangent[axis] = desired[axis] - direction[axis] * dot;
	// A directly-behind target has no unique turn plane; choose a stable perpendicular.
	if (NormalizeVector(tangent, tangent) < 0.0001) {
		float basis[3];
		if (FloatAbs(direction[2]) < 0.9)
			basis[2] = 1.0;
		else
			basis[1] = 1.0;
		GetVectorCrossProduct(direction, basis, tangent);
		NormalizeVector(tangent, tangent);
	}
	float cosine = Cosine(maxAngle);
	float sine = Sine(maxAngle);
	for (int axis = 0; axis < 3; axis++)
		direction[axis] = direction[axis] * cosine + tangent[axis] * sine;
	NormalizeVector(direction, direction);
}

public Action Command_Status(int client, int args) {
	ReplyToCommand(client, "[Guided Rockets] Damage diagnostics: %s (sm_guidedrockets_debug_damage).", g_bDamageDebug ? "ON" : "OFF");
	int active;
	for (int player = 1; player <= MaxClients; player++)
		if (g_iRocketIndex[player] != 0 && ValidateGuidance(player))
			active++;
	ReplyToCommand(client, "[Guided Rockets] v%s | %s | turn %.0f deg/s | max %.1fs | active %d", PL_VERSION, g_bEnabled ? "ON" : "OFF", g_fTurnRate, g_fMaxTime, active);
	ReplyToCommand(client, "[Guided Rockets] Available modes: Normal | Guided: %s | Guided with camera: %s.", IsRocketModeEnabled(Rocket_Guided) ? "ON" : "OFF", IsRocketModeEnabled(Rocket_Camera) ? "ON" : "OFF");
	ReplyToCommand(client, "[Guided Rockets] Guided speed: %.0f units/s (effective %.0f; 0 = native/rpg-speed-plugin).", g_fSpeed, GetGuidedSpeed());
	ReplyToCommand(client, "[Guided Rockets] Camera offset: %.0f back / %.0f up. Press AIM or switch weapon to exit the camera.", g_fCameraBack, g_fCameraUp);
	ReplyToCommand(client, "[Guided Rockets] Camera position updates: %d.", g_iCameraUpdates);
	ReplyToCommand(client, "[Guided Rockets] Blast calls: %d | body-position redirects: %d | blast depth: %d.", g_iRadiusDamageCalls, g_iBodyDamageRedirects, g_iRadiusDamageDepth);
	ReplyToCommand(client, "[Guided Rockets] Camera end delay: %.1fs (0 = immediate).", g_fCameraEndDelay);
	ReplyToCommand(client, "[Guided Rockets] Shooter-only aim dot: %s.", g_bAimDot && g_iAimDotModel > 0 ? "ON" : "OFF");
	ReplyToCommand(client, "[Guided Rockets] Red dot attempts: %d | updates: %d | sprite index: %d | %s", g_iDotAttempts, g_iDotSent, g_iAimDotModel, AIM_DOT_MATERIAL);
	ReplyToCommand(client, "[Guided Rockets] Since map/load: linked %d | steering updates %d | launcher-removal overrides %d", g_iAttached, g_iSteered, g_iKept);
	if (client > 0)
		ReplyToCommand(client, "[Guided Rockets] Selected: %s | rocket: %d | launcher: %d | camera: %d", g_sModeNames[g_eSelectedMode[client]], EntRefToEntIndex(g_iRocketRef[client]), EntRefToEntIndex(g_iLauncherRef[client]), EntRefToEntIndex(g_iCameraRef[client]));
	return Plugin_Handled;
}
