#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION			"1.0.4"

#define TEAM_SECURITY			2
#define DAMAGE_YES				2

#define CHECK_DELAY_FIRST		0.75

char	g_sLogDir[PLATFORM_MAX_PATH];
bool	g_bKilledForBadModel[MAXPLAYERS + 1];
char	g_sLastGoodSecurityModel[PLATFORM_MAX_PATH];

public Plugin myinfo = {
	name = "[INS] Error Model Guard",
	author = "ChatGPT",
	description = "Kills human Security players who spawn with broken/error player models.",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart() {
	BuildPath(Path_SM, g_sLogDir, sizeof(g_sLogDir), "logs/error_model_guard");

	if (!DirExists(g_sLogDir))
		CreateDirectory(g_sLogDir, 448);

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	RegAdminCmd("sm_emscan", Cmd_Scan, ADMFLAG_BAN, "Scan alive human Security players for broken/error models.");
	RegAdminCmd("sm_emmodel", Cmd_Model, ADMFLAG_BAN, "Print target player model path.");
}

public void OnClientDisconnect(int client) {
	g_bKilledForBadModel[client] = false;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client > 0)
		g_bKilledForBadModel[client] = false;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsHumanClient(client))
		return;

	g_bKilledForBadModel[client] = false;

	CreateTimer(CHECK_DELAY_FIRST, Timer_CheckPlayer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CheckPlayer(Handle timer, any userid) {
	int client = GetClientOfUserId(userid);

	if (!IsSecurityHumanAlive(client))
		return Plugin_Stop;

	CheckPlayerModel(client, true);
	return Plugin_Stop;
}

public Action Cmd_Scan(int client, int args) {
	int bad;

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsSecurityHumanAlive(i))
			continue;

		if (!CheckPlayerModel(i, true))
			bad++;
	}

	ReplyToCommand(client, "[ErrorModelGuard] Scan complete. Bad players found: %d", bad);
	return Plugin_Handled;
}

public Action Cmd_Model(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "Usage: sm_emmodel <target>");
		return Plugin_Handled;
	}

	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));

	int targets[MAXPLAYERS];
	char targetName[MAX_TARGET_LENGTH];
	bool tn_is_ml;

	int count = ProcessTargetString(arg, client, targets, sizeof(targets), COMMAND_FILTER_CONNECTED, targetName, sizeof(targetName), tn_is_ml);

	if (count <= 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	for (int i = 0; i < count; i++) {
		int target = targets[i];

		char clientModel[PLATFORM_MAX_PATH];
		char entityModel[PLATFORM_MAX_PATH];
		char clientReason[128];
		char entityReason[128];

		GetClientModel(target, clientModel, sizeof(clientModel));
		GetEntityModelName(target, entityModel, sizeof(entityModel));
		GetModelFailureReason(clientModel, clientReason, sizeof(clientReason));
		GetModelFailureReason(entityModel, entityReason, sizeof(entityReason));

		int modelIndex = GetEntityModelIndex(target);

		ReplyToCommand(client, "[ErrorModelGuard] %N client_model=\"%s\" entity_model=\"%s\" model_index=%d client_reason=\"%s\" entity_reason=\"%s\"",
			target,
			clientModel,
			entityModel,
			modelIndex,
			clientReason,
			entityReason);
	}

	return Plugin_Handled;
}

bool CheckPlayerModel(int client, bool fix) {
	if (!IsSecurityHumanAlive(client))
		return true;

	char model[PLATFORM_MAX_PATH];
	char entityModel[PLATFORM_MAX_PATH];
	char badModel[PLATFORM_MAX_PATH];
	char goodModel[PLATFORM_MAX_PATH];
	char reason[128];

	GetClientModel(client, model, sizeof(model));
	GetEntityModelName(client, entityModel, sizeof(entityModel));

	if (!IsBadPlayerModel(model, entityModel, badModel, sizeof(badModel), goodModel, sizeof(goodModel), reason, sizeof(reason))) {
		strcopy(g_sLastGoodSecurityModel, sizeof(g_sLastGoodSecurityModel), goodModel);
		return true;
	}

	LogBadModelEvent(client, "BAD_MODEL_DETECTED", model, entityModel, reason);

	if (!fix)
		return false;

	if (g_bKilledForBadModel[client])
		return false;

	g_bKilledForBadModel[client] = true;

	// Only touch m_takedamage after the player is confirmed bugged.
	SetEntProp(client, Prop_Data, "m_takedamage", DAMAGE_YES);

	ForcePlayerSuicide(client);

	PrintToChatAll("\x070088cc[BM]\x01 %N spawned with a broken player model and was killed.", client);
	LogBadModelEvent(client, "BAD_MODEL_KILLED", badModel, entityModel, reason);

	return false;
}

void EMG_Log(const char[] format, any ...) {
	char date[16];
	FormatTime(date, sizeof(date), "%Y-%m-%d", GetTime());

	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof(path), "%s/%s.log", g_sLogDir, date);

	char buffer[1024];
	VFormat(buffer, sizeof(buffer), format, 2);

	LogToFileEx(path, "[ErrorModelGuard] %s", buffer);
}

void LogBadModelEvent(int client, const char[] action, const char[] model, const char[] entityModel, const char[] reason) {
	char steam2[32];
	char steam64[32];
	char ip[64];

	GetClientIdentity(client, steam2, sizeof(steam2), steam64, sizeof(steam64), ip, sizeof(ip));

	EMG_Log("%s | name=\"%N\" | userid=%d | steam2=\"%s\" | steam64=\"%s\" | ip=\"%s\" | model=\"%s\" | entity_model=\"%s\" | reason=\"%s\" | last_good_security_model=\"%s\"",
		action,
		client,
		GetClientUserId(client),
		steam2,
		steam64,
		ip,
		model,
		entityModel,
		reason,
		g_sLastGoodSecurityModel);
}

void GetClientIdentity(int client, char[] steam2, int steam2Len, char[] steam64, int steam64Len, char[] ip, int ipLen) {
	strcopy(steam2, steam2Len, "UNKNOWN");
	strcopy(steam64, steam64Len, "UNKNOWN");
	strcopy(ip, ipLen, "UNKNOWN");

	if (!IsClientInGame(client))
		return;

	GetClientIP(client, ip, ipLen, true);

	if (!GetClientAuthId(client, AuthId_Steam2, steam2, steam2Len, true))
		strcopy(steam2, steam2Len, "UNKNOWN");

	if (!GetClientAuthId(client, AuthId_SteamID64, steam64, steam64Len, true))
		strcopy(steam64, steam64Len, "UNKNOWN");
}

bool IsBadPlayerModel(const char[] clientModel, const char[] entityModel, char[] badModel, int badLen, char[] goodModel, int goodLen, char[] reason, int reasonLen) {
	if (IsExplicitErrorModel(clientModel)) {
		strcopy(badModel, badLen, clientModel);
		strcopy(reason, reasonLen, "client_model_is_error");
		return true;
	}

	if (IsExplicitErrorModel(entityModel)) {
		strcopy(badModel, badLen, entityModel);
		strcopy(reason, reasonLen, "entity_model_is_error");
		return true;
	}

	if (IsUsablePlayerModel(clientModel)) {
		strcopy(goodModel, goodLen, clientModel);
		return false;
	}

	if (IsUsablePlayerModel(entityModel)) {
		strcopy(goodModel, goodLen, entityModel);
		return false;
	}

	if (clientModel[0] != '\0')
		strcopy(badModel, badLen, clientModel);
	else
		strcopy(badModel, badLen, entityModel);

	GetModelFailureReason(badModel, reason, reasonLen);
	return true;
}

bool IsUsablePlayerModel(const char[] model) {
	if (model[0] == '\0')
		return false;

	if (!HasMdlExtension(model))
		return false;

	if (IsExplicitErrorModel(model))
		return false;

	if (!FileExists(model, true))
		return false;

	if (!IsModelPrecached(model))
		return false;

	return true;
}

bool IsExplicitErrorModel(const char[] model) {
	if (model[0] == '\0')
		return false;

	return StrContains(model, "error.mdl", false) != -1;
}

void GetModelFailureReason(const char[] model, char[] reason, int reasonLen) {
	if (model[0] == '\0') {
		strcopy(reason, reasonLen, "empty_model");
		return;
	}

	if (!HasMdlExtension(model)) {
		strcopy(reason, reasonLen, "not_mdl_path");
		return;
	}

	if (IsExplicitErrorModel(model)) {
		strcopy(reason, reasonLen, "explicit_error_model");
		return;
	}

	if (!FileExists(model, true)) {
		strcopy(reason, reasonLen, "model_file_missing");
		return;
	}

	if (!IsModelPrecached(model)) {
		strcopy(reason, reasonLen, "model_not_precached");
		return;
	}

	strcopy(reason, reasonLen, "unknown");
}

void GetEntityModelName(int client, char[] model, int maxlen) {
	model[0] = '\0';

	if (HasEntProp(client, Prop_Data, "m_ModelName"))
		GetEntPropString(client, Prop_Data, "m_ModelName", model, maxlen);
}

int GetEntityModelIndex(int client) {
	if (!HasEntProp(client, Prop_Data, "m_nModelIndex"))
		return -1;

	return GetEntProp(client, Prop_Data, "m_nModelIndex", 2);
}

bool HasMdlExtension(const char[] model) {
	int len = strlen(model);

	if (len < 5)
		return false;

	if (model[len - 4] != '.')
		return false;

	if (model[len - 3] != 'm' && model[len - 3] != 'M')
		return false;

	if (model[len - 2] != 'd' && model[len - 2] != 'D')
		return false;

	if (model[len - 1] != 'l' && model[len - 1] != 'L')
		return false;

	return true;
}

bool IsSecurityHumanAlive(int client) {
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& IsPlayerAlive(client)
		&& GetClientTeam(client) == TEAM_SECURITY;
}

bool IsHumanClient(int client) {
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& !IsFakeClient(client);
}
