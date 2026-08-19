//	Stock by Guren  https://forums.alliedmods.net/showthread.php?t=210080
//
//	New syntax by Franc1sco https://github.com/Franc1sco/aimbot/blob/master/scripting/aimbot.sp
//
//	Model by aus1271 https://steamcommunity.com/sharedfiles/filedetails/?id=486623714
//
//	Idea by Circleus
//
//	https://forums.alliedmods.net/showthread.php?t=298332

// Integrated bot_spawnprotection with this plugin to save resources

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
//#include <insurgencydy>

#define PLUGIN_VERSION "1.4.0"
#define BULLET_GAMEDATA_FILE "insurgency-bm.games"

static const float RICOCHET_MIN_DAMAGE = 5.0;
static const float RICOCHET_KILL_WINDOW = 0.25;
static const float RICOCHET_ORIGIN_OFFSET = 6.0;

ConVar	g_cvBotProtectionTime = null,
		g_cvBotProtectionBurn = null,
		g_cvBotProtectionFall = null,
		g_cvBotProtectionBlast = null,
		g_cvBotRiotShieldChance = null,
		g_cvBotRiotShieldMinSec = null,
		g_cvRiotShieldSprintMode = null,
		g_cvRicochetEnabled = null,
		g_cvRicochetBotShields = null,
		g_cvRicochetCloseDistance = null,
		g_cvRicochetMaxDistance = null,
		g_cvRicochetMaxAngle = null,
		g_cvRicochetDamageScale = null,
		g_cvRicochetMaxDamage = null,
		g_cvRicochetCooldown = null,
		g_cvRicochetFxCooldown = null;

Handle	g_hTEFireBullets = null,
		g_hGetWeaponDefinitionHandle = null,
		g_hGetMuzzle = null;

DynamicHook g_hAllowPlayerSprintHook = null;

int		ga_iAttackerOfShield[MAXPLAYERS + 1] = {0, ...},
		ga_iRicochetKillerUserId[MAXPLAYERS + 1] = {0, ...},
		g_iBotRiotShieldMinSec,
		g_iRiotShieldSprintMode,
		g_iSecPlayersAlive;

bool	ga_bBlacklistClass[MAXPLAYERS + 1] = {false, ...},
		g_bBotProtectionBurn,
		g_bBotProtectionFall,
		g_bBotProtectionBlast,
		g_bRicochetEnabled,
		g_bRicochetBotShields,
		g_bApplyingRicochet,
		g_bLateLoad;

float	ga_fShieldBlockTime[MAXPLAYERS + 1] = {0.0, ...},
		ga_fProtectionTimeLeft[MAXPLAYERS + 1] = {0.0, ...},
		ga_fNextRicochetTime[MAXPLAYERS + 1] = {0.0, ...},
		ga_fNextRicochetFxTime[MAXPLAYERS + 1] = {0.0, ...},
		ga_fRicochetKillExpire[MAXPLAYERS + 1] = {0.0, ...},
		g_fBotProtectionTime,
		g_fBotRiotShieldChance,
		g_fRicochetCloseDistance,
		g_fRicochetMaxDistance,
		g_fRicochetMaxAngle,
		g_fRicochetDamageScale,
		g_fRicochetMaxDamage,
		g_fRicochetCooldown,
		g_fRicochetFxCooldown;

int		g_iLastShieldBlocker = 0,
		g_iLastShieldAttacker = 0;

float	g_fLastShieldBlockTime = 0.0;

int		g_iLastShieldInflictorRef = INVALID_ENT_REFERENCE;

// ae_modern_medicbomberengineervip_default_checkpoint.theater
const int	gc_iBomber = 31,
			gc_iTank = 32;

// Some damage combos come through as large bitmasks; keep explicit constant used for tripmines here.
static const int DMG_TRIPMINE = 134217792;
static const float SHIELD_BLOCK_ANGLE_DEG = 90.0;
static const float SHIELD_CONTACT_BLOCK_DIST = 56.0;
static const float SHIELD_CONTACT_REAR_GRACE_DOT = -0.20;

public Plugin myinfo = {
	name = "riotshield",
	author = "Nullifidian, Franc1sco, Guren, Circleus, aus1271 & Codex",
	description = "riotshield & bot spawn protection",
	version = PLUGIN_VERSION,
	url = ""
};

// ---------- Small helpers ----------
static stock bool IsGoodClient(int i, bool inGame = true)
{
	if (i < 1 || i > MaxClients)
		return false;
	return (!inGame || IsClientInGame(i));
}

static stock bool IsAliveClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

// ---------- Lifecycle ----------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_Insurgency)
		SetFailState("This plugin supports Insurgency 2014 only.");

	HookEvent("round_start", Events_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("object_destroyed", Events_NoCopy, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", Events_NoCopy, EventHookMode_PostNoCopy);

	HookEvent("player_spawn", Event_PlayerSpawn_Post, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_pick_squad", Event_PlayerPickSquad_Post, EventHookMode_Post);

	GameData config = LoadGameConfigFile(BULLET_GAMEDATA_FILE);
	if (config == null)
	{
		LogError("Ricochet tracers disabled: missing gamedata addons/sourcemod/gamedata/%s.txt", BULLET_GAMEDATA_FILE);
	}
	else
	{
		g_hTEFireBullets = PrepareTEFireBullets(config);
		g_hGetWeaponDefinitionHandle = PrepareGetWeaponDefinitionHandle(config);
		g_hGetMuzzle = PrepareGetMuzzle(config);
		g_hAllowPlayerSprintHook = DHookCreate(-1, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
		if (g_hAllowPlayerSprintHook == null || !DHookSetFromConf(g_hAllowPlayerSprintHook, config, SDKConf_Virtual, "CINSWeapon::AllowPlayerSprint"))
		{
			delete g_hAllowPlayerSprintHook;
			LogError("Riot-shield sprint override disabled: could not find CINSWeapon::AllowPlayerSprint in %s.txt", BULLET_GAMEDATA_FILE);
		}
		delete config;

		if (g_hTEFireBullets == null || g_hGetWeaponDefinitionHandle == null)
			LogError("Ricochet tracers disabled: one or more safe bullet signatures failed to resolve.");
		if (g_hGetMuzzle == null)
			LogError("Ricochet muzzle targeting unavailable: falling back to the shooter's eye position.");
	}

	g_cvBotProtectionTime = CreateConVar("bot_spawnprotectiontime", "6.0", "Bot spawn protection time [0.0 - 30.0]", _, true, 0.0, true, 30.0);
	g_fBotProtectionTime = g_cvBotProtectionTime.FloatValue;
	g_cvBotProtectionTime.AddChangeHook(OnConVarChanged);

	g_cvBotProtectionBurn = CreateConVar("bot_spawnprotectionburn", "1.0", "Protection from BURN damage [0.0 = Off 1.0 = On]", _, true, 0.0, true, 1.0);
	g_bBotProtectionBurn = g_cvBotProtectionBurn.BoolValue;
	g_cvBotProtectionBurn.AddChangeHook(OnConVarChanged);

	g_cvBotProtectionFall = CreateConVar("bot_spawnprotectionfall", "1.0", "Protection from FALL damage [0.0 = Off 1.0 = On]", _, true, 0.0, true, 1.0);
	g_bBotProtectionFall = g_cvBotProtectionFall.BoolValue;
	g_cvBotProtectionFall.AddChangeHook(OnConVarChanged);

	g_cvBotProtectionBlast = CreateConVar("bot_spawnprotectionblast", "1.0", "Protection from BLAST damage [0.0 = Off 1.0 = On]", _, true, 0.0, true, 1.0);
	g_bBotProtectionBlast = g_cvBotProtectionBlast.BoolValue;
	g_cvBotProtectionBlast.AddChangeHook(OnConVarChanged);

	g_cvBotRiotShieldChance = CreateConVar("bot_riotshield", "0.015", "Chance that bot spawn with riotshield [0.0 = Off 1.0 = max]", _, true, 0.0, true, 1.0);
	g_fBotRiotShieldChance = g_cvBotRiotShieldChance.FloatValue;
	g_cvBotRiotShieldChance.AddChangeHook(OnConVarChanged);

	g_cvBotRiotShieldMinSec = CreateConVar("bot_riotshield_minplayers", "4.0", "Min. security players alive for 'bot_riotshield' to trigger", _, true, 0.0);
	g_iBotRiotShieldMinSec = g_cvBotRiotShieldMinSec.IntValue;
	g_cvBotRiotShieldMinSec.AddChangeHook(OnConVarChanged);

	g_cvRiotShieldSprintMode = CreateConVar("riotshield_sprint_mode", "0", "Allow sprinting with an active riot shield [0 = disabled, 1 = bots only, 2 = humans only, 3 = bots and humans]", _, true, 0.0, true, 3.0);
	g_iRiotShieldSprintMode = g_cvRiotShieldSprintMode.IntValue;
	g_cvRiotShieldSprintMode.AddChangeHook(OnConVarChanged);

	g_cvRicochetEnabled = CreateConVar("riotshield_ricochet_enable", "1", "Enable enemy bullet ricochets from actively held riot shields", _, true, 0.0, true, 1.0);
	g_bRicochetEnabled = g_cvRicochetEnabled.BoolValue;
	g_cvRicochetEnabled.AddChangeHook(OnConVarChanged);

	g_cvRicochetBotShields = CreateConVar("riotshield_ricochet_bot_shields", "0", "Allow shields held by bots to ricochet bullets [0 = block only, 1 = ricochet]", _, true, 0.0, true, 1.0);
	g_bRicochetBotShields = g_cvRicochetBotShields.BoolValue;
	g_cvRicochetBotShields.AddChangeHook(OnConVarChanged);

	g_cvRicochetCloseDistance = CreateConVar("riotshield_ricochet_close_distance", "400.0", "Distance where ricochets return directly toward the shooter", _, true, 0.0);
	g_fRicochetCloseDistance = g_cvRicochetCloseDistance.FloatValue;
	g_cvRicochetCloseDistance.AddChangeHook(OnConVarChanged);

	g_cvRicochetMaxDistance = CreateConVar("riotshield_ricochet_max_distance", "2000.0", "Maximum distance at which a blocked bullet can ricochet", _, true, 1.0);
	g_fRicochetMaxDistance = g_cvRicochetMaxDistance.FloatValue;
	g_cvRicochetMaxDistance.AddChangeHook(OnConVarChanged);

	g_cvRicochetMaxAngle = CreateConVar("riotshield_ricochet_max_angle", "5.0", "Maximum random ricochet cone angle at maximum distance", _, true, 0.0, true, 45.0);
	g_fRicochetMaxAngle = g_cvRicochetMaxAngle.FloatValue;
	g_cvRicochetMaxAngle.AddChangeHook(OnConVarChanged);

	g_cvRicochetDamageScale = CreateConVar("riotshield_ricochet_damage_scale", "1.0", "Fraction of the blocked bullet damage returned to its shooter", _, true, 0.0, true, 2.0);
	g_fRicochetDamageScale = g_cvRicochetDamageScale.FloatValue;
	g_cvRicochetDamageScale.AddChangeHook(OnConVarChanged);

	g_cvRicochetMaxDamage = CreateConVar("riotshield_ricochet_max_damage", "200.0", "Maximum damage from one shield ricochet", _, true, RICOCHET_MIN_DAMAGE, true, 500.0);
	g_fRicochetMaxDamage = g_cvRicochetMaxDamage.FloatValue;
	g_cvRicochetMaxDamage.AddChangeHook(OnConVarChanged);

	g_cvRicochetCooldown = CreateConVar("riotshield_ricochet_cooldown", "0.05", "Minimum time between ricochet traces for one shield", _, true, 0.01, true, 1.0);
	g_fRicochetCooldown = g_cvRicochetCooldown.FloatValue;
	g_cvRicochetCooldown.AddChangeHook(OnConVarChanged);

	g_cvRicochetFxCooldown = CreateConVar("riotshield_ricochet_fx_cooldown", "0.08", "Minimum time between visible ricochet tracers for one shield", _, true, 0.01, true, 1.0);
	g_fRicochetFxCooldown = g_cvRicochetFxCooldown.FloatValue;
	g_cvRicochetFxCooldown.AddChangeHook(OnConVarChanged);

	AutoExecConfig(true, "riotshield_botspawnprotection");
	HookExistingRiotShieldSprint();

	if (g_bLateLoad)
	{
		int iClassSlot;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsGoodClient(i, true))
				continue;

			if (IsFakeClient(i) && GetClientTeam(i) == 3)
			{
				iClassSlot = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iPlayerClass", _, i);
				if (iClassSlot == gc_iBomber || iClassSlot == gc_iTank)
				{
					ga_bBlacklistClass[i] = true;
				}
			}
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}
		g_iSecPlayersAlive = Team_CountAlivePlayers(2, true);
	}
}

public void OnPluginEnd()
{
	delete g_hTEFireBullets;
	delete g_hGetWeaponDefinitionHandle;
	delete g_hGetMuzzle;
	delete g_hAllowPlayerSprintHook;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (g_hAllowPlayerSprintHook != null && strcmp(classname, "weapon_riotshield", false) == 0)
		RequestFrame(Frame_HookRiotShieldSprint, EntIndexToEntRef(entity));
}

void Frame_HookRiotShieldSprint(any reference)
{
	int weapon = EntRefToEntIndex(reference);
	if (weapon > MaxClients && IsValidEntity(weapon))
		HookRiotShieldSprint(weapon);
}

void HookExistingRiotShieldSprint()
{
	if (g_hAllowPlayerSprintHook == null)
		return;

	char classname[64];
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
	{
		if (!IsValidEntity(entity))
			continue;

		GetEntityClassname(entity, classname, sizeof(classname));
		if (strcmp(classname, "weapon_riotshield", false) == 0)
			HookRiotShieldSprint(entity);
	}
}

void HookRiotShieldSprint(int weapon)
{
	int hookID = DHookEntity(g_hAllowPlayerSprintHook, true, weapon, INVALID_FUNCTION, Detour_AllowPlayerSprint_Post);
	if (hookID == INVALID_HOOK_ID)
		LogError("Could not hook riot-shield sprint check for entity %d.", weapon);
}

public MRESReturn Detour_AllowPlayerSprint_Post(int weapon, DHookReturn hReturn, DHookParam hParams)
{
	if (g_iRiotShieldSprintMode == 0)
		return MRES_Ignored;

	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	if (!IsAliveClient(owner) || GetEntPropEnt(owner, Prop_Send, "m_hActiveWeapon") != weapon)
		return MRES_Ignored;

	bool isBot = IsFakeClient(owner);
	if ((isBot && (g_iRiotShieldSprintMode & 1) == 0) || (!isBot && (g_iRiotShieldSprintMode & 2) == 0))
		return MRES_Ignored;

	hReturn.Value = true;
	return MRES_Override;
}

public void OnMapStart()
{
	for (int client = 1; client <= MaxClients; client++)
		ResetRicochetState(client);

	char sBuffer[64];
	for (int i = 1; i <= 5; i++)
	{
		FormatEx(sBuffer, sizeof sBuffer, "riotshield/bullet_impact/impact_riotshield_0%d.wav", i);
		PrecacheSound(sBuffer);
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (IsGoodClient(client, true))
	{
		ResetRicochetState(client);
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public void OnClientDisconnect(int client)
{
	if (!IsGoodClient(client, false))
		return;

	// Clean per-client state to avoid stale matches
	ga_iAttackerOfShield[client] = 0;
	ga_fShieldBlockTime[client] = 0.0;
	ga_fProtectionTimeLeft[client] = 0.0;
	ga_bBlacklistClass[client] = false;
	ResetRicochetState(client);

	if (g_iLastShieldBlocker == client || g_iLastShieldAttacker == client) {
		g_iLastShieldBlocker = 0;
		g_iLastShieldAttacker = 0;
		g_fLastShieldBlockTime = 0.0;
		g_iLastShieldInflictorRef = INVALID_ENT_REFERENCE;
	}

	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// ---------- Events ----------
public void Events_NoCopy(Event event, char[] name, bool dontBroadcast)
{
	g_iSecPlayersAlive = Team_CountAlivePlayers(2, true);
}

public Action Event_PlayerPickSquad_Post(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsGoodClient(client, true) && IsFakeClient(client) && GetClientTeam(client) == 3)
	{
		char sClass[64];
		event.GetString("class_template", sClass, sizeof sClass);
		ga_bBlacklistClass[client] = (StrContains(sClass, "bomber", false) > -1) || (StrContains(sClass, "tank", false) > -1);
	}
	return Plugin_Continue;
}

public Action Event_PlayerSpawn_Post(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsGoodClient(client, true) || !IsFakeClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	// Spawn protection window
	if (g_fBotProtectionTime > 0.0)
	{
		ga_fProtectionTimeLeft[client] = GetGameTime() + g_fBotProtectionTime;
	}
	else
	{
		ga_fProtectionTimeLeft[client] = 0.0;
	}

	// FIX: trigger only when Security alive >= min (previous code used reversed '<' logic)
	if (g_fBotRiotShieldChance <= 0.0 || g_iSecPlayersAlive < g_iBotRiotShieldMinSec || ga_bBlacklistClass[client])
		return Plugin_Continue;

	if (GetRandomFloat(0.0, 1.0) <= g_fBotRiotShieldChance)
	{
		// Sturdier weapon strip: remove multiple slots safely (avoid stale indices)
		for (int s = 0; s <= 5; s++)
		{
			int wep;
			while ((wep = GetPlayerWeaponSlot(client, s)) != -1)
			{
				if (!IsValidEntity(wep))
					break;

				RemovePlayerItem(client, wep);
				SafeKillIdx(wep);
			}
		}
		GivePlayerItem(client, "weapon_riotshield");
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsGoodClient(victim, true))
		return Plugin_Continue;

	Action result = Plugin_Continue;
	int killerUserId = ga_iRicochetKillerUserId[victim];
	if (killerUserId > 0
		&& ga_fRicochetKillExpire[victim] >= GetGameTime()
		&& event.GetInt("attacker") == killerUserId)
	{
		int killer = GetClientOfUserId(killerUserId);
		if (IsGoodClient(killer, true) && killer != victim)
		{
			// Keep Insurgency's original attacker and weapon fields so this death
			// follows the existing riot-shield weapon tracking.
			result = Plugin_Continue;
		}
	}
	ga_iRicochetKillerUserId[victim] = 0;
	ga_fRicochetKillExpire[victim] = 0.0;

	if (!IsFakeClient(victim))
		return result;

	// Clear spawn protection and any recent shield state
	ga_fProtectionTimeLeft[victim] = 0.0;
	ga_fShieldBlockTime[victim] = 0.0;
	ga_iAttackerOfShield[victim] = 0;

	if (g_iLastShieldBlocker == victim || g_iLastShieldAttacker == victim) {
		g_iLastShieldBlocker = 0;
		g_iLastShieldAttacker = 0;
		g_fLastShieldBlockTime = 0.0;
		g_iLastShieldInflictorRef = INVALID_ENT_REFERENCE;
	}

	return result;
}

// ---------- Damage ----------
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype,
	int &weapon, float damageForce[3], float damagePosition[3])
{
	if (g_bApplyingRicochet)
		return Plugin_Continue;

	if (!IsAliveClient(victim) || victim == attacker)
		return Plugin_Continue;

	// --- Bot spawn protection (use bitwise checks instead of equality) ---
	if (IsFakeClient(victim))
	{
		bool bIsBlast = (damagetype & DMG_BLAST) != 0;
		bool bIsBurn  = (damagetype & DMG_BURN) != 0 || (damagetype & DMG_DIRECT) != 0;
		bool bIsFall  = (damagetype & DMG_FALL) != 0;
		bool bIsTrip  = (damagetype == DMG_TRIPMINE); // keep exact match for this special case

		if (ga_fProtectionTimeLeft[victim] > GetGameTime())
		{
			if ((bIsBlast && g_bBotProtectionBlast)
			 || (bIsBurn  && g_bBotProtectionBurn)
			 || (bIsFall  && g_bBotProtectionFall)
			 || bIsTrip)
			{
				return Plugin_Handled;
			}
		}
		else
		{
			ga_fProtectionTimeLeft[victim] = 0.0;
		}
	}

	// Past this point we care about attacker only if it is a valid client
	if (!IsGoodClient(attacker, true))
		return Plugin_Continue;

	float fNow = GetGameTime();

	bool bIsBullet = ((damagetype & DMG_BULLET) != 0) || ((damagetype & DMG_BUCKSHOT) != 0);
	float fTick = GetTickInterval();

	// If victim is actively holding a riot shield and the damage source is in front arc, block the hit.
	int iWeaponVictim = GetEntPropEnt(victim, Prop_Data, "m_hActiveWeapon");
	if (iWeaponVictim > 0)
	{
		char sWeaponVictim[32];
		GetEntityClassname(iWeaponVictim, sWeaponVictim, sizeof sWeaponVictim);

		// Require shield up and in front arc
		if (strcmp(sWeaponVictim, "weapon_riotshield", false) == 0)
		{
			float vSrc[3];
			GetDamageSourcePos(attacker, inflictor, bIsBullet, vSrc);
			if (IsShieldBlockingSource(victim, vSrc))
			{
				int iWepOfAttacker = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");

				if (iWepOfAttacker > 0)
				{
					char sWeaponAttacker[32];
					GetEntityClassname(iWepOfAttacker, sWeaponAttacker, sizeof sWeaponAttacker);

					// Let M107 punch through (only meaningful for hitscan)
					if (bIsBullet && strcmp(sWeaponAttacker, "weapon_M107", false) == 0)
						return Plugin_Continue;

					// Record that this attack was just blocked by a shield (to protect allies behind)
					ga_fShieldBlockTime[victim] = fNow;
					ga_iAttackerOfShield[victim] = attacker;
					g_iLastShieldBlocker = victim;
					g_iLastShieldAttacker = attacker;
					g_fLastShieldBlockTime = fNow;
					g_iLastShieldInflictorRef = INVALID_ENT_REFERENCE;
					if (inflictor > MaxClients && IsValidEntity(inflictor))
						g_iLastShieldInflictorRef = EntIndexToEntRef(inflictor);

					if (bIsBullet)
					{
						char sBuffer[64];
						FormatEx(sBuffer, sizeof sBuffer, "riotshield/bullet_impact/impact_riotshield_0%d.wav", GetRandomInt(1, 5));
						EmitSoundToAll(sBuffer, iWeaponVictim, SNDCHAN_WEAPON, _, _, 1.0);
						TryShieldRicochet(victim, attacker, iWepOfAttacker, damage, damagePosition);
					}
					return Plugin_Handled;
				}
			}
		}
	}

	// --- Block damage that would have hit a teammate standing behind a shield that just blocked this same attacker ---
	if (g_iLastShieldBlocker > 0 && g_iLastShieldAttacker == attacker && (fNow - g_fLastShieldBlockTime) <= fTick)
	{
		float vSrc[3];
		GetDamageSourcePos(attacker, inflictor, bIsBullet, vSrc);

		int curInfRef = INVALID_ENT_REFERENCE;
		if (inflictor > MaxClients && IsValidEntity(inflictor))
			curInfRef = EntIndexToEntRef(inflictor);
		if (g_iLastShieldInflictorRef != INVALID_ENT_REFERENCE && curInfRef != g_iLastShieldInflictorRef)
			return Plugin_Continue;

		int iFriendlyShield = g_iLastShieldBlocker;
		if (IsGoodClient(iFriendlyShield, true) && iFriendlyShield != victim && GetClientTeam(iFriendlyShield) == GetClientTeam(victim))
		{
			float vVictim[3], vShield[3];
			GetClientAbsOrigin(victim, vVictim);
			GetClientAbsOrigin(iFriendlyShield, vShield);

			float vDirVictim[3], vDirShield[3];
			MakeVectorFromPoints(vSrc, vVictim, vDirVictim);
			MakeVectorFromPoints(vSrc, vShield, vDirShield);

			float distVictim = GetVectorLength(vDirVictim);
			float distShield = GetVectorLength(vDirShield);
			if (distVictim > 0.0 && distShield > 0.0)
			{
				NormalizeVector(vDirVictim, vDirVictim);
				NormalizeVector(vDirShield, vDirShield);

				// Require the shield to be broadly on the same ray from attacker, and closer than the victim.
				if (GetVectorDotProduct(vDirVictim, vDirShield) >= 0.95 && distVictim > distShield)
					return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

// ---------- Ricochet ----------

static Handle PrepareTEFireBullets(GameData config)
{
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "TE_FireBullets"))
		return null;

	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	return EndPrepSDKCall();
}

static Handle PrepareGetWeaponDefinitionHandle(GameData config)
{
	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CINSWeapon::GetWeaponDefinitionHandle"))
		return null;

	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	return EndPrepSDKCall();
}

static Handle PrepareGetMuzzle(GameData config)
{
	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CINSPlayer::GetMuzzle"))
		return null;

	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	return EndPrepSDKCall();
}

static void ResetRicochetState(int client)
{
	ga_fNextRicochetTime[client] = 0.0;
	ga_fNextRicochetFxTime[client] = 0.0;
	ga_iRicochetKillerUserId[client] = 0;
	ga_fRicochetKillExpire[client] = 0.0;
}

static void TryShieldRicochet(int shieldBearer, int shooter, int shooterWeapon,
	float blockedDamage, const float damagePosition[3])
{
	if (!g_bRicochetEnabled || !IsAliveClient(shieldBearer) || !IsAliveClient(shooter))
		return;
	if (!g_bRicochetBotShields && IsFakeClient(shieldBearer))
		return;

	int shieldTeam = GetClientTeam(shieldBearer);
	int shooterTeam = GetClientTeam(shooter);
	if (shieldTeam < 2 || shooterTeam < 2 || shieldTeam == shooterTeam)
		return;

	float now = GetGameTime();
	if (now < ga_fNextRicochetTime[shieldBearer])
		return;

	float origin[3], direction[3], distance;
	GetRicochetImpactPosition(shieldBearer, damagePosition, origin);
	if (!BuildRicochetDirection(origin, shooter, direction, distance))
		return;

	ga_fNextRicochetTime[shieldBearer] = now + g_fRicochetCooldown;

	float traceOrigin[3];
	traceOrigin[0] = origin[0] + direction[0] * RICOCHET_ORIGIN_OFFSET;
	traceOrigin[1] = origin[1] + direction[1] * RICOCHET_ORIGIN_OFFSET;
	traceOrigin[2] = origin[2] + direction[2] * RICOCHET_ORIGIN_OFFSET;

	float endPosition[3];
	endPosition[0] = traceOrigin[0] + direction[0] * g_fRicochetMaxDistance;
	endPosition[1] = traceOrigin[1] + direction[1] * g_fRicochetMaxDistance;
	endPosition[2] = traceOrigin[2] + direction[2] * g_fRicochetMaxDistance;

	Handle trace = TR_TraceRayFilterEx(traceOrigin, endPosition, MASK_SHOT,
		RayType_EndPoint, TraceFilter_IgnoreShieldBearer, shieldBearer);
	if (trace == null)
		return;

	bool didHit = TR_DidHit(trace);
	int hitEntity = didHit ? TR_GetEntityIndex(trace) : -1;
	float hitPosition[3];
	if (didHit)
		TR_GetEndPosition(hitPosition, trace);
	else
	{
		hitPosition[0] = endPosition[0];
		hitPosition[1] = endPosition[1];
		hitPosition[2] = endPosition[2];
	}
	delete trace;

	if (now >= ga_fNextRicochetFxTime[shieldBearer])
	{
		EmitRicochetEffect(shieldBearer, shooterWeapon, traceOrigin, direction);
		ga_fNextRicochetFxTime[shieldBearer] = now + g_fRicochetFxCooldown;
	}

	// The original shooter stays eligible. A different first hit can only be an enemy bot.
	if (!IsAliveClient(hitEntity) || GetClientTeam(hitEntity) == shieldTeam)
		return;
	if (hitEntity != shooter && !IsFakeClient(hitEntity))
		return;
	if (g_fRicochetDamageScale <= 0.0)
		return;
	int ricochetTarget = hitEntity;

	float reflectedDamage = blockedDamage * g_fRicochetDamageScale;
	if (reflectedDamage < RICOCHET_MIN_DAMAGE)
		reflectedDamage = RICOCHET_MIN_DAMAGE;
	if (reflectedDamage > g_fRicochetMaxDamage)
		reflectedDamage = g_fRicochetMaxDamage;

	float reflectedForce[3];
	reflectedForce[0] = direction[0] * reflectedDamage * 40.0;
	reflectedForce[1] = direction[1] * reflectedDamage * 40.0;
	reflectedForce[2] = direction[2] * reflectedDamage * 40.0;

	ga_iRicochetKillerUserId[ricochetTarget] = GetClientUserId(shieldBearer);
	ga_fRicochetKillExpire[ricochetTarget] = now + RICOCHET_KILL_WINDOW;
	CreateTimer(RICOCHET_KILL_WINDOW, Timer_ClearRicochetMarker,
		GetClientUserId(ricochetTarget), TIMER_FLAG_NO_MAPCHANGE);

	g_bApplyingRicochet = true;
	SDKHooks_TakeDamage(ricochetTarget, shieldBearer, shieldBearer, reflectedDamage, DMG_BULLET,
		-1, reflectedForce, hitPosition, false);
	g_bApplyingRicochet = false;
}

public Action Timer_ClearRicochetMarker(Handle timer, any victimUserId)
{
	int victim = GetClientOfUserId(victimUserId);
	if (IsGoodClient(victim, true) && ga_fRicochetKillExpire[victim] <= GetGameTime())
	{
		ga_iRicochetKillerUserId[victim] = 0;
		ga_fRicochetKillExpire[victim] = 0.0;
	}
	return Plugin_Stop;
}

static void GetRicochetImpactPosition(int shieldBearer, const float damagePosition[3], float outPosition[3])
{
	float eyePosition[3];
	GetClientEyePosition(shieldBearer, eyePosition);

	bool nonZero = FloatAbs(damagePosition[0]) > 0.001
		|| FloatAbs(damagePosition[1]) > 0.001
		|| FloatAbs(damagePosition[2]) > 0.001;

	if (nonZero && GetVectorDistance(eyePosition, damagePosition) <= 128.0)
	{
		outPosition[0] = damagePosition[0];
		outPosition[1] = damagePosition[1];
		outPosition[2] = damagePosition[2];
		return;
	}

	float vForward[3];
	GetClientForwardVector(shieldBearer, vForward);
	outPosition[0] = eyePosition[0] + vForward[0] * 24.0;
	outPosition[1] = eyePosition[1] + vForward[1] * 24.0;
	outPosition[2] = eyePosition[2] + vForward[2] * 24.0 - 8.0;
}

static bool BuildRicochetDirection(const float origin[3], int shooter, float direction[3], float &distance)
{
	float shooterMuzzle[3];
	GetRicochetTargetPosition(shooter, shooterMuzzle);
	MakeVectorFromPoints(origin, shooterMuzzle, direction);
	distance = GetVectorLength(direction);
	if (distance <= 0.001 || distance > g_fRicochetMaxDistance)
		return false;

	NormalizeVector(direction, direction);

	float coneAngle = 0.0;
	if (distance > g_fRicochetCloseDistance && g_fRicochetMaxAngle > 0.0)
	{
		float angleRange = g_fRicochetMaxDistance - g_fRicochetCloseDistance;
		if (angleRange > 0.001)
		{
			float fraction = (distance - g_fRicochetCloseDistance) / angleRange;
			if (fraction > 1.0)
				fraction = 1.0;
			coneAngle = g_fRicochetMaxAngle * fraction;
		}
		else
		{
			coneAngle = g_fRicochetMaxAngle;
		}
	}

	if (coneAngle <= 0.0)
		return true;

	// Sample a circular cone instead of independent square pitch/yaw offsets.
	float reference[3] = {0.0, 0.0, 1.0};
	if (FloatAbs(direction[2]) > 0.98)
	{
		reference[0] = 0.0;
		reference[1] = 1.0;
		reference[2] = 0.0;
	}

	float right[3], up[3];
	GetVectorCrossProduct(direction, reference, right);
	NormalizeVector(right, right);
	GetVectorCrossProduct(right, direction, up);
	NormalizeVector(up, up);

	float sampledAngle = DegToRad(coneAngle * SquareRoot(GetRandomFloat(0.0, 1.0)));
	float azimuth = GetRandomFloat(0.0, 2.0 * FLOAT_PI);
	float forwardScale = Cosine(sampledAngle);
	float radialScale = Sine(sampledAngle);
	float rightScale = radialScale * Cosine(azimuth);
	float upScale = radialScale * Sine(azimuth);

	direction[0] = direction[0] * forwardScale + right[0] * rightScale + up[0] * upScale;
	direction[1] = direction[1] * forwardScale + right[1] * rightScale + up[1] * upScale;
	direction[2] = direction[2] * forwardScale + right[2] * rightScale + up[2] * upScale;
	NormalizeVector(direction, direction);
	return true;
}

static void GetRicochetTargetPosition(int shooter, float outPosition[3])
{
	if (g_hGetMuzzle != null)
	{
		float muzzleAngles[3], shooterOrigin[3];
		SDKCall(g_hGetMuzzle, shooter, outPosition, muzzleAngles);
		GetClientAbsOrigin(shooter, shooterOrigin);
		if (GetVectorDistance(outPosition, shooterOrigin) <= 128.0)
			return;
	}

	GetClientEyePosition(shooter, outPosition);
}

static void EmitRicochetEffect(int shieldBearer, int shooterWeapon, const float origin[3], const float direction[3])
{
	if (g_hTEFireBullets == null || g_hGetWeaponDefinitionHandle == null
		|| shooterWeapon <= MaxClients || !IsValidEntity(shooterWeapon))
		return;

	if (!HasEntProp(shooterWeapon, Prop_Send, "m_iActiveFiremode")
		|| !HasEntProp(shooterWeapon, Prop_Data, "m_iPrimaryAmmoType"))
		return;

	int weaponDefinition = SDKCall(g_hGetWeaponDefinitionHandle, shooterWeapon);
	int ammoIndex = GetEntProp(shooterWeapon, Prop_Data, "m_iPrimaryAmmoType");
	if (weaponDefinition < 0 || ammoIndex < 0)
		return;

	float spread[3] = {0.0, 0.0, 0.0};
	int seed = GetURandomInt() & 0xFF;
	SDKCall(g_hTEFireBullets, shieldBearer, origin, direction, spread, 1.0,
		weaponDefinition, ammoIndex, 0, seed);
}

public bool TraceFilter_IgnoreShieldBearer(int entity, int contentsMask, any data)
{
	return entity != data;
}

// ---------- Geometry ----------

static void GetDamageSourcePos(int attacker, int inflictor, bool hitscan, float outPos[3])
{
	// For hitscan (bullets/buckshot), using attacker eye pos is more reliable than the weapon entity origin.
	if (hitscan && IsGoodClient(attacker, true))
	{
		GetClientEyePosition(attacker, outPos);
		return;
	}

	// For projectiles/explosions, prefer the inflictor entity origin (grenade/rocket/etc.)
	if (inflictor > MaxClients && IsValidEntity(inflictor))
	{
		if (HasEntProp(inflictor, Prop_Send, "m_vecOrigin"))
			GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", outPos);
		else if (HasEntProp(inflictor, Prop_Data, "m_vecAbsOrigin"))
			GetEntPropVector(inflictor, Prop_Data, "m_vecAbsOrigin", outPos);
		else if (IsGoodClient(attacker, true))
			GetClientAbsOrigin(attacker, outPos);
		else
			outPos[0] = outPos[1] = outPos[2] = 0.0;
		return;
	}

	if (IsGoodClient(attacker, true))
		GetClientAbsOrigin(attacker, outPos);
	else
		outPos[0] = outPos[1] = outPos[2] = 0.0;
}

static bool IsShieldBlockingSource(int client, const float vPoint[3])
{
	if (IsPointInSightRange(client, vPoint, SHIELD_BLOCK_ANGLE_DEG))
		return true;

	float vEye[3], vToPoint[3];
	GetClientEyePosition(client, vEye);
	MakeVectorFromPoints(vEye, vPoint, vToPoint);

	float distance = GetVectorLength(vToPoint);
	if (distance <= SHIELD_CONTACT_BLOCK_DIST)
	{
		float vForward[3];
		GetClientForwardVector(client, vForward);

		if (distance <= 0.001)
			return true;

		NormalizeVector(vToPoint, vToPoint);
		return GetVectorDotProduct(vToPoint, vForward) >= SHIELD_CONTACT_REAR_GRACE_DOT;
	}

	return false;
}

static bool IsPointInSightRange(int client, const float vPoint[3], float angle = 90.0, float distance = 0.0, bool heightcheck = true, bool negativeangle = false)
{
	if (angle > 360.0)
		angle = 360.0;
	if (angle < 0.0)
		return false;

	float vClient[3], vFwd[3], vToPoint[3];
	float ang[3];
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, vFwd, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(vFwd, vFwd);
	if (negativeangle)
		NegateVector(vFwd);

	GetClientEyePosition(client, vClient);

	float resultdistance = 0.0;
	if (heightcheck && distance > 0.0)
		resultdistance = GetVectorDistance(vClient, vPoint);

	MakeVectorFromPoints(vClient, vPoint, vToPoint);
	float vecLen = GetVectorLength(vToPoint);
	if (vecLen <= 0.001)
		return true;
	NormalizeVector(vToPoint, vToPoint);

	float dot = GetVectorDotProduct(vToPoint, vFwd);
	if (dot > 1.0)
		dot = 1.0;
	else if (dot < -1.0)
		dot = -1.0;

	float resultangle = RadToDeg(ArcCosine(dot));
	if (resultangle > (angle * 0.5))
		return false;

	if (distance > 0.0)
	{
		if (!heightcheck)
			resultdistance = GetVectorDistance(vClient, vPoint);
		return (distance >= resultdistance);
	}

	return true;
}

static void GetClientForwardVector(int client, float vForward[3])
{
	float ang[3];
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, vForward, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(vForward, vForward);
}

stock int Team_CountAlivePlayers(int team, bool ignorebots)
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) != team || !IsPlayerAlive(i))
			continue;
		if (ignorebots && IsFakeClient(i))
			continue;
		count++;
	}
	return count;
}

stock void SafeKillIdx(int ent) {
	if (ent <= MaxClients) return;
	int ref = EntIndexToEntRef(ent);
	if (ref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, ref);
}

stock void SafeKillRef(int entref) {
	if (entref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, entref);
}

stock void NF_KillEntity(any entref) {
	int ent = EntRefToEntIndex(entref);
	if (ent <= MaxClients || !IsValidEntity(ent)) return;

	if (!AcceptEntityInput(ent, "Kill"))
		RemoveEntity(ent);
}

// ---------- ConVars ----------
void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_cvBotProtectionTime)
	{
		g_fBotProtectionTime = g_cvBotProtectionTime.FloatValue;
	}
	else if (convar == g_cvBotProtectionBurn)
	{
		g_bBotProtectionBurn = g_cvBotProtectionBurn.BoolValue;
	}
	else if (convar == g_cvBotProtectionFall)
	{
		g_bBotProtectionFall = g_cvBotProtectionFall.BoolValue;
	}
	else if (convar == g_cvBotProtectionBlast)
	{
		g_bBotProtectionBlast = g_cvBotProtectionBlast.BoolValue;
	}
	else if (convar == g_cvBotRiotShieldChance)
	{
		g_fBotRiotShieldChance = g_cvBotRiotShieldChance.FloatValue;
	}
	else if (convar == g_cvBotRiotShieldMinSec)
	{
		g_iBotRiotShieldMinSec = g_cvBotRiotShieldMinSec.IntValue;
		g_iSecPlayersAlive = Team_CountAlivePlayers(2, true);
	}
	else if (convar == g_cvRicochetEnabled)
	{
		g_bRicochetEnabled = g_cvRicochetEnabled.BoolValue;
	}
	else if (convar == g_cvRicochetBotShields)
	{
		g_bRicochetBotShields = g_cvRicochetBotShields.BoolValue;
	}
	else if (convar == g_cvRicochetCloseDistance)
	{
		g_fRicochetCloseDistance = g_cvRicochetCloseDistance.FloatValue;
	}
	else if (convar == g_cvRicochetMaxDistance)
	{
		g_fRicochetMaxDistance = g_cvRicochetMaxDistance.FloatValue;
	}
	else if (convar == g_cvRicochetMaxAngle)
	{
		g_fRicochetMaxAngle = g_cvRicochetMaxAngle.FloatValue;
	}
	else if (convar == g_cvRicochetDamageScale)
	{
		g_fRicochetDamageScale = g_cvRicochetDamageScale.FloatValue;
	}
	else if (convar == g_cvRicochetMaxDamage)
	{
		g_fRicochetMaxDamage = g_cvRicochetMaxDamage.FloatValue;
	}
	else if (convar == g_cvRicochetCooldown)
	{
		g_fRicochetCooldown = g_cvRicochetCooldown.FloatValue;
	}
	else if (convar == g_cvRicochetFxCooldown)
	{
		g_fRicochetFxCooldown = g_cvRicochetFxCooldown.FloatValue;
	}
	else if (convar == g_cvRiotShieldSprintMode)
	g_iRiotShieldSprintMode = g_cvRiotShieldSprintMode.IntValue;
}
