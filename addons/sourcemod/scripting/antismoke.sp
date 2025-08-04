#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <smlib>

#define MAX_ENTITIES 2048
#define INS_PL_BUYZONE (1 << 7)
#define SND_COUGH_MIN_CD 2
#define SND_COUGH_MAX_CD 4

const int	gc_iGasMask_ID = 34;

ArrayList	ga_hDetonatedSmokeRef;

ConVar		g_cvCough,
			g_cvShoot,
			g_cvShake;

bool		g_bLateLoad,
			ga_bPlayerWeaponFocused[MAXPLAYERS + 1] = {false, ...},
			g_bShoot,
			ga_bBotFireWeapon[MAXPLAYERS + 1] = {false, ...},
			g_bShake;

int			g_iCough,
			g_iPlayerEquipGear,
			ga_iConfirmedHelmet[MAXPLAYERS + 1],
			ga_iSoundCoughCd[MAXPLAYERS + 1],
			ga_iPlayerCoughedNearNadeRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};

float		ga_fSoundNadeInvestCd[MAX_ENTITIES + 1] = {0.0, ...},
			ga_fSoundBotInvestCd[MAXPLAYERS + 1] = {0.0, ...},
			ga_fSoundNadeFireCd[MAX_ENTITIES + 1] = {0.0, ...},
			ga_fSoundBotFireCd[MAXPLAYERS + 1] = {0.0, ...};

public Plugin myinfo = {
	name = "antismoke",
	author = "Nullifidian",
	description = "Makes players and bots cough in smoke and triggers other effects if they are not wearing a gas mask or are not in focus (holding breath).",
	version = "1.1",
	url = ""
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

	char sBuffer[64];
	for (int i = 1; i <= 2; i++) {
		FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/ins_bot_idle_cough_0%d.ogg", i);
		PrecacheSound(sBuffer);
	}

	for (int i = 11; i <= 16; i++) {
		FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/investigating%d.ogg", i);
		PrecacheSound(sBuffer);
	}

	for (int i = 10; i <= 15; i++) {
		FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/fire%d.ogg", i);
		PrecacheSound(sBuffer);
	}

	ga_hDetonatedSmokeRef = new ArrayList();

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("grenade_detonate", Event_GrenadeDetonate);

	HookEvent("weapon_focus_enter", Event_WeaponFocusEnter);
	HookEvent("weapon_focus_exit", Event_WeaponFocusExit);

	HookEvent("round_start", Event_RoundStart);

	AddCommandListener(CmdListener, "inventory_resupply");
	AddCommandListener(CmdListener, "inventory_confirm");

	g_cvCough = CreateConVar("sm_antismoke_cough", "1.0", "Enable cough sounds? [0 = off, 1 = for all, 2 = players only, 3 = bots only]", FCVAR_NONE, true, 0.0, true, 3.0);
	g_iCough = g_cvCough.IntValue;
	g_cvCough.AddChangeHook(OnConVarChanged);

	g_cvShoot = CreateConVar("sm_antismoke_shoot", "1.0", "Bot will shoot if he heard player cough and he is in bot's crosshair [0 = off, 1 = on]", FCVAR_NONE, true, 0.0, true, 1.0);
	g_bShoot = g_cvShoot.BoolValue;
	g_cvShoot.AddChangeHook(OnConVarChanged);

	g_cvShake = CreateConVar("sm_antismoke_shake", "1.0", "Shake player's screen when coughing? [0 = off, 1 = on]", FCVAR_NONE, true, 0.0, true, 1.0);
	g_bShake = g_cvShake.BoolValue;
	g_cvShake.AddChangeHook(OnConVarChanged);

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i)) {
				continue;
			}
			if (!IsFakeClient(i)) {
				ConfirmEquipment(i);
			}
			ga_iSoundCoughCd[i] = GetRandomInt(SND_COUGH_MIN_CD, SND_COUGH_MAX_CD);
		}
	}
}

public void OnMapStart() {
	ResetGlobalNadeCooldowns();
	CreateTimer(1.0, TimerR_SmokeCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client) {
	ga_iSoundCoughCd[client] = GetRandomInt(SND_COUGH_MIN_CD, SND_COUGH_MAX_CD);
	ga_iPlayerCoughedNearNadeRef[client] = INVALID_ENT_REFERENCE;
	ga_bPlayerWeaponFocused[client] = false;
}

public void OnClientDisconnect(int client) {
	ga_fSoundBotInvestCd[client] = 0.0;
	ga_fSoundBotFireCd[client] = 0.0;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	ga_hDetonatedSmokeRef.Clear();
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsClientInGame(client) && !IsFakeClient(client)) {
		ConfirmEquipment(client);
	}
	return Plugin_Continue;
}

public Action CmdListener(int client, const char[] cmd, int argc) {
	if (IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client)) {
		if ((GetEntProp(client, Prop_Send, "m_iPlayerFlags") & INS_PL_BUYZONE)) {
			ConfirmEquipment(client);
		}
	}
	return Plugin_Continue;
}

public Action Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast) {
	int iGrenadeId = event.GetInt("entityid");
	if (!IsValidEntity(iGrenadeId)) {
		return Plugin_Continue;
	}

	char sGrenadeName[32];
	if (!GetEntityClassname(iGrenadeId, sGrenadeName, sizeof(sGrenadeName))) {
		return Plugin_Continue;
	}
	
	if (StrContains(sGrenadeName, "m18", false) == -1 && StrContains(sGrenadeName, "smoke", false) == -1) {
		return Plugin_Continue;
	}

	ga_hDetonatedSmokeRef.Push(EntIndexToEntRef(iGrenadeId));

	return Plugin_Continue;
}

public Action Event_WeaponFocusEnter(Event event, const char[] name, bool dontBroadcast) {
	ga_bPlayerWeaponFocused[GetClientOfUserId(event.GetInt("userid"))] = true;
	return Plugin_Continue;
}

public Action Event_WeaponFocusExit(Event event, const char[] name, bool dontBroadcast) {
	ga_bPlayerWeaponFocused[GetClientOfUserId(event.GetInt("userid"))] = false;
	return Plugin_Continue;
}

Action TimerR_SmokeCheck(Handle timer) {
	if (ga_hDetonatedSmokeRef.Length < 1) {
		return Plugin_Continue;
	}

	int		iEnt,
			iAimTarget,
			iNearestBot;
			
	float	fEntPos[3],
			fPlayerPos[3],
			fTargetPos[3],
			fDistance,
			fTempDistance,
			fNearestDistance = -1.0;

	char	sBuffer[64];
	
	for (int i = 1; i < MaxClients; i++) {
		if (ga_hDetonatedSmokeRef.Length < 1) {
			break;
		}

		if (!IsClientInGame(i) || !IsPlayerAlive(i)) {
			continue;
		}

		if (ga_iConfirmedHelmet[i] == gc_iGasMask_ID) {
			continue;
		}

		if (ga_bPlayerWeaponFocused[i]) {
			ga_iPlayerCoughedNearNadeRef[i] = INVALID_ENT_REFERENCE;
			ga_iSoundCoughCd[i]--;
			continue;
		}

		float fTime = GetGameTime();
		for (int j = (ga_hDetonatedSmokeRef.Length - 1); j >= 0; j--) {
			iEnt = EntRefToEntIndex(ga_hDetonatedSmokeRef.Get(j));

			if (iEnt == INVALID_ENT_REFERENCE || !IsValidEntity(iEnt)) {
				ga_hDetonatedSmokeRef.Erase(j);
				continue;
			}

			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fEntPos);
			GetClientAbsOrigin(i, fPlayerPos);

			fDistance = GetVectorDistance(fEntPos, fPlayerPos);

			if (IsFakeClient(i)) {
				ga_bBotFireWeapon[i] = false;
				if (g_bShoot && fDistance < 1200) {
					iAimTarget = GetClientAimTarget(i, true);
					if (iAimTarget > 0 && EntRefToEntIndex(ga_iPlayerCoughedNearNadeRef[iAimTarget]) == iEnt) {
						GetClientAbsOrigin(iAimTarget, fTargetPos);
						if (GetVectorDistance(fEntPos, fTargetPos) < 290) {
							if (ga_fSoundNadeFireCd[iEnt] <= fTime) {
								FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/fire%d.ogg", GetRandomInt(10, 15));
								EmitSoundToAll(sBuffer, i, SNDCHAN_VOICE, _, _, 1.0);
								ga_fSoundNadeFireCd[iEnt] = fTime + 10.0;
								ga_fSoundBotFireCd[i] = fTime + 5.0;
							}
							ga_bBotFireWeapon[i] = true;
						}
					}
				}

				if (g_iCough != 1 && g_iCough != 3) {
					continue;
				}
			}
			else if (g_iCough != 1 && g_iCough !=2) {
				continue;
			}

			if (fDistance > 290) {
				continue;
			}

			if (--ga_iSoundCoughCd[i] <= 0) {
				if (!IsFakeClient(i)) {
					ga_iPlayerCoughedNearNadeRef[i] = EntIndexToEntRef(iEnt);
					//PrintHintText(i, "You are giving away your position! Hold your breath (focus: aim + sprint)");
					if (g_bShake) {
						Client_Shake(i, SHAKE_START, 1.0, 150.0, 1.0);
					}
				}

				FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/ins_bot_idle_cough_0%d.ogg", GetRandomInt(1, 2));
				EmitSoundToAll(sBuffer, i, SNDCHAN_VOICE, _, _, 1.0);
				ga_iSoundCoughCd[i] = GetRandomInt(SND_COUGH_MIN_CD, SND_COUGH_MAX_CD);


				return Plugin_Continue;
			}

			if (ga_fSoundNadeInvestCd[iEnt] <= fTime && !IsFakeClient(i)) {
				iNearestBot = 0;
				for (int k = 1; k <= MaxClients; k++) {
					if (!IsClientInGame(k) || !IsPlayerAlive(k) || !IsFakeClient(k)) {
						continue;
					}

					GetClientAbsOrigin(k, fTargetPos);
					fTempDistance = GetVectorDistance(fPlayerPos, fTargetPos);
					
					if (fTempDistance < fNearestDistance || fNearestDistance == -1) {
						fNearestDistance = fTempDistance;
						iNearestBot = k;
					}
				}

				if (iNearestBot > 0 && IsClientInGame(iNearestBot) && IsFakeClient(iNearestBot) && IsPlayerAlive(iNearestBot) && ga_fSoundBotInvestCd[iNearestBot] <= fTime) {
					FormatEx(sBuffer, sizeof(sBuffer), "player/voice/bot/investigating%d.ogg", GetRandomInt(11, 16));
					EmitSoundToAll(sBuffer, iNearestBot, SNDCHAN_VOICE, _, _, 1.0);
					ga_fSoundNadeInvestCd[iEnt] = fTime + 10.0;
					ga_fSoundBotInvestCd[iNearestBot] = fTime + 5.0;
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
	if (ga_bBotFireWeapon[client]) {
		if (!IsClientInGame(client) || !IsFakeClient(client) || GetClientTeam(client) != 3 || !IsPlayerAlive(client)) {
			ga_bBotFireWeapon[client] = false;
			return Plugin_Continue;
		}
	} else {
		return Plugin_Continue;
	}

	int	iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iActiveWeapon < 1) {
		ga_bBotFireWeapon[client] = false;
		return Plugin_Continue;
	}

	if (GetEntProp(iActiveWeapon, Prop_Send, "m_iClip1") > 0) {
		buttons |= IN_ATTACK;
		return Plugin_Changed;
	} else {
		ga_bBotFireWeapon[client] = false;
	}

	return Plugin_Continue;
}

void ConfirmEquipment(int client) {
	ga_iConfirmedHelmet[client] = GetEntData(client, g_iPlayerEquipGear + (4 * 1));
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvCough) {
		g_iCough = g_cvCough.IntValue;
	}
	else if (convar == g_cvShoot) {
		g_bShoot = g_cvShoot.BoolValue;
	}
	else if (convar == g_cvShake) {
		g_bShake = g_cvShake.BoolValue;
	}
}

void ResetGlobalNadeCooldowns() {
	for (int i = 0; i <= MAX_ENTITIES; i++) {
		ga_fSoundNadeInvestCd[i] = 0.0;
		ga_fSoundNadeFireCd[i] = 0.0;
	}
}