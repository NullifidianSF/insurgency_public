#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#define TEAM_SECURITY 2

#define MAXENTITIES 2048

#define MAX_CONTROLPOINTS 20
float ga_fCPpos[MAX_CONTROLPOINTS][3];
char ga_sCPname[MAX_CONTROLPOINTS][64];
int ga_iCPCZent[MAX_CONTROLPOINTS];

static int  g_iObjResEntity = -1;
static char g_sObjResNetClass[32];

int g_iNCP;
int g_iHookedCZ = 0;
int g_iActivePoint = 0;

float g_fRushPercent;
bool g_bCapturePaused;
bool g_bIsLateLoad;

ConVar g_cvRushPercent;

GameData g_hGameData = null;
DynamicDetour g_hAdjustCaptureSpeedDetour = null;

public Plugin myinfo = {
	name = "cp_norush",
	author = "Nullifidian",
	description = "Pause CP capture progress when too few players are capturing",
	version = "2.5",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bIsLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	g_cvRushPercent = CreateConVar("sm_rushpercent", "0.5",
		"Percent (rounded down) of alive players needed on a CP to continue capturing",
		_, true, 0.0, true, 1.0);
	g_fRushPercent = g_cvRushPercent.FloatValue;
	g_cvRushPercent.AddChangeHook(OnConVarChanged);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("object_destroyed", ObjEvents_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", ObjEvents_NoCopy, EventHookMode_PostNoCopy);

	InitialiseAdjustCaptureSpeedDetour();

	char cfgName[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, cfgName, sizeof cfgName);
	ReplaceString(cfgName, sizeof cfgName, ".smx", "", false);
	AutoExecConfig(true, cfgName);
}

public void OnMapStart() {
	g_iHookedCZ = 0;
	g_iActivePoint = 0;
	g_bCapturePaused = false;
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
	g_bCapturePaused = false;
	UnhookCZ();
	RequestFrame(Frame_SetActivePointAndHook);
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, char[] name, bool dontBroadcast) {
	g_bCapturePaused = false;
	UnhookCZ();
	return Plugin_Continue;
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
	g_bCapturePaused = false;
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

bool InCounterAttack() { return view_as<bool>(GameRules_GetProp("m_bCounterAttack")); }

bool IsValidCZIndex(int idx) {
	return (0 <= idx && idx < g_iNCP && ga_iCPCZent[idx] > 0 && IsValidEntity(ga_iCPCZent[idx]));
}

void UnhookCZ() {
	g_iHookedCZ = 0;
	g_bCapturePaused = false;
}

public void OnMapEnd() { UnhookCZ(); }

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvRushPercent) g_fRushPercent = g_cvRushPercent.FloatValue;
}

public void OnPluginEnd() {
	if (g_hAdjustCaptureSpeedDetour != null)
		g_hAdjustCaptureSpeedDetour.Disable(Hook_Pre, Detour_AdjustCaptureSpeed_Pre);

	delete g_hAdjustCaptureSpeedDetour;
	delete g_hGameData;
}

void InitialiseAdjustCaptureSpeedDetour() {
	if (GetFeatureStatus(FeatureType_Native, "DynamicDetour.DynamicDetour") != FeatureStatus_Available
		|| GetFeatureStatus(FeatureType_Native, "DHookSetup.SetFromConf") != FeatureStatus_Available
		|| GetFeatureStatus(FeatureType_Native, "DHookSetup.AddParam") != FeatureStatus_Available)
		SetFailState("[cp_norush] DHooks with DynamicDetour support is required.");

	g_hGameData = LoadGameConfigFile("insurgency-bm.games");
	if (g_hGameData == null)
		SetFailState("[cp_norush] Missing gamedata: addons/sourcemod/gamedata/insurgency-bm.games.txt");

	g_hAdjustCaptureSpeedDetour = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Float, ThisPointer_Address);
	if (g_hAdjustCaptureSpeedDetour == null)
		SetFailState("[cp_norush] Could not create the CINSRules_Checkpoint::AdjustCaptureSpeed detour.");

	g_hAdjustCaptureSpeedDetour.AddParam(HookParamType_ObjectPtr);
	g_hAdjustCaptureSpeedDetour.AddParam(HookParamType_Int);
	g_hAdjustCaptureSpeedDetour.AddParam(HookParamType_Int);
	g_hAdjustCaptureSpeedDetour.AddParam(HookParamType_Int);
	g_hAdjustCaptureSpeedDetour.AddParam(HookParamType_Int);

	if (!g_hAdjustCaptureSpeedDetour.SetFromConf(g_hGameData, SDKConf_Signature, "CINSRules_Checkpoint::AdjustCaptureSpeed")
		|| !g_hAdjustCaptureSpeedDetour.Enable(Hook_Pre, Detour_AdjustCaptureSpeed_Pre))
		SetFailState("[cp_norush] Could not enable the CINSRules_Checkpoint::AdjustCaptureSpeed detour.");
}

public MRESReturn Detour_AdjustCaptureSpeed_Pre(Address pThis, DHookReturn hReturn, DHookParam hParams) {
	if (g_iHookedCZ <= MaxClients || !IsValidEntity(g_iHookedCZ))
		return MRES_Ignored;

	Address zoneAddress = hParams.GetAddress(1);
	Address hookedZoneAddress = GetEntityAddress(g_iHookedCZ);
	if (zoneAddress == Address_Null || zoneAddress != hookedZoneAddress)
		return MRES_Ignored;

	int team = hParams.Get(2);
	if (team != TEAM_SECURITY)
		return MRES_Ignored;

	float capturePercent = ObjectiveResource_GetPropFloat("m_flLazyCapPerc", 4, g_iActivePoint);
	if (capturePercent < 0.75 || capturePercent >= 1.0) {
		g_bCapturePaused = false;
		return MRES_Ignored;
	}

	int playersOnPoint = ObjectiveResource_GetProp("m_nInsurgentCount", 4, g_iActivePoint);
	int alivePlayers = CountAliveSecurityPlayers();
	int requiredPlayers = RoundToFloor(g_fRushPercent * alivePlayers);
	if (playersOnPoint <= 0 || playersOnPoint >= requiredPlayers || alivePlayers < requiredPlayers) {
		g_bCapturePaused = false;
		return MRES_Ignored;
	}

	if (!g_bCapturePaused) {
		PrintToChatAll("\x070088cc[BM]\x01 Capture paused due to low player cap (\x070088cc%d\x01/\x070088cc%d\x01)",
			playersOnPoint, requiredPlayers);
		g_bCapturePaused = true;
	}
	hReturn.Value = 0.0;
	return MRES_Supercede;
}

int CountAliveSecurityPlayers() {
	int count = 0;
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SECURITY)
			count++;

	return count;
}
