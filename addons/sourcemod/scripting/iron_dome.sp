//required files: https://steamcommunity.com/sharedfiles/filedetails/?id=2844331697
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <insurgencydy>

#define SND_DETECT "bm/IronDome/detect.wav"
#define SND_EXPLODE "bm/IronDome/explode.wav"
#define SND_TAKE "weapons/universal/uni_weapon_raise_02.wav"

bool		g_bLateLoad;

const int	gc_iIronDome_ID = 32,
			gc_iMaxAllowedBlocks = 3;

int			g_iBeaconBeam,
			g_iBeaconHalo,
			ga_iConfirmedMisc[MAXPLAYERS + 1] = {-1, ...},
			g_iPlayerEquipGear,
			g_iRoundStatus = 0,
			ga_iBlocks[MAXPLAYERS + 1] = {1, ...},
			ga_iLastButtons[MAXPLAYERS + 1];

ArrayList	ga_hExplosives;

public Plugin myinfo = {
	name		= "iron_dome",
	author		= "Nullifidian",
	description	= "The portable Iron Dome defence system that designed to destroy hostile RPGs and grenades",
	version		= "1.8",
	url			= ""
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

	ga_hExplosives = CreateArray();

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
			if (!IsClientInGame(i) || IsFakeClient(i)) {
				continue;
			}
			ConfirmEquipment(i);
		}
	}
}

public void OnMapStart() {
	PrecacheSound(SND_DETECT, true);
	PrecacheSound(SND_EXPLODE, true);
	PrecacheSound(SND_TAKE, true);
	g_iBeaconBeam = PrecacheModel("sprites/laserbeam.vmt");
	g_iBeaconHalo = PrecacheModel("sprites/glow01.vmt");
	CreateTimer(0.1, TimerR_IronDome, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	ga_hExplosives.Clear();
	g_iRoundStatus = 1;
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}
		ga_iBlocks[i] = 1;
	}
	return Plugin_Continue;
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
		if (!IsClientInGame(i) || IsFakeClient(i) || ga_iBlocks[i] > 0) {
			continue;
		}
		ga_iBlocks[i] = 1;
	}
	return Plugin_Continue;
}

public Action Event_PlayerRespawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client)) {
		ConfirmEquipment(client);
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || !IsClientInGame(victim) || IsFakeClient(victim) || ga_iBlocks[victim] == 1) {
		return Plugin_Continue;
	}
	ga_iBlocks[victim] = 1;
	return Plugin_Continue;
}

public Action Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || (IsClientInGame(client) && !IsFakeClient(client))) {
		return Plugin_Continue;
	}
	
	if (ga_hExplosives.Length < 1) {
		return Plugin_Continue;
	}

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
	if (IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client)) {
		if ((GetEntProp(client, Prop_Send, "m_iPlayerFlags") & INS_PL_BUYZONE)) {
			ConfirmEquipment(client);
		}
	}
	return Plugin_Continue;
}

public Action Event_NadeAndMissile(Event event, char[] name, bool dontBroadcast) {
	int	client = GetClientOfUserId(event.GetInt("userid")),
		ent = event.GetInt("entityid");

	if (client < 1 || !IsClientInGame(client) || !IsFakeClient(client) || ent < 1 || !IsValidEntity(ent)) {
		return Plugin_Continue;
	}

	char sEnt[32];
	GetEntityClassname(ent, sEnt, sizeof(sEnt));
	if (StrContains(sEnt, "grenade_m18", false) > -1) {
		return Plugin_Continue;
	}
	
	ga_hExplosives.Push(EntIndexToEntRef(ent));

	return Plugin_Continue;
}

Action TimerR_IronDome(Handle timer) {
	if (!g_iRoundStatus || ga_hExplosives.Length < 1) {
		return Plugin_Continue;
	}

	int		iEnt;

	float	vEnt[3],
			vClient[3];
			
	char	sEnt[32];

	for (int i = 1; i <= MaxClients; i++) {
		if (ga_iConfirmedMisc[i] != gc_iIronDome_ID || ga_iBlocks[i] < 1) {
			continue;
		}
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i)) {
			continue;
		}

		if (ga_hExplosives.Length < 1) {
			break;
		}

		for (int j = (ga_hExplosives.Length - 1); j >= 0; j--) {
			iEnt = EntRefToEntIndex(ga_hExplosives.Get(j));
			if (iEnt == INVALID_ENT_REFERENCE || !IsValidEntity(iEnt)) {
				ga_hExplosives.Erase(j);
				continue;
			}

			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vEnt);
			GetClientAbsOrigin(i, vClient);

			if (GetVectorDistance(vClient, vEnt) > 350.0) {
				continue;
			}
			
			vClient[2] += 25.0;
			ShowSprite(vClient, vEnt);
			CreateParticle(vEnt);
			EmitSoundToAll(SND_DETECT, i, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);
			EmitSoundToAll(SND_EXPLODE, iEnt, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);
			ga_hExplosives.Erase(j);
			ga_iBlocks[i]--;

			if (GetEntityClassname(iEnt, sEnt, sizeof(sEnt))) {
				PrintToChat(i, "\x070088cc[ID]\x01 Shot down \x070088cc%s\x01 \x01Ammo left: \x070088cc%d\x01/\x070088cc%d", sEnt,  ga_iBlocks[i], gc_iMaxAllowedBlocks);
			} else {
				PrintToChat(i, "\x070088cc[ID]\x01 Shot down explosive device \x01Ammo left: \x070088cc%d\x01/\x070088cc%d", sEnt,  ga_iBlocks[i], gc_iMaxAllowedBlocks);
			}
			RemoveEntity(iEnt);
			if (ga_iBlocks[i] < 1) {
				break;
			}
		}
	}
	return Plugin_Continue;
}

void ShowSprite(float vClient[3], float vEnt[3]) {
	TE_SetupBeamPoints(vClient, vEnt, g_iBeaconBeam, g_iBeaconHalo, 0, 15, 0.8, 0.7, 0.8, 90, 0.0, {255, 0, 0, 255}, 1);
	TE_SendToAll();
}

void CreateParticle(float fPos[3]) {
	int iParticle = CreateEntityByName("info_particle_system");
	if (iParticle > MaxClients && IsValidEntity(iParticle)) {
		char sPos[128];
		FormatEx(sPos, sizeof(sPos), "%f %f %f", fPos[0], fPos[1], fPos[2]);

		DispatchKeyValue(iParticle,"Origin", sPos);
		DispatchKeyValue(iParticle, "effect_name", "skybox_white_phos_glow_c");	//fire_01l4d.pcf
		DispatchSpawn(iParticle);
		
		CreateTimer(1.5, Timer_KillParticle, EntIndexToEntRef(iParticle));

		ActivateEntity(iParticle);
		AcceptEntityInput(iParticle, "start");
	}
}

Action Timer_KillParticle(Handle timer, int entRef) {
	int iParticle = EntRefToEntIndex(entRef);
	if (iParticle != INVALID_ENT_REFERENCE && IsValidEntity(iParticle)) {
		RemoveEntity(iParticle);
	}
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
	if (!g_iRoundStatus || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client) || ga_iConfirmedMisc[client] != gc_iIronDome_ID) {
		return Plugin_Continue;
	}
	int button;
	for (int i = 0; i < MAX_BUTTONS; i++) {
		button = (1 << i);
		if (buttons & button) {
			if (!(ga_iLastButtons[client] & button)) {
				OnButtonPress(client, button);
			}
		}
	}
	ga_iLastButtons[client] = buttons;
	return Plugin_Continue;
}

void OnButtonPress(int client, int button) {
	if (button & INS_SPECIAL1) {
		int iTarget = GetClientAimTarget(client, false);
		if (iTarget <= MaxClients || iTarget > 2048 || !IsValidEntity(iTarget)) {
			return;
		}

		char sName[64];
		if (!GetEntityClassname(iTarget, sName, sizeof(sName))) {
			return;
		}

		if (strcmp(sName, "weapon_at4", false) == 0 || strcmp(sName, "weapon_rpg7", false) == 0) {
			float	vClient[3],
					vTarget[3];

			GetClientAbsOrigin(client, vClient);
			GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vTarget);
			if (GetVectorDistance(vClient, vTarget) > 90.0) {
				return;
			}

			if (ga_iBlocks[client] >= gc_iMaxAllowedBlocks) {
				PrintToChat(client, "\x070088cc[ID]\x01 Ammo: \x070088cc%d\x01/\x070088cc%d", gc_iMaxAllowedBlocks, gc_iMaxAllowedBlocks);
				return;
			}
			EmitSoundToAll(SND_TAKE, iTarget, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 100);
			RemoveEntity(iTarget);
			ga_iBlocks[client]++;
			PrintToChat(client, "\x070088cc[ID]\x01 Ammo: \x070088cc%d\x01/\x070088cc%d", ga_iBlocks[client], gc_iMaxAllowedBlocks);
		}
	}
}