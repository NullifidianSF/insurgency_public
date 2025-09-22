// required files: https://steamcommunity.com/sharedfiles/filedetails/?id=2844331697
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define SND_DETECT "bm/IronDome/detect.wav"
#define SND_EXPLODE "bm/IronDome/explode.wav"
#define SND_TAKE "weapons/universal/uni_weapon_raise_02.wav"

#define BTN_SPECIAL1 (1 << 17)
#define PF_BUYZONE (1 << 7)

const int gc_iIronDome_ID = 32;
const int gc_iMaxAllowedBlocks = 3;
const float IRON_DOME_RANGE = 350.0;
const float PICKUP_RANGE = 90.0;

bool g_bLateLoad;

int g_iBeaconBeam;
int g_iBeaconHalo;
int g_iPlayerEquipGear = -1;
int g_iRoundStatus = 0;
int ga_iConfirmedMisc[MAXPLAYERS + 1] = { -1, ... };
int ga_iBlocks[MAXPLAYERS + 1] = { 1, ... };
int ga_iLastButtons[MAXPLAYERS + 1];

ArrayList ga_hExplosives;

public Plugin myinfo = {
	name = "iron_dome",
	author = "Nullifidian",
	description = "Portable system that intercepts hostile RPGs and grenades",
	version = "1.9",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	g_iPlayerEquipGear = FindSendPropInfo("CINSPlayer", "m_EquippedGear");
	if (g_iPlayerEquipGear == -1)
		SetFailState("Offset \"m_EquippedGear\" not found!");

	ga_hExplosives = new ArrayList();

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("game_end", Event_GameEnd, EventHookMode_PostNoCopy);
	HookEvent("grenade_thrown", Event_NadeAndMissile);
	HookEvent("missile_launched", Event_NadeAndMissile);
	HookEvent("player_spawn", Event_PlayerRespawn);
	HookEvent("object_destroyed", Event_Objective, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", Event_Objective, EventHookMode_PostNoCopy);
	HookEvent("grenade_detonate", Event_GrenadeDetonate);

	AddCommandListener(CmdListener, "inventory_resupply");
	AddCommandListener(CmdListener, "inventory_confirm");

	if (g_bLateLoad) {
		g_iRoundStatus = 1;
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;
			ConfirmEquipment(i);
		}
	}
}

public void OnMapStart() {
	PrecacheSound(SND_DETECT, true);
	PrecacheSound(SND_EXPLODE, true);
	PrecacheSound(SND_TAKE, true);

	g_iBeaconBeam = PrecacheModel("materials/sprites/laser.vmt");
	g_iBeaconHalo = PrecacheModel("materials/sprites/glow01.vmt");

	CreateTimer(0.1, TimerR_IronDome, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	ga_hExplosives.Clear();
	g_iRoundStatus = 1;

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		ga_iBlocks[i] = 1;
	}
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client) {
	if (client && !IsFakeClient(client)) {
		ga_iConfirmedMisc[client] = -1;
		ga_iBlocks[client] = 1;
		ga_iLastButtons[client] = 0;
	}
}

public void OnClientDisconnect(int client) {
	if (client && !IsFakeClient(client)) {
		ga_iConfirmedMisc[client] = -1;
		ga_iBlocks[client] = 1;
		ga_iLastButtons[client] = 0;
	}
}

public Action Event_Objective(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (ga_iBlocks[i] <= 0)
			ga_iBlocks[i] = 1;
	}
	return Plugin_Continue;
}

public Action Event_PlayerRespawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2)
		ConfirmEquipment(client);
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || !IsClientInGame(victim) || IsFakeClient(victim))
		return Plugin_Continue;

	if (ga_iBlocks[victim] < 1)
		ga_iBlocks[victim] = 1;

	return Plugin_Continue;
}

public Action Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast) {
	if (ga_hExplosives.Length < 1)
		return Plugin_Continue;

	int nade = event.GetInt("entityid");
	for (int i = 0; i < ga_hExplosives.Length; i++) {
		if (nade == EntRefToEntIndex(ga_hExplosives.Get(i))) {
			ga_hExplosives.Erase(i);
			break;
		}
	}
	return Plugin_Continue;
}

public Action CmdListener(int client, const char[] cmd, int argc) {
	if (!IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
		return Plugin_Continue;

	int pflags = GetEntProp(client, Prop_Send, "m_iPlayerFlags");
	if (pflags & PF_BUYZONE)
		ConfirmEquipment(client);
	return Plugin_Continue;
}

public Action Event_NadeAndMissile(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int ent = event.GetInt("entityid");

	if (client < 1 || !IsClientInGame(client) || !IsFakeClient(client))
		return Plugin_Continue;
	if (ent < 1 || !IsValidEntity(ent))
		return Plugin_Continue;

	char sEnt[32];
	GetEntityClassname(ent, sEnt, sizeof(sEnt));

	if (StrContains(sEnt, "grenade_m18", false) > -1)
		return Plugin_Continue;

	ga_hExplosives.Push(EntIndexToEntRef(ent));
	return Plugin_Continue;
}

Action TimerR_IronDome(Handle timer) {
	if (!g_iRoundStatus || ga_hExplosives.Length < 1)
		return Plugin_Continue;

	for (int client = 1; client <= MaxClients; client++) {
		if (ga_iConfirmedMisc[client] != gc_iIronDome_ID || ga_iBlocks[client] < 1)
			continue;
		if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
			continue;

		float vClient[3];
		GetClientAbsOrigin(client, vClient);

		for (int j = ga_hExplosives.Length - 1; j >= 0; j--) {
			int ent = EntRefToEntIndex(ga_hExplosives.Get(j));
			if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent)) {
				ga_hExplosives.Erase(j);
				continue;
			}

			float vEnt[3];
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vEnt);

			if (GetVectorDistance(vClient, vEnt) > IRON_DOME_RANGE)
				continue;

			float vBeamStart[3];
			vBeamStart[0] = vClient[0];
			vBeamStart[1] = vClient[1];
			vBeamStart[2] = vClient[2] + 25.0;

			ShowSprite(vBeamStart, vEnt);
			CreateParticle(vEnt);

			EmitSoundToAll(SND_DETECT, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
			EmitSoundToAll(SND_EXPLODE, ent, SNDCHAN_AUTO, SNDLEVEL_NORMAL);

			ga_hExplosives.Erase(j);
			ga_iBlocks[client]--;

			char cname[64];
			if (GetEntityClassname(ent, cname, sizeof(cname)))
				PrintToChat(client, "\x070088cc[ID]\x01 Shot down \x070088cc%s\x01 Ammo: \x070088cc%d\x01/\x070088cc%d", cname, ga_iBlocks[client], gc_iMaxAllowedBlocks);
			else
				PrintToChat(client, "\x070088cc[ID]\x01 Shot down explosive device \x01Ammo: \x070088cc%d\x01/\x070088cc%d", ga_iBlocks[client], gc_iMaxAllowedBlocks);

			RemoveEntity(ent);

			if (ga_iBlocks[client] < 1)
				break;
		}
	}
	return Plugin_Continue;
}

void ShowSprite(const float vStart[3], const float vEnd[3]) {
	int color[4] = {255, 0, 0, 255};
	TE_SetupBeamPoints(vStart, vEnd, g_iBeaconBeam, g_iBeaconHalo, 0, 15, 0.8, 0.7, 0.8, 90, 0.0, color, 1);
	TE_SendToAll();
}

void CreateParticle(const float fPos[3]) {
	int iParticle = CreateEntityByName("info_particle_system");
	if (iParticle > MaxClients && IsValidEntity(iParticle)) {
		char sPos[96];
		FormatEx(sPos, sizeof(sPos), "%f %f %f", fPos[0], fPos[1], fPos[2]);

		DispatchKeyValue(iParticle, "Origin", sPos);
		DispatchKeyValue(iParticle, "effect_name", "skybox_white_phos_glow_c");
		DispatchSpawn(iParticle);

		CreateTimer(1.5, Timer_KillParticle, EntIndexToEntRef(iParticle), TIMER_FLAG_NO_MAPCHANGE);

		ActivateEntity(iParticle);
		AcceptEntityInput(iParticle, "start");
	}
}

public Action Timer_KillParticle(Handle timer, int entRef) {
	int iParticle = EntRefToEntIndex(entRef);
	if (iParticle != INVALID_ENT_REFERENCE && IsValidEntity(iParticle))
		RemoveEntity(iParticle);
	return Plugin_Stop;
}

void ConfirmEquipment(int client) {
	ga_iConfirmedMisc[client] = GetEntData(client, g_iPlayerEquipGear + (4 * 5));
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	g_iRoundStatus = 0;
	return Plugin_Continue;
}

public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	g_iRoundStatus = 0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
	if (!g_iRoundStatus || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;
	if (ga_iConfirmedMisc[client] != gc_iIronDome_ID)
		return Plugin_Continue;

	int newlyPressed = (buttons ^ ga_iLastButtons[client]) & buttons;
	if (newlyPressed & BTN_SPECIAL1)
		OnButtonPress(client, BTN_SPECIAL1);

	ga_iLastButtons[client] = buttons;
	return Plugin_Continue;
}

void OnButtonPress(int client, int button) {
	if ((button & BTN_SPECIAL1) == 0)
		return;

	int target = GetClientAimTarget(client, false);
	if (target <= MaxClients || target > 2048 || !IsValidEntity(target))
		return;

	char sName[64];
	if (!GetEntityClassname(target, sName, sizeof(sName)))
		return;

	if (strcmp(sName, "weapon_at4", false) != 0 && strcmp(sName, "weapon_rpg7", false) != 0)
		return;

	float vClient[3], vTarget[3];
	GetClientAbsOrigin(client, vClient);
	GetEntPropVector(target, Prop_Send, "m_vecOrigin", vTarget);
	if (GetVectorDistance(vClient, vTarget) > PICKUP_RANGE)
		return;

	if (ga_iBlocks[client] >= gc_iMaxAllowedBlocks) {
		PrintToChat(client, "\x070088cc[ID]\x01 Ammo: \x070088cc%d\x01/\x070088cc%d", gc_iMaxAllowedBlocks, gc_iMaxAllowedBlocks);
		return;
	}

	EmitSoundToAll(SND_TAKE, target, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
	RemoveEntity(target);

	ga_iBlocks[client]++;
	PrintToChat(client, "\x070088cc[ID]\x01 Ammo: \x070088cc%d\x01/\x070088cc%d", ga_iBlocks[client], gc_iMaxAllowedBlocks);
}
