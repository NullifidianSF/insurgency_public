#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PL_VERSION		"2.14"

#define MAXENTITIES		2048
#define MAX_BUTTONS		29

#define BTN_ATTACK1		(1 << 0)
#define BTN_JUMP		(1 << 1)
#define BTN_DUCK		(1 << 2)
#define BTN_FORWARD		(1 << 4)
#define BTN_BACKWARD	(1 << 5)
#define BTN_USE			(1 << 6)
#define BTN_LEFT		(1 << 9)
#define BTN_RIGHT		(1 << 10)
#define BTN_RELOAD		(1 << 11)
#define BTN_FIREMODE	(1 << 12)
#define BTN_LEAN_LEFT	(1 << 13)
#define BTN_LEAN_RIGHT	(1 << 14)
#define BTN_SPRINT		(1 << 15)
#define BTN_WALK		(1 << 16)
#define BTN_SPECIAL1	(1 << 17)
#define BTN_AIM			(1 << 18)
#define BTN_SCOREBOARD	(1 << 19)
#define BTN_FLASHLIGHT	(1 << 22)
#define BTN_AIM_TOGGLE	(1 << 27)
#define BTN_ACCESSORY	(1 << 28)

#define PF_DEPLOY_BIPOD	(1 << 1)
#define PF_BUYZONE		(1 << 7)

#define DAMAGE_NO					0
#define DAMAGE_EVENTS_ONLY			1
#define DAMAGE_YES					2
#define DAMAGE_AIM					3

#define STARTBUILDPOINTS			3		// Free starting build points for all players

#define PROP_ALPHA					125
#define PROP_ROTATE_STEP			10.0
#define PROP_DAMAGE_TAKE			100.0	// Amount of damage the prop takes each time a bot touches it, limited by PROP_TOUCH_COOLDOWN.
#define PROP_TOUCH_COOLDOWN			0.50
#define PROP_GLOWHP_PERCENT			0.25
#define PROP_HEALTH					6000
#define PROP_HOLD_DISTANCE			120.0
#define PROP_LIMIT					10		// Prop limit per player
#define PROP_PLAYER_DISTANCE		50.0
#define PROP_MIN_BOT_DISTANCE		200.0	// If a bot spawns at this distance from the prop, the prop will be destroyed.
#define PROP_MIN_BOT_VERT_DISTANCE	80.0	// If a bot spawns at this vertical distance from the prop, the prop will be destroyed.

#define BOT_BLEED_WIREDAMAGE		10.0	// Amount of bleed damage bot takes from a barbed wire

#define MENU_COOLDOWN				1.0
#define MENU_STAYOPENTIME			10

#define SND_SUPPLYREFUND		"ui/receivedsupply.wav"
#define SND_BUYBUILDPOINTS		"ui/menu_click.wav"
#define SND_CANTBUY				"ui/vote_no.wav"

ArrayList ga_hPropPlaced[MAXPLAYERS + 1];
ConVar g_cvAllFree = null;

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
	"weapon_KACStonerA1"
};

enum struct PropDef {
	char model[PLATFORM_MAX_PATH];
	int  cost;
	bool blocksExplosive;
}

enum PropId {
	Prop_BarbWire = 0,
	Prop_SandbagWall,
	Prop_TWall,
	Prop_HescoBasket,
	Prop_PanjStairs,
	Prop_Mattress,
	Prop_ContainerOpen2,
	Prop_EmbassyCenter02,
	Prop_IedJammer,
	Prop_AmmoCacheSmall,
	
	Prop_Count
};

#define MID(%1) (view_as<int>(%1))

static const PropDef g_PropDefs[] = {
	{ "models/fortifications/barbed_wire_02b.mdl",			2, false },
	{ "models/static_fortifications/sandbagwall01.mdl",		1, true },
	{ "models/iraq/ir_twall_01.mdl",						3, true },
	{ "models/iraq/ir_hesco_basket_01_row.mdl",				4, true },
	{ "models/static_afghan/prop_panj_stairs.mdl",			1, false },
	{ "models/static_afghan/prop_interior_mattress_a.mdl",	2, false },
	{ "models/static_props/container_01_open2.mdl",			5, true },
	{ "models/embassy/embassy_center_02.mdl",				6, true },
	{ "models/sernix/ied_jammer/ied_jammer.mdl",			5, false },
	{ "models/sernix/ammo_cache/ammo_cache_small.mdl",		8, false }
};

#define PROP_COUNT (sizeof(g_PropDefs))
PropId ga_iModelIndex[MAXPLAYERS + 1] = {Prop_BarbWire, ...};

char ga_sLastInflictorModel[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

int ga_iPropHolding[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int ga_iLastButtons[MAXPLAYERS + 1];
int ga_iLastInflictor[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int ga_iEntIdBipodDeployedOn[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int ga_iPlayerBuildPoints[MAXPLAYERS + 1] = {STARTBUILDPOINTS, ...};
int ga_iPropOwner[MAXPLAYERS + 1] = {0, ...};
int ga_iTokensSpent[MAXPLAYERS + 1] = {0, ...};
int g_iAllFree;

bool ga_bHelpMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool ga_bPropRotateMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool ga_bBuildMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool ga_bShopMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool ga_bIgnoreRemoval[MAXPLAYERS + 1] = {false, ...};
bool ga_bHoldingMeleeWeapon[MAXPLAYERS + 1] = {false, ...};
bool g_bLateLoad;
bool ga_bBipodForced[MAXPLAYERS + 1] = {false, ...};
bool ga_bPlayerRefund[MAXPLAYERS + 1] = {false, ...};
bool ga_bFirstTimeJoinedSquad[MAXPLAYERS + 1] = {true, ...};

float ga_fPropRotations[MAXPLAYERS + 1][PROP_COUNT][3];
float ga_fLastTouchTime[MAXPLAYERS + 1] = {0.0, ...};
float ga_fPressedJumpTime[MAXPLAYERS + 1] = {0.0, ...};
float ga_fPropMenuCooldown[MAXPLAYERS + 1] = {0.0, ...};
float ga_fShopMenuCooldown[MAXPLAYERS + 1] = {0.0, ...};
float ga_fWireSoundCooldown[MAXENTITIES + 1] = {0.0, ...};

public Plugin myinfo = {
	name = "props",
	author = "Nullifidian",
	description = "Spawn props",
	version = PL_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	int enumCount  = view_as<int>(Prop_Count);
	int arrayCount = PROP_COUNT;

	if (enumCount != arrayCount) {
		SetFailState("PropId count (%d) != g_PropDefs count (%d). Update the enum or the array order.", enumCount, arrayCount);
		return;
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
			if (!IsClientInGame(i))
				continue;

			if (IsFakeClient(i)) {
				SDKHook(i, SDKHook_OnTakeDamage, BotOnTakeDamage);
				continue;
			}

			SDKHook(i, SDKHook_OnTakeDamage, PlayerOnTakeDamage);

			ga_hPropPlaced[i] = new ArrayList();
			if (ga_hPropPlaced[i] == null)
				LogError("Failed to create array for client %d", i);

			if (IsHoldingMeleeWeapon(i))
				ga_bHoldingMeleeWeapon[i] = true;

			SDKHook(i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitch);
			SetModelIndex(i);
		}
	}
}

public void OnMapStart() {
	PrecacheFiles();
	for (int i = 0; i <= MAXENTITIES; i++)
		ga_fWireSoundCooldown[i] = 0.0;
}

public void OnClientPostAdminCheck(int client) {
	if (client < 1)
		return;

	ga_fLastTouchTime[client]   = 0.0;
	ga_fShopMenuCooldown[client] = 0.0;
	ga_fPropMenuCooldown[client] = 0.0;
	ga_fPressedJumpTime[client] = 0.0;

	if (!IsFakeClient(client)) {
		SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitch);
		SDKHook(client, SDKHook_OnTakeDamage, PlayerOnTakeDamage);

		ga_hPropPlaced[client] = new ArrayList();
		if (ga_hPropPlaced[client] == null)
			LogError("Failed to create array for client %d", client);

		ga_bBipodForced[client] = false;
		ga_bFirstTimeJoinedSquad[client] = true;
	}
	else
		SDKHook(client, SDKHook_OnTakeDamage, BotOnTakeDamage);
}

public void OnClientDisconnect(int client) {
	if (IsFakeClient(client))
		return;

	ga_iLastButtons[client] = 0;
	StopHolding(client);

	if (ga_hPropPlaced[client] == null)
		return;

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
			if (!IsClientInGame(i) || i == client)
				continue;
			if (ga_iPropOwner[i] == client)
				ga_iPropOwner[i] = 0;
		}
	}

	delete ga_hPropPlaced[client];
	ga_hPropPlaced[client] = null;
}

public Action Event_PlayerPickSquad(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	if (ga_bFirstTimeJoinedSquad[client]) {
		ga_bFirstTimeJoinedSquad[client] = false;
		ga_bPlayerRefund[client] = false;
	}
	else {
		DeconstructAllProps(client);
		ga_bPlayerRefund[client] = true;
	}

	ga_iTokensSpent[client] = 0;
	RestoreBuildPoints(client);
	SetModelIndex(client);

	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		ga_iPropHolding[i] = INVALID_ENT_REFERENCE;
		ga_iPropOwner[i] = 0;
		ga_bPlayerRefund[i] = false;
		RestoreBuildPoints(i);
	}
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1)
		return Plugin_Continue;

	if (!IsFakeClient(client)) {
		ga_bBipodForced[client] = false;
		ga_iEntIdBipodDeployedOn[client] = INVALID_ENT_REFERENCE;
	}
	else {
		for (int i = 1; i <= MaxClients; i++) {
			if (ga_hPropPlaced[i] == null || ga_hPropPlaced[i].Length < 1)
				continue;

			int iArraySize = ga_hPropPlaced[i].Length, ent, removedCount = 0;
			float vPos[3], vPosClient[3];
			char message[256] = "", temp[64], finalMessage[256];

			for (int j = iArraySize - 1; j >= 0; j--) {
				ent = EntRefToEntIndex(ga_hPropPlaced[i].Get(j));
				if (ent <= MaxClients || !IsValidEntity(ent))
					continue;

				GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
				GetClientAbsOrigin(client, vPosClient);
				if (GetVectorDistance(vPos, vPosClient, true) <= (PROP_MIN_BOT_DISTANCE * PROP_MIN_BOT_DISTANCE) && FloatAbs(vPos[2] - vPosClient[2]) <= PROP_MIN_BOT_VERT_DISTANCE) {
					FormatEx(temp, sizeof(temp), " #%d", j + 1);
					StrCat(message, sizeof(message), temp);
					RemoveEntity(ent);
					removedCount++;
				}
			}

			if (removedCount > 0) {
				if (removedCount == 1)
					FormatEx(finalMessage, sizeof(finalMessage), "Your prop%s was removed for being placed too close to a bot spawn.", message);
				else
					FormatEx(finalMessage, sizeof(finalMessage), "Your props%s were removed for being placed too close to a bot spawn.", message);

				PrintHintText(i, "%s", finalMessage);
			}
		}
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath_Pre(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || !IsClientInGame(victim))
		return Plugin_Continue;

	if (IsFakeClient(victim)) {
		int inflictor = EntRefToEntIndex(ga_iLastInflictor[victim]);

		if (inflictor != INVALID_ENT_REFERENCE && IsValidEntity(inflictor)) {
			char inflictorClassname[64];
			GetEntityClassname(inflictor, inflictorClassname, sizeof(inflictorClassname));
			if (strcmp(inflictorClassname, "prop_dynamic") == 0) {
				char sModelName[PLATFORM_MAX_PATH];
				GetEntPropString(inflictor, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));

				if (strcmp(sModelName, "models/fortifications/barbed_wire_02b.mdl") == 0) {
					event.SetString("weapon", "Barbed Wire");
					return Plugin_Changed;
				}
			}
		}
		else if (strcmp(ga_sLastInflictorModel[victim], "models/fortifications/barbed_wire_02b.mdl") == 0) {
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
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		ga_bPlayerRefund[i] = false;
		RestoreBuildPoints(i);
	}
	return Plugin_Continue;
}

void HoldProp(int client) {
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client) || ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
		return;

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
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
		return Plugin_Continue;

	int button;
	for (int i = 0; i < MAX_BUTTONS; i++) {
		button = (1 << i);
		if (buttons & button) {
			if (!(ga_iLastButtons[client] & button))
				OnButtonPress(client, button, vel);
		}
	}
	ga_iLastButtons[client] = buttons;

	if (!ga_bHoldingMeleeWeapon[client])
		return Plugin_Continue;

	int ent = EntRefToEntIndex(ga_iPropHolding[client]);
	if (ent > MaxClients && IsValidEntity(ent)) {
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
	if (button & BTN_JUMP) {
		float GameTime = GetGameTime();
		if (GameTime - ga_fPressedJumpTime[client] <= 1.0)
			ga_fPressedJumpTime[client] = 0.0;
		else
			ga_fPressedJumpTime[client] = GameTime;
	}

	if ((button & BTN_SPRINT) || (button & BTN_ATTACK1)) {
		StopHolding(client);
		CloseAllPropMenus(client);
		return;
	}

	if (button & BTN_SPECIAL1) {
		if (!ga_bHoldingMeleeWeapon[client]) {
			if (WeaponWithBipod(client)) {
				switch (ga_bBipodForced[client]) {
					case false: {
						int target = GetClientAimTarget(client, false);
						if (target <= MaxClients)
							return;

						char sName[64];
						GetEntPropString(target, Prop_Data, "m_iName", sName, sizeof(sName));
						if (StrContains(sName, "bmprop_c#", true) == -1)
							return;

						char sModelName[PLATFORM_MAX_PATH];
						GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
						if (StrContains(sModelName, "sandbagwall01", false) == -1)
							return;

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
		}
		else {
			float GameTime = GetGameTime();
			if (ga_fPropMenuCooldown[client] > GameTime) {
				PrintCenterText(client, "You must wait before opening the menu again.");
				return;
			}

			ga_fPropMenuCooldown[client] = MENU_COOLDOWN + GameTime;
			OpenPropSelectionMenu(client);
		}
		return;
	}

	if (ga_bBipodForced[client]) {
		if ((button & BTN_JUMP) || (button & BTN_DUCK) || (button & BTN_FORWARD) || (button & BTN_BACKWARD) || (button & BTN_LEFT) || (button & BTN_RIGHT)) {
			ga_bBipodForced[client] = false;
			ga_iEntIdBipodDeployedOn[client] = 0;
		}
	}

	if (!ga_bHoldingMeleeWeapon[client])
		return;

	if (button & BTN_FIREMODE) {
		if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE) {
			OpenShopMenu(client);
			return;
		}
	}

	if ((button & BTN_AIM) || (button & BTN_AIM_TOGGLE)) {
		if (!ga_bHoldingMeleeWeapon[client])
			return;

		if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE) {
			int target = GetClientAimTarget(client, false);

			if (target <= MaxClients || !IsValidEntity(target))
				return;

			char sName[64];
			GetEntPropString(target, Prop_Data, "m_iName", sName, sizeof(sName));

			if (StrContains(sName, "bmprop_c#", true) != -1) {
				char sModelName[PLATFORM_MAX_PATH];
				GetEntPropString(target, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
				if (strcmp(sModelName, "models/sernix/ammo_cache/ammo_cache_small.mdl") == 0)
					return;

				if (IsPlayerOnProp(client)) {
					PrintCenterText(client, "You cannot move props while standing on one.");
					return;
				}

				if (IsPlayerOnGround(client) != 1)
					return;

				float vPos[3], vAng[3];
				GetEntPropVector(target, Prop_Send, "m_vecOrigin", vPos);
				GetEntPropVector(target, Prop_Send, "m_angRotation", vAng);

				int propOwner = GetNumber(sName, "_c#");
				int iArraySize = (ga_hPropPlaced[propOwner] != null) ? ga_hPropPlaced[propOwner].Length : 0;

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
				ga_iModelIndex[client] = view_as<PropId>(GetNumber(sName, "_m#"));
				ga_iPropOwner[client] = propOwner;
				CreateProp(client, vPos, vAng, health);
			}
			else
				HoldProp(client);
			return;
		}
		else {
			int ent = EntRefToEntIndex(ga_iPropHolding[client]);
			if (ent <= MaxClients || !IsValidEntity(ent))
				return;

			if (vel[0] != 0.0 || vel[1] != 0.0 || vel[2] != 0.0)
				return;

			float vAng[3];
			GetClientEyeAngles(client, vAng);
			float vPos[3];
			GetClientEyePosition(client, vPos);
			GetPositionInFront(vPos, vAng, PROP_HOLD_DISTANCE);

			if (IsCollidingWithPlayer(client, vPos)) {
				PrintCenterText(client, "Too close to another player.");
				return;
			}

			TeleportEntity(ent, vPos, NULL_VECTOR, NULL_VECTOR);

			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
			GetEntPropVector(ent, Prop_Send, "m_angRotation", vAng);

			int health = GetEntProp(ent, Prop_Data, "m_iHealth");
			StopHolding(client);
			CreateProp(client, vPos, vAng, health, true);

			PrintCenterText(client, "Prop: %d/%d", (ga_hPropPlaced[client] != null) ? ga_hPropPlaced[client].Length : 0, PROP_LIMIT);
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

int IsPlayerOnGround(int client) { return GetEntityFlags(client) & FL_ONGROUND; }

void CreateProp(int client, float vPos[3], float vAng[3], int oldhealth = 0, bool solid = false) {
	if (IsPlayerOnGround(client) != 1) {
		PrintHintText(client, "You cannot build a prop while falling!");
		return;
	}

	PropId modelId = ga_iModelIndex[client];
	int mid = MID(modelId);
	int buildCost = (g_iAllFree == 1) ? 0 : g_PropDefs[mid].cost;

	if (!ga_iPropOwner[client] && !HasEnoughResources(client, buildCost)) {
		if (solid) {
			PrintCenterText(client, "You don't have enough resources to build. Press 'Cycle Firemode' to open the shop menu.");
			return;
		}
		else if (SetModelIndex(client)) {
			modelId = ga_iModelIndex[client];
			mid = MID(modelId);
			buildCost = g_PropDefs[mid].cost;
		}
		else {
			PrintCenterText(client, "You don't have enough resources to build. Press 'Cycle Firemode' to open the shop menu.");
			return;
		}
	}

	int prop = CreateEntityByName("prop_dynamic_override");
	if (prop != -1) {
		DispatchKeyValue(prop, "physdamagescale", "0.0");
		DispatchKeyValue(prop, "model", g_PropDefs[mid].model);
		if (solid) {
			char PropName[64];
			DispatchKeyValue(prop, "solid", "6");

			if (!ga_iPropOwner[client]) {
				ga_iPlayerBuildPoints[client] -= buildCost;
				ClearOldestPropIfLimitReached(client);
				TeleportEntity(prop, vPos, ga_fPropRotations[client][mid], NULL_VECTOR);

				if (ga_hPropPlaced[client] == null)
					ga_hPropPlaced[client] = new ArrayList();

				ga_hPropPlaced[client].Push(EntIndexToEntRef(prop));
				FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", client, mid);
			}
			else {
				TeleportEntity(prop, vPos, vAng, NULL_VECTOR);

				if (ga_hPropPlaced[ga_iPropOwner[client]] != null) {
					ga_hPropPlaced[ga_iPropOwner[client]].Push(EntIndexToEntRef(prop));
					FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", ga_iPropOwner[client], mid);
				}
				else {
					ClearOldestPropIfLimitReached(client);

					if (ga_hPropPlaced[client] == null)
						ga_hPropPlaced[client] = new ArrayList();

					ga_hPropPlaced[client].Push(EntIndexToEntRef(prop));
					FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", client, mid);
					oldhealth = 0;
				}
				ga_iPropOwner[client] = 0;
			}

			if (strcmp(g_PropDefs[mid].model, "models/sernix/ammo_cache/ammo_cache_small.mdl") == 0) {
				SetVariantColor({255, 255, 102, 255});
				SetEntityRenderMode(prop, RENDER_NORMAL);
				SetEntityRenderColor(prop, 255, 255, 255, 255);
				AcceptEntityInput(prop, "SetGlowColor");
				SetEntProp(prop, Prop_Send, "m_bShouldGlow", true);
				SetEntPropFloat(prop, Prop_Send, "m_flGlowMaxDist", 1600.0);
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			}
			else if (strcmp(g_PropDefs[mid].model, "models/sernix/ied_jammer/ied_jammer.mdl") == 0) {
				SetVariantColor({80, 210, 255, 255});
				SetEntityRenderMode(prop, RENDER_NORMAL);
				AcceptEntityInput(prop, "SetGlowColor");
				SetEntProp(prop, Prop_Send, "m_bShouldGlow", true);
				SetEntPropFloat(prop, Prop_Send, "m_flGlowMaxDist", 600.0);
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			}
			else if (strcmp(g_PropDefs[mid].model, "models/fortifications/barbed_wire_02b.mdl") == 0) {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchWire);
			}
			else if (strcmp(g_PropDefs[mid].model, "models/static_afghan/prop_interior_mattress_a.mdl") == 0) {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchMattress);
			}
			else
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);

			DispatchKeyValue(prop, "targetname", PropName);
			SDKHook(prop, SDKHook_OnTakeDamage, PropOnTakeDamage);

			if (ga_bPropRotateMenuOpen[client])
				ClientCommand(client, "slot9");
		}
		else {
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
			}
			else
				TeleportEntity(prop, vPos, ga_fPropRotations[client][mid], NULL_VECTOR);
		}

		DispatchSpawn(prop);
		SetEntityMoveType(prop, MOVETYPE_NONE);
		SetEntProp(prop, Prop_Data, "m_takedamage", DAMAGE_YES);

		if (oldhealth > 0) {
			SetEntProp(prop, Prop_Data, "m_iHealth", oldhealth);
			GlowLowHp(prop, oldhealth);
		}
		else
			SetEntProp(prop, Prop_Data, "m_iHealth", PROP_HEALTH);

		SetEntProp(prop, Prop_Data, "m_iMaxHealth", PROP_HEALTH);
	}
	else
		PrintCenterText(client, "Failed to create prop.");
}

void ClearOldestPropIfLimitReached(int client) {
	int ent;
	while (ga_hPropPlaced[client] != null && ga_hPropPlaced[client].Length >= PROP_LIMIT && PROP_LIMIT > 1) {
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
	int pos = StrContains(str, substr, false);
	if (pos == -1)
		return -1;

	pos += strlen(substr);
	char numberStr[32];
	strcopy(numberStr, sizeof(numberStr), str[pos]);
	return StringToInt(numberStr);
}

public Action SHook_OnTouchPropTakeDamage(int entity, int touch) {
	if (touch < 1 || touch > MaxClients)
		return Plugin_Continue;

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch) || GetClientTeam(touch) != 3)
		return Plugin_Continue;

	float GameTime = GetGameTime();
	if (ga_fLastTouchTime[touch] > GameTime)
		return Plugin_Continue;

	ga_fLastTouchTime[touch] = GameTime + PROP_TOUCH_COOLDOWN;
	DoDamageToEnt(entity, touch);
	return Plugin_Continue;
}

void DoDamageToEnt(int entity, int client) {
	SDKHooks_TakeDamage(entity, client, client, PROP_DAMAGE_TAKE, DMG_SLASH, -1, NULL_VECTOR, NULL_VECTOR, false);
}

public Action SHook_OnTouchMattress(int entity, int touch) {
	if (touch < 1 || touch > MaxClients)
		return Plugin_Continue;

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch))
		return Plugin_Continue;

	float GameTime = GetGameTime();
	if (ga_fLastTouchTime[touch] > GameTime)
		return Plugin_Continue;

	if (entity == GetEntPropEnt(touch, Prop_Send, "m_hGroundEntity") && GetEntProp(touch, Prop_Send, "m_iCurrentStance") == 0) {
		if (!IsFakeClient(touch)) {
			if (GameTime - ga_fPressedJumpTime[touch] <= 1.0) {
				ga_fPressedJumpTime[touch] = GameTime + 1.0;
				SetEntPropVector(touch, Prop_Data, "m_vecBaseVelocity", {0.0, 0.0, 500.0});
				PlayWireSound(entity);
			}
		}
		else {
			SetEntPropVector(touch, Prop_Data, "m_vecBaseVelocity", {0.0, 0.0, 500.0});
			PlayWireSound(entity);
			DoDamageToEnt(entity, touch);
		}
	}

	ga_fLastTouchTime[touch] = GameTime + PROP_TOUCH_COOLDOWN;
	return Plugin_Continue;
}

public Action SHook_OnTouchWire(int entity, int touch) {
	if (touch < 1 || touch > MaxClients)
		return Plugin_Continue;

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch) || GetClientTeam(touch) != 3)
		return Plugin_Continue;

	float GameTime = GetGameTime();
	if (ga_fLastTouchTime[touch] <= GameTime) {
		ga_fLastTouchTime[touch] = GameTime + PROP_TOUCH_COOLDOWN;

		int propOwner = GetPropOwner(entity);
		if (propOwner > 0) {
			SDKHooks_TakeDamage(touch, entity, propOwner, BOT_BLEED_WIREDAMAGE, DMG_SLASH, -1, NULL_VECTOR, NULL_VECTOR, false);

			float vPos[3];
			GetClientAbsOrigin(touch, vPos);
			CreateBleedEffect(touch, vPos);
		}

		if (ga_fWireSoundCooldown[entity] <= GameTime) {
			PlayWireSound(entity);
			ga_fWireSoundCooldown[entity] = GameTime + 2.0;
		}
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

	SetVariantString("!activator");
	AcceptEntityInput(particle, "SetParent", client, particle);

	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");

	CreateTimer(PROP_TOUCH_COOLDOWN, Timer_RemoveParticle, EntIndexToEntRef(particle));
}

public Action Timer_RemoveParticle(Handle timer, int particleRef) {
	int particle = EntRefToEntIndex(particleRef);
	if (particle != INVALID_ENT_REFERENCE && IsValidEntity(particle))
		RemoveEntity(particle);
	else
		PrintToServer("Failed to remove particle system entity. It might not exist.");
	return Plugin_Stop;
}

public Action PropOnTakeDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (GlowLowHp(entity, GetEntProp(entity, Prop_Data, "m_iHealth")))
		SDKUnhook(entity, SDKHook_OnTakeDamage, PropOnTakeDamage);
	return Plugin_Continue;
}

public Action BotOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	ga_iLastInflictor[victim] = EntIndexToEntRef(inflictor);
	return Plugin_Continue;
}

public Action PlayerOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (damagetype & DMG_FALL) {
		int groundEntity = GetEntPropEnt(victim, Prop_Send, "m_hGroundEntity");
		if (groundEntity > MaxClients && IsValidEntity(groundEntity)) {
			char sModelName[PLATFORM_MAX_PATH];
			GetEntPropString(groundEntity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
			if (strcmp(sModelName, "models/static_afghan/prop_interior_mattress_a.mdl") == 0) {
				PrintCenterText(victim, "Mattress cushioned your fall!");
				return Plugin_Handled;
			}
		}
	}

	if ((damagetype & DMG_BLAST) && IsValidEntity(inflictor) && inflictor != victim) {
		float vStart[3], vEnd[3];
		GetClientEyePosition(victim, vStart);
		GetEntPropVector(inflictor, Prop_Data, "m_vecAbsOrigin", vEnd);

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

				char shortName[64];
				GetModelName(sModelName, shortName, sizeof(shortName));
				PrintCenterText(victim, "A %s shielded you from the explosion!", shortName);
				CloseHandle(trace);
				return Plugin_Handled;
			}
		}
		CloseHandle(trace);
	}
	return Plugin_Continue;
}

public bool TraceEntityFilterPlayers(int entity, int contentsMask, any data) { return (entity != data && (entity <= 0 || entity > MaxClients)); }

bool ModelBlocksExplosion(const char[] sModelName) {
	for (int i = 0; i < PROP_COUNT; i++) {
		if (strcmp(g_PropDefs[i].model, sModelName) == 0)
			return g_PropDefs[i].blocksExplosive;
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
	if (entity <= MaxClients)
		return;

	int propOwner = GetPropOwner(entity);
	if (propOwner < 1)
		return;

	for (int i = 1; i <= MaxClients; i++) {
		if (EntRefToEntIndex(ga_iLastInflictor[i]) == entity) {
			GetEntPropString(entity, Prop_Data, "m_ModelName", ga_sLastInflictorModel[i], PLATFORM_MAX_PATH);
			ga_iLastInflictor[i] = INVALID_ENT_REFERENCE;
		}

		if (ga_iEntIdBipodDeployedOn[i] == entity)
			ga_iEntIdBipodDeployedOn[i] = INVALID_ENT_REFERENCE;
	}

	if (propOwner > 0 && ga_hPropPlaced[propOwner] != null) {
		int iArraySize = ga_hPropPlaced[propOwner].Length;
		if (iArraySize < 1 || ga_bIgnoreRemoval[propOwner])
			return;

		for (int i = iArraySize - 1; i >= 0; i--) {
			int ent = EntRefToEntIndex(ga_hPropPlaced[propOwner].Get(i));
			if (ent == entity) {
				ga_hPropPlaced[propOwner].Erase(i);
				break;
			}
		}
	}
}

int GetPropOwner(int entity) {
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));
	if (StrContains(sName, "bmprop_c#", false) == -1)
		return -1;

	int propOwner = GetNumber(sName, "_c#");
	if (propOwner < 1 || propOwner > MaxClients)
		return -1;

	if (ga_hPropPlaced[propOwner] == null)
		return -1;

	return propOwner;
}

public Action Panel_HelpInfo(int client) {
	Panel panel = new Panel();
	char sPropLimit[64];
	FormatEx(sPropLimit, sizeof(sPropLimit), "Prop limit: %d/%d \n(at max oldest deleted)", (ga_hPropPlaced[client] != null) ? ga_hPropPlaced[client].Length : 0, PROP_LIMIT);
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

public int PanelHandler1(Menu menu, MenuAction action, int client, int param2) {
	if ((action == MenuAction_Cancel || action == MenuAction_Select) && client >= 1 && client <= MaxClients) {
		ga_bHelpMenuOpen[client] = false;
	}
	return 0;
}

bool WeaponWithBipod(int client) {
	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon < 1)
		return false;

	int upgradeslot = GetEntSendPropOffs(iWeapon, "m_upgradeSlots");
	if (upgradeslot > -1) {
		int iUnderbarrel = GetEntData(iWeapon, upgradeslot + 24);
		if (iUnderbarrel == 211 || iUnderbarrel == 212)
			return true;
	}

	char sWeapon[32];
	GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));
	for (int count = 0; count < sizeof(ga_sLmgWeapons); count++) {
		if (strcmp(sWeapon, ga_sLmgWeapons[count], false) == 0)
			return true;
	}
	return false;
}

public Action Timer_ForceDeployBipod(Handle timer, DataPack hDatapack) {
	hDatapack.Reset();
	int client = hDatapack.ReadCell();
	int sandbag = EntRefToEntIndex(hDatapack.ReadCell());
	float pivot = hDatapack.ReadFloat();

	if (sandbag == INVALID_ENT_REFERENCE || !IsValidEntity(sandbag) || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;

	SetEntPropFloat(client, Prop_Send, "m_flPivotYaw", pivot);
	SetEntPropFloat(client, Prop_Send, "m_flViewOffsetBipod", 55.0);
	SetEntProp(client, Prop_Send, "m_iPlayerFlags", GetEntProp(client, Prop_Send, "m_iPlayerFlags") | PF_DEPLOY_BIPOD);
	ga_bBipodForced[client] = true;
	ga_iEntIdBipodDeployedOn[client] = sandbag;

	return Plugin_Stop;
}

public Action Hook_WeaponSwitch(int client, int entity) {
	if (IsHoldingMeleeWeapon(client)) {
		ga_bHoldingMeleeWeapon[client] = true;
		PrintCenterText(client, "Bipod = Build menu. !prophelp = Open help menu.");
	}
	else {
		ga_bHoldingMeleeWeapon[client] = false;
		StopHolding(client);
	}
	return Plugin_Continue;
}

void PrecacheFiles() {
	for (int i = 0; i < PROP_COUNT; i++)
		PrecacheModel(g_PropDefs[i].model, true);

	for (int i = 0; i < NUM_WIRESOUNDS; i++)
		PrecacheSound(ga_sBarbWire[i], true);

	PrecacheSound(SND_SUPPLYREFUND, true);
	PrecacheSound(SND_BUYBUILDPOINTS, true);
	PrecacheSound(SND_CANTBUY, true);
}

bool IsHoldingMeleeWeapon(int client) {
	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon < 1)
		return false;

	// slot 2 = melee in Ins2014
	if (GetPlayerWeaponSlot(client, 2) != iWeapon)
		return false;

	return true;
}

bool IsCollidingWithPlayer(int client, float vPos[3]) {
	for (int i = 1; i <= MaxClients; i++) {
		if (i == client || !IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		float vPlayerPos[3];
		GetClientAbsOrigin(i, vPlayerPos);

		if (GetVectorDistance(vPos, vPlayerPos) < PROP_PLAYER_DISTANCE)
			return true;
	}
	return false;
}

bool HasEnoughResources(int client, int cost) { return ga_iPlayerBuildPoints[client] >= cost; }

void OpenShopMenu(int client, bool cooldown = true) {
	float GameTime = GetGameTime();
	if (cooldown && (ga_fShopMenuCooldown[client] > GameTime)) {
		PrintCenterText(client, "You must wait before opening the menu again.");
		return;
	}
	ga_fShopMenuCooldown[client] = GameTime + MENU_COOLDOWN;

	if (ga_bPlayerRefund[client]) {
		PrintCenterText(client, "Since you recently refunded or changed class, you can only purchase build points after the team completes the current objective.");
		PrintToChat(client, "Since you recently refunded or changed class, you can only purchase build points after the team completes the current objective.");
		return;
	}

	int playerTokens = GetEntProp(client, Prop_Send, "m_nAvailableTokens");
	Menu buyMenu = new Menu(BuyMenuHandler);
	buyMenu.SetTitle("Buy build points. (You have: %d)", ga_iPlayerBuildPoints[client]);

	char itemBuffer[128];

	FormatEx(itemBuffer, sizeof(itemBuffer), "Buy 1 build point - Cost: 1 supply (You have: %d supply)", playerTokens);
	buyMenu.AddItem("1", itemBuffer, (playerTokens >= 1) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	int maxBuy = playerTokens;
	if (maxBuy >= 1) {
		FormatEx(itemBuffer, sizeof(itemBuffer), "Buy %d build %s - Cost: %d supply (You have: %d supply)", maxBuy, (maxBuy == 1 ? "point" : "points"), maxBuy, playerTokens);
		buyMenu.AddItem("max", itemBuffer, ITEMDRAW_DEFAULT);
	}
	else
		buyMenu.AddItem("max", "Buy MAX build points (Need supply)", ITEMDRAW_DISABLED);

	buyMenu.AddItem("spacer", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);

	if (ga_iTokensSpent[client] > 0) {
		FormatEx(itemBuffer, sizeof(itemBuffer), "Refund %d supply (Destroys all your props)", ga_iTokensSpent[client]);
		buyMenu.AddItem("refund", itemBuffer, ITEMDRAW_DEFAULT);
	}
	else
		buyMenu.AddItem("refund", "Refund (no purchases yet)", ITEMDRAW_DISABLED);

	buyMenu.ExitBackButton = true;
	ga_bShopMenuOpen[client] = true;
	buyMenu.Display(client, MENU_STAYOPENTIME);
}

public int BuyMenuHandler(Menu menu, MenuAction action, int client, int param) {
	switch (action) {
		case MenuAction_End:
			delete menu;
		case MenuAction_Cancel: {
			if (client >= 1 && client <= MaxClients)
				ga_bShopMenuOpen[client] = false;
		}
		case MenuAction_Select: {
			if (client < 1 || client > MaxClients)
				return 0;
			if (param < 0)
				return 0;

			char item[16], display[128];
			int style;
			if (!menu.GetItem(param, item, sizeof(item), style, display, sizeof(display)))
				return 0;
			if (style & ITEMDRAW_SPACER || style & ITEMDRAW_DISABLED)
				return 0;

			if (strcmp(item, "1", false) == 0 || strcmp(item, "max", false) == 0) {
				int playerTokens = GetEntProp(client, Prop_Send, "m_nAvailableTokens");
				int cost = (strcmp(item, "1", false) == 0) ? 1 : playerTokens;
				int buildPoints = cost;

				if (playerTokens >= cost && cost >= 1) {
					SetEntProp(client, Prop_Send, "m_nAvailableTokens", playerTokens - cost);
					ga_iPlayerBuildPoints[client] += buildPoints;
					ga_iTokensSpent[client] += cost;

					PrintToChat(client, buildPoints > 1 ? "You purchased %d build points." : "You purchased %d build point.", buildPoints);
					EmitSoundToClient(client, SND_BUYBUILDPOINTS, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
				}
				else {
					PrintToChat(client, "You do not have enough supply.");
					EmitSoundToClient(client, SND_CANTBUY, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
				}

				OpenShopMenu(client, false);
			}
			else if (strcmp(item, "refund", false) == 0)
				OpenRefundConfirmMenu(client);
		}
	}
	return 0;
}

void OpenRefundConfirmMenu(int client) {
	Menu confirm = new Menu(RefundConfirmHandler);
	confirm.SetTitle("Refund %d supply and destroy ALL your props?\n\nAre you sure?", ga_iTokensSpent[client]);
	confirm.AddItem("yes", "Yes - refund and deconstruct");
	confirm.AddItem("no", "No - go back");
	confirm.ExitBackButton = false;
	confirm.Display(client, 10);
}

public int RefundConfirmHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		if (param < 0)
			return 0;

		char item[8], display[64];
		int style;
		if (!menu.GetItem(param, item, sizeof(item), style, display, sizeof(display)))
			return 0;

		if (strcmp(item, "yes", false) == 0) {
			ga_bPlayerRefund[client] = true;
			DeconstructAllProps(client);
			RefundAllSupply(client);
			ga_bShopMenuOpen[client] = false;
			CancelClientMenu(client);
		}
		else
			OpenShopMenu(client, false);
	}
	return 0;
}

bool AnyPropMenuFlagOpen(int client) {
	return ga_bHelpMenuOpen[client] || ga_bPropRotateMenuOpen[client] || ga_bBuildMenuOpen[client] || ga_bShopMenuOpen[client];
}

void CloseAllPropMenus(int client, bool sendSlot9IfNeeded = true) {
	bool hadSmMenu = (GetClientMenu(client) != MenuSource_None);
	if (hadSmMenu)
		CancelClientMenu(client);

	bool hadOurFlags = AnyPropMenuFlagOpen(client);
	if (sendSlot9IfNeeded && (hadSmMenu || hadOurFlags)) 
		ClientCommand(client, "slot9");

	ga_bHelpMenuOpen[client] = false;
	ga_bPropRotateMenuOpen[client] = false;
	ga_bBuildMenuOpen[client] = false;
	ga_bShopMenuOpen[client] = false;
}

void DeconstructAllProps(int client) {
	if (ga_hPropPlaced[client] == null)
		return;

	int iArraySize = ga_hPropPlaced[client].Length;
	if (iArraySize < 1)
		return;

	for (int i = iArraySize - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(ga_hPropPlaced[client].Get(i));
		if (ent > MaxClients && IsValidEntity(ent)) RemoveEntity(ent);
	}
}

void RestoreBuildPoints(int client) {
	ga_iPlayerBuildPoints[client] = ga_bPlayerRefund[client] ? 0 : STARTBUILDPOINTS + ga_iTokensSpent[client];
}

bool SetModelIndex(int client, bool found = false) {
	int count = PROP_COUNT;
	if (count > 0) {
		int idx = MID(ga_iModelIndex[client]);
		for (int i = 0; i < count; i++) {
			idx = (idx + 1) % count;
			if (HasEnoughResources(client, g_PropDefs[idx].cost)) {
				ga_iModelIndex[client] = view_as<PropId>(idx);
				return true;
			}
		}
	}
	return found;
}

void RefundAllSupply(int client) {
	StopHolding(client);

	if (ga_iTokensSpent[client] == 0)
		return;

	SetEntProp(client, Prop_Send, "m_nAvailableTokens", GetEntProp(client, Prop_Send, "m_nAvailableTokens") + ga_iTokensSpent[client]);
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

void OpenPropSelectionMenu(int client) {
	ga_bBuildMenuOpen[client] = true;

	Menu propMenu = new Menu(PropSelectionMenuHandler);
	propMenu.SetTitle("Select Prop.\n(build points: %d)", ga_iPlayerBuildPoints[client]);

	char itemBuffer[64], modelName[64], indexStr[8];

	for (int i = 0; i < PROP_COUNT; i++) {
		if (g_iAllFree == 0 && !HasEnoughResources(client, g_PropDefs[i].cost))
			continue;

		GetModelName(g_PropDefs[i].model, modelName, sizeof(modelName));
		FormatEx(itemBuffer, sizeof(itemBuffer), "%s - Cost: %d", modelName, (g_iAllFree == 0 ? g_PropDefs[i].cost : 0));
		IntToString(i, indexStr, sizeof(indexStr));
		propMenu.AddItem(indexStr, itemBuffer);
	}

	if (ga_hPropPlaced[client] != null && ga_hPropPlaced[client].Length > 0)
		propMenu.AddItem("99", "Deconstruct all props");

	propMenu.AddItem("98", "Open shop menu (Cycle Firemode)");

	if (g_iAllFree == 0) {
		for (int i = 0; i < PROP_COUNT; i++) {
			if (HasEnoughResources(client, g_PropDefs[i].cost))
				continue;

			GetModelName(g_PropDefs[i].model, modelName, sizeof(modelName));
			FormatEx(itemBuffer, sizeof(itemBuffer), "%s - Cost: %d (Can't afford)", modelName, g_PropDefs[i].cost);
			IntToString(i, indexStr, sizeof(indexStr));
			propMenu.AddItem(indexStr, itemBuffer, ITEMDRAW_DISABLED);
		}
	}

	propMenu.ExitBackButton = true;
	propMenu.Display(client, MENU_STAYOPENTIME);
}

public int PropSelectionMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		if (param < 0)
			return 0;

		char indexStr[8], display[96];
		int style;
		if (!menu.GetItem(param, indexStr, sizeof(indexStr), style, display, sizeof(display)))
			return 0;
		if (style & ITEMDRAW_DISABLED)
			return 0;

		int selectedIndex = StringToInt(indexStr);
		if (selectedIndex >= 0 && selectedIndex < PROP_COUNT) {
			ga_iModelIndex[client] = view_as<PropId>(selectedIndex);

			char modelName[64];
			GetModelName(g_PropDefs[selectedIndex].model, modelName, sizeof(modelName));
			PrintCenterText(client, "Selected prop: %s (Cost: %d)", modelName, g_PropDefs[selectedIndex].cost);

			int ent = EntRefToEntIndex(ga_iPropHolding[client]);
			if (ent <= MaxClients || !IsValidEntity(ent)) {
				HoldProp(client);
				OpenRotationMenu(client);
				return 0;
			}

			float vPos[3], vAng[3];
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
			GetEntPropVector(ent, Prop_Send, "m_angRotation", vAng);

			RemoveEntity(ent);
			ga_iPropHolding[client] = INVALID_ENT_REFERENCE;

			if (!ga_iPropOwner[client])
				CreateProp(client, vPos, vAng);
			else ga_iPropOwner[client] = 0;

			OpenRotationMenu(client);
		}
		else if (selectedIndex == 99)
			OpenDeconstructConfirmMenu(client);
		else if (selectedIndex == 98) {
			if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
				StopHolding(client);

			OpenShopMenu(client);
		}
		else
			PrintToChat(client, "Invalid prop selection.");
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients)
			ga_bBuildMenuOpen[client] = false;
	return 0;
}

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

public int RotationMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		if (param < 0)
			return 0;

		char item[16], display[64];
		int style;
		if (!menu.GetItem(param, item, sizeof(item), style, display, sizeof(display)))
			return 0;
		if (style & ITEMDRAW_DISABLED)
			return 0;
		int ent = EntRefToEntIndex(ga_iPropHolding[client]);
		if (ent <= MaxClients || !IsValidEntity(ent))
			return 0;

		float vRot[3];
		GetEntPropVector(ent, Prop_Send, "m_angRotation", vRot);

		if (strcmp(item, "y+") == 0)
			vRot[1] += PROP_ROTATE_STEP;
		else if (strcmp(item, "y-") == 0)
			vRot[1] -= PROP_ROTATE_STEP;
		else if (strcmp(item, "x+") == 0)
			vRot[0] += PROP_ROTATE_STEP;
		else if (strcmp(item, "x-") == 0)
			vRot[0] -= PROP_ROTATE_STEP;
		else if (strcmp(item, "z+") == 0)
			vRot[2] += PROP_ROTATE_STEP;
		else if (strcmp(item, "z-") == 0)
			vRot[2] -= PROP_ROTATE_STEP;
		else if (strcmp(item, "reset") == 0)
			{ vRot[0] = 0.0; vRot[1] = 0.0; vRot[2] = 0.0; }

		SetEntPropVector(ent, Prop_Send, "m_angRotation", vRot);
		PrintCenterText(client, "Rotation: Yaw: %.1f°, Pitch: %.1f°, Roll: %.1f°", vRot[1], vRot[0], vRot[2]);

		int mid = MID(ga_iModelIndex[client]);
		ga_fPropRotations[client][mid][0] = vRot[0];
		ga_fPropRotations[client][mid][1] = vRot[1];
		ga_fPropRotations[client][mid][2] = vRot[2];

		OpenRotationMenu(client);
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients)
		ga_bPropRotateMenuOpen[client] = false;
	return 0;
}

void OpenDeconstructConfirmMenu(int client) {
	int count = (ga_hPropPlaced[client] != null) ? ga_hPropPlaced[client].Length : 0;

	Menu confirm = new Menu(DeconstructConfirmHandler);
	confirm.SetTitle("Deconstruct ALL your props? (%d placed)\n\nAre you sure?", count);
	confirm.AddItem("yes", "Yes - deconstruct all props");
	confirm.AddItem("no",  "No - go back");
	confirm.ExitBackButton = false;
	confirm.Display(client, 10);
}

public int DeconstructConfirmHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		if (param < 0)
			return 0;

		char item[8], display[64];
		int style;
		if (!menu.GetItem(param, item, sizeof(item), style, display, sizeof(display)))
			return 0;

		if (strcmp(item, "yes", false) == 0) {
			DeconstructAllProps(client);
			PrintToChat(client, "All your props have been deconstructed.");
			ga_bBuildMenuOpen[client] = false;
			CancelClientMenu(client);
		}
		else
			OpenPropSelectionMenu(client);
	}
	return 0;
}

void GetModelName(const char[] fullPath, char[] modelName, int maxLen) {
	int len = strlen(fullPath);
	int start = len;
	int end = len;

	for (int i = len - 1; i >= 0; i--) {
		if (fullPath[i] == '/') {
			start = i + 1;
			break;
		}
	}

	for (int i = start; i < len; i++) {
		if (fullPath[i] == '.') {
			end = i;
			break;
		}
	}

	int copyLen = end - start;
	if (copyLen >= maxLen)
		copyLen = maxLen - 1;

	strcopy(modelName, copyLen + 1, fullPath[start]);
}

bool IsPlayerOnProp(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return false;

	int groundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	if (groundEntity <= MaxClients || !IsValidEntity(groundEntity))
		return false;

	char entityName[64];
	GetEntPropString(groundEntity, Prop_Data, "m_iName", entityName, sizeof(entityName));
	return (StrContains(entityName, "bmprop_c#", false) != -1);
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		RefundAllSupply(i);

		if (ga_hPropPlaced[i] == null)
			continue;

		int iArraySize = ga_hPropPlaced[i].Length;
		if (iArraySize > 0) {
			for (int j = iArraySize - 1; j >= 0; j--) {
				int ent = EntRefToEntIndex(ga_hPropPlaced[i].Get(j));
				if (ent > MaxClients && IsValidEntity(ent))
					RemoveEntity(ent);
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
	if (convar == g_cvAllFree)
		g_iAllFree = g_cvAllFree.IntValue;
}
