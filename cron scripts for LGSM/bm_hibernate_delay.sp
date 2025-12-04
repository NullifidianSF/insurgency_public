#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PL_VERSION "1.2"

// How long to keep hibernate disabled after the last human leaves (seconds)
#define HIBERNATE_DELAY_SEC 20.0

bool g_bIsMapChanging = false;
bool g_bRecountQueued = false;

ConVar g_cvHibernate = null;
Handle g_hDelayTimer = null;

public Plugin myinfo =
{
	name        = "Hibernate Delay After Empty",
	author      = "Nullifidian + ChatGPT",
	description = "Delays server hibernate after last human leaves.",
	version     = PL_VERSION,
	url         = ""
};

public void OnPluginStart()
{
	g_cvHibernate = FindConVar("sv_hibernate_when_empty");
	if (g_cvHibernate == null)
	{
		SetFailState("Could not find ConVar sv_hibernate_when_empty");
	}

	// Mapchange detection (same pattern as AFK manager)
	AddCommandListener(ChangeLevelListener, "changelevel");
	AddCommandListener(ChangeLevelListener, "map");
	AddCommandListener(ChangeLevelListener, "sm_map");
}

public void OnMapStart()
{
	g_bIsMapChanging = false;
	g_bRecountQueued = false;

	if (g_hDelayTimer != null)
	{
		delete g_hDelayTimer;
		g_hDelayTimer = null;
	}

	// Start from "no hibernate" on each map
	g_cvHibernate.BoolValue = false;

	// If server booted empty, we can already schedule a delayed enable
	if (HumanCountInGame() == 0)
	{
		StartHibernateDelay();
	}
}

public void OnMapEnd()
{
	g_bIsMapChanging = true;

	if (g_hDelayTimer != null)
	{
		delete g_hDelayTimer;
		g_hDelayTimer = null;
	}
}

// ---------- Client tracking ----------

public void OnClientPostAdminCheck(int client)
{
	if (!IsHumanClientInGame(client))
		return;

	// Any human joining: cancel pending enable + keep hibernate disabled
	if (g_hDelayTimer != null)
	{
		delete g_hDelayTimer;
		g_hDelayTimer = null;
	}

	g_cvHibernate.BoolValue = false;
}

public void OnClientDisconnect(int client)
{
	// Ignore mass disconnects during map change
	if (g_bIsMapChanging)
		return;

	if (!g_bRecountQueued)
	{
		g_bRecountQueued = true;
		RequestFrame(Frame_RecountAfterDisconnect);
	}
}

public void Frame_RecountAfterDisconnect(any data)
{
	g_bRecountQueued = false;

	if (g_bIsMapChanging)
		return;

	int humans = HumanCountInGame();

	if (humans == 0)
	{
		// Server truly empty now → start delay window
		StartHibernateDelay();
	}
	else
	{
		// Still humans; keep hibernate disabled
		if (g_hDelayTimer != null)
		{
			delete g_hDelayTimer;
			g_hDelayTimer = null;
		}
		g_cvHibernate.BoolValue = false;
	}
}

// ---------- Core logic ----------

void StartHibernateDelay()
{
	if (g_cvHibernate == null)
		return;

	// Always cancel existing delay timer before starting a new one
	if (g_hDelayTimer != null)
	{
		delete g_hDelayTimer;
		g_hDelayTimer = null;
	}

	// While we wait, make sure hibernate is DISABLED
	g_cvHibernate.BoolValue = false;

	g_hDelayTimer = CreateTimer(HIBERNATE_DELAY_SEC, Timer_EnableHibernateIfStillEmpty, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_EnableHibernateIfStillEmpty(Handle timer, any data)
{
	g_hDelayTimer = null;

	if (g_bIsMapChanging)
	{
		return Plugin_Stop;
	}

	int humans = HumanCountInGame();

	if (humans == 0)
	{
		// Still empty after delay → allow hibernate now
		g_cvHibernate.BoolValue = true;
	}
	else
	{
		// Someone joined during delay → keep hibernate disabled
		g_cvHibernate.BoolValue = false;
	}

	return Plugin_Stop;
}

// ---------- Helpers ----------

bool IsHumanClientInGame(int client)
{
	return (client > 0 &&
	        client <= MaxClients &&
	        IsClientInGame(client) &&
	        !IsClientSourceTV(client) &&
	        !IsFakeClient(client));
}

int HumanCountInGame()
{
	int n = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanClientInGame(i))
			n++;
	}
	return n;
}

public Action ChangeLevelListener(int client, const char[] command, int argc)
{
	if (StrEqual(command, "sm_map", false))
	{
		if (client > 0 && !CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP, true))
			return Plugin_Continue;
	}
	else if (StrEqual(command, "map", false) || StrEqual(command, "changelevel", false))
	{
		if (client > 0)
			return Plugin_Continue;
	}
	else
	{
		return Plugin_Continue;
	}

	if (argc > 0)
	{
		char nextMap[PLATFORM_MAX_PATH];
		GetCmdArg(1, nextMap, sizeof(nextMap));
		if (IsMapValid(nextMap))
			g_bIsMapChanging = true;
	}
	return Plugin_Continue;
}

public void OnPluginEnd()
{
	if (g_hDelayTimer != null)
	{
		delete g_hDelayTimer;
		g_hDelayTimer = null;
	}

	// Leave server in a sane default: allow hibernate when empty
	if (g_cvHibernate != null)
	{
		g_cvHibernate.BoolValue = true;
	}
}
