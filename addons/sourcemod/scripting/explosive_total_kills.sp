#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

const float ARTILLERY_IMPACT_GRACE = 10.0;

enum SupportShellType
{
	SupportShell_Rocket,
	SupportShell_Frag,
	SupportShell_Molotov
};

enum struct KillTotals
{
	int explosiveKills;
	int artilleryKills;
	SupportShellType artilleryShellType;
	bool artilleryActive;
	Handle explosiveTimer;
	Handle artilleryTimer;
}

KillTotals g_KillTotals[MAXPLAYERS + 1];
bool g_bFireSupportPlugin;

char g_sExplosiveWeapons[][] = {
	"rocket_at4",
	"rocket_rpg7",
	"grenade_f1",
	"grenade_m67",
	"grenade_m26a2",
	"grenade_c4",
	"grenade_ied",
	"grenade_ied_gunshot",
	"grenade_m203_he",
	"grenade_gp25_he",
	//"grenade_m79",
	"grenade_ied_fire",
	"grenade_ied_radius",
	"grenade_c4_radius",
	"prop_dynamic"
};

public Plugin myinfo = {
	name = "explosive_total_kills",
	author = "Nullifidian",
	description = "Print in chat how many kills with one explosive.",
	version = "1.1.0",
	url = "https://steamcommunity.com/id/Nullifidian/"
};

public void OnPluginStart()
{
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("round_end", Event_RoundEnd);
}

public void OnAllPluginsLoaded()
{
	g_bFireSupportPlugin = LibraryExists("FireSupport");
}

public void OnPluginEnd()
{
	for (int client = 1; client <= MaxClients; client++)
		ResetClientState(client, true);
}

public void OnMapStart()
{
	// Map-change timers are already destroyed by SourceMod. Clear their stale handles.
	for (int client = 1; client <= MaxClients; client++)
		ResetClientState(client, false);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "FireSupport", false))
		g_bFireSupportPlugin = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (!StrEqual(name, "FireSupport", false))
		return;

	g_bFireSupportPlugin = false;
	for (int client = 1; client <= MaxClients; client++)
		ResetArtilleryState(client, true);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client, true);
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int client = 1; client <= MaxClients; client++)
		ResetArtilleryState(client, true);

	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(attacker) || attacker == victim || IsFakeClient(attacker))
		return Plugin_Continue;

	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));

	if (g_bFireSupportPlugin && g_KillTotals[attacker].artilleryActive
		&& IsArtilleryWeapon(weapon, g_KillTotals[attacker].artilleryShellType))
	{
		g_KillTotals[attacker].artilleryKills++;
		return Plugin_Continue;
	}

	if (IsExplosiveWeapon(weapon))
		TrackExplosiveKill(attacker, weapon);

	return Plugin_Continue;
}

public void FireSupport_OnBarrageStarted(int userid, int shellType)
{
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	ResetArtilleryState(client, true);
	g_KillTotals[client].artilleryActive = true;
	g_KillTotals[client].artilleryShellType = view_as<SupportShellType>(shellType);
}

public void FireSupport_OnBarrageFinished(int userid, int shellType)
{
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client) || !g_KillTotals[client].artilleryActive
		|| g_KillTotals[client].artilleryShellType != view_as<SupportShellType>(shellType))
		return;

	delete g_KillTotals[client].artilleryTimer;
	g_KillTotals[client].artilleryTimer = CreateTimer(ARTILLERY_IMPACT_GRACE,
		Timer_ArtilleryTotalKilled, userid, TIMER_FLAG_NO_MAPCHANGE);
}

void TrackExplosiveKill(int client, const char[] weapon)
{
	g_KillTotals[client].explosiveKills++;
	if (g_KillTotals[client].explosiveTimer != null)
		return;

	DataPack data;
	g_KillTotals[client].explosiveTimer = CreateDataTimer(0.1, Timer_ExplosiveTotalKilled,
		data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(GetClientUserId(client));
	data.WriteString(weapon);
}

Action Timer_ExplosiveTotalKilled(Handle timer, DataPack data)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	char weapon[32];
	data.ReadString(weapon, sizeof(weapon));

	if (IsValidClient(client))
	{
		if (g_KillTotals[client].explosiveKills > 5)
			PrintExplosiveTotal(client, weapon, g_KillTotals[client].explosiveKills);

		g_KillTotals[client].explosiveKills = 0;
		g_KillTotals[client].explosiveTimer = null;
	}
	return Plugin_Stop;
}

Action Timer_ArtilleryTotalKilled(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (IsValidClient(client))
	{
		if (g_KillTotals[client].artilleryKills > 5)
			PrintToChatAll("\x07859715%N  \x07ffffff[Artillery] x \x07ad3e24%d", client,
				g_KillTotals[client].artilleryKills);

		ResetArtilleryState(client, false);
	}
	return Plugin_Stop;
}

void ResetClientState(int client, bool closeTimers)
{
	if (closeTimers)
		delete g_KillTotals[client].explosiveTimer;
	else
		g_KillTotals[client].explosiveTimer = null;

	g_KillTotals[client].explosiveKills = 0;
	ResetArtilleryState(client, closeTimers);
}

void ResetArtilleryState(int client, bool closeTimer)
{
	if (closeTimer)
		delete g_KillTotals[client].artilleryTimer;
	else
		g_KillTotals[client].artilleryTimer = null;

	g_KillTotals[client].artilleryKills = 0;
	g_KillTotals[client].artilleryShellType = SupportShell_Rocket;
	g_KillTotals[client].artilleryActive = false;
}

bool IsExplosiveWeapon(const char[] weapon)
{
	for (int index = 0; index < sizeof(g_sExplosiveWeapons); index++)
		if (StrEqual(weapon, g_sExplosiveWeapons[index], false))
			return true;

	return false;
}

bool IsArtilleryWeapon(const char[] weapon, SupportShellType shellType)
{
	switch (shellType)
	{
		case SupportShell_Rocket: return StrEqual(weapon, "rocket_firesupport", false);
		case SupportShell_Frag: return StrEqual(weapon, "grenade_f1", false)
			|| StrEqual(weapon, "grenade_m67", false);
		case SupportShell_Molotov: return StrEqual(weapon, "grenade_molotov", false);
	}
	return false;
}

void PrintExplosiveTotal(int client, const char[] weapon, int kills)
{
	char displayName[32];
	GetExplosiveDisplayName(weapon, displayName, sizeof(displayName));
	PrintToChatAll("\x07859715%N  \x07ffffff[%s] x \x07ad3e24%d", client, displayName, kills);
}

void GetExplosiveDisplayName(const char[] weapon, char[] displayName, int maxLength)
{
	if (StrEqual(weapon, "rocket_at4", false)) strcopy(displayName, maxLength, "AT4");
	else if (StrEqual(weapon, "rocket_rpg7", false)) strcopy(displayName, maxLength, "RPG-7");
	else if (StrEqual(weapon, "grenade_f1", false)) strcopy(displayName, maxLength, "F1");
	else if (StrEqual(weapon, "grenade_m67", false)) strcopy(displayName, maxLength, "M67");
	else if (StrEqual(weapon, "grenade_m26a2", false)) strcopy(displayName, maxLength, "M26A2 Frag");
	else if (StrEqual(weapon, "grenade_c4", false)) strcopy(displayName, maxLength, "C4");
	else if (StrEqual(weapon, "grenade_ied", false)) strcopy(displayName, maxLength, "IED");
	else if (StrEqual(weapon, "grenade_ied_gunshot", false)) strcopy(displayName, maxLength, "IED-G");
	else if (StrEqual(weapon, "grenade_m203_he", false)) strcopy(displayName, maxLength, "M203 HE");
	else if (StrEqual(weapon, "grenade_gp25_he", false)) strcopy(displayName, maxLength, "GP-25 HE");
	else if (StrEqual(weapon, "grenade_ied_fire", false)) strcopy(displayName, maxLength, "IED-F");
	else if (StrEqual(weapon, "grenade_ied_radius", false)) strcopy(displayName, maxLength, "IED-R");
	else if (StrEqual(weapon, "grenade_c4_radius", false)) strcopy(displayName, maxLength, "C4-R");
	else strcopy(displayName, maxLength, weapon);
}

bool IsValidClient(int client)
{
	return client >= 1 && client <= MaxClients && IsClientInGame(client);
}
