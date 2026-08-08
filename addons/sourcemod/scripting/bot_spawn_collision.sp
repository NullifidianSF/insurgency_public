#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define PLAYERFLAG_IN_SPAWNZONE (1 << 7)
#define COLLISION_GROUP_PLAYER 5
#define COLLISION_GROUP_PLAYER_MOVEMENT 8

ConVar g_cvEnabled = null;
ConVar g_cvSpawnDelay = null;

bool g_bLateLoad;
bool g_bHooked[MAXPLAYERS + 1] = {false, ...};
float g_fCollisionEnableTime[MAXPLAYERS + 1] = {0.0, ...};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "Bot Spawn Collision",
	author = "GPT",
	description = "Makes spawn-zone bots collide after a short spawn grace period",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	g_cvEnabled = CreateConVar("sm_bot_spawn_collision", "1", "Enable collision for bots in their spawn zone.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvSpawnDelay = CreateConVar("sm_bot_spawn_collision_delay", "2.0", "Seconds after a bot spawns before spawn-zone collision is enabled.", FCVAR_NONE, true, 0.0, true, 10.0);

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	AutoExecConfig(true, "bot_spawn_collision");

	if (g_bLateLoad)
		RequestFrame(Frame_HookExistingBots);
}

public void OnMapStart()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		g_bHooked[client] = false;
		g_fCollisionEnableTime[client] = 0.0;
	}
}

public void OnPluginEnd()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_bHooked[client] && IsClientInGame(client))
			SDKUnhook(client, SDKHook_ShouldCollide, Hook_ShouldCollide);
	}
}

public void OnClientPutInServer(int client)
{
	if (IsClientInGame(client) && IsFakeClient(client))
		HookBot(client);
}

public void OnClientDisconnect(int client)
{
	if (client < 1 || client > MaxClients)
		return;

	g_bHooked[client] = false;
	g_fCollisionEnableTime[client] = 0.0;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsFakeClient(client))
		return;

	HookBot(client);
	g_fCollisionEnableTime[client] = GetGameTime() + g_cvSpawnDelay.FloatValue;
}

void Frame_HookExistingBots(any data)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsFakeClient(client))
			continue;

		HookBot(client);
		g_fCollisionEnableTime[client] = GetGameTime() + g_cvSpawnDelay.FloatValue;
	}
}

void HookBot(int client)
{
	if (g_bHooked[client])
		return;

	SDKHook(client, SDKHook_ShouldCollide, Hook_ShouldCollide);
	g_bHooked[client] = true;
}

public bool Hook_ShouldCollide(int client, int collisionGroup, int contentsMask, bool originalResult)
{
	if (!g_cvEnabled.BoolValue
		|| GetGameTime() < g_fCollisionEnableTime[client]
		|| (GetEntProp(client, Prop_Send, "m_iPlayerFlags") & PLAYERFLAG_IN_SPAWNZONE) == 0)
	{
		return originalResult;
	}

	if ((collisionGroup == COLLISION_GROUP_PLAYER || collisionGroup == COLLISION_GROUP_PLAYER_MOVEMENT) && !originalResult)
		return true;

	return originalResult;
}
