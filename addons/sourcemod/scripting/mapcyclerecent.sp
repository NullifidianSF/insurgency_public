/*
	Your mapcyclefile structure must be like this(mapSPACEgamemod): map gamemode
	Examples:	ministry_coop checkpoint
				anbar_coop checkpoint //blah blah random comment
				
	Plugin searchers for the map name match with the space after it so it won't remove maps with similar names like "ministry_coop_2013a".
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

ConVar		g_cvDefMapcycleFile = null;

int			ga_iCooldown[MAXPLAYERS + 1] = {0, ...};

char		g_sDefMapcycleFile[PLATFORM_MAX_PATH],
			g_sTempMapcycleFile[PLATFORM_MAX_PATH];

bool		g_bHooked = false;

ArrayList	ga_hExcludedMaps;

public Plugin myinfo = {
	name		= "mapcyclerecent",
	author		= "Nullifidian",
	description	= "Creates & sets the server to a new custom mapcyclefile without 5 last played maps.",
	version		= "1.1",
	url			= ""
};

public void OnPluginStart() {
	if (!(g_cvDefMapcycleFile = FindConVar("mapcyclefile"))) {
		SetFailState("Fatal Error [0]: Unable to FindConVar \"mapcyclefile\" !");
	}

	ga_hExcludedMaps = CreateArray(32);

	RegConsoleCmd("recentmaps", cmd_recentmaps, "Recently played maps that will be excluded from the map vote.");

	//because plugin reloads faster than "ServerCommand" in "OnPluginEnd"
	CreateTimer(0.1, Timer_Setup, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart() {
	char	sBuffer[32],
			sMap[32];
			
	GetCurrentMap(sMap, sizeof(sMap));
	FormatEx(sBuffer, sizeof(sBuffer), "%s ", sMap);

	if (GetArraySize(ga_hExcludedMaps) == 5) {
		RemoveFromArray(ga_hExcludedMaps, 0);
	}

	PushArrayString(ga_hExcludedMaps, sBuffer);

	CreateTimer(0.2, Timer_MakeTempMapcyle, _, TIMER_FLAG_NO_MAPCHANGE);
}

void MakeTempMapcyle() {
	int iArraySize = (GetArraySize(ga_hExcludedMaps) - 1);
	if (iArraySize < 0) {
		PrintToServer("Fatal Error [1]: array \"%s\" is empty!", ga_hExcludedMaps);
		SetFailState("Fatal Error [1]: array \"%s\" is empty!", ga_hExcludedMaps);
	}

	Handle hRead = OpenFile(g_sDefMapcycleFile, "rt", false);
	if (!hRead) {
		PrintToServer("Fatal Error [2]: can't open \"%s\" is empty!", g_sDefMapcycleFile);
		SetFailState("Fatal Error [2]: can't open \"%s\" is empty!", g_sDefMapcycleFile);
	}

	Handle hWrite = OpenFile(g_sTempMapcycleFile, "wt", false);
	if (!hWrite) {
		PrintToServer("Fatal Error [3]: can't open \"%s\" is empty!", g_sTempMapcycleFile);
		SetFailState("Fatal Error [3]: can't open \"%s\" is empty!", g_sTempMapcycleFile);
	}

	bool	bSkip = false;

	char	sBuffer[128],
			sArrayBuffer[32];

	int		iLines = 0;

	while (!IsEndOfFile(hRead)) {
		iLines++;
		ReadFileLine(hRead, sBuffer, sizeof(sBuffer));
		for (int i = 0; i <= iArraySize; i++) {
			GetArrayString(ga_hExcludedMaps, i, sArrayBuffer, sizeof(sArrayBuffer));
			if (StrContains(sBuffer, sArrayBuffer, false) > -1) {
				bSkip = true;
				break;
			}
		}
		if (bSkip) {
			bSkip = false;
			continue;
		}
		TrimString(sBuffer);
		WriteFileLine(hWrite, sBuffer);
	}

	if (iLines < 5) {
		PrintToServer("Fatal Error [4]: failed to make \"%s\" due to \"%s\" not having enough maps!", g_sTempMapcycleFile, g_sDefMapcycleFile);
		SetFailState("Fatal Error [4]: failed to make \"%s\" due to \"%s\" not having enough maps!", g_sTempMapcycleFile, g_sDefMapcycleFile);
	}

	delete hWrite;
	delete hRead;
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvDefMapcycleFile && strcmp(newValue, g_sTempMapcycleFile, false) != 0) {
		//strcopy(g_sDefMapcycleFile, sizeof(g_sDefMapcycleFile), g_sTempMapcycleFile);
		ServerCommand("mapcyclefile %s", g_sTempMapcycleFile);
	}
}

public Action cmd_recentmaps(int client, int args) {
	if (client > 0) {
		int iTime = GetTime();
		if (iTime < ga_iCooldown[client]) {
			ga_iCooldown[client] += 2;
			ReplyToCommand(client, "You must wait %d seconds before using this command again!", (ga_iCooldown[client] - iTime));
			return Plugin_Handled;
		}
		ga_iCooldown[client] = iTime + 3;
	}

	int		iArraySize = GetArraySize(ga_hExcludedMaps) - 1;

	char	sBuffer[200],
			sArrayBuffer[40];

	for (int i = 0; i <= iArraySize; i++) {
		GetArrayString(ga_hExcludedMaps, i, sArrayBuffer, sizeof(sArrayBuffer));
		if (iArraySize != i) {
			ReplaceString(sArrayBuffer, sizeof(sArrayBuffer), " ", " | ", false);
		}
		StrCat(sBuffer, sizeof(sBuffer), sArrayBuffer);
	}

	ReplyToCommand(client, "%s", sBuffer);

	return Plugin_Handled;
}

Action Timer_Setup(Handle timer) {
	GetConVarString(g_cvDefMapcycleFile, g_sDefMapcycleFile, sizeof(g_sDefMapcycleFile));
	char sBuffer[PLATFORM_MAX_PATH];
	
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	BuildPath(Path_SM, g_sTempMapcycleFile, sizeof(g_sTempMapcycleFile), "data/%s.txt", sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "%s", g_sDefMapcycleFile);
	if (!FileExists(sBuffer, false)) {
		PrintToServer("Fatal Error [5]: mapcyclefile \"%s\" doesn't exist!", sBuffer);
		SetFailState("Fatal Error [5]: mapcyclefile \"%s\" doesn't exist!", sBuffer);
	}
}

Action Timer_MakeTempMapcyle(Handle timer) {
	MakeTempMapcyle();
	ServerCommand("mapcyclefile %s", g_sTempMapcycleFile);
	if (!g_bHooked) {
		g_bHooked = true;
		g_cvDefMapcycleFile.AddChangeHook(OnConVarChanged);
	}
}

public void OnPluginEnd() {
	ServerCommand("mapcyclefile %s", g_sDefMapcycleFile);
}