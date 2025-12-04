#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PL_VERSION "1.3"

bool g_bRecountQueued = false;

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
	// Re-evaluate when new map starts (handles empty server on fresh map)
	UpdateEmptyFlag();
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
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& !IsClientSourceTV(client));
}

static void UpdateEmptyFlag()
{
	int humans = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanClient(i))
		{
			humans++;
		}
	}

	File f = OpenFile(g_sFlagPath, "w");
	if (f != null)
	{
		// Your bash script checks: grep -qx "1"
		// so write exactly "1" or "0" as a line.
		if (humans == 0)
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
