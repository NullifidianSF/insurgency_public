#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PL_VERSION		"1.0.1"

#define TEAM_SPECTATOR	1
#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

#define MAX_CPS 32

float g_fMinSpawnDistHuman = 1300.0;		// how far from humans a CP spawn must be
float g_fProximityGraceSeconds = 15.0;		// disable proximity check for this long

float g_fProxGraceUntil = 0.0;

ArrayList g_CPSpawns[MAX_CPS];
ArrayList g_CASpawns[MAX_CPS];
int g_iNumCPs = 0;
int g_iActiveCP = 0;

Handle	g_hForceRespawn = null;
Handle	g_hGameConfig = null;

ConVar cv_hBotLives = null;
ConVar cv_hMaxCounterAttackDuration = null;
ConVar cv_hMinCounterAttackDuration = null;
ConVar cv_hCounterAttackDuration = null;
ConVar cv_hCounterAttackDisable = null;
ConVar cv_hCounterAttackAlways = null;
ConVar cv_hCounterAttackChance = null;
ConVar cv_hMinSpawnDistHuman = null;
ConVar cv_hProximityGraceSeconds = null;

int g_iMaxCounterAttackDuration;
int g_iMinCounterAttackDuration;
float g_fCounterAttackChance;

int ga_iStuckCheckSount[MAXPLAYERS + 1] = {0, ...};
bool ga_bIsBotStuck[MAXPLAYERS + 1] = {false, ...};
float ga_fBotSpawnOrigin[MAXPLAYERS + 1][3];
float ga_fBotSpawnTime[MAXPLAYERS + 1] = {0.0, ...};
int ga_iBotNoMoveChecks[MAXPLAYERS + 1] = {0, ...};
bool ga_bBotSpawnOriginValid[MAXPLAYERS + 1] = {false, ...};
float ga_fBotLastPos[MAXPLAYERS + 1][3];
float ga_fBotLastMoveTime[MAXPLAYERS + 1] = {0.0, ...};
int ga_iBotIdleMoveChecks[MAXPLAYERS + 1] = {0, ...};

int g_iBotLives = 0;
int g_iBotLivesRemain = 0;

int g_iPlayerEquipGear;
static const int g_iRadioGearID = 4;
int g_iTotalAliveEnemies;

bool g_bIsMapChanging = false;
bool g_bIsGameEnd = false;
bool g_bIsRoundActive = false;

int g_iObjResEntity = -1;
char g_sObjResNetClass[32];

bool ga_bPickSquad[MAXPLAYERS + 1] = {false, ...};

bool g_bLateLoad;

public Plugin myinfo = {
	name		= "bm_botrespawn",
	author		= "Nullifidian + ChatGPT",
	description	= "Respawns bots at custom spawn locations",
	version		= PL_VERSION
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	if ((g_hGameConfig = LoadGameConfigFile("insurgency.games")) == INVALID_HANDLE)
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");

	if ((g_iPlayerEquipGear = FindSendPropInfo("CINSPlayer", "m_EquippedGear")) == -1)
		SetFailState("Offset \"m_EquippedGear\" not found!");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(g_hGameConfig, SDKConf_Signature, "ForceRespawn");
	if ((g_hForceRespawn = EndPrepSDKCall()) == INVALID_HANDLE)
		SetFailState("Fatal Error: Unable to find signature for \"ForceRespawn\"!");

	for (int i = 0; i < MAX_CPS; i++) {
		if (g_CPSpawns[i] == null) g_CPSpawns[i] = new ArrayList(3);
		if (g_CASpawns[i] == null) g_CASpawns[i] = new ArrayList(3);
	}

	SetupCvars();
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("object_destroyed", Event_ObjDone_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", Event_ObjDone_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("game_end", Event_GameEnd, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_pick_squad", Event_PlayerPickSquad_Post, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam);

	HookEvent("object_destroyed", Event_Objectives_Pre, EventHookMode_Pre);
	HookEvent("controlpoint_captured", Event_Objectives_Pre, EventHookMode_Pre);

	LoadTranslations("common.phrases");

	RegAdminCmd("sm_respawn", cmd_respawn, ADMFLAG_SLAY, "sm_respawn <#userid|name|@all|@bots|@humans|@me> - Respawn player(s).");
	RegAdminCmd("sm_bots", cmd_bots, ADMFLAG_BAN, "sm_bots - How many bots alive and lives remain.");

	if (g_bLateLoad)
		g_bIsRoundActive = true;

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart() {
	char map[64]; GetCurrentMap(map, sizeof map);

	g_iNumCPs = ObjectiveResource_GetProp("m_iNumControlPoints");
	if (g_iNumCPs < 0 || g_iNumCPs > MAX_CPS) g_iNumCPs = MAX_CPS;

	g_iActiveCP = ObjectiveResource_GetProp("m_nActivePushPointIndex");
	if (g_iActiveCP < 0) g_iActiveCP = 0;
	if (g_iActiveCP > g_iNumCPs && g_iNumCPs > 0) g_iActiveCP = g_iNumCPs - 1;

	LoadSpawnsForMap(map, g_CPSpawns, g_CASpawns, (g_iNumCPs > 0 ? g_iNumCPs : MAX_CPS));

	if (!g_bLateLoad) {
		g_bIsRoundActive = false;
		g_bLateLoad = false;
	}

	g_bIsMapChanging = false;
	g_bIsGameEnd = false;

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
}

public void OnClientPostAdminCheck(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	ga_bPickSquad[client] = false;
	ga_bBotSpawnOriginValid[client] = false;
	ga_iBotNoMoveChecks[client] = 0;
	ga_fBotSpawnTime[client] = 0.0;
	ga_fBotLastMoveTime[client] = 0.0;
	ga_iBotIdleMoveChecks[client] = 0;
}

public void OnClientDisconnect(int client) {
	if (client < 1 || client > MaxClients)
		return;

	ga_bPickSquad[client] = false;
	ga_bBotSpawnOriginValid[client] = false;
	ga_iBotNoMoveChecks[client] = 0;
	ga_fBotSpawnTime[client] = 0.0;
	ga_fBotLastMoveTime[client] = 0.0;
	ga_iBotIdleMoveChecks[client] = 0;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client < 1 || client > MaxClients)
		return Plugin_Continue;

	ga_bPickSquad[client] = false;

	return Plugin_Continue;
}

public Action Event_PlayerPickSquad_Post(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Continue;

	ga_bPickSquad[client] = true;

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
	//ga_iStuckCheckSount[client] = 0;
	//StartStuckDetection(client);
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	if (g_iBotLivesRemain < 1)
		return Plugin_Continue;
		
	int userid = event.GetInt("userid");
	int victim = GetClientOfUserId(userid);
	if (victim < 1 || !IsClientInGame(victim) || !IsFakeClient(victim) || GetClientTeam(victim) != TEAM_INSURGENT)
		return Plugin_Continue;
	
	g_iBotLivesRemain--;
	CreateTimer(0.05, Timer_RespawnBot, userid, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Timer_RespawnBot(Handle timer, any userid) {
	int bot = GetClientOfUserId(userid);
	if (!g_bIsRoundActive || bot < 1 || bot > MaxClients || !IsClientInGame(bot) || !IsFakeClient(bot) || IsPlayerAlive(bot) ||  GetClientTeam(bot) != TEAM_INSURGENT)
		return Plugin_Stop;

	SDKCall(g_hForceRespawn, bot);
	return Plugin_Stop;
}

public Action Event_ObjDone_NoCopy(Event event, const char[] name, bool dontBroadcast) {
	if (g_iActiveCP < g_iNumCPs) g_iActiveCP++;
	RequestFrame(Frame_SetBotLives);
	return Plugin_Continue;
}

public Action Event_Objectives_Pre(Event event, const char[] name, bool dontBroadcast) {
	// When an objective is completed, shut off plugin bot lives
	// and start proximity grace for the *next* objective.
	if (g_fProximityGraceSeconds > 0.0) {
		g_iBotLivesRemain = 0;
		BM_StartProxGrace(g_fProximityGraceSeconds + 1.1);
	}

	bool bFinalObj = (g_iActiveCP + 1 == g_iNumCPs);
	bool bWillCounterAttack = false;

	if (bFinalObj)
	{
		g_iBotLivesRemain = 0;

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && IsFakeClient(i) && GetClientTeam(i) == TEAM_INSURGENT)
				ForcePlayerSuicide(i);
		}

		SetConVarInt(cv_hCounterAttackDuration, GetRandomInt(g_iMaxCounterAttackDuration, g_iMinCounterAttackDuration), true, false);
		SetConVarInt(cv_hCounterAttackDisable, 0, true, false);
		SetConVarInt(cv_hCounterAttackAlways, 1, true, false);
	}
	else if (GetRandomFloat(0.0, 1.0) < g_fCounterAttackChance) {
		// Normal mid-round counter-attack
		bWillCounterAttack = true;

		SetConVarInt(cv_hCounterAttackDuration, GetRandomInt(g_iMaxCounterAttackDuration, g_iMinCounterAttackDuration), true, false);
		SetConVarInt(cv_hCounterAttackDisable, 0, true, false);
		SetConVarInt(cv_hCounterAttackAlways, 1, true, false);
	}
	else
		SetConVarInt(cv_hCounterAttackDisable, 1, true, false);

	// For non-final counter-attacks: clean up "useless" bots so the
	// engine + your CA spawns can bring a fresh wave in good positions.
	if (bWillCounterAttack && !bFinalObj)
		BM_CleanUpBotsForCounterAttack();

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

static void BM_StartProxGrace(float seconds) {
	g_fProxGraceUntil = GetGameTime() + seconds;
}

static bool BM_InProxGrace() {
	return GetGameTime() < g_fProxGraceUntil;
}

static bool BM_FindSafeSpawnForCP(int cpIndex, float humans[32][3], int hcount, float minDistSq, float outVec[3])
{
	if (cpIndex < 0 || cpIndex >= MAX_CPS)
	{
		return false;
	}

	if (g_CPSpawns[cpIndex] == null || g_CPSpawns[cpIndex].Length <= 0)
	{
		return false;
	}

	int n = g_CPSpawns[cpIndex].Length;
	int safeCount = 0;
	bool picked = false;
	float pickedPos[3];

	for (int s = 0; s < n; s++)
	{
		float cand[3];
		g_CPSpawns[cpIndex].GetArray(s, cand, 3);

		bool near = false;
		for (int h = 0; h < hcount; h++)
		{
			if (GetVectorDistance(cand, humans[h], true) <= minDistSq)
			{
				near = true;
				break;
			}
		}

		if (!near)
		{
			// Reservoir sample among all safe candidates on this CP
			safeCount++;
			if (GetRandomInt(1, safeCount) == 1)
			{
				picked = true;
				pickedPos[0] = cand[0];
				pickedPos[1] = cand[1];
				pickedPos[2] = cand[2];
			}
		}
	}

	if (!picked)
	{
		return false;
	}

	outVec[0] = pickedPos[0];
	outVec[1] = pickedPos[1];
	outVec[2] = pickedPos[2];
	return true;
}

static bool BM_IsBotVisibleToAnyHuman(int bot, float maxDistSq) {
	float botEye[3];
	GetClientEyePosition(bot, botEye);

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SECURITY)
			continue;

		float humanEye[3];
		GetClientEyePosition(i, humanEye);

		float distSq = GetVectorDistance(botEye, humanEye, true);
		if (distSq > maxDistSq)
			continue;

		Handle trace = TR_TraceRayFilterEx(humanEye, botEye, MASK_SOLID, RayType_EndPoint, TraceEntityFilterSolid);
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

	//int killed = 0;

	for (int bot = 1; bot <= MaxClients; bot++)
	{
		if (!IsClientInGame(bot) || !IsFakeClient(bot) || !IsPlayerAlive(bot) || GetClientTeam(bot) != TEAM_INSURGENT)
			continue;

		// Keep bots that are near + visible to any human
		if (BM_IsBotVisibleToAnyHuman(bot, kMaxVisDistSq))
			continue;

		// Slay irrelevant bots. Do NOT touch g_iBotLivesRemain:
		// we just zeroed it for the counter-attack, so these deaths
		// should not create extra plugin respawns.
		ForcePlayerSuicide(bot);
		//killed++;
	}

	// Optional debug:
	//PrintToServer("[bm_botrespawn] CA cleanup: killed %d far/out-of-sight bots.", killed);
}

void TeleportBot(int client) {
	float vec[3] = {0.0, 0.0, 0.0};

	int cp  = ClampCP(g_iActiveCP);
	int cpN = ClampCP(g_iActiveCP + 1);

	if (!IsCounterAttack())
	{
		bool haveCurr = HasAnySpawnsCP(cp);
		bool haveNext = (cpN != cp) && HasAnySpawnsCP(cpN);

		if (!haveCurr && !haveNext)
			return;

		// During grace OR at last CP → original selection, no proximity checks
		if (BM_InProxGrace() || g_iActiveCP == g_iNumCPs - 1)
		{
			if (haveCurr && haveNext)
			{
				if (GetRandomFloat(0.0, 1.0) <= 0.8)
				{
					int n = g_CPSpawns[cp].Length;
					g_CPSpawns[cp].GetArray((n > 1) ? GetRandomInt(0, n - 1) : 0, vec, 3);
				}
				else
				{
					int n2 = g_CPSpawns[cpN].Length;
					g_CPSpawns[cpN].GetArray((n2 > 1) ? GetRandomInt(0, n2 - 1) : 0, vec, 3);
				}
			}
			else if (haveCurr)
			{
				int n = g_CPSpawns[cp].Length;
				g_CPSpawns[cp].GetArray((n > 1) ? GetRandomInt(0, n - 1) : 0, vec, 3);
			}
			else
			{
				int n2 = g_CPSpawns[cpN].Length;
				g_CPSpawns[cpN].GetArray((n2 > 1) ? GetRandomInt(0, n2 - 1) : 0, vec, 3);
			}
		}
		else
		{
			// AFTER GRACE:
			// Check proximity on CURRENT CP, then NEXT CP,
			// then scan other CPs (forward then backward) until we find a safe spawn.

			// 1) Cache human positions once.
			float humans[32][3];
			int hcount = 0;
			for (int i = 1; i <= MaxClients && hcount < 32; i++)
			{
				if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != TEAM_SECURITY || !IsPlayerAlive(i))
					continue;

				GetClientAbsOrigin(i, humans[hcount]);
				hcount++;
			}

			float min2 = g_fMinSpawnDistHuman * g_fMinSpawnDistHuman;
			bool pickedAny = false;
			float chosen[3];

			// 2) Try current CP first (if it has spawns)
			if (haveCurr)
			{
				if (BM_FindSafeSpawnForCP(cp, humans, hcount, min2, chosen))
				{
					pickedAny = true;
				}
			}

			// 3) Then try next CP (with proximity) if not found yet
			if (!pickedAny && haveNext)
			{
				if (BM_FindSafeSpawnForCP(cpN, humans, hcount, min2, chosen))
				{
					pickedAny = true;
				}
			}

			// 4) If still nothing, scan forward through later CPs (cpN+1 .. g_iNumCPs-1)
			if (!pickedAny && g_iNumCPs > 0)
			{
				for (int c = g_iActiveCP + 2; c < g_iNumCPs; c++)
				{
					if (!HasAnySpawnsCP(c))
						continue;

					if (BM_FindSafeSpawnForCP(c, humans, hcount, min2, chosen))
					{
						pickedAny = true;
						break;
					}
				}
			}

			// 5) Finally, scan backwards through earlier CPs (cp-1 .. 0)
			if (!pickedAny && g_iNumCPs > 0)
			{
				for (int c = g_iActiveCP - 1; c >= 0; c--)
				{
					if (!HasAnySpawnsCP(c))
						continue;

					if (BM_FindSafeSpawnForCP(c, humans, hcount, min2, chosen))
					{
						pickedAny = true;
						break;
					}
				}
			}

			if (!pickedAny)
			{
				// No safe custom spawn anywhere → fall back to default game spawn
				return;
			}

			vec[0] = chosen[0];
			vec[1] = chosen[1];
			vec[2] = chosen[2];
		}
	}
	else
	{
		// Counter-attack: unchanged (no proximity filter unless you want it)
		int cpC = ClampCP(g_iActiveCP - 1);
		int m = g_CASpawns[cpC].Length;
		if (m <= 0) return;
		g_CASpawns[cpC].GetArray((m > 1) ? GetRandomInt(0, m - 1) : 0, vec, 3);
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
	const int kSpawnRequiredNoMoveChecks_Normal = 2;

	// During COUNTER-ATTACK we want this faster:
	const int kSpawnRequiredNoMoveChecks_CA = 1;

	// Nav-stuck (general idle): how long they must be idle before we care
	const float kNavIdleMinTime_Normal = 180.0;	// normal: ~3+ minutes

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

	for (int client = 1; client <= MaxClients; client++)
	{
		// We only track alive insurgent bots.
		if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_INSURGENT)
		{
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
		if (ga_bBotSpawnOriginValid[client])
		{
			// Only start caring once they've had some time to move away from spawn.
			if (now - ga_fBotSpawnTime[client] >= kMinSpawnStuckTime)
			{
				float dist2Spawn = GetVectorDistance(origin, ga_fBotSpawnOrigin[client], true);

				if (dist2Spawn <= kSpawnMoveDistSq)
				{
					// Still basically at custom spawn
					ga_iBotNoMoveChecks[client]++;

					if (ga_iBotNoMoveChecks[client] >= spawnRequiredNoMoveChecks)
					{
						// Treat as spawn-stuck: kill and refund a life so this bot
						// doesn't eat reinforcements.
						int livesBefore = g_iBotLivesRemain;
						if (g_bIsRoundActive && livesBefore > 0)
						{
							// This cancels out the -- in Event_PlayerDeath.
							g_iBotLivesRemain++;
						}

						ForcePlayerSuicide(client);

						ga_bBotSpawnOriginValid[client] = false;
						ga_iBotNoMoveChecks[client] = 0;

						// Bot will respawn if there were lives left; no need to run
						// nav-stuck logic for this client on this tick.
						continue;
					}
				}
				else
				{
					// Left spawn radius → stop spawn-based tracking for this bot.
					ga_bBotSpawnOriginValid[client] = false;
					ga_iBotNoMoveChecks[client] = 0;
				}
			}
		}

		// ---------------- NAV-STUCK (GENERAL IDLE) CHECK ----------------

		// First-time init for nav-stuck tracking
		if (ga_fBotLastMoveTime[client] <= 0.0)
		{
			ga_fBotLastPos[client][0] = origin[0];
			ga_fBotLastPos[client][1] = origin[1];
			ga_fBotLastPos[client][2] = origin[2];
			ga_fBotLastMoveTime[client] = now;
			ga_iBotIdleMoveChecks[client] = 0;
			continue;
		}

		float dist2Nav = GetVectorDistance(origin, ga_fBotLastPos[client], true);

		if (dist2Nav > kNavMoveDistSq)
		{
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
		{
			// Not idle long enough yet; keep waiting.
			continue;
		}

		ga_iBotIdleMoveChecks[client]++;

		if (ga_iBotIdleMoveChecks[client] >= kNavRequiredIdleChecks)
		{
			// Treat as "nav-stuck anywhere": kill and refund a life iff there
			// were still reinforcements available.
			int livesBefore2 = g_iBotLivesRemain;
			if (g_bIsRoundActive && livesBefore2 > 0)
			{
				g_iBotLivesRemain++;
			}

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

static int ClampCP(int cp) {
	if (cp < 0) return 0;
	if (cp > g_iNumCPs) return g_iNumCPs;	//cp >= g_iNumCPs
	return cp;
}

static bool HasAnySpawnsCP(int cp) {
	cp = ClampCP(cp);
	return (g_CPSpawns[cp].Length > 0);
}

void StartStuckDetection(int client) {
	ga_iStuckCheckSount[client]++;
	ga_bIsBotStuck[client] = false;
	CheckIfBotCanMove(client, 0, 500.0, 0.0, 0.0);
	ga_bIsBotStuck[client] = CheckIfBotStuck(client);
}

bool CheckIfBotStuck(int client) {
	float vecMin[3], vecMax[3], vecOrigin[3];
	GetClientMins(client, vecMin);
	GetClientMaxs(client, vecMax);
	GetClientAbsOrigin(client, vecOrigin);
	TR_TraceHullFilter(vecOrigin, vecOrigin, vecMin, vecMax, MASK_SOLID, TraceEntityFilterSolid);
	return TR_DidHit();
}

void CheckIfBotCanMove(int client, int testid, float X=0.0, float Y=0.0, float Z=0.0) {
	float origin[3];
	GetClientAbsOrigin(client, origin);

	float vel[3];
	vel[0] = X;
	vel[1] = Y;
	vel[2] = Z;
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", vel);

	int userid = GetClientUserId(client);

	DataPack TimerDataPack;
	CreateDataTimer(0.1, TimerWait, TimerDataPack, TIMER_FLAG_NO_MAPCHANGE);
	TimerDataPack.WriteCell(userid);
	TimerDataPack.WriteCell(testid);
	TimerDataPack.WriteFloat(origin[0]);
	TimerDataPack.WriteFloat(origin[1]);
	TimerDataPack.WriteFloat(origin[2]);
}

Action TimerWait(Handle timer, DataPack data) {
	float origin[3];
	float NewOrigin[3];

	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	int testid = data.ReadCell();
	origin[0] = data.ReadFloat();
	origin[1] = data.ReadFloat();
	origin[2] = data.ReadFloat();
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)) {
		GetClientAbsOrigin(client, NewOrigin);
		if (GetVectorDistance(origin, NewOrigin, false) < 10.0) {
			if (testid == 0)
				CheckIfBotCanMove(client, 1, 0.0, 0.0, -500.0);
			else if (testid == 1)
				CheckIfBotCanMove(client, 2, -500.0, 0.0, 0.0);
			else if (testid == 2)
				CheckIfBotCanMove(client, 3, 0.0, 500.0, 0.0);
			else if (testid == 3)
				CheckIfBotCanMove(client, 4, 0.0, -500.0, 0.0);
			else if (testid == 4)
				CheckIfBotCanMove(client, 5, 0.0, 0.0, 300.0);
			else
				FixPlayerPosition(client);
		}
	}
	return Plugin_Stop;
}

void FixPlayerPosition(int client) {
	if (ga_bIsBotStuck[client]) {
		float pos_Z = 0.1;
		while (pos_Z <= 200.0 && !TryFixPosition(client, 10.0, pos_Z)) {
			pos_Z = -pos_Z;
			if (pos_Z > 0.0)
				pos_Z += 20.0;
		}
		if (!CheckIfBotStuck(client) && ga_iStuckCheckSount[client] < 7)
			StartStuckDetection(client);
	}
	else {
		Handle trace = INVALID_HANDLE;
		float vecOrigin[3], vecAngle[3];
		GetClientAbsOrigin(client, vecOrigin);
		vecAngle[0] = 90.0;
		trace = TR_TraceRayFilterEx(vecOrigin, vecAngle, MASK_SOLID, RayType_Infinite, TraceEntityFilterSolid);
		if (!TR_DidHit(trace)) {
			delete trace;
			return;
		}
		
		TR_GetEndPosition(vecOrigin, trace);
		delete trace;
		vecOrigin[2] += 10.0;
		TeleportEntity(client, vecOrigin, NULL_VECTOR, {0.0, 0.0, -300.0});

		if (ga_iStuckCheckSount[client] < 7) {
			StartStuckDetection(client);
		} else {
			ForcePlayerSuicide(client);
			g_iBotLivesRemain++;
		}
	}
}

public bool TraceEntityFilterSolid(int entity, int contentsMask, any data) {
	return (entity > MaxClients);
}

bool TryFixPosition(int client, float rad, float pos_Z) {
	float DegreeAngle, vecPosition[3], vecOrigin[3], vecAngle[3];
	GetClientAbsOrigin(client, vecOrigin);
	GetClientEyeAngles(client, vecAngle);
	vecPosition[2] = vecOrigin[2] + pos_Z;

	DegreeAngle = -180.0;
	while (DegreeAngle < 180.0) {
		vecPosition[0] = vecOrigin[0] + rad * Cosine(DegreeAngle * FLOAT_PI / 180);
		vecPosition[1] = vecOrigin[1] + rad * Sine(DegreeAngle * FLOAT_PI / 180);
		
		TeleportEntity(client, vecPosition, vecAngle, {0.0, 0.0, -300.0});
		if (!CheckIfBotStuck(client))
			return true;
		DegreeAngle += 10.0;
	}
	TeleportEntity(client, vecOrigin, vecAngle, {0.0, 0.0, -300.0});
	if (rad <= 200.0)
		return TryFixPosition(client, rad + 20.0, pos_Z);
	return false;
}

bool LoadSpawnsForMap(const char[] map, ArrayList[] cpSpawns, ArrayList[] caSpawns, int maxCps) {
	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof path, "addons/sourcemod/data/bm_botspawns/%s.txt", map);

	File f = OpenFile(path, "r");
	if (f == null) return false;

	for (int i = 0; i < maxCps; i++) {
		if (cpSpawns[i] == null) cpSpawns[i] = new ArrayList(3);
		else cpSpawns[i].Clear();
		if (caSpawns[i] == null) caSpawns[i] = new ArrayList(3);
		else caSpawns[i].Clear();
	}

	int cp = -1; bool inCA = false;
	char line[256];
	while (!f.EndOfFile() && f.ReadLine(line, sizeof line))
	{
		TrimString(line);
		if (line[0] == '\0') continue;

		if (line[0] == '"' && line[1] == 'C' && line[2] == 'P') {
			int i = 3, n = 0; while (line[i] >= '0' && line[i] <= '9') { n = n*10 + (line[i]-'0'); i++; }
			cp = (n >= 0 && n < maxCps) ? n : -1; inCA = false; continue;
		}
		if (StrContains(line, "\"CA\"") == 0) { inCA = true; continue; }
		if (line[0] == '{' || line[0] == '}') { if (line[0] == '}') inCA = false; continue; }

		if (cp >= 0 && line[0] == '"') {
			int len = strlen(line);
			if (len >= 2 && line[len-1] == '"') line[len-1] = '\0';
			char vec[256]; strcopy(vec, sizeof vec, line[1]);
			TrimString(vec);
			float v[3];
			if (BM_ParseVec3(vec, v)) {
				(inCA ? caSpawns[cp] : cpSpawns[cp]).PushArray(v, 3);
			}
		}
	}
	delete f;
	return true;
}

bool BM_ParseVec3(const char[] s, float out[3]) {
	char parts[3][32];
	int n = ExplodeString(s, ",", parts, 3, 32);
	if (n != 3) return false;
	TrimString(parts[0]); TrimString(parts[1]); TrimString(parts[2]);
	out[0] = StringToFloat(parts[0]);
	out[1] = StringToFloat(parts[1]);
	out[2] = StringToFloat(parts[2]);
	return true;
}

void SetBotLives() {
	g_iBotLivesRemain = g_iBotLives > 0 ? SecPlayersInGame() * g_iBotLives : 0;
}

int SecPlayersInGame() {
	int n = 0;
	for ( int i = 1; i <= MaxClients; i++ ) {
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == TEAM_SECURITY)
				n++;
	}
	return n;
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
		if (IsMapValid(nextMap))
			g_bIsMapChanging = true;
	}
	return Plugin_Continue;
}

int OR_Cache(bool force = false) {
	if (force || g_iObjResEntity < 1 || !IsValidEntity(g_iObjResEntity)) {
		g_iObjResEntity = FindEntityByClassname(-1, "ins_objective_resource");
		if (g_iObjResEntity > 0) GetEntityNetClass(g_iObjResEntity, g_sObjResNetClass, sizeof(g_sObjResNetClass));
		else g_sObjResNetClass[0] = '\0';
	} else {
		char cls[32];
		GetEntityClassname(g_iObjResEntity, cls, sizeof(cls));
		if (!StrEqual(cls, "ins_objective_resource", false)) return OR_Cache(true);
	}
	return g_iObjResEntity;
}

int ObjectiveResource_GetProp(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1) return GetEntData(g_iObjResEntity, offs + (size * element));
	}
	return -1;
}

bool IsCounterAttack() {
	return view_as<bool>(GameRules_GetProp("m_bCounterAttack"));
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
		if (IsClientInGame(i)
			&& IsPlayerAlive(i)
			&& GetClientTeam(i) == TEAM_INSURGENT) {
			count++;
		}
	}
	return count;
}

Action Timer_Enemies_Remaining(Handle timer) {
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

public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	g_bIsGameEnd = true;
	g_bIsRoundActive = false;
}

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

	cv_hMinSpawnDistHuman = CreateConVar("sm_botspawnmindist", "1300.0", "Minimum distance (in units) from human players for bot custom spawns.", _, true, 0.0, true, 5000.0);
	g_fMinSpawnDistHuman = cv_hMinSpawnDistHuman.FloatValue;
	cv_hMinSpawnDistHuman.AddChangeHook(OnConVarChanged);

	cv_hProximityGraceSeconds = CreateConVar("sm_botproxgrace", "15.0", "Seconds after objective where bot spawns ignore proximity checks.", _, true, 0.0, true, 60.0);
	g_fProximityGraceSeconds = cv_hProximityGraceSeconds.FloatValue;
	cv_hProximityGraceSeconds.AddChangeHook(OnConVarChanged);

	cv_hCounterAttackDuration = FindConVar("mp_checkpoint_counterattack_duration");
	cv_hCounterAttackDisable = FindConVar("mp_checkpoint_counterattack_disable");
	cv_hCounterAttackAlways = FindConVar("mp_checkpoint_counterattack_always");
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
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
}