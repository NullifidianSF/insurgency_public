#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PL_VERSION "0.5"
#define GAMEDATA_FILE "insurgency-bm.games"
#define PURCHASE_SIZE 0x38
#define PURCHASES_OFFSET 0x34
#define PURCHASE_COUNT_OFFSET 0x40
#define PURCHASE_DEFINITION_OFFSET 0x04
#define PURCHASE_SLOT_OFFSET 0x30
#define PURCHASE_SLOT_INDEX_OFFSET 0x34

enum ExplosiveChoice {
	Explosive_None,
	Explosive_Frag,
	Explosive_Flash,
	Explosive_Smoke,
	Explosive_Molotov,
	Explosive_RPG
};

Handle g_hDestroyItem = null;
Handle g_hRefundWeapon = null;
ConVar g_cvEnabled;
ConVar g_cvNoneChance;
ConVar g_cvFragChance;
ConVar g_cvFlashChance;
ConVar g_cvSmokeChance;
ConVar g_cvMolotovChance;
ConVar g_cvRPGChance;
int g_iMyWeaponsOffset = -1;
int g_iPlayerInventoryOffset = -1;

public Plugin myinfo = {
	name = "[INS] Bot Explosives",
	author = "Nullifidian and Codex",
	description = "Randomises bot explosive loadouts without dropping weapon pickups",
	version = PL_VERSION,
	url = ""
};

public void OnPluginStart() {
	GameData gameData = LoadGameConfigFile(GAMEDATA_FILE);
	if (gameData == null)
		SetFailState("[Bot Explosives] Missing gamedata/%s.txt", GAMEDATA_FILE);

	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CBaseCombatWeapon::DestroyItem")) {
		delete gameData;
		SetFailState("[Bot Explosives] Missing CBaseCombatWeapon::DestroyItem signature.");
	}

	g_hDestroyItem = EndPrepSDKCall();
	if (g_hDestroyItem == null)
	{
		delete gameData;
		SetFailState("[Bot Explosives] Unable to prepare CBaseCombatWeapon::DestroyItem SDKCall.");
	}

	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CPlayerInventory::RefundWeapon")) {
		delete gameData;
		SetFailState("[Bot Explosives] Missing CPlayerInventory::RefundWeapon signature.");
	}
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hRefundWeapon = EndPrepSDKCall();
	if (g_hRefundWeapon == null) {
		delete gameData;
		SetFailState("[Bot Explosives] Unable to prepare CPlayerInventory::RefundWeapon SDKCall.");
	}

	g_iPlayerInventoryOffset = gameData.GetOffset("CINSPlayer::PlayerInventory");
	delete gameData;

	g_iMyWeaponsOffset = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
	if (g_iMyWeaponsOffset == -1)
		SetFailState("[Bot Explosives] Unable to find CBasePlayer::m_hMyWeapons.");

	if (g_iPlayerInventoryOffset == -1)
		SetFailState("[Bot Explosives] Missing CINSPlayer::PlayerInventory offset.");

	g_cvEnabled = CreateConVar("sm_botexplosive_enable", "1",
		"Enable random bot explosive loadouts. 0 = disabled, 1 = enabled.", _, true, 0.0, true, 1.0);
	g_cvNoneChance = CreateConVar("sm_botexplosive_none_chance", "0.60",
		"Chance to remove a bot's explosive without giving a replacement. All bot explosive chances combined must not exceed 1.00.", _, true, 0.0, true, 1.0);
	g_cvFragChance = CreateConVar("sm_botexplosive_frag_chance", "0.20",
		"Chance to give a bot its faction's frag grenade. All bot explosive chances combined must not exceed 1.00.", _, true, 0.0, true, 1.0);
	g_cvFlashChance = CreateConVar("sm_botexplosive_flash_chance", "0.05",
		"Chance to give a bot an M84 flash grenade. All bot explosive chances combined must not exceed 1.00.", _, true, 0.0, true, 1.0);
	g_cvSmokeChance = CreateConVar("sm_botexplosive_smoke_chance", "0.05",
		"Chance to give a bot an M18 smoke grenade. All bot explosive chances combined must not exceed 1.00.", _, true, 0.0, true, 1.0);
	g_cvMolotovChance = CreateConVar("sm_botexplosive_molotov_chance", "0.10",
		"Chance to give a bot a molotov. All bot explosive chances combined must not exceed 1.00.", _, true, 0.0, true, 1.0);
	g_cvRPGChance = CreateConVar("sm_botexplosive_rpg_chance", "0.05",
		"Chance to give a bot an RPG-7. All bot explosive chances combined must not exceed 1.00.", _, true, 0.0, true, 1.0);

	RegAdminCmd("sm_botexplosive_destroy", Command_DestroyExplosives, ADMFLAG_ROOT,
		"sm_botexplosive_destroy [target] - Permanently remove a living player's grenades/RPG without dropping them.");
	RegAdminCmd("sm_botexplosive_inventory", Command_PrintInventory, ADMFLAG_ROOT,
		"sm_botexplosive_inventory [target] - Print a player's native weapon-purchase slots for diagnostics.");
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	AutoExecConfig(true, "bot_explosives");
}

public void OnPluginEnd() {
	delete g_hDestroyItem;
	delete g_hRefundWeapon;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	if (!g_cvEnabled.BoolValue)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsBotAlive(client))
		RequestFrame(Frame_RandomiseBotExplosives, GetClientUserId(client));
}

void Frame_RandomiseBotExplosives(any data) {
	int client = GetClientOfUserId(data);
	if (!IsBotAlive(client))
		return;

	ExplosiveChoice choice = SelectExplosiveChoice();
	if (choice == view_as<ExplosiveChoice>(-1))
		return;

	int removedPurchases;
	DestroyExplosives(client, removedPurchases);
	if (choice == Explosive_None)
		return;

	char weaponClass[32];
	GetExplosiveWeaponClass(client, choice, weaponClass, sizeof(weaponClass));
	GiveExplosive(client, weaponClass);
}

public Action Command_DestroyExplosives(int client, int args) {
	if (client == 0) {
		ReplyToCommand(client, "[Bot Explosives] Run this command in-game or provide a target.");
		return Plugin_Handled;
	}

	int targets[1];
	int targetCount;
	char targetName[MAX_TARGET_LENGTH];
	bool targetNameIsMl;

	if (args == 0) {
		targets[0] = client;
		targetCount = 1;
	} else {
		char targetPattern[MAX_NAME_LENGTH];
		GetCmdArgString(targetPattern, sizeof(targetPattern));
		targetCount = ProcessTargetString(targetPattern, client, targets, sizeof(targets), COMMAND_FILTER_ALIVE,
			targetName, sizeof(targetName), targetNameIsMl);
		if (targetCount != 1) {
			ReplyToTargetError(client, targetCount);
			return Plugin_Handled;
		}
	}

	int removedPurchases;
	int destroyed = DestroyExplosives(targets[0], removedPurchases);
	ReplyToCommand(client, "[Bot Explosives] Removed %d native explosive purchase%s and %d active explosive item%s from %N without dropping a pickup.",
		removedPurchases, removedPurchases == 1 ? "" : "s", destroyed, destroyed == 1 ? "" : "s", targets[0]);
	return Plugin_Handled;
}

public Action Command_PrintInventory(int client, int args) {
	if (client == 0) {
		ReplyToCommand(client, "[Bot Explosives] Run this command in-game or provide a target.");
		return Plugin_Handled;
	}

	int targets[1];
	int targetCount;
	char targetName[MAX_TARGET_LENGTH];
	bool targetNameIsMl;

	if (args == 0) {
		targets[0] = client;
		targetCount = 1;
	} else {
		char targetPattern[MAX_NAME_LENGTH];
		GetCmdArgString(targetPattern, sizeof(targetPattern));
		targetCount = ProcessTargetString(targetPattern, client, targets, sizeof(targets), COMMAND_FILTER_ALIVE,
			targetName, sizeof(targetName), targetNameIsMl);
		if (targetCount != 1) {
			ReplyToTargetError(client, targetCount);
			return Plugin_Handled;
		}
	}

	Address inventory = GetEntityAddress(targets[0]) + view_as<Address>(g_iPlayerInventoryOffset);
	Address purchases = view_as<Address>(LoadFromAddress(inventory + view_as<Address>(PURCHASES_OFFSET), NumberType_Int32));
	int purchaseCount = LoadFromAddress(inventory + view_as<Address>(PURCHASE_COUNT_OFFSET), NumberType_Int32);

	ReplyToCommand(client, "[Bot Explosives] %N has %d native weapon purchase%s.",
		targets[0], purchaseCount, purchaseCount == 1 ? "" : "s");
	if (purchases == Address_Null || purchaseCount < 1)
		return Plugin_Handled;

	for (int index = 0; index < purchaseCount; index++) {
		Address purchase = purchases + view_as<Address>(index * PURCHASE_SIZE);
		int definition = LoadFromAddress(purchase + view_as<Address>(PURCHASE_DEFINITION_OFFSET), NumberType_Int32);
		int slot = LoadFromAddress(purchase + view_as<Address>(PURCHASE_SLOT_OFFSET), NumberType_Int32);
		int slotIndex = LoadFromAddress(purchase + view_as<Address>(PURCHASE_SLOT_INDEX_OFFSET), NumberType_Int32);
		ReplyToCommand(client, "  [%d] definition %d | slot %d | slot index %d", index, definition, slot, slotIndex);
	}

	return Plugin_Handled;
}

ExplosiveChoice SelectExplosiveChoice() {
	float roll = GetRandomFloat(0.0, 1.0);
	float cumulative = g_cvNoneChance.FloatValue;
	if (roll < cumulative)
		return Explosive_None;

	cumulative += g_cvFragChance.FloatValue;
	if (roll < cumulative)
		return Explosive_Frag;

	cumulative += g_cvFlashChance.FloatValue;
	if (roll < cumulative)
		return Explosive_Flash;

	cumulative += g_cvSmokeChance.FloatValue;
	if (roll < cumulative)
		return Explosive_Smoke;

	cumulative += g_cvMolotovChance.FloatValue;
	if (roll < cumulative)
		return Explosive_Molotov;

	cumulative += g_cvRPGChance.FloatValue;
	if (roll < cumulative)
		return Explosive_RPG;

	return view_as<ExplosiveChoice>(-1);
}

void GetExplosiveWeaponClass(int client, ExplosiveChoice choice, char[] weaponClass, int maxLength) {
	switch (choice) {
		case Explosive_Frag:
			strcopy(weaponClass, maxLength, GetClientTeam(client) == 2 ? "weapon_m67" : "weapon_f1");
		case Explosive_Flash:
			strcopy(weaponClass, maxLength, "weapon_m84");
		case Explosive_Smoke:
			strcopy(weaponClass, maxLength, "weapon_m18");
		case Explosive_Molotov:
			strcopy(weaponClass, maxLength, "weapon_molotov");
		case Explosive_RPG:
			strcopy(weaponClass, maxLength, "weapon_rpg7");
	}
}

void GiveExplosive(int client, const char[] weaponClass) {
	int weapon = GivePlayerItem(client, weaponClass);
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return;

	int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
	if (ammoType >= 0)
		SetEntProp(client, Prop_Send, "m_iAmmo", 1, _, ammoType);
}

int DestroyExplosives(int client, int &removedPurchases) {
	int weaponRefs[48];
	int weaponCount;

	for (int offset = 0; offset < 192; offset += 4) {
		int weapon = GetEntDataEnt2(client, g_iMyWeaponsOffset + offset);
		if (!IsExplosiveWeapon(weapon))
			continue;

		int weaponRef = EntIndexToEntRef(weapon);
		bool alreadyFound;
		for (int index = 0; index < weaponCount; index++)
			if (weaponRefs[index] == weaponRef) {
				alreadyFound = true;
				break;
			}

		if (!alreadyFound)
			weaponRefs[weaponCount++] = weaponRef;
	}

	int destroyed;
	for (int index = 0; index < weaponCount; index++) {
		int weapon = EntRefToEntIndex(weaponRefs[index]);
		if (weapon == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
			continue;

		SDKCall(g_hDestroyItem, weapon);
		destroyed++;
	}

	removedPurchases = RefundExplosivePurchases(client);
	return destroyed;
}

int RefundExplosivePurchases(int client) {
	Address inventory = GetEntityAddress(client) + view_as<Address>(g_iPlayerInventoryOffset);
	Address purchases = view_as<Address>(LoadFromAddress(inventory + view_as<Address>(PURCHASES_OFFSET), NumberType_Int32));
	int purchaseCount = LoadFromAddress(inventory + view_as<Address>(PURCHASE_COUNT_OFFSET), NumberType_Int32);
	if (purchases == Address_Null || purchaseCount < 1 || purchaseCount > 48)
		return 0;

	int refunded;
	for (int index = purchaseCount - 1; index >= 0; index--) {
		Address purchase = purchases + view_as<Address>(index * PURCHASE_SIZE);
		int slot = LoadFromAddress(purchase + view_as<Address>(PURCHASE_SLOT_OFFSET), NumberType_Int32);
		if (slot != 3)
			continue;

		if (SDKCall(g_hRefundWeapon, inventory, index) == 0)
			refunded++;
	}

	return refunded;
}

bool IsExplosiveWeapon(int weapon) {
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return false;

	char weaponClass[32];
	GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));
	return StrEqual(weaponClass, "weapon_m67")
		|| StrEqual(weaponClass, "weapon_m26a2")
		|| StrEqual(weaponClass, "weapon_f1")
		|| StrEqual(weaponClass, "weapon_m18")
		|| StrEqual(weaponClass, "weapon_m84")
		|| StrEqual(weaponClass, "weapon_molotov")
		|| StrEqual(weaponClass, "weapon_rpg7");
}

bool IsBotAlive(int client) {
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client) && IsPlayerAlive(client);
}
