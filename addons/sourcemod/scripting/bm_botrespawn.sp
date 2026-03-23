#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PL_VERSION		"1.1.5"

#define TEAM_SPECTATOR	1
#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

#define MAX_CPS			32

enum BotSpawnRole {
	BotSpawnRole_Normal = 0,
	BotSpawnRole_Bomber,
	BotSpawnRole_Tank
};

// ------------------------------------------------------------
// Config / state
// ------------------------------------------------------------

float g_fMinSpawnDistHuman = 1150.0;		// how far from humans a CP spawn must be
float g_fProximityGraceSeconds = 15.0;		// disable proximity check for this long

float g_fProxGraceUntil = 0.0;

ArrayList g_CPSpawns[MAX_CPS];
ArrayList g_CASpawns[MAX_CPS];
ArrayList g_CPSpawnLastUsed[MAX_CPS];
ArrayList g_CASpawnLastUsed[MAX_CPS];
ArrayList g_CPSpawnPenaltyUntil[MAX_CPS];
ArrayList g_CASpawnPenaltyUntil[MAX_CPS];
int g_iNumCPs = 0;
int g_iActiveCP = 0;

Handle g_hForceRespawn = null;
Handle g_hGameConfig = null;

ConVar cv_hBotLives = null;
ConVar cv_hMaxCounterAttackDuration = null;
ConVar cv_hMinCounterAttackDuration = null;
ConVar cv_hCounterAttackDuration = null;
ConVar cv_hCounterAttackDisable = null;
ConVar cv_hCounterAttackAlways = null;
ConVar cv_hCounterAttackChance = null;
ConVar cv_hMinSpawnDistHuman = null;
ConVar cv_hProximityGraceSeconds = null;
ConVar cv_hBomberRespawns = null;
ConVar cv_hTankRespawns = null;
ConVar cv_hRoleMinDistScaleNormal = null;
ConVar cv_hRoleMinDistScaleBomber = null;
ConVar cv_hRoleMinDistScaleTank = null;
ConVar cv_hHeatCooldownNormal = null;
ConVar cv_hHeatCooldownNormalCA = null;
ConVar cv_hHeatCooldownBomber = null;
ConVar cv_hHeatCooldownBomberCA = null;
ConVar cv_hHeatCooldownTank = null;
ConVar cv_hHeatCooldownTankCA = null;
ConVar cv_hThreatNearDist = null;
ConVar cv_hThreatVisDist = null;
ConVar cv_hScoreNormalDist = null;
ConVar cv_hScoreNormalNear = null;
ConVar cv_hScoreNormalVisible = null;
ConVar cv_hScoreBomberDist = null;
ConVar cv_hScoreBomberNear = null;
ConVar cv_hScoreBomberVisible = null;
ConVar cv_hScoreTankTargetDist = null;
ConVar cv_hScoreTankTargetDistCA = null;
ConVar cv_hScoreTankTargetBase = null;
ConVar cv_hScoreTankTargetWeight = null;
ConVar cv_hScoreTankNear = null;
ConVar cv_hScoreTankVisible = null;
ConVar cv_hHeatPenaltyBase = null;
ConVar cv_hHeatPenaltyWeight = null;
ConVar cv_hHeatRandomJitter = null;
ConVar cv_hAntiLoopWindow = null;
ConVar cv_hAntiLoopDist = null;
ConVar cv_hAntiLoopPenalty = null;
ConVar cv_hAntiLoopPenaltyBomberBonus = null;
ConVar cv_hAntiLoopPenaltyTankBonus = null;
ConVar cv_hAntiLoopPenaltyMax = null;

ConVar g_cvCADelay = null;
ConVar g_cvCADelayFinale = null;
ConVar g_cvCAWarnRadius = null;

int g_iMaxCounterAttackDuration = 0;
int g_iMinCounterAttackDuration = 0;
float g_fCounterAttackChance = 0.0;
float g_fRoleMinDistScaleNormal = 1.0;
float g_fRoleMinDistScaleBomber = 1.35;
float g_fRoleMinDistScaleTank = 0.75;
float g_fHeatCooldownNormal = 18.0;
float g_fHeatCooldownNormalCA = 12.0;
float g_fHeatCooldownBomber = 30.0;
float g_fHeatCooldownBomberCA = 20.0;
float g_fHeatCooldownTank = 12.0;
float g_fHeatCooldownTankCA = 8.0;
float g_fThreatNearDist = 1600.0;
float g_fThreatVisDist = 2950.0;
float g_fScoreNormalDist = 0.40;
float g_fScoreNormalNear = 180.0;
float g_fScoreNormalVisible = 250.0;
float g_fScoreBomberDist = 0.70;
float g_fScoreBomberNear = 260.0;
float g_fScoreBomberVisible = 425.0;
float g_fScoreTankTargetDist = 950.0;
float g_fScoreTankTargetDistCA = 800.0;
float g_fScoreTankTargetBase = 350.0;
float g_fScoreTankTargetWeight = 0.25;
float g_fScoreTankNear = 110.0;
float g_fScoreTankVisible = 120.0;
float g_fHeatPenaltyBase = 500.0;
float g_fHeatPenaltyWeight = 20.0;
float g_fHeatRandomJitter = 10.0;
float g_fAntiLoopWindow = 20.0;
float g_fAntiLoopDist = 800.0;
float g_fAntiLoopPenalty = 45.0;
float g_fAntiLoopPenaltyBomberBonus = 15.0;
float g_fAntiLoopPenaltyTankBonus = 10.0;
float g_fAntiLoopPenaltyMax = 120.0;

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
int ga_iBotLastSpawnCP[MAXPLAYERS + 1];
int ga_iBotLastSpawnIndex[MAXPLAYERS + 1];
bool ga_bBotLastSpawnCA[MAXPLAYERS + 1];

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
	author		= "Nullifidian + GPT/Codex",
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

	LoadSpawnsForMap(map);

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
	g_iObjResEntity = -1;
	g_sObjResNetClass[0] = '\0';

	// CA countdown cleanup
	if (g_hCACountdownTimer != null) {
		KillTimer(g_hCACountdownTimer);
		g_hCACountdownTimer = null;
	}
	if (g_hCAProbeTimer != null) {
		KillTimer(g_hCAProbeTimer);
		g_hCAProbeTimer = null;
	}
	g_iCACountdownLeft = 0;
	g_bCAFinaleCountdown = false;

	BM_FreeAllSpawns();
}

public void OnPluginEnd() {
	// Timers (defensive)
	if (g_hCACountdownTimer != null) {
		KillTimer(g_hCACountdownTimer);
		g_hCACountdownTimer = null;
	}
	if (g_hCAProbeTimer != null) {
		KillTimer(g_hCAProbeTimer);
		g_hCAProbeTimer = null;
	}

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
	ga_bPickSquad[client] = false;
	ga_bIsTank[client] = false;
	ga_bIsBomber[client] = false;
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
	ga_iBotLastSpawnCP[client] = -1;
	ga_iBotLastSpawnIndex[client] = -1;
	ga_bBotLastSpawnCA[client] = false;
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
	g_iActiveCP = 0;
	g_bIsRoundActive = true;
	BM_StartProxGrace(g_fProximityGraceSeconds);
	SetBotLives();
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	g_bIsRoundActive = false;
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bIsRoundActive)
		return Plugin_Continue;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_INSURGENT)
		return Plugin_Continue;

	TeleportBot(client);
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	if (g_iBotLivesRemain < 1)
		return Plugin_Continue;
		
	int userid = event.GetInt("userid");
	int victim = GetClientOfUserId(userid);
	if (victim < 1 || !IsClientInGame(victim) || !IsFakeClient(victim) || GetClientTeam(victim) != TEAM_INSURGENT)
		return Plugin_Continue;

	BM_ApplyAntiLoopPenalty(victim);
	
	if (ga_bIsBomber[victim]) {
		if (g_iBomberRespawCount >= g_iBomberRespawnsMax)
			return Plugin_Continue;
		else
			g_iBomberRespawCount++;
	}
	else if (ga_bIsTank[victim]) {
		if (g_iTankRespawnCount >= g_iTankRespawnsMax)
			return Plugin_Continue;
		else
			g_iTankRespawnCount++;
	}

	g_iBotLivesRemain--;
	CreateTimer(0.05, Timer_RespawnBot, userid, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Timer_RespawnBot(Handle timer, any userid) {
	int bot = GetClientOfUserId(userid);
	if (!g_bIsRoundActive || bot < 1 || bot > MaxClients || !IsClientInGame(bot) || !IsFakeClient(bot) || IsPlayerAlive(bot) || GetClientTeam(bot) != TEAM_INSURGENT)
		return Plugin_Stop;

	SDKCall(g_hForceRespawn, bot);
	return Plugin_Stop;
}

public Action Event_ObjDone_NoCopy(Event event, const char[] name, bool dontBroadcast) {
	if (g_iActiveCP < g_iNumCPs)
		g_iActiveCP++;

	RequestFrame(Frame_SetBotLives);
	return Plugin_Continue;
}

public Action Event_Objectives_Pre(Event event, const char[] name, bool dontBroadcast) {
	g_iBotLivesRemain = 0;
	
	if (g_fProximityGraceSeconds > 0.0)
		BM_StartProxGrace(g_fProximityGraceSeconds + 1.1);

	if (g_iActiveCP + 1 == g_iNumCPs || GetRandomFloat(0.0, 1.0) < g_fCounterAttackChance) {
		BM_CleanUpBotsForCounterAttack();
		SetConVarInt(cv_hCounterAttackDuration, GetRandomInt(g_iMinCounterAttackDuration, g_iMaxCounterAttackDuration), true, false);
		SetConVarInt(cv_hCounterAttackDisable, 0, true, false);
		SetConVarInt(cv_hCounterAttackAlways, 1, true, false);
	}
	else
		SetConVarInt(cv_hCounterAttackDisable, 1, true, false);

	return Plugin_Continue;
}

void Frame_SetBotLives() {
	SetBotLives();
	if (IsCounterAttack())
		CreateTimer(1.0, TimerR_MonitorCA, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action TimerR_MonitorCA(Handle timer) {
	if (g_bIsGameEnd || g_bIsMapChanging || !g_bIsRoundActive)
		return Plugin_Stop;

	if (!IsCounterAttack()) {
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
	if (event.GetInt("team") == TEAM_SECURITY && g_hCAProbeTimer == null)
		g_hCAProbeTimer = CreateTimer(1.0, CA_Timer_IsCounterAttack, _, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action CA_Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast) {
	if (event.GetInt("attackerteam") == TEAM_SECURITY && g_hCAProbeTimer == null)
		g_hCAProbeTimer = CreateTimer(1.0, CA_Timer_IsCounterAttack, _, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action CA_Timer_IsCounterAttack(Handle timer) {
	g_hCAProbeTimer = null;

	if (IsCounterAttack() && g_hCACountdownTimer == null)
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

	// Run countdown + proximity update every 2 seconds
	g_hCACountdownTimer = CreateTimer(2.0, CA_Timer_CountdownTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action CA_Timer_CountdownTick(Handle timer) {
	// We step in 2-second chunks to match the timer interval
	g_iCACountdownLeft -= 2;

	if (g_iCACountdownLeft <= 0) {
		CA_PlayCountdownSound();
		CA_ResetCountdownTimer();
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
	// Always show the base countdown to everyone in-game (alive, dead, any team).
	PrintCenterTextAll("Insurgents counter-attacking in %d", g_iCACountdownLeft);

	// If CA warning is disabled or we're not in CA, just keep the generic message.
	if (!IsCounterAttack() || g_fCAWarnRadius <= 0.0)
		return;

	int cpIndex = BM_GetCurrentCACpIndex();
	if (cpIndex < 0 || g_CASpawns[cpIndex] == null || g_CASpawns[cpIndex].Length <= 0)
		// No valid CA spawns → generic message already printed above.
		return;

	float radiusSq = g_fCAWarnRadius * g_fCAWarnRadius;
	int numSpawns = g_CASpawns[cpIndex].Length;

	float playerPos[3];
	float spawnPos[3];

	for (int i = 1; i <= MaxClients; i++) {
		// Only override HUD for alive Security players.
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SECURITY)
			continue;

		GetClientAbsOrigin(i, playerPos);

		bool bNear = false;

		for (int s = 0; s < numSpawns; s++) {
			g_CASpawns[cpIndex].GetArray(s, spawnPos, 3);

			float distSq = GetVectorDistance(playerPos, spawnPos, true);
			if (distSq <= radiusSq) {
				bNear = true;
				break;
			}
		}

		if (bNear)
			// Override the generic center text for this player only.
			PrintCenterText(i, "Insurgents counter-attacking in %d\nWarning! You are very close to enemy counter-attack spawns!", g_iCACountdownLeft);
	}
}

static void BM_StartProxGrace(float seconds) {
	g_fProxGraceUntil = GetGameTime() + seconds;
}

static bool BM_InProxGrace() {
	return GetGameTime() < g_fProxGraceUntil;
}

static ArrayList BM_EnsureSpawnMetaList(int cp, bool inCA, bool penalty) {
	if (cp < 0 || cp >= MAX_CPS)
		return null;

	ArrayList list = null;
	if (inCA)
		list = penalty ? g_CASpawnPenaltyUntil[cp] : g_CASpawnLastUsed[cp];
	else
		list = penalty ? g_CPSpawnPenaltyUntil[cp] : g_CPSpawnLastUsed[cp];

	if (list != null)
		return list;

	list = new ArrayList();
	if (inCA) {
		if (penalty)
			g_CASpawnPenaltyUntil[cp] = list;
		else
			g_CASpawnLastUsed[cp] = list;
	}
	else {
		if (penalty)
			g_CPSpawnPenaltyUntil[cp] = list;
		else
			g_CPSpawnLastUsed[cp] = list;
	}

	return list;
}

static float BM_GetMetaFloat(ArrayList list, int index) {
	if (list == null || index < 0 || index >= list.Length)
		return 0.0;

	return view_as<float>(list.Get(index));
}

static void BM_SetMetaFloat(ArrayList list, int index, float value) {
	if (list == null || index < 0 || index >= list.Length)
		return;

	list.Set(index, view_as<int>(value));
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

static int BM_CollectSecurityData(float origins[32][3], float eyes[32][3]) {
	int count = 0;

	for (int i = 1; i <= MaxClients && count < 32; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SECURITY)
			continue;

		GetClientAbsOrigin(i, origins[count]);
		GetClientEyePosition(i, eyes[count]);
		count++;
	}

	return count;
}

static BotSpawnRole BM_GetBotSpawnRole(int client) {
	if (ga_bIsBomber[client])
		return BotSpawnRole_Bomber;
	if (ga_bIsTank[client])
		return BotSpawnRole_Tank;
	return BotSpawnRole_Normal;
}

static float BM_GetRoleMinDistSq(BotSpawnRole role) {
	float scale = g_fRoleMinDistScaleNormal;

	switch (role) {
		case BotSpawnRole_Bomber: scale = g_fRoleMinDistScaleBomber;
		case BotSpawnRole_Tank:   scale = g_fRoleMinDistScaleTank;
	}

	float dist = g_fMinSpawnDistHuman * scale;
	return dist * dist;
}

static float BM_GetRoleHeatCooldown(BotSpawnRole role, bool inCA) {
	switch (role) {
		case BotSpawnRole_Bomber: return inCA ? g_fHeatCooldownBomberCA : g_fHeatCooldownBomber;
		case BotSpawnRole_Tank:   return inCA ? g_fHeatCooldownTankCA : g_fHeatCooldownTank;
	}
	return inCA ? g_fHeatCooldownNormalCA : g_fHeatCooldownNormal;
}

static float BM_ScoreSpawnCandidate(const float candidate[3], ArrayList lastUsedList, ArrayList penaltyList, int index, float humanOrigins[32][3], float humanEyes[32][3], int hcount, BotSpawnRole role, bool inCA, bool enforceMinDist) {
	float threatNearDistSq = g_fThreatNearDist * g_fThreatNearDist;
	float maxVisDistSq = g_fThreatVisDist * g_fThreatVisDist;

	float now = GetGameTime();
	float penaltyUntil = BM_GetMetaFloat(penaltyList, index);
	if (penaltyUntil > now)
		return -1000000.0;

	float nearestHumanSq = 999999999.0;
	int nearHumans = 0;

	for (int i = 0; i < hcount; i++) {
		float distSq = GetVectorDistance(candidate, humanOrigins[i], true);
		if (distSq < nearestHumanSq)
			nearestHumanSq = distSq;
		if (distSq <= threatNearDistSq)
			nearHumans++;
	}

	float roleMinDistSq = BM_GetRoleMinDistSq(role);
	if (hcount > 0 && enforceMinDist && nearestHumanSq < roleMinDistSq)
		return -1000000.0;

	int visibleHumans = 0;
	for (int i = 0; i < hcount; i++) {
		if (GetVectorDistance(candidate, humanEyes[i], true) > maxVisDistSq)
			continue;

		Handle trace = TR_TraceRayFilterEx(humanEyes[i], candidate, MASK_SOLID, RayType_EndPoint, TraceEntityFilterSolid);
		bool visible = !TR_DidHit(trace);
		delete trace;

		if (visible) {
			visibleHumans++;
			if (visibleHumans >= 3)
				break;
		}
	}

	float nearestDist = (nearestHumanSq < 999999998.0) ? SquareRoot(nearestHumanSq) : 2500.0;
	float score = 0.0;

	switch (role) {
		case BotSpawnRole_Bomber: {
			score += nearestDist * g_fScoreBomberDist;
			score -= float(nearHumans) * g_fScoreBomberNear;
			score -= float(visibleHumans) * g_fScoreBomberVisible;
		}
		case BotSpawnRole_Tank: {
			float targetDist = inCA ? g_fScoreTankTargetDistCA : g_fScoreTankTargetDist;
			score += g_fScoreTankTargetBase - FloatAbs(nearestDist - targetDist) * g_fScoreTankTargetWeight;
			score -= float(nearHumans) * g_fScoreTankNear;
			score -= float(visibleHumans) * g_fScoreTankVisible;
		}
		default: {
			score += nearestDist * g_fScoreNormalDist;
			score -= float(nearHumans) * g_fScoreNormalNear;
			score -= float(visibleHumans) * g_fScoreNormalVisible;
		}
	}

	float lastUsed = BM_GetMetaFloat(lastUsedList, index);
	float cooldown = BM_GetRoleHeatCooldown(role, inCA);
	if (lastUsed > 0.0) {
		float sinceUsed = now - lastUsed;
		if (sinceUsed < cooldown)
			score -= g_fHeatPenaltyBase + ((cooldown - sinceUsed) * g_fHeatPenaltyWeight);
	}

	score += GetRandomFloat(0.0, g_fHeatRandomJitter);
	return score;
}

static bool BM_SelectBestSpawnForCP(int client, int cpIndex, bool inCA, float humanOrigins[32][3], float humanEyes[32][3], int hcount, bool enforceMinDist, float outVec[3], int &outIndex) {
	if (cpIndex < 0 || cpIndex >= MAX_CPS)
		return false;

	ArrayList spawns = inCA ? g_CASpawns[cpIndex] : g_CPSpawns[cpIndex];
	if (spawns == null || spawns.Length <= 0)
		return false;

	ArrayList lastUsed = BM_EnsureSpawnMetaList(cpIndex, inCA, false);
	ArrayList penalty  = BM_EnsureSpawnMetaList(cpIndex, inCA, true);
	if (lastUsed == null || penalty == null)
		return false;

	BotSpawnRole role = BM_GetBotSpawnRole(client);
	float bestScore = -1000001.0;
	bool found = false;
	float candidate[3];

	for (int i = 0; i < spawns.Length; i++) {
		spawns.GetArray(i, candidate, 3);
		float score = BM_ScoreSpawnCandidate(candidate, lastUsed, penalty, i, humanOrigins, humanEyes, hcount, role, inCA, enforceMinDist);
		if (!found || score > bestScore) {
			bestScore = score;
			outVec[0] = candidate[0];
			outVec[1] = candidate[1];
			outVec[2] = candidate[2];
			outIndex = i;
			found = true;
		}
	}

	return found && bestScore > -1000000.0;
}

static void BM_MarkSpawnUsed(int cpIndex, bool inCA, int spawnIndex) {
	ArrayList lastUsed = BM_EnsureSpawnMetaList(cpIndex, inCA, false);
	if (lastUsed == null)
		return;

	BM_SetMetaFloat(lastUsed, spawnIndex, GetGameTime());
}

static void BM_ApplyAntiLoopPenalty(int client) {
	if (!ga_bBotSpawnOriginValid[client] || ga_iBotLastSpawnCP[client] < 0 || ga_iBotLastSpawnIndex[client] < 0)
		return;

	float now = GetGameTime();
	if (now - ga_fBotSpawnTime[client] > g_fAntiLoopWindow)
		return;

	float origin[3];
	GetClientAbsOrigin(client, origin);
	float antiLoopDistSq = g_fAntiLoopDist * g_fAntiLoopDist;
	if (GetVectorDistance(origin, ga_fBotSpawnOrigin[client], true) > antiLoopDistSq)
		return;

	ArrayList penalty = BM_EnsureSpawnMetaList(ga_iBotLastSpawnCP[client], ga_bBotLastSpawnCA[client], true);
	ArrayList lastUsed = BM_EnsureSpawnMetaList(ga_iBotLastSpawnCP[client], ga_bBotLastSpawnCA[client], false);
	if (penalty == null || lastUsed == null)
		return;

	float extraPenalty = g_fAntiLoopPenalty;
	if (ga_bIsBomber[client])
		extraPenalty += g_fAntiLoopPenaltyBomberBonus;
	else if (ga_bIsTank[client])
		extraPenalty += g_fAntiLoopPenaltyTankBonus;

	float penaltyUntil = BM_GetMetaFloat(penalty, ga_iBotLastSpawnIndex[client]);
	if (penaltyUntil < now)
		penaltyUntil = now;

	penaltyUntil += extraPenalty;
	float maxPenalty = now + g_fAntiLoopPenaltyMax;
	if (penaltyUntil > maxPenalty)
		penaltyUntil = maxPenalty;

	BM_SetMetaFloat(penalty, ga_iBotLastSpawnIndex[client], penaltyUntil);
	BM_SetMetaFloat(lastUsed, ga_iBotLastSpawnIndex[client], now);
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
	int chosenCp = -1;
	int chosenIndex = -1;
	bool chosenInCA = false;

	float humanOrigins[32][3];
	float humanEyes[32][3];
	int hcount = BM_CollectSecurityData(humanOrigins, humanEyes);

	if (!IsCounterAttack()) {
		bool haveCurr = HasAnySpawnsCP(cp);
		bool haveNext = (cpN != cp) && HasAnySpawnsCP(cpN);

		if (!haveCurr && !haveNext)
			return;

		// During grace OR at last CP → original selection, no proximity checks
		if (BM_InProxGrace() || g_iActiveCP == g_iNumCPs - 1) {
			if (haveCurr && haveNext) {
				if (GetRandomFloat(0.0, 1.0) <= 0.8) {
					if (BM_SelectBestSpawnForCP(client, cp, false, humanOrigins, humanEyes, hcount, false, vec, chosenIndex))
						chosenCp = cp;
					else if (BM_SelectBestSpawnForCP(client, cpN, false, humanOrigins, humanEyes, hcount, false, vec, chosenIndex))
						chosenCp = cpN;
				}
				else {
					if (BM_SelectBestSpawnForCP(client, cpN, false, humanOrigins, humanEyes, hcount, false, vec, chosenIndex))
						chosenCp = cpN;
					else if (BM_SelectBestSpawnForCP(client, cp, false, humanOrigins, humanEyes, hcount, false, vec, chosenIndex))
						chosenCp = cp;
				}
			}
			else if (haveCurr) {
				if (BM_SelectBestSpawnForCP(client, cp, false, humanOrigins, humanEyes, hcount, false, vec, chosenIndex))
					chosenCp = cp;
			}
			else {
				if (BM_SelectBestSpawnForCP(client, cpN, false, humanOrigins, humanEyes, hcount, false, vec, chosenIndex))
					chosenCp = cpN;
			}
		}
		else {
			bool pickedAny = false;

			// 2) Try current CP first (if it has spawns)
			if (haveCurr) {
				if (BM_SelectBestSpawnForCP(client, cp, false, humanOrigins, humanEyes, hcount, true, vec, chosenIndex)) {
					pickedAny = true;
					chosenCp = cp;
				}
			}

			// 3) Then try next CP (with proximity) if not found yet
			if (!pickedAny && haveNext) {
				if (BM_SelectBestSpawnForCP(client, cpN, false, humanOrigins, humanEyes, hcount, true, vec, chosenIndex)) {
					pickedAny = true;
					chosenCp = cpN;
				}
			}

			// 4) If still nothing, scan forward through later CPs (cpN+1 .. g_iNumCPs-1)
			if (!pickedAny && g_iNumCPs > 0) {
				for (int c = g_iActiveCP + 2; c < g_iNumCPs; c++) {
					if (!HasAnySpawnsCP(c))
						continue;

					if (BM_SelectBestSpawnForCP(client, c, false, humanOrigins, humanEyes, hcount, true, vec, chosenIndex)) {
						pickedAny = true;
						chosenCp = c;
						break;
					}
				}
			}

			// 5) Finally, scan backwards through earlier CPs (cp-1 .. 0)
			if (!pickedAny && g_iNumCPs > 0) {
				for (int c = g_iActiveCP - 1; c >= 0; c--) {
					if (!HasAnySpawnsCP(c))
						continue;

					if (BM_SelectBestSpawnForCP(client, c, false, humanOrigins, humanEyes, hcount, true, vec, chosenIndex)) {
						pickedAny = true;
						chosenCp = c;
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
		// Counter-attack: use role/threat-aware scoring on CA spawns
		int cpC = ClampCP(g_iActiveCP - 1);
		if (g_CASpawns[cpC] == null || g_CASpawns[cpC].Length <= 0)
			return;

		if (!BM_SelectBestSpawnForCP(client, cpC, true, humanOrigins, humanEyes, hcount, false, vec, chosenIndex))
			return;

		chosenCp = cpC;
		chosenInCA = true;
	}

	if (vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0)
		return;

	TeleportEntity(client, vec, NULL_VECTOR, NULL_VECTOR);

	if (chosenCp >= 0 && chosenIndex >= 0)
		BM_MarkSpawnUsed(chosenCp, chosenInCA, chosenIndex);

	ga_fBotSpawnOrigin[client][0] = vec[0];
	ga_fBotSpawnOrigin[client][1] = vec[1];
	ga_fBotSpawnOrigin[client][2] = vec[2];
	ga_fBotSpawnTime[client] = GetGameTime();
	ga_iBotNoMoveChecks[client] = 0;
	ga_bBotSpawnOriginValid[client] = true;
	ga_iBotLastSpawnCP[client] = chosenCp;
	ga_iBotLastSpawnIndex[client] = chosenIndex;
	ga_bBotLastSpawnCA[client] = chosenInCA;
}

// ------------------------------------------------------------
// Global stuck check timer
// ------------------------------------------------------------

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
						// Treat as spawn-stuck: kill and refund a life so this bot
						// doesn't eat reinforcements.
						int livesBefore = g_iBotLivesRemain;
						if (g_bIsRoundActive && livesBefore > 0)
							// This cancels out the -- in Event_PlayerDeath.
							g_iBotLivesRemain++;

						ForcePlayerSuicide(client);

						ga_bBotSpawnOriginValid[client] = false;
						ga_iBotNoMoveChecks[client] = 0;

						// Bot will respawn if there were lives left; no need to run
						// nav-stuck logic for this client on this tick.
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
			// Treat as "nav-stuck anywhere": kill and refund a life iff there
			// were still reinforcements available.
			int livesBefore2 = g_iBotLivesRemain;
			if (g_bIsRoundActive && livesBefore2 > 0)
				g_iBotLivesRemain++;

			ForcePlayerSuicide(client);

			// Reset tracking; bot will respawn (if lives > 0) and get fresh data.
			ga_fBotLastMoveTime[client] = 0.0;
			ga_iBotIdleMoveChecks[client] = 0;

			ga_bBotSpawnOriginValid[client] = false;
			ga_iBotNoMoveChecks[client] = 0;
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
	for (int i = 0; i < MAX_CPS; i++) {
		if (g_CPSpawns[i] != null) {
			delete g_CPSpawns[i];
			g_CPSpawns[i] = null;
		}
		if (g_CPSpawnLastUsed[i] != null) {
			delete g_CPSpawnLastUsed[i];
			g_CPSpawnLastUsed[i] = null;
		}
		if (g_CPSpawnPenaltyUntil[i] != null) {
			delete g_CPSpawnPenaltyUntil[i];
			g_CPSpawnPenaltyUntil[i] = null;
		}
		if (g_CASpawns[i] != null) {
			delete g_CASpawns[i];
			g_CASpawns[i] = null;
		}
		if (g_CASpawnLastUsed[i] != null) {
			delete g_CASpawnLastUsed[i];
			g_CASpawnLastUsed[i] = null;
		}
		if (g_CASpawnPenaltyUntil[i] != null) {
			delete g_CASpawnPenaltyUntil[i];
			g_CASpawnPenaltyUntil[i] = null;
		}
	}
}

static ArrayList BM_EnsureSpawnList(int cp, bool inCA) {
	if (cp < 0 || cp >= MAX_CPS)
		return null;

	ArrayList list = (inCA ? g_CASpawns[cp] : g_CPSpawns[cp]);
	if (list != null)
		return list;

	list = new ArrayList(3);
	if (inCA)
		g_CASpawns[cp] = list;
	else
		g_CPSpawns[cp] = list;

	BM_EnsureSpawnMetaList(cp, inCA, false);
	BM_EnsureSpawnMetaList(cp, inCA, true);

	return list;
}

// ------------------------------------------------------------
// Spawn file load
// ------------------------------------------------------------

bool LoadSpawnsForMap(const char[] map) {
	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof path, "addons/sourcemod/data/bm_botspawns/%s.txt", map);

	File f = OpenFile(path, "r");
	if (f == null)
		return false;

	int maxCps = (g_iNumCPs > 0 ? g_iNumCPs : MAX_CPS);

	int cp = -1;
	bool inCA = false;
	char line[256];
	while (!f.EndOfFile() && f.ReadLine(line, sizeof line)) {
		TrimString(line);
		if (line[0] == '\0')
			continue;

		if (line[0] == '"' && line[1] == 'C' && line[2] == 'P') {
			int i = 3;
			int n = 0;
			while (line[i] >= '0' && line[i] <= '9') {
				n = n * 10 + (line[i] - '0');
				i++;
			}
			cp = (n >= 0 && n < maxCps) ? n : -1;
			inCA = false;
			continue;
		}
		if (StrContains(line, "\"CA\"") == 0) {
			inCA = true;
			continue;
		}
		if (line[0] == '{' || line[0] == '}') {
			if (line[0] == '}')
				inCA = false;
			continue;
		}

		if (cp >= 0 && line[0] == '"') {
			int len = strlen(line);
			if (len >= 2 && line[len - 1] == '"')
				line[len - 1] = '\0';
			char vec[256];
			strcopy(vec, sizeof vec, line[1]);
			TrimString(vec);
			float v[3];
			if (BM_ParseVec3(vec, v)) {
				ArrayList list = BM_EnsureSpawnList(cp, inCA);
				if (list != null) {
					list.PushArray(v, 3);
					ArrayList lastUsed = BM_EnsureSpawnMetaList(cp, inCA, false);
					ArrayList penalty = BM_EnsureSpawnMetaList(cp, inCA, true);
					if (lastUsed != null)
						lastUsed.Push(view_as<int>(0.0));
					if (penalty != null)
						penalty.Push(view_as<int>(0.0));
				}
			}
		}
	}
	delete f;
	return true;
}

bool BM_ParseVec3(const char[] s, float out[3]) {
	char parts[3][32];
	int n = ExplodeString(s, ",", parts, 3, 32);
	if (n != 3)
		return false;
	TrimString(parts[0]);
	TrimString(parts[1]);
	TrimString(parts[2]);
	out[0] = StringToFloat(parts[0]);
	out[1] = StringToFloat(parts[1]);
	out[2] = StringToFloat(parts[2]);
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
}

// ------------------------------------------------------------
// Cvars
// ------------------------------------------------------------

void SetupCvars() {
	cv_hBotLives = CreateConVar("sm_botlives", "5.0", "Bot lives per human security player.", _, true, 0.0, true, 1000.0);
	g_iBotLives = cv_hBotLives.IntValue;
	cv_hBotLives.AddChangeHook(OnConVarChanged);

	cv_hMaxCounterAttackDuration = CreateConVar("sm_botcamax", "150.0", "Maximum randomised counter-attack duration.", _, true, 0.0, true, 360.0);
	g_iMaxCounterAttackDuration = cv_hMaxCounterAttackDuration.IntValue;
	cv_hMaxCounterAttackDuration.AddChangeHook(OnConVarChanged);

	cv_hMinCounterAttackDuration = CreateConVar("sm_botcamin", "100.0", "Minimum randomised counter-attack duration.", _, true, 0.0, true, 360.0);
	g_iMinCounterAttackDuration = cv_hMinCounterAttackDuration.IntValue;
	cv_hMinCounterAttackDuration.AddChangeHook(OnConVarChanged);
	
	cv_hCounterAttackChance = CreateConVar("sm_botcachance", "0.5", "Chance that the counter-attack will happen.", _, true, 0.0, true, 1.0);
	g_fCounterAttackChance = cv_hCounterAttackChance.FloatValue;
	cv_hCounterAttackChance.AddChangeHook(OnConVarChanged);

	cv_hMinSpawnDistHuman = CreateConVar("sm_botspawnmindist", "1150.0", "Minimum distance (in units) from human players for bot custom spawns.", _, true, 0.0, true, 5000.0);
	g_fMinSpawnDistHuman = cv_hMinSpawnDistHuman.FloatValue;
	cv_hMinSpawnDistHuman.AddChangeHook(OnConVarChanged);

	cv_hProximityGraceSeconds = CreateConVar("sm_botproxgrace", "15.0", "Seconds after objective where bot spawns ignore proximity checks.", _, true, 0.0, true, 60.0);
	g_fProximityGraceSeconds = cv_hProximityGraceSeconds.FloatValue;
	cv_hProximityGraceSeconds.AddChangeHook(OnConVarChanged);

	cv_hBomberRespawns = CreateConVar("sm_botbomber_respawns", "1", "Max bomber bot respawns per control point and per counter-attack (0 = none).", _, true, 0.0, true, 10.0);
	g_iBomberRespawnsMax = cv_hBomberRespawns.IntValue;
	cv_hBomberRespawns.AddChangeHook(OnConVarChanged);

	cv_hTankRespawns = CreateConVar("sm_bottank_respawns", "1", "Max tank bot respawns per control point and per counter-attack (0 = none).", _, true, 0.0, true, 10.0);
	g_iTankRespawnsMax = cv_hTankRespawns.IntValue;
	cv_hTankRespawns.AddChangeHook(OnConVarChanged);

	cv_hRoleMinDistScaleNormal = CreateConVar("sm_botspawn_role_scale_normal", "1.0", "Spawn min-distance scale for normal bots.", _, true, 0.1, true, 5.0);
	g_fRoleMinDistScaleNormal = cv_hRoleMinDistScaleNormal.FloatValue;
	cv_hRoleMinDistScaleNormal.AddChangeHook(OnConVarChanged);

	cv_hRoleMinDistScaleBomber = CreateConVar("sm_botspawn_role_scale_bomber", "1.35", "Spawn min-distance scale for bomber bots.", _, true, 0.1, true, 5.0);
	g_fRoleMinDistScaleBomber = cv_hRoleMinDistScaleBomber.FloatValue;
	cv_hRoleMinDistScaleBomber.AddChangeHook(OnConVarChanged);

	cv_hRoleMinDistScaleTank = CreateConVar("sm_botspawn_role_scale_tank", "0.75", "Spawn min-distance scale for tank bots.", _, true, 0.1, true, 5.0);
	g_fRoleMinDistScaleTank = cv_hRoleMinDistScaleTank.FloatValue;
	cv_hRoleMinDistScaleTank.AddChangeHook(OnConVarChanged);

	cv_hHeatCooldownNormal = CreateConVar("sm_botspawn_heat_normal", "18.0", "Spawn heat cooldown for normal bots outside counter-attack.", _, true, 0.0, true, 120.0);
	g_fHeatCooldownNormal = cv_hHeatCooldownNormal.FloatValue;
	cv_hHeatCooldownNormal.AddChangeHook(OnConVarChanged);

	cv_hHeatCooldownNormalCA = CreateConVar("sm_botspawn_heat_normal_ca", "12.0", "Spawn heat cooldown for normal bots during counter-attack.", _, true, 0.0, true, 120.0);
	g_fHeatCooldownNormalCA = cv_hHeatCooldownNormalCA.FloatValue;
	cv_hHeatCooldownNormalCA.AddChangeHook(OnConVarChanged);

	cv_hHeatCooldownBomber = CreateConVar("sm_botspawn_heat_bomber", "30.0", "Spawn heat cooldown for bomber bots outside counter-attack.", _, true, 0.0, true, 120.0);
	g_fHeatCooldownBomber = cv_hHeatCooldownBomber.FloatValue;
	cv_hHeatCooldownBomber.AddChangeHook(OnConVarChanged);

	cv_hHeatCooldownBomberCA = CreateConVar("sm_botspawn_heat_bomber_ca", "20.0", "Spawn heat cooldown for bomber bots during counter-attack.", _, true, 0.0, true, 120.0);
	g_fHeatCooldownBomberCA = cv_hHeatCooldownBomberCA.FloatValue;
	cv_hHeatCooldownBomberCA.AddChangeHook(OnConVarChanged);

	cv_hHeatCooldownTank = CreateConVar("sm_botspawn_heat_tank", "12.0", "Spawn heat cooldown for tank bots outside counter-attack.", _, true, 0.0, true, 120.0);
	g_fHeatCooldownTank = cv_hHeatCooldownTank.FloatValue;
	cv_hHeatCooldownTank.AddChangeHook(OnConVarChanged);

	cv_hHeatCooldownTankCA = CreateConVar("sm_botspawn_heat_tank_ca", "8.0", "Spawn heat cooldown for tank bots during counter-attack.", _, true, 0.0, true, 120.0);
	g_fHeatCooldownTankCA = cv_hHeatCooldownTankCA.FloatValue;
	cv_hHeatCooldownTankCA.AddChangeHook(OnConVarChanged);

	cv_hThreatNearDist = CreateConVar("sm_botspawn_threat_neardist", "1600.0", "Distance at which Security players start counting as nearby spawn threats.", _, true, 0.0, true, 10000.0);
	g_fThreatNearDist = cv_hThreatNearDist.FloatValue;
	cv_hThreatNearDist.AddChangeHook(OnConVarChanged);

	cv_hThreatVisDist = CreateConVar("sm_botspawn_threat_visdist", "2950.0", "Maximum LOS test distance for spawn visibility scoring.", _, true, 0.0, true, 10000.0);
	g_fThreatVisDist = cv_hThreatVisDist.FloatValue;
	cv_hThreatVisDist.AddChangeHook(OnConVarChanged);

	cv_hScoreNormalDist = CreateConVar("sm_botspawn_score_normal_dist", "0.40", "Distance reward weight for normal bot spawn scoring.", _, true, 0.0, true, 10.0);
	g_fScoreNormalDist = cv_hScoreNormalDist.FloatValue;
	cv_hScoreNormalDist.AddChangeHook(OnConVarChanged);

	cv_hScoreNormalNear = CreateConVar("sm_botspawn_score_normal_near", "180.0", "Nearby-human penalty weight for normal bot spawn scoring.", _, true, 0.0, true, 1000.0);
	g_fScoreNormalNear = cv_hScoreNormalNear.FloatValue;
	cv_hScoreNormalNear.AddChangeHook(OnConVarChanged);

	cv_hScoreNormalVisible = CreateConVar("sm_botspawn_score_normal_visible", "250.0", "Visible-human penalty weight for normal bot spawn scoring.", _, true, 0.0, true, 1000.0);
	g_fScoreNormalVisible = cv_hScoreNormalVisible.FloatValue;
	cv_hScoreNormalVisible.AddChangeHook(OnConVarChanged);

	cv_hScoreBomberDist = CreateConVar("sm_botspawn_score_bomber_dist", "0.70", "Distance reward weight for bomber spawn scoring.", _, true, 0.0, true, 10.0);
	g_fScoreBomberDist = cv_hScoreBomberDist.FloatValue;
	cv_hScoreBomberDist.AddChangeHook(OnConVarChanged);

	cv_hScoreBomberNear = CreateConVar("sm_botspawn_score_bomber_near", "260.0", "Nearby-human penalty weight for bomber spawn scoring.", _, true, 0.0, true, 1000.0);
	g_fScoreBomberNear = cv_hScoreBomberNear.FloatValue;
	cv_hScoreBomberNear.AddChangeHook(OnConVarChanged);

	cv_hScoreBomberVisible = CreateConVar("sm_botspawn_score_bomber_visible", "425.0", "Visible-human penalty weight for bomber spawn scoring.", _, true, 0.0, true, 1000.0);
	g_fScoreBomberVisible = cv_hScoreBomberVisible.FloatValue;
	cv_hScoreBomberVisible.AddChangeHook(OnConVarChanged);

	cv_hScoreTankTargetDist = CreateConVar("sm_botspawn_score_tank_targetdist", "950.0", "Preferred normal-mode distance to Security for tank spawn scoring.", _, true, 0.0, true, 10000.0);
	g_fScoreTankTargetDist = cv_hScoreTankTargetDist.FloatValue;
	cv_hScoreTankTargetDist.AddChangeHook(OnConVarChanged);

	cv_hScoreTankTargetDistCA = CreateConVar("sm_botspawn_score_tank_targetdist_ca", "800.0", "Preferred counter-attack distance to Security for tank spawn scoring.", _, true, 0.0, true, 10000.0);
	g_fScoreTankTargetDistCA = cv_hScoreTankTargetDistCA.FloatValue;
	cv_hScoreTankTargetDistCA.AddChangeHook(OnConVarChanged);

	cv_hScoreTankTargetBase = CreateConVar("sm_botspawn_score_tank_targetbase", "350.0", "Base score for tank target-distance scoring.", _, true, 0.0, true, 5000.0);
	g_fScoreTankTargetBase = cv_hScoreTankTargetBase.FloatValue;
	cv_hScoreTankTargetBase.AddChangeHook(OnConVarChanged);

	cv_hScoreTankTargetWeight = CreateConVar("sm_botspawn_score_tank_targetweight", "0.25", "Distance deviation penalty for tank target-distance scoring.", _, true, 0.0, true, 10.0);
	g_fScoreTankTargetWeight = cv_hScoreTankTargetWeight.FloatValue;
	cv_hScoreTankTargetWeight.AddChangeHook(OnConVarChanged);

	cv_hScoreTankNear = CreateConVar("sm_botspawn_score_tank_near", "110.0", "Nearby-human penalty weight for tank spawn scoring.", _, true, 0.0, true, 1000.0);
	g_fScoreTankNear = cv_hScoreTankNear.FloatValue;
	cv_hScoreTankNear.AddChangeHook(OnConVarChanged);

	cv_hScoreTankVisible = CreateConVar("sm_botspawn_score_tank_visible", "120.0", "Visible-human penalty weight for tank spawn scoring.", _, true, 0.0, true, 1000.0);
	g_fScoreTankVisible = cv_hScoreTankVisible.FloatValue;
	cv_hScoreTankVisible.AddChangeHook(OnConVarChanged);

	cv_hHeatPenaltyBase = CreateConVar("sm_botspawn_heat_penalty_base", "500.0", "Base score penalty when a spawn is still on heat cooldown.", _, true, 0.0, true, 5000.0);
	g_fHeatPenaltyBase = cv_hHeatPenaltyBase.FloatValue;
	cv_hHeatPenaltyBase.AddChangeHook(OnConVarChanged);

	cv_hHeatPenaltyWeight = CreateConVar("sm_botspawn_heat_penalty_weight", "20.0", "Extra score penalty per second of remaining spawn heat cooldown.", _, true, 0.0, true, 1000.0);
	g_fHeatPenaltyWeight = cv_hHeatPenaltyWeight.FloatValue;
	cv_hHeatPenaltyWeight.AddChangeHook(OnConVarChanged);

	cv_hHeatRandomJitter = CreateConVar("sm_botspawn_heat_jitter", "10.0", "Random score jitter added after spawn heat and threat scoring.", _, true, 0.0, true, 100.0);
	g_fHeatRandomJitter = cv_hHeatRandomJitter.FloatValue;
	cv_hHeatRandomJitter.AddChangeHook(OnConVarChanged);

	cv_hAntiLoopWindow = CreateConVar("sm_botspawn_antiloop_window", "20.0", "Death window in seconds for anti-loop spawn penalties.", _, true, 0.0, true, 120.0);
	g_fAntiLoopWindow = cv_hAntiLoopWindow.FloatValue;
	cv_hAntiLoopWindow.AddChangeHook(OnConVarChanged);

	cv_hAntiLoopDist = CreateConVar("sm_botspawn_antiloop_dist", "800.0", "Max distance from original spawn to count a bot death as a spawn loop.", _, true, 0.0, true, 5000.0);
	g_fAntiLoopDist = cv_hAntiLoopDist.FloatValue;
	cv_hAntiLoopDist.AddChangeHook(OnConVarChanged);

	cv_hAntiLoopPenalty = CreateConVar("sm_botspawn_antiloop_penalty", "45.0", "Base anti-loop spawn penalty duration in seconds.", _, true, 0.0, true, 300.0);
	g_fAntiLoopPenalty = cv_hAntiLoopPenalty.FloatValue;
	cv_hAntiLoopPenalty.AddChangeHook(OnConVarChanged);

	cv_hAntiLoopPenaltyBomberBonus = CreateConVar("sm_botspawn_antiloop_penalty_bomber", "15.0", "Extra anti-loop penalty duration for bomber bot spawn loops.", _, true, 0.0, true, 300.0);
	g_fAntiLoopPenaltyBomberBonus = cv_hAntiLoopPenaltyBomberBonus.FloatValue;
	cv_hAntiLoopPenaltyBomberBonus.AddChangeHook(OnConVarChanged);

	cv_hAntiLoopPenaltyTankBonus = CreateConVar("sm_botspawn_antiloop_penalty_tank", "10.0", "Extra anti-loop penalty duration for tank bot spawn loops.", _, true, 0.0, true, 300.0);
	g_fAntiLoopPenaltyTankBonus = cv_hAntiLoopPenaltyTankBonus.FloatValue;
	cv_hAntiLoopPenaltyTankBonus.AddChangeHook(OnConVarChanged);

	cv_hAntiLoopPenaltyMax = CreateConVar("sm_botspawn_antiloop_penalty_max", "120.0", "Maximum total anti-loop penalty duration in seconds for a single spawn.", _, true, 0.0, true, 600.0);
	g_fAntiLoopPenaltyMax = cv_hAntiLoopPenaltyMax.FloatValue;
	cv_hAntiLoopPenaltyMax.AddChangeHook(OnConVarChanged);

	g_cvCAWarnRadius = CreateConVar("sm_botcawarn_radius", "350.0", "Radius around counter-attack bot spawns to warn Security players in center text (0 = disabled).", _, true, 0.0, true, 5000.0);
	g_fCAWarnRadius = g_cvCAWarnRadius.FloatValue;
	g_cvCAWarnRadius.AddChangeHook(OnConVarChanged);

	cv_hCounterAttackDuration = FindConVar("mp_checkpoint_counterattack_duration");
	cv_hCounterAttackDisable = FindConVar("mp_checkpoint_counterattack_disable");
	cv_hCounterAttackAlways = FindConVar("mp_checkpoint_counterattack_always");
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == cv_hBotLives)
		g_iBotLives = cv_hBotLives.IntValue;
	else if (convar == cv_hMaxCounterAttackDuration)
		g_iMaxCounterAttackDuration = cv_hMaxCounterAttackDuration.IntValue;
	else if (convar == cv_hMinCounterAttackDuration)
		g_iMinCounterAttackDuration = cv_hMinCounterAttackDuration.IntValue;
	else if (convar == cv_hCounterAttackChance)
		g_fCounterAttackChance = cv_hCounterAttackChance.FloatValue;
	else if (convar == cv_hMinSpawnDistHuman)
		g_fMinSpawnDistHuman = cv_hMinSpawnDistHuman.FloatValue;
	else if (convar == cv_hProximityGraceSeconds)
		g_fProximityGraceSeconds = cv_hProximityGraceSeconds.FloatValue;
	else if (convar == cv_hBomberRespawns)
		g_iBomberRespawnsMax = cv_hBomberRespawns.IntValue;
	else if (convar == cv_hTankRespawns)
		g_iTankRespawnsMax = cv_hTankRespawns.IntValue;
	else if (convar == cv_hRoleMinDistScaleNormal)
		g_fRoleMinDistScaleNormal = cv_hRoleMinDistScaleNormal.FloatValue;
	else if (convar == cv_hRoleMinDistScaleBomber)
		g_fRoleMinDistScaleBomber = cv_hRoleMinDistScaleBomber.FloatValue;
	else if (convar == cv_hRoleMinDistScaleTank)
		g_fRoleMinDistScaleTank = cv_hRoleMinDistScaleTank.FloatValue;
	else if (convar == cv_hHeatCooldownNormal)
		g_fHeatCooldownNormal = cv_hHeatCooldownNormal.FloatValue;
	else if (convar == cv_hHeatCooldownNormalCA)
		g_fHeatCooldownNormalCA = cv_hHeatCooldownNormalCA.FloatValue;
	else if (convar == cv_hHeatCooldownBomber)
		g_fHeatCooldownBomber = cv_hHeatCooldownBomber.FloatValue;
	else if (convar == cv_hHeatCooldownBomberCA)
		g_fHeatCooldownBomberCA = cv_hHeatCooldownBomberCA.FloatValue;
	else if (convar == cv_hHeatCooldownTank)
		g_fHeatCooldownTank = cv_hHeatCooldownTank.FloatValue;
	else if (convar == cv_hHeatCooldownTankCA)
		g_fHeatCooldownTankCA = cv_hHeatCooldownTankCA.FloatValue;
	else if (convar == cv_hThreatNearDist)
		g_fThreatNearDist = cv_hThreatNearDist.FloatValue;
	else if (convar == cv_hThreatVisDist)
		g_fThreatVisDist = cv_hThreatVisDist.FloatValue;
	else if (convar == cv_hScoreNormalDist)
		g_fScoreNormalDist = cv_hScoreNormalDist.FloatValue;
	else if (convar == cv_hScoreNormalNear)
		g_fScoreNormalNear = cv_hScoreNormalNear.FloatValue;
	else if (convar == cv_hScoreNormalVisible)
		g_fScoreNormalVisible = cv_hScoreNormalVisible.FloatValue;
	else if (convar == cv_hScoreBomberDist)
		g_fScoreBomberDist = cv_hScoreBomberDist.FloatValue;
	else if (convar == cv_hScoreBomberNear)
		g_fScoreBomberNear = cv_hScoreBomberNear.FloatValue;
	else if (convar == cv_hScoreBomberVisible)
		g_fScoreBomberVisible = cv_hScoreBomberVisible.FloatValue;
	else if (convar == cv_hScoreTankTargetDist)
		g_fScoreTankTargetDist = cv_hScoreTankTargetDist.FloatValue;
	else if (convar == cv_hScoreTankTargetDistCA)
		g_fScoreTankTargetDistCA = cv_hScoreTankTargetDistCA.FloatValue;
	else if (convar == cv_hScoreTankTargetBase)
		g_fScoreTankTargetBase = cv_hScoreTankTargetBase.FloatValue;
	else if (convar == cv_hScoreTankTargetWeight)
		g_fScoreTankTargetWeight = cv_hScoreTankTargetWeight.FloatValue;
	else if (convar == cv_hScoreTankNear)
		g_fScoreTankNear = cv_hScoreTankNear.FloatValue;
	else if (convar == cv_hScoreTankVisible)
		g_fScoreTankVisible = cv_hScoreTankVisible.FloatValue;
	else if (convar == cv_hHeatPenaltyBase)
		g_fHeatPenaltyBase = cv_hHeatPenaltyBase.FloatValue;
	else if (convar == cv_hHeatPenaltyWeight)
		g_fHeatPenaltyWeight = cv_hHeatPenaltyWeight.FloatValue;
	else if (convar == cv_hHeatRandomJitter)
		g_fHeatRandomJitter = cv_hHeatRandomJitter.FloatValue;
	else if (convar == cv_hAntiLoopWindow)
		g_fAntiLoopWindow = cv_hAntiLoopWindow.FloatValue;
	else if (convar == cv_hAntiLoopDist)
		g_fAntiLoopDist = cv_hAntiLoopDist.FloatValue;
	else if (convar == cv_hAntiLoopPenalty)
		g_fAntiLoopPenalty = cv_hAntiLoopPenalty.FloatValue;
	else if (convar == cv_hAntiLoopPenaltyBomberBonus)
		g_fAntiLoopPenaltyBomberBonus = cv_hAntiLoopPenaltyBomberBonus.FloatValue;
	else if (convar == cv_hAntiLoopPenaltyTankBonus)
		g_fAntiLoopPenaltyTankBonus = cv_hAntiLoopPenaltyTankBonus.FloatValue;
	else if (convar == cv_hAntiLoopPenaltyMax)
		g_fAntiLoopPenaltyMax = cv_hAntiLoopPenaltyMax.FloatValue;
	else if (convar == g_cvCADelay)
		g_iCADelay = g_cvCADelay.IntValue;
	else if (convar == g_cvCADelayFinale)
		g_iCADelayFinale = g_cvCADelayFinale.IntValue;
	else if (convar == g_cvCAWarnRadius)
		g_fCAWarnRadius = g_cvCAWarnRadius.FloatValue;
}
