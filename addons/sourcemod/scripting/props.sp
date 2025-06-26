#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define MAXENTITIES 2048
#define MAX_BUTTONS 29

#define INS_PL_BUYZONE (1 << 7)
#define INS_DEPLOY_BIPOD (1 << 1)
#define INS_ATTACK1 (1 << 0)
#define INS_JUMP (1 << 1)
#define INS_DUCK (1 << 2)
#define INS_PRONE (1 << 3)
#define INS_FORWARD (1 << 4)
#define INS_BACKWARD (1 << 5)
#define INS_USE (1 << 6)
#define INS_LEFT (1 << 9)
#define INS_RIGHT (1 << 10)
#define INS_RELOAD (1 << 11)
#define INS_FIREMODE (1 << 12)
#define INS_LEAN_LEFT (1 << 13)
#define INS_LEAN_RIGHT (1 << 14)
#define INS_SPRINT (1 << 15)
#define INS_WALK (1 << 16)
#define INS_SPECIAL1 (1 << 17)
#define INS_AIM (1 << 18)
#define INS_SCOREBOARD (1 << 19)
#define INS_FLASHLIGHT (1 << 22)
#define INS_AIM_TOGGLE (1 << 27)
#define INS_ACCESSORY (1 << 28)

#define DAMAGE_NO 0
#define DAMAGE_EVENTS_ONLY 1
#define DAMAGE_YES 2
#define DAMAGE_AIM 3

#define STARTBUILDPOINTS 3

#define PROP_ALPHA 125
#define PROP_ROTATE_STEP 10.0
#define PROP_DAMAGE_TAKE 20.0	// Amount of damage the prop takes each time a bot touches it, limited by PROP_TOUCH_COOLDOWN.
#define PROP_TOUCH_COOLDOWN 0.25
#define PROP_GLOWHP_PERCENT 0.25
#define PROP_HEALTH 6000
#define PROP_HOLD_DISTANCE 120.0
#define PROP_LIMIT 10
#define PROP_PLAYER_DISTANCE 50.0
#define PROP_MIN_BOT_DISTANCE 350.0	// If a bot spawns at this distance from the prop, the prop will be destroyed.
#define PROP_MIN_BOT_VERT_DISTANCE 100.0	// If a bot spawns at this vertical distance from the prop, the prop will be destroyed.

#define BOT_BLEED_COOLDOWN 2.0
#define BOT_BLEED_DAMAGE 40.0

#define MENU_COOLDOWN 2
#define MENU_STAYOPENTIME 10

#define SND_SUPPLYREFUND "ui/receivedsupply.wav"
#define SND_BUYBUILDPOINTS "ui/menu_click.wav"
#define SND_CANTBUY "ui/vote_no.wav"

ArrayList ga_hPropPlaced[MAXPLAYERS + 1];

ConVar	g_cvAllFree = null;

#define NUM_WIRESOUNDS 3
char ga_sBarbWire[NUM_WIRESOUNDS][] = {
	"doi/dynamic/barbedwire_stress_01.ogg",
	"doi/dynamic/barbedwire_stress_02.ogg",
	"doi/dynamic/barbedwire_stress_03.ogg"
};

char ga_sLmgWeapons[][] = {
	"weapon_rpk",
	"weapon_m240",
	"weapon_m249",
	"weapon_m60",
	"weapon_mg42",
	"weapon_mk46",
	"weapon_pecheneg",
	"weapon_KACStonerA1",
	"weapon_mk46"
};

char ga_sModel[][] = {
	"models/fortifications/barbed_wire_02b.mdl",
	"models/static_fortifications/sandbagwall01.mdl",
	"models/iraq/ir_twall_01.mdl",
	"models/iraq/ir_hesco_basket_01_row.mdl",
	"models/static_afghan/prop_panj_stairs.mdl",
	"models/static_afghan/prop_interior_mattress_a.mdl",
	"models/static_props/container_01_open2.mdl",
	"models/embassy/embassy_center_02.mdl",
	"models/sernix/ied_jammer/ied_jammer.mdl",
	"models/sernix/ammo_cache/ammo_cache_small.mdl"
};

int ga_iModelCosts[sizeof(ga_sModel)] = {
	2, // Build cost for "models/fortifications/barbed_wire_02b.mdl"
	1, // Build cost for "models/static_fortifications/sandbagwall01.mdl"
	3, // Build cost for "models/iraq/ir_twall_01.mdl"
	4, // Build cost for "models/iraq/ir_hesco_basket_01_row.mdl"
	1, // Build cost for "models/static_afghan/prop_panj_stairs.mdl"
	2, // Build cost for "models/static_afghan/prop_interior_mattress_a.mdl"
	5, // Build cost for "models/static_props/container_01_open2.mdl"
	6, // Build cost for "models/embassy/embassy_center_02.mdl"
	5, // Build cost for "models/sernix/ied_jammer/ied_jammer.mdl"
	8  // Build cost for "models/sernix/ammo_cache/ammo_cache_small.mdl"
};

// List of props that allowed and not allowed to block explosion if player behind this prop
bool ga_bModelBlockExplosiveDamage[sizeof(ga_sModel)] = {
	false, // "models/fortifications/barbed_wire_02b.mdl"
	true, // "models/static_fortifications/sandbagwall01.mdl"
	true, // "models/iraq/ir_twall_01.mdl"
	true, // "models/iraq/ir_hesco_basket_01_row.mdl"
	false, // "models/static_afghan/prop_panj_stairs.mdl"
	false, // "models/static_afghan/prop_interior_mattress_a.mdl"
	true, // "models/static_props/container_01_open2.mdl"
	true, // "models/embassy/embassy_center_02.mdl"
	false, // "models/sernix/ied_jammer/ied_jammer.mdl"
	false  // "models/sernix/ammo_cache/ammo_cache_small.mdl"
};

char ga_sLastInflictorModel[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

int ga_iPropHolding[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...},
	ga_iModelIndex[MAXPLAYERS + 1] = {0, ...},
	g_iSpawnTime,
	ga_iLastButtons[MAXPLAYERS + 1],
	ga_iLastInflictor[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...},
	ga_iEntIdBipodDeployedOn[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...},
	ga_iPlayerBuildPoints[MAXPLAYERS + 1] = {STARTBUILDPOINTS, ...},
	ga_iPropOwner[MAXPLAYERS + 1] = {0, ...},
	ga_iShopMenuCooldown[MAXPLAYERS + 1] = {0, ...},
	ga_iTokensSpent[MAXPLAYERS + 1] = {0, ...},
	ga_iPropMenuCooldown[MAXPLAYERS + 1] = {0, ...},
	g_iAllFree;

bool ga_bHelpMenuOpen[MAXPLAYERS + 1] = {false, ...},
	ga_bPropRotateMenuOpen[MAXPLAYERS + 1] = {false, ...},
	ga_bBuildMenuOpen[MAXPLAYERS + 1] = {false, ...},
	ga_bIgnoreRemoval[MAXPLAYERS + 1] = {false, ...},
	ga_bHoldingMeleeWeapon[MAXPLAYERS + 1] = {false, ...},
	g_bLateLoad,
	ga_bBipodForced[MAXPLAYERS + 1] = {false, ...},
	ga_bPlayerRefund[MAXPLAYERS + 1] = {false, ...},
	ga_bFirstTimeJoinedSquad[MAXPLAYERS + 1] = {true, ...};

float ga_fPropSoundCooldown[MAXENTITIES + 1] = {0.0, ...},
	ga_fBotBleedCooldown[MAXPLAYERS + 1] = {0.0, ...},
	ga_fPropRotations[MAXPLAYERS + 1][sizeof(ga_sModel)][3],
	ga_fLastTouchTime[MAXPLAYERS + 1] = {0.0, ...};


public Plugin myinfo = {
	name        = "props",
	author      = "Nullifidian",
	description = "Spawn props",
	version     = "2.6"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	g_iSpawnTime = FindSendPropInfo("CINSPlayer", "m_flSpawnTime");
	if (g_iSpawnTime == -1) {
		SetFailState("Offset \"m_flSpawnTime\" not found!");
	}

	SetupConVars();
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath_Pre, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_pick_squad", Event_PlayerPickSquad);

	HookEvent("object_destroyed", Event_ObjectiveDone, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", Event_ObjectiveDone, EventHookMode_PostNoCopy);

	RegConsoleCmd("prophelp", cmd_prophelp, "Open help menu.");

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i)) {
				continue;
			}

			if (IsFakeClient(i)) {
				SDKHook(i, SDKHook_OnTakeDamage, BotOnTakeDamage);
				continue;
			}

			SDKHook(i, SDKHook_OnTakeDamage, PlayerOnTakeDamage);

			ga_hPropPlaced[i] = CreateArray();
			if (ga_hPropPlaced[i] == INVALID_HANDLE) {
				LogError("Failed to create array for client %d", i);
			}

			if (IsHoldingMeleeWeapon(i)) {
				ga_bHoldingMeleeWeapon[i] = true;
			}
			SDKHook(i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitch);
			SetModelIndex(i); // Ensure the model index is set to one that the player can afford.
		}
	}
}

public void OnMapStart() {
	PrecacheFiles();
}

public void OnClientPostAdminCheck(int client) {
	if (client > 0) {
		if (!IsFakeClient(client)) {
			SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitch);
			SDKHook(client, SDKHook_OnTakeDamage, PlayerOnTakeDamage);
			ga_hPropPlaced[client] = CreateArray();
			if (ga_hPropPlaced[client] == INVALID_HANDLE) {
				LogError("Failed to create array for client %d", client);
			}
			ga_bBipodForced[client] = false;
			ga_bFirstTimeJoinedSquad[client] = true;
		} else {
			SDKHook(client, SDKHook_OnTakeDamage, BotOnTakeDamage);
		}
	}
}

public void OnClientDisconnect(int client) {
	if (IsFakeClient(client)) {
		return;
	}

	ga_iLastButtons[client] = 0;

	StopHolding(client);

	if (ga_hPropPlaced[client] == INVALID_HANDLE) {
		return;
	}

	int iArraySize = ga_hPropPlaced[client].Length;
	bool removed = false;
	
	if (iArraySize > 0) {
		int ent;
		for (int i = iArraySize - 1; i >= 0; i--) {
			ent = EntRefToEntIndex(ga_hPropPlaced[client].Get(i));
			if (ent > MaxClients && IsValidEntity(ent)) {
				RemoveEntity(ent);
				removed = true;
			}
		}
	}

	if (removed) {
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || i == client) {
				continue;
			}
			if (ga_iPropOwner[i] == client) {
				ga_iPropOwner[i] = 0;
			}
		}
	}
	
	delete ga_hPropPlaced[client];
}

public Action Event_PlayerPickSquad(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client)) {
		return Plugin_Continue;
	}

	if (ga_bFirstTimeJoinedSquad[client]) {
		ga_bFirstTimeJoinedSquad[client] = false;
		ga_bPlayerRefund[client] = false;
	} else {
		DeconstructAllProps(client);
		ga_bPlayerRefund[client] = true;
	}

	ga_iTokensSpent[client] = 0;
	RestoreBuildPoints(client);
	SetModelIndex(client); // Ensure the model index is set to one that the player can afford.

	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}
		ga_iPropHolding[i] = INVALID_ENT_REFERENCE;
		ga_iPropOwner[i] = 0;
		ga_bPlayerRefund[i] = false;
		RestoreBuildPoints(i);
	}
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1) {
		return Plugin_Continue;
	}

	if (!IsFakeClient(client)) {
		ga_bBipodForced[client] = false;
		ga_iEntIdBipodDeployedOn[client] = INVALID_ENT_REFERENCE;
	} else {
		for (int i = 1; i <= MaxClients; i++) {
			if (ga_hPropPlaced[i] == INVALID_HANDLE || ga_hPropPlaced[i].Length < 1) {
				continue;
			}

			// Initialize variables only when there are props placed
			int iArraySize = ga_hPropPlaced[i].Length, ent, removedCount = 0;
			float vPos[3], vPosClient[3];
			char message[256] = "", temp[64], finalMessage[256];

			for (int j = iArraySize - 1; j >= 0; j--) {
				ent = EntRefToEntIndex(ga_hPropPlaced[i].Get(j));
				if (ent <= MaxClients || !IsValidEntity(ent)) {
					continue;
				}

				GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
				GetClientAbsOrigin(client, vPosClient);
				if (GetVectorDistance(vPos, vPosClient, true) <= (PROP_MIN_BOT_DISTANCE * PROP_MIN_BOT_DISTANCE) &&
					FloatAbs(vPos[2] - vPosClient[2]) <= PROP_MIN_BOT_VERT_DISTANCE) {
					
					FormatEx(temp, sizeof(temp), " #%d", j + 1);
					StrCat(message, sizeof(message), temp);
					RemoveEntity(ent);
					removedCount++;
				}
			}

			if (removedCount > 0) {
				if (removedCount == 1) {
					FormatEx(finalMessage, sizeof(finalMessage), "Your prop%s was removed for being placed too close to a bot spawn.", message);
				} else {
					FormatEx(finalMessage, sizeof(finalMessage), "Your props%s were removed for being placed too close to a bot spawn.", message);
				}
				PrintHintText(i, "%s", finalMessage);
			}
		}
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath_Pre(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || !IsClientInGame(victim)) {
		return Plugin_Continue;
	}

	if (IsFakeClient(victim)) {
		int inflictor = EntRefToEntIndex(ga_iLastInflictor[victim]);

		if (inflictor != INVALID_ENT_REFERENCE && IsValidEntity(inflictor)) {
			char inflictorClassname[64];
			GetEntityClassname(inflictor, inflictorClassname, sizeof(inflictorClassname));
			if (strcmp(inflictorClassname, "prop_dynamic", false) == 0) {
				char sModelName[PLATFORM_MAX_PATH];
				GetEntPropString(inflictor, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));

				if (strcmp(sModelName, "models/fortifications/barbed_wire_02b.mdl") == 0) {
					event.SetString("weapon", "Barbed Wire");
					return Plugin_Changed;
				}
			}
		} else if (strcmp(ga_sLastInflictorModel[victim], "models/fortifications/barbed_wire_02b.mdl") == 0) {
			// Use the stored model name if the entity is no longer valid
			event.SetString("weapon", "Barbed Wire");
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}

	StopHolding(victim);
	
	return Plugin_Continue;
}

public Action Event_ObjectiveDone(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}
		ga_bPlayerRefund[i] = false;
		RestoreBuildPoints(i);
	}
	return Plugin_Continue;
}

void HoldProp(int client) {
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client) || ga_iPropHolding[client] != INVALID_ENT_REFERENCE) {
		return;
	}

	float vPos[3], vAng[3];
	GetClientEyePosition(client, vPos);
	GetClientEyeAngles(client, vAng);
	GetPositionInFront(vPos, vAng, PROP_HOLD_DISTANCE);

	CreateProp(client, vPos, NULL_VECTOR);
}

void StopHolding(int client) {
	if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE) {
		int ent = EntRefToEntIndex(ga_iPropHolding[client]);
		if (ent > MaxClients && IsValidEntity(ent)) {
			ga_bIgnoreRemoval[client] = true;
			RemoveEntity(ent);
			ga_bIgnoreRemoval[client] = false;
		}
		ga_iPropHolding[client] = INVALID_ENT_REFERENCE;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client)) {
		return Plugin_Continue;
	}

	int button;
	for (int i = 0; i < MAX_BUTTONS; i++) {
		button = (1 << i);
		if (buttons & button) {
			if (!(ga_iLastButtons[client] & button)) {
				OnButtonPress(client, button, vel);
			}
		}
	}
	ga_iLastButtons[client] = buttons;

	if (!ga_bHoldingMeleeWeapon[client]) {
		return Plugin_Continue;
	}

	int ent = EntRefToEntIndex(ga_iPropHolding[client]);
	if (ent > MaxClients && IsValidEntity(ent)) {
		// Move prop in front of the player
		float vAng[3];
		GetClientEyeAngles(client, vAng);

		float vPos[3];
		GetClientEyePosition(client, vPos);
		GetPositionInFront(vPos, vAng, PROP_HOLD_DISTANCE);
		TeleportEntity(ent, vPos, NULL_VECTOR, NULL_VECTOR);
	}
	return Plugin_Continue;
}

void OnButtonPress(int client, int button, float vel[3]) {
	if (button & INS_SPRINT || button & INS_ATTACK1) {
		StopHolding(client);
		if (ga_bHelpMenuOpen[client]) {
			ga_bHelpMenuOpen[client] = false;
			ClientCommand(client, "slot9");
		} else if (ga_bPropRotateMenuOpen[client]) {
			ClientCommand(client, "slot9");
		} else if (ga_bBuildMenuOpen[client]) {
			ClientCommand(client, "slot9");
		}
		return;
	}

	if (button & INS_SPECIAL1) {
		// Deploy bipod on sandbag
		if (!ga_bHoldingMeleeWeapon[client]) {
			if (WeaponWithBipod(client)) {
				switch (ga_bBipodForced[client]) {
					case false: {
						int target = GetClientAimTarget(client, false);
						if (target <= MaxClients) {
							return;
						}

						char sName[64];
						GetEntPropString(target, Prop_Data, "m_iName", sName, sizeof(sName));
						if (StrContains(sName, "bmprop_c#", true) == -1) {
							return;
						}

						char sModelName[PLATFORM_MAX_PATH];
						GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));

						if (StrContains(sModelName, "sandbagwall01", false) == -1) {
							return;
						}

						float vPos[3], vPosClient[3], vAng[3];
						GetEntPropVector(target, Prop_Send, "m_vecOrigin", vPos);
						GetClientAbsOrigin(client, vPosClient);

						if (GetVectorDistance(vPos, vPosClient) <= 43.0) {
							float fHeight = (vPosClient[2] - vPos[2]);
							if (fHeight <= 10.0 && fHeight >= -10.0) {
								GetClientEyeAngles(client, vAng);
								DataPack hDatapack;
								CreateDataTimer(0.1, Timer_ForceDeployBipod, hDatapack);
								hDatapack.WriteCell(client);
								hDatapack.WriteCell(EntIndexToEntRef(target));
								hDatapack.WriteFloat(vAng[1]);
							}
						}
					}
					case true: {
						ga_bBipodForced[client] = false;
						ga_iEntIdBipodDeployedOn[client] = 0;
					}
				}
			}
		} else {
			int currentTime = GetTime();
			if (currentTime - ga_iPropMenuCooldown[client] < MENU_COOLDOWN) {
				PrintCenterText(client, "You must wait before opening the menu again.");
				return;
			}

			ga_iPropMenuCooldown[client] = currentTime;

			OpenPropSelectionMenu(client);
		}
		return;
	}

	if (ga_bBipodForced[client]) {
		if (button & INS_JUMP || button & INS_DUCK || button & INS_FORWARD || button & INS_BACKWARD || button & INS_LEFT || button & INS_RIGHT) {
			ga_bBipodForced[client] = false;
			ga_iEntIdBipodDeployedOn[client] = 0;
		}
	}

	if (!ga_bHoldingMeleeWeapon[client]) {
		return;
	}

	if (button & INS_FIREMODE) {
		if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE) {
			OpenShopMenu(client);
			return;
		}
	}
	
	if (button & INS_AIM || button & INS_AIM_TOGGLE) {
		if (!ga_bHoldingMeleeWeapon[client]) {
			return;
		}

		if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE) {
			int target = GetClientAimTarget(client, false);

			if (target <= MaxClients || !IsValidEntity(target)) {
				return;
			}

			char sName[64];
			GetEntPropString(target, Prop_Data, "m_iName", sName, sizeof(sName));
			
			if (StrContains(sName, "bmprop_c#", true) != -1) {
				char sModelName[PLATFORM_MAX_PATH];
				GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
				// Block ammo bag moving to stop resupply limit reset.
				if (strcmp(sModelName, "models/sernix/ammo_cache/ammo_cache_small.mdl") == 0) {
					return;
				}

				if (IsPlayerOnProp(client)) {
					PrintCenterText(client, "You cannot move props while standing on one.");
					return;
				}

				// Prevent picking up the prop while the player is not on the ground.
				if (IsPlayerOnGround(client) != 1) {
					return;
				}

				float vPos[3], vAng[3];
				GetEntPropVector(target, Prop_Send, "m_vecOrigin", vPos);
				GetEntPropVector(target, Prop_Send, "m_angRotation", vAng);

				int propOwner = GetNumber(sName, "_c#"),
					iArraySize = ga_hPropPlaced[propOwner].Length;
					
				if (iArraySize > 0) {
					int ent;
					for (int j = iArraySize - 1; j >= 0; j--) {
						ent = EntRefToEntIndex(ga_hPropPlaced[propOwner].Get(j));
						if (ent == target) {
							ga_hPropPlaced[propOwner].Erase(j);
							break;
						}
					}
				}

				int health = GetEntProp(target, Prop_Data, "m_iHealth");
				RemoveEntity(target);
				ga_iModelIndex[client] = GetNumber(sName, "_m#");

				ga_iPropOwner[client] = propOwner;

				CreateProp(client, vPos, vAng, health);
			} else {
				HoldProp(client);
			}
			return;
		} else {
			int ent = EntRefToEntIndex(ga_iPropHolding[client]);
			if (ent <= MaxClients || !IsValidEntity(ent)) {
				return;
			}

			// Don't place it if the player is moving
			if (vel[0] != 0.0 || vel[1] != 0.0 || vel[2] != 0.0) {
				return;
			}

			// Move prop in front of the player
			float vAng[3];
			GetClientEyeAngles(client, vAng);

			float vPos[3];
			GetClientEyePosition(client, vPos);
			GetPositionInFront(vPos, vAng, PROP_HOLD_DISTANCE);

			// Check if the position is valid
			if (IsCollidingWithPlayer(client, vPos)) {
				PrintCenterText(client, "Too close to another player.");
				return;
			}
			
			TeleportEntity(ent, vPos, NULL_VECTOR, NULL_VECTOR);

			// Changing solid flag on existing prop doesn't do anything,
			// so have to spawn a new one with solid flag and delete the old one
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
			GetEntPropVector(ent, Prop_Send, "m_angRotation", vAng);

			int health = GetEntProp(ent, Prop_Data, "m_iHealth");
			StopHolding(client);
			CreateProp(client, vPos, vAng, health, true);

			PrintCenterText(client, "Prop: %d/%d", ga_hPropPlaced[client].Length, PROP_LIMIT);
		}
		return;
	}
}

void GetPositionInFront(float vPos[3], const float vAng[3], float distance) {
	float vecForward[3];
	GetAngleVectors(vAng, vecForward, NULL_VECTOR, NULL_VECTOR);

	vPos[0] += vecForward[0] * distance;
	vPos[1] += vecForward[1] * distance;
	vPos[2] += vecForward[2] * distance;
}

int IsPlayerOnGround(int client) {
	return GetEntityFlags(client) & FL_ONGROUND;
}

void CreateProp(int client, float vPos[3], float vAng[3], int oldhealth = 0, bool solid = false) {
	if (IsPlayerOnGround(client) != 1) {
		PrintHintText(client, "You cannot build a prop while falling!");
		return;
	}

	int modelIndex = ga_iModelIndex[client], buildCost;
	
	if (g_iAllFree == 1) {
		buildCost = 0;
	} else {
		buildCost = ga_iModelCosts[modelIndex];
	}

	if (!ga_iPropOwner[client] && !HasEnoughResources(client, buildCost)) {
		if (solid) {
			PrintCenterText(client, "You don't have enough resources to build. Press 'Cycle Firemode' to open the shop menu.");
			return;
		} else if (SetModelIndex(client)) { // Ensure the model index is set to one that the player can afford.
			modelIndex = ga_iModelIndex[client];
			buildCost = ga_iModelCosts[modelIndex];
		} else {
			PrintCenterText(client, "You don't have enough resources to build. Press 'Cycle Firemode' to open the shop menu.");
			return;
		}
	}

	int prop = CreateEntityByName("prop_dynamic_override");
	if (prop != -1) {
		DispatchKeyValue(prop, "physdamagescale", "0.0");
		DispatchKeyValue(prop, "model", ga_sModel[modelIndex]);
		if (solid) {
			char PropName[64];
			DispatchKeyValue(prop, "solid", "6");

			if (!ga_iPropOwner[client]) {
				ga_iPlayerBuildPoints[client] -= buildCost;
				ClearOldestPropIfLimitReached(client); // If prop limit reached for the player, delete the oldest prop
				TeleportEntity(prop, vPos, ga_fPropRotations[client][modelIndex], NULL_VECTOR); // Use stored rotation
				PushArrayCell(ga_hPropPlaced[client], EntIndexToEntRef(prop));
				FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", client, modelIndex);
			} else {
				TeleportEntity(prop, vPos, vAng, NULL_VECTOR);

				// In rare cases ga_hPropPlaced[ga_iPropOwner[client]] can be INVALID_HANDLE, so we need to check again.
				if (ga_hPropPlaced[ga_iPropOwner[client]] != INVALID_HANDLE) {
					PushArrayCell(ga_hPropPlaced[ga_iPropOwner[client]], EntIndexToEntRef(prop));
					FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", ga_iPropOwner[client], modelIndex);
				} else {
					ClearOldestPropIfLimitReached(client); // If prop limit reached for the player, delete the oldest prop
					PushArrayCell(ga_hPropPlaced[client], EntIndexToEntRef(prop));
					FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", client, modelIndex);
					oldhealth = 0;
				}

				ga_iPropOwner[client] = 0;
			}

			if (strcmp(ga_sModel[modelIndex], "models/sernix/ammo_cache/ammo_cache_small.mdl") == 0) {
				SetVariantColor({255, 255, 102, 255});
				SetEntityRenderMode(prop, RENDER_NORMAL);
				SetEntityRenderColor(prop, 255, 255, 255, 255);
				AcceptEntityInput(prop, "SetGlowColor");
				SetEntProp(prop, Prop_Send, "m_bShouldGlow", true);
				SetEntPropFloat(prop, Prop_Send, "m_flGlowMaxDist", 1600.0);
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			} else if (strcmp(ga_sModel[modelIndex], "models/sernix/ied_jammer/ied_jammer.mdl") == 0) {
				SetVariantColor({80, 210, 255, 255});
				SetEntityRenderMode(prop, RENDER_NORMAL);
				AcceptEntityInput(prop, "SetGlowColor");
				SetEntProp(prop, Prop_Send, "m_bShouldGlow", true);
				SetEntPropFloat(prop, Prop_Send, "m_flGlowMaxDist", 600.0);
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			} else if (strcmp(ga_sModel[modelIndex], "models/fortifications/barbed_wire_02b.mdl") == 0) {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchWire);
			} else if (strcmp(ga_sModel[modelIndex], "models/static_afghan/prop_interior_mattress_a.mdl") == 0) {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchMattress);
			} else {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			}

			DispatchKeyValue(prop, "targetname", PropName);
			SDKHook(prop, SDKHook_OnTakeDamage, PropOnTakeDamage);

			if (ga_bPropRotateMenuOpen[client]) {
				ClientCommand(client, "slot9"); // Close rotation menu
			}
		} else {
			DispatchKeyValue(prop, "solid", "0");
			DispatchKeyValue(prop, "disableshadows", "1");
			DispatchKeyValue(prop, "disableshadowdepth", "1");
			SetEntityRenderMode(prop, RENDER_TRANSCOLOR);
			SetEntityRenderColor(prop, 255, 255, 255, PROP_ALPHA);
			ga_iPropHolding[client] = EntIndexToEntRef(prop);

			if (ga_iPropOwner[client] > 0 && IsClientInGame(ga_iPropOwner[client])) {
				TeleportEntity(prop, vPos, vAng, NULL_VECTOR);
				PrintCenterText(client, "Built by: %N", ga_iPropOwner[client]);
				OpenRotationMenu(client);
			} else {
				TeleportEntity(prop, vPos, ga_fPropRotations[client][modelIndex], NULL_VECTOR); // Use stored rotation
			}
		}

		DispatchSpawn(prop);
		SetEntityMoveType(prop, MOVETYPE_NONE);
		SetEntProp(prop, Prop_Data, "m_takedamage", DAMAGE_YES);

		if (oldhealth > 0) {
			SetEntProp(prop, Prop_Data, "m_iHealth", oldhealth > 0 ? oldhealth : PROP_HEALTH);
			GlowLowHp(prop, oldhealth);
		} else {
			SetEntProp(prop, Prop_Data, "m_iHealth", PROP_HEALTH);
		}

		SetEntProp(prop, Prop_Data, "m_iMaxHealth", PROP_HEALTH);
	} else {
		PrintCenterText(client, "Failed to create prop.");
	}
}

void ClearOldestPropIfLimitReached(int client) {
	int ent;
	while (ga_hPropPlaced[client] != INVALID_HANDLE && ga_hPropPlaced[client].Length >= PROP_LIMIT && PROP_LIMIT > 1) {
		ent = EntRefToEntIndex(ga_hPropPlaced[client].Get(0));
		if (ent > MaxClients && IsValidEntity(ent)) {
			ga_bIgnoreRemoval[client] = true;
			RemoveEntity(ent);
			ga_bIgnoreRemoval[client] = false;
		}
		ga_hPropPlaced[client].Erase(0);
	}
}

int GetNumber(const char[] str, const char[] substr) {
	// Find the position of the substring in the string
	int pos = StrContains(str, substr, false);
	if (pos == -1) {
		return -1; // Return an error value if the substring is not found
	}

	// Move the position to start after the substring
	pos += strlen(substr);

	// Extract the number part as a substring
	char numberStr[32];
	strcopy(numberStr, sizeof(numberStr), str[pos]);

	// Convert the extracted substring to an integer
	return StringToInt(numberStr);
}

public Action SHook_OnTouchPropTakeDamage(int entity, int touch) {
	if (touch < 1 || touch > MaxClients) {
		return Plugin_Continue;
	}

	float time = GetGameTime();
	if (time - ga_fLastTouchTime[touch] < PROP_TOUCH_COOLDOWN) {
		return Plugin_Continue;
	}

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch) || GetClientTeam(touch) != 3) {
		return Plugin_Continue;
	}

	ga_fLastTouchTime[touch] = time + PROP_TOUCH_COOLDOWN;

	DoDamageToEnt(entity, touch);
	return Plugin_Continue;
}

void DoDamageToEnt(int entity, int client) {
	// When a bot touches the prop, deal damage. If the bot has been alive for half a second or less, deal damage equal to the prop's health.
	SDKHooks_TakeDamage(entity, client, client, ((GetGameTime() - GetEntDataFloat(client, g_iSpawnTime)) < 0.5) ? float(GetEntProp(entity, Prop_Data, "m_iHealth")) : PROP_DAMAGE_TAKE, DMG_SLASH, -1, NULL_VECTOR, NULL_VECTOR, false);
}

public Action SHook_OnTouchMattress(int entity, int touch) {
	if (touch < 1 || touch > MaxClients) {
		return Plugin_Continue;
	}

	float time = GetGameTime();
	if (time - ga_fLastTouchTime[touch] < PROP_TOUCH_COOLDOWN) {
		return Plugin_Continue;
	}

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch)) {
		return Plugin_Continue;
	}

	if (entity == GetEntPropEnt(touch, Prop_Send, "m_hGroundEntity") && GetEntProp(touch, Prop_Send, "m_iCurrentStance") != 2) {
		SetEntPropVector(touch, Prop_Data, "m_vecBaseVelocity", {0.0, 0.0, 500.0});
		PlayWireSound(entity);
	}

	ga_fLastTouchTime[touch] = time + PROP_TOUCH_COOLDOWN;

	if (GetClientTeam(touch) == 3) {
		DoDamageToEnt(entity, touch);
	}

	return Plugin_Continue;
}

public Action SHook_OnTouchWire(int entity, int touch) {
	if (touch < 1 || touch > MaxClients) {
		return Plugin_Continue;
	}

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch) || GetClientTeam(touch) != 3) {
		return Plugin_Continue;
	}

	float time = GetGameTime();
	if (time >= ga_fPropSoundCooldown[entity]) {
		ga_fPropSoundCooldown[entity] = time + GetRandomFloat(2.5, 5.0);
		PlayWireSound(entity);
	}

	if (time >= ga_fBotBleedCooldown[touch]) {
		// Apply bleeding effect
		ga_fBotBleedCooldown[touch] = time + BOT_BLEED_COOLDOWN;
		int propOwner = GetPropOwner(entity);
		if (propOwner > 0) {
			SDKHooks_TakeDamage(touch, entity, propOwner, BOT_BLEED_DAMAGE, DMG_SLASH, -1, NULL_VECTOR, NULL_VECTOR, false);
			// Add particle effect
			float vPos[3];
			GetClientAbsOrigin(touch, vPos);
			CreateBleedEffect(touch, vPos);
		}
	}

	if (time - ga_fLastTouchTime[touch] >= PROP_TOUCH_COOLDOWN) {
		ga_fLastTouchTime[touch] = time + PROP_TOUCH_COOLDOWN;
		DoDamageToEnt(entity, touch);
	}

	return Plugin_Continue;
}

void PlayWireSound(int entity) {
	float vPos[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vPos);
	EmitAmbientSound(ga_sBarbWire[GetRandomInt(0, NUM_WIRESOUNDS - 1)], vPos);
}

void CreateBleedEffect(int client, float vPos[3]) {
	int particle = CreateEntityByName("info_particle_system");
	if (particle == -1) {
		PrintToServer("Failed to create particle system entity.");
		return;
	}

	DispatchKeyValue(particle, "effect_name", "blood_impact_red_01_mist");
	DispatchSpawn(particle);
	vPos[2] += 42.0;
	TeleportEntity(particle, vPos, NULL_VECTOR, NULL_VECTOR);

	// Set the particle to follow the player
	AcceptEntityInput(particle, "SetParent", client, particle, 0);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");

	// Set the particle to be removed after some time
	CreateTimer(BOT_BLEED_COOLDOWN, Timer_RemoveParticle, EntIndexToEntRef(particle));
}

public Action Timer_RemoveParticle(Handle timer, int particleRef) {
	int particle = EntRefToEntIndex(particleRef);
	if (particle != INVALID_ENT_REFERENCE && IsValidEntity(particle)) {
		RemoveEntity(particle);
	} else {
		PrintToServer("Failed to remove particle system entity. It might not exist.");
	}
	return Plugin_Stop;
}

public Action PropOnTakeDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (GlowLowHp(entity, GetEntProp(entity, Prop_Data, "m_iHealth"))) {
		SDKUnhook(entity, SDKHook_OnTakeDamage, PropOnTakeDamage);
	}
	return Plugin_Continue;
}

public Action BotOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	ga_iLastInflictor[victim] = EntIndexToEntRef(inflictor);
	return Plugin_Continue;
}

public Action PlayerOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (damagetype & DMG_FALL) {
		// Check if the victim is landing on the mattress model
		int groundEntity = GetEntPropEnt(victim, Prop_Send, "m_hGroundEntity");
		if (groundEntity > MaxClients && IsValidEntity(groundEntity)) {
			char sModelName[PLATFORM_MAX_PATH];
			GetEntPropString(groundEntity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
			if (strcmp(sModelName, "models/static_afghan/prop_interior_mattress_a.mdl") == 0) {
				PrintCenterText(victim, "Mattress cushioned your fall!");
				// Ignore fall damage
				return Plugin_Handled;
			}
		}
	}

	// Block explosive damage if a prop is between explosion source and victim
	if ((damagetype & DMG_BLAST) && IsValidEntity(inflictor) && inflictor != victim) {
		float vStart[3], vEnd[3];
		GetClientEyePosition(victim, vStart); // Start from the victim
		GetEntPropVector(inflictor, Prop_Data, "m_vecAbsOrigin", vEnd); // Go to the explosion

		Handle trace = TR_TraceRayFilterEx(vStart, vEnd, MASK_SOLID, RayType_EndPoint, TraceEntityFilterPlayers, victim);
		if (TR_DidHit(trace)) {
			int hitEnt = TR_GetEntityIndex(trace);
			if (hitEnt != victim && hitEnt > MaxClients && IsValidEntity(hitEnt)) {
				char sModelName[PLATFORM_MAX_PATH];
				
				GetEntPropString(hitEnt, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
				if (!ModelBlocksExplosion(sModelName)) {
					CloseHandle(trace);
					return Plugin_Continue;
				}

				GetModelName(sModelName, sModelName, sizeof(sModelName));
				PrintCenterText(victim, "A %s shielded you from the explosion!", sModelName);
				CloseHandle(trace);
				return Plugin_Handled;
			}
		}
		CloseHandle(trace);
	}
	return Plugin_Continue;
}

public bool TraceEntityFilterPlayers(int entity, int contentsMask, any data) {
	return (entity != data && (entity <= 0 || entity > MaxClients)); // ignore victim and all players
}

bool ModelBlocksExplosion(const char[] sModelName) {
	for (int i = 0; i < sizeof(ga_sModel); i++) {
		if (strcmp(ga_sModel[i], sModelName) == 0) {
			return ga_bModelBlockExplosiveDamage[i];
		}
	}
	return false;
}

bool GlowLowHp(int entity, int health) {
	float healthPercentage = float(health) / float(PROP_HEALTH);
	if (healthPercentage <= PROP_GLOWHP_PERCENT) {
		SetEntityRenderColor(entity, 255, 0, 0, PROP_ALPHA);
		return true;
	}
	return false;
}

public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients) {
		return;
	}

	int propOwner = GetPropOwner(entity);
	if (propOwner < 1) {
		return;
	}

	for (int i = 1; i <= MaxClients; i++) {
		// Update the model name if the entity was the last inflictor
		if (EntRefToEntIndex(ga_iLastInflictor[i]) == entity) {
			GetEntPropString(entity, Prop_Data, "m_ModelName", ga_sLastInflictorModel[i], PLATFORM_MAX_PATH);
			ga_iLastInflictor[i] = INVALID_ENT_REFERENCE;
		}

		if (ga_iEntIdBipodDeployedOn[i] == entity) {
			ga_iEntIdBipodDeployedOn[i] = INVALID_ENT_REFERENCE;
		}
	}

	int iArraySize = ga_hPropPlaced[propOwner].Length;
	if (iArraySize < 1 || ga_bIgnoreRemoval[propOwner]) {
		return;
	}

	int ent;
	for (int i = iArraySize - 1; i >= 0; i--) {
		ent = EntRefToEntIndex(ga_hPropPlaced[propOwner].Get(i));
		if (ent == entity) {
			ga_hPropPlaced[propOwner].Erase(i);
			break;
		}
	}
}

int GetPropOwner(int entity) {
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));
	if (StrContains(sName, "bmprop_c#", false) == -1) {
		return -1;
	}

	int propOwner = GetNumber(sName, "_c#");
	if (ga_hPropPlaced[propOwner] == INVALID_HANDLE) {
		return -1;
	}

	return propOwner;
}

public Action Panel_HelpInfo(int client) {
	Panel panel = new Panel();
	char sPropLimit[64];
	FormatEx(sPropLimit, sizeof(sPropLimit), "Prop limit: %d/%d \n(at max oldest deleted)", ga_hPropPlaced[client].Length, PROP_LIMIT);
	DrawPanelText(panel, sPropLimit);
	DrawPanelText(panel, " ");
	DrawPanelText(panel, "Aim = To place/move prop");
	DrawPanelText(panel, "Bipod = Build menu");
	DrawPanelText(panel, "Cycle Firemode = Shop menu");
	DrawPanelText(panel, " ");
	DrawPanelItem(panel, "Sprint or Shoot = Close menu");
	SetPanelKeys(panel, (1 << 0 | 1 << 1 | 1 << 2 | 1 << 3 | 1 << 4 | 1 << 5 | 1 << 6 | 1 << 7 | 1 << 8));
	panel.Send(client, PanelHandler1, 60);
	delete panel;
	return Plugin_Continue;
}

public int PanelHandler1(Menu menu, MenuAction action, int param1, int param2) {
	ga_bHelpMenuOpen[param1] = false;
	return 0;
}

bool WeaponWithBipod(int client) {
	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon < 1) {
		return false;
	}

	int upgradeslot = GetEntSendPropOffs(iWeapon, "m_upgradeSlots");
	if (upgradeslot > -1) {
		int iUnderbarrel = GetEntData(iWeapon, upgradeslot + 24);
		if (iUnderbarrel == 211 || iUnderbarrel == 212) {
			return true;
		}
	}

	char sWeapon[32];
	GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
	for (int count = 0; count < sizeof(ga_sLmgWeapons); count++) {
		if (strcmp(sWeapon, ga_sLmgWeapons[count], false) == 0) {
			return true;
		}
	}
	return false;
}

public Action Timer_ForceDeployBipod(Handle timer, DataPack hDatapack) {
	hDatapack.Reset();
	int client = hDatapack.ReadCell(),
		sandbag = EntRefToEntIndex(hDatapack.ReadCell());
	float pivot = hDatapack.ReadFloat();

	if (sandbag == INVALID_ENT_REFERENCE || !IsValidEntity(sandbag) || !IsClientInGame(client) || !IsPlayerAlive(client)) {
		return Plugin_Stop;
	}

	SetEntPropFloat(client, Prop_Send, "m_flPivotYaw", pivot);
	SetEntPropFloat(client, Prop_Send, "m_flViewOffsetBipod", 55.0);
	SetEntProp(client, Prop_Send, "m_iPlayerFlags", GetEntProp(client, Prop_Send, "m_iPlayerFlags") | INS_DEPLOY_BIPOD);
	ga_bBipodForced[client] = true;
	ga_iEntIdBipodDeployedOn[client] = sandbag;
	
	return Plugin_Stop;
}

public Action Hook_WeaponSwitch(int client, int entity) {
	if (IsHoldingMeleeWeapon(client)) {
		ga_bHoldingMeleeWeapon[client] = true;
		PrintCenterText(client, "Bipod = Build menu. !prophelp = Open help menu.");
	} else {
		ga_bHoldingMeleeWeapon[client] = false;
		StopHolding(client);
	}
	return Plugin_Continue;
}

void PrecacheFiles() {
	for (int i = 0; i < sizeof(ga_sModel); i++) {
		PrecacheModel(ga_sModel[i]);
	}

	for (int i = 0; i < NUM_WIRESOUNDS; i++) {
		PrecacheSound(ga_sBarbWire[i]);
	}

	PrecacheSound(SND_SUPPLYREFUND);
	PrecacheSound(SND_BUYBUILDPOINTS);
	PrecacheSound(SND_CANTBUY);

	// g_iJammerBeam = PrecacheModel("sprites/laserbeam.vmt");
	// g_iJammerHalo = PrecacheModel("sprites/halo01.vmt");
}

bool IsHoldingMeleeWeapon(int client) {
	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon < 1) {
		return false;
	}

	if (GetPlayerWeaponSlot(client, 2) != iWeapon) {
		return false;
	}
	return true;
}

bool IsCollidingWithPlayer(int client, float vPos[3]) {
	for (int i = 1; i <= MaxClients; i++) {
		if (i == client || !IsClientInGame(i) || !IsPlayerAlive(i)) {
			continue;
		}

		float vPlayerPos[3];
		GetClientAbsOrigin(i, vPlayerPos);

		// Check distance between build position and player position
		if (GetVectorDistance(vPos, vPlayerPos) < PROP_PLAYER_DISTANCE) {
			return true;
		}
	}
	return false;
}

bool HasEnoughResources(int client, int cost) {
	return ga_iPlayerBuildPoints[client] >= cost;
}

void OpenShopMenu(int client, bool cooldown = true) {
	int currentTime = GetTime();
	if (cooldown && (currentTime - ga_iShopMenuCooldown[client] < MENU_COOLDOWN)) {
		PrintCenterText(client, "You must wait before opening the menu again.");
		return;
	}

	ga_iShopMenuCooldown[client] = currentTime;

	if (ga_bPlayerRefund[client]) {
		PrintCenterText(client, "Since you recently refunded or changed class, you can only purchase build points after the team completes the current objective.");
		PrintToChat(client, "Since you recently refunded or changed class, you can only purchase build points after the team completes the current objective.");
		return;
	}

	int playerTokens = GetEntProp(client, Prop_Send, "m_nAvailableTokens");

	Menu buyMenu = new Menu(BuyMenuHandler);
	buyMenu.SetTitle("Buy build points. (You have: %d)", ga_iPlayerBuildPoints[client]);

	char itemBuffer[64];
	bool canBuy = false;

	if (playerTokens >= 1) {
		FormatEx(itemBuffer, sizeof(itemBuffer), "Buy 1 build point - Cost: 1 supply (You have: %d supply)", playerTokens);
		buyMenu.AddItem("1", itemBuffer);
		canBuy = true;
	}

	if (playerTokens >= 5) {
		FormatEx(itemBuffer, sizeof(itemBuffer), "Buy 5 build points - Cost: 5 supply (You have: %d supply)", playerTokens);
		buyMenu.AddItem("5", itemBuffer);
		canBuy = true;
	}

	if (playerTokens >= 10) {
		FormatEx(itemBuffer, sizeof(itemBuffer), "Buy 10 build points - Cost: 10 supply (You have: %d supply)", playerTokens);
		buyMenu.AddItem("10", itemBuffer);
		canBuy = true;
	}

	if (ga_iTokensSpent[client] > 0) {
		FormatEx(itemBuffer, sizeof(itemBuffer), "Refund %d supply (Destroys all your props)", ga_iTokensSpent[client]);
		buyMenu.AddItem("refund", itemBuffer);
		canBuy = true;
	}

	if (canBuy) {
		buyMenu.ExitBackButton = true;
		buyMenu.Display(client, MENU_STAYOPENTIME);
	} else {
		PrintToChat(client, "You do not have enough supply to buy any build points.");
		delete buyMenu;
	}
}

public int BuyMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End) {
		delete menu;
	} else if (action == MenuAction_Select) {
		int playerTokens = GetEntProp(client, Prop_Send, "m_nAvailableTokens"),
			buildPoints = 0,
			cost = 0;

		char item[7];
		menu.GetItem(param, item, sizeof(item));
		
		if (strcmp(item, "1", false) == 0) {
			cost = 1;
			buildPoints = 1;
		} else if (strcmp(item, "5", false) == 0) {
			cost = 5;
			buildPoints = 5;
		} else if (strcmp(item, "10", false) == 0) {
			cost = 10;
			buildPoints = 10;
		} else if (strcmp(item, "deconstruct", false) == 0) {
			DeconstructAllProps(client);

		} else if (strcmp(item, "refund", false) == 0) {
			ga_bPlayerRefund[client] = true;
			DeconstructAllProps(client);
			RefundAllSupply(client);
			return 0;
		}

		if (playerTokens >= cost) {
			SetEntProp(client, Prop_Send, "m_nAvailableTokens", playerTokens - cost);
			ga_iPlayerBuildPoints[client] += buildPoints;
			ga_iTokensSpent[client] += cost;
			PrintToChat(client, buildPoints > 1 ? "You have purchased %d build points." : "You have purchased %d build point.", buildPoints);
			EmitSoundToClient(client, SND_BUYBUILDPOINTS, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
		} else {
			PrintToChat(client, "You do not have enough supply to make this purchase.");
			EmitSoundToClient(client, SND_CANTBUY, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
		}
	}
	return 0;
}

void DeconstructAllProps(int client) {
	if (ga_hPropPlaced[client] == INVALID_HANDLE) {
		return;
	}

	int ent, iArraySize;

	iArraySize = ga_hPropPlaced[client].Length;
	if (iArraySize < 1) {
		return;
	}

	for (int i = iArraySize - 1; i >= 0; i--) {
		ent = EntRefToEntIndex(ga_hPropPlaced[client].Get(i));
		if (ent > MaxClients && IsValidEntity(ent)) {
			RemoveEntity(ent);
		}
	}
}

void RestoreBuildPoints(int client) {
	ga_iPlayerBuildPoints[client] = ga_bPlayerRefund[client] ? 0 : STARTBUILDPOINTS + ga_iTokensSpent[client];
}

bool SetModelIndex(int client, bool found = false) {
	int iArraySize = sizeof(ga_sModel);
	if (iArraySize > 0) {
		for (int i = 0; i < iArraySize; i++) {
			ga_iModelIndex[client] = (ga_iModelIndex[client] + 1) % iArraySize;
			if (HasEnoughResources(client, ga_iModelCosts[ga_iModelIndex[client]])) {
				return found = true;
			}
		}
	}
	return found;
}

// Refund the tokens spent by the player
void RefundAllSupply(int client) {
	StopHolding(client);
	if (ga_iTokensSpent[client] == 0) {
		return;
	}
	SetEntProp(client, Prop_Send, "m_nAvailableTokens",  GetEntProp(client, Prop_Send, "m_nAvailableTokens") + ga_iTokensSpent[client]);
	PrintToChat(client, "You have been refunded %d supply points.", ga_iTokensSpent[client]);
	ga_iTokensSpent[client] = 0;
	RestoreBuildPoints(client);
	EmitSoundToClient(client, SND_SUPPLYREFUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
}

public Action cmd_prophelp(int client, int args) {
	if (client > 0 && IsClientInGame(client) && !ga_bHelpMenuOpen[client]) {
		ga_bHelpMenuOpen[client] = true;
		Panel_HelpInfo(client);
	}
	return Plugin_Handled;
}

// Function to open the prop selection menu
void OpenPropSelectionMenu(int client) {
	ga_bBuildMenuOpen[client] = true;
	Menu propMenu = new Menu(PropSelectionMenuHandler);
	propMenu.SetTitle("Select Prop.\n(build points: %d)", ga_iPlayerBuildPoints[client]);

	char itemBuffer[64], modelName[64], indexStr[3];

	// First loop: Add items the player can afford
	for (int i = 0; i < sizeof(ga_sModel); i++) {
		if (g_iAllFree == 0 && !HasEnoughResources(client, ga_iModelCosts[i])) {
			continue;
		}

		GetModelName(ga_sModel[i], modelName, sizeof(modelName));
		FormatEx(itemBuffer, sizeof(itemBuffer), "%s - Cost: %d", modelName, g_iAllFree == 0 ? ga_iModelCosts[i] : 0);
		IntToString(i, indexStr, sizeof(indexStr)); // Convert index to string
		propMenu.AddItem(indexStr, itemBuffer); // Add the index as a string
	}

	// If player has placed props, add the "Deconstruct all props" option
	if (ga_hPropPlaced[client] != INVALID_HANDLE && ga_hPropPlaced[client].Length > 0) {
		propMenu.AddItem("99", "Deconstruct all props");
	}

	propMenu.AddItem("98", "Open shop menu (Cycle Firemode)");

	// Second loop: Add unselectable items the player can't afford
	if (g_iAllFree == 0) {
		for (int i = 0; i < sizeof(ga_sModel); i++) {
			if (HasEnoughResources(client, ga_iModelCosts[i])) {
				continue; // Skip if player can afford this prop
			}

			GetModelName(ga_sModel[i], modelName, sizeof(modelName));
			FormatEx(itemBuffer, sizeof(itemBuffer), "%s - Cost: %d (Can't afford)", modelName, ga_iModelCosts[i]);
			IntToString(i, indexStr, sizeof(indexStr)); // Convert index to string
			propMenu.AddItem(indexStr, itemBuffer, ITEMDRAW_DISABLED); // Add as unselectable
		}
	}

	propMenu.ExitBackButton = true;
	propMenu.Display(client, MENU_STAYOPENTIME);
}

// Menu handler for prop selection
public int PropSelectionMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End) {
		delete menu;
	} else if (action == MenuAction_Select) {
		char indexStr[3];
		menu.GetItem(param, indexStr, sizeof(indexStr)); // Get the selected index as string
		int selectedIndex = StringToInt(indexStr); // Convert the string back to integer

		if (selectedIndex >= 0 && selectedIndex < sizeof(ga_sModel)) {
			ga_iModelIndex[client] = selectedIndex;
			char modelName[64];
			GetModelName(ga_sModel[selectedIndex], modelName, sizeof(modelName));
			PrintCenterText(client, "Selected prop: %s (Cost: %d)", modelName, ga_iModelCosts[selectedIndex]);

			int ent = EntRefToEntIndex(ga_iPropHolding[client]);
			if (ent <= MaxClients || !IsValidEntity(ent)) {
				HoldProp(client);
				OpenRotationMenu(client);
				return 0;
			}

			// Get current position and rotation of the existing prop
			float vPos[3], vAng[3];
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
			GetEntPropVector(ent, Prop_Send, "m_angRotation", vAng);

			// Remove the existing prop
			RemoveEntity(ent);
			ga_iPropHolding[client] = INVALID_ENT_REFERENCE;
			if (!ga_iPropOwner[client]) {
				CreateProp(client, vPos, vAng);
			} else {
				ga_iPropOwner[client] = 0;
			}
			
			OpenRotationMenu(client);
		} else if (selectedIndex == 99) {
			DeconstructAllProps(client);
		} else if (selectedIndex == 98) {
			if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE) {
				StopHolding(client);
			}
			OpenShopMenu(client);
		} else {
			PrintToChat(client, "Invalid prop selection.");
		}
	} else if (action == MenuAction_Cancel) {
		ga_bBuildMenuOpen[client] = false;
	}
	return 0;
}

// Function to open the rotation menu
void OpenRotationMenu(int client) {
	ga_bPropRotateMenuOpen[client] = true;
	Menu rotationMenu = new Menu(RotationMenuHandler);
	rotationMenu.SetTitle("Rotation");

	rotationMenu.AddItem("y+", "+Yaw");
	rotationMenu.AddItem("y-", "-Yaw");
	rotationMenu.AddItem("x+", "+Pitch");
	rotationMenu.AddItem("x-", "-Pitch");
	rotationMenu.AddItem("z+", "+Roll");
	rotationMenu.AddItem("z-", "-Roll");
	
	rotationMenu.AddItem("reset", "Reset Rotation");

	rotationMenu.ExitBackButton = false;
	rotationMenu.Display(client, 60);
}

// Menu handler for rotation
public int RotationMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End) {
		delete menu;
	} else if (action == MenuAction_Select) {
		int ent = EntRefToEntIndex(ga_iPropHolding[client]);
		if (ent <= MaxClients || !IsValidEntity(ent)) {
			// PrintToChat(client, "No prop is being held.");
			return 0;
		}

		float vRot[3];
		GetEntPropVector(ent, Prop_Send, "m_angRotation", vRot);

		char item[16];
		menu.GetItem(param, item, sizeof(item));

		if (strcmp(item, "y+") == 0) {
			vRot[1] += PROP_ROTATE_STEP;
		} else if (strcmp(item, "y-") == 0) {
			vRot[1] -= PROP_ROTATE_STEP;
		} else if (strcmp(item, "x+") == 0) {
			vRot[0] += PROP_ROTATE_STEP;
		} else if (strcmp(item, "x-") == 0) {
			vRot[0] -= PROP_ROTATE_STEP;
		} else if (strcmp(item, "z+") == 0) {
			vRot[2] += PROP_ROTATE_STEP;
		} else if (strcmp(item, "z-") == 0) {
			vRot[2] -= PROP_ROTATE_STEP;
		} else if (strcmp(item, "reset") == 0) {
			vRot[0] = 0.0;
			vRot[1] = 0.0;
			vRot[2] = 0.0;
		}

		SetEntPropVector(ent, Prop_Send, "m_angRotation", vRot);
		PrintCenterText(client, "Rotation: Yaw: %.1f°, Pitch: %.1f°, Roll: %.1f°", vRot[1], vRot[0], vRot[2]);

		// Save the rotation for the current model index
		ga_fPropRotations[client][ga_iModelIndex[client]][0] = vRot[0];
		ga_fPropRotations[client][ga_iModelIndex[client]][1] = vRot[1];
		ga_fPropRotations[client][ga_iModelIndex[client]][2] = vRot[2];

		// Reopen rotation menu
		OpenRotationMenu(client);
	} else if (action == MenuAction_Cancel) {
		ga_bPropRotateMenuOpen[client] = false;
	}
	return 0;
}

// Function to extract model name from the full path
void GetModelName(const char[] fullPath, char[] modelName, int maxLen) {
	int len = strlen(fullPath),
		start = len,
		end = len;

	// Find the start of the model name
	for (int i = len - 1; i >= 0; i--) {
		if (fullPath[i] == '/') {
			start = i + 1;
			break;
		}
	}

	// Find the end of the model name (excluding .mdl extension)
	for (int i = start; i < len; i++) {
		if (fullPath[i] == '.') {
			end = i;
			break;
		}
	}

	// Copy the model name to the output buffer
	int copyLen = end - start;
	if (copyLen >= maxLen) {
		copyLen = maxLen - 1;
	}

	strcopy(modelName, copyLen + 1, fullPath[start]);
}

bool IsPlayerOnProp(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)) {
		return false;
	}

	// Get the player's ground entity
	int groundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	// Ensure the ground entity is valid
	if (groundEntity <= MaxClients || !IsValidEntity(groundEntity)) {
		return false;
	}

	// Get the entity's name and check if it matches the prop prefix
	char entityName[64];
	GetEntPropString(groundEntity, Prop_Data, "m_iName", entityName, sizeof(entityName));

	// Check if the entity's name starts with the prop prefix "bmprop_c"
	if (StrContains(entityName, "bmprop_c#", false) != -1) {
		return true;
	}

	return false;
}

public void OnPluginEnd() {
	int ent, iArraySize;

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}

		RefundAllSupply(i);

		if (ga_hPropPlaced[i] == INVALID_HANDLE) {
			continue;
		}

		iArraySize = ga_hPropPlaced[i].Length;

		if (iArraySize > 0) {
			for (int j = iArraySize - 1; j >= 0; j--) {
				ent = EntRefToEntIndex(ga_hPropPlaced[i].Get(j));
				if (ent > MaxClients && IsValidEntity(ent)) {
					RemoveEntity(ent);
				}
			}
		}

		delete ga_hPropPlaced[i];
	}
}

void SetupConVars() {
	g_cvAllFree = CreateConVar("sm_props_allfree", "0", "Make all props free?; 0 - disabled, 1 - enabled", _, true, 0.0, true, 1.0);
	g_iAllFree = g_cvAllFree.IntValue;
	g_cvAllFree.AddChangeHook(OnConVarChanged);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvAllFree) {
		g_iAllFree = g_cvAllFree.IntValue;
	}
}