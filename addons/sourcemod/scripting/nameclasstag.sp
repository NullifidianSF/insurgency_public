#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PL_VERSION	"1.0.1"

#define TEAM_SPECTATOR	1
#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

public Plugin myinfo =
{
	name        = "Class Name Tags",
	author      = "ChatGPT",
	description = "Adds [MEDIC]/[MG]/[VIP] name tags based on current theater",
	version     = PL_VERSION
};

// ----------------------------------------------------------------------
// Theater / class-slot detection
// ----------------------------------------------------------------------

ConVar g_cvTheaterOverride = null;

// Class slots – filled at runtime based on active theater
int g_iClassMedic1  = -1;
int g_iClassMedic2  = -1;
int g_iClassMG1     = -1;
int g_iClassMG2     = -1;
int g_iClassVIP     = -1;

// ----------------------------------------------------------------------
// Per-player state
// ----------------------------------------------------------------------

Handle g_hApplyTimer[MAXPLAYERS + 1];

char g_sBaseName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char g_sClassKind[MAXPLAYERS + 1][16]; // "medic", "mg", "vip" or ""

bool g_bHasBaseName[MAXPLAYERS + 1];
int g_iIgnoreNameChange[MAXPLAYERS + 1];

// ----------------------------------------------------------------------
// Plugin lifecycle
// ----------------------------------------------------------------------

public void OnPluginStart()
{
	g_cvTheaterOverride = FindConVar("mp_theater_override");

	if (g_cvTheaterOverride != null)
	{
		HookConVarChange(g_cvTheaterOverride, ConVarChanged_Theater);
	}

	HookEvent("player_team", Event_PlayerTeam_Post, EventHookMode_Post);
	HookEvent("player_pick_squad", Event_PlayerPickSquad_Post, EventHookMode_Post);
	HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Post);

	DetectTheaterAndSetupClasses();
}

public void OnConfigsExecuted()
{
	DetectTheaterAndSetupClasses();
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_hApplyTimer[i] = null;
		g_bHasBaseName[i] = false;
		g_iIgnoreNameChange[i] = 0;
		g_sClassKind[i][0] = '\0';
	}
}

public void OnClientPostAdminCheck(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	g_bHasBaseName[client] = false;
	g_iIgnoreNameChange[client] = 0;
	g_sClassKind[client][0] = '\0';
	StoreBaseNameIfNeeded(client);
}

public void OnClientDisconnect(int client)
{
	if (g_hApplyTimer[client] != null)
	{
		KillTimer(g_hApplyTimer[client]);
		g_hApplyTimer[client] = null;
	}

	g_bHasBaseName[client] = false;
	g_iIgnoreNameChange[client] = 0;
	g_sClassKind[client][0] = '\0';
	
}

void SetClientName_Safe(int client, const char[] name)
{
	g_iIgnoreNameChange[client]++;
	SetClientName(client, name);
}

public Action Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	if (g_iIgnoreNameChange[client] > 0)
	{
		g_iIgnoreNameChange[client]--;
		return Plugin_Continue;
	}

	char newName[MAX_NAME_LENGTH];
	event.GetString("newname", newName, sizeof(newName));

	StripExistingTag(newName, sizeof(newName));

	strcopy(g_sBaseName[client], sizeof(g_sBaseName[]), newName);
	g_bHasBaseName[client] = true;

	// Re-apply tag immediately after a real rename
	ApplyNameTag(client);

	return Plugin_Continue;
}

public Action Event_PlayerTeam_Post(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	// Ignore disconnect-generated team events
	if (event.GetBool("disconnect"))
		return Plugin_Continue;

	int team = event.GetInt("team");

	// If they are leaving Security, strip tag and restore base name immediately
	if (team != TEAM_SECURITY)
	{
		// Cancel any pending "apply tags" timer (if they were spamming squad pick then switched team)
		if (g_hApplyTimer[client] != null)
		{
			KillTimer(g_hApplyTimer[client]);
			g_hApplyTimer[client] = null;
		}

		// Ensure we have a base name cached (strips any tag from current name)
		StoreBaseNameIfNeeded(client);

		// Clear class kind so future ApplyNameTag() would restore base name
		g_sClassKind[client][0] = '\0';

		// Restore base name now (removes [VIP]/[MG]/[MEDIC])
		if (g_bHasBaseName[client])
			SetClientName_Safe(client, g_sBaseName[client]);
	}

	return Plugin_Continue;
}

public Action Event_PlayerPickSquad_Post(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	if (g_hApplyTimer[client] != null)
	{
		KillTimer(g_hApplyTimer[client]);
		g_hApplyTimer[client] = null;
	}

	g_hApplyTimer[client] = CreateTimer(0.1, Timer_ApplyTags, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Timer_ApplyTags(Handle timer, any data)
{
	int client = GetClientOfUserId(data);

	// Clear timer handle if possible
	if (client >= 1 && client <= MaxClients)
		g_hApplyTimer[client] = null;

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Stop;

	UpdatePlayerClassAndTags(client);
	return Plugin_Stop;
}

// ----------------------------------------------------------------------
// Theater detection
// ----------------------------------------------------------------------

public void ConVarChanged_Theater(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// Just update mapping; don't reapply tags here anymore
	DetectTheaterAndSetupClasses();
}

void DetectTheaterAndSetupClasses()
{
	char sTheater[128];
	sTheater[0] = '\0';

	// Defaults: ae_modern_bombervip_default_checkpoint.theater
	g_iClassMedic1 = -1;
	g_iClassMedic2 = -1;
	g_iClassMG1    = 6;
	g_iClassMG2    = 14;
	g_iClassVIP    = 7;

	if (g_cvTheaterOverride != null)
	{
		GetConVarString(g_cvTheaterOverride, sTheater, sizeof(sTheater));
	}

	TrimString(sTheater);

	if (sTheater[0] == '\0')
	{
		//LogMessage("[NameTags] No theater set, assuming bombervip (MG:6/14, VIP:7).");
		return;
	}

	if (StrContains(sTheater, "medic", false) != -1)
	{
		// ae_modern_medicbomberengineervip_default_checkpoint.theater
		g_iClassMedic1 = 6;
		g_iClassMedic2 = 14;
		g_iClassMG1    = 4;
		g_iClassMG2    = 12;

		//LogMessage("[NameTags] Detected medicbomberengineervip theater (%s). MEDIC:6/14, MG:4/12, VIP:7.", sTheater);
	}
	//else
	//{
		//LogMessage("[NameTags] Theater '%s' not recognised as medicbomberengineervip; using bombervip mapping (MG:6/14, VIP:7).", sTheater);
	//}
}

// ----------------------------------------------------------------------
// Core helpers
// ----------------------------------------------------------------------

void UpdatePlayerClassAndTags(int client)
{
	StoreBaseNameIfNeeded(client);
	DetectClassKindForClient(client);
	ApplyNameTag(client);
}

void DetectClassKindForClient(int client)
{
	g_sClassKind[client][0] = '\0';

	int team = GetClientTeam(client);
	if (team != TEAM_SECURITY)
	{
		return;
	}

	int iPR = GetPlayerResourceEntity();
	if (iPR == -1)
	{
		return;
	}

	int slot = GetEntProp(iPR, Prop_Send, "m_iPlayerClass", 4, client);

	if ((g_iClassMedic1 != -1 && slot == g_iClassMedic1)
	 || (g_iClassMedic2 != -1 && slot == g_iClassMedic2))
	{
		strcopy(g_sClassKind[client], sizeof(g_sClassKind[]), "medic");
	}
	else if ((g_iClassMG1 != -1 && slot == g_iClassMG1)
		  || (g_iClassMG2 != -1 && slot == g_iClassMG2))
	{
		strcopy(g_sClassKind[client], sizeof(g_sClassKind[]), "mg");
	}
	else if (g_iClassVIP != -1 && slot == g_iClassVIP)
	{
		strcopy(g_sClassKind[client], sizeof(g_sClassKind[]), "vip");
	}
}

// ----------------------------------------------------------------------
// Name handling
// ----------------------------------------------------------------------

void StoreBaseNameIfNeeded(int client)
{
	if (g_bHasBaseName[client])
	{
		return;
	}

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	StripExistingTag(sName, sizeof(sName));

	strcopy(g_sBaseName[client], sizeof(g_sBaseName[]), sName);
	g_bHasBaseName[client] = true;
}

void StripExistingTag(char[] name, int maxlen)
{
	static const char sPrefixes[][] =
	{
		"[MEDIC]",
		"[MG]",
		"[VIP]"
	};

	bool changed;

	do
	{
		changed = false;

		for (int i = 0; i < sizeof(sPrefixes); i++)
		{
			int len = strlen(sPrefixes[i]);

			// Starts with prefix (case-insensitive)
			if (StrContains(name, sPrefixes[i], false) == 0)
			{
				int idx = len;

				// Skip any whitespace after the tag: " ", "  ", "\t", etc.
				while (name[idx] == ' ' || name[idx] == '\t')
					idx++;

				// Shift remainder to the front
				int j = 0;
				while (name[idx + j] != '\0' && j < maxlen - 1)
				{
					name[j] = name[idx + j];
					j++;
				}
				name[j] = '\0';

				changed = true;
				break; // restart loop in case there are stacked tags
			}
		}
	}
	while (changed);
}

void ApplyNameTag(int client)
{
	if (!g_bHasBaseName[client])
	{
		StoreBaseNameIfNeeded(client);
	}

	if (!g_bHasBaseName[client])
	{
		return;
	}

	// If we don't have a class tag, restore the original name
	if (g_sClassKind[client][0] == '\0')
	{
		SetClientName_Safe(client, g_sBaseName[client]);
		return;
	}

	char sTag[8];
	sTag[0] = '\0';

	if (StrEqual(g_sClassKind[client], "medic", false))
	{
		strcopy(sTag, sizeof(sTag), "MEDIC");
	}
	else if (StrEqual(g_sClassKind[client], "mg", false))
	{
		strcopy(sTag, sizeof(sTag), "MG");
	}
	else if (StrEqual(g_sClassKind[client], "vip", false))
	{
		strcopy(sTag, sizeof(sTag), "VIP");
	}
	else
	{
		SetClientName_Safe(client, g_sBaseName[client]);
		return;
	}

	char sNewName[MAX_NAME_LENGTH];
	Format(sNewName, sizeof(sNewName), "[%s] %s", sTag, g_sBaseName[client]);

	SetClientName_Safe(client, sNewName);
}
