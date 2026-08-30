// required https://steamcommunity.com/sharedfiles/filedetails/?id=2794417302

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>

Handle	g_hClientCookie = INVALID_HANDLE;

ConVar	g_cvThirdPerson = null;

int		ga_iSetting[MAXPLAYERS + 1] = {0, ...},
		ga_iFpsAds[MAXPLAYERS + 1] = {0, ...};

bool	g_bLateLoad;

public Plugin myinfo = {
	name		= "thirdperson",
	author		= "Nullifidian",
	description	= "third person view command",
	version		= "2.0.2",
	url			= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	if (!(g_cvThirdPerson = FindConVar("sv_thirdperson"))) {
		SetFailState("Fatal Error: Unable to FindConVar \"sv_thirdperson\" !");
	}

	g_hClientCookie = RegClientCookie("TpCookie", "third person view cookie", CookieAccess_Private);
	LoadTranslations("common.phrases");

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("weapon_ironsight", Event_WeaponIronsight, EventHookMode_Pre);
	HookEvent("weapon_lower_sight", Event_WeaponLowerSight, EventHookMode_Pre);
	HookEvent("weapon_deploy", Event_WeaponDeploy, EventHookMode_Post);
	
	RegConsoleCmd("fp", cmd_firstPerson, "Set your view to first person");
	RegConsoleCmd("tp", cmd_thirdPerson, "Set your view to third person");
	RegAdminCmd("sm_tpinfo", Command_TpInfo, ADMFLAG_BAN, "Show a player's third-person settings");

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || IsFakeClient(i) || !AreClientCookiesCached(i)) {
				continue;
			}
			OnClientCookiesCached(i);
			if (IsPlayerAlive(i)) {
				RestoreThirdPerson(i);
			}
		}
	}
}

public void OnClientCookiesCached(int client) {
	if (IsClientConnected(client) && !IsFakeClient(client)) {
		char 	sValue[4],
				sArray[2][2];
		GetClientCookie(client, g_hClientCookie, sValue, sizeof(sValue));
		ExplodeString(sValue, ";", sArray, sizeof(sArray), sizeof(sArray[]));
		ga_iSetting[client] = StringToInt(sArray[0]);
		ga_iFpsAds[client] = StringToInt(sArray[1]);
	}
}

public void OnClientDisconnect(int client) {
	if (client && !IsFakeClient(client)) {
		char sBuffer[4];
		FormatEx(sBuffer, sizeof(sBuffer), "%d;%d", ga_iSetting[client], ga_iFpsAds[client]);
		SetClientCookie(client, g_hClientCookie, sBuffer);
		ga_iSetting[client] = 0;
		ga_iFpsAds[client] = 0;
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	PrintToChatAll("\x070088cc[!tp]\x01 Type \x07ffff00!tp \x01to switch to third-person.");
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client) || ga_iSetting[client] == 0) {
		return Plugin_Continue;
	}
	RestoreThirdPerson(client);
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || IsFakeClient(client) || ga_iSetting[client] == 0) {
		return Plugin_Continue;
	}
	ClientCommand(client, "r_screenoverlay null");
	SendConVarValue(client, g_cvThirdPerson, "0");
	return Plugin_Continue;
}

public Action cmd_thirdPerson(int client, int args) {
	if (client < 1 || !IsClientInGame(client)) {
		return Plugin_Handled;
	}

	if (GetClientTeam(client) < 2) {
		ReplyToCommand(client, "You must join a team first!");
		return Plugin_Handled;
	}

	TpMenuSetup(client);
	return Plugin_Handled;
}

public Action cmd_firstPerson(int client, int args) {
	if (client < 1 || !IsClientInGame(client)) {
		return Plugin_Handled;
	}

	if (GetClientTeam(client) < 2) {
		ReplyToCommand(client, "You must join a team first!");
		return Plugin_Handled;
	}

	ClientCommand(client, "r_screenoverlay null");
	SendConVarValue(client, g_cvThirdPerson, "0");
	ReplyToCommand(client, "TP off");
	ga_iSetting[client] = 0;
	
	return Plugin_Handled;
}

public Action Command_TpInfo(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "Usage: sm_tpinfo <target>");
		return Plugin_Handled;
	}

	char sTargetArg[MAX_TARGET_LENGTH];
	GetCmdArg(1, sTargetArg, sizeof(sTargetArg));

	int targets[MAXPLAYERS];
	char sTargetName[MAX_TARGET_LENGTH];
	bool tnIsMl;
	int targetCount = ProcessTargetString(sTargetArg, client, targets, sizeof(targets), COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_BOTS, sTargetName, sizeof(sTargetName), tnIsMl);
	if (targetCount <= 0) {
		ReplyToTargetError(client, targetCount);
		return Plugin_Handled;
	}

	for (int i = 0; i < targetCount; i++) {
		int target = targets[i];
		char sSetting[32];
		GetThirdPersonSettingName(ga_iSetting[target], sSetting, sizeof(sSetting));
		ReplyToCommand(client, "%N: TP %s | FP ADS %s", target, sSetting, ga_iFpsAds[target] ? "ON" : "OFF");
	}

	return Plugin_Handled;
}

void TpMenuSetup (int client) {
	Menu menu = new Menu(Handle_TpMenu);
	menu.SetTitle("Third Person Options");
	menu.AddItem("0", "TP off", (ga_iSetting[client] == 0) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.AddItem("1", "TP on (without crosshair)", (ga_iSetting[client] == 1) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	char sBuffer[16];
	FormatEx(sBuffer, sizeof(sBuffer), ga_iFpsAds[client] ? "FP ADS = ON" : "FP ADS = OFF");
	menu.AddItem("2", sBuffer);

	menu.AddItem("3", "TP + small red dot", (ga_iSetting[client] == 3) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.AddItem("4", "TP + medium red dot", (ga_iSetting[client] == 4) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.AddItem("5", "TP + large red dot", (ga_iSetting[client] == 5) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.AddItem("6", "TP + small blue dot", (ga_iSetting[client] == 6) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.AddItem("7", "TP + medium blue dot", (ga_iSetting[client] == 7) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.AddItem("8", "TP + large blue dot", (ga_iSetting[client] == 8) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	menu.Display(client, 15);
}

public int Handle_TpMenu(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			switch (param2) {
				case 0: {
					ClientCommand(param1, "r_screenoverlay null");
					SendConVarValue(param1, g_cvThirdPerson, "0");
					ReplyToCommand(param1, "TP off");
					ga_iSetting[param1] = param2;
				}
				case 1: {
					ClientCommand(param1, "r_screenoverlay null");
					SendConVarValue(param1, g_cvThirdPerson, "1");
					ReplyToCommand(param1, "TP on");
					ga_iSetting[param1] = param2;
				}
				case 2: {
					switch (ga_iFpsAds[param1]) {
						case 0: {
							ga_iFpsAds[param1] = 1;
							ReplyToCommand(param1, "Enabled FP ADS");
							TpMenuSetup(param1);
						}
						case 1: {
							ga_iFpsAds[param1] = 0;
							ReplyToCommand(param1, "Disabled FP ADS");
							TpMenuSetup(param1);
						}
					}
				}
				case 3: {
					ClientCommand(param1, "r_screenoverlay thirdperson/crosshair/dot/red_small.vtf");
					SendConVarValue(param1, g_cvThirdPerson, "1");
					ReplyToCommand(param1, "TP + small red dot");
					ga_iSetting[param1] = param2;
				}
				case 4: {
					ClientCommand(param1, "r_screenoverlay thirdperson/crosshair/dot/red_medium.vtf");
					SendConVarValue(param1, g_cvThirdPerson, "1");
					ReplyToCommand(param1, "TP + medium red dot");
					ga_iSetting[param1] = param2;
				}
				case 5: {
					ClientCommand(param1, "r_screenoverlay thirdperson/crosshair/dot/red_large.vtf");
					SendConVarValue(param1, g_cvThirdPerson, "1");
					ReplyToCommand(param1, "TP + large red dot");
					ga_iSetting[param1] = param2;
				}
				case 6: {
					ClientCommand(param1, "r_screenoverlay thirdperson/crosshair/dot/blue_small.vtf");
					SendConVarValue(param1, g_cvThirdPerson, "1");
					ReplyToCommand(param1, "TP + small blue dot");
					ga_iSetting[param1] = param2;
				}
				case 7: {
					ClientCommand(param1, "r_screenoverlay thirdperson/crosshair/dot/blue_medium.vtf");
					SendConVarValue(param1, g_cvThirdPerson, "1");
					ReplyToCommand(param1, "TP + medium blue dot");
					ga_iSetting[param1] = param2;
				}
				case 8: {
					ClientCommand(param1, "r_screenoverlay thirdperson/crosshair/dot/blue_large.vtf");
					SendConVarValue(param1, g_cvThirdPerson, "1");
					ReplyToCommand(param1, "TP + large blue dot");
					ga_iSetting[param1] = param2;
				}
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

public Action Event_WeaponIronsight(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client) || ga_iSetting[client] == 0 || !ga_iFpsAds[client]) {
		return Plugin_Continue;
	}
	ClientCommand(client, "r_screenoverlay null");
	SendConVarValue(client, g_cvThirdPerson, "0");
	return Plugin_Continue;
}

public Action Event_WeaponLowerSight(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client) || ga_iSetting[client] == 0 || !ga_iFpsAds[client]) {
		return Plugin_Continue;
	}
	RestoreThirdPerson(client);
	return Plugin_Continue;
}

public Action Event_WeaponDeploy(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client) || ga_iSetting[client] == 0 || !ga_iFpsAds[client]) {
		return Plugin_Continue;
	}

	RequestFrame(Frame_RestoreThirdPersonAfterWeaponDeploy, GetClientUserId(client));
	return Plugin_Continue;
}

void Frame_RestoreThirdPersonAfterWeaponDeploy(any data) {
	int client = GetClientOfUserId(data);
	if (!client || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client) || ga_iSetting[client] == 0 || !ga_iFpsAds[client]) {
		return;
	}

	RestoreThirdPerson(client);
}

void RestoreThirdPerson(int client) {
	SendConVarValue(client, g_cvThirdPerson, "1");
	switch (ga_iSetting[client]) {
		case 1: ClientCommand(client, "r_screenoverlay null");
		case 3: ClientCommand(client, "r_screenoverlay thirdperson/crosshair/dot/red_small.vtf");
		case 4: ClientCommand(client, "r_screenoverlay thirdperson/crosshair/dot/red_medium.vtf");
		case 5: ClientCommand(client, "r_screenoverlay thirdperson/crosshair/dot/red_large.vtf");
		case 6: ClientCommand(client, "r_screenoverlay thirdperson/crosshair/dot/blue_small.vtf");
		case 7: ClientCommand(client, "r_screenoverlay thirdperson/crosshair/dot/blue_medium.vtf");
		case 8: ClientCommand(client, "r_screenoverlay thirdperson/crosshair/dot/blue_large.vtf");
	}
}

void GetThirdPersonSettingName(int setting, char[] buffer, int maxlen) {
	switch (setting) {
		case 0: strcopy(buffer, maxlen, "OFF");
		case 1: strcopy(buffer, maxlen, "ON (no crosshair)");
		case 3: strcopy(buffer, maxlen, "small red dot");
		case 4: strcopy(buffer, maxlen, "medium red dot");
		case 5: strcopy(buffer, maxlen, "large red dot");
		case 6: strcopy(buffer, maxlen, "small blue dot");
		case 7: strcopy(buffer, maxlen, "medium blue dot");
		case 8: strcopy(buffer, maxlen, "large blue dot");
		default: strcopy(buffer, maxlen, "unknown");
	}
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || ga_iSetting[i] == 0) {
			continue;
		}
		ClientCommand(i, "r_screenoverlay null");
		SendConVarValue(i, g_cvThirdPerson, "0");
	}
}
