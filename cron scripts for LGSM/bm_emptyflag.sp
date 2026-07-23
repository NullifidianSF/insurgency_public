#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PL_VERSION "1.4"
#define MAP_START_RECOUNT_DELAY 3.0

bool g_bRecountQueued = false;
bool g_bAllowEmptyFlag = false;

char g_sFlagPath[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name        = "Empty Restart Flag",
	author      = "Nullifidian + ChatGPT",
	description = "Writes a flag file when server is truly empty.",
	version     = PL_VERSION,
	url         = ""
};

public void OnPluginStart()
{
	// addons/sourcemod/data/bm_server_empty.txt
	BuildPath(Path_SM, g_sFlagPath, sizeof(g_sFlagPath), "data/bm_server_empty.txt");
}

public void OnMapStart()
{
	g_bRecountQueued = false;
	g_bAllowEmptyFlag = false;

	// Never advertise an empty server while humans are transitioning to the new map.
	WriteEmptyFlag(false);
	CreateTimer(MAP_START_RECOUNT_DELAY, Timer_RecountAfterMapStart, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
	g_bAllowEmptyFlag = false;
	WriteEmptyFlag(false);
}

public Action Timer_RecountAfterMapStart(Handle timer, any data)
{
	g_bAllowEmptyFlag = true;
	UpdateEmptyFlag();
	return Plugin_Stop;
}

public void OnClientConnected(int client)
{
	if (IsFakeClient(client) || IsClientSourceTV(client))
		return;

	// Protect connecting humans before they reach the in-game state.
	WriteEmptyFlag(false);
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client) || IsClientSourceTV(client))
		return;

	// Any real human joining means "server is in use" → not empty
	UpdateEmptyFlag();
}

public void OnClientDisconnect(int client)
{
	// Recount once, next frame (after all disconnect callbacks for the tick)
	if (!g_bRecountQueued)
	{
		g_bRecountQueued = true;
		RequestFrame(Frame_RecountAfterDisconnect);
	}
}

public void Frame_RecountAfterDisconnect(any data)
{
	g_bRecountQueued = false;
	UpdateEmptyFlag();
}

// ------------ Helpers ------------

static bool IsHumanClient(int client)
{
	return (client > 0
		&& client <= MaxClients
		&& IsClientConnected(client)
		&& !IsFakeClient(client)
		&& !IsClientSourceTV(client));
}

static void UpdateEmptyFlag()
{
	if (!g_bAllowEmptyFlag)
	{
		WriteEmptyFlag(false);
		return;
	}

	int humans = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanClient(i))
		{
			humans++;
		}
	}

	WriteEmptyFlag(humans == 0);
}

static void WriteEmptyFlag(bool empty)
{
	File f = OpenFile(g_sFlagPath, "w");
	if (f != null)
	{
		// Your bash script checks: grep -qx "1"
		// so write exactly "1" or "0" as a line.
		if (empty)
		{
			f.WriteLine("1"); // server empty → safe to restart
		}
		else
		{
			f.WriteLine("0"); // server has humans
		}
		delete f;
	}
}

public void OnPluginEnd()
{
	// Optional: clean up flag on unload so cron doesn't think it’s permanently safe
	if (g_sFlagPath[0] != '\0')
	{
		DeleteFile(g_sFlagPath);
	}
}
