#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

bool	g_bLateLoad;

char	ga_sBlackList[][] = {
		".com",
		".de",
		".net",
		".cn",
		".uk",
		".org",
		".nl",
		".eu",
		".ru",
		".aero",
		".asia",
		".biz",
		".cat",
		".coop",
		".edu",
		".info",
		".int",
		".jobs",
		".mobi",
		".museum",
		".name",
		".pro",
		".tel",
		".travel",
		".co",
		".tv",
		".fm",
		".ly",
		".ws",
		".me",
		".cc",
		"www.",
		"keydrop"
};

public Plugin myinfo = {
	name		= "nickblacklist",
	author		= "Nullifidian",
	description	= "Removes blacklisted words from player's nick",
	version		= "1.0",
	url			= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	HookEvent("player_changename", Event_ChangeName, EventHookMode_Pre);
	
	if (g_bLateLoad) {
		char sName[32];
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || IsFakeClient(i)) {
				continue;
			}
			if (GetClientName(i, sName, sizeof(sName))) {
				FindAndRemove(i, sName);
			}
		}
	}
}

public void OnClientPutInServer(int client) {
	if (!IsFakeClient(client)) {
		char sName[32];
		if (GetClientName(client, sName, sizeof(sName))) {
			FindAndRemove(client, sName);
		}

	}
}

public Action Event_ChangeName(Event event, char[] name, bool dontBroadcast) {
	int	client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsClientInGame(client) || IsFakeClient(client)) {
		return Plugin_Continue;
	}

	char sNew[32];
	event.GetString("newname", sNew, sizeof(sNew));

	if (FindAndRemove(client, sNew)) {
		//event.SetString("newname", sNew);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

bool FindAndRemove(int client, char sName[32]) {
	bool bRemoved = false;
	
	for (int i=0; i<sizeof(ga_sBlackList); i++) {
		if (ReplaceString(sName, sizeof(sName), ga_sBlackList[i], "", false)) {
			bRemoved = true;
		}
	}

	if (bRemoved) {
		if (strlen(sName) < 1) {
			char sBuffer[32];
			FormatEx(sBuffer, sizeof(sBuffer), "Player %d", client);
			sName = sBuffer;
		}
		SetClientName(client, sName);
		return true;
	}
	return false;
}