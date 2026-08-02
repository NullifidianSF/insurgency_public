#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.1.4"

#define BTN_ATTACK1 (1 << 0)
#define BTN_USE     (1 << 6)

#define PICKUP_RETRY_INTERVAL 0.10
#define DEBUG_REPORT_INTERVAL 0.50
#define WEAPON_ATTACK_BLOCK_TIME 0.25
#define SIGHT_END_TOLERANCE   12.0
#define SIGHT_TARGET_Z_OFFSET 6.0

ConVar g_cvEnabled;
ConVar g_cvPickupRange;
ConVar g_cvThrowSpeed;
ConVar g_cvEnemyOnly;
ConVar g_cvDebug;

ArrayList g_LiveGrenades;

int g_iHeldGrenade[MAXPLAYERS + 1];
int g_iLastButtons[MAXPLAYERS + 1];
float g_fNextPickupAttempt[MAXPLAYERS + 1];
float g_fNextDebugReport[MAXPLAYERS + 1];
int g_iOldMoveType[MAXPLAYERS + 1];
int g_iOldSolidType[MAXPLAYERS + 1];
int g_iOldSolidFlags[MAXPLAYERS + 1];
int g_iOldCollisionGroup[MAXPLAYERS + 1];
bool g_bHadSolidType[MAXPLAYERS + 1];
bool g_bHadSolidFlags[MAXPLAYERS + 1];
bool g_bHadCollisionGroup[MAXPLAYERS + 1];
bool g_bBlockAttackUntilRelease[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[INS] Grenade Throwback",
	author = "Nullifidian & OpenAI",
	description = "Lets players pick up live enemy frag grenades and throw them back",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	g_cvEnabled = CreateConVar(
		"sm_grenade_throwback_enabled", "1",
		"Enable live grenade throwback (0/1).",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvPickupRange = CreateConVar(
		"sm_grenade_throwback_range", "90.0",
		"Maximum distance in Hammer units at which a grenade can be picked up.",
		FCVAR_NOTIFY, true, 24.0, true, 160.0);

	g_cvThrowSpeed = CreateConVar(
		"sm_grenade_throwback_speed", "850.0",
		"Forward velocity applied when a held grenade is thrown.",
		FCVAR_NOTIFY, true, 200.0, true, 1600.0);

	g_cvEnemyOnly = CreateConVar(
		"sm_grenade_throwback_enemy_only", "1",
		"Only allow grenades owned by the opposing team to be picked up (0/1).",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvDebug = CreateConVar(
		"sm_grenade_throwback_debug", "0",
		"Log pickup and throwback actions (0/1).",
		FCVAR_NONE, true, 0.0, true, 1.0);

	g_LiveGrenades = new ArrayList();

	HookEvent("grenade_thrown", Event_GrenadeThrown, EventHookMode_Post);
	HookEvent("grenade_detonate", Event_GrenadeDetonate, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

	for (int client = 1; client <= MaxClients; client++)
		ResetClientState(client);

	AutoExecConfig(true, "grenade_throwback");
}

public void OnMapStart()
{
	if (g_LiveGrenades != null)
		g_LiveGrenades.Clear();

	for (int client = 1; client <= MaxClients; client++)
		ResetClientState(client);
}

public void OnMapEnd()
{
	if (g_LiveGrenades != null)
		g_LiveGrenades.Clear();

	for (int client = 1; client <= MaxClients; client++)
		ResetClientState(client);
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
}

public void OnClientDisconnect(int client)
{
	ReleaseGrenade(client, false);
	ResetClientState(client);
}

public void OnPluginEnd()
{
	for (int client = 1; client <= MaxClients; client++)
		ReleaseGrenade(client, false);

	delete g_LiveGrenades;
}

public Action Event_GrenadeThrown(Event event, const char[] name, bool dontBroadcast)
{
	RemoveTrackedGrenade(-1);

	int entity = event.GetInt("entityid");
	if (entity <= MaxClients || !IsValidEntity(entity) || !IsThrowbackGrenade(entity))
		return Plugin_Continue;

	int entRef = EntIndexToEntRef(entity);
	if (entRef != INVALID_ENT_REFERENCE && g_LiveGrenades.FindValue(entRef) == -1)
		g_LiveGrenades.Push(entRef);

	return Plugin_Continue;
}

public Action Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast)
{
	int entity = event.GetInt("entityid");
	RemoveTrackedGrenade(entity);

	for (int client = 1; client <= MaxClients; client++)
	{
		int held = EntRefToEntIndex(g_iHeldGrenade[client]);
		if (held == INVALID_ENT_REFERENCE || held == entity)
			ClearHeldState(client);
	}

	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client >= 1 && client <= MaxClients)
	{
		ReleaseGrenade(client, false);
		g_bBlockAttackUntilRelease[client] = false;
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3],
	int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	int inputButtons = buttons;
	bool changed = false;

	if (g_bBlockAttackUntilRelease[client])
	{
		if ((buttons & BTN_ATTACK1) != 0)
		{
			DelayEquippedWeaponAttack(client);
			buttons &= ~BTN_ATTACK1;
			changed = true;
		}
		else
		{
			g_bBlockAttackUntilRelease[client] = false;
		}
	}

	if (!g_cvEnabled.BoolValue || !IsPlayerAlive(client))
	{
		if (g_iHeldGrenade[client] != INVALID_ENT_REFERENCE)
			ReleaseGrenade(client, false);

		g_iLastButtons[client] = inputButtons;
		return changed ? Plugin_Changed : Plugin_Continue;
	}

	int held = EntRefToEntIndex(g_iHeldGrenade[client]);

	if (held != INVALID_ENT_REFERENCE && held > MaxClients && IsValidEntity(held))
	{
		UpdateHeldGrenade(client, held);
		DelayEquippedWeaponAttack(client);

		if ((buttons & BTN_ATTACK1) != 0 && (g_iLastButtons[client] & BTN_ATTACK1) == 0)
		{
			ReleaseGrenade(client, true);
			g_bBlockAttackUntilRelease[client] = true;
			DelayEquippedWeaponAttack(client);
			buttons &= ~BTN_ATTACK1;
			changed = true;
		}
		else if ((buttons & BTN_USE) != 0 && (g_iLastButtons[client] & BTN_USE) == 0)
		{
			ReleaseGrenade(client, false);
			buttons &= ~BTN_USE;
			changed = true;
		}
		else
		{
			if ((buttons & BTN_ATTACK1) != 0)
			{
				DelayEquippedWeaponAttack(client);
				buttons &= ~BTN_ATTACK1;
				changed = true;
			}
		}
	}
	else
	{
		if (g_iHeldGrenade[client] != INVALID_ENT_REFERENCE)
			ClearHeldState(client);

		float now = GetGameTime();
		if ((buttons & BTN_USE) != 0 && now >= g_fNextPickupAttempt[client])
		{
			g_fNextPickupAttempt[client] = now + PICKUP_RETRY_INTERVAL;
			bool debugReport = g_cvDebug.BoolValue && now >= g_fNextDebugReport[client];
			if (debugReport)
				g_fNextDebugReport[client] = now + DEBUG_REPORT_INTERVAL;

			int grenade = FindPickupGrenade(client, debugReport);
			if (grenade != -1 && PickUpGrenade(client, grenade))
			{
				buttons &= ~BTN_USE;
				changed = true;
			}
		}
	}

	g_iLastButtons[client] = inputButtons;
	return changed ? Plugin_Changed : Plugin_Continue;
}

bool PickUpGrenade(int client, int grenade)
{
	if (!IsValidThrowbackTarget(client, grenade))
		return false;

	g_iHeldGrenade[client] = EntIndexToEntRef(grenade);
	g_iOldMoveType[client] = view_as<int>(GetEntityMoveType(grenade));

	g_bHadSolidType[client] = HasEntProp(grenade, Prop_Send, "m_nSolidType");
	if (g_bHadSolidType[client])
	{
		g_iOldSolidType[client] = GetEntProp(grenade, Prop_Send, "m_nSolidType");
		SetEntProp(grenade, Prop_Send, "m_nSolidType", 0);
	}

	g_bHadSolidFlags[client] = HasEntProp(grenade, Prop_Data, "m_usSolidFlags");
	if (g_bHadSolidFlags[client])
	{
		g_iOldSolidFlags[client] = GetEntProp(grenade, Prop_Data, "m_usSolidFlags");
		SetEntProp(grenade, Prop_Data, "m_usSolidFlags", 0);
	}

	g_bHadCollisionGroup[client] = HasEntProp(grenade, Prop_Send, "m_CollisionGroup");
	if (g_bHadCollisionGroup[client])
	{
		g_iOldCollisionGroup[client] = GetEntProp(grenade, Prop_Send, "m_CollisionGroup");
		SetEntProp(grenade, Prop_Send, "m_CollisionGroup", 10);
	}

	SetEntityMoveType(grenade, MOVETYPE_NONE);
	UpdateHeldGrenade(client, grenade);
	DelayEquippedWeaponAttack(client);

	PrintHintText(client, "LIVE GRENADE PICKED UP!\nPRIMARY ATTACK: throw   USE: drop");

	if (g_cvDebug.BoolValue)
		LogMessage("%N picked up live grenade entity %d", client, grenade);

	return true;
}

void ReleaseGrenade(int client, bool throwGrenade)
{
	if (client < 1 || client > MaxClients)
		return;

	int grenade = EntRefToEntIndex(g_iHeldGrenade[client]);
	if (grenade == INVALID_ENT_REFERENCE || grenade <= MaxClients || !IsValidEntity(grenade))
	{
		ClearHeldState(client);
		return;
	}

	SetEntityMoveType(grenade, view_as<MoveType>(g_iOldMoveType[client]));

	if (g_bHadSolidType[client] && HasEntProp(grenade, Prop_Send, "m_nSolidType"))
		SetEntProp(grenade, Prop_Send, "m_nSolidType", g_iOldSolidType[client]);

	if (g_bHadSolidFlags[client] && HasEntProp(grenade, Prop_Data, "m_usSolidFlags"))
		SetEntProp(grenade, Prop_Data, "m_usSolidFlags", g_iOldSolidFlags[client]);

	if (g_bHadCollisionGroup[client] && HasEntProp(grenade, Prop_Send, "m_CollisionGroup"))
		SetEntProp(grenade, Prop_Send, "m_CollisionGroup", g_iOldCollisionGroup[client]);

	float velocity[3] = {0.0, 0.0, 0.0};

	if (throwGrenade && IsClientInGame(client) && IsPlayerAlive(client))
	{
		float eyePos[3], eyeAngles[3], vecForward[3], throwPos[3], playerVelocity[3];
		GetClientEyePosition(client, eyePos);
		GetClientEyeAngles(client, eyeAngles);
		GetAngleVectors(eyeAngles, vecForward, NULL_VECTOR, NULL_VECTOR);

		throwPos[0] = eyePos[0] + vecForward[0] * 32.0;
		throwPos[1] = eyePos[1] + vecForward[1] * 32.0;
		throwPos[2] = eyePos[2] + vecForward[2] * 32.0 - 6.0;

		velocity[0] = vecForward[0] * g_cvThrowSpeed.FloatValue;
		velocity[1] = vecForward[1] * g_cvThrowSpeed.FloatValue;
		velocity[2] = vecForward[2] * g_cvThrowSpeed.FloatValue;

		if (HasEntProp(client, Prop_Data, "m_vecAbsVelocity"))
		{
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", playerVelocity);
			AddVectors(velocity, playerVelocity, velocity);
		}

		TeleportEntity(grenade, throwPos, NULL_VECTOR, velocity);
		PrintHintText(client, "GRENADE THROWN BACK!");

		if (g_cvDebug.BoolValue)
			LogMessage("%N threw back live grenade entity %d", client, grenade);
	}
	else
	{
		TeleportEntity(grenade, NULL_VECTOR, NULL_VECTOR, velocity);
	}

	ClearHeldState(client);
}

void UpdateHeldGrenade(int client, int grenade)
{
	float eyePos[3], eyeAngles[3], vecForward[3], right[3], up[3], holdPos[3];
	GetClientEyePosition(client, eyePos);
	GetClientEyeAngles(client, eyeAngles);
	GetAngleVectors(eyeAngles, vecForward, right, up);

	holdPos[0] = eyePos[0] + vecForward[0] * 25.0 + right[0] * 9.0 - up[0] * 8.0;
	holdPos[1] = eyePos[1] + vecForward[1] * 25.0 + right[1] * 9.0 - up[1] * 8.0;
	holdPos[2] = eyePos[2] + vecForward[2] * 25.0 + right[2] * 9.0 - up[2] * 8.0;

	float zero[3] = {0.0, 0.0, 0.0};
	TeleportEntity(grenade, holdPos, NULL_VECTOR, zero);
}

void DelayEquippedWeaponAttack(int client)
{
	float blockUntil = GetGameTime() + WEAPON_ATTACK_BLOCK_TIME;

	if (HasEntProp(client, Prop_Send, "m_flNextAttack"))
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", blockUntil);

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon > MaxClients && IsValidEntity(weapon))
	{
		if (HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack"))
			SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", blockUntil);

		if (HasEntProp(weapon, Prop_Send, "m_flNextSecondaryAttack"))
			SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", blockUntil);
	}
}

int FindPickupGrenade(int client, bool debugReport)
{
	if (g_LiveGrenades.Length == 0)
	{
		if (debugReport)
			DebugPickupMessage(client, "no tracked live M67 or F1 grenades");
		return -1;
	}

	float playerPos[3], eyePos[3], eyeAngles[3], vecForward[3];
	GetClientAbsOrigin(client, playerPos);
	GetClientEyePosition(client, eyePos);
	GetClientEyeAngles(client, eyeAngles);
	GetAngleVectors(eyeAngles, vecForward, NULL_VECTOR, NULL_VECTOR);

	float range = g_cvPickupRange.FloatValue;
	float maxDistanceSqr = range * range;
	float bestScore = -999999.0;
	int bestGrenade = -1;
	bool rejectionReported = false;

	for (int i = g_LiveGrenades.Length - 1; i >= 0; i--)
	{
		int entRef = g_LiveGrenades.Get(i);
		int grenade = EntRefToEntIndex(entRef);

		if (grenade == INVALID_ENT_REFERENCE || grenade <= MaxClients || !IsValidEntity(grenade))
		{
			g_LiveGrenades.Erase(i);
			continue;
		}

		char rejection[128];
		if (!ValidateThrowbackTarget(client, grenade, rejection, sizeof(rejection)))
		{
			if (debugReport)
			{
				DebugPickupRejection(client, grenade, rejection);
				rejectionReported = true;
			}
			continue;
		}

		float grenadePos[3], direction[3];
		GetEntPropVector(grenade, Prop_Data, "m_vecAbsOrigin", grenadePos);
		float distanceSqr = GetVectorDistance(playerPos, grenadePos, true);
		if (distanceSqr > maxDistanceSqr)
		{
			if (debugReport)
			{
				FormatEx(rejection, sizeof(rejection), "too far (%.1f > %.1f units)",
					SquareRoot(distanceSqr), range);
				DebugPickupRejection(client, grenade, rejection);
				rejectionReported = true;
			}
			continue;
		}

		MakeVectorFromPoints(eyePos, grenadePos, direction);
		NormalizeVector(direction, direction);
		float aim = GetVectorDotProduct(vecForward, direction);
		if (aim < 0.55)
		{
			if (debugReport)
			{
				FormatEx(rejection, sizeof(rejection), "not sufficiently aimed at (dot %.2f < 0.55)", aim);
				DebugPickupRejection(client, grenade, rejection);
				rejectionReported = true;
			}
			continue;
		}

		if (!HasLineOfSight(client, grenade, eyePos, grenadePos))
		{
			if (debugReport)
			{
				DebugPickupRejection(client, grenade, "visibility trace blocked by geometry");
				rejectionReported = true;
			}
			continue;
		}

		float score = aim * 1000.0 - SquareRoot(distanceSqr);
		if (score > bestScore)
		{
			bestScore = score;
			bestGrenade = grenade;
		}
	}

	if (bestGrenade == -1 && debugReport && !rejectionReported)
		DebugPickupMessage(client, "all tracked grenade references had already expired");

	return bestGrenade;
}

bool IsValidThrowbackTarget(int client, int grenade)
{
	char rejection[1];
	return ValidateThrowbackTarget(client, grenade, rejection, sizeof(rejection));
}

bool ValidateThrowbackTarget(int client, int grenade, char[] rejection, int rejectionLen)
{
	if (!IsThrowbackGrenade(grenade))
	{
		if (rejectionLen > 1)
			strcopy(rejection, rejectionLen, "unsupported or invalid grenade entity");
		return false;
	}

	if (IsHeldByAnotherPlayer(client, grenade))
	{
		if (rejectionLen > 1)
			strcopy(rejection, rejectionLen, "already held by another player");
		return false;
	}

	if (g_cvEnemyOnly.BoolValue)
	{
		int owner = GetGrenadeOwner(grenade);
		if (owner >= 1 && owner <= MaxClients && IsClientInGame(owner)
			&& GetClientTeam(owner) == GetClientTeam(client))
		{
			if (rejectionLen > 1)
				FormatEx(rejection, rejectionLen, "same-team grenade owned by %N; enemy-only mode is enabled", owner);
			return false;
		}
	}

	return true;
}

void DebugPickupRejection(int client, int grenade, const char[] reason)
{
	char classname[32];
	GetEntityClassname(grenade, classname, sizeof(classname));

	char message[192];
	FormatEx(message, sizeof(message), "entity %d (%s) rejected: %s", grenade, classname, reason);
	DebugPickupMessage(client, message);
}

void DebugPickupMessage(int client, const char[] message)
{
	PrintToConsole(client, "[Grenade Throwback] Pickup failed: %s", message);
	LogMessage("Pickup failed for %N: %s", client, message);
}

bool IsThrowbackGrenade(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
		return false;

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	return StrEqual(classname, "grenade_m67", false)
		|| StrEqual(classname, "grenade_f1", false);
}

bool IsHeldByAnotherPlayer(int client, int grenade)
{
	int entRef = EntIndexToEntRef(grenade);
	for (int other = 1; other <= MaxClients; other++)
	{
		if (other != client && g_iHeldGrenade[other] == entRef)
			return true;
	}

	return false;
}

void RemoveTrackedGrenade(int entity)
{
	for (int i = g_LiveGrenades.Length - 1; i >= 0; i--)
	{
		int tracked = EntRefToEntIndex(g_LiveGrenades.Get(i));
		if (tracked == INVALID_ENT_REFERENCE || tracked == entity)
			g_LiveGrenades.Erase(i);
	}
}

bool HasLineOfSight(int client, int grenade, const float start[3], const float end[3])
{
	float sightTarget[3];
	sightTarget[0] = end[0];
	sightTarget[1] = end[1];
	sightTarget[2] = end[2] + SIGHT_TARGET_Z_OFFSET;

	Handle trace = TR_TraceRayFilterEx(start, sightTarget, MASK_SOLID, RayType_EndPoint, TraceFilter_IgnoreClient, client);
	bool visible = !TR_DidHit(trace) || TR_GetEntityIndex(trace) == grenade;

	if (!visible)
	{
		float traceEnd[3];
		TR_GetEndPosition(traceEnd, trace);
		visible = GetVectorDistance(traceEnd, sightTarget) <= SIGHT_END_TOLERANCE;
	}

	delete trace;
	return visible;
}

public bool TraceFilter_IgnoreClient(int entity, int contentsMask, any client)
{
	return entity != client;
}

int GetGrenadeOwner(int grenade)
{
	if (HasEntProp(grenade, Prop_Send, "m_hThrower"))
	{
		int thrower = GetEntPropEnt(grenade, Prop_Send, "m_hThrower");
		if (thrower >= 1 && thrower <= MaxClients)
			return thrower;
	}

	if (HasEntProp(grenade, Prop_Data, "m_hThrower"))
	{
		int thrower = GetEntPropEnt(grenade, Prop_Data, "m_hThrower");
		if (thrower >= 1 && thrower <= MaxClients)
			return thrower;
	}

	if (HasEntProp(grenade, Prop_Send, "m_hOwnerEntity"))
		return GetEntPropEnt(grenade, Prop_Send, "m_hOwnerEntity");

	if (HasEntProp(grenade, Prop_Data, "m_hOwnerEntity"))
		return GetEntPropEnt(grenade, Prop_Data, "m_hOwnerEntity");

	return -1;
}

void ResetClientState(int client)
{
	g_iHeldGrenade[client] = INVALID_ENT_REFERENCE;
	g_iLastButtons[client] = 0;
	g_fNextPickupAttempt[client] = 0.0;
	g_fNextDebugReport[client] = 0.0;
	g_iOldMoveType[client] = view_as<int>(MOVETYPE_VPHYSICS);
	g_iOldSolidType[client] = 0;
	g_iOldSolidFlags[client] = 0;
	g_iOldCollisionGroup[client] = 0;
	g_bHadSolidType[client] = false;
	g_bHadSolidFlags[client] = false;
	g_bHadCollisionGroup[client] = false;
	g_bBlockAttackUntilRelease[client] = false;
}

void ClearHeldState(int client)
{
	g_iHeldGrenade[client] = INVALID_ENT_REFERENCE;
	g_iOldMoveType[client] = view_as<int>(MOVETYPE_VPHYSICS);
	g_bHadSolidType[client] = false;
	g_bHadSolidFlags[client] = false;
	g_bHadCollisionGroup[client] = false;
}
