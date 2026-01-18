#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION		"3.6"

#define MAXENTITIES			2048
#define ENTIDX_OK(%1)	((%1) > 0 && (%1) <= MAXENTITIES)

#define PF_BUYZONE			(1 << 7)
#define DAMAGE_NO			0
#define DAMAGE_EVENTS_ONLY	1
#define DAMAGE_YES			2
#define DAMAGE_AIM			3
#define OBS_MODE_ROAMING	6
#define MINE_DEATH_WINDOW	0.02
#define HUMAN_NEAR_DIST		650.0

char g_sModelMine[] = "models/static_props/wcache_landmine_01.mdl";
char g_sSoundDetonate[] = "weapons/m67/m67_detonate.wav";
char g_sSoundBeep[] = "ui/sfx/beep2.wav";
char g_sSoundDefuse[] = "physics/metal/solidmetal_impact_soft_01.wav";
char g_sSoundFound[] = "player/voice/botsurvival/leader/heard14.ogg";
char g_sSoundStepOnMine[] = "player/voice/botsurvival/subordinate/heard8.ogg";
char g_sSoundStepOnMineArm[] = "weapons/m67/handling/m67_spooneject.wav";
char g_sSoundHelp[] = "player/voice/responses/security/subordinate/suppressed/suppressed9.ogg";
char g_sSoundPlant[] = "player/voice/responses/insurgent/subordinate/unsuppressed/c4planted4.ogg";

float g_fMineBreakTime;
float g_fTimerMin;
float g_fTimerMax;
float g_fHelpChance;
float ga_fDetectorSoundCooldown[MAXPLAYERS + 1] = {0.0, ...};
float ga_fPlayerOrgSpeed[MAXPLAYERS + 1] = {1.0, ...};
float ga_fMineSoundCooldown[MAXENTITIES + 1] = {0.0, ...};
float ga_fPlayerVoiceCooldown[MAXPLAYERS + 1] = {0.0, ...};
float g_fAliveTime;
float ga_fMineLastPos[MAXENTITIES + 1][3];

int g_iRoundStatus = 0;
int g_iMaxMines;
int g_iTriggeredMines = 0;

int ga_iMineToView[MAXPLAYERS + 1] = {-1, ...};
int ga_iConfirmedMisc[MAXPLAYERS + 1] = {-1, ...};
int g_iDamage;
int g_iRadius;
int ga_iDefuseCount[MAXPLAYERS + 1] = {0, ...};
int ga_iDestroyCount[MAXPLAYERS + 1] = {0, ...};
int ga_iDeathCount[MAXPLAYERS + 1] = {0, ...};
int ga_iTouchedBy[MAXENTITIES + 1] = {0, ...};

bool g_bLateLoad;
bool g_bTimerOn;
bool ga_bPlayerHooked[MAXPLAYERS + 1] = {false, ...};
bool ga_bAutoViewMine[MAXPLAYERS + 1] = {false, ...};

ArrayList ga_hMines;

ConVar g_cvMaxMines = null;
ConVar g_cvAliveTime = null;
ConVar g_cvTimerMin = null;
ConVar g_cvTimerMax = null;
ConVar g_cvDamage = null;
ConVar g_cvRadius = null;
ConVar g_cvHelpChance = null;
ConVar g_cvDetectorId = null;

int g_iDetectorId = 33;

public Plugin myinfo = {
	name = "bot_mines",
	author = "Nullifidian",
	description = "Random bots place mines every X minutes",
	version = PLUGIN_VERSION
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	ga_hMines = new ArrayList();

	g_cvMaxMines = CreateConVar("sm_botmines_max", "3", "Maximum concurrent mines allowed.", FCVAR_NONE, true, 1.0, true, 15.0);
	g_iMaxMines = g_cvMaxMines.IntValue;
	g_cvMaxMines.AddChangeHook(OnConVarChanged);

	g_cvAliveTime = CreateConVar("sm_botmines_alivetime", "6.0", "The bot must stay alive for X seconds before considering spawning mine next to him.", FCVAR_NONE, true, 0.0);
	g_fAliveTime = g_cvAliveTime.FloatValue;
	g_cvAliveTime.AddChangeHook(OnConVarChanged);

	g_cvTimerMin = CreateConVar("sm_botmines_timermin", "60.0", "Minimum possible delay before a random bot places a mine.", FCVAR_NONE, true, 30.0);
	g_fTimerMin = g_cvTimerMin.FloatValue;
	g_cvTimerMin.AddChangeHook(OnConVarChanged);

	g_cvTimerMax = CreateConVar("sm_botmines_timermax", "240.0", "Maximum possible delay before a random bot places a mine.", FCVAR_NONE, true, 60.0);
	g_fTimerMax = g_cvTimerMax.FloatValue;
	g_cvTimerMax.AddChangeHook(OnConVarChanged);

	g_cvDamage = CreateConVar("sm_botmines_damage", "250", "Explosion damage.", FCVAR_NONE, true, 100.0, true, 10000.0);
	g_iDamage = g_cvDamage.IntValue;
	g_cvDamage.AddChangeHook(OnConVarChanged);

	g_cvRadius = CreateConVar("sm_botmines_radius", "300", "Explosion radius.", FCVAR_NONE, true, 50.0, true, 10000.0);
	g_iRadius = g_cvRadius.IntValue;
	g_cvRadius.AddChangeHook(OnConVarChanged);

	g_cvHelpChance = CreateConVar("sm_botmines_help", "0.5", "Chance that mine won't explode and teammates can defuse to save the victim.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_fHelpChance = g_cvHelpChance.FloatValue;
	g_cvHelpChance.AddChangeHook(OnConVarChanged);

	g_cvDetectorId = CreateConVar("sm_botmines_detectorid", "33", "Gear ID that acts as a mine detector.", FCVAR_NONE, true, 0.0, true, 255.0);
	g_iDetectorId = g_cvDetectorId.IntValue;
	g_cvDetectorId.AddChangeHook(OnConVarChanged);

	RegAdminCmd("sm_botmine", cmd_botmine, ADMFLAG_RCON, "Spawn a mine at a random bot's location.");
	RegAdminCmd("sm_botmineview", cmd_botmineview, ADMFLAG_RCON, "While dead, teleport your view to a mine's location (repeat to show the next mine).");
	RegAdminCmd("sm_botmineautoview", cmd_botmineautoview, ADMFLAG_RCON, "While dead, automatically teleport your view to newly created mines (toggle).");

	HookEvent("player_spawn", Event_PlayerRespawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);

	AddCommandListener(CmdListener, "inventory_resupply");
	AddCommandListener(CmdListener, "inventory_confirm");

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(GetMyHandle(), sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);

	if (g_bLateLoad)
	{
		g_iRoundStatus = 1;
		StartRandomSpawnTimer();
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i)) continue;
			ConfirmEquipment(i);
		}
	}
}

public void OnMapStart()
{
	PrecacheModel(g_sModelMine, true);
	PrecacheSound(g_sSoundDetonate, true);
	PrecacheSound(g_sSoundBeep, true);
	PrecacheSound(g_sSoundDefuse, true);
	PrecacheSound(g_sSoundFound, true);
	PrecacheSound(g_sSoundStepOnMine, true);
	PrecacheSound(g_sSoundStepOnMineArm, true);
	PrecacheSound(g_sSoundHelp, true);
	PrecacheSound(g_sSoundPlant, true);

	g_bTimerOn = false;
	CreateTimer(0.1, TimerR_NearestMine, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
	if (client && !IsFakeClient(client))
	{
		if (ga_bPlayerHooked[client]) DamageHook(client, false);

		ga_iConfirmedMisc[client] = -1;
		ga_fDetectorSoundCooldown[client] = 0.0;
		ga_fPlayerVoiceCooldown[client] = 0.0;
		ga_bPlayerHooked[client] = false;

		ResetMineStats(client);
		ga_iMineToView[client] = -1;
		ga_bAutoViewMine[client] = false;

		if (g_iRoundStatus && ga_hMines.Length > 0 && g_iTriggeredMines > 0)
			RequestFrame(Frame_CheckLastManMines, 0);
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_iRoundStatus = 1;

	for (int i = 0; i < ga_hMines.Length; i++)
	{
		SafeKillRef(ga_hMines.Get(i));
	}
	ga_hMines.Clear();
	g_iTriggeredMines = 0;

	StartRandomSpawnTimer();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i)) continue;

		ResetMineStats(i);

		if (ga_bPlayerHooked[i]) DamageHook(i, false);

		if (GetEntProp(i, Prop_Send, "m_bGlowEnabled"))
			SetEntProp(i, Prop_Send, "m_bGlowEnabled", false);

		if (GetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue") == 0.0)
			SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", ga_fPlayerOrgSpeed[i]);
	}
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_iRoundStatus = 0;
	g_iTriggeredMines = 0;
	return Plugin_Continue;
}

public Action Event_PlayerRespawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client))
		ConfirmEquipment(client);

	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
	{
		if (ga_bPlayerHooked[client]) DamageHook(client, false);

		if (GetEntProp(client, Prop_Send, "m_bGlowEnabled"))
			SetEntProp(client, Prop_Send, "m_bGlowEnabled", false);

		if (g_iRoundStatus && ga_hMines.Length > 0 && g_iTriggeredMines > 0)
			RequestFrame(Frame_CheckLastManMines, 0);
	}

	if (event.GetInt("weaponid") == -1 && FloatAbs(GetGameTime() - g_fMineBreakTime) <= MINE_DEATH_WINDOW)
	{
		char sWeapon[32];
		event.GetString("weapon", sWeapon, sizeof sWeapon);
		if (strcmp(sWeapon, "prop_dynamic", false) == 0)
		{
			event.SetString("weapon", "land mine");
			if (client)
			{
				ga_iDeathCount[client]++;
				PrintMineStats(client);
			}
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public Action cmd_botmine(int client, int args)
{
	if (!g_iRoundStatus) { ReplyToCommand(client, "Wait for game round to start first"); return Plugin_Handled; }
	if (g_iMaxMines == 0) { ReplyToCommand(client, "spawning disabled: sm_botmines_max = 0"); return Plugin_Handled; }

	int userid; float pos[3];
	if (GetRandomBotSnapshot(userid, pos, true))
	{
		if (CreateMineAt(userid, pos))
		{
			int idx = GetClientOfUserId(userid);
			int emitter = (idx > 0 && IsClientInGame(idx)) ? idx : SOUND_FROM_WORLD;
			EmitSoundToAll(g_sSoundPlant, emitter, SNDCHAN_VOICE, _, _, 1.0);
			if (idx > 0) ReplyToCommand(client, "Spawned mine @ %N's location", idx);
			else ReplyToCommand(client, "Spawned mine @ bot snapshot");
			return Plugin_Handled;
		}
		ReplyToCommand(client, "\"CreateMine\" failed");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "No valid bot found");
	return Plugin_Handled;
}

public Action cmd_botmineautoview(int client, int args)
{
	if (!client) { ReplyToCommand(client, "Server console can't use this command!"); return Plugin_Handled; }
	if (!IsClientInGame(client)) return Plugin_Handled;

	if (!ga_bAutoViewMine[client])
	{
		ga_bAutoViewMine[client] = true;
		ReplyToCommand(client, "sm_botmineautoview enabled");
	}
	else
	{
		ga_bAutoViewMine[client] = false;
		ReplyToCommand(client, "sm_botmineautoview disabled");
	}
	return Plugin_Handled;
}

public Action cmd_botmineview(int client, int args)
{
	if (!client) { ReplyToCommand(client, "Server console can't use this command!"); return Plugin_Handled; }
	if (!IsClientInGame(client)) return Plugin_Handled;
	if (!g_iRoundStatus) { ReplyToCommand(client, "Wait for the game round to start first!"); return Plugin_Handled; }
	if (IsPlayerAlive(client)) { ReplyToCommand(client, "You can't view a mine while you are alive!"); return Plugin_Handled; }
	if (ga_hMines.Length == 0) { ReplyToCommand(client, "No active mine!"); return Plugin_Handled; }

	if (ga_iMineToView[client] >= ga_hMines.Length) ga_iMineToView[client] = -1;
	if (ga_iMineToView[client] + 1 != ga_hMines.Length) ga_iMineToView[client]++;
	else ga_iMineToView[client] = 0;

	int iMine = EntRefToEntIndex(ga_hMines.Get(ga_iMineToView[client]));
	if (iMine == INVALID_ENT_REFERENCE || !IsValidEntity(iMine))
	{
		ga_hMines.Erase(ga_iMineToView[client]);
		RequestFrame(Frame_botmineview, client);
		return Plugin_Handled;
	}

	if (GetEntProp(client, Prop_Send, "m_iObserverMode") != OBS_MODE_ROAMING)
		SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_ROAMING);

	SetViewOnMine(client, iMine, true);
	ReplyToCommand(client, "Mine: %d/%d Index: %d", ga_iMineToView[client] + 1, ga_hMines.Length, iMine);
	return Plugin_Handled;
}

void SetViewOnMine(int client, int mine, bool bGetPos = false, float fMinePos[3] = {0.0})
{
	if (GetEntProp(client, Prop_Send, "m_iObserverMode") != OBS_MODE_ROAMING)
		SetEntProp(client, Prop_Send, "m_iObserverMode", OBS_MODE_ROAMING);

	if (bGetPos)
		GetEntPropVector(mine, Prop_Send, "m_vecOrigin", fMinePos);

	fMinePos[2] += 40.0;
	TeleportEntity(client, fMinePos, NULL_VECTOR, NULL_VECTOR);

	float viewAngles[3];
	GetClientEyeAngles(client, viewAngles);
	viewAngles[0] = 90.0;
	TeleportEntity(client, NULL_VECTOR, viewAngles, NULL_VECTOR);
}

void Frame_botmineview(int client)
{
	cmd_botmineview(client, 0);
}

bool PosClearOfHumans(const float pos[3], float minDist)
{
	float p[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i))
			continue;

		GetClientAbsOrigin(i, p);
		if (GetVectorDistance(pos, p) < minDist)
			return false;
	}
	return true;
}

bool IsLastHumanOnTeam(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return false;

	int team = GetClientTeam(client);
	if (team <= 1)
		return false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client)
			continue;
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i))
			continue;
		if (GetClientTeam(i) != team)
			continue;
		return false;
	}
	return true;
}

bool GetRandomBotSnapshot(int &outUserid, float outPos[3], bool bCmd = false)
{
	int candidates[MAXPLAYERS + 1];
	int count = 0;
	float fBotPos[3], fPlayerPos[3];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i))
			continue;

		if (GetEntPropEnt(i, Prop_Send, "m_hGroundEntity") == -1)
			continue;

		if (!bCmd && g_fAliveTime > 0.0 && (GetGameTime() - GetEntPropFloat(i, Prop_Send, "m_flSpawnTime")) < g_fAliveTime)
			continue;

		GetClientAbsOrigin(i, fBotPos);
		bool ok = true;
		for (int j = 1; j <= MaxClients; j++)
		{
			if (!IsClientInGame(j) || IsFakeClient(j) || !IsPlayerAlive(j))
				continue;

			GetClientAbsOrigin(j, fPlayerPos);
			if (GetVectorDistance(fBotPos, fPlayerPos) < HUMAN_NEAR_DIST)
			{
				ok = false;
				break;
			}
		}

		if (!ok) continue;

		candidates[count++] = i;
	}

	if (count == 0) return false;

	int start = GetRandomInt(0, count - 1);
	for (int k = 0; k < count; k++)
	{
		int idx = candidates[(start + k) % count];
		if (!IsClientInGame(idx) || !IsFakeClient(idx) || !IsPlayerAlive(idx))
			continue;

		if (GetEntPropEnt(idx, Prop_Send, "m_hGroundEntity") == -1)
			continue;

		if (!bCmd && g_fAliveTime > 0.0 && (GetGameTime() - GetEntPropFloat(idx, Prop_Send, "m_flSpawnTime")) < g_fAliveTime)
			continue;

		GetClientAbsOrigin(idx, outPos);
		outPos[2] -= 1.0;
		outUserid = GetClientUserId(idx);
		return outUserid != 0;
	}

	return false;
}

bool CreateMineAt(int userid, const float snapPos[3])
{
	int client = GetClientOfUserId(userid);
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client)) return false;
	if (!PosClearOfHumans(snapPos, HUMAN_NEAR_DIST)) return false;

	while (ga_hMines.Length >= g_iMaxMines && g_iMaxMines != 0)
	{
		int ent = EntRefToEntIndex(ga_hMines.Get(0));
		if (ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
		{
			if (!ENTIDX_OK(ent) || !ga_iTouchedBy[ent])
				SafeKillIdx(ent);
			if (ENTIDX_OK(ent)) ga_iTouchedBy[ent] = 0;
		}
		ga_hMines.Erase(0);
	}

	int iEnt = CreateEntityByName("prop_dynamic_override");
	if (!IsValidEntity(iEnt)) return false;

	DispatchKeyValue(iEnt, "physdamagescale", "0.0");
	DispatchKeyValue(iEnt, "model", g_sModelMine);
	DispatchKeyValue(iEnt, "solid", "6");
	if (!DispatchSpawn(iEnt)) { SafeKillIdx(iEnt); return false; }

	ga_hMines.Push(EntIndexToEntRef(iEnt));
	if (ENTIDX_OK(iEnt))
	{
		ga_fMineSoundCooldown[iEnt] = 0.0;
		ga_fMineLastPos[iEnt][0] = snapPos[0];
		ga_fMineLastPos[iEnt][1] = snapPos[1];
		ga_fMineLastPos[iEnt][2] = snapPos[2];
		ga_iTouchedBy[iEnt] = 0;
	}

	SetEntProp(iEnt, Prop_Data, "m_takedamage", DAMAGE_YES);
	SetEntProp(iEnt, Prop_Data, "m_iHealth", 200);
	SetEntProp(iEnt, Prop_Data, "m_iMaxHealth", 200);

	TeleportEntity(iEnt, snapPos, NULL_VECTOR, NULL_VECTOR);

	SetEntityMoveType(iEnt, MOVETYPE_NONE);
	SetEntPropEnt(iEnt, Prop_Data, "m_hLastAttacker", client);

	char sBuffer[16];
	FormatEx(sBuffer, sizeof sBuffer, "%d", g_iRadius);
	DispatchKeyValue(iEnt, "ExplodeRadius", sBuffer);
	FormatEx(sBuffer, sizeof sBuffer, "%d", g_iDamage);
	DispatchKeyValue(iEnt, "ExplodeDamage", sBuffer);
	DispatchKeyValue(iEnt, "minhealthdmg", "25");

	SDKHook(iEnt, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	SDKHook(iEnt, SDKHook_StartTouch, Hook_StartTouch);
	HookSingleEntityOutput(iEnt, "OnBreak", Mine_OnBreak, true);

	float fClientPos[3];
	fClientPos[0] = snapPos[0];
	fClientPos[1] = snapPos[1];
	fClientPos[2] = snapPos[2];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!ga_bAutoViewMine[i]) continue;
		if (!IsClientInGame(i)) { ga_bAutoViewMine[i] = false; continue; }
		if (IsPlayerAlive(i)) continue;
		SetViewOnMine(i, iEnt, false, fClientPos);
	}

	return true;
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) 
{
	if (!ENTIDX_OK(victim)) return Plugin_Continue;

	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker) || IsFakeClient(attacker))
		return Plugin_Handled;

	if (damagetype & DMG_SLASH)
	{
		if (ga_iTouchedBy[victim] == attacker)
			return Plugin_Handled;

		if (IsValidEntity(victim))
		{
			EmitSoundToAll(g_sSoundDefuse, victim, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);

			if (ga_iTouchedBy[victim])
			{
				DamageHook(ga_iTouchedBy[victim], false);
				SetEntProp(ga_iTouchedBy[victim], Prop_Send, "m_bGlowEnabled", false);
				PrintToChatAll("\x070088cc%N\x01 saved \x070088cc%N\x01's life by defusing the mine.", attacker, ga_iTouchedBy[victim]);
			}

			SafeKillIdx(victim);
			ga_iDefuseCount[attacker]++;
			PrintMineStats(attacker);
			SendDefusedMessage(attacker);
		}
		return Plugin_Handled;
	}

	if (ga_iTouchedBy[victim]) return Plugin_Handled;

	if ((damagetype & (DMG_BULLET | DMG_BUCKSHOT)) == 0 )
		return Plugin_Handled;

	damage = 1000.0;
	return Plugin_Changed;
}

public Action Hook_StartTouch(int entity, int touch)
{
	if (!ENTIDX_OK(entity)) return Plugin_Continue;

	if (touch > 0 && touch <= MaxClients && IsClientInGame(touch) && !IsFakeClient(touch))
	{
		if (IsLastHumanOnTeam(touch))
		{
			RequestFrame(BreakNextFrame, EntIndexToEntRef(entity));
			return Plugin_Continue;
		}

		if (GetRandomFloat(0.0, 1.0) <= g_fHelpChance)
		{
			if (ENTIDX_OK(entity))
			{
				if (ga_iTouchedBy[entity] == 0)
					g_iTriggeredMines++;
				ga_iTouchedBy[entity] = touch;
			}

			ga_fPlayerOrgSpeed[touch] = GetEntPropFloat(touch, Prop_Send, "m_flLaggedMovementValue");
			SetEntPropFloat(touch, Prop_Send, "m_flLaggedMovementValue", 0.0);

			DataPack dPack;
			CreateDataTimer(0.6, Timer_EnablePlayerMovement, dPack, TIMER_FLAG_NO_MAPCHANGE);
			dPack.WriteCell(GetClientUserId(touch));
			dPack.WriteCell(EntIndexToEntRef(entity));

			PrintHintText(touch, "Don't move! You are standing on the mine!");
			EmitSoundToAll(g_sSoundStepOnMineArm, entity, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);
			EmitSoundToAll(g_sSoundStepOnMine, touch, SNDCHAN_VOICE, _, _, 1.0);

			SDKHook(entity, SDKHook_EndTouch, Hook_EndTouch);
			SDKUnhook(entity, SDKHook_StartTouch, Hook_StartTouch);
		}
		else
		{
			RequestFrame(BreakNextFrame, EntIndexToEntRef(entity));
		}
	}
	return Plugin_Continue;
}

Action Timer_EnablePlayerMovement(Handle timer, DataPack dPack)
{
	dPack.Reset();
	int userid = dPack.ReadCell();
	int ent = EntRefToEntIndex(dPack.ReadCell());
	int client = GetClientOfUserId(userid);

	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue") == 0.0)
	{
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", ga_fPlayerOrgSpeed[client]);

		if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent))
			return Plugin_Stop;

		DataPack dPack2;
		CreateDataTimer(1.5, Timer_HelpMe, dPack2, TIMER_FLAG_NO_MAPCHANGE);
		dPack2.WriteCell(userid);
		dPack2.WriteCell(EntIndexToEntRef(ent));
	}
	return Plugin_Stop;
}

Action Timer_HelpMe(Handle timer, DataPack dPack)
{
	dPack.Reset();
	int client = GetClientOfUserId(dPack.ReadCell());
	int ent = EntRefToEntIndex(dPack.ReadCell());

	if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent) || client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;

	DamageHook(client, true);
	SetEntProp(client, Prop_Send, "m_bGlowEnabled", true);
	EmitSoundToAll(g_sSoundHelp, client, SNDCHAN_VOICE, _, _, 1.0);
	PrintToChatAll("\x070088cc%N\x01 stepped on the mine & needs your help defusing (knife hit) it!", client);

	return Plugin_Stop;
}

void Frame_CheckLastManMines(any data)
{
	if (!g_iRoundStatus || ga_hMines.Length == 0)
		return;

	for (int i = ga_hMines.Length - 1; i >= 0; i--)
	{
		int mine = EntRefToEntIndex(ga_hMines.Get(i));
		if (mine == INVALID_ENT_REFERENCE || !IsValidEntity(mine))
			continue;
		if (!ENTIDX_OK(mine) || !ga_iTouchedBy[mine])
			continue;

		int victim = ga_iTouchedBy[mine];
		if (victim < 1 || victim > MaxClients || !IsClientInGame(victim) || IsFakeClient(victim) || !IsPlayerAlive(victim))
			continue;
		if (!IsLastHumanOnTeam(victim))
			continue;

		RequestFrame(BreakNextFrame, EntIndexToEntRef(mine));
	}
}

public Action Hook_OnTakeDamageBlock(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker) || IsFakeClient(attacker))
		return Plugin_Continue;

	if (damagetype == DMG_SLASH)
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action Hook_EndTouch(int entity, int touch)
{
	if (!ENTIDX_OK(entity)) return Plugin_Continue;

	if (ENTIDX_OK(entity) && ga_iTouchedBy[entity] != touch) return Plugin_Continue;
	if (touch < 1 || touch > MaxClients || !IsClientInGame(touch) || IsFakeClient(touch))
		return Plugin_Continue;

	if (ga_bPlayerHooked[touch])
	{
		DamageHook(touch, false);
		SetEntProp(touch, Prop_Send, "m_bGlowEnabled", false);
	}

	RequestFrame(BreakNextFrame, EntIndexToEntRef(entity));
	return Plugin_Continue;
}

void Mine_OnBreak(const char[] output, int caller, int activator, float delay)
{
	g_fMineBreakTime = GetGameTime();

	if (ENTIDX_OK(caller))
	{
		int victim = ga_iTouchedBy[caller];
		if (victim > 0 && victim <= MaxClients && IsClientInGame(victim))
		{
			if (ga_bPlayerHooked[victim]) DamageHook(victim, false);
			if (GetEntProp(victim, Prop_Send, "m_bGlowEnabled"))
				SetEntProp(victim, Prop_Send, "m_bGlowEnabled", false);
		}
		
		if (ga_iTouchedBy[caller] > 0 && g_iTriggeredMines > 0)
			g_iTriggeredMines--;

		ga_iTouchedBy[caller] = 0;
	}

	if (IsValidEntity(caller))
	{
		int iAttacker = GetEntPropEnt(caller, Prop_Data, "m_hLastAttacker");
		if (iAttacker > 0 && IsClientInGame(iAttacker))
		{
			ga_iDestroyCount[iAttacker]++;
			PrintMineStats(iAttacker);
		}
	}

	if (ga_hMines.Length > 0)
	{
		for (int i = 0; i < ga_hMines.Length; i++)
		{
			if (caller == EntRefToEntIndex(ga_hMines.Get(i))) { ga_hMines.Erase(i); break; }
		}
	}

	float fPos[3];
	bool callerValid = (ENTIDX_OK(caller) && IsValidEntity(caller));
	bool callerIndexOk = ENTIDX_OK(caller);
	if (callerValid)
	{
		GetEntPropVector(caller, Prop_Send, "m_vecOrigin", fPos);
	}
	else if (callerIndexOk)
	{
		fPos[0] = ga_fMineLastPos[caller][0];
		fPos[1] = ga_fMineLastPos[caller][1];
		fPos[2] = ga_fMineLastPos[caller][2];
	}
	else
	{
		fPos[0] = 0.0; fPos[1] = 0.0; fPos[2] = 0.0;
	}

	int emitter = callerValid ? caller : SOUND_FROM_WORLD;
	EmitSoundToAll(g_sSoundDetonate, emitter, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);

	int iParticle = CreateEntityByName("info_particle_system");
	if (IsValidEntity(iParticle))
	{
		char sPos[64];
		FormatEx(sPos, sizeof sPos, "%f %f %f", fPos[0], fPos[1], fPos[2]);
		DispatchKeyValue(iParticle, "origin", sPos);
		DispatchKeyValue(iParticle, "effect_name", "ins_grenade_explosion");
		DispatchSpawn(iParticle);
		ActivateEntity(iParticle);
		AcceptEntityInput(iParticle, "start");
		CreateTimer(3.0, Timer_KillParticle, EntIndexToEntRef(iParticle), TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_KillParticle(Handle timer, int entRef)
{
	SafeKillRef(entRef);
	return Plugin_Stop;
}

public void OnMapEnd()
{
	g_iRoundStatus = 0;
}

void StartRandomSpawnTimer()
{
	if (!g_bTimerOn)
	{
		g_bTimerOn = true;
		CreateTimer(GetRandomFloat(g_fTimerMin, g_fTimerMax), Timer_SpawnMine, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_SpawnMine(Handle timer)
{
	if (g_iRoundStatus == 1)
	{
		if (g_iMaxMines > 0)
		{
			int userid;
			float pos[3];
			if (GetRandomBotSnapshot(userid, pos, false))
			{
				if (CreateMineAt(userid, pos))
				{
					int client = GetClientOfUserId(userid);
					int emitter = (client > 0 && IsClientInGame(client)) ? client : SOUND_FROM_WORLD;
					EmitSoundToAll(g_sSoundPlant, emitter, SNDCHAN_VOICE, _, _, 1.0);
				}
			}
		}
		CreateTimer(GetRandomFloat(g_fTimerMin, g_fTimerMax), Timer_SpawnMine, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		g_bTimerOn = false;
	}
	return Plugin_Stop;
}

Action TimerR_NearestMine(Handle timer)
{
	if (g_iRoundStatus == 0 || ga_hMines.Length == 0)
		return Plugin_Continue;

	int iMine;
	int iNearestMine;
	float fMine[3];
	float fClient[3];
	float fNearestMineDistance;
	float fTempDistance;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && ga_iConfirmedMisc[i] == g_iDetectorId)
		{
			fNearestMineDistance = 0.0;
			iNearestMine = 0;
			GetClientAbsOrigin(i, fClient);

			for (int j = 0; j < ga_hMines.Length; j++)
			{
				iMine = EntRefToEntIndex(ga_hMines.Get(j));
				if (iMine != INVALID_ENT_REFERENCE && IsValidEntity(iMine))
				{
					GetEntPropVector(iMine, Prop_Send, "m_vecOrigin", fMine);
					fTempDistance = GetVectorDistance(fMine, fClient);
					if (fNearestMineDistance == 0.0 || fTempDistance < fNearestMineDistance)
					{
						fNearestMineDistance = fTempDistance;
						iNearestMine = iMine;
					}
				}
			}

			if (iNearestMine && fNearestMineDistance < 500.0 && ga_fDetectorSoundCooldown[i] <= GetGameTime())
			{
				EmitSoundToClient(i, g_sSoundBeep, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.3);

				if (fNearestMineDistance > 350.0)
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 2.0;
				else if (fNearestMineDistance > 250.0)
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 0.8;
				else if (fNearestMineDistance > 100.0)
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 0.4;
				else
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 0.2;

				if (fNearestMineDistance <= 175.0 &&
					ENTIDX_OK(iNearestMine) &&
					ga_fMineSoundCooldown[iNearestMine] <= GetGameTime() &&
					ga_fPlayerVoiceCooldown[i] <= GetGameTime())
				{
					EmitSoundToAll(g_sSoundFound, i, SNDCHAN_VOICE, _, _, 1.0);
					float now = GetGameTime();
					ga_fMineSoundCooldown[iNearestMine] = now + 10.0;
					ga_fPlayerVoiceCooldown[i] = now + 10.0;
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action CmdListener(int client, const char[] cmd, int argc)
{
	if (IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client))
	{
		if (GetEntProp(client, Prop_Send, "m_iPlayerFlags") & PF_BUYZONE)
			ConfirmEquipment(client);
	}
	return Plugin_Continue;
}

void ConfirmEquipment(int client)
{
	ga_iConfirmedMisc[client] = GetEntProp(client, Prop_Send, "m_EquippedGear", 4, 5);
}

void SendDefusedMessage(int client)
{
	Event event = CreateEvent("player_death", true);
	if (event == null)
		return;
	event.SetInt("userid", 0);
	event.SetInt("attacker", GetClientUserId(client));
	event.SetString("weapon", "Defused Land Mine");
	event.Fire(false);
}

void PrintMineStats(int client)
{
	PrintToChat(client, "\x070088cc[Your Stats]\x01 Defused: \x070088cc%d\x01 Destroyed: \x070088cc%d\x01 Died from: \x070088cc%d", ga_iDefuseCount[client], ga_iDestroyCount[client], ga_iDeathCount[client]);
}

void ResetMineStats(int client)
{
	ga_iDefuseCount[client] = 0;
	ga_iDestroyCount[client] = 0;
	ga_iDeathCount[client] = 0;
}

void DamageHook(int client, bool bInput)
{
	switch (bInput)
	{
		case true:
		{
			if (!ga_bPlayerHooked[client])
			{
				SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamageBlock);
				ga_bPlayerHooked[client] = true;
			}
		}
		case false:
		{
			if (ga_bPlayerHooked[client])
			{
				SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamageBlock);
				ga_bPlayerHooked[client] = false;
			}
		}
	}
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_cvMaxMines)
		g_iMaxMines = g_cvMaxMines.IntValue;
	else if (convar == g_cvAliveTime)
		g_fAliveTime = g_cvAliveTime.FloatValue;
	else if (convar == g_cvTimerMin || convar == g_cvTimerMax)
	{
		g_fTimerMin = g_cvTimerMin.FloatValue;
		g_fTimerMax = g_cvTimerMax.FloatValue;
		if (g_fTimerMax < g_fTimerMin)
		{
			float tmp = g_fTimerMin;
			g_fTimerMin = g_fTimerMax;
			g_fTimerMax = tmp;
		}
	}
	else if (convar == g_cvDamage)
		g_iDamage = g_cvDamage.IntValue;
	else if (convar == g_cvRadius)
		g_iRadius = g_cvRadius.IntValue;
	else if (convar == g_cvHelpChance)
		g_fHelpChance = g_cvHelpChance.FloatValue;
	else if (convar == g_cvDetectorId)
		g_iDetectorId = g_cvDetectorId.IntValue;
}

public void OnEntityDestroyed(int ent)
{
	if (!ENTIDX_OK(ent)) return;

	if (ga_iTouchedBy[ent] > 0 && g_iTriggeredMines > 0)
		g_iTriggeredMines--;

	ga_iTouchedBy[ent] = 0;
	ga_fMineSoundCooldown[ent] = 0.0;

	for (int i = 0; i < ga_hMines.Length; i++)
	{
		if (ent == EntRefToEntIndex(ga_hMines.Get(i)))
		{
			ga_hMines.Erase(i);
			break;
		}
	}
}

public void OnPluginEnd()
{
	for (int i = 0; i < ga_hMines.Length; i++)
	{
		KillNowRef(ga_hMines.Get(i));
	}

	delete ga_hMines;

	for (int j = 1; j <= MaxClients; j++)
	{
		if (IsClientInGame(j) && IsPlayerAlive(j))
		{
			if (GetEntPropFloat(j, Prop_Send, "m_flLaggedMovementValue") == 0.0)
				SetEntPropFloat(j, Prop_Send, "m_flLaggedMovementValue", ga_fPlayerOrgSpeed[j]);

			if (GetEntProp(j, Prop_Send, "m_bGlowEnabled") != 0)
				SetEntProp(j, Prop_Send, "m_bGlowEnabled", false);
		}

		if (ga_bPlayerHooked[j]) DamageHook(j, false);
	}
}

stock void KillNowRef(int entref)
{
	int ent = EntRefToEntIndex(entref);
	if (ent > MaxClients && IsValidEntity(ent))
	{
		if (!AcceptEntityInput(ent, "Kill"))
			RemoveEntity(ent);
	}
}

void SafeKillIdx(int ent)
{
	if (ent <= MaxClients) return;
	int ref = EntIndexToEntRef(ent);
	if (ref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, ref);
}

void SafeKillRef(int entref)
{
	if (entref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, entref);
}

void NF_KillEntity(any entref)
{
	int ent = EntRefToEntIndex(entref);
	if (ent <= MaxClients || !IsValidEntity(ent)) return;

	if (!AcceptEntityInput(ent, "Kill"))
		RemoveEntity(ent);
}

void BreakNextFrame(any entref)
{
	int ent = EntRefToEntIndex(entref);
	if (ent > MaxClients && IsValidEntity(ent))
		AcceptEntityInput(ent, "Break");
}