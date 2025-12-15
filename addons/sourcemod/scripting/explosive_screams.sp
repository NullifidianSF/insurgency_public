#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

#define FRAG_DIST_SQR	(300.0 * 300.0)
#define FIRE_DIST_SQR	(300.0 * 300.0)		// 300 HU ≈ 300 inches ≈ 7.62 meters

public Plugin myinfo =
{
	name		= "[INS] Explosive Screams",
	author		= "Jared Ballou, Daimyo, Nullifidian & ChatGPT",
	description	= "Grenade / incendiary callouts for Insurgency 2014",
	version		= "1.0.1",
	url			= ""
};

public void OnPluginStart()
{
	HookEvent("grenade_thrown", Event_GrenadeThrown, EventHookMode_Post);
}

public void OnMapStart()
{
	PrecacheCalloutSounds();
}

public Action Event_GrenadeThrown(Event event, const char[] name, bool dontBroadcast)
{
	int ent = event.GetInt("entityid");
	if (ent <= MaxClients || !IsValidEntity(ent))
		return Plugin_Continue;

	// Let classname/owner settle (cheap insurance)
	CreateTimer(0.0, Timer_StartWatch, EntIndexToEntRef(ent), TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action Timer_StartWatch(Handle timer, int entref)
{
	int entity = EntRefToEntIndex(entref);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity))
		return Plugin_Stop;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	// ONE-SHOT checks (no TIMER_REPEAT)
	if (StrEqual(classname, "grenade_m67") || StrEqual(classname, "grenade_f1") || StrEqual(classname, "grenade_m26a2"))
	{
		CreateTimer(0.5, GrenadeScreamCheckTimer, entref, TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (StrEqual(classname, "grenade_molotov") || StrEqual(classname, "grenade_anm14"))
	{
		CreateTimer(0.2, FireScreamCheckTimer, entref, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Stop;
}

public Action FireScreamCheckTimer(Handle timer, int entref)
{
	int entity = EntRefToEntIndex(entref);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Send, "m_hOwnerEntity"))
		return Plugin_Stop;

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner > MaxClients || !IsClientInGame(owner))
		return Plugin_Stop;

	int ownerTeam = GetClientTeam(owner);
	if (ownerTeam != TEAM_SECURITY && ownerTeam != TEAM_INSURGENT)
		return Plugin_Stop;

	float fGrenOrigin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", fGrenOrigin);

	float fPlayerOrigin[3];

	int bestClient = 0;
	float bestDistSqr = FIRE_DIST_SQR + 1.0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (GetClientTeam(client) == ownerTeam)
			continue;

		GetClientAbsOrigin(client, fPlayerOrigin);

		float distSqr = GetVectorDistance(fPlayerOrigin, fGrenOrigin, true);
		if (distSqr <= FIRE_DIST_SQR && distSqr < bestDistSqr)
		{
			bestDistSqr = distSqr;
			bestClient = client;
		}
	}

	if (bestClient != 0)
	{
		// If insurgents throw -> security callouts.
		// If security throw -> insurgent callouts.
		if (ownerTeam == TEAM_INSURGENT)
			PlayerFireScreamRand(bestClient);
		else
			BotFireScreamRand(bestClient);
	}

	return Plugin_Stop;
}

public Action GrenadeScreamCheckTimer(Handle timer, int entref)
{
	int entity = EntRefToEntIndex(entref);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Send, "m_hOwnerEntity"))
		return Plugin_Stop;

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner > MaxClients || !IsClientInGame(owner))
		return Plugin_Stop;

	int ownerTeam = GetClientTeam(owner);
	if (ownerTeam != TEAM_SECURITY && ownerTeam != TEAM_INSURGENT)
		return Plugin_Stop;

	float fGrenOrigin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", fGrenOrigin);

	float fPlayerOrigin[3];

	int bestClient = 0;
	float bestDistSqr = FRAG_DIST_SQR + 1.0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (GetClientTeam(client) == ownerTeam)
			continue;

		GetClientAbsOrigin(client, fPlayerOrigin);

		float distSqr = GetVectorDistance(fPlayerOrigin, fGrenOrigin, true);
		if (distSqr <= FRAG_DIST_SQR && distSqr < bestDistSqr)
		{
			bestDistSqr = distSqr;
			bestClient = client;
		}
	}

	if (bestClient != 0)
	{
		if (ownerTeam == TEAM_INSURGENT)
			PlayerGrenadeScreamRand(bestClient);
		else
			BotGrenadeScreamRand(bestClient);
	}

	return Plugin_Stop;
}

/* ---- your original sound precache + rand emit code below ---- */

void PrecacheCalloutSounds()
{
	char sBuffer[128];

	PrecacheSound("player/voice/botsurvival/subordinate/incominggrenade9.ogg", true);
	PrecacheSound("player/voice/botsurvival/subordinate/incominggrenade33.ogg", true);
	PrecacheSound("player/voice/botsurvival/subordinate/incominggrenade34.ogg", true);
	PrecacheSound("player/voice/botsurvival/leader/incominggrenade9.ogg", true);
	PrecacheSound("player/voice/botsurvival/leader/incominggrenade4.ogg", true);
	PrecacheSound("player/voice/botsurvival/leader/incominggrenade18.ogg", true);

	for (int i = 1; i <= 3; i++)
	{
		FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/subordinate/incominggrenade%d.ogg", i);
		PrecacheSound(sBuffer, true);
	}
	for (int i = 11; i <= 13; i++)
	{
		FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/leader/incominggrenade%d.ogg", i);
		PrecacheSound(sBuffer, true);
	}

	PrecacheSound("player/voice/responses/security/subordinate/damage/molotov_incendiary_detonated7.ogg", true);
	PrecacheSound("player/voice/responses/security/subordinate/damage/molotov_incendiary_detonated6.ogg", true);
	PrecacheSound("player/voice/responses/security/leader/damage/molotov_incendiary_detonated5.ogg", true);
	PrecacheSound("player/voice/responses/security/leader/damage/molotov_incendiary_detonated4.ogg", true);

	PrecacheSound("player/voice/responses/insurgent/leader/damage/molotov_incendiary_detonated5.ogg", true);
	PrecacheSound("player/voice/responses/insurgent/leader/damage/molotov_incendiary_detonated7.ogg", true);
	PrecacheSound("player/voice/responses/insurgent/subordinate/damage/molotov_incendiary_detonated3.ogg", true);
}

stock void PlayerGrenadeScreamRand(int client)
{
	switch (GetRandomInt(0, 5))
	{
		case 0: EmitSoundToAll("player/voice/botsurvival/leader/incominggrenade4.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/botsurvival/leader/incominggrenade9.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/botsurvival/leader/incominggrenade18.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/botsurvival/subordinate/incominggrenade9.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 4: EmitSoundToAll("player/voice/botsurvival/subordinate/incominggrenade33.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 5: EmitSoundToAll("player/voice/botsurvival/subordinate/incominggrenade34.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}

stock void PlayerFireScreamRand(int client)
{
	switch (GetRandomInt(0, 3))
	{
		case 0: EmitSoundToAll("player/voice/responses/security/subordinate/damage/molotov_incendiary_detonated6.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/responses/security/subordinate/damage/molotov_incendiary_detonated7.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/responses/security/leader/damage/molotov_incendiary_detonated4.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/responses/security/leader/damage/molotov_incendiary_detonated5.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}

stock void BotGrenadeScreamRand(int client)
{
	switch (GetRandomInt(0, 5))
	{
		case 0: EmitSoundToAll("player/voice/bot/subordinate/incominggrenade1.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/bot/subordinate/incominggrenade2.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/bot/subordinate/incominggrenade3.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/bot/leader/incominggrenade11.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 4: EmitSoundToAll("player/voice/bot/leader/incominggrenade12.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 5: EmitSoundToAll("player/voice/bot/leader/incominggrenade13.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}

stock void BotFireScreamRand(int client)
{
	switch (GetRandomInt(0, 2))
	{
		case 0: EmitSoundToAll("player/voice/responses/insurgent/leader/damage/molotov_incendiary_detonated5.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/responses/insurgent/leader/damage/molotov_incendiary_detonated7.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/responses/insurgent/subordinate/damage/molotov_incendiary_detonated3.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}
