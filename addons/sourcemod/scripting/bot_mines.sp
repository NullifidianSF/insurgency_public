//buy gui https://steamcommunity.com/sharedfiles/filedetails/?id=2879767008

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <insurgencydy>

#define MAXENTITIES 2048

#define DAMAGE_NO			0
#define DAMAGE_EVENTS_ONLY	1
#define DAMAGE_YES			2
#define DAMAGE_AIM			3

//gameme
GlobalForward	MineDefusedForward;

char			g_sModelMine[43] = "models/static_props/wcache_landmine_01.mdl",
				g_sSoundDetonate[29] = "weapons/m67/m67_detonate.wav",
				g_sSoundBeep[17] = "ui/sfx/beep2.wav",	//duration 0:00.348
				g_sSoundDefuse[44] = "physics/metal/solidmetal_impact_soft_01.wav",
				g_sSoundFound[44] = "player/voice/botsurvival/leader/heard14.ogg",
				g_sSoundStepOnMine[48] = "player/voice/botsurvival/subordinate/heard8.ogg",
				g_sSoundStepOnMineArm[40] = "weapons/m67/handling/m67_spooneject.wav",
				g_sSoundHelp[71] = "player/voice/responses/security/subordinate/suppressed/suppressed9.ogg";

float			g_fMineBreakTime,
				g_fTimerMin,
				g_fTimerMax,
				g_fHelpChance,
				ga_fDetectorSoundCooldown[MAXPLAYERS + 1] = {0.0, ...},

				//cooldown for both so that players won't spam about the same mine or if the mines are close together
				ga_fMineSoundCooldown[MAXENTITIES + 1] = {0.0, ...},
				ga_fPlayerVoiceCooldown[MAXPLAYERS + 1] = {0.0, ...},

				ga_fPlayerOrgSpeed[MAXPLAYERS + 1] = {1.0, ...};

int				g_iRoundStatus = 0,
				g_iMaxMines,
				g_iPlayerEquipGear,
				g_iPlayerSpeed,
				ga_iConfirmedMisc[MAXPLAYERS + 1] = {-1, ...},
				g_iDamage,
				g_iRadius,
				ga_iDefuseCount[MAXPLAYERS + 1] = {0, ...},
				ga_iDestroyCount[MAXPLAYERS + 1] = {0, ...},
				ga_iDeathCount[MAXPLAYERS + 1] = {0, ...},
				ga_iTouchedBy[MAXENTITIES +1] = {0, ...};

bool			g_bLateLoad,
				g_bTimerOn,
				ga_bPlayerHooked[MAXPLAYERS + 1] = {false, ...};

const int		gc_iMineDetector_ID = 33;

Handle			ga_hHelpTimer[MAXPLAYERS + 1];

ArrayList		ga_hMines;

ConVar			g_cvMaxMines = null,
				g_cvTimerMin = null,
				g_cvTimerMax = null,
				g_cvDamage = null,
				g_cvRadius = null,
				g_cvHelpChance = null;

public Plugin myinfo = {
	name = "bot_mines",
	author = "Nullifidian",
	description = "Random bots place mines every X minutes",
	version = "1.9https://github.com/NullifidianSF/insurgency_public/blob/main/addons/sourcemod/scripting/bot_antismoke.sp"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	g_iPlayerEquipGear = FindSendPropInfo("CINSPlayer", "m_EquippedGear");
	if (g_iPlayerEquipGear == -1) {
		SetFailState("Offset \"m_EquippedGear\" not found!");
	}

	g_iPlayerSpeed = FindSendPropInfo("CBasePlayer","m_flLaggedMovementValue");
	if (g_iPlayerSpeed == -1) {
		SetFailState("Offset \"m_flLaggedMovementValue\" not found!");
	}

	ga_hMines = CreateArray();

	g_cvMaxMines = CreateConVar("sm_botmines_max", "3", "Maximum concurrent mines allowed", FCVAR_NONE, true, 1.0, true, 15.0);
	g_iMaxMines = g_cvMaxMines.IntValue;
	g_cvMaxMines.AddChangeHook(OnConVarChanged);

	g_cvTimerMin = CreateConVar("sm_botmines_timermin", "60.0", "Minimum possible delay before a random bot places a mine", FCVAR_NONE, true, 30.0);
	g_fTimerMin = g_cvTimerMin.FloatValue;
	g_cvTimerMin.AddChangeHook(OnConVarChanged);

	g_cvTimerMax = CreateConVar("sm_botmines_timermax", "240.0", "Maximum possible delay before a random bot places a mine", FCVAR_NONE, true, 60.0);
	g_fTimerMax = g_cvTimerMax.FloatValue;
	g_cvTimerMax.AddChangeHook(OnConVarChanged);

	g_cvDamage = CreateConVar("sm_botmines_damage", "250", "Explosion damage", FCVAR_NONE, true, 100.0, true, 10000.0);
	g_iDamage = g_cvDamage.IntValue;
	g_cvDamage.AddChangeHook(OnConVarChanged);

	g_cvRadius = CreateConVar("sm_botmines_radius", "300", "Explosion radius", FCVAR_NONE, true, 50.0, true, 10000.0);
	g_iRadius = g_cvRadius.IntValue;
	g_cvRadius.AddChangeHook(OnConVarChanged);

	g_cvHelpChance = CreateConVar("sm_botmines_help", "0.5", "The chance that mine won't explode and teammates can defuse it to save the victim.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_fHelpChance = g_cvHelpChance.FloatValue;
	g_cvHelpChance.AddChangeHook(OnConVarChanged);

	RegAdminCmd("sm_botmine", cmd_botmine, ADMFLAG_RCON, "spawn mine at random bot");

	HookEvent("player_spawn", Event_PlayerRespawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);

	AddCommandListener(CmdListener, "inventory_resupply");
	AddCommandListener(CmdListener, "inventory_confirm");

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);

	if (g_bLateLoad) {
		g_iRoundStatus = 1;
		StartRandomSpawnTimer();
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i)) {
				continue;
			}
			ConfirmEquipment(i);
		}
	}

	//gameme stats
	MineDefusedForward = new GlobalForward("Mine_Defused", ET_Event, Param_Cell);
}

public void OnMapStart() {
	PrecacheModel(g_sModelMine, true);
	PrecacheSound(g_sSoundDetonate, true);
	PrecacheSound(g_sSoundBeep, true);
	PrecacheSound(g_sSoundDefuse, true);
	PrecacheSound(g_sSoundFound, true);
	PrecacheSound(g_sSoundStepOnMine, true);
	PrecacheSound(g_sSoundStepOnMineArm, true);
	PrecacheSound(g_sSoundHelp, true);

	g_bTimerOn = false;
	CreateTimer(0.1, TimerR_NearestMine, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client) {
	if (client && !IsFakeClient(client)) {
		ga_iConfirmedMisc[client] = -1;
		ga_fDetectorSoundCooldown[client] = 0.0;
		ga_fPlayerVoiceCooldown[client] = 0.0;
		ga_bPlayerHooked[client] = false;
		ResetMineStats(client);
		delete ga_hHelpTimer[client];
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	g_iRoundStatus = 1;
	ga_hMines.Clear();
	StartRandomSpawnTimer();

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}
		ResetMineStats(i);
	}
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	g_iRoundStatus = 0;
	return Plugin_Continue;
}

public Action Event_PlayerRespawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client)) {
		ConfirmEquipment(client);
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int iWeaponId = event.GetInt("weaponid");
	if (iWeaponId != -1) {
		return Plugin_Continue;
	}

	if (g_fMineBreakTime != GetGameTime()) {
		return Plugin_Continue;
	}

	char sWeapon[32];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	if (strcmp(sWeapon, "prop_dynamic", false) == 0) {
		event.SetString("weapon", "land mine");
		
		int client = GetClientOfUserId(event.GetInt("userid"));
		if (client) {
			ga_iDeathCount[client]++;
			PrintMineStats(client);
		}
	}
	return Plugin_Continue;
}

public Action cmd_botmine(int client, int args) {
	if (!g_iRoundStatus) {
		ReplyToCommand(client, "Wait for game round to start first");
		return Plugin_Handled;
	}

	int iBot = GetRandomAliveBot();
	if (iBot > 0) {
		if (!CreateMine(iBot)) {
			ReplyToCommand(client, "\"CreateMine\" failed");
			return Plugin_Handled;
		}
		ReplyToCommand(client, "Spawned mine @ %N's location", iBot);
		return Plugin_Handled;
	}

	ReplyToCommand(client, "No valid bot found");
	return Plugin_Handled;
}

bool CreateMine(int client) {
	int iEnt = CreateEntityByName("prop_dynamic_override");
	if (!IsValidEdict(iEnt)) {
		return false;
	}

	//if max concurrent mines reached then remove the oldest mine
	int iOldMine;
	while (ga_hMines.Length >= g_iMaxMines && g_iMaxMines != 0) {
		iOldMine = EntRefToEntIndex(ga_hMines.Get(0));
		if (iOldMine != INVALID_ENT_REFERENCE && IsValidEdict(iOldMine)) {
			RemoveEntity(iOldMine);
		}
		ga_hMines.Erase(0);
	}

	ga_hMines.Push(EntIndexToEntRef(iEnt));
	
	ga_fMineSoundCooldown[iEnt] = 0.0;

	float fClientPos[3];
	GetClientAbsOrigin(client, fClientPos);
	fClientPos[2] -= 1.0;
	
	DispatchKeyValue(iEnt, "physdamagescale", "0.0");
	DispatchKeyValue(iEnt, "model", g_sModelMine);
	DispatchKeyValue(iEnt, "Solid", "6");
	
	if (!DispatchSpawn(iEnt)) {
		RemoveEntity(iEnt);
		return false;
	}

	SetEntProp(iEnt, Prop_Data, "m_takedamage", DAMAGE_YES);
	SetEntProp(iEnt, Prop_Data, "m_iHealth", 200);
	SetEntProp(iEnt, Prop_Data, "m_iMaxHealth", 200);

	TeleportEntity(iEnt, fClientPos, NULL_VECTOR, NULL_VECTOR);
	SetEntityMoveType(iEnt, MOVETYPE_NONE);
	SetEntPropEnt(iEnt, Prop_Data, "m_hLastAttacker", client);

	char sBuffer[10];
	FormatEx(sBuffer, sizeof(sBuffer), "%d", g_iRadius);
	DispatchKeyValue(iEnt, "ExplodeRadius", sBuffer);	//grenade_f1 750

	FormatEx(sBuffer, sizeof(sBuffer), "%d", g_iDamage);
	DispatchKeyValue(iEnt, "ExplodeDamage", sBuffer);	//grenade_f1 160

	DispatchKeyValue(iEnt, "minhealthdmg", "25");

	ga_iTouchedBy[iEnt] = 0;

	SDKHook(iEnt, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	SDKHook(iEnt, SDKHook_StartTouch, Hook_StartTouch);
	SDKHook(iEnt, SDKHook_EndTouch, Hook_EndTouch);
	HookSingleEntityOutput(iEnt, "OnBreak", Mine_OnBreak, true);

	return true;
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker) || IsFakeClient(attacker)) {
		return Plugin_Handled;
	}
	if (damagetype == DMG_SLASH) {
		if (ga_iTouchedBy[victim] == attacker) {
			return Plugin_Handled;
		}
		if (IsValidEdict(victim)) {
			EmitSoundToAll(g_sSoundDefuse, victim, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);
			
			if (ga_iTouchedBy[victim]) {
				DamageHook(ga_iTouchedBy[victim], false);
				SetEntProp(ga_iTouchedBy[victim], Prop_Send, "m_bGlowEnabled", false);
				PrintToChatAll("\x070088cc%N\x01 saved \x070088cc%N\x01's life by defusing the mine.", attacker, ga_iTouchedBy[victim]);
			}

			RemoveEntity(victim);
			ga_iDefuseCount[attacker]++;
			SendForwardResult(MineDefusedForward, attacker);	//gameme

			PrintMineStats(attacker);
			SendDefusedMessage(attacker);
		}
		return Plugin_Handled;
	}

	if (ga_iTouchedBy[victim]) {
		return Plugin_Handled;
	}

	if (damagetype != DMG_BULLET && damagetype != DMG_BUCKSHOT && damagetype != (DMG_BULLET + DMG_BUCKSHOT)) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Hook_StartTouch(int entity, int touch) {
	if (touch > 0 && touch <= MaxClients && IsClientInGame(touch) && !IsFakeClient(touch)) {
		if (GetRandomFloat(0.0, 1.0) <= g_fHelpChance) {
			ga_iTouchedBy[entity] = touch;
			ga_fPlayerOrgSpeed[touch] = GetEntDataFloat(touch, g_iPlayerSpeed);
			SetEntDataFloat(touch, g_iPlayerSpeed, 0.0);

			DataPack dPack;
			CreateDataTimer(0.6, Timer_EnablePlayerMovement, dPack, TIMER_FLAG_NO_MAPCHANGE);
			dPack.WriteCell(touch);
			dPack.WriteCell(EntIndexToEntRef(entity));

			PrintHintText(touch, "Don't move! You are standing on the mine!");
			EmitSoundToAll(g_sSoundStepOnMine, touch, SNDCHAN_VOICE, _, _, 1.0);
		}

		EmitSoundToAll(g_sSoundStepOnMineArm, entity, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);
		SDKUnhook(entity, SDKHook_StartTouch, Hook_StartTouch);
	}
	return Plugin_Continue;
}

Action Timer_EnablePlayerMovement(Handle timer, DataPack dPack) {
	dPack.Reset();
	int client = dPack.ReadCell(),
		iEnt = EntRefToEntIndex(dPack.ReadCell());

	if (iEnt == INVALID_ENT_REFERENCE || !IsValidEdict(iEnt)) {
		return Plugin_Stop;
	}

	if (IsClientInGame(client) && IsPlayerAlive(client) && GetEntDataFloat(client, g_iPlayerSpeed) == 0.0) {
		SetEntDataFloat(client, g_iPlayerSpeed, ga_fPlayerOrgSpeed[client]);

		DataPack dPack2;
		ga_hHelpTimer[client] = CreateDataTimer(1.5, Timer_HelpMe, dPack2);
		dPack2.WriteCell(client);
		dPack2.WriteCell(EntIndexToEntRef(iEnt));
	}
	return Plugin_Stop;
}

Action Timer_HelpMe(Handle timer, DataPack dPack) {
	dPack.Reset();
	int client = dPack.ReadCell(),
		iEnt = EntRefToEntIndex(dPack.ReadCell());

	if (iEnt == INVALID_ENT_REFERENCE || !IsValidEdict(iEnt)) {
		return Plugin_Stop;
	}

	if (IsPlayerAlive(client)) {
		DamageHook(client, true);
		SetEntProp(client, Prop_Send, "m_bGlowEnabled", true);
		EmitSoundToAll(g_sSoundHelp, client, SNDCHAN_VOICE, _, _, 1.0);
		PrintToChatAll("\x070088cc%N\x01 stepped on the mine & needs your help defusing (knife hit) it!", client);
	}
	return Plugin_Stop;
}

public Action Hook_OnTakeDamageBlock(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker) || IsFakeClient(attacker)) {
		return Plugin_Continue;
	}
	
	if (damagetype == DMG_SLASH) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action Hook_EndTouch(int entity, int touch) {
	if (touch > 0 && touch <= MaxClients && IsClientInGame(touch) && !IsFakeClient(touch)) {
		if (ga_bPlayerHooked[touch]) {
			DamageHook(touch, false);
			SetEntProp(touch, Prop_Send, "m_bGlowEnabled", false);
		}

		AcceptEntityInput(entity, "Break");
	}
	return Plugin_Continue;
}

void Mine_OnBreak(const char[] output, int caller, int activator, float delay) {
	g_fMineBreakTime = GetGameTime();

	if (IsValidEdict(caller)) {
		int iAttacker = GetEntPropEnt(caller, Prop_Data, "m_hLastAttacker");
		if (iAttacker > 0 && IsClientInGame(iAttacker)) {
			ga_iDestroyCount[iAttacker]++;
			PrintMineStats(iAttacker);
		}
	}
	
	if (ga_hMines.Length > 0) {
		for (int i = 0; i < ga_hMines.Length; i++) {
			if (caller == EntRefToEntIndex(ga_hMines.Get(i))) {
				ga_hMines.Erase(i);
				break;
			}
		}
	}

	int iParticle = CreateEntityByName("info_particle_system");
	if (IsValidEdict(iParticle)) {
		float fPos[3];
		GetEntPropVector(caller, Prop_Send, "m_vecOrigin", fPos);

		char sPos[64];
		FormatEx(sPos, sizeof(sPos), "%f %f %f", fPos[0], fPos[1], fPos[2]);
		DispatchKeyValue(iParticle,"Origin", sPos);
		DispatchKeyValue(iParticle, "effect_name", "ins_grenade_explosion");
		DispatchSpawn(iParticle);

		ActivateEntity(iParticle);
		AcceptEntityInput(iParticle, "start");
		CreateTimer(3.0, Timer_KillParticle, EntIndexToEntRef(iParticle));
	}
	EmitSoundToAll(g_sSoundDetonate, caller, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);
}

Action Timer_KillParticle(Handle timer, int entRef) {
	int iParticle = EntRefToEntIndex(entRef);
	if (iParticle != INVALID_ENT_REFERENCE && IsValidEdict(iParticle)) {
		RemoveEntity(iParticle);
	}
	return Plugin_Stop;
}

public void OnMapEnd() {
	g_iRoundStatus = 0;
}

int GetRandomAliveBot() {
	int[]	iClients = new int[MaxClients + 1];
	
	int		iCount;

	bool	bTooClose = false;
	
	float	fBotPos[3],
			fPlayerPos[3];

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetEntPropEnt(i, Prop_Send, "m_hGroundEntity") == 0) {
			//make sure not to use a bot that is too close to a player
			GetClientAbsOrigin(i, fBotPos);
			for (int j = 1; j <= MaxClients; j++) {
				if (IsClientInGame(j) && !IsFakeClient(j) && IsPlayerAlive(j)) {
					GetClientAbsOrigin(j, fPlayerPos);
					if (GetVectorDistance(fBotPos, fPlayerPos) < 650.0) {
						bTooClose = true;
						break;
					}
				}
			}
			if (bTooClose) {
				bTooClose = false;
				continue;
			}
			iClients[iCount++] = i;
		}
	}
	return (iCount == 0) ? -1 : iClients[GetRandomInt(0, iCount - 1)];
}

void StartRandomSpawnTimer() {
	if (!g_bTimerOn) {
		g_bTimerOn = true;
		CreateTimer(GetRandomFloat(g_fTimerMin, g_fTimerMax), Timer_SpawnMine, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_SpawnMine(Handle timer) {
	if (g_iRoundStatus == 1) {
		int iBot = GetRandomAliveBot();
		if (iBot > 0) {
			CreateMine(iBot);
		}
		CreateTimer(GetRandomFloat(g_fTimerMin, g_fTimerMax), Timer_SpawnMine, _, TIMER_FLAG_NO_MAPCHANGE);
	} else {
		g_bTimerOn = false;
	}
	return Plugin_Stop;
}

Action TimerR_NearestMine(Handle timer) {
	if (g_iRoundStatus == 0 || ga_hMines.Length == 0) {
		return Plugin_Continue;
	}

	int		iMine,
			iNearestMine;

	float	fMine[3],
			fClient[3],
			fNearestMineDistance,
			fTempDistance;

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && ga_iConfirmedMisc[i] == gc_iMineDetector_ID) {
			fNearestMineDistance = 0.0;
			iNearestMine = 0;

			for (int j = 0; j < ga_hMines.Length; j++) {
				iMine = EntRefToEntIndex(ga_hMines.Get(j));
				if (iMine != INVALID_ENT_REFERENCE && IsValidEdict(iMine)) {
					GetEntPropVector(iMine, Prop_Send, "m_vecOrigin", fMine);
					GetClientAbsOrigin(i, fClient);
					fTempDistance = GetVectorDistance(fMine, fClient);

					if (fNearestMineDistance == 0.0 || fTempDistance < fNearestMineDistance) {
						fNearestMineDistance = fTempDistance;
						iNearestMine = iMine;
					}
				}
			}

			if (iNearestMine && fNearestMineDistance < 500.0 && ga_fDetectorSoundCooldown[i] <= GetGameTime()) {
				EmitSoundToClient(i, g_sSoundBeep, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.3);
				if (fNearestMineDistance > 350.0) {
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 2.0;
				}
				else if (fNearestMineDistance > 250.0){
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 0.8;
				}
				else if (fNearestMineDistance > 100.0){
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 0.4;
				}
				else if (fNearestMineDistance >= 0.0){
					ga_fDetectorSoundCooldown[i] = GetGameTime() + 0.2;
				}

				if (fNearestMineDistance <= 175.0 && ga_fMineSoundCooldown[iNearestMine] <= GetGameTime() && ga_fPlayerVoiceCooldown[i] <= GetGameTime()) {
					EmitSoundToAll(g_sSoundFound, i, SNDCHAN_VOICE, _, _, 1.0);
					ga_fMineSoundCooldown[iNearestMine] = ga_fPlayerVoiceCooldown[i] = GetGameTime() + 10.0;
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action CmdListener(int client, const char[] cmd, int argc) {
	if (IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client)) {
		if (GetEntProp(client, Prop_Send, "m_iPlayerFlags") & INS_PL_BUYZONE) {
			ConfirmEquipment(client);
		}
	}
	return Plugin_Continue;
}

void ConfirmEquipment(int client) {
	ga_iConfirmedMisc[client] = GetEntData(client, g_iPlayerEquipGear + (4 * 5));
}

void SendDefusedMessage(int client) {
	Event event = CreateEvent("player_death", true);
	if (event == null) {
		return;
	}

	event.SetInt("userid", 0);
	event.SetInt("attacker", GetClientUserId(client));
	event.SetString("weapon", "Defused Land Mine");
	event.Fire(false);
}

void PrintMineStats(int client) {
	PrintToChat(client, "\x070088cc[Your Stats]\x01 Defused: \x070088cc%d\x01 Destroyed: \x070088cc%d\x01 Died from: \x070088cc%d",
							ga_iDefuseCount[client], ga_iDestroyCount[client], ga_iDeathCount[client]);
}

void ResetMineStats(int client) {
	ga_iDefuseCount[client] = 0;
	ga_iDestroyCount[client] = 0;
	ga_iDeathCount[client] = 0;
}

//gameme
public Action SendForwardResult(GlobalForward sName, int iClient) {	//gameme stats forward
	Action result;
	Call_StartForward(sName);
	Call_PushCell(iClient);
	Call_Finish(result);
	return result;
}

bool DamageHook(int client, bool bInput) {
	switch (bInput) {
		case true: {
			if (!ga_bPlayerHooked[client]) {
				SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamageBlock);
				ga_bPlayerHooked[client] = true;
			}
		}
		case false: {
			if (ga_bPlayerHooked[client]) {
				SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamageBlock);
				ga_bPlayerHooked[client] = false;
			}
		}
	}
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvMaxMines) {
		g_iMaxMines = g_cvMaxMines.IntValue;
	}
	else if (convar == g_cvTimerMin) {
		g_fTimerMin = g_cvTimerMin.FloatValue;
	}
	else if (convar == g_cvTimerMax) {
		g_fTimerMax = g_cvTimerMax.FloatValue;
	}
	else if (convar == g_cvDamage) {
		g_iDamage = g_cvDamage.IntValue;
	}
	else if (convar == g_cvRadius) {
		g_iRadius = g_cvRadius.IntValue;
	}
	else if (convar == g_cvHelpChance) {
		g_fHelpChance = g_cvHelpChance.FloatValue;
	}
}

public void OnPluginEnd() {
	if (ga_hMines.Length < 1) {
		return;
	}

	int iMine = -1;
	for (int i = 0; i < ga_hMines.Length; i++) {
		iMine = EntRefToEntIndex(ga_hMines.Get(i));
		if (iMine != INVALID_ENT_REFERENCE && IsValidEdict(iMine)) {
			RemoveEntity(iMine);
		}
	}

	for (int j = 1; j <= MaxClients; j++) {
		if (IsClientInGame(j) && IsPlayerAlive(j)) {
			if (GetEntDataFloat(j, g_iPlayerSpeed) == 0.0) {
				SetEntDataFloat(j, g_iPlayerSpeed, ga_fPlayerOrgSpeed[j]);
			}
			if (GetEntProp(j, Prop_Send, "m_bGlowEnabled") != 0) {
				SetEntProp(j, Prop_Send, "m_bGlowEnabled", false);
			}
		}
	}
}