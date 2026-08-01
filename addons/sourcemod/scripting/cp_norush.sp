#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define TEAM_SPECTATOR 1
#define TEAM_SECURITY 2
#define TEAM_INSURGENT 3

#define MAXENTITIES 2048

#define MAX_CONTROLPOINTS 20
float ga_fCPpos[MAX_CONTROLPOINTS][3];
char ga_sCPname[MAX_CONTROLPOINTS][64];
int ga_iCPCZent[MAX_CONTROLPOINTS];

static int  g_iObjResEntity = -1;
static char g_sObjResNetClass[32];

int g_iNCP;
int g_iBlockedCpTimes = 0;
int g_iBlockcountdown = 0;
int g_iAntiRushTimer = 0;
int g_iDisabledCZ = 0;
int g_iHookedCZ = 0;
int g_iAliveSecPlayers= 0;
int g_iActivePoint = 0;
int g_iRushBlockTime;

float g_fRushPercent;
bool ga_bPlayerAlive[MAXPLAYERS + 1] = {false, ...};
bool g_bIsLateLoad;

ConVar g_cvRushBlockTime;
ConVar g_cvRushPercent;

public Plugin myinfo = {
	name = "cp_norush",
	author = "Nullifidian",
	description = "Disable CP if low player cap",
	version = "2.1",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bIsLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	g_cvRushBlockTime = CreateConVar("sm_rushblocktime", "15.0",
		"For how long to disable CP objective when trying to cap CP with low number of players",
		_, true, 0.0, true, 90.0);
	g_iRushBlockTime = g_cvRushBlockTime.IntValue;
	g_cvRushBlockTime.AddChangeHook(OnConVarChanged);

	g_cvRushPercent = CreateConVar("sm_rushpercent", "0.5",
		"Percent (rounded to nearest) of alive players need to be on a CP to cap",
		_, true, 0.0, true, 1.0);
	g_fRushPercent = g_cvRushPercent.FloatValue;
	g_cvRushPercent.AddChangeHook(OnConVarChanged);

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("object_destroyed", ObjEvents_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", ObjEvents_NoCopy, EventHookMode_PostNoCopy);

	char cfgName[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, cfgName, sizeof cfgName);
	ReplaceString(cfgName, sizeof cfgName, ".smx", "", false);
	AutoExecConfig(true, cfgName);
}

public void OnMapStart() {
	g_iHookedCZ = 0;
	g_iActivePoint = 0;
	for (int i = 1; i <= MaxClients; i++) ga_bPlayerAlive[i] = false;
	for (int i = 0; i < MAX_CONTROLPOINTS; i++) {
		ga_iCPCZent[i] = -1;
		ga_sCPname[i][0] = '\0';
		ga_fCPpos[i][0] = ga_fCPpos[i][1] = ga_fCPpos[i][2] = 0.0;
	}
	CreateTimer(1.0, Timer_MapStart, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_MapStart(Handle timer) {
	OR_Cache(true);

	g_iNCP = ObjectiveResource_GetProp("m_iNumControlPoints");
	if (g_iNCP < 0) g_iNCP = 0;
	if (g_iNCP > MAX_CONTROLPOINTS) g_iNCP = MAX_CONTROLPOINTS;

	FindCPpos();
	MatchByExactPosition();
	if (g_bIsLateLoad) SetActivePointAndHook();
	return Plugin_Stop;
}

public Action Event_RoundStart(Event event, char[] name, bool dontBroadcast) {
	g_iBlockedCpTimes = 0;
	UnhookCZ();
	RequestFrame(Frame_SetActivePointAndHook);
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++) ga_bPlayerAlive[i] = false;
	g_iAliveSecPlayers = 0;
	UnhookCZ();
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client && !IsFakeClient(client) && IsPlayerAlive(client)) {
		if (g_iAntiRushTimer == g_iHookedCZ && !ga_bPlayerAlive[client]) g_iAliveSecPlayers++;
		ga_bPlayerAlive[client] = true;
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if (victim && !IsFakeClient(victim)) {
		if (g_iAntiRushTimer == g_iHookedCZ && ga_bPlayerAlive[victim]) {
			ga_bPlayerAlive[victim] = false;
			g_iAliveSecPlayers--;
		}
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client) {
	if (client && g_iAntiRushTimer == g_iHookedCZ && ga_bPlayerAlive[client]) {
		ga_bPlayerAlive[client] = false;
		g_iAliveSecPlayers--;
	}
}

void FindCPpos() {
	for (int i = 0; i < g_iNCP; i++) ObjectiveResource_GetPropVector("m_vCPPositions", ga_fCPpos[i], i);
}

void MatchByExactPosition() {
	char classname[64];
	char targetname[64];
	float origin[3];

	for (int ent = MaxClients + 1; ent <= MAXENTITIES; ent++) {
		if (!IsValidEntity(ent)) continue;

		GetEntityClassname(ent, classname, sizeof(classname));
		if (strcmp(classname, "point_controlpoint") != 0) continue;

		GetEntPropVector(ent, Prop_Data, "m_vecOrigin", origin);
		GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));

		for (int i = 0; i < g_iNCP; i++) {
			if (FloatCompare(ga_fCPpos[i][0], origin[0]) == 0 && FloatCompare(ga_fCPpos[i][1], origin[1]) == 0 && FloatCompare(ga_fCPpos[i][2], origin[2]) == 0) {
				strcopy(ga_sCPname[i], sizeof(ga_sCPname[]), targetname);
				break;
			}
		}
	}

	for (int ent = MaxClients + 1; ent <= MAXENTITIES; ent++) {
		if (!IsValidEntity(ent)) continue;

		GetEntityClassname(ent, classname, sizeof(classname));
		if (strcmp(classname, "trigger_capture_zone") != 0) continue;

		char cpTarget[64];
		GetEntPropString(ent, Prop_Data, "m_iszCapPointName", cpTarget, sizeof(cpTarget));

		for (int i = 0; i < g_iNCP; i++) {
			if (strcmp(cpTarget, ga_sCPname[i]) == 0) {
				ga_iCPCZent[i] = ent;
				break;
			}
		}
	}
}

public void ObjEvents_NoCopy(Event event, char[] name, bool dontBroadcast) {
	g_iBlockedCpTimes = 0;
	g_iDisabledCZ = 0;
	g_iBlockcountdown = 0;
	RequestFrame(Frame_SetActivePointAndHook);
}

void Frame_SetActivePointAndHook(any data) { SetActivePointAndHook(); }

void SetActivePointAndHook() {
	int acp = ObjectiveResource_GetProp("m_nActivePushPointIndex");

	int target = -1;
	if (acp >= 0 && acp < g_iNCP) {
		target = acp;
	} else {
		for (int i = 0; i < g_iNCP; i++)
			if (IsValidCZIndex(i)) { target = i; break; }
	}

	if (target == -1) {
		PrintToServer("[cp_norush] No valid CZ index found (NCP=%d).", g_iNCP);
		return;
	}

	if (InCounterAttack() && acp >= 0) {
		int next = acp + 1;
		if (IsValidCZIndex(next)) target = next;
	}

	if (!IsValidCZIndex(target)) return;

	int ent = ga_iCPCZent[target];
	if (g_iHookedCZ == ent && g_iActivePoint == target) return;
	
	UnhookCZ();
	g_iHookedCZ = ent;
	g_iActivePoint = target;
	SDKHook(ent, SDKHook_StartTouch, Hook_StartTouchCZ);
}

bool ToggleObjective(int ent, bool enable, bool announce = true) {
	char input[8];

	if (!enable) {
		strcopy(input, sizeof input, "Disable");
	} else {
		strcopy(input, sizeof input, "Enable");
	}

	if (!IsValidEntity(ent) || !AcceptEntityInput(ent, input)) {
		LogError("[cp_norush] Failed to %s capture zone entity %d.", input, ent);
		return false;
	}

	if (!enable) {
		g_iDisabledCZ = ent;
	} else {
		if (g_iDisabledCZ == ent) g_iDisabledCZ = 0;
		if (announce) PrintToChatAll("\x070088cc[BM]\x01 Control point enabled");
	}

	return true;
}

void RestoreDisabledObjective() {
	if (g_iDisabledCZ > 0) {
		int ent = g_iDisabledCZ;
		if (!IsValidEntity(ent)) {
			g_iDisabledCZ = 0;
		} else {
			ToggleObjective(ent, true, false);
		}
	}

	g_iBlockcountdown = 0;
}

public Action Hook_StartTouchCZ(int entity, int client) {
	if (client > 0 && client <= MaxClients && !IsFakeClient(client)) {
		if (g_iAntiRushTimer != entity) {
			g_iAntiRushTimer = entity;
			CreateTimer(1.0, Timer_AntiCpRush, EntIndexToEntRef(entity), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			g_iAliveSecPlayers = Team_CountAlivePlayers(TEAM_SECURITY, true);
		}
	}
	return Plugin_Continue;
}

Action Timer_AntiCpRush(Handle timer, int entref) {
	int ent = EntRefToEntIndex(entref);
	if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent) || ent != g_iHookedCZ || ent != g_iAntiRushTimer) return Plugin_Stop;

	if (g_iBlockcountdown) {
		g_iBlockcountdown--;
		if (!g_iBlockcountdown && !ToggleObjective(ent, true)) g_iBlockcountdown = 1;
		return Plugin_Continue;
	}

	static int iCpMsgcooldowntime = 0;
	if (iCpMsgcooldowntime > 0)
		iCpMsgcooldowntime--;

	float fCapPercent = ObjectiveResource_GetPropFloat("m_flLazyCapPerc", 4, g_iActivePoint);

	if (g_iRushBlockTime && g_iBlockedCpTimes < 5 && fCapPercent >= 0.75 && fCapPercent < 1.0) {
		int iPlayersOnCp = ObjectiveResource_GetProp("m_nInsurgentCount", 4, g_iActivePoint);
		int iNeedPlayers = RoundToFloor(g_fRushPercent * g_iAliveSecPlayers);

		if (iPlayersOnCp > 0 && iPlayersOnCp < iNeedPlayers && g_iAliveSecPlayers >= iNeedPlayers) {
			if (ToggleObjective(ent, false)) {
				PrintToChatAll("\x070088cc[BM]\x01 Control point locked for \x070088cc%d\x01s due to low player cap  (\x070088cc%d\x01/\x070088cc%d\x01)",
							g_iRushBlockTime, iPlayersOnCp, iNeedPlayers);
				g_iBlockedCpTimes++;
				g_iBlockcountdown = g_iRushBlockTime;
				return Plugin_Continue;
			}
		}
	}

	if (!iCpMsgcooldowntime && fCapPercent > 0.02 && fCapPercent < 1.0) {
		int iCapPercent  = RoundFloat(fCapPercent * 100.0);
		int iNeedPlayers = RoundToFloor(g_fRushPercent * g_iAliveSecPlayers);

		if (iNeedPlayers && g_iRushBlockTime) {
			int iPlayersOnCp = ObjectiveResource_GetProp("m_nInsurgentCount", 4, g_iActivePoint);
			PrintToChatAll("\x070088cc[BM]\x01 Capture progress at \x070088cc%d\x01%% (\x070088cc%d\x01/\x070088cc%d\x01)",
						iCapPercent, iPlayersOnCp, iNeedPlayers);
		}
		else PrintToChatAll("\x070088cc[BM]\x01 Capture progress at \x070088cc%d\x01%%", iCapPercent);

		iCpMsgcooldowntime = 10;
	}

	return Plugin_Continue;
}

bool ObjectiveResource_GetPropVector(const char[] prop, float vec[3], int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1) {
			GetEntDataVector(g_iObjResEntity, offs + (12 * element), vec);
			return true;
		}
	}
	return false;
}

int OR_Cache(bool force = false) {
	if (force || g_iObjResEntity < 1 || !IsValidEntity(g_iObjResEntity)) {
		g_iObjResEntity = FindEntityByClassname(-1, "ins_objective_resource");
		if (g_iObjResEntity > 0) GetEntityNetClass(g_iObjResEntity, g_sObjResNetClass, sizeof g_sObjResNetClass);
		else g_sObjResNetClass[0] = '\0';
	} else {
		char cls[32];
		GetEntityClassname(g_iObjResEntity, cls, sizeof cls);
		if (strcmp(cls, "ins_objective_resource") != 0) return OR_Cache(true);
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

float ObjectiveResource_GetPropFloat(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1) return GetEntDataFloat(g_iObjResEntity, offs + (size * element));
	}
	return -1.0;
}

int Team_CountAlivePlayers(int team, bool ignorebots) {
	int count = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || GetClientTeam(i) != team || !IsPlayerAlive(i) || ignorebots && IsFakeClient(i)) continue;
		count++;
	}
	return count;
}

bool InCounterAttack() { return view_as<bool>(GameRules_GetProp("m_bCounterAttack")); }

bool IsValidCZIndex(int idx) {
	return (0 <= idx && idx < g_iNCP && ga_iCPCZent[idx] > 0 && IsValidEntity(ga_iCPCZent[idx]));
}

void UnhookCZ() {
	RestoreDisabledObjective();

	if (g_iHookedCZ > 0) {
		SDKUnhook(g_iHookedCZ, SDKHook_StartTouch, Hook_StartTouchCZ);
		g_iHookedCZ = 0;
	}
	g_iAntiRushTimer = 0;
}

public void OnMapEnd() { UnhookCZ(); }

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvRushBlockTime) g_iRushBlockTime = g_cvRushBlockTime.IntValue;
	else if (convar == g_cvRushPercent) g_fRushPercent = g_cvRushPercent.FloatValue;
}

public void OnPluginEnd() {
	RestoreDisabledObjective();
}
