#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

native bool Drag_IsEntityDragged(int entity);
native void Drag_ForceDrop(int entity);
Handle	g_hFwdRagdollReady = null;

#define TEAM_SPECTATOR	1
#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

// ---- Objective Resource access (read-only) ----
static int  g_iObjResEntity = -1;
static char g_sObjResNetClass[32];

//LUA Healing define values
#define Healthkit_Timer_Tickrate			0.5		// Basic Sound has 0.8 loop
#define Healthkit_Timer_Timeout				300.0	// 5 minutes
#define Healthkit_Radius					120.0
#define Revive_Indicator_Radius				100.0
#define SND_REVIVENOTIFY		"cues/nwi2_generic4.wav"

#define MAX_ENTITIES 2048

// ----------------------------------------------------------------------
// ConVars + cached values
// ----------------------------------------------------------------------
ConVar	g_cvReviveEnabled = null;
bool	g_bReviveEnabled;

ConVar	g_cvFatalChance = null;
float	g_fFatalChance;

ConVar	g_cvFatalHeadChance = null;
float	g_fFatalHeadChance;

ConVar	g_cvFatalLimbDmg = null;
int		g_iFatalLimbDmg;

ConVar	g_cvFatalHeadDmg = null;
int		g_iFatalHeadDmg;

ConVar	g_cvFatalBurnDmg = null;
int		g_iFatalBurnDmg;

ConVar	g_cvFatalExplosiveDmg = null;
int		g_iFatalExplosiveDmg;

ConVar	g_cvFatalChestStomach = null;
int		g_iFatalChestStomach;

ConVar	g_cvReviveDistanceMetric = null;
bool	g_bDistanceFeet;	// true = feet, false = meters

ConVar	g_cvHealAmountMedpack = null;
int		g_iHealAmountMedpack;

ConVar	g_cvHealAmountPaddles = null;
int		g_iHealAmountPaddles;

ConVar	g_cvNonMedicHealAmt = null;
int		g_iNonMedicHealAmt;

ConVar	g_cvNonMedicReviveHp = null;
int		g_iNonMedicReviveHp;

ConVar	g_cvMedicMinorReviveHp = null;
int		g_iMedicMinorReviveHp;

ConVar	g_cvMedicModerateReviveHp = null;
int		g_iMedicModerateReviveHp;

ConVar	g_cvMedicCriticalReviveHp = null;
int		g_iMedicCriticalReviveHp;

ConVar	g_cvMinorWoundDmg = null;
int		g_iMinorWoundDmg;

ConVar	g_cvModerateWoundDmg = null;
int		g_iModerateWoundDmg;

ConVar	g_cvMedicHealSelfMax = null;
int		g_iMedicHealSelfMax;

ConVar	g_cvNonMedicHealSelfMax = null;
int		g_iNonMedicHealSelfMax;

ConVar	g_cvNonMedicMaxHealOther = null;
int		g_iNonMedicMaxHealOther;

ConVar	g_cvMinorReviveTime = null;
int		g_iMinorReviveTime;

ConVar	g_cvModerateReviveTime = null;
int		g_iModerateReviveTime;

ConVar	g_cvCriticalReviveTime = null;
int		g_iCriticalReviveTime;

ConVar	g_cvNonMedicReviveTime = null;
int		g_iNonMedicReviveTime;

ConVar	g_cvMedpackHealthAmount = null;
int		g_iMedpackHealthAmount;

// ----------------------------------------------------------------------
// Runtime state
// ----------------------------------------------------------------------
bool	g_bMapInit;
bool	g_bRoundActive;
bool	g_bReviveActive;

bool	g_bPreRoundInitial = false;
bool	g_bLateLoad = false;

int		g_iBeaconBeam;
int		g_iBeaconHalo;
int		m_hMyWeapons;

Handle	g_hForceRespawn = null;
Handle	g_hGameConfig = null;

// ----------------------------------------------------------------------
// Per-entity state
// ----------------------------------------------------------------------
int		ga_iTimeCheckHeight[MAX_ENTITIES + 1];
int		ga_iHealthPack_Amount[MAX_ENTITIES + 1];
float	ga_fLastHeight[MAX_ENTITIES + 1];
float	ga_fTimeCheck[MAX_ENTITIES + 1];
bool	ga_bHealthkitInit[MAX_ENTITIES + 1];

// ----------------------------------------------------------------------
// Per-player state
// ----------------------------------------------------------------------
int		ga_iReviveRemainingTime[MAXPLAYERS + 1];
int		ga_iReviveNonMedicRemainingTime[MAXPLAYERS + 1];

bool	ga_bHurtFatal[MAXPLAYERS + 1];
int		ga_iClientRagdolls[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iNearestBody[MAXPLAYERS + 1];

int		ga_iTimeReviveCheck[MAXPLAYERS + 1] = {-1, ...};
int		ga_iClientDamageDone[MAXPLAYERS + 1];
int		ga_iPlayerWoundType[MAXPLAYERS + 1];
int		ga_iPlayerWoundTime[MAXPLAYERS + 1];
int		ga_iDeathStance[MAXPLAYERS + 1];

float	ga_fDeadAngle[MAXPLAYERS + 1][3];
float	ga_fRagdollPosition[MAXPLAYERS + 1][3];

// Ragdoll teleport safety (avoid TeleportEntity on ragdolls before physics is ready)
int		g_iOffsPhysicsObject = -1;

int		ga_iPendingRagTeleportRef[MAXPLAYERS + 1];
int		ga_iPendingRagTeleportTries[MAXPLAYERS + 1];
float	ga_fPendingRagTeleportPos[MAXPLAYERS + 1][3];
float	ga_fPendingRagTeleportAng[MAXPLAYERS + 1][3];
float	ga_fPendingRagTeleportVel[MAXPLAYERS + 1][3];

bool	ga_bBeingRevivedByMedic[MAXPLAYERS + 1];
bool	ga_bRevivedByMedic[MAXPLAYERS + 1];
bool	ga_bPlayerSelectNewClass[MAXPLAYERS + 1];
bool	ga_bPlayerPickSquad[MAXPLAYERS + 1];

char	ga_sPlayerBGroups[MAXPLAYERS + 1][32];
char	ga_sClientLastClassString[MAXPLAYERS + 1][64];

// Revive/heal stats
int		ga_iStatRevives[MAXPLAYERS + 1];
int		ga_iStatHeals[MAXPLAYERS + 1];
int		ga_iTotalHP[MAXPLAYERS + 1];

// Shared colors (avoid inline array literals for older compilers)
int		g_iColorReviveRing[4];
int		g_iColorHealRing[4];

public Plugin myinfo = {
	name = "medic",
	author = "",
	description = "Jared Ballou, Daimyo, naong, Lua, Nullifidian & ChatGPT",
	version = "1.0.5",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	MarkNativeAsOptional("Drag_IsEntityDragged");
	MarkNativeAsOptional("Drag_ForceDrop");

	CreateNative("Medic_GetClientRagdollRef", Native_Medic_GetClientRagdollRef);
	CreateNative("Medic_IsClientMedic", Native_Medic_IsClientMedic);

	return APLRes_Success;
}

public any Native_Medic_GetClientRagdollRef(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
		return INVALID_ENT_REFERENCE;

	return ga_iClientRagdolls[client];
}

public any Native_Medic_IsClientMedic(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
		return false;

	return (StrContains(ga_sClientLastClassString[client], "medic", false) != -1);
}

public void OnPluginStart() {
	RegPluginLibrary("bm_medic");

	if (g_hFwdRagdollReady == null)
		g_hFwdRagdollReady = CreateGlobalForward("Medic_OnRagdollReady", ET_Ignore, Param_Cell, Param_Cell);

	
	// Shared colors
	g_iColorReviveRing[0] = 255;
	g_iColorReviveRing[1] = 0;
	g_iColorReviveRing[2] = 0;
	g_iColorReviveRing[3] = 255;

	g_iColorHealRing[0] = 0;
	g_iColorHealRing[1] = 200;
	g_iColorHealRing[2] = 0;
	g_iColorHealRing[3] = 75;

	for (int i = 1; i <= MaxClients; i++)
		ClearPendingRagTeleport(i);

	if ((m_hMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons")) == -1)
		SetFailState("Fatal Error: Unable to find property offset \"CBasePlayer::m_hMyWeapons\" !");

	if ((g_hGameConfig = LoadGameConfigFile("insurgency.games")) == INVALID_HANDLE)
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(g_hGameConfig, SDKConf_Signature, "ForceRespawn");
	if ((g_hForceRespawn = EndPrepSDKCall()) == INVALID_HANDLE)
		SetFailState("Fatal Error: Unable to find signature for \"ForceRespawn\"!");

	SetupConVars();

	RegConsoleCmd("fatal", cmd_fatal, "Set your death to fatal");

	AddCommandListener(cmdListener, "kill");
	AddCommandListener(ChangeLevelListener, "changelevel");
	AddCommandListener(ChangeLevelListener, "map");
	AddCommandListener(ChangeLevelListener, "sm_map");

	HookEvent("grenade_thrown", Event_GrenadeThrown);
	HookEvent("player_hurt", Event_PlayerHurt_Pre, EventHookMode_Pre);
	HookEvent("round_end", Event_RoundEnd_Pre, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_spawn", Event_Spawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_pick_squad", Event_PlayerPickSquad_Post, EventHookMode_Post);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_connect", Event_PlayerConnect);
	HookEvent("game_end", Event_GameEnd, EventHookMode_PostNoCopy);

	//Load localization file
	LoadTranslations("nearest_player.phrases.txt");

	if (g_bLateLoad)
		g_bRoundActive = true;

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart() {
	PrecacheFiles();

	CreateTimer(5.0, Timer_MapStart, _, TIMER_FLAG_NO_MAPCHANGE);
	if (!g_bLateLoad)
		g_bPreRoundInitial = true;
}

public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	g_bReviveActive = false;
	g_bRoundActive = false;
	g_bLateLoad = false;
}

Action Timer_MapStart(Handle timer) {
	if (g_bMapInit) return Plugin_Stop;
	g_bMapInit = true;

	g_bReviveActive = g_bLateLoad;
	CreateTimer(1.0, Timer_ReviveMonitor, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.5, Timer_MedicMonitor, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.1, Timer_NearestBody, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, Timer_PlayerStatus, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public void OnMapEnd() {
	g_bMapInit = false;
	g_bRoundActive = false;
	g_bReviveActive = false;
	g_bLateLoad = false;
	g_iObjResEntity = -1;
	g_sObjResNetClass[0] = '\0';
}
public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients || entity > MAX_ENTITIES)
		return;

	if (!ga_bHealthkitInit[entity] && ga_iHealthPack_Amount[entity] == 0)
		return;

	ga_bHealthkitInit[entity] = false;
	ga_iHealthPack_Amount[entity] = 0;
	ga_fLastHeight[entity] = 0.0;
	ga_fTimeCheck[entity] = 0.0;
	ga_iTimeCheckHeight[entity] = 0;
}


public void OnClientPostAdminCheck(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	ga_bHurtFatal[client] = false;
	ClearPendingRagTeleport(client);
	ResetMedicStats(client);
}

// Check and inform player status
Action Timer_PlayerStatus(Handle timer) {
	if (!g_bRoundActive) return Plugin_Continue;

	char woundType[20];
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client))
			continue;
		if (!ga_bPlayerPickSquad[client]
			|| IsPlayerAlive(client)
			|| GetClientTeam(client) != TEAM_SECURITY
			|| !g_bReviveActive
			|| !g_bRoundActive
			|| ga_bPlayerSelectNewClass[client])
			continue;

		if      (ga_iPlayerWoundType[client] == 0) strcopy(woundType, sizeof(woundType), "MINORLY WOUNDED");
		else if (ga_iPlayerWoundType[client] == 1) strcopy(woundType, sizeof(woundType), "MODERATELY WOUNDED");
		else if (ga_iPlayerWoundType[client] == 2) strcopy(woundType, sizeof(woundType), "CRITICALLY WOUNDED");
		else                                        strcopy(woundType, sizeof(woundType), "WOUNDED");

		if (ga_bHurtFatal[client])
			PrintCenterText(client, "You were fatally killed for %i damage and must wait til next objective to spawn", ga_iClientDamageDone[client]);
		else if (!ga_bHurtFatal[client])
			PrintCenterText(client, "[You're %s for %d damage]..wait patiently for a medic..do NOT mic/chat spam!", woundType, ga_iClientDamageDone[client]);
	}
	return Plugin_Continue;
}

public Action Event_Spawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SECURITY)
		return Plugin_Continue;

	RemoveRagdoll(client);
	ClearPendingRagTeleport(client);
	ga_bHurtFatal[client] = false;
	ga_bPlayerSelectNewClass[client] = false;
	ga_bBeingRevivedByMedic[client] = false;
	ga_iTimeReviveCheck[client] = -1;
	return Plugin_Continue;
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients)
		return Plugin_Continue;

	ga_bPlayerPickSquad[client] = false;
	ga_bHurtFatal[client] = false;
	return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients) {
		ga_bPlayerPickSquad[client] = false;
		ga_sClientLastClassString[client][0] = '\0';

		RemoveRagdoll(client);
	}
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	g_bLateLoad = false;
	g_bReviveActive = false;

	int iPreRoundFirst = GetConVarInt(FindConVar("mp_timer_preround_first"));
	int iPreRound = GetConVarInt(FindConVar("mp_timer_preround"));
	if (g_bPreRoundInitial) {
		CreateTimer(float(iPreRoundFirst), PreReviveTimer, _, TIMER_FLAG_NO_MAPCHANGE);
		iPreRoundFirst = iPreRoundFirst + 5;
		g_bPreRoundInitial = false;
	} else
		CreateTimer(float(iPreRound), PreReviveTimer, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

Action PreReviveTimer(Handle timer) {
	g_bRoundActive = true;
	g_bReviveActive = true;
	return Plugin_Stop;
}

public Action Event_RoundEnd_Pre(Event event, const char[] name, bool dontBroadcast) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client)
			|| IsFakeClient(client)
			|| GetClientTeam(client) != TEAM_SECURITY)
			continue;

		if ((ga_iStatRevives[client] > 0 || ga_iStatHeals[client] > 0) && StrContains(ga_sClientLastClassString[client], "medic", false) > -1)
			PrintToChatAll("\x070088cc%N\x01 - Heals: \x0700cc44%d\x01  HP: \x0700cc44%d\x01  Revives: \x0700cc44%d", client, ga_iStatHeals[client], ga_iTotalHP[client], ga_iStatRevives[client]);
		ResetMedicStats(client);
	}
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	g_bReviveActive = false;
	int ent = MaxClients + 1;
	while ((ent = FindEntityByClassname(ent, "healthkit")) != -1)
		SafeKillIdx(ent);
	g_bRoundActive = false;
	return Plugin_Continue;
}

public Action Event_PlayerPickSquad_Post(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	char class_template[64];
	event.GetString("class_template", class_template, sizeof(class_template));
	strcopy(ga_sClientLastClassString[client], sizeof(ga_sClientLastClassString[]), class_template);

	if (client == 0 || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	ga_bPlayerPickSquad[client] = true;

	// If player changed squad and remain ragdoll
	int team = GetClientTeam(client);
	if (!IsPlayerAlive(client) && !ga_bHurtFatal[client] && team == TEAM_SECURITY) {
		RemoveRagdoll(client);
		ga_bHurtFatal[client] = true;
		ga_bPlayerSelectNewClass[client] = true;
	}

	return Plugin_Continue;
}

public Action Event_PlayerHurt_Pre(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));

	if (!IsClientInGame(victim) || IsFakeClient(victim))
		return Plugin_Continue;

	int	attacker = GetClientOfUserId(event.GetInt("attacker")),
		victimHealth = event.GetInt("health"),
		dmg_taken = event.GetInt("dmg_health");

	if (dmg_taken < victimHealth)
		return Plugin_Continue;

	ga_iDeathStance[victim] = GetEntProp(victim, Prop_Send, "m_iCurrentStance");

	if (g_fFatalChance > 0.0) {
		int hitgroup = event.GetInt("hitgroup");
		ga_iClientDamageDone[victim] = dmg_taken;	// Update last damage (related to 'hurt_fatal')
		char weapon[32];
		event.GetString("weapon", weapon, sizeof(weapon));
		float fRandom = GetRandomFloat(0.0, 1.0);	// Get fatal chance
		//PrintToChatAll("victim %d | victimHealth %d | dmg_taken %d | hitgroup %d | attacker %d | weapon %s",victim,victimHealth,dmg_taken,hitgroup,attacker, weapon);
		switch (hitgroup) {
			case 0: {
				if (!attacker) {	//fatal chance from anyhting that doesn't broadcast attacker = entityflame(burn plugin) & death from fall
					if (fRandom <= 0.25)
						ga_bHurtFatal[victim] = true;
				}
				//fire
				else if ((strcmp(weapon, "grenade_anm14", false) == 0)
				|| (strcmp(weapon, "grenade_molotov", false) == 0)
				|| (strcmp(weapon, "grenade_m203_incid", false) == 0)
				|| (strcmp(weapon, "grenade_gp25_incid", false) == 0)
				|| (strcmp(weapon, "grenade_m79_incen", false) == 0)) {
					if (dmg_taken >= g_iFatalBurnDmg && (fRandom <= g_fFatalChance)) {
						ga_bHurtFatal[victim] = true;	// Hurt fatally
					}
				}
				//explosive
				else if ((strcmp(weapon, "grenade_m67", false) == 0)
				|| (strcmp(weapon, "grenade_f1", false) == 0)
				|| (strcmp(weapon, "grenade_ied", false) == 0)
				|| (strcmp(weapon, "grenade_c4", false) == 0)
				|| (strcmp(weapon, "rocket_rpg7", false) == 0)
				|| (strcmp(weapon, "rocket_at4", false) == 0)
				|| (strcmp(weapon, "grenade_gp25_he", false) == 0)
				|| (strcmp(weapon, "grenade_m203_he", false) == 0)
				|| (strcmp(weapon, "grenade_m26a2", false) == 0)
				|| (strcmp(weapon, "grenade_c4_radius", false) == 0)
				|| (strcmp(weapon, "grenade_ied_radius", false) == 0)
				|| (strcmp(weapon, "grenade_ied_gunshot", false) == 0)
				|| (strcmp(weapon, "grenade_ied_fire", false) == 0)
				|| (strcmp(weapon, "grenade_ied_fire_bomber", false) == 0)
				|| (strcmp(weapon, "grenade_m79", false) == 0)) {
					if (dmg_taken >= g_iFatalExplosiveDmg && (fRandom <= g_fFatalChance)) {
						ga_bHurtFatal[victim] = true;	// Hurt fatally
					}
				}
			}
			case 1: {	// Headshot
				if (dmg_taken >= g_iFatalHeadDmg
				&& fRandom <= g_fFatalHeadChance
				&& attacker > 0
				&& IsClientInGame(attacker)
				&& GetClientTeam(attacker) != TEAM_SECURITY) {
					ga_bHurtFatal[victim] = true;	// Hurt fatally
				}
			}
			case 2, 3: {	//Chest
				if (dmg_taken >= g_iFatalChestStomach && (fRandom <= g_fFatalChance)) {
					ga_bHurtFatal[victim] = true;	// Hurt fatally
				}
			}
			case 4, 5, 6, 7: {	// Limbs
				if (dmg_taken >= g_iFatalLimbDmg && (fRandom <= g_fFatalChance)) {
					ga_bHurtFatal[victim] = true;	// Hurt fatally
				}
			}
		}

		if (!ga_bHurtFatal[victim])	{	//Track wound type (minor, moderate, critical)
			if (dmg_taken <= g_iMinorWoundDmg) {
				ga_iPlayerWoundTime[victim] = g_iMinorReviveTime;
				ga_iPlayerWoundType[victim] = 0;
			}
			else if (dmg_taken > g_iMinorWoundDmg && dmg_taken <= g_iModerateWoundDmg) {
				ga_iPlayerWoundTime[victim] = g_iModerateReviveTime;
				ga_iPlayerWoundType[victim] = 1;
			}
			else if (dmg_taken > g_iModerateWoundDmg) {
				ga_iPlayerWoundTime[victim] = g_iCriticalReviveTime;
				ga_iPlayerWoundType[victim] = 2;
			}
		}
		else {
			ga_iPlayerWoundTime[victim] = -1;
			ga_iPlayerWoundType[victim] = -1;
		}
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || !IsClientInGame(victim)) return Plugin_Continue;

	int team = GetClientTeam(victim);

	int dmg_taken = event.GetInt("damagebits");
	if (dmg_taken <= 0) {
		ga_iPlayerWoundTime[victim] = g_iMinorReviveTime;
		ga_iPlayerWoundType[victim] = 0;
	}

	if (g_bReviveEnabled && team == TEAM_SECURITY) {
		char sBuffer[32];
		IntToString(GetEntProp(victim, Prop_Send, "m_nBody"), sBuffer, sizeof(sBuffer));
		strcopy(ga_sPlayerBGroups[victim], sizeof(ga_sPlayerBGroups[]), sBuffer);

		int iWeapon;
		for (int offset = 0; offset < 128; offset += 4) {
			iWeapon = GetEntDataEnt2(victim, m_hMyWeapons + offset);
			if (iWeapon < 0)
				continue;
			char sWeapon[32];
			GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
			if (StrContains(sWeapon, "weapon_healthkit", false) != -1
			&& IsValidEntity(iWeapon)) {
				RemovePlayerItem(victim, iWeapon);
				SafeKillIdx(iWeapon);
			}
		}

		if (g_bReviveActive && g_bRoundActive) {
			// Convert ragdoll
			GetClientAbsAngles(victim, ga_fDeadAngle[victim]);	// Get current angles
			if (ga_iDeathStance[victim] == 2)
				ga_fDeadAngle[victim][0] += -90.0;
			RequestFrame(Frame_ConvertDeleteRagdoll, GetClientUserId(victim));
		}
	}

	char woundType[20];

	if      (ga_iPlayerWoundType[victim] == 0) FormatEx(woundType, sizeof(woundType), "MINORLY WOUNDED");
	else if (ga_iPlayerWoundType[victim] == 1) FormatEx(woundType, sizeof(woundType), "MODERATELY WOUNDED");
	else if (ga_iPlayerWoundType[victim] == 2) FormatEx(woundType, sizeof(woundType), "CRITICALLY WOUNDED");
	else                                        FormatEx(woundType, sizeof(woundType), "WOUNDED");

	if (g_fFatalChance > 0.0 && ga_bHurtFatal[victim]) {
		PrintHintText(victim, "You were fatally killed for %i damage", ga_iClientDamageDone[victim]);
		PrintToChat(victim, "\x01You were \x070088ccfatally\x01 killed for \x070088cc%i\x01 damage", ga_iClientDamageDone[victim]);
	} else {
		PrintHintText(victim, "You're %s for %i damage, call a medic for revive!", woundType, ga_iClientDamageDone[victim]);
		PrintToChat(victim, "\x01You're \x070088cc%s\x01 for \x070088cc%i\x01 damage, call a medic for revive!", woundType, ga_iClientDamageDone[victim]);
	}
	return Plugin_Continue;
}

// Convert dead body to new ragdoll
void Frame_ConvertDeleteRagdoll(int userid) {
	int client = GetClientOfUserId(userid);
	if (IsClientInGame(client)
		&& g_bRoundActive
		&& !IsPlayerAlive(client)
		&& (
			GetClientTeam(client) == TEAM_SECURITY
			|| GetClientTeam(client) == TEAM_INSURGENT
			)
		&& HasEntProp(client, Prop_Send, "m_hRagdoll")) {

		int clientRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (clientRagdoll > 0 && IsValidEntity(clientRagdoll) && g_bReviveActive) {
				if (!ga_bHurtFatal[client]) {
					float	fVelocity[3],
							fOrigin[3];
					GetEntPropVector(clientRagdoll, Prop_Send, "m_vecRagdollOrigin", fOrigin);
					GetEntPropVector(clientRagdoll, Prop_Send, "m_vecForce", fVelocity);

					int tempRag = CreateEntityByName("prop_ragdoll");
					if (IsValidEntity(tempRag)) {
						ga_iClientRagdolls[client] = EntIndexToEntRef(tempRag);
						char sBuffer[64];
						GetClientModel(client, sBuffer, sizeof(sBuffer));
						SetEntityModel(tempRag, sBuffer);
						// Give custom ragdoll name for each client, this way other plugins can search for targetname to modify behavior
						FormatEx(sBuffer, sizeof(sBuffer), "playervital_ragdoll_%i", client);
						DispatchKeyValue(tempRag, "targetname", sBuffer);
						DispatchKeyValue(tempRag, "body", ga_sPlayerBGroups[client]);
		/*
						Format(sBuffer, sizeof(sBuffer), "%f %f %f", g_fDeadPosition[client][0], g_fDeadPosition[client][1], g_fDeadPosition[client][2] += 15.0);
						DispatchKeyValue(tempRag, "Origin", sBuffer);

						Format(sBuffer, sizeof(sBuffer), "%f %f %f", ga_fDeadAngle[client][0] += -90.0, ga_fDeadAngle[client][1], ga_fDeadAngle[client][2]);
						DispatchKeyValue(tempRag, "Angles", sBuffer);
		*/
						DispatchSpawn(tempRag);

						ActivateEntity(tempRag);

						//must be after DispatchSpawn
						DispatchKeyValue(tempRag, "CollisionGroup", "17");	//COLLISION_GROUP_PUSHAWAY

						fOrigin[2] += 50.0;
						VecCopy(fOrigin, ga_fRagdollPosition[client]);

						ga_iPendingRagTeleportRef[client] = EntIndexToEntRef(tempRag);
						ga_iPendingRagTeleportTries[client] = 0;
						VecCopy(fOrigin, ga_fPendingRagTeleportPos[client]);
						VecCopy(ga_fDeadAngle[client], ga_fPendingRagTeleportAng[client]);
						VecCopy(fVelocity, ga_fPendingRagTeleportVel[client]);

						RequestFrame(Frame_TeleportPendingRagdoll, userid);
						ga_iReviveRemainingTime[client] = ga_iPlayerWoundTime[client];
						ga_iReviveNonMedicRemainingTime[client] = g_iNonMedicReviveTime;
					}
				}
				SafeKillIdx(clientRagdoll);
				clientRagdoll = INVALID_ENT_REFERENCE;
		}
	}
}

bool hasCorrectWeapon(const char[] sWeapon, bool melee = true) {
	if (melee) {
		if (StrContains(sWeapon, "weapon_defib", false) != -1
			|| StrContains(sWeapon, "weapon_knife", false) != -1
			|| StrContains(sWeapon, "weapon_kabar", false) != -1
			|| StrContains(sWeapon, "weapon_katana", false) != -1)
			// player has one of the above weapons
			return true;
	} else {
		if (StrContains(sWeapon, "weapon_healthkit", false) != -1)
			// player has one of the above
			return true;
	}
	return false;
}

static bool EntHasPhysicsObject(int ent) {
	if (ent <= MaxClients || !IsValidEntity(ent))
		return false;

	if (g_iOffsPhysicsObject == -1) {
		g_iOffsPhysicsObject = FindDataMapInfo(ent, "m_pPhysicsObject");
		if (g_iOffsPhysicsObject == -1)
			g_iOffsPhysicsObject = -2;
	}

	if (g_iOffsPhysicsObject == -2)
		return true;

	return (GetEntData(ent, g_iOffsPhysicsObject) != 0);
}

static void ClearPendingRagTeleport(int client) {
	ga_iPendingRagTeleportRef[client] = INVALID_ENT_REFERENCE;
	ga_iPendingRagTeleportTries[client] = 0;

	ga_fPendingRagTeleportPos[client][0] = 0.0;
	ga_fPendingRagTeleportPos[client][1] = 0.0;
	ga_fPendingRagTeleportPos[client][2] = 0.0;

	ga_fPendingRagTeleportAng[client][0] = 0.0;
	ga_fPendingRagTeleportAng[client][1] = 0.0;
	ga_fPendingRagTeleportAng[client][2] = 0.0;

	ga_fPendingRagTeleportVel[client][0] = 0.0;
	ga_fPendingRagTeleportVel[client][1] = 0.0;
	ga_fPendingRagTeleportVel[client][2] = 0.0;
}

void Frame_TeleportPendingRagdoll(int userid) {
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients)
		return;

	int ref = ga_iPendingRagTeleportRef[client];
	if (ref == INVALID_ENT_REFERENCE)
		return;

	int ent = EntRefToEntIndex(ref);
	if (ent == INVALID_ENT_REFERENCE || ent <= MaxClients || !IsValidEntity(ent)) {
		ClearPendingRagTeleport(client);
		return;
	}

	if (!EntHasPhysicsObject(ent)) {
		if (++ga_iPendingRagTeleportTries[client] >= 10) {
			ClearPendingRagTeleport(client);
			return;
		}

		RequestFrame(Frame_TeleportPendingRagdoll, userid);
		return;
	}

	TeleportEntity(ent, ga_fPendingRagTeleportPos[client], ga_fPendingRagTeleportAng[client], ga_fPendingRagTeleportVel[client]);
	AcceptEntityInput(ent, "Wake");
	
	if (g_hFwdRagdollReady != null) {
		Call_StartForward(g_hFwdRagdollReady);
		Call_PushCell(client);
		Call_PushCell(EntIndexToEntRef(ent));
		Call_Finish();
	}

	ClearPendingRagTeleport(client);
}

void RemoveRagdoll(int client) {
	if (client < 1 || client > MaxClients) return;

	ClearPendingRagTeleport(client);

	int ref = ga_iClientRagdolls[client];
	if (ref == INVALID_ENT_REFERENCE) return;

	int entity = EntRefToEntIndex(ref);

	ga_iClientRagdolls[client] = INVALID_ENT_REFERENCE;

	if (entity > MaxClients && IsValidEntity(entity)) {
		bool dragged = false;
		if (GetFeatureStatus(FeatureType_Native, "Drag_IsEntityDragged") == FeatureStatus_Available)
			dragged = Drag_IsEntityDragged(entity);

		if (dragged && GetFeatureStatus(FeatureType_Native, "Drag_ForceDrop") == FeatureStatus_Available)
			Drag_ForceDrop(entity);

		SafeKillRef(ref);
	}
}

void RespawnPlayerRevive(int client) {	// Revive player
	if (!IsClientInGame(client)) return;
	if (IsPlayerAlive(client) || !g_bRoundActive) return;

	SDKCall(g_hForceRespawn, client);	// Call forcerespawn fucntion
	SetEntProp(client, Prop_Send, "m_iDesiredStance", 2);	//spawn player in prone position

	int iHealth = GetClientHealth(client);
	if (ga_bRevivedByMedic[client]) {
		if (ga_iPlayerWoundType[client] == 0)
			iHealth = g_iMedicMinorReviveHp;
		else if (ga_iPlayerWoundType[client] == 1)
			iHealth = g_iMedicModerateReviveHp;
		else if (ga_iPlayerWoundType[client] == 2)
			iHealth = g_iMedicCriticalReviveHp;
	} else
		iHealth = g_iNonMedicReviveHp;
	SetEntityHealth(client, iHealth);

	RemoveRagdoll(client);	//Remove network ragdoll

	RespawnPlayerRevivePost(client);
}

void RespawnPlayerRevivePost(int client) {
	TeleportEntity(client, ga_fRagdollPosition[client], NULL_VECTOR, NULL_VECTOR);
	// Reset ragdoll position
	ga_fRagdollPosition[client][0] = 0.0;
	ga_fRagdollPosition[client][1] = 0.0;
	ga_fRagdollPosition[client][2] = 0.0;
}

// Handles reviving for medics and non-medics
Action Timer_ReviveMonitor(Handle timer) {
	if (!g_bRoundActive)
		return Plugin_Continue;

	float	flalivePlayerPosition[3],
			fDistance,
			fReviveDistance = 80.0;

	int		deadPlayer,
			deadPlayerRagdoll,
			ActiveWeapon,
			CurrentTime;

	char	sWeapon[32],
			woundType[20];

	for (int alivePlayer = 1; alivePlayer <= MaxClients; alivePlayer++) {
		if (!IsClientInGame(alivePlayer) || GetClientTeam(alivePlayer) != TEAM_SECURITY || !IsPlayerAlive(alivePlayer))
			continue;

		deadPlayer = ga_iNearestBody[alivePlayer];
		if (deadPlayer <= 0 || !IsClientInGame(deadPlayer) || IsPlayerAlive(deadPlayer) || ga_bHurtFatal[deadPlayer] || deadPlayer == alivePlayer || GetClientTeam(alivePlayer) != GetClientTeam(deadPlayer))
			continue;

		ActiveWeapon = GetEntPropEnt(alivePlayer, Prop_Data, "m_hActiveWeapon");
		if (ActiveWeapon < 0)
			continue;

		deadPlayerRagdoll = INVALID_ENT_REFERENCE;
		deadPlayerRagdoll = EntRefToEntIndex(ga_iClientRagdolls[deadPlayer]);

		if (deadPlayerRagdoll == INVALID_ENT_REFERENCE || !IsValidEntity(deadPlayerRagdoll))
			continue;

		GetClientAbsOrigin(alivePlayer, flalivePlayerPosition);
		GetEntPropVector(deadPlayerRagdoll, Prop_Data, "m_vecAbsOrigin", ga_fRagdollPosition[deadPlayer]);

		fDistance = GetVectorDistance(ga_fRagdollPosition[deadPlayer], flalivePlayerPosition);

		if (fDistance > fReviveDistance || !ClientCanSeeVector(alivePlayer, ga_fRagdollPosition[deadPlayer], fReviveDistance))
			continue;

		if      (ga_iPlayerWoundType[deadPlayer] == 0) strcopy(woundType, sizeof(woundType), "minor wound");
		else if (ga_iPlayerWoundType[deadPlayer] == 1) strcopy(woundType, sizeof(woundType), "moderate wound");
		else if (ga_iPlayerWoundType[deadPlayer] == 2) strcopy(woundType, sizeof(woundType), "critical wound");
		else                                           strcopy(woundType, sizeof(woundType), "wound");

		GetEdictClassname(ActiveWeapon, sWeapon, sizeof(sWeapon));

		if (StrContains(ga_sClientLastClassString[alivePlayer], "medic", false) != -1) {
			/* I'm a medic */

			if (!hasCorrectWeapon(sWeapon))
				continue;

			if (ga_iReviveRemainingTime[deadPlayer] > 0) {
				PrintHintText(alivePlayer, "Reviving %N in: %i seconds (%s)", deadPlayer, ga_iReviveRemainingTime[deadPlayer], woundType);
				PrintHintText(deadPlayer, "%N is reviving you in: %i seconds (%s)", alivePlayer, ga_iReviveRemainingTime[deadPlayer], woundType);
				ga_iReviveRemainingTime[deadPlayer]--;
				ga_bBeingRevivedByMedic[deadPlayer] = true;
				CurrentTime = GetTime();
				ga_iTimeReviveCheck[deadPlayer] = CurrentTime;
			} else {
				PrintHintText(alivePlayer, "You revived %N from a %s", deadPlayer, woundType);
				PrintHintText(deadPlayer, "%N revived you from a %s", alivePlayer, woundType);

				PlayVictimReviveSound(deadPlayer);
				EmitSoundToAll("weapons/defibrillator/defibrillator_revive.wav", alivePlayer, SNDCHAN_AUTO, _, _, 0.3);

				ga_iStatRevives[alivePlayer]++;

				Check_NearbyMedicsRevive(alivePlayer, deadPlayer);
				ga_bRevivedByMedic[deadPlayer] = true;
				RespawnPlayerRevive(deadPlayer);
			}
		} else {
			/* I'm not a medic */

			if (!hasCorrectWeapon(sWeapon, false))
				continue;

			if (ga_iReviveNonMedicRemainingTime[deadPlayer] > 0) {
				PrintHintText(alivePlayer, "Reviving %N in: %i seconds (%s)", deadPlayer, ga_iReviveNonMedicRemainingTime[deadPlayer], woundType);
				PrintHintText(deadPlayer, "%N is reviving you in: %i seconds (%s)", alivePlayer, ga_iReviveNonMedicRemainingTime[deadPlayer], woundType);
				ga_iReviveNonMedicRemainingTime[deadPlayer]--;
			} else {
				PrintHintText(alivePlayer, "You revived %N from a %s", deadPlayer, woundType);
				PrintHintText(deadPlayer, "%N revived you from a %s", alivePlayer, woundType);

				PlayVictimReviveSound(deadPlayer);
				ga_iStatRevives[alivePlayer]++;

				Check_NearbyMedicsRevive(alivePlayer, deadPlayer);
				ga_bRevivedByMedic[deadPlayer] = false;
				RespawnPlayerRevive(deadPlayer);

				int iAmmoType = GetEntProp(ActiveWeapon, Prop_Data, "m_iPrimaryAmmoType");
				int iAmmo = GetEntProp(alivePlayer, Prop_Data, "m_iAmmo", _, iAmmoType);

				if (iAmmo > 0)
					SetEntProp(alivePlayer, Prop_Send, "m_iAmmo", iAmmo-1, _, iAmmoType);

				if (iAmmo == 1) {
					//RemovePlayerItem(alivePlayer, ActiveWeapon);
					//ChangePlayerWeaponSlot(alivePlayer, 2);
					if (GetPlayerWeaponSlot(alivePlayer, 0) > 0)
						ClientCommand(alivePlayer, "slot1");
					else if (GetPlayerWeaponSlot(alivePlayer, 1) > 0)
						ClientCommand(alivePlayer, "slot2");
				}
			}
		}
	}
	return Plugin_Continue;
}

// Handles medic functions (Inspecting health, healing)
Action Timer_MedicMonitor(Handle timer) {
	if (!g_bRoundActive)
		return Plugin_Continue;

	bool	bCanHealPaddle = false,
			bCanHealMedpack = false;

	float	fReviveDistance = 80.0,
			vecOriginatingPlayer[3],
			vecTargetPlayer[3],
			tDistance;

	int		ActiveWeapon,
			iHealth,
			targetPlayer;

	char	sWeapon[32];

	for (int originatingPlayer = 1; originatingPlayer <= MaxClients; originatingPlayer++) {
		if (!IsClientInGame(originatingPlayer) || !IsPlayerAlive(originatingPlayer) || GetClientTeam(originatingPlayer) != TEAM_SECURITY)
			continue;

		ActiveWeapon = GetEntPropEnt(originatingPlayer, Prop_Data, "m_hActiveWeapon");
		if (ActiveWeapon < 0)
			continue;

		bCanHealPaddle = false;
		bCanHealMedpack = false;

		GetEdictClassname(ActiveWeapon, sWeapon, sizeof(sWeapon));

		if (hasCorrectWeapon(sWeapon)) {
			bCanHealPaddle = true;
			bCanHealMedpack = false;
		}
		if (hasCorrectWeapon(sWeapon, false)) {
			bCanHealPaddle = false;
			bCanHealMedpack = true;
		}

		if (!bCanHealPaddle && !bCanHealMedpack)
			continue;

		if (StrContains(ga_sClientLastClassString[originatingPlayer], "medic", false) != -1) {
			/* I'm a medic */

			targetPlayer = TraceClientViewEntity(originatingPlayer);
			if (targetPlayer > 0 && targetPlayer <= MaxClients && IsClientInGame(targetPlayer) && IsPlayerAlive(targetPlayer) && GetClientTeam(targetPlayer) == TEAM_SECURITY) {

				GetClientAbsOrigin(originatingPlayer, vecOriginatingPlayer);
				GetClientAbsOrigin(targetPlayer, vecTargetPlayer);
				tDistance = GetVectorDistance(vecOriginatingPlayer,vecTargetPlayer);

				iHealth = GetClientHealth(targetPlayer);
				if (tDistance < 750.0)
					PrintHintText(originatingPlayer, "%N\nHP: %i", targetPlayer, iHealth);

				if (tDistance > fReviveDistance
					|| !ClientCanSeeVector(originatingPlayer, vecTargetPlayer, fReviveDistance))
					continue;

				if (iHealth < 100) {
					iHealth += bCanHealPaddle && !bCanHealMedpack ? g_iHealAmountPaddles : g_iHealAmountMedpack;
					ga_iTotalHP[originatingPlayer] += bCanHealPaddle && !bCanHealMedpack ? g_iHealAmountPaddles : g_iHealAmountMedpack;

					if (iHealth >= 100) {
						ga_iTotalHP[originatingPlayer] -= (iHealth - 100);

						ga_iStatHeals[originatingPlayer]++;

						iHealth = 100;
						PrintHintText(targetPlayer, "You were healed by %N (HP: %i)", originatingPlayer, iHealth);
						PrintHintText(originatingPlayer, "You fully healed %N", targetPlayer);
						PrintToChat(originatingPlayer, "\x01You fully healed \x070088cc%N", targetPlayer);
					} else
						PrintHintText(targetPlayer, "DON'T MOVE! %N is healing you.(HP: %i)", originatingPlayer, iHealth);
					SetEntityHealth(targetPlayer, iHealth);
					PrintHintText(originatingPlayer, "%N\nHP: %i\n\nHealing with %s for: %i", targetPlayer, iHealth, bCanHealPaddle && !bCanHealMedpack ? "paddle" : "medpack", bCanHealPaddle && !bCanHealMedpack ? g_iHealAmountPaddles : g_iHealAmountMedpack);
				}
			} else {
				iHealth = GetClientHealth(originatingPlayer);
				if (iHealth < g_iMedicHealSelfMax) {
					iHealth += bCanHealPaddle && !bCanHealMedpack ? g_iHealAmountPaddles : g_iHealAmountMedpack;

					if (iHealth >= g_iMedicHealSelfMax) {
						iHealth = g_iMedicHealSelfMax;
						PrintHintText(originatingPlayer, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iMedicHealSelfMax);
					} else
						PrintHintText(originatingPlayer, "Healing Self (HP: %i) | MAX: %i", iHealth, g_iMedicHealSelfMax);
					SetEntityHealth(originatingPlayer, iHealth);
				}
			}
		} else {
			/* I'm not a medic */

			if (!bCanHealMedpack)
				continue;

			targetPlayer = TraceClientViewEntity(originatingPlayer);
			if (targetPlayer > 0 && targetPlayer <= MaxClients && IsClientInGame(targetPlayer) && IsPlayerAlive(targetPlayer) && GetClientTeam(targetPlayer) == TEAM_SECURITY) {
				GetClientAbsOrigin(originatingPlayer, vecOriginatingPlayer);
				GetClientAbsOrigin(targetPlayer, vecTargetPlayer);
				tDistance = GetVectorDistance(vecOriginatingPlayer,vecTargetPlayer);

				if (tDistance > fReviveDistance || !ClientCanSeeVector(originatingPlayer, vecTargetPlayer, fReviveDistance))
					continue;

				iHealth = GetClientHealth(targetPlayer);
				if (tDistance < 750.0)
					PrintHintText(originatingPlayer, "%N\nHP: %i", targetPlayer, iHealth);

				if (iHealth < g_iNonMedicMaxHealOther) {
					iHealth += g_iNonMedicHealAmt;
					ga_iTotalHP[originatingPlayer] += g_iNonMedicHealAmt;

					if (iHealth >= g_iNonMedicMaxHealOther) {
						ga_iTotalHP[originatingPlayer] -= (iHealth - g_iNonMedicMaxHealOther);
						ga_iStatHeals[originatingPlayer]++;
						iHealth = g_iNonMedicMaxHealOther;
						PrintHintText(targetPlayer, "Non-Medic %N can only heal you to %i HP!", originatingPlayer, iHealth);
						PrintHintText(originatingPlayer, "You max healed %N", targetPlayer);
						PrintToChat(originatingPlayer, "\x01You max healed \x070088cc%N", targetPlayer);
					} else
						PrintHintText(targetPlayer, "DON'T MOVE! %N is healing you.(HP: %i)", originatingPlayer, iHealth);
					SetEntityHealth(targetPlayer, iHealth);
					PrintHintText(originatingPlayer, "%N\nHP: %i\n\nHealing.", targetPlayer, iHealth);
				} else {
					if (iHealth < g_iNonMedicMaxHealOther)
						PrintHintText(originatingPlayer, "%N\nHP: %i", targetPlayer, iHealth);
					else if (iHealth >= g_iNonMedicMaxHealOther)
						PrintHintText(originatingPlayer, "%N\nHP: %i (MAX YOU CAN HEAL)", targetPlayer, iHealth);
				}
			} else {
				iHealth = GetClientHealth(originatingPlayer);
				if (iHealth < g_iNonMedicHealSelfMax) {
					iHealth += g_iNonMedicHealAmt;
					if (iHealth >= g_iNonMedicHealSelfMax) {
						iHealth = g_iNonMedicHealSelfMax;
						PrintHintText(originatingPlayer, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
					} else
						PrintHintText(originatingPlayer, "Healing Self (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
					SetEntityHealth(originatingPlayer, iHealth);
				}
			}
		}
	}
	return Plugin_Continue;
}

Action Timer_NearestBody(Handle timer) {
	if (!g_bRoundActive)
		return Plugin_Continue;

	float	flAlivePlayerPosition[3],
			flAlivePlayerAngle[3],
			flLastPlayerDistance,
			fTempDistance,
			flShortestDistanceToPlayer;

	int		closestDeadPlayer,
			closestDeadPlayerWithoutMedic,
			amountOfHurtPlayers,
			now,
			clientRagdoll;

	char	sDirection[64],
			sDistance[64],
			sHeight[64];

	for (int alivePlayer = 1; alivePlayer <= MaxClients; alivePlayer++) {
		if (!IsClientInGame(alivePlayer) || GetClientTeam(alivePlayer) != TEAM_SECURITY || !IsPlayerAlive(alivePlayer))
			continue;

		if (StrContains(ga_sClientLastClassString[alivePlayer], "medic", false) != -1) {
			/* I'm a medic */
			flLastPlayerDistance = 0.0;
			flShortestDistanceToPlayer = 0.0;
			closestDeadPlayer = 0;
			closestDeadPlayerWithoutMedic = 0;
			amountOfHurtPlayers = 0;
			GetClientAbsOrigin(alivePlayer, flAlivePlayerPosition);

			for (int deadPlayer = 1; deadPlayer <= MaxClients; deadPlayer++) {
				if (!IsClientInGame(deadPlayer) || IsPlayerAlive(deadPlayer) || ga_bHurtFatal[deadPlayer] || deadPlayer == alivePlayer || GetClientTeam(alivePlayer) != GetClientTeam(deadPlayer))
					continue;

				if (ga_bBeingRevivedByMedic[deadPlayer]) {
					now = GetTime();
					if ((now - ga_iTimeReviveCheck[deadPlayer]) >= 2)
						ga_bBeingRevivedByMedic[deadPlayer] = false;
				}

				clientRagdoll = INVALID_ENT_REFERENCE;
				clientRagdoll = EntRefToEntIndex(ga_iClientRagdolls[deadPlayer]);

				if (clientRagdoll == INVALID_ENT_REFERENCE || !IsValidEntity(clientRagdoll))
					continue;

				fTempDistance = GetVectorDistance(flAlivePlayerPosition, ga_fRagdollPosition[deadPlayer]);

				if ( flLastPlayerDistance == 0.0 || fTempDistance < flLastPlayerDistance) {
					flLastPlayerDistance = fTempDistance;
					closestDeadPlayer = deadPlayer;
				}

				if (!ga_bBeingRevivedByMedic[deadPlayer] && (flShortestDistanceToPlayer == 0.0 || fTempDistance < flShortestDistanceToPlayer)) {
					flShortestDistanceToPlayer = fTempDistance;
					closestDeadPlayerWithoutMedic = deadPlayer;
				}

				amountOfHurtPlayers++;
			}

			// set the closest body for this client
			ga_iNearestBody[alivePlayer] = closestDeadPlayer != 0 ? closestDeadPlayer : -1;

			if (closestDeadPlayerWithoutMedic != 0) {
				GetClientAbsAngles(alivePlayer, flAlivePlayerAngle);

				// Get direction string (if it cause server lag, remove this)
				GetDirectionString(flAlivePlayerAngle, flAlivePlayerPosition, ga_fRagdollPosition[closestDeadPlayerWithoutMedic], sDirection, sizeof(sDirection));
				GetDistanceString(flShortestDistanceToPlayer, sDistance, sizeof(sDistance));
				GetHeightString(flAlivePlayerPosition, ga_fRagdollPosition[closestDeadPlayerWithoutMedic], sHeight, sizeof(sHeight));
				PrintCenterText(alivePlayer, "Nearest dead[%d]: %N ( %s | %s | %s )", amountOfHurtPlayers, closestDeadPlayerWithoutMedic, sDistance, sDirection, sHeight);
			}

		} else {
			/* I'm not a medic */
			closestDeadPlayer = 0;
			flLastPlayerDistance = 0.0;
			GetClientAbsOrigin(alivePlayer, flAlivePlayerPosition);

			for (int deadPlayer = 1; deadPlayer <= MaxClients; deadPlayer++) {
				if (!IsClientInGame(deadPlayer) || IsPlayerAlive(deadPlayer) || ga_bHurtFatal[deadPlayer] || deadPlayer == alivePlayer || GetClientTeam(alivePlayer) != GetClientTeam(deadPlayer))
					continue;

				clientRagdoll = INVALID_ENT_REFERENCE;
				clientRagdoll = EntRefToEntIndex(ga_iClientRagdolls[deadPlayer]);

				if (clientRagdoll == INVALID_ENT_REFERENCE || !IsValidEntity(clientRagdoll))
					continue;

				fTempDistance = GetVectorDistance(flAlivePlayerPosition, ga_fRagdollPosition[deadPlayer]);

				if (flLastPlayerDistance == 0.0 || fTempDistance < flLastPlayerDistance) {
					flLastPlayerDistance = fTempDistance;
					closestDeadPlayer = deadPlayer;
				}
			}

			ga_iNearestBody[alivePlayer] = closestDeadPlayer != 0 ? closestDeadPlayer : -1;
		}
	}
	return Plugin_Continue;
}

// Direction string: e.g., "FWD", "RIGHT", "BACK-LEFT"
void GetDirectionString(const float fClientAngles[3], const float fClientPosition[3], const float fTargetPosition[3], char[] outDir, int outLen) {
	float v[3], ang[3];
	MakeVectorFromPoints(fClientPosition, fTargetPosition, v);
	GetVectorAngles(v, ang);

	float diff = fClientAngles[1] - ang[1];
	if (diff < -180.0) diff += 360.0;
	if (diff >  180.0) diff -= 360.0;

	if      (diff >=  -22.5 && diff <   22.5) FormatEx(outDir, outLen, "FWD");
	else if (diff >=   22.5 && diff <   67.5) FormatEx(outDir, outLen, "FWD-RIGHT");
	else if (diff >=   67.5 && diff <  112.5) FormatEx(outDir, outLen, "RIGHT");
	else if (diff >=  112.5 && diff <  157.5) FormatEx(outDir, outLen, "BACK-RIGHT");
	else if (diff >=  157.5 || diff < -157.5) FormatEx(outDir, outLen, "BACK");
	else if (diff >= -157.5 && diff < -112.5) FormatEx(outDir, outLen, "BACK-LEFT");
	else if (diff >= -112.5 && diff <  -67.5) FormatEx(outDir, outLen, "LEFT");
	else /* diff >= -67.5 && diff < -22.5 */   FormatEx(outDir, outLen, "FWD-LEFT");
}

// Distance string: meters or feet based on g_bDistanceFeet
void GetDistanceString(float fDistance, char[] outStr, int outLen) {
	float meters = fDistance * 0.01905;
	if (g_bDistanceFeet) {
		float feet = meters * 3.2808399;
		FormatEx(outStr, outLen, "%.0f feet", feet);
	} else
		FormatEx(outStr, outLen, "%.0f meter", meters);
}

// Height relation string: ABOVE / BELOW / LEVEL
void GetHeightString(const float fClientPosition[3], const float fTargetPosition[3], char[] outStr, int outLen) {
	float dz = FloatAbs(fClientPosition[2] - fTargetPosition[2]);
	float meters = dz * 0.01905;

	if (g_bDistanceFeet) {
		float feet = meters * 3.2808399;
		if (fClientPosition[2] + 64.0 < fTargetPosition[2])      FormatEx(outStr, outLen, "ABOVE %.0f'", feet);
		else if (fClientPosition[2] - 64.0 > fTargetPosition[2]) FormatEx(outStr, outLen, "BELOW %.0f'", feet);
		else                                                      FormatEx(outStr, outLen, "LEVEL");
	} else {
		if (fClientPosition[2] + 64.0 < fTargetPosition[2])      FormatEx(outStr, outLen, "ABOVE %.0fm", meters);
		else if (fClientPosition[2] - 64.0 > fTargetPosition[2]) FormatEx(outStr, outLen, "BELOW %.0fm", meters);
		else                                                      FormatEx(outStr, outLen, "LEVEL");
	}
}

int TraceClientViewEntity(int client) {
	float eyePos[3], eyeAng[3];
	GetClientEyePosition(client, eyePos);
	GetClientEyeAngles(client, eyeAng);
	Handle tr = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_VISIBLE, RayType_Infinite, TRDontHitSelf, client);
	int pEntity = -1;
	if (TR_DidHit(tr)) {
		pEntity = TR_GetEntityIndex(tr);
		delete tr;
		return pEntity;
	}
	delete tr;
	return -1;
}

public Action Event_GrenadeThrown(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int nade_id = event.GetInt("entityid");

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	if (nade_id <= MaxClients || !IsValidEntity(nade_id))
		return Plugin_Continue;

	char grenade_name[32];
	GetEntityClassname(nade_id, grenade_name, sizeof(grenade_name));

	if (!StrEqual(grenade_name, "healthkit"))
		return Plugin_Continue;

	// Your existing voice lines
	switch (GetRandomInt(0, 3)) {
		case 0: EmitSoundToAll("player/voice/radial/security/leader/unsuppressed/need_backup1.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/radial/security/leader/unsuppressed/holdposition2.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/radial/security/leader/suppressed/holdposition1.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/security/command/leader/setwaypoint2.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}

	// Start the healthkit timers/hooks next frame (safer than immediate)
	RequestFrame(Frame_InitHealthkit, EntIndexToEntRef(nade_id));

	return Plugin_Continue;
}

void InitHealthkitEntity(int entity) {
	if (entity <= MaxClients || entity > MAX_ENTITIES || !IsValidEntity(entity))
		return;

	if (ga_bHealthkitInit[entity])
		return;

	ga_bHealthkitInit[entity] = true;

	ga_iHealthPack_Amount[entity] = g_iMedpackHealthAmount;

	DataPack hDatapack;
	CreateDataTimer(Healthkit_Timer_Tickrate, Healthkit, hDatapack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	int entref = EntIndexToEntRef(entity);
	hDatapack.WriteCell(entref);
	hDatapack.WriteFloat(GetGameTime() + Healthkit_Timer_Timeout);

	ga_fLastHeight[entity] = -9999.0;

	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	ga_iTimeCheckHeight[entity] = RoundFloat(origin[2]);
	ga_fTimeCheck[entity] = GetGameTime();

	SDKHook(entity, SDKHook_VPhysicsUpdate, HealthkitGroundCheck);
	CreateTimer(0.1, HealthkitGroundCheckTimer, entref, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}


void Frame_InitHealthkit(any entref) {
	int entity = EntRefToEntIndex(entref);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity))
		return;

	InitHealthkitEntity(entity);
}

static void HealthkitForceLogoUp(int entity) {
	float ang[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", ang);

	ang[0] = 90.0;
	ang[2] = 0.0;

	float vel[3];
	vel[0] = 0.0; vel[1] = 0.0; vel[2] = 0.0;

	TeleportEntity(entity, NULL_VECTOR, ang, vel);

	if (HasEntProp(entity, Prop_Data, "m_vecAngVelocity")) {
		float avel[3];
		avel[0] = 0.0; avel[1] = 0.0; avel[2] = 0.0;
		SetEntPropVector(entity, Prop_Data, "m_vecAngVelocity", avel);
	}

	SetEntityMoveType(entity, MOVETYPE_NONE);
}

public void HealthkitGroundCheck(int entity) {
	if (entity <= MaxClients || !IsValidEntity(entity))
		return;

	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);

	int h = RoundFloat(origin[2]);
	if (h != ga_iTimeCheckHeight[entity]) {
		ga_iTimeCheckHeight[entity] = h;
		ga_fTimeCheck[entity] = GetGameTime();
	}
}

public Action HealthkitGroundCheckTimer(Handle timer, int entref) {
	int entity = EntRefToEntIndex(entref);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity))
		return Plugin_Stop;

	float now = GetGameTime();
	if (now - ga_fTimeCheck[entity] < 0.25)
		return Plugin_Continue;

	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);

	int h = RoundFloat(origin[2]);
	if (h != ga_iTimeCheckHeight[entity]) {
		ga_iTimeCheckHeight[entity] = h;
		ga_fTimeCheck[entity] = now;
		return Plugin_Continue;
	}

	HealthkitForceLogoUp(entity);

	SDKUnhook(entity, SDKHook_VPhysicsUpdate, HealthkitGroundCheck);
	return Plugin_Stop;
}

Action Healthkit(Handle timer, DataPack hDatapack) {
	hDatapack.Reset();

	int entref = hDatapack.ReadCell();
	float fEndTime = hDatapack.ReadFloat();

	int healthPack = EntRefToEntIndex(entref);
	if (healthPack == INVALID_ENT_REFERENCE || healthPack <= MaxClients || healthPack > MAX_ENTITIES || !IsValidEntity(healthPack))
		return Plugin_Stop;

	float fGameTime = GetGameTime();
	if (fGameTime > fEndTime || ga_iHealthPack_Amount[healthPack] <= 0) {
		ga_bHealthkitInit[healthPack] = false;
		ga_iHealthPack_Amount[healthPack] = 0;
		SafeKillIdx(healthPack);
		return Plugin_Stop;
	}

	float	fOrigin[3],
			fPlayerOrigin[3];

	int		ActiveWeapon,
			iHealth;

	char	sWeapon[32];

	GetEntPropVector(healthPack, Prop_Data, "m_vecAbsOrigin", fOrigin);
	fOrigin[2] += 1.0;
	TE_SetupBeamRingPoint(fOrigin, 1.0, Healthkit_Radius*1.95, g_iBeaconBeam, g_iBeaconHalo, 0, 30, 3.0, 4.0, 0.0, g_iColorHealRing, 1, FBEAM_HALOBEAM);
	TE_SendToAll();
	fOrigin[2] -= 16.0;

	if (ga_fLastHeight[healthPack] == -9999.0)
		ga_fLastHeight[healthPack] = 0.0;

	if (fOrigin[2] != ga_fLastHeight[healthPack])
		ga_fLastHeight[healthPack] = fOrigin[2];

	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SECURITY)
			continue;

		if (StrContains(ga_sClientLastClassString[client], "medic", false) != -1) {
			/* I'm a medic */
			ActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
			if (ActiveWeapon < 0)
				continue;

			GetEdictClassname(ActiveWeapon, sWeapon, sizeof(sWeapon));
			if (!hasCorrectWeapon(sWeapon))
				continue;

			GetClientEyePosition(client, fPlayerOrigin);
			if (GetVectorDistance(fPlayerOrigin, fOrigin) > Healthkit_Radius)
				continue;

			iHealth = GetClientHealth(client);
			if (Check_NearbyMedics(client)) {
				if (iHealth < 100) {
					iHealth += g_iHealAmountPaddles;
					ga_iHealthPack_Amount[healthPack] -= g_iHealAmountPaddles;
					if (iHealth >= 100) {
						iHealth = 100;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "A medic assisted in healing you (HP: %i)", iHealth);
					}
					else {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Self area healing (HP: %i)", iHealth);
					}
					SetEntityHealth(client, iHealth);
				}
			} else {
				if (iHealth < g_iMedicHealSelfMax) {
					iHealth += g_iHealAmountPaddles;
					ga_iHealthPack_Amount[healthPack] -= g_iHealAmountPaddles;
					if (iHealth >= g_iMedicHealSelfMax) {
						iHealth = g_iMedicHealSelfMax;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "You area healed yourself (HP: %i) | MAX: %i", iHealth, g_iMedicHealSelfMax);
					} else {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Self area healing (HP: %i) | MAX %i", iHealth, g_iMedicHealSelfMax);
					}
				} else {
					PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
					PrintHintText(client, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iMedicHealSelfMax);
				}
			}
		} else {
			/* I'm not a medic */
			GetClientEyePosition(client, fPlayerOrigin);
			if (GetVectorDistance(fPlayerOrigin, fOrigin) > Healthkit_Radius)
				continue;

			if (Check_NearbyMedics(client)) {
				iHealth = GetClientHealth(client);
				if (iHealth < 100) {
					iHealth += g_iHealAmountPaddles;
					ga_iHealthPack_Amount[healthPack] -= g_iHealAmountPaddles;
					if (iHealth >= 100) {
						iHealth = 100;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "A medic assisted in healing you (HP: %i)", iHealth);
					} else  {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Medic area healing you (HP: %i)", iHealth);
						switch (GetRandomInt(0, 1)) {
							case 0: EmitSoundToAll("weapons/universal/uni_crawl_l_01.wav", client, SNDCHAN_VOICE, _, _, 1.0);
							case 1: EmitSoundToAll("weapons/universal/uni_crawl_l_02.wav", client, SNDCHAN_VOICE, _, _, 1.0);
						}
					}
					SetEntityHealth(client, iHealth);
				}
			} else {
				ActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
				if (ActiveWeapon < 0)
					continue;
				GetEdictClassname(ActiveWeapon, sWeapon, sizeof(sWeapon));
				iHealth = GetClientHealth(client);

				if (!hasCorrectWeapon(sWeapon)) {
					if (iHealth < g_iNonMedicHealSelfMax)
						PrintHintText(client, "No medics nearby! Pull knife out to heal! (HP: %i)", iHealth);
					continue;
				}

				if (iHealth < g_iNonMedicHealSelfMax) {
					iHealth += g_iNonMedicHealAmt;
					ga_iHealthPack_Amount[healthPack] -= g_iNonMedicHealAmt;
					if (iHealth >= g_iNonMedicHealSelfMax) {
						iHealth = g_iNonMedicHealSelfMax;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
					} else {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Healing Self (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
					}
					SetEntityHealth(client, iHealth);
				} else {
					PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
					PrintHintText(client, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
				}
			}
		}
	}


	return Plugin_Continue;
}

bool Check_NearbyMedics(int client) {
	float	clientPosition[3],
			medicPosition[3],
			fDistance;

	int		ActiveWeapon;

	char	sWeapon[32];

	for (int friendlyMedic = 1; friendlyMedic <= MaxClients; friendlyMedic++) {
		if (!IsClientInGame(friendlyMedic) || !IsPlayerAlive(friendlyMedic) || client == friendlyMedic || StrContains(ga_sClientLastClassString[friendlyMedic], "medic", false) == -1)
			continue;

		ActiveWeapon = GetEntPropEnt(friendlyMedic, Prop_Data, "m_hActiveWeapon");
		if (ActiveWeapon < 0)
			continue;

		GetEdictClassname(ActiveWeapon, sWeapon, sizeof(sWeapon));
		if (!hasCorrectWeapon(sWeapon) && !hasCorrectWeapon(sWeapon, false))
			continue;

		GetClientAbsOrigin(client, clientPosition);
		GetClientAbsOrigin(friendlyMedic, medicPosition);
		fDistance = GetVectorDistance(medicPosition, clientPosition);

		if (fDistance <= Healthkit_Radius)
			return true;
	}
	return false;
}

void Check_NearbyMedicsRevive(int client, int iInjured) {
	float	medicPosition[3],
			fDistance;

	int		ActiveWeapon;

	char	sWeapon[32],
			woundType[20];

	for (int assistingMedic = 1; assistingMedic <= MaxClients; assistingMedic++) {
		if (!IsClientInGame(assistingMedic) || !IsPlayerAlive(assistingMedic) || client == assistingMedic || StrContains(ga_sClientLastClassString[assistingMedic], "medic", false) == -1)
			continue;

		ActiveWeapon = GetEntPropEnt(assistingMedic, Prop_Data, "m_hActiveWeapon");
		if (ActiveWeapon < 0)
			continue;

		GetEdictClassname(ActiveWeapon, sWeapon, sizeof(sWeapon));
		if (!hasCorrectWeapon(sWeapon))
			continue;

		GetClientAbsOrigin(assistingMedic, medicPosition);
		fDistance = GetVectorDistance(medicPosition, ga_fRagdollPosition[iInjured]);

		if (fDistance <= 65.0) {
			if (ga_iPlayerWoundType[iInjured] == 0)
				strcopy(woundType, sizeof(woundType), "minor wound");
			else if (ga_iPlayerWoundType[iInjured] == 1)
				strcopy(woundType, sizeof(woundType), "moderate wound");
			else if (ga_iPlayerWoundType[iInjured] == 2)
				strcopy(woundType, sizeof(woundType), "critical wound");
			else
				strcopy(woundType, sizeof(woundType), "wound");

			ga_iStatRevives[assistingMedic]++;

			PrintHintText(assistingMedic, "You revived(assisted) %N from a %s", iInjured, woundType);
		}
	}
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	int oldTeam = event.GetInt("oldteam");
	int newTeam = event.GetInt("team");

	if (oldTeam == TEAM_SECURITY && newTeam != TEAM_SECURITY)
		RemoveRagdoll(client);

	return Plugin_Continue;
}

public Action cmd_fatal(int client, int args) {
	if (!IsPlayerAlive(client) && !ga_bHurtFatal[client]) {
		ga_bHurtFatal[client] = true;
		RemoveRagdoll(client);
		PrintToChat(client, "Changed your death to fatal.");
	}
	return Plugin_Handled;
}

void ResetMedicStats (int client) {
	ga_iStatRevives[client] = 0;
	ga_iStatHeals[client] = 0;
	ga_iTotalHP[client] = 0;
}

void PlayVictimReviveSound(int client) {
	char sBuffer[64];
	FormatEx(sBuffer, sizeof(sBuffer), "lua_sounds/medic/thx/medic_thanks%d.ogg", GetRandomInt(9, 11));
	EmitSoundToAll(sBuffer, client, SNDCHAN_VOICE, _, _, 1.0);
	EmitSoundToClient(client, SND_REVIVENOTIFY, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
}

public Action cmdListener(int client, const char[] cmd, int argc) {
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	if (GetRandomInt(0, 1) == 1)
		ga_bHurtFatal[client] = true;

	return Plugin_Continue;
}

public Action ChangeLevelListener(int client, const char[] command, int argc) {
	if (StrEqual(command, "sm_map", false)) {
		if (client > 0 && !CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP, true))
			return Plugin_Continue;
	}
	else if (StrEqual(command, "map", false) || StrEqual(command, "changelevel", false)) {
		if (client > 0)
			return Plugin_Continue;
	}
	else
		return Plugin_Continue;

	if (argc > 0) {
		char nextMap[PLATFORM_MAX_PATH];
		GetCmdArg(1, nextMap, sizeof(nextMap));
		if (IsMapValid(nextMap)) {
			g_bMapInit = false;
			g_bRoundActive = false;
			g_bReviveActive = false;
		}
	}
	return Plugin_Continue;
}

static void VecCopy(const float src[3], float dest[3]) {
	dest[0] = src[0];
	dest[1] = src[1];
	dest[2] = src[2];
}

public bool TraceEntityFilterPlayers(int entity, int contentsMask, any data) {
	if (entity == data) return false;
	return (entity > MaxClients);
}

public bool TraceEntityFilterSolid(int entity, int contentsMask, any data) {
	return (entity > MaxClients);
}

public bool TRDontHitSelf(int entity, int contentsMask, any data) {
	return (entity != data);
}

void PrecacheFiles() {
	char sBuffer[128];
	g_iBeaconBeam = PrecacheModel("materials/sprites/laser.vmt");
	g_iBeaconHalo = PrecacheModel("materials/sprites/glow01.vmt");

	// Deploying sounds
	PrecacheSound("player/voice/radial/security/leader/unsuppressed/need_backup1.ogg");
	PrecacheSound("player/voice/radial/security/leader/unsuppressed/holdposition2.ogg");
	PrecacheSound("player/voice/radial/security/leader/suppressed/holdposition1.ogg");
	PrecacheSound("player/voice/security/command/leader/setwaypoint2.ogg");
	//Lua sounds
	for (int i = 9; i <= 11; i++) {
		FormatEx(sBuffer, sizeof(sBuffer), "lua_sounds/medic/thx/medic_thanks%d.ogg", i);
		PrecacheSound(sBuffer);
	}
	for (int i = 1; i <= 2; i++) {
		FormatEx(sBuffer, sizeof(sBuffer), "weapons/universal/uni_crawl_l_0%d.wav", i);
		PrecacheSound(sBuffer);
	}
	//L4D2 defibrillator revive sound
	PrecacheSound("weapons/defibrillator/defibrillator_revive.wav");
	// Destory, Flip sounds
	PrecacheSound("ui/sfx/cl_click.wav");

	PrecacheSound(SND_REVIVENOTIFY);
}

static int OR_Cache(bool force = false) {
	if (force || g_iObjResEntity < 1 || !IsValidEntity(g_iObjResEntity)) {
		g_iObjResEntity = FindEntityByClassname(-1, "ins_objective_resource");
		if (g_iObjResEntity > 0)
			GetEntityNetClass(g_iObjResEntity, g_sObjResNetClass, sizeof g_sObjResNetClass);
		else
			g_sObjResNetClass[0] = '\0';
	}
	else {
		char classname[32];
		GetEntityClassname(g_iObjResEntity, classname, sizeof classname);
		if (classname[0] == '\0' || !StrEqual(classname, "ins_objective_resource", false))
			return OR_Cache(true);
	}
	return g_iObjResEntity;
}

stock int Ins_ObjectiveResource_GetProp(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1)
			return GetEntData(g_iObjResEntity, offs + (size * element));
	}
	return -1;
}

stock float Ins_ObjectiveResource_GetPropFloat(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1)
			return GetEntDataFloat(g_iObjResEntity, offs + (size * element));
	}
	return -1.0;
}

stock int Ins_ObjectiveResource_GetPropEnt(const char[] prop, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1)
			return GetEntData(g_iObjResEntity, offs + (4 * element));
	}
	return -1;
}

stock bool Ins_ObjectiveResource_GetPropVector(const char[] prop, float vec[3], int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1) {
			GetEntDataVector(g_iObjResEntity, offs + (12 * element), vec); // 3*4 bytes
			return true;
		}
	}
	return false;
}

// stock int Ins_ObjectiveResource_GetPropString(const char[] prop, char[] buffer, int maxlen) {
// 	buffer[0] = '\0';
// 	return 0;
// }

stock bool Ins_InCounterAttack() {
	return (GameRules_GetProp("m_bCounterAttack") != 0);
}

public bool TraceFilter_NoPlayersNoRagdolls(int entity, int contentsMask, any data) {
	if (entity >= 1 && entity <= MaxClients)
		return false;

	if (entity > MaxClients && IsValidEntity(entity)) {
		static char cls[32];
		GetEntityClassname(entity, cls, sizeof cls);
		if (StrContains(cls, "ragdoll", false) != -1)
			return false;
	}

	return true;
}

bool ClientCanSeeVector(int client, float vTargetPosition[3], float distance = 0.0, float height = 40.0) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;

	if (distance > 0.0) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		if (GetVectorDistance(pos, vTargetPosition, false) > distance)
			return false;
	}

	float start[3], end[3];
	GetClientEyePosition(client, start);
	end[0] = vTargetPosition[0];
	end[1] = vTargetPosition[1];
	end[2] = vTargetPosition[2] + height;
	
	Handle tr = TR_TraceRayFilterEx(start, end, MASK_VISIBLE, RayType_EndPoint, TraceFilter_NoPlayersNoRagdolls);
	bool blocked = TR_DidHit(tr);
	delete tr;
	return !blocked;
}

stock void SafeKillIdx(int ent) {
	if (ent <= MaxClients) return;
	int ref = EntIndexToEntRef(ent);
	if (ref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, ref);
}

stock void SafeKillRef(int entref) {
	if (entref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, entref);
}

stock void NF_KillEntity(any entref) {
	int ent = EntRefToEntIndex(entref);
	if (ent <= MaxClients || !IsValidEntity(ent)) return;

	if (!AcceptEntityInput(ent, "Kill"))
		RemoveEntity(ent);
}

void SetupConVars() {
	g_cvReviveEnabled = CreateConVar("sm_revive_enabled", "1", "Reviving enabled from medics?  This creates revivable ragdoll after death; 0 - disabled, 1 - enabled");
	g_bReviveEnabled = g_cvReviveEnabled.BoolValue;
	g_cvReviveEnabled.AddChangeHook(OnConVarChanged);

	g_cvFatalChance = CreateConVar("sm_respawn_fatal_chance", "0.20", "Chance for a kill to be fatal, 0.6 default = 60% chance to be fatal (To disable set 0.0)");
	g_fFatalChance = g_cvFatalChance.FloatValue;
	g_cvFatalChance.AddChangeHook(OnConVarChanged);

	g_cvFatalHeadChance = CreateConVar("sm_respawn_fatal_head_chance", "0.75", "Chance for a headshot kill to be fatal, 0.6 default = 60% chance to be fatal");
	g_fFatalHeadChance = g_cvFatalHeadChance.FloatValue;
	g_cvFatalHeadChance.AddChangeHook(OnConVarChanged);

	g_cvFatalLimbDmg = CreateConVar("sm_respawn_fatal_limb_dmg", "180", "Amount of damage to fatally kill player in limb");
	g_iFatalLimbDmg = g_cvFatalLimbDmg.IntValue;
	g_cvFatalLimbDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalHeadDmg = CreateConVar("sm_respawn_fatal_head_dmg", "200", "Amount of damage to fatally kill player in head");
	g_iFatalHeadDmg = g_cvFatalHeadDmg.IntValue;
	g_cvFatalHeadDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalBurnDmg = CreateConVar("sm_respawn_fatal_burn_dmg", "80", "Amount of damage to fatally kill player in burn");
	g_iFatalBurnDmg = g_cvFatalBurnDmg.IntValue;
	g_cvFatalBurnDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalExplosiveDmg = CreateConVar("sm_respawn_fatal_explosive_dmg", "220", "Amount of damage to fatally kill player in explosive");
	g_iFatalExplosiveDmg = g_cvFatalExplosiveDmg.IntValue;
	g_cvFatalExplosiveDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalChestStomach = CreateConVar("sm_respawn_fatal_chest_stomach", "170", "Amount of damage to fatally kill player in chest/stomach");
	g_iFatalChestStomach = g_cvFatalChestStomach.IntValue;
	g_cvFatalChestStomach.AddChangeHook(OnConVarChanged);

	g_cvReviveDistanceMetric = CreateConVar("sm_revive_distance_metric", "0", "Distance metric (0: meters / 1: feet)");
	g_bDistanceFeet = g_cvReviveDistanceMetric.BoolValue;
	g_cvReviveDistanceMetric.AddChangeHook(OnConVarChanged);

	g_cvHealAmountMedpack = CreateConVar("sm_heal_amount_medpack", "8", "Heal amount per 0.5 seconds when using medpack");
	g_iHealAmountMedpack = g_cvHealAmountMedpack.IntValue;
	g_cvHealAmountMedpack.AddChangeHook(OnConVarChanged);

	g_cvHealAmountPaddles = CreateConVar("sm_heal_amount_paddles", "4", "Heal amount per 0.5 seconds when using paddles");
	g_iHealAmountPaddles = g_cvHealAmountPaddles.IntValue;
	g_cvHealAmountPaddles.AddChangeHook(OnConVarChanged);

	g_cvNonMedicHealAmt = CreateConVar("sm_non_medic_heal_amt", "3", "Heal amount per 0.5 seconds when non-medic");
	g_iNonMedicHealAmt = g_cvNonMedicHealAmt.IntValue;
	g_cvNonMedicHealAmt.AddChangeHook(OnConVarChanged);

	g_cvNonMedicReviveHp = CreateConVar("sm_non_medic_revive_hp", "20", "Health given to target revive when non-medic reviving");
	g_iNonMedicReviveHp = g_cvNonMedicReviveHp.IntValue;
	g_cvNonMedicReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMedicMinorReviveHp = CreateConVar("sm_medic_minor_revive_hp", "70", "Health given to target revive when medic reviving minor wound");
	g_iMedicMinorReviveHp = g_cvMedicMinorReviveHp.IntValue;
	g_cvMedicMinorReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMedicModerateReviveHp = CreateConVar("sm_medic_moderate_revive_hp", "50", "Health given to target revive when medic reviving moderate wound");
	g_iMedicModerateReviveHp = g_cvMedicModerateReviveHp.IntValue;
	g_cvMedicModerateReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMedicCriticalReviveHp = CreateConVar("sm_medic_critical_revive_hp", "35", "Health given to target revive when medic reviving critical wound");
	g_iMedicCriticalReviveHp = g_cvMedicCriticalReviveHp.IntValue;
	g_cvMedicCriticalReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMinorWoundDmg = CreateConVar("sm_minor_wound_dmg", "150", "Any amount of damage <= to this is considered a minor wound when killed");
	g_iMinorWoundDmg = g_cvMinorWoundDmg.IntValue;
	g_cvMinorWoundDmg.AddChangeHook(OnConVarChanged);

	g_cvModerateWoundDmg = CreateConVar("sm_moderate_wound_dmg", "250", "Any amount of damage <= to this is considered a minor wound when killed.	Anything greater is CRITICAL");
	g_iModerateWoundDmg = g_cvModerateWoundDmg.IntValue;
	g_cvModerateWoundDmg.AddChangeHook(OnConVarChanged);

	g_cvMedicHealSelfMax = CreateConVar("sm_medic_heal_self_max", "80", "Max medic can heal self to with med pack");
	g_iMedicHealSelfMax = g_cvMedicHealSelfMax.IntValue;
	g_cvMedicHealSelfMax.AddChangeHook(OnConVarChanged);

	g_cvNonMedicHealSelfMax = CreateConVar("sm_non_medic_heal_self_max", "60", "Max non-medic can heal self to with med pack");
	g_iNonMedicHealSelfMax = g_cvNonMedicHealSelfMax.IntValue;
	g_cvNonMedicHealSelfMax.AddChangeHook(OnConVarChanged);

	g_cvNonMedicMaxHealOther = CreateConVar("sm_non_medic_max_heal_other", "60", "Heal amount per 0.5 seconds when using paddles");
	g_iNonMedicMaxHealOther = g_cvNonMedicMaxHealOther.IntValue;
	g_cvNonMedicMaxHealOther.AddChangeHook(OnConVarChanged);

	g_cvMinorReviveTime = CreateConVar("sm_minor_revive_time", "4", "Seconds it takes medic to revive minor wounded");
	g_iMinorReviveTime = g_cvMinorReviveTime.IntValue;
	g_cvMinorReviveTime.AddChangeHook(OnConVarChanged);

	g_cvModerateReviveTime = CreateConVar("sm_moderate_revive_time", "6", "Seconds it takes medic to revive moderate wounded");
	g_iModerateReviveTime = g_cvModerateReviveTime.IntValue;
	g_cvModerateReviveTime.AddChangeHook(OnConVarChanged);

	g_cvCriticalReviveTime = CreateConVar("sm_critical_revive_time", "8", "Seconds it takes medic to revive critical wounded");
	g_iCriticalReviveTime = g_cvCriticalReviveTime.IntValue;
	g_cvCriticalReviveTime.AddChangeHook(OnConVarChanged);

	g_cvNonMedicReviveTime = CreateConVar("sm_non_medic_revive_time", "15", "Seconds it takes non-medic to revive minor wounded, requires medpack");
	g_iNonMedicReviveTime = g_cvNonMedicReviveTime.IntValue;
	g_cvNonMedicReviveTime.AddChangeHook(OnConVarChanged);

	g_cvMedpackHealthAmount = CreateConVar("sm_medpack_health_amount", "500", "Amount of health a deployed healthpack has");
	g_iMedpackHealthAmount = g_cvMedpackHealthAmount.IntValue;
	g_cvMedpackHealthAmount.AddChangeHook(OnConVarChanged);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvReviveEnabled)
		g_bReviveEnabled = g_cvReviveEnabled.BoolValue;
	else if (convar == g_cvFatalChance)
		g_fFatalChance = g_cvFatalChance.FloatValue;
	else if (convar == g_cvFatalHeadChance)
		g_fFatalHeadChance = g_cvFatalHeadChance.FloatValue;
	else if (convar == g_cvFatalLimbDmg)
		g_iFatalLimbDmg = g_cvFatalLimbDmg.IntValue;
	else if (convar == g_cvFatalHeadDmg)
		g_iFatalHeadDmg = g_cvFatalHeadDmg.IntValue;
	else if (convar == g_cvFatalBurnDmg)
		g_iFatalBurnDmg = g_cvFatalBurnDmg.IntValue;
	else if (convar == g_cvFatalExplosiveDmg)
		g_iFatalExplosiveDmg = g_cvFatalExplosiveDmg.IntValue;
	else if (convar == g_cvFatalChestStomach)
		g_iFatalChestStomach = g_cvFatalChestStomach.IntValue;
	else if (convar == g_cvReviveDistanceMetric)
		g_bDistanceFeet = g_cvReviveDistanceMetric.BoolValue;
	else if (convar == g_cvHealAmountMedpack)
		g_iHealAmountMedpack = g_cvHealAmountMedpack.IntValue;
	else if (convar == g_cvHealAmountPaddles)
		g_iHealAmountPaddles = g_cvHealAmountPaddles.IntValue;
	else if (convar == g_cvNonMedicHealAmt)
		g_iNonMedicHealAmt = g_cvNonMedicHealAmt.IntValue;
	else if (convar == g_cvNonMedicReviveHp)
		g_iNonMedicReviveHp = g_cvNonMedicReviveHp.IntValue;
	else if (convar == g_cvMedicMinorReviveHp)
		g_iMedicMinorReviveHp = g_cvMedicMinorReviveHp.IntValue;
	else if (convar == g_cvMedicModerateReviveHp)
		g_iMedicModerateReviveHp = g_cvMedicModerateReviveHp.IntValue;
	else if (convar == g_cvMedicCriticalReviveHp)
		g_iMedicCriticalReviveHp = g_cvMedicCriticalReviveHp.IntValue;
	else if (convar == g_cvMinorWoundDmg)
		g_iMinorWoundDmg = g_cvMinorWoundDmg.IntValue;
	else if (convar == g_cvModerateWoundDmg)
		g_iModerateWoundDmg = g_cvModerateWoundDmg.IntValue;
	else if (convar == g_cvMedicHealSelfMax)
		g_iMedicHealSelfMax = g_cvMedicHealSelfMax.IntValue;
	else if (convar == g_cvNonMedicHealSelfMax)
		g_iNonMedicHealSelfMax = g_cvNonMedicHealSelfMax.IntValue;
	else if (convar == g_cvNonMedicMaxHealOther)
		g_iNonMedicMaxHealOther = g_cvNonMedicMaxHealOther.IntValue;
	else if (convar == g_cvMinorReviveTime)
		g_iMinorReviveTime = g_cvMinorReviveTime.IntValue;
	else if (convar == g_cvModerateReviveTime)
		g_iModerateReviveTime = g_cvModerateReviveTime.IntValue;
	else if (convar == g_cvCriticalReviveTime)
		g_iCriticalReviveTime = g_cvCriticalReviveTime.IntValue;
	else if (convar == g_cvNonMedicReviveTime)
		g_iNonMedicReviveTime = g_cvNonMedicReviveTime.IntValue;
	else if (convar == g_cvMedpackHealthAmount)
		g_iMedpackHealthAmount = g_cvMedpackHealthAmount.IntValue;
}
