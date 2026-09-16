#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <bm_spawn_reviews>

#define PL_VERSION		"1.4.1"

#define TEAM_SPECTATOR	1
#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

#define MAX_CPS			32

// ------------------------------------------------------------
// Config / state
// ------------------------------------------------------------

float g_fMinSpawnDistHuman = 1150.0;		// how far from humans a CP spawn must be
float g_fProximityGraceSeconds = 15.0;		// disable proximity check for this long

float g_fProxGraceUntil = 0.0;

ArrayList g_CPSpawns[MAX_CPS];
ArrayList g_CASpawns[MAX_CPS];
int g_iNumCPs = 0;
int g_iActiveCP = 0;

int g_iStageGeneration = 0;
Handle ga_hRespawnTimer[MAXPLAYERS + 1];
int ga_iRespawnStage[MAXPLAYERS + 1];
int ga_iRespawnClass[MAXPLAYERS + 1];
bool ga_bRespawnCharged[MAXPLAYERS + 1];
bool ga_bRecoveringStuck[MAXPLAYERS + 1];
int ga_iLifeSerial[MAXPLAYERS + 1];
int ga_iSpawnCP[MAXPLAYERS + 1];
bool ga_bSpawnCA[MAXPLAYERS + 1];

ArrayList g_SpawnSafety[MAX_CPS];
int g_iSafetyEpoch = 0;
int g_iSafetyTick = -1;
int g_iHumanCount = 0;
float g_HumanOrigins[32][3];
ConVar g_cvSpawnCache;
bool g_bSpawnCache = true;
int g_iPositionCollections = 0;
int g_iSafetyChecks = 0;
int g_iSafetyCacheHits = 0;
int g_iDistanceChecks = 0;
StringMap g_SpawnFailures;
char g_sSpawnLoadError[192];
int g_iReviewBeam = -1;

Handle g_hForceRespawn = null;
Handle g_hGameConfig = null;

ConVar cv_hBotLives = null;
ConVar cv_hMaxCounterAttackDuration = null;
ConVar cv_hMinCounterAttackDuration = null;
ConVar cv_hMaxFinalCounterAttackDuration = null;
ConVar cv_hMinFinalCounterAttackDuration = null;
ConVar cv_hCounterAttackDuration = null;
ConVar cv_hCounterAttackDisable = null;
ConVar cv_hCounterAttackAlways = null;
ConVar cv_hCounterAttackChance = null;
ConVar cv_hMinSpawnDistHuman = null;
ConVar cv_hProximityGraceSeconds = null;
ConVar cv_hBomberRespawns = null;
ConVar cv_hTankRespawns = null;

ConVar g_cvCADelay = null;
ConVar g_cvCADelayFinale = null;
ConVar g_cvCAWarnRadius = null;

int g_iMaxCounterAttackDuration = 0;
int g_iMinCounterAttackDuration = 0;
int g_iMaxFinalCounterAttackDuration = 0;
int g_iMinFinalCounterAttackDuration = 0;
float g_fCounterAttackChance = 0.0;

const int gc_iBomber = 31;
const int gc_iTank = 32;
bool ga_bIsBomber[MAXPLAYERS + 1];
bool ga_bIsTank[MAXPLAYERS + 1];

int g_iBomberRespawnsMax = 0;
int g_iTankRespawnsMax = 0;

int g_iBomberRespawCount = 0;
int g_iTankRespawnCount = 0;

float ga_fBotSpawnOrigin[MAXPLAYERS + 1][3];
float ga_fBotSpawnTime[MAXPLAYERS + 1];
int ga_iBotNoMoveChecks[MAXPLAYERS + 1];
bool ga_bBotSpawnOriginValid[MAXPLAYERS + 1];
float ga_fBotLastPos[MAXPLAYERS + 1][3];
float ga_fBotLastMoveTime[MAXPLAYERS + 1];
int ga_iBotIdleMoveChecks[MAXPLAYERS + 1];

int g_iBotLives = 0;
int g_iBotLivesRemain = 0;

int g_iPlayerEquipGear = -1;
static const int g_iRadioGearID = 4;
int g_iTotalAliveEnemies = 0;

bool g_bIsMapChanging = false;
bool g_bIsGameEnd = false;
bool g_bIsRoundActive = false;

int g_iObjResEntity = -1;
int g_iObjResOffNumCPs = -1;
int g_iObjResOffActiveCP = -1;
char g_sObjResNetClass[32];

bool ga_bPickSquad[MAXPLAYERS + 1];

bool g_bLateLoad = false;

// CA countdown state
static const char g_sCASound1[] = "hq/outpost/outpost_nextwave8.ogg";
static const char g_sCASound2[] = "hq/outpost/outpost_nextwave5.ogg";

Handle g_hCACountdownTimer = null;
Handle g_hCAProbeTimer = null;
Handle g_hCAMonitorTimer = null;

int g_iCADelay = 0;
int g_iCADelayFinale = 0;
int g_iCACountdownLeft = 0;
bool g_bCAFinaleCountdown = false;
float g_fCAWarnRadius = 350.0;

// ------------------------------------------------------------
// Plugin info
// ------------------------------------------------------------

public Plugin myinfo = {
	name		= "bm_botrespawn",
	author		= "Nullifidian + ChatGPT",
	description	= "Respawns bots at custom spawn locations + integrated CA countdown and spawn warnings",
	version		= PL_VERSION
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

// ------------------------------------------------------------
// Plugin start / map start / end
// ------------------------------------------------------------

public void OnPluginStart() {
	if ((g_hGameConfig = LoadGameConfigFile("insurgency.games")) == INVALID_HANDLE)
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");

	if ((g_iPlayerEquipGear = FindSendPropInfo("CINSPlayer", "m_EquippedGear")) == -1)
		SetFailState("Offset \"m_EquippedGear\" not found!");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(g_hGameConfig, SDKConf_Signature, "ForceRespawn");
	if ((g_hForceRespawn = EndPrepSDKCall()) == INVALID_HANDLE)
		SetFailState("Fatal Error: Unable to find signature for \"ForceRespawn\"!");

	SetupCvars();
	
	HookEvent("player_spawn",				Event_PlayerSpawn);
	HookEvent("player_death",				Event_PlayerDeath);
	HookEvent("object_destroyed",			Event_ObjDone_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured",		Event_ObjDone_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("game_end",					Event_GameEnd, EventHookMode_PostNoCopy);
	HookEvent("round_start",				Event_RoundStart);
	HookEvent("round_end",					Event_RoundEnd);
	HookEvent("player_pick_squad",			Event_PlayerPickSquad_Post, EventHookMode_Post);
	HookEvent("player_team",				Event_PlayerTeam_Post, EventHookMode_Post);

	HookEvent("object_destroyed",			Event_Objectives_Pre, EventHookMode_Pre);
	HookEvent("controlpoint_captured",		Event_Objectives_Pre, EventHookMode_Pre);

	// CA countdown hooks
	HookEvent("controlpoint_captured",		CA_Event_ControlPointCaptured);
	HookEvent("object_destroyed",			CA_Event_ObjectDestroyed);

	LoadTranslations("common.phrases");

	RegAdminCmd("sm_respawn",	cmd_respawn, ADMFLAG_SLAY, "sm_respawn <#userid|name|@all|@bots|@humans|@me> - Respawn player(s).");
	RegAdminCmd("sm_bots",		cmd_bots, ADMFLAG_BAN, "sm_bots - How many bots alive and lives remain.");
	RegAdminCmd("sm_botrespawn_reload", Cmd_ReloadSpawns, ADMFLAG_RCON, "Reload and validate this map's spawn file without resetting lives.");
	RegAdminCmd("sm_botspawn_stats", Cmd_SpawnStats, ADMFLAG_RCON, "Show proximity-cache work counters; optional argument: reset.");
	RegAdminCmd("sm_botspawn_failures", Cmd_SpawnFailures, ADMFLAG_RCON, "List suspected spawn failures for this map in your console.");
	RegAdminCmd("sm_botspawn_mark", Cmd_MarkSpawnArea, ADMFLAG_RCON, "Mark the aimed-at area for later review: sm_botspawn_mark [note]");
	g_SpawnFailures = new StringMap();

	if (g_bLateLoad) {
		g_bIsRoundActive = true;

		int iClass;
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i))
				continue;

			BM_ResetClientState(i);

			if (GetClientTeam(i) != TEAM_INSURGENT)
				continue;

			iClass = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iPlayerClass", _, i);

			if (iClass == gc_iTank)
				ga_bIsTank[i] = true;
			else if (iClass == gc_iBomber)
				ga_bIsBomber[i] = true;
		}
	}

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart() {
	g_iReviewBeam = PrecacheModel("materials/sprites/laser.vmt", true);
	BM_AdvanceStage();
	g_SpawnFailures.Clear();
	BM_ResetSpawnStats();
	for (int client = 1; client <= MaxClients; client++)
		BM_ResetMovementState(client);
	char map[64];
	GetCurrentMap(map, sizeof map);

	BM_FreeAllSpawns();

	// Cache OR + CP info (may be -1 early, but we clamp)
	g_iNumCPs = ObjectiveResource_GetProp("m_iNumControlPoints");
	if (g_iNumCPs < 0 || g_iNumCPs > MAX_CPS) {
		g_iNumCPs = MAX_CPS;
	}

	g_iActiveCP = ObjectiveResource_GetProp("m_nActivePushPointIndex");
	if (g_iActiveCP < 0)
		g_iActiveCP = 0;

	if (g_iActiveCP >= g_iNumCPs && g_iNumCPs > 0)
		g_iActiveCP = g_iNumCPs - 1;

	if (!LoadSpawnsForMap(map))
		LogError("[BM] Spawn file not loaded for %s: %s", map, g_sSpawnLoadError);

	if (!g_bLateLoad)
		g_bIsRoundActive = false;
		
	g_bLateLoad = false;
	
	g_bIsMapChanging = false;
	g_bIsGameEnd = false;

	ResetTankBomberRespawnCount();

	// CA countdown sounds
	PrecacheSound(g_sCASound1, true);
	PrecacheSound(g_sCASound2, true);

	// Init CA delay cvars once entities are ready
	CreateTimer(0.1, CA_Timer_InitConVars, _, TIMER_FLAG_NO_MAPCHANGE);

	CreateTimer(30.0, Timer_Enemies_Remaining, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(5.0, Timer_MapStart, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(60.0, Timer_CheckSpawnMovedGlobal, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_MapStart(Handle timer) {
	ServerCommand("exec betterbots.cfg");
	return Plugin_Stop;
}

public void OnMapEnd() {
	g_bIsMapChanging = true;
	g_bIsRoundActive = false;
	BM_AdvanceStage();
	g_iObjResEntity = -1;
	g_sObjResNetClass[0] = '\0';

	BM_FreeAllSpawns();
}

public void OnPluginEnd() {
	BM_AdvanceStage();
	delete g_SpawnFailures;
	BM_FreeAllSpawns();

	if (g_hForceRespawn != null) {
		delete g_hForceRespawn;
		g_hForceRespawn = null;
	}
	if (g_hGameConfig != null) {
		delete g_hGameConfig;
		g_hGameConfig = null;
	}
}

static void BM_ResetClientState(int client) {
	BM_CancelRespawn(client, true);
	BM_InvalidateSpawnCache();
	ga_bPickSquad[client] = false;
	ga_bIsTank[client] = false;
	ga_bIsBomber[client] = false;
	ga_bRecoveringStuck[client] = false;
	ga_iLifeSerial[client] = 0;
	BM_ResetMovementState(client);
}

static void BM_ResetMovementState(int client) {
	ga_iSpawnCP[client] = -1;
	ga_bSpawnCA[client] = false;
	ga_bBotSpawnOriginValid[client] = false;
	ga_iBotNoMoveChecks[client] = 0;
	ga_fBotSpawnTime[client] = 0.0;
	ga_fBotSpawnOrigin[client][0] = 0.0;
	ga_fBotSpawnOrigin[client][1] = 0.0;
	ga_fBotSpawnOrigin[client][2] = 0.0;
	ga_fBotLastPos[client][0] = 0.0;
	ga_fBotLastPos[client][1] = 0.0;
	ga_fBotLastPos[client][2] = 0.0;
	ga_fBotLastMoveTime[client] = 0.0;
	ga_iBotIdleMoveChecks[client] = 0;
}

public void OnClientPostAdminCheck(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	BM_ResetClientState(client);
}

public void OnClientDisconnect(int client) {
	if (client < 1 || client > MaxClients)
		return;

	BM_ResetClientState(client);
}

public Action Event_PlayerTeam_Post(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client < 1 || client > MaxClients)
		return Plugin_Continue;

	BM_CancelRespawn(client, true);
	BM_ResetMovementState(client);
	BM_InvalidateSpawnCache();
	ga_bPickSquad[client] = false;
	ga_bIsTank[client] = false;
	ga_bIsBomber[client] = false;

	if (!event.GetBool("isbot") && event.GetInt("team") == TEAM_SECURITY)
		BM_MaybeBoostBotLives();

	return Plugin_Continue;
}

public Action Event_PlayerPickSquad_Post(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Continue;

	ga_bPickSquad[client] = true;

	if (GetClientTeam(client) == TEAM_INSURGENT) {
		char class_template[64];
		event.GetString("class_template", class_template, sizeof(class_template));

		if (StrContains(class_template, "tank", false) != -1) {
			ga_bIsTank[client] = true;
			ga_bIsBomber[client] = false;
		}
		else if (StrContains(class_template, "bomber", false) != -1) {
			ga_bIsBomber[client] = true;
			ga_bIsTank[client] = false;
		}
		else {
			ga_bIsTank[client] = false;
			ga_bIsBomber[client] = false;
		}
	}

	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	BM_AdvanceStage();
	g_bIsGameEnd = false;
	for (int client = 1; client <= MaxClients; client++)
		BM_ResetMovementState(client);
	g_iActiveCP = 0;
	g_bIsRoundActive = true;
	BM_StartProxGrace(g_fProximityGraceSeconds);
	SetBotLives();
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	g_bIsRoundActive = false;
	BM_AdvanceStage();
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Continue;
	if (!IsFakeClient(client))
		BM_InvalidateSpawnCache();

	BM_CancelRespawn(client, true);
	ga_iLifeSerial[client]++;
	BM_ResetMovementState(client);
	if (!IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_INSURGENT)
		return Plugin_Continue;

	if (g_bIsRoundActive)
		TeleportBot(client);
	GetClientAbsOrigin(client, ga_fBotLastPos[client]);
	ga_fBotLastMoveTime[client] = GetGameTime();
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim > 0 && IsClientInGame(victim) && !IsFakeClient(victim))
		BM_InvalidateSpawnCache();
	if (victim < 1 || !IsClientInGame(victim) || !IsFakeClient(victim) || GetClientTeam(victim) != TEAM_INSURGENT)
		return Plugin_Continue;

	BM_ResetMovementState(victim);
	BM_QueueRespawn(victim, ga_bRecoveringStuck[victim]);
	return Plugin_Continue;
}

static void BM_QueueRespawn(int bot, bool recovery) {
	if (!g_bIsRoundActive || g_bIsGameEnd || g_bIsMapChanging || g_iBotLivesRemain < 1 || ga_hRespawnTimer[bot] != null)
		return;

	int specialClass = 0;
	if (ga_bIsBomber[bot]) {
		if (g_iBomberRespawCount >= g_iBomberRespawnsMax)
			return;
		specialClass = gc_iBomber;
	}
	else if (ga_bIsTank[bot]) {
		if (g_iTankRespawnCount >= g_iTankRespawnsMax)
			return;
		specialClass = gc_iTank;
	}

	ga_iRespawnStage[bot] = g_iStageGeneration;
	ga_iRespawnClass[bot] = specialClass;
	ga_bRespawnCharged[bot] = !recovery;
	if (!recovery)
		g_iBotLivesRemain--;
	if (specialClass == gc_iBomber)
		g_iBomberRespawCount++;
	else if (specialClass == gc_iTank)
		g_iTankRespawnCount++;
	ga_hRespawnTimer[bot] = CreateTimer(0.05, Timer_RespawnBot, GetClientUserId(bot), TIMER_FLAG_NO_MAPCHANGE);
}

static void BM_RefundRespawn(int stage, bool charged, int specialClass) {
	if (stage != g_iStageGeneration)
		return;
	if (charged)
		g_iBotLivesRemain++;
	if (specialClass == gc_iBomber && g_iBomberRespawCount > 0)
		g_iBomberRespawCount--;
	else if (specialClass == gc_iTank && g_iTankRespawnCount > 0)
		g_iTankRespawnCount--;
}

static void BM_CancelRespawn(int bot, bool refund) {
	if (ga_hRespawnTimer[bot] == null)
		return;
	delete ga_hRespawnTimer[bot];
	if (refund)
		BM_RefundRespawn(ga_iRespawnStage[bot], ga_bRespawnCharged[bot], ga_iRespawnClass[bot]);
	ga_bRespawnCharged[bot] = false;
	ga_iRespawnClass[bot] = 0;
}

static void BM_AdvanceStage() {
	g_iStageGeneration++;
	for (int bot = 1; bot <= MaxClients; bot++)
		BM_CancelRespawn(bot, false);
	CA_ResetCountdownTimer();
	delete g_hCAProbeTimer;
	delete g_hCAMonitorTimer;
	BM_InvalidateSpawnCache();
}

public Action Timer_RespawnBot(Handle timer, any userid) {
	int bot = GetClientOfUserId(userid);
	if (bot < 1 || ga_hRespawnTimer[bot] != timer)
		return Plugin_Stop;

	ga_hRespawnTimer[bot] = null;
	int stage = ga_iRespawnStage[bot];
	int specialClass = ga_iRespawnClass[bot];
	bool charged = ga_bRespawnCharged[bot];
	ga_bRespawnCharged[bot] = false;
	ga_iRespawnClass[bot] = 0;
	if (stage != g_iStageGeneration || !g_bIsRoundActive || g_bIsGameEnd || g_bIsMapChanging || !IsClientInGame(bot) || !IsFakeClient(bot) || IsPlayerAlive(bot) || GetClientTeam(bot) != TEAM_INSURGENT) {
		BM_RefundRespawn(stage, charged, specialClass);
		return Plugin_Stop;
	}

	int lifeSerial = ga_iLifeSerial[bot];
	SDKCall(g_hForceRespawn, bot);
	if (GetClientOfUserId(userid) != bot || (ga_iLifeSerial[bot] == lifeSerial && !IsPlayerAlive(bot)))
		BM_RefundRespawn(stage, charged, specialClass);
	return Plugin_Stop;
}

public Action Event_ObjDone_NoCopy(Event event, const char[] name, bool dontBroadcast) {
	if (g_iActiveCP < g_iNumCPs)
		g_iActiveCP++;

	RequestFrame(Frame_SetBotLives, g_iStageGeneration);
	return Plugin_Continue;
}

public Action Event_Objectives_Pre(Event event, const char[] name, bool dontBroadcast) {
	BM_AdvanceStage();
	g_iBotLivesRemain = 0;
	
	if (g_fProximityGraceSeconds > 0.0)
		BM_StartProxGrace(g_fProximityGraceSeconds + 1.1);

	bool finalCA = g_iActiveCP + 1 == g_iNumCPs;
	if (finalCA || GetRandomFloat(0.0, 1.0) < g_fCounterAttackChance) {
		BM_CleanUpBotsForCounterAttack();
		int minDuration = finalCA ? g_iMinFinalCounterAttackDuration : g_iMinCounterAttackDuration;
		int maxDuration = finalCA ? g_iMaxFinalCounterAttackDuration : g_iMaxCounterAttackDuration;
		if (minDuration > maxDuration)
			maxDuration = minDuration;
		SetConVarInt(cv_hCounterAttackDuration, GetRandomInt(minDuration, maxDuration), true, false);
		SetConVarInt(cv_hCounterAttackDisable, 0, true, false);
		SetConVarInt(cv_hCounterAttackAlways, 1, true, false);
	}
	else
		SetConVarInt(cv_hCounterAttackDisable, 1, true, false);

	return Plugin_Continue;
}

void Frame_SetBotLives(any stage) {
	if (stage != g_iStageGeneration || !g_bIsRoundActive || g_bIsGameEnd || g_bIsMapChanging)
		return;
	SetBotLives();
	if (IsCounterAttack() && g_hCAMonitorTimer == null)
		g_hCAMonitorTimer = CreateTimer(1.0, TimerR_MonitorCA, stage, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action TimerR_MonitorCA(Handle timer, any stage) {
	if (stage != g_iStageGeneration || g_bIsGameEnd || g_bIsMapChanging || !g_bIsRoundActive) {
		g_hCAMonitorTimer = null;
		return Plugin_Stop;
	}

	if (!IsCounterAttack()) {
		g_hCAMonitorTimer = null;
		BM_AdvanceStage();
		BM_StartProxGrace(g_fProximityGraceSeconds);
		SetBotLives();
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action CA_Timer_InitConVars(Handle timer) {
	g_cvCADelay = FindConVar("mp_checkpoint_counterattack_delay");
	if (!g_cvCADelay)
		SetFailState("mp_checkpoint_counterattack_delay not found!");

	g_iCADelay = g_cvCADelay.IntValue;
	g_cvCADelay.AddChangeHook(OnConVarChanged);

	g_cvCADelayFinale = FindConVar("mp_checkpoint_counterattack_delay_finale");
	if (!g_cvCADelayFinale)
		SetFailState("mp_checkpoint_counterattack_delay_finale not found!");

	g_iCADelayFinale = g_cvCADelayFinale.IntValue;
	g_cvCADelayFinale.AddChangeHook(OnConVarChanged);

	return Plugin_Stop;
}

public Action CA_Event_ControlPointCaptured(Event event, const char[] name, bool dontBroadcast) {
	if (g_bIsRoundActive && !g_bIsGameEnd && !g_bIsMapChanging && event.GetInt("team") == TEAM_SECURITY && g_hCAProbeTimer == null)
		g_hCAProbeTimer = CreateTimer(1.0, CA_Timer_IsCounterAttack, g_iStageGeneration, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action CA_Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast) {
	if (g_bIsRoundActive && !g_bIsGameEnd && !g_bIsMapChanging && event.GetInt("attackerteam") == TEAM_SECURITY && g_hCAProbeTimer == null)
		g_hCAProbeTimer = CreateTimer(1.0, CA_Timer_IsCounterAttack, g_iStageGeneration, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action CA_Timer_IsCounterAttack(Handle timer, any stage) {
	g_hCAProbeTimer = null;

	if (stage == g_iStageGeneration && g_bIsRoundActive && !g_bIsGameEnd && !g_bIsMapChanging && IsCounterAttack() && g_hCACountdownTimer == null)
		CA_StartCountdownForCurrentStage();

	return Plugin_Stop;
}

void CA_StartCountdownForCurrentStage() {
	if (g_hCACountdownTimer != null)
		return;

	if (OR_Cache() <= 0)
		return;

	int ncp = ObjectiveResource_GetProp("m_iNumControlPoints") - 1;
	int acp = ObjectiveResource_GetProp("m_nActivePushPointIndex");
	if (ncp < 0 || acp < 0)
		return;

	g_bCAFinaleCountdown = (acp == ncp);

	int delay = g_bCAFinaleCountdown ? g_iCADelayFinale : g_iCADelay;
	if (delay <= 0)
		return;

	g_iCACountdownLeft = delay;

	// Run countdown + proximity update every 1 seconds
	g_hCACountdownTimer = CreateTimer(1.0, CA_Timer_CountdownTick, g_iStageGeneration, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action CA_Timer_CountdownTick(Handle timer, any stage) {
	if (stage != g_iStageGeneration || !g_bIsRoundActive || g_bIsGameEnd || g_bIsMapChanging || !IsCounterAttack()) {
		g_hCACountdownTimer = null;
		g_iCACountdownLeft = 0;
		g_bCAFinaleCountdown = false;
		return Plugin_Stop;
	}
	// We step in 2-second chunks to match the timer interval
	g_iCACountdownLeft -= 2;

	if (g_iCACountdownLeft <= 0) {
		CA_PlayCountdownSound();
		g_hCACountdownTimer = null;
		g_iCACountdownLeft = 0;
		g_bCAFinaleCountdown = false;
		return Plugin_Stop;
	}

	CA_UpdateCountdownHUD();
	return Plugin_Continue;
}

void CA_PlayCountdownSound() {
	EmitSoundToAll(GetRandomInt(1, 2) == 1 ? g_sCASound1 : g_sCASound2);
}

void CA_ResetCountdownTimer() {
	if (g_hCACountdownTimer != null) {
		KillTimer(g_hCACountdownTimer);
		g_hCACountdownTimer = null;
	}
	g_iCACountdownLeft = 0;
	g_bCAFinaleCountdown = false;
}

// Which CP's CA spawns are used for the current counter-attack?
static int BM_GetCurrentCACpIndex() {
	if (g_iNumCPs <= 0)
		return -1;

	int cpC = ClampCP(g_iActiveCP - 1);

	if (cpC < 0 || cpC >= MAX_CPS)
		return -1;

	if (g_CASpawns[cpC] == null || g_CASpawns[cpC].Length <= 0)
		return -1;

	return cpC;
}

void CA_UpdateCountdownHUD() {
	int cpIndex = (IsCounterAttack() && g_fCAWarnRadius > 0.0) ? BM_GetCurrentCACpIndex() : -1;
	float radiusSq = g_fCAWarnRadius * g_fCAWarnRadius;
	int numSpawns = cpIndex >= 0 ? g_CASpawns[cpIndex].Length : 0;

	float playerPos[3];
	float spawnPos[3];

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		bool bNear = false;
		if (numSpawns > 0 && IsPlayerAlive(i) && GetClientTeam(i) == TEAM_SECURITY) {
			GetClientAbsOrigin(i, playerPos);
			for (int s = 0; s < numSpawns; s++) {
				g_CASpawns[cpIndex].GetArray(s, spawnPos, 3);
				if (GetVectorDistance(playerPos, spawnPos, true) <= radiusSq) {
					bNear = true;
					break;
				}
			}
		}

		if (bNear)
			PrintCenterText(i, "Insurgents counter-attacking in %d\nWarning! You are very close to enemy counter-attack spawns!", g_iCACountdownLeft);
		else
			PrintCenterText(i, "Insurgents counter-attacking in %d", g_iCACountdownLeft);
	}
}

static void BM_StartProxGrace(float seconds) {
	g_fProxGraceUntil = GetGameTime() + seconds;
}

static bool BM_InProxGrace() {
	return GetGameTime() < g_fProxGraceUntil;
}

static int BM_CollectSecurityPositions(float positions[32][3], bool eyePos = false) {
	int count = 0;

	for (int i = 1; i <= MaxClients && count < 32; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SECURITY)
			continue;

		if (eyePos)
			GetClientEyePosition(i, positions[count]);
		else
			GetClientAbsOrigin(i, positions[count]);

		count++;
	}

	return count;
}

static bool BM_PickRandomSpawnFromList(ArrayList spawns, float outVec[3]) {
	if (spawns == null || spawns.Length <= 0)
		return false;

	int index = GetRandomInt(0, spawns.Length - 1);
	spawns.GetArray(index, outVec, 3);
	return true;
}

static bool BM_IsSpawnSafe(const float candidate[3], float humanOrigins[32][3], int hcount, float minDistSq) {
	for (int i = 0; i < hcount; i++) {
		g_iDistanceChecks++;
		if (GetVectorDistance(candidate, humanOrigins[i], true) < minDistSq)
			return false;
	}

	return true;
}

static void BM_InvalidateSpawnCache() {
	g_iSafetyTick = -1;
}

static void BM_PrepareSpawnCache() {
	int tick = GetGameTickCount();
	if (g_bSpawnCache && g_iSafetyTick == tick)
		return;
	g_iSafetyTick = tick;
	g_iSafetyEpoch++;
	g_iHumanCount = BM_CollectSecurityPositions(g_HumanOrigins);
	g_iPositionCollections++;
}

static void BM_ResetSpawnStats() {
	g_iPositionCollections = 0;
	g_iSafetyChecks = 0;
	g_iSafetyCacheHits = 0;
	g_iDistanceChecks = 0;
}

static bool BM_FindSafeSpawnForCP(int cpIndex, float minDistSq, float outVec[3]) {
	if (cpIndex < 0 || cpIndex >= MAX_CPS)
		return false;

	ArrayList spawns = g_CPSpawns[cpIndex];
	if (spawns == null || spawns.Length <= 0)
		return false;

	if (g_iHumanCount <= 0 || minDistSq <= 0.0)
		return BM_PickRandomSpawnFromList(spawns, outVec);

	int count = spawns.Length;
	int start = GetRandomInt(0, count - 1);
	float candidate[3];

	for (int offset = 0; offset < count; offset++) {
		int index = (start + offset) % count;
		g_iSafetyChecks++;
		bool safe;
		if (g_bSpawnCache && g_SpawnSafety[cpIndex].Get(index, 0) == g_iSafetyEpoch) {
			safe = g_SpawnSafety[cpIndex].Get(index, 1) != 0;
			g_iSafetyCacheHits++;
		}
		else {
			spawns.GetArray(index, candidate, 3);
			safe = BM_IsSpawnSafe(candidate, g_HumanOrigins, g_iHumanCount, minDistSq);
			if (g_bSpawnCache) {
				g_SpawnSafety[cpIndex].Set(index, g_iSafetyEpoch, 0);
				g_SpawnSafety[cpIndex].Set(index, safe, 1);
			}
		}
		if (!safe)
			continue;

		spawns.GetArray(index, candidate, 3);
		outVec[0] = candidate[0];
		outVec[1] = candidate[1];
		outVec[2] = candidate[2];
		return true;
	}

	return false;
}

static bool BM_IsBotVisibleToAnyHuman(int bot, float humanEyes[32][3], int hcount, float maxDistSq) {
	float botEye[3];
	GetClientEyePosition(bot, botEye);

	for (int i = 0; i < hcount; i++) {
		float distSq = GetVectorDistance(botEye, humanEyes[i], true);
		if (distSq > maxDistSq)
			continue;

		Handle trace = TR_TraceRayFilterEx(humanEyes[i], botEye, MASK_SOLID, RayType_EndPoint, TraceEntityFilterSolid);
		bool visible = false;

		if (!TR_DidHit(trace))
			visible = true;
		else {
			int hitEnt = TR_GetEntityIndex(trace);
			if (hitEnt == bot)
				visible = true;
		}

		delete trace;

		if (visible)
			return true;
	}

	return false;
}

static void BM_CleanUpBotsForCounterAttack() {
	// 2950 units ≈ 75 m → "relevant" distance for LOS checks
	const float kMaxVisDistSq = 8702500.0;	// 2950^2
	float humanEyes[32][3];
	int hcount = BM_CollectSecurityPositions(humanEyes, true);

	if (hcount <= 0)
		return;

	for (int bot = 1; bot <= MaxClients; bot++) {
		if (!IsClientInGame(bot) || !IsFakeClient(bot) || !IsPlayerAlive(bot) || GetClientTeam(bot) != TEAM_INSURGENT)
			continue;

		// Keep bots that are near + visible to any human
		if (BM_IsBotVisibleToAnyHuman(bot, humanEyes, hcount, kMaxVisDistSq))
			continue;

		ForcePlayerSuicide(bot);
	}
}

// ------------------------------------------------------------
// Teleport bots to custom spawns
// ------------------------------------------------------------

void TeleportBot(int client) {
	float vec[3];
	vec[0] = 0.0;
	vec[1] = 0.0;
	vec[2] = 0.0;

	int cp  = ClampCP(g_iActiveCP);
	int cpN = ClampCP(g_iActiveCP + 1);
	float minDistSq = g_fMinSpawnDistHuman * g_fMinSpawnDistHuman;
	int spawnCP = cp;
	bool inCA = IsCounterAttack();

	if (!inCA) {
		bool haveCurr = HasAnySpawnsCP(cp);
		bool haveNext = (cpN != cp) && HasAnySpawnsCP(cpN);

		if (!haveCurr && !haveNext)
			return;

		// During grace OR at last CP → original selection, no proximity checks
		if (BM_InProxGrace() || g_iActiveCP == g_iNumCPs - 1) {
			if (haveCurr && haveNext)
				spawnCP = GetRandomFloat(0.0, 1.0) <= 0.8 ? cp : cpN;
			else
				spawnCP = haveCurr ? cp : cpN;
			if (!BM_PickRandomSpawnFromList(g_CPSpawns[spawnCP], vec))
				return;
		}
		else {
			if (minDistSq > 0.0)
				BM_PrepareSpawnCache();
			bool pickedAny = false;

			// 2) Try current CP first (if it has spawns)
			if (haveCurr) {
				pickedAny = BM_FindSafeSpawnForCP(cp, minDistSq, vec);
			}

			// 3) Then try next CP (with proximity) if not found yet
			if (!pickedAny && haveNext) {
				spawnCP = cpN;
				pickedAny = BM_FindSafeSpawnForCP(cpN, minDistSq, vec);
			}

			// 4) If still nothing, scan forward through later CPs (cpN+1 .. g_iNumCPs-1)
			if (!pickedAny && g_iNumCPs > 0) {
				for (int c = g_iActiveCP + 2; c < g_iNumCPs; c++) {
					if (!HasAnySpawnsCP(c))
						continue;

					if (BM_FindSafeSpawnForCP(c, minDistSq, vec)) {
						spawnCP = c;
						pickedAny = true;
						break;
					}
				}
			}

			// 5) Finally, scan backwards through earlier CPs (cp-1 .. 0)
			if (!pickedAny && g_iNumCPs > 0) {
				for (int c = g_iActiveCP - 1; c >= 0; c--) {
					if (!HasAnySpawnsCP(c))
						continue;

					if (BM_FindSafeSpawnForCP(c, minDistSq, vec)) {
						spawnCP = c;
						pickedAny = true;
						break;
					}
				}
			}

			if (!pickedAny)
				// No safe custom spawn anywhere → fall back to default game spawn
				return;
		}
	}
	else {
		// Counter-attack uses the CA spawn list for the previous objective.
		int cpC = ClampCP(g_iActiveCP - 1);
		spawnCP = cpC;
		if (g_CASpawns[cpC] == null || g_CASpawns[cpC].Length <= 0)
			return;

		if (!BM_PickRandomSpawnFromList(g_CASpawns[cpC], vec))
			return;
	}

	if (vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0)
		return;

	TeleportEntity(client, vec, NULL_VECTOR, NULL_VECTOR);

	ga_fBotSpawnOrigin[client][0] = vec[0];
	ga_fBotSpawnOrigin[client][1] = vec[1];
	ga_fBotSpawnOrigin[client][2] = vec[2];
	ga_fBotSpawnTime[client] = GetGameTime();
	ga_iBotNoMoveChecks[client] = 0;
	ga_bBotSpawnOriginValid[client] = true;
	ga_iSpawnCP[client] = spawnCP;
	ga_bSpawnCA[client] = inCA;
}

// ------------------------------------------------------------
// Global stuck check timer
// ------------------------------------------------------------

static void BM_RecordSpawnFailure(int client) {
	int cp = ga_iSpawnCP[client];
	if (cp < 0 || cp >= MAX_CPS)
		return;
	char key[160];
	Format(key, sizeof key, "CP%d %s (%.6f, %.6f, %.6f)", cp, ga_bSpawnCA[client] ? "CA" : "CP",
		ga_fBotSpawnOrigin[client][0], ga_fBotSpawnOrigin[client][1], ga_fBotSpawnOrigin[client][2]);
	int count = 0;
	g_SpawnFailures.GetValue(key, count);
	g_SpawnFailures.SetValue(key, ++count);
	char map[64], path[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof map);
	BuildPath(Path_SM, path, sizeof path, "logs/bm_botspawn_failures.log");
	LogToFileEx(path, "map=%s suspect=%s failures=%d age=%.1fs bot_userid=%d (movement check, not proof of a bad spawn)",
		map, key, count, GetGameTime() - ga_fBotSpawnTime[client], GetClientUserId(client));
}

static void BM_RecoverStuckBot(int client, bool spawnFailure) {
	if (spawnFailure)
		BM_RecordSpawnFailure(client);
	BM_ResetMovementState(client);
	ga_bRecoveringStuck[client] = true;
	ForcePlayerSuicide(client);
	ga_bRecoveringStuck[client] = false;
}

public Action Timer_CheckSpawnMovedGlobal(Handle timer, any data) {
	// Let the timer keep running; just skip logic when round is not active.
	if (!g_bIsRoundActive || g_bIsMapChanging || g_bIsGameEnd)
		return Plugin_Continue;

	// ----- BASE CONSTANTS (do not change at runtime) -----

	// Spawn-stuck: how long after teleport we even start checking
	const float kMinSpawnStuckTime = 45.0;		// seconds after TeleportBot

	// Spawn-stuck: radius from spawn to still count as "never left"
	// 50 units → 50 * 50 = 2500 (squared)
	const float kSpawnMoveDistSq = 2500.0;

	// Normal spawn-stuck: how many *consecutive* checks they must fail
	const int kSpawnRequiredNoMoveChecks_Normal = 1;

	// During COUNTER-ATTACK we want this faster:
	const int kSpawnRequiredNoMoveChecks_CA = 1;

	// Nav-stuck (general idle): how long they must be idle before we care
	const float kNavIdleMinTime_Normal = 120.0;	// normal: ~2+ minutes

	// During COUNTER-ATTACK we shorten this more:
	const float kNavIdleMinTime_CA = 60.0;		// ~1–1.5 minutes after last movement

	// Nav-stuck: how far they must move between checks to count as "moved"
	const float kNavMoveDistSq = 10000.0;		// 100 units squared

	// Nav-stuck: how many *consecutive* idle checks before we kill
	const int kNavRequiredIdleChecks = 1;

	float now = GetGameTime();

	// Decide thresholds based on whether a counter-attack is currently running.
	bool bInCounterAttack = IsCounterAttack();

	int spawnRequiredNoMoveChecks = bInCounterAttack
		? kSpawnRequiredNoMoveChecks_CA
		: kSpawnRequiredNoMoveChecks_Normal;

	float navIdleMinTime = bInCounterAttack
		? kNavIdleMinTime_CA
		: kNavIdleMinTime_Normal;

	for (int client = 1; client <= MaxClients; client++) {
		// We only track alive insurgent bots.
		if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_INSURGENT) {
			// Clear tracking for anything else (humans, specs, dead, etc.)
			ga_bBotSpawnOriginValid[client] = false;
			ga_iBotNoMoveChecks[client] = 0;
			ga_fBotSpawnTime[client] = 0.0;

			ga_fBotLastMoveTime[client] = 0.0;
			ga_iBotIdleMoveChecks[client] = 0;
			continue;
		}

		float origin[3];
		GetClientAbsOrigin(client, origin);

		// ---------------- SPAWN-STUCK CHECK ----------------
		if (ga_bBotSpawnOriginValid[client]) {
			// Only start caring once they've had some time to move away from spawn.
			if (now - ga_fBotSpawnTime[client] >= kMinSpawnStuckTime) {
				float dist2Spawn = GetVectorDistance(origin, ga_fBotSpawnOrigin[client], true);

				if (dist2Spawn <= kSpawnMoveDistSq) {
					// Still basically at custom spawn
					ga_iBotNoMoveChecks[client]++;

					if (ga_iBotNoMoveChecks[client] >= spawnRequiredNoMoveChecks) {
						BM_RecoverStuckBot(client, true);
						continue;
					}
				}
				else {
					// Left spawn radius → stop spawn-based tracking for this bot.
					ga_bBotSpawnOriginValid[client] = false;
					ga_iBotNoMoveChecks[client] = 0;
				}
			}
		}

		// ---------------- NAV-STUCK (GENERAL IDLE) CHECK ----------------

		// First-time init for nav-stuck tracking
		if (ga_fBotLastMoveTime[client] <= 0.0) {
			ga_fBotLastPos[client][0] = origin[0];
			ga_fBotLastPos[client][1] = origin[1];
			ga_fBotLastPos[client][2] = origin[2];
			ga_fBotLastMoveTime[client] = now;
			ga_iBotIdleMoveChecks[client] = 0;
			continue;
		}

		float dist2Nav = GetVectorDistance(origin, ga_fBotLastPos[client], true);

		if (dist2Nav > kNavMoveDistSq) {
			// Bot has moved enough since last check → reset idle tracking.
			ga_fBotLastPos[client][0] = origin[0];
			ga_fBotLastPos[client][1] = origin[1];
			ga_fBotLastPos[client][2] = origin[2];
			ga_fBotLastMoveTime[client] = now;
			ga_iBotIdleMoveChecks[client] = 0;
			continue;
		}

		// Hasn't moved enough to count as "movement"
		float idleTime = now - ga_fBotLastMoveTime[client];
		if (idleTime < navIdleMinTime)
			// Not idle long enough yet; keep waiting.
			continue;

		ga_iBotIdleMoveChecks[client]++;

		if (ga_iBotIdleMoveChecks[client] >= kNavRequiredIdleChecks) {
			BM_RecoverStuckBot(client, false);
		}
	}

	return Plugin_Continue;
}

// ------------------------------------------------------------
// Misc helpers
// ------------------------------------------------------------

static int ClampCP(int cp) {
	int max = g_iNumCPs - 1;
	if (max < 0) max = 0;
	if (max >= MAX_CPS) max = MAX_CPS - 1;
	if (cp < 0) return 0;
	if (cp > max) return max;
	return cp;
}

static bool HasAnySpawnsCP(int cp) {
	cp = ClampCP(cp);

	if (g_CPSpawns[cp] == null)
		return false;

	return (g_CPSpawns[cp].Length > 0);
}

public bool TraceEntityFilterSolid(int entity, int contentsMask, any data) {
	return (entity > MaxClients);
}

static void BM_FreeAllSpawns() {
	BM_InvalidateSpawnCache();
	for (int i = 0; i < MAX_CPS; i++) {
		delete g_SpawnSafety[i];
		if (g_CPSpawns[i] != null) {
			delete g_CPSpawns[i];
			g_CPSpawns[i] = null;
		}
		if (g_CASpawns[i] != null) {
			delete g_CASpawns[i];
			g_CASpawns[i] = null;
		}
	}
}

bool LoadSpawnsForMap(const char[] map) {
	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof path, "addons/sourcemod/data/bm_botspawns/%s.txt", map);
	File f = OpenFile(path, "r");
	if (f == null) {
		strcopy(g_sSpawnLoadError, sizeof g_sSpawnLoadError, "file missing or unreadable");
		return false;
	}

	ArrayList pendingCP[MAX_CPS], pendingCA[MAX_CPS];
	bool seenCP[MAX_CPS], seenCA[MAX_CPS];
	int cp = -1;
	int depth = 0;
	int pendingDepth = 0;
	int lineNumber = 0;
	int sections = 0;
	bool valid = true;
	char line[256];
	while (f.ReadLine(line, sizeof line)) {
		lineNumber++;
		if (strlen(line) >= sizeof line - 1) {
			valid = false;
			break;
		}
		if (lineNumber == 1 && line[0] == 0xEF && line[1] == 0xBB && line[2] == 0xBF)
			strcopy(line, sizeof line, line[3]);
		int comment = StrContains(line, "//");
		if (comment >= 0)
			line[comment] = '\0';
		TrimString(line);
		if (line[0] == '\0')
			continue;
		if (StrEqual(line, "{")) {
			if (pendingDepth == 0) {
				valid = false;
				break;
			}
			depth = pendingDepth;
			pendingDepth = 0;
			continue;
		}
		if (StrEqual(line, "}")) {
			if (pendingDepth != 0 || depth == 0) {
				valid = false;
				break;
			}
			depth--;
			if (depth == 0)
				cp = -1;
			continue;
		}
		int len = strlen(line);
		if (pendingDepth != 0 || len < 2 || line[0] != '"' || line[len - 1] != '"') {
			valid = false;
			break;
		}
		line[len - 1] = '\0';
		char value[256];
		strcopy(value, sizeof value, line[1]);
		if (depth == 0) {
			int number;
			int digits = strlen(value) - 2;
			if (value[0] != 'C' || value[1] != 'P' || digits <= 0 || StringToIntEx(value[2], number) != digits || number < 0 || number >= MAX_CPS) {
				valid = false;
				break;
			}
			if (seenCP[number]) {
				valid = false;
				break;
			}
			cp = number;
			seenCP[cp] = true;
			sections++;
			pendingDepth = 1;
		}
		else if (StrEqual(value, "CA")) {
			if (depth != 1 || seenCA[cp]) {
				valid = false;
				break;
			}
			seenCA[cp] = true;
			pendingDepth = 2;
		}
		else {
			float pos[3];
			if (!BM_ParseVec3(value, pos)) {
				valid = false;
				break;
			}
			if (depth == 2) {
				if (pendingCA[cp] == null)
					pendingCA[cp] = new ArrayList(3);
				pendingCA[cp].PushArray(pos, 3);
			}
			else {
				if (pendingCP[cp] == null)
					pendingCP[cp] = new ArrayList(3);
				pendingCP[cp].PushArray(pos, 3);
			}
		}
	}
	valid = valid && f.EndOfFile() && depth == 0 && pendingDepth == 0 && sections > 0;
	delete f;
	if (!valid) {
		for (int i = 0; i < MAX_CPS; i++) {
			delete pendingCP[i];
			delete pendingCA[i];
		}
		Format(g_sSpawnLoadError, sizeof g_sSpawnLoadError, "invalid or incomplete spawn data near line %d", lineNumber);
		return false;
	}

	BM_FreeAllSpawns();
	int counts[2];
	int emptyCache[2];
	for (int i = 0; i < MAX_CPS; i++) {
		g_CPSpawns[i] = pendingCP[i];
		g_CASpawns[i] = pendingCA[i];
		if (g_CPSpawns[i] != null) {
			g_SpawnSafety[i] = new ArrayList(2);
			int count = g_CPSpawns[i].Length;
			for (int j = 0; j < count; j++)
				g_SpawnSafety[i].PushArray(emptyCache, 2);
			counts[0] += count;
		}
		if (g_CASpawns[i] != null)
			counts[1] += g_CASpawns[i].Length;
	}
	g_sSpawnLoadError[0] = '\0';
	LogMessage("[BM] Loaded %s: %d CP spawns, %d CA spawns across %d objective sections.", map, counts[0], counts[1], sections);
	return true;
}

bool BM_ParseVec3(const char[] s, float out[3]) {
	char parts[4][64];
	if (ExplodeString(s, ",", parts, sizeof parts, sizeof parts[]) != 3)
		return false;
	for (int i = 0; i < 3; i++) {
		if (strlen(parts[i]) >= sizeof parts[] - 1)
			return false;
		TrimString(parts[i]);
		int len = strlen(parts[i]);
		if (len == 0 || StringToFloatEx(parts[i], out[i]) != len)
			return false;
		if ((view_as<int>(out[i]) & 0x7F800000) == 0x7F800000)
			return false;
	}
	return true;
}

// ------------------------------------------------------------
// Bot lives / counts
// ------------------------------------------------------------

void SetBotLives() {
	g_iBotLivesRemain = (g_iBotLives > 0 ? SecPlayersInGame() * g_iBotLives : 0);
	ResetTankBomberRespawnCount();
}

int SecPlayersInGame() {
	int n = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == TEAM_SECURITY)
			n++;
	}
	return n;
}

void BM_MaybeBoostBotLives() {
	// If at least 7 Security players and sm_botlives is below 10,
	// automatically raise it to 10.
	if (SecPlayersInGame() >= 7 && g_iBotLives < 10) {
		SetConVarInt(cv_hBotLives, 10, true, false);
		PrintToChatAll("\x070088cc[BM]\x01 7+ Security players detected - bot reinforcements raised to 10 per player.");
	}
}

// ------------------------------------------------------------
// Map change listener (currently unused helper)
// ------------------------------------------------------------

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
		if (IsMapValid(nextMap))
			g_bIsMapChanging = true;
	}
	return Plugin_Continue;
}

// ------------------------------------------------------------
// Objective resource helpers
// ------------------------------------------------------------

int OR_Cache(bool force = false) {
	if (force || g_iObjResEntity < 1 || !IsValidEntity(g_iObjResEntity)) {
		g_iObjResEntity = FindEntityByClassname(-1, "ins_objective_resource");
		if (g_iObjResEntity > 0) {
			GetEntityNetClass(g_iObjResEntity, g_sObjResNetClass, sizeof(g_sObjResNetClass));
			g_iObjResOffNumCPs = FindSendPropInfo(g_sObjResNetClass, "m_iNumControlPoints");
			g_iObjResOffActiveCP = FindSendPropInfo(g_sObjResNetClass, "m_nActivePushPointIndex");
		}
		else {
			g_sObjResNetClass[0] = '\0';
			g_iObjResOffNumCPs = -1;
			g_iObjResOffActiveCP = -1;
		}
	}
	else {
		char cls[32];
		GetEntityClassname(g_iObjResEntity, cls, sizeof(cls));
		if (!StrEqual(cls, "ins_objective_resource", false))
			return OR_Cache(true);
	}
	return g_iObjResEntity;
}

int ObjectiveResource_GetProp(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = -1;

		if (StrEqual(prop, "m_iNumControlPoints", false))
			offs = g_iObjResOffNumCPs;
		else if (StrEqual(prop, "m_nActivePushPointIndex", false))
			offs = g_iObjResOffActiveCP;
		else
			offs = FindSendPropInfo(g_sObjResNetClass, prop);

		if (offs != -1)
			return GetEntData(g_iObjResEntity, offs + (size * element));
	}
	return -1;
}

bool IsCounterAttack() {
	return view_as<bool>(GameRules_GetProp("m_bCounterAttack"));
}

// ------------------------------------------------------------
// Admin commands
// ------------------------------------------------------------

static bool BM_GetReviewView(int client, float eye[3], float angles[3], int &mode, int &target) {
	target = client;
	mode = IsPlayerAlive(client) ? 0 : GetEntProp(client, Prop_Send, "m_iObserverMode");
	if (HasEntProp(client, Prop_Send, "m_hViewEntity")) {
		int camera = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
		if (camera > 0 && camera != client && IsValidEntity(camera)) {
			ReplyToCommand(client, "[BM] Exit the special camera before marking an area.");
			return false;
		}
	}
	if (mode == 4) {
		target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
		if (target < 1 || target > MaxClients || !IsClientInGame(target) || !IsPlayerAlive(target)) {
			ReplyToCommand(client, "[BM] No valid first-person spectator target. Switch to free camera to mark.");
			return false;
		}
	}
	else if (mode != 0 && mode != 6) {
		// Chase/death camera offsets are calculated client-side.
		ReplyToCommand(client, "[BM] Switch to free camera or first-person spectating, aim at the area, then run sm_botspawn_mark again.");
		return false;
	}
	if (!IsPlayerAlive(client) && mode == 0) {
		ReplyToCommand(client, "[BM] Wait for spectator mode before marking an area.");
		return false;
	}
	GetClientEyePosition(target, eye);
	GetClientEyeAngles(target, angles);
	return true;
}

public bool BM_ReviewAimFilter(int entity, int contentsMask, any ignored) {
	int client = ignored & 0xFFFF;
	int target = ignored >> 16;
	return entity != client && entity != target;
}

public Action Cmd_MarkSpawnArea(int client, int args) {
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client)) {
		ReplyToCommand(client, "[BM] Use this command in-game while looking at the area.");
		return Plugin_Handled;
	}
	BMReview mark;
	int target;
	if (!BM_GetReviewView(client, mark.eye, mark.angles, mark.observerMode, target))
		return Plugin_Handled;
	char note[512];
	GetCmdArgString(note, sizeof note);
	StripQuotes(note);
	TrimString(note);
	if (strlen(note) >= sizeof mark.note) {
		ReplyToCommand(client, "[BM] Note is too long (maximum %d bytes).", sizeof mark.note - 1);
		return Plugin_Handled;
	}
	ReplaceString(note, sizeof note, "\n", " ");
	ReplaceString(note, sizeof note, "\r", " ");
	ReplaceString(note, sizeof note, "\t", " ");
	strcopy(mark.note, sizeof mark.note, note);
	Handle trace = TR_TraceRayFilterEx(mark.eye, mark.angles, MASK_SOLID, RayType_Infinite, BM_ReviewAimFilter, client | (target << 16));
	if (!TR_DidHit(trace) || TR_StartSolid(trace) || (TR_GetSurfaceFlags(trace) & (SURF_SKY | SURF_SKY2D))) {
		delete trace;
		ReplyToCommand(client, "[BM] Aim at a solid location in the map, not the sky.");
		return Plugin_Handled;
	}
	TR_GetEndPosition(mark.point, trace);
	TR_GetPlaneNormal(trace, mark.normal);
	delete trace;
	mark.counterattack = IsCounterAttack();
	mark.objective = g_iNumCPs > 0 ? ClampCP(g_iActiveCP - (mark.counterattack ? 1 : 0)) : -1;
	mark.created = GetTime();
	GetClientName(client, mark.admin, sizeof mark.admin);
	if (!GetClientAuthId(client, AuthId_Steam2, mark.steamid, sizeof mark.steamid))
		strcopy(mark.steamid, sizeof mark.steamid, "unknown");
	char error[192];
	if (!BMReview_Add(mark, error, sizeof error)) {
		ReplyToCommand(client, "[BM] Marker not saved: %s", error);
		return Plugin_Handled;
	}
	float top[3];
	top = mark.point;
	top[2] += 64.0;
	TE_SetupBeamPoints(mark.point, top, g_iReviewBeam, 0, 0, 0, 3.0, 4.0, 4.0, 0, 0.0, {255, 220, 60, 255}, 0);
	TE_SendToClient(client);
	ReplyToCommand(client, "[BM] Review marker #%d saved at %.0f, %.0f, %.0f. Note: %s", mark.id, mark.point[0], mark.point[1], mark.point[2], mark.note[0] ? mark.note : "(none)");
	return Plugin_Handled;
}

public Action Cmd_ReloadSpawns(int client, int args) {
	char map[64];
	GetCurrentMap(map, sizeof map);
	if (!LoadSpawnsForMap(map)) {
		ReplyToCommand(client, "[BM] Reload failed: %s. Existing spawn lists retained.", g_sSpawnLoadError);
		return Plugin_Handled;
	}
	int cpCount = 0, caCount = 0;
	for (int cp = 0; cp < MAX_CPS; cp++) {
		if (g_CPSpawns[cp] != null)
			cpCount += g_CPSpawns[cp].Length;
		if (g_CASpawns[cp] != null)
			caCount += g_CASpawns[cp].Length;
	}
	ReplyToCommand(client, "[BM] Reloaded %s: CP %d, CA %d. Reinforcements and timers preserved.", map, cpCount, caCount);
	return Plugin_Handled;
}

public Action Cmd_SpawnStats(int client, int args) {
	if (args > 0) {
		char arg[16];
		GetCmdArg(1, arg, sizeof arg);
		if (!StrEqual(arg, "reset", false)) {
			ReplyToCommand(client, "[BM] Usage: sm_botspawn_stats [reset]");
			return Plugin_Handled;
		}
		BM_ResetSpawnStats();
		BM_InvalidateSpawnCache();
	}
	ReplyToCommand(client, "[BM] Cache %s | Position collections: %d | Candidates checked: %d | Cached results: %d | Distance calculations: %d",
		g_bSpawnCache ? "ON" : "OFF", g_iPositionCollections, g_iSafetyChecks, g_iSafetyCacheHits, g_iDistanceChecks);
	return Plugin_Handled;
}

public Action Cmd_SpawnFailures(int client, int args) {
	StringMapSnapshot entries = g_SpawnFailures.Snapshot();
	char key[160];
	ReplyToCommand(client, "[BM] %d suspect spawn locations this map. Details in console; these are movement-check failures, not confirmed bad spawns.", entries.Length);
	for (int i = 0; i < entries.Length; i++) {
		entries.GetKey(i, key, sizeof key);
		int count;
		g_SpawnFailures.GetValue(key, count);
		PrintToConsole(client, "[BM] %s | failures: %d", key, count);
	}
	delete entries;
	return Plugin_Handled;
}

public Action cmd_respawn(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_respawn <#userid|name|@all|@bots|@humans|@me>");
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS + 1];
	int target_count;
	bool tn_is_ml;

	target_count = ProcessTargetString(
		arg,
		client,
		target_list,
		sizeof(target_list),
		COMMAND_FILTER_DEAD,
		target_name,
		sizeof(target_name),
		tn_is_ml
	);

	if (target_count <= COMMAND_TARGET_NONE) {
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	int new_target_count = 0;

	for (int i = 0; i < target_count; i++) {
		int target = target_list[i];

		if (!IsClientInGame(target))
			continue;

		int team = GetClientTeam(target);
		if (team == TEAM_SECURITY || team == TEAM_INSURGENT) {
			if (!ga_bPickSquad[target])
				continue;

			SDKCall(g_hForceRespawn, target);
			target_list[new_target_count] = target;
			new_target_count++;
		}
	}

	if (new_target_count == 0) {
		ReplyToCommand(client, "[SM] No valid players to respawn.");
		return Plugin_Handled;
	}

	ShowActivity2(client, "[SM] ", "Respawned: %s", target_name);
	return Plugin_Handled;
}

public Action cmd_bots(int client, int args) {
	if (!g_bIsRoundActive) {
		ReplyToCommand(client, "Use it after round start");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "Enemies alive: %d | Enemy reinforcements left: %d | sm_botlives: %d", CountAliveInsurgents(), g_iBotLivesRemain, g_iBotLives);

	return Plugin_Handled;
}

int CountAliveInsurgents() {
	int count = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == TEAM_INSURGENT)
			count++;
	}
	return count;
}

// ------------------------------------------------------------
// Radio hint about total enemies
// ------------------------------------------------------------

public Action Timer_Enemies_Remaining(Handle timer) {
	if (g_bIsGameEnd || g_bIsMapChanging || !g_bIsRoundActive)
		return Plugin_Continue;

	int aliveInsurgents = CountAliveInsurgents();
	g_iTotalAliveEnemies = aliveInsurgents + g_iBotLivesRemain;
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
			continue;

		if (GetEntData(client, g_iPlayerEquipGear + (4 * 5)) == g_iRadioGearID)
			PrintHintText(client, "Total enemies alive: %d", g_iTotalAliveEnemies);
	}
	return Plugin_Continue;
}

// ------------------------------------------------------------
// Misc
// ------------------------------------------------------------

void ResetTankBomberRespawnCount() {
	g_iBomberRespawCount = 0;
	g_iTankRespawnCount = 0;
}

public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	g_bIsGameEnd = true;
	g_bIsRoundActive = false;
	BM_AdvanceStage();
}

// ------------------------------------------------------------
// Cvars
// ------------------------------------------------------------

void SetupCvars() {
	g_cvSpawnCache = CreateConVar("sm_botspawn_cache", "1", "Reuse proximity checks within a server tick (0 = disable for comparison).", _, true, 0.0, true, 1.0);
	g_bSpawnCache = g_cvSpawnCache.BoolValue;
	g_cvSpawnCache.AddChangeHook(OnConVarChanged);

	cv_hBotLives = CreateConVar("sm_botlives", "5.0", "Bot lives per human security player.", _, true, 0.0, true, 1000.0);
	g_iBotLives = cv_hBotLives.IntValue;
	cv_hBotLives.AddChangeHook(OnConVarChanged);

	cv_hMaxCounterAttackDuration = CreateConVar("sm_botcamax", "180.0", "Maximum randomised non-final counter-attack duration in seconds.", _, true, 0.0, true, 360.0);
	g_iMaxCounterAttackDuration = cv_hMaxCounterAttackDuration.IntValue;
	cv_hMaxCounterAttackDuration.AddChangeHook(OnConVarChanged);

	cv_hMinCounterAttackDuration = CreateConVar("sm_botcamin", "120.0", "Minimum randomised non-final counter-attack duration in seconds.", _, true, 0.0, true, 360.0);
	g_iMinCounterAttackDuration = cv_hMinCounterAttackDuration.IntValue;
	cv_hMinCounterAttackDuration.AddChangeHook(OnConVarChanged);

	cv_hMaxFinalCounterAttackDuration = CreateConVar("sm_botfinalcamax", "360.0", "Maximum randomised final counter-attack duration in seconds.", _, true, 0.0, true, 360.0);
	g_iMaxFinalCounterAttackDuration = cv_hMaxFinalCounterAttackDuration.IntValue;
	cv_hMaxFinalCounterAttackDuration.AddChangeHook(OnConVarChanged);

	cv_hMinFinalCounterAttackDuration = CreateConVar("sm_botfinalcamin", "240.0", "Minimum randomised final counter-attack duration in seconds.", _, true, 0.0, true, 360.0);
	g_iMinFinalCounterAttackDuration = cv_hMinFinalCounterAttackDuration.IntValue;
	cv_hMinFinalCounterAttackDuration.AddChangeHook(OnConVarChanged);
	
	cv_hCounterAttackChance = CreateConVar("sm_botcachance", "0.5", "Chance that the counter-attack will happen.", _, true, 0.0, true, 1.0);
	g_fCounterAttackChance = cv_hCounterAttackChance.FloatValue;
	cv_hCounterAttackChance.AddChangeHook(OnConVarChanged);

	cv_hMinSpawnDistHuman = CreateConVar("sm_botspawnmindist", "1150.0", "Minimum distance (in units) from human players for bot custom spawns.", _, true, 0.0, true, 5000.0);
	g_fMinSpawnDistHuman = cv_hMinSpawnDistHuman.FloatValue;
	cv_hMinSpawnDistHuman.AddChangeHook(OnConVarChanged);

	cv_hProximityGraceSeconds = CreateConVar("sm_botproxgrace", "20.0", "Seconds after objective where bot spawns ignore proximity checks.", _, true, 0.0, true, 60.0);
	g_fProximityGraceSeconds = cv_hProximityGraceSeconds.FloatValue;
	cv_hProximityGraceSeconds.AddChangeHook(OnConVarChanged);

	cv_hBomberRespawns = CreateConVar("sm_botbomber_respawns", "1", "Max bomber bot respawns per control point and per counter-attack (0 = none).", _, true, 0.0, true, 10.0);
	g_iBomberRespawnsMax = cv_hBomberRespawns.IntValue;
	cv_hBomberRespawns.AddChangeHook(OnConVarChanged);

	cv_hTankRespawns = CreateConVar("sm_bottank_respawns", "1", "Max tank bot respawns per control point and per counter-attack (0 = none).", _, true, 0.0, true, 10.0);
	g_iTankRespawnsMax = cv_hTankRespawns.IntValue;
	cv_hTankRespawns.AddChangeHook(OnConVarChanged);

	g_cvCAWarnRadius = CreateConVar("sm_botcawarn_radius", "350.0", "Radius around counter-attack bot spawns to warn Security players in center text (0 = disabled).", _, true, 0.0, true, 5000.0);
	g_fCAWarnRadius = g_cvCAWarnRadius.FloatValue;
	g_cvCAWarnRadius.AddChangeHook(OnConVarChanged);

	cv_hCounterAttackDuration = FindConVar("mp_checkpoint_counterattack_duration");
	cv_hCounterAttackDisable = FindConVar("mp_checkpoint_counterattack_disable");
	cv_hCounterAttackAlways = FindConVar("mp_checkpoint_counterattack_always");
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvSpawnCache) {
		g_bSpawnCache = g_cvSpawnCache.BoolValue;
		BM_InvalidateSpawnCache();
		BM_ResetSpawnStats();
		return;
	}
	if (convar == cv_hBotLives)
		g_iBotLives = cv_hBotLives.IntValue;
	else if (convar == cv_hMaxCounterAttackDuration)
		g_iMaxCounterAttackDuration = cv_hMaxCounterAttackDuration.IntValue;
	else if (convar == cv_hMinCounterAttackDuration)
		g_iMinCounterAttackDuration = cv_hMinCounterAttackDuration.IntValue;
	else if (convar == cv_hMaxFinalCounterAttackDuration)
		g_iMaxFinalCounterAttackDuration = cv_hMaxFinalCounterAttackDuration.IntValue;
	else if (convar == cv_hMinFinalCounterAttackDuration)
		g_iMinFinalCounterAttackDuration = cv_hMinFinalCounterAttackDuration.IntValue;
	else if (convar == cv_hCounterAttackChance)
		g_fCounterAttackChance = cv_hCounterAttackChance.FloatValue;
	else if (convar == cv_hMinSpawnDistHuman) {
		g_fMinSpawnDistHuman = cv_hMinSpawnDistHuman.FloatValue;
		BM_InvalidateSpawnCache();
	}
	else if (convar == cv_hProximityGraceSeconds)
		g_fProximityGraceSeconds = cv_hProximityGraceSeconds.FloatValue;
	else if (convar == cv_hBomberRespawns)
		g_iBomberRespawnsMax = cv_hBomberRespawns.IntValue;
	else if (convar == cv_hTankRespawns)
		g_iTankRespawnsMax = cv_hTankRespawns.IntValue;
	else if (convar == g_cvCADelay)
		g_iCADelay = g_cvCADelay.IntValue;
	else if (convar == g_cvCADelayFinale)
		g_iCADelayFinale = g_cvCADelayFinale.IntValue;
	else if (convar == g_cvCAWarnRadius)
		g_fCAWarnRadius = g_cvCAWarnRadius.FloatValue;
}
