#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PL_VERSION "1.1"

char g_LogFilePath[PLATFORM_MAX_PATH];
char g_sPluginName[PLATFORM_MAX_PATH];
char g_sMap[64];

ArrayList g_hSpawns;

int g_iNextIndex[MAXPLAYERS + 1] = {-1, ...};
int g_iPrevIndex[MAXPLAYERS + 1] = {-1, ...};

ConVar g_cvScanDelay;
ConVar g_cvClassnameScan;

public Plugin myinfo =
{
	name        = "spawnreport",
	author      = "Nullifidian",
	description = "Dump all ins_spawnpoint to file and let admins hop between them",
	version     = PL_VERSION,
	url         = ""
};

public void OnPluginStart() {
	g_hSpawns = new ArrayList(4);

	GetPluginFilename(INVALID_HANDLE, g_sPluginName, sizeof g_sPluginName);
	ReplaceString(g_sPluginName, sizeof g_sPluginName, ".smx", "", false);

	RegAdminCmd("sm_gotospawn", Cmd_GoToSpawn, ADMFLAG_RCON, "Usage: sm_gotospawn [prev|next|<index>|sec|ins] — teleport to spawn points (wraps).");
	RegAdminCmd("sm_dump_spawns", Cmd_DumpSpawns, ADMFLAG_RCON, "Re-scan and write spawns to file.");

	g_cvScanDelay = CreateConVar("sr_scan_delay", "1.0", "Delay (s) before scanning spawns on map start.", FCVAR_NONE, true, 0.0);
	g_cvClassnameScan = CreateConVar("sr_classname", "ins_spawnpoint", "Classname to scan.", FCVAR_NONE);

	AutoExecConfig(true, g_sPluginName);
}

public void OnPluginEnd() {
	if (g_hSpawns != null) {
		delete g_hSpawns;
		g_hSpawns = null;
	}
}

public void OnClientPostAdminCheck(int client) {
	g_iNextIndex[client] = -1;
	g_iPrevIndex[client] = -1;
}

public void OnClientDisconnect(int client) {
	g_iNextIndex[client] = -1;
	g_iPrevIndex[client] = -1;
}

public void OnMapStart() {
	g_hSpawns.Clear();

	GetCurrentMap(g_sMap, sizeof g_sMap);

	char dirPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, dirPath, sizeof dirPath, "logs/%s", g_sPluginName);
	CreateDirectory(dirPath, 0777);

	BuildPath(Path_SM, g_LogFilePath, sizeof g_LogFilePath, "logs/%s/%s.log", g_sPluginName, g_sMap);
	if (FileExists(g_LogFilePath, false)) DeleteFile(g_LogFilePath);

	float delay = g_cvScanDelay.FloatValue;
	CreateTimer(delay, Timer_DumpAllSpawns, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Cmd_DumpSpawns(int client, int args) {
	DumpAllSpawnsToFile(true);
	ReplyToCommand(client, "[spawnreport] Re-scanned spawns and rewrote log.");
	return Plugin_Handled;
}

public Action Cmd_GoToSpawn(int client, int args) {
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client) || g_hSpawns.Length == 0)
		return Plugin_Handled;

	int targetIndex = g_iNextIndex[client];

	char arg[32];
	bool hasArg = (args >= 1);
	if (hasArg) GetCmdArg(1, arg, sizeof arg);

	int desiredTeam = -1;
	if (hasArg) {
		if (StrEqual(arg, "sec", false)) desiredTeam = 2;
		else if (StrEqual(arg, "ins", false)) desiredTeam = 3;
	}

	if (hasArg && IsCharNumeric(arg[0])) {
		int idx = StringToInt(arg);
		if (idx < 0) idx = 0;
		if (idx >= g_hSpawns.Length) idx = g_hSpawns.Length - 1;
		targetIndex = idx;
	}
	else if (hasArg && StrEqual(arg, "prev", false)) {
		if (targetIndex <= 0) targetIndex = g_hSpawns.Length - 1;
		else targetIndex--;
	}
	else {
		if (targetIndex < 0) targetIndex = 0;
		else targetIndex = (targetIndex + 1) % g_hSpawns.Length;
	}

	if (desiredTeam != -1 && g_hSpawns.Length > 0) {
		int start = targetIndex;
		for (int i = 0; i < g_hSpawns.Length; i++) {
			int idx = (start + i) % g_hSpawns.Length;
			int team = view_as<int>(g_hSpawns.Get(idx, 3));
			if (team == desiredTeam) {
				targetIndex = idx;
				break;
			}
		}
	}

	float vOrigin[3];
	vOrigin[0] = view_as<float>(g_hSpawns.Get(targetIndex, 0));
	vOrigin[1] = view_as<float>(g_hSpawns.Get(targetIndex, 1));
	vOrigin[2] = view_as<float>(g_hSpawns.Get(targetIndex, 2));
	int team = view_as<int>(g_hSpawns.Get(targetIndex, 3));

	g_iNextIndex[client] = targetIndex;
	g_iPrevIndex[client] = targetIndex;

	ReplyToCommand(client, "SPAWN[%d/%d] TEAM[%d]: %.2f, %.2f, %.2f",
		targetIndex, g_hSpawns.Length - 1, team, vOrigin[0], vOrigin[1], vOrigin[2]);

	TeleportEntity(client, vOrigin, NULL_VECTOR, NULL_VECTOR);
	return Plugin_Handled;
}

public Action Timer_DumpAllSpawns(Handle timer) {
	DumpAllSpawnsToFile(false);
	return Plugin_Stop;
}

static void DumpAllSpawnsToFile(bool quiet) {
	g_hSpawns.Clear();

	char classname[64];
	g_cvClassnameScan.GetString(classname, sizeof classname);

	int ent = -1;
	int count = 0;

	while ((ent = FindEntityByClassname(ent, classname)) != -1) {
		float org[3];
		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", org);

		int team = -1;
		if (HasEntProp(ent, Prop_Send, "m_iTeamNum"))
			team = GetEntProp(ent, Prop_Send, "m_iTeamNum");
		else if (HasEntProp(ent, Prop_Data, "m_iTeamNum"))
			team = GetEntProp(ent, Prop_Data, "m_iTeamNum");

		g_hSpawns.Push(0);
		int row = g_hSpawns.Length - 1;

		g_hSpawns.Set(row, org[0], 0);
		g_hSpawns.Set(row, org[1], 1);
		g_hSpawns.Set(row, org[2], 2);
		g_hSpawns.Set(row, team, 3);

		LogToFile(g_LogFilePath, "SPAWN[%d] TEAM[%d]: %f, %f, %f", count, team, org[0], org[1], org[2]);
		count++;
	}

	if (!quiet) PrintToServer("[spawnreport] Wrote %d spawns to: %s", count, g_LogFilePath);
}
