#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>

#define PL_VERSION "4.27"
#define CONFIG_FILE "configs/weapon_vote_loadout_weapons.cfg"
#define THEATER_ITEMS_FILE "configs/weapon_vote_theateritems.txt"
#define GENERATED_CONFIG_FILE "configs/weapon_vote_loadout_weapons.generated.cfg"
#define LOG_DIRECTORY "logs/weapon_vote"
#define SOUND_VOTE_START "ui/vote_started.wav"
#define SOUND_VOTE_PASSED "ui/vote_success.wav"
#define SOUND_VOTE_FAILED "ui/vote_failure.wav"
#define MAX_WEAPON_CLASSNAME 64
#define MAX_WEAPON_DISPLAY_NAME 64
#define MAX_PLAYER_WEAPONS 48
#define MAX_NATIVE_PURCHASES 48
#define PURCHASE_SIZE 0x38
#define PURCHASES_OFFSET 0x34
#define PURCHASE_COUNT_OFFSET 0x40
#define PURCHASE_SLOT_OFFSET 0x30

enum {
	WeaponSlot_Primary,
	WeaponSlot_Secondary,
	WeaponSlot_Count
};

enum {
	UpgradeCategory_Ammo,
	UpgradeCategory_Scope,
	UpgradeCategory_Barrel,
	UpgradeCategory_Aesthetic,
	UpgradeCategory_Siderail,
	UpgradeCategory_Underbarrel,
	UpgradeCategory_Magazine,
	UpgradeCategory_Stock,
	UpgradeCategory_Count
};

Handle g_hDestroyItem = null;
Handle g_hRefundWeapon = null;
Handle g_hInstallWeaponUpgrade = null;
Handle g_hGiveAmmo = null;
Handle g_hGetMagazines = null;
DynamicDetour g_hPlayerResupplyDetour = null;
ArrayList g_aWeaponClasses = null;
ArrayList g_aWeaponNames = null;
ArrayList g_aWeaponDefinitions = null;
ArrayList g_aWeaponSlots = null;
ArrayList g_aGeneratorWeaponClasses = null;
ArrayList g_aGeneratorWeaponDefinitions = null;
ArrayList g_aGeneratorUpgradeNames = null;
ArrayList g_aGeneratorUpgradeCategories = null;
File g_fGeneratedConfig = null;
Handle g_hGeneratorTimer = null;
Handle g_hWeaponVoteAdvertTimer = null;
Handle g_hWeaponVoteEnableTimer = null;

ConVar g_cvEnabled;
ConVar g_cvStartDelay;
ConVar g_cvVoteTime;
ConVar g_cvRequiredRatio;
ConVar g_cvMinVoters;
ConVar g_cvCooldown;
ConVar g_cvAllowRevote;
ConVar g_cvRounds;
ConVar g_cvReserveAmmo;
ConVar g_cvRoundTime = null;
int g_iPlayerInventoryOffset = -1;
int g_iMyWeaponsOffset = -1;
int g_iVotesYes;
int g_iVotesNo;
int g_iRoundsRemaining;
float g_fNextVoteAt;
float g_fVoteEnableAt;
bool g_bVoteRunning;
bool g_bDisableVote;
bool g_bModeActive;
int g_iGeneratorClientUserId;
int g_iGeneratorWeaponIndex;
int g_iGeneratorUpgradeIndex;
int g_iGeneratorRestoreWeaponRef = INVALID_ENT_REFERENCE;
bool g_bGeneratorWeaponOpen;
bool g_bGeneratorRoundTimeOverridden;
char g_sGeneratorOriginalRoundTime[32];
bool g_bClientVoted[MAXPLAYERS + 1];
char ga_sSelectedWeapons[MAXPLAYERS + 1][WeaponSlot_Count][MAX_WEAPON_CLASSNAME];
char ga_sSelectedWeaponNames[MAXPLAYERS + 1][WeaponSlot_Count][MAX_WEAPON_DISPLAY_NAME];
int ga_iSelectedWeaponDefinitions[MAXPLAYERS + 1][WeaponSlot_Count];
int ga_iSelectedUpgrades[MAXPLAYERS + 1][WeaponSlot_Count][UpgradeCategory_Count];
char g_sPendingWeapons[WeaponSlot_Count][MAX_WEAPON_CLASSNAME];
char g_sPendingWeaponNames[WeaponSlot_Count][MAX_WEAPON_DISPLAY_NAME];
int g_iPendingWeaponDefinitions[WeaponSlot_Count];
int g_iPendingUpgrades[WeaponSlot_Count][UpgradeCategory_Count];
char g_sActiveWeapons[WeaponSlot_Count][MAX_WEAPON_CLASSNAME];
char g_sActiveWeaponNames[WeaponSlot_Count][MAX_WEAPON_DISPLAY_NAME];
int g_iActiveWeaponDefinitions[WeaponSlot_Count];
int g_iActiveUpgrades[WeaponSlot_Count][UpgradeCategory_Count];

public Plugin myinfo = {
	name = "[INS] Weapon Vote",
	author = "Nullifidian & Codex",
	description = "Lets players vote for a configured two-weapon loadout",
	version = PL_VERSION,
	url = ""
};

public void OnPluginStart() {
	GameData gameData = LoadGameConfigFile("insurgency-bm.games");
	if (gameData == null)
		SetFailState("[Weapon Vote] Missing gamedata/insurgency-bm.games.txt");

	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CBaseCombatWeapon::DestroyItem")) {
		delete gameData;
		SetFailState("[Weapon Vote] Missing CBaseCombatWeapon::DestroyItem signature.");
	}

	g_hDestroyItem = EndPrepSDKCall();
	if (g_hDestroyItem == null) {
		delete gameData;
		SetFailState("[Weapon Vote] Unable to prepare CBaseCombatWeapon::DestroyItem SDKCall.");
	}

	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CPlayerInventory::RefundWeapon")) {
		delete gameData;
		SetFailState("[Weapon Vote] Missing CPlayerInventory::RefundWeapon signature.");
	}

	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hRefundWeapon = EndPrepSDKCall();
	if (g_hRefundWeapon == null) {
		delete gameData;
		SetFailState("[Weapon Vote] Unable to prepare CPlayerInventory::RefundWeapon SDKCall.");
	}

	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CINSWeapon::InstallWeaponUpgrade")) {
		delete gameData;
		SetFailState("[Weapon Vote] Missing CINSWeapon::InstallWeaponUpgrade signature.");
	}

	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_hInstallWeaponUpgrade = EndPrepSDKCall();
	if (g_hInstallWeaponUpgrade == null) {
		delete gameData;
		SetFailState("[Weapon Vote] Unable to prepare CINSWeapon::InstallWeaponUpgrade SDKCall.");
	}

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CINSPlayer::GiveAmmo")) {
		delete gameData;
		SetFailState("[Weapon Vote] Missing CINSPlayer::GiveAmmo signature.");
	}

	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hGiveAmmo = EndPrepSDKCall();
	if (g_hGiveAmmo == null) {
		delete gameData;
		SetFailState("[Weapon Vote] Unable to prepare CINSPlayer::GiveAmmo SDKCall.");
	}

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CINSPlayer::GetMagazines")) {
		delete gameData;
		SetFailState("[Weapon Vote] Missing CINSPlayer::GetMagazines signature.");
	}

	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hGetMagazines = EndPrepSDKCall();
	if (g_hGetMagazines == null) {
		delete gameData;
		SetFailState("[Weapon Vote] Unable to prepare CINSPlayer::GetMagazines SDKCall.");
	}

	g_iPlayerInventoryOffset = gameData.GetOffset("CINSPlayer::PlayerInventory");
	if (g_iPlayerInventoryOffset == -1)
		SetFailState("[Weapon Vote] Missing CINSPlayer::PlayerInventory offset.");

	g_hPlayerResupplyDetour = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Bool, ThisPointer_CBaseEntity);
	if (!g_hPlayerResupplyDetour.SetFromConf(gameData, SDKConf_Signature, "CINSPlayer::Resupply")) {
		delete gameData;
		SetFailState("[Weapon Vote] Missing CINSPlayer::Resupply signature.");
	}

	g_hPlayerResupplyDetour.AddParam(HookParamType_Bool);
	if (!g_hPlayerResupplyDetour.Enable(Hook_Post, Detour_PlayerResupply_Post)) {
		delete gameData;
		SetFailState("[Weapon Vote] Could not enable the CINSPlayer::Resupply detour.");
	}

	delete gameData;

	g_iMyWeaponsOffset = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
	if (g_iMyWeaponsOffset == -1)
		SetFailState("[Weapon Vote] Unable to find CBasePlayer::m_hMyWeapons.");

	g_aWeaponClasses = new ArrayList(ByteCountToCells(MAX_WEAPON_CLASSNAME));
	g_aWeaponNames = new ArrayList(ByteCountToCells(MAX_WEAPON_DISPLAY_NAME));
	g_aWeaponDefinitions = new ArrayList();
	g_aWeaponSlots = new ArrayList();
	g_aGeneratorWeaponClasses = new ArrayList(ByteCountToCells(MAX_WEAPON_CLASSNAME));
	g_aGeneratorWeaponDefinitions = new ArrayList();
	g_aGeneratorUpgradeNames = new ArrayList(ByteCountToCells(MAX_WEAPON_DISPLAY_NAME));
	g_aGeneratorUpgradeCategories = new ArrayList();
	LoadWeaponConfig();

	g_cvEnabled = CreateConVar("sm_weaponvote_enabled", "1",
		"Enable player weapon votes. 0 = disabled, 1 = enabled.", _, true, 0.0, true, 1.0);

	g_cvStartDelay = CreateConVar("sm_weaponvote_start_delay", "30.0",
		"Seconds after a map starts before players may use !weaponvote. Gives players time to join. 0 = no delay.", _, true, 0.0, true, 300.0);

	g_cvVoteTime = CreateConVar("sm_weaponvote_vote_time", "20",
		"Seconds a weapon loadout vote remains open.", _, true, 5.0, true, 60.0);

	g_cvRequiredRatio = CreateConVar("sm_weaponvote_required_ratio", "0.70",
		"Yes-vote fraction of cast votes required to enable the selected loadout.", _, true, 0.01, true, 1.0);

	g_cvMinVoters = CreateConVar("sm_weaponvote_min_voters", "6",
		"Minimum number of cast votes required for a weapon loadout vote to pass.", _, true, 1.0, true, float(MAXPLAYERS));

	g_cvCooldown = CreateConVar("sm_weaponvote_cooldown", "300.0",
		"Seconds before another player may start a weapon loadout vote.", _, true, 0.0);

	g_cvAllowRevote = CreateConVar("sm_weaponvote_allow_revote", "1",
		"Allow a new loadout vote after sm_weaponvote_cooldown while a voted loadout is active. 0 = only a disable vote is available, 1 = allow replacement votes.", _, true, 0.0, true, 1.0);

	g_cvRounds = CreateConVar("sm_weaponvote_rounds", "1",
		"Rounds the winning weapon loadout lasts. 0 = until the map changes.", _, true, 0.0, true, 99.0);

	g_cvReserveAmmo = CreateConVar("sm_weaponvote_reserve_ammo", "7",
		"Full reloads given with each voted weapon. Loose-ammo weapons receive this many weapon-capacity reloads. 0 = weapon starts loaded only.", _, true, 0.0, true, 100.0);

	g_cvRoundTime = FindConVar("mp_roundtime");

	RegConsoleCmd("sm_weaponvote", Command_WeaponVote,
		"Open the weapon-vote loadout menu.");

	RegAdminCmd("sm_weaponvote_end", Command_EndWeaponVote, ADMFLAG_BAN,
		"End the active weapon loadout restriction.");

	RegAdminCmd("sm_weaponvote_reload", Command_ReloadWeaponVote, ADMFLAG_ROOT,
		"Reload configs/weapon_vote_loadout_weapons.cfg.");
	// Optional automatic config generator:
	// 1. Run listtheateritems in the server console and paste its full output into
	//    addons/sourcemod/configs/weapon_vote_theateritems.txt.
	// 2. As an alive root admin on a quiet server, run sm_weaponvote_generate.
	// The generator tests every listed upgrade one at a time and writes accepted
	// upgrades to addons/sourcemod/configs/weapon_vote_loadout_weapons.generated.cfg.
	// It does not overwrite the live config. Use sm_weaponvote_generate_stop to stop early.
	RegAdminCmd("sm_weaponvote_generate", Command_GenerateWeaponVoteConfig, ADMFLAG_ROOT,
		"Generate weapon_vote_loadout_weapons.generated.cfg by probing the theater item list.");
		
	RegAdminCmd("sm_weaponvote_generate_stop", Command_StopWeaponVoteGenerator, ADMFLAG_ROOT,
		"Stop the current weapon-vote theater-item scan and keep completed entries.");

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_pick_squad", Event_PlayerPickSquad, EventHookMode_Post);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	AddCommandListener(CommandListener_BuyWeapon, "inventory_buy_weapon");
	AutoExecConfig(true, "weapon_vote");

	for (int client = 1; client <= MaxClients; client++)
		ResetClientSelection(client);

	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client))
			SDKHook(client, SDKHook_WeaponEquip, Hook_WeaponEquip);
}

public void OnMapStart() {
	PrecacheVoteSounds();
	ScheduleWeaponVoteEnable();
	ScheduleWeaponVoteAdvertisement();
	g_bVoteRunning = false;
	g_bDisableVote = false;
	g_bModeActive = false;
	g_iRoundsRemaining = 0;
	ResetPendingLoadout();
	ResetActiveLoadout();
}

void PrecacheVoteSounds() {
	PrecacheSound(SOUND_VOTE_START, true);
	PrecacheSound(SOUND_VOTE_PASSED, true);
	PrecacheSound(SOUND_VOTE_FAILED, true);
}

void PlayVoteSound(const char[] sound) {
	EmitSoundToAll(sound, _, SNDCHAN_STATIC);
}

void ScheduleWeaponVoteEnable() {
	delete g_hWeaponVoteEnableTimer;
	float delay = g_cvStartDelay.FloatValue;
	g_fVoteEnableAt = GetGameTime() + delay;
	if (delay > 0.0)
		g_hWeaponVoteEnableTimer = CreateTimer(delay, Timer_EnableWeaponVote);
}

public Action Timer_EnableWeaponVote(Handle timer) {
	g_hWeaponVoteEnableTimer = null;
	if (g_cvEnabled.BoolValue)
		PrintToChatAll("\x04[Weapon Vote]\x01 Weapon voting is now enabled. Type !weaponvote to start a vote.");

	return Plugin_Stop;
}

void ScheduleWeaponVoteAdvertisement() {
	delete g_hWeaponVoteAdvertTimer;
	g_hWeaponVoteAdvertTimer = CreateTimer(GetRandomFloat(900.0, 1800.0), Timer_WeaponVoteAdvertisement);
}

public Action Timer_WeaponVoteAdvertisement(Handle timer) {
	g_hWeaponVoteAdvertTimer = null;
	if (g_cvEnabled.BoolValue && !g_bModeActive)
		PrintToChatAll("\x04[Weapon Vote]\x01 Type !weaponvote to choose a weapon loadout and start a vote.");

	ScheduleWeaponVoteAdvertisement();
	return Plugin_Stop;
}

public void OnPluginEnd() {
	RestoreGeneratorRoundTime();
	if (g_hPlayerResupplyDetour != null)
		g_hPlayerResupplyDetour.Disable(Hook_Post, Detour_PlayerResupply_Post);
	delete g_hPlayerResupplyDetour;
	delete g_hDestroyItem;
	delete g_hRefundWeapon;
	delete g_hInstallWeaponUpgrade;
	delete g_hGiveAmmo;
	delete g_hGetMagazines;
	delete g_aWeaponClasses;
	delete g_aWeaponNames;
	delete g_aWeaponDefinitions;
	delete g_aWeaponSlots;
	delete g_aGeneratorWeaponClasses;
	delete g_aGeneratorWeaponDefinitions;
	delete g_aGeneratorUpgradeNames;
	delete g_aGeneratorUpgradeCategories;
	delete g_hGeneratorTimer;
	delete g_hWeaponVoteAdvertTimer;
	delete g_hWeaponVoteEnableTimer;
	delete g_fGeneratedConfig;
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_WeaponEquip, Hook_WeaponEquip);
}

public void OnClientDisconnect(int client) {
	g_bClientVoted[client] = false;
	ResetClientSelection(client);
}

public void Event_PlayerPickSquad(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bModeActive)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsEligibleVoter(client))
		return;

	char loadout[160];
	BuildLoadoutDescription(g_sActiveWeaponNames[WeaponSlot_Primary], g_sActiveWeaponNames[WeaponSlot_Secondary], loadout, sizeof(loadout));
	PrintToChat(client, "\x04[Weapon Vote]\x01 Active voted loadout: %s.", loadout);
}

public Action Command_WeaponVote(int client, int args) {
	if (!IsEligibleVoter(client)) {
		ReplyToCommand(client, "[Weapon Vote] You must be an active human player to start a vote.");
		return Plugin_Handled;
	}

	if (!g_cvEnabled.BoolValue) {
		ReplyToCommand(client, "[Weapon Vote] Weapon votes are disabled.");
		return Plugin_Handled;
	}

	float enableRemaining = g_fVoteEnableAt - GetGameTime();
	if (enableRemaining > 0.0) {
		ReplyToCommand(client, "[Weapon Vote] Weapon voting will be enabled in %.0f seconds, allowing players time to join.", enableRemaining);
		return Plugin_Handled;
	}

	if (g_bVoteRunning || IsVoteInProgress()) {
		ReplyToCommand(client, "[Weapon Vote] A vote is already in progress.");
		return Plugin_Handled;
	}

	float remaining = g_fNextVoteAt - GetGameTime();
	if (remaining > 0.0) {
		ReplyToCommand(client, "[Weapon Vote] Wait %.0f seconds before starting another vote.", remaining);
		return Plugin_Handled;
	}

	if (g_bModeActive && !g_cvAllowRevote.BoolValue) {
		if (args == 0)
			ShowLoadoutMenu(client);
		else
			ReplyToCommand(client, "[Weapon Vote] A voted loadout is active. Use sm_weaponvote without an argument to vote to disable it.");

		return Plugin_Handled;
	}

	if (args == 0) {
		ShowLoadoutMenu(client);
		return Plugin_Handled;
	}

	char weaponClass[MAX_WEAPON_CLASSNAME];
	GetCmdArg(1, weaponClass, sizeof(weaponClass));
	int index = g_aWeaponClasses.FindString(weaponClass);
	if (index == -1) {
		ReplyToCommand(client, "[Weapon Vote] '%s' is not listed in %s.", weaponClass, CONFIG_FILE);
		return Plugin_Handled;
	}

	SelectWeapon(client, WeaponSlot_Primary, index);
	ShowUpgradeMenu(client, WeaponSlot_Primary);
	return Plugin_Handled;
}

public Action Command_EndWeaponVote(int client, int args) {
	if (!g_bModeActive) {
		ReplyToCommand(client, "[Weapon Vote] No weapon loadout mode is active.");
		return Plugin_Handled;
	}

	EndWeaponMode();
	PrintToChatAll("\x04[Weapon Vote]\x01 Weapon loadout restriction ended.");
	return Plugin_Handled;
}

public Action Command_ReloadWeaponVote(int client, int args) {
	LoadWeaponConfig();
	ReplyToCommand(client, "[Weapon Vote] Loaded %d configured weapon%s.",
		g_aWeaponClasses.Length, g_aWeaponClasses.Length == 1 ? "" : "s");
	return Plugin_Handled;
}

public Action Command_GenerateWeaponVoteConfig(int client, int args) {
	if (!IsEligibleVoter(client) || !IsPlayerAlive(client)) {
		ReplyToCommand(client, "[Weapon Vote] You must be an alive human player to run the generator.");
		return Plugin_Handled;
	}

	if (g_bModeActive) {
		ReplyToCommand(client, "[Weapon Vote] End the active voted loadout before running the generator.");
		return Plugin_Handled;
	}

	if (g_hGeneratorTimer != null) {
		ReplyToCommand(client, "[Weapon Vote] A theater-item scan is already running.");
		return Plugin_Handled;
	}

	if (!LoadGeneratorItemList()) {
		ReplyToCommand(client, "[Weapon Vote] Missing or invalid %s.", THEATER_ITEMS_FILE);
		return Plugin_Handled;
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), GENERATED_CONFIG_FILE);
	g_fGeneratedConfig = OpenFile(path, "w");
	if (g_fGeneratedConfig == null) {
		ReplyToCommand(client, "[Weapon Vote] Could not open %s for writing.", GENERATED_CONFIG_FILE);
		return Plugin_Handled;
	}

	g_fGeneratedConfig.WriteLine("// Generated by sm_weaponvote_generate. Review before replacing the live config.");
	g_fGeneratedConfig.WriteLine("// Only upgrades accepted by CINSWeapon::InstallWeaponUpgrade are included.");
	g_fGeneratedConfig.WriteLine("\"WeaponVoteWeapons\"");
	g_fGeneratedConfig.WriteLine("{");
	g_iGeneratorClientUserId = GetClientUserId(client);
	g_iGeneratorWeaponIndex = 0;
	g_iGeneratorUpgradeIndex = 0;
	g_iGeneratorRestoreWeaponRef = INVALID_ENT_REFERENCE;
	g_bGeneratorWeaponOpen = false;
	SetGeneratorRoundTime();
	ServerCommand("mp_restartgame 1");
	g_hGeneratorTimer = CreateTimer(2.0, Timer_GenerateWeaponVoteConfig, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	ReplyToCommand(client, "[Weapon Vote] Restarting the round, then scanning %d weapons against %d upgrades. Do not play while it runs.",
		g_aGeneratorWeaponClasses.Length, g_aGeneratorUpgradeNames.Length);
	return Plugin_Handled;
}

public Action Command_StopWeaponVoteGenerator(int client, int args) {
	if (g_hGeneratorTimer == null) {
		ReplyToCommand(client, "[Weapon Vote] No theater-item scan is running.");
		return Plugin_Handled;
	}

	delete g_hGeneratorTimer;
	FinishWeaponVoteGenerator(false);
	ReplyToCommand(client, "[Weapon Vote] Generator stopped. Completed entries were kept in %s.", GENERATED_CONFIG_FILE);
	return Plugin_Handled;
}

public Action Timer_GenerateWeaponVoteConfig(Handle timer) {
	int client = GetClientOfUserId(g_iGeneratorClientUserId);
	if (!IsEligibleVoter(client) || !IsPlayerAlive(client)) {
		FinishWeaponVoteGenerator(false);
		return Plugin_Stop;
	}

	if (g_iGeneratorWeaponIndex >= g_aGeneratorWeaponClasses.Length) {
		FinishWeaponVoteGenerator(true);
		PrintToChat(client, "\x04[Weapon Vote]\x01 Generation finished. Created %s.", GENERATED_CONFIG_FILE);
		ReplyToCommand(client, "[Weapon Vote] Generated %s.", GENERATED_CONFIG_FILE);
		LogMessage("[Weapon Vote] Generation finished. Created %s.", GENERATED_CONFIG_FILE);
		return Plugin_Stop;
	}

	char weaponClass[MAX_WEAPON_CLASSNAME];
	g_aGeneratorWeaponClasses.GetString(g_iGeneratorWeaponIndex, weaponClass, sizeof(weaponClass));
	int previousWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	g_iGeneratorRestoreWeaponRef = previousWeapon > MaxClients && IsValidEntity(previousWeapon) ? EntIndexToEntRef(previousWeapon) : INVALID_ENT_REFERENCE;

	int weapon = GivePlayerItem(client, weaponClass);
	if (weapon <= MaxClients || !IsValidEntity(weapon)) {
		LogError("[Weapon Vote] Generator could not give %s to %N.", weaponClass, client);
		AdvanceWeaponVoteGenerator();
		return Plugin_Continue;
	}

	if (!g_bGeneratorWeaponOpen)
		OpenGeneratedWeaponSection(client, weapon, weaponClass);

	int upgradeId = g_iGeneratorUpgradeIndex + 1;
	if (SDKCall(g_hInstallWeaponUpgrade, weapon, upgradeId, true))
		WriteGeneratedUpgrade(upgradeId);

	SDKCall(g_hDestroyItem, weapon);
	RequestFrame(Frame_RestoreGeneratorActiveWeapon, g_iGeneratorRestoreWeaponRef);
	g_iGeneratorUpgradeIndex++;
	if (g_iGeneratorUpgradeIndex >= g_aGeneratorUpgradeNames.Length)
		AdvanceWeaponVoteGenerator();

	return Plugin_Continue;
}

void Frame_RestoreGeneratorActiveWeapon(any data) {
	int weapon = EntRefToEntIndex(data);
	int client = GetClientOfUserId(g_iGeneratorClientUserId);
	if (IsEligibleVoter(client) && weapon > MaxClients && IsValidEntity(weapon))
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
}

void OpenGeneratedWeaponSection(int client, int weapon, const char[] weaponClass) {
	char displayName[MAX_WEAPON_DISPLAY_NAME];
	strcopy(displayName, sizeof(displayName), weaponClass[7]);
	ReplaceString(displayName, sizeof(displayName), "_", " ");
	int definition = g_aGeneratorWeaponDefinitions.Get(g_iGeneratorWeaponIndex);
	char slot[16];
	GetGeneratedWeaponSlot(client, weapon, weaponClass, slot, sizeof(slot));

	g_fGeneratedConfig.WriteLine("\t\"%s\"", weaponClass);
	g_fGeneratedConfig.WriteLine("\t{");
	g_fGeneratedConfig.WriteLine("\t\t\"name\" \"%s\"", displayName);
	g_fGeneratedConfig.WriteLine("\t\t\"definition\" \"%d\"", definition);
	g_fGeneratedConfig.WriteLine("\t\t\"slot\" \"%s\"", slot);
	g_fGeneratedConfig.WriteLine("\t\t\"upgrades\"");
	g_fGeneratedConfig.WriteLine("\t\t{");
	g_bGeneratorWeaponOpen = true;
}

void WriteGeneratedUpgrade(int upgradeId) {
	char upgradeName[MAX_WEAPON_DISPLAY_NAME];
	g_aGeneratorUpgradeNames.GetString(g_iGeneratorUpgradeIndex, upgradeName, sizeof(upgradeName));
	ReplaceString(upgradeName, sizeof(upgradeName), "_", " ");
	int category = g_aGeneratorUpgradeCategories.Get(g_iGeneratorUpgradeIndex);
	char categoryName[32];
	GetUpgradeCategoryName(category, categoryName, sizeof(categoryName));
	g_fGeneratedConfig.WriteLine("\t\t\t\"upgrade_%d\" { \"id\" \"%d\" \"name\" \"%s\" \"category\" \"%s\" }", upgradeId, upgradeId, upgradeName, categoryName);
}

void AdvanceWeaponVoteGenerator() {
	if (g_bGeneratorWeaponOpen) {
		g_fGeneratedConfig.WriteLine("\t\t}");
		g_fGeneratedConfig.WriteLine("\t}");
	}

	g_iGeneratorWeaponIndex++;
	g_iGeneratorUpgradeIndex = 0;
	g_bGeneratorWeaponOpen = false;
}

void FinishWeaponVoteGenerator(bool completed) {
	if (g_bGeneratorWeaponOpen) {
		g_fGeneratedConfig.WriteLine("\t\t}");
		g_fGeneratedConfig.WriteLine("\t}");
	}

	if (g_fGeneratedConfig != null) {
		g_fGeneratedConfig.WriteLine("}");
		delete g_fGeneratedConfig;
	}

	if (!completed)
		LogMessage("[Weapon Vote] Generator stopped before completion. The generated file contains completed weapons only.");
	g_hGeneratorTimer = null;
	g_bGeneratorWeaponOpen = false;
	RestoreGeneratorRoundTime();
}

void SetGeneratorRoundTime() {
	if (g_cvRoundTime == null)
		return;

	g_cvRoundTime.GetString(g_sGeneratorOriginalRoundTime, sizeof(g_sGeneratorOriginalRoundTime));
	g_cvRoundTime.FloatValue = 9999.0;
	g_bGeneratorRoundTimeOverridden = true;
}

void RestoreGeneratorRoundTime() {
	if (!g_bGeneratorRoundTimeOverridden || g_cvRoundTime == null)
		return;

	g_cvRoundTime.SetString(g_sGeneratorOriginalRoundTime);
	g_bGeneratorRoundTimeOverridden = false;
}

bool LoadGeneratorItemList() {
	g_aGeneratorWeaponClasses.Clear();
	g_aGeneratorWeaponDefinitions.Clear();
	g_aGeneratorUpgradeNames.Clear();
	g_aGeneratorUpgradeCategories.Clear();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), THEATER_ITEMS_FILE);
	File file = OpenFile(path, "r");
	if (file == null)
		return false;

	bool readingUpgrades;
	int weaponDefinition;
	int upgradeId;
	char line[PLATFORM_MAX_PATH];
	while (file.ReadLine(line, sizeof(line))) {
		TrimString(line);
		if (line[0] == '\0')
			continue;

		if (StrContains(line, "Weapons:", false) == 0) {
			readingUpgrades = true;
			continue;
		}

		if (StrContains(line, "Weapon Upgrades:", false) == 0)
			break;

		if (!readingUpgrades) {
			weaponDefinition++;
			if (IsGeneratorWeaponCandidate(line)) {
				g_aGeneratorWeaponClasses.PushString(line);
				g_aGeneratorWeaponDefinitions.Push(weaponDefinition);
			}
			continue;
		}

		upgradeId++;
		g_aGeneratorUpgradeNames.PushString(line);
		g_aGeneratorUpgradeCategories.Push(GetGeneratedUpgradeCategory(line));
	}

	delete file;
	return g_aGeneratorWeaponClasses.Length > 0 && g_aGeneratorUpgradeNames.Length > 0;
}

bool IsGeneratorWeaponCandidate(const char[] weaponClass) {
	return StrContains(weaponClass, "weapon_", false) == 0
		&& !IsAllowedUtilityWeapon(weaponClass)
		&& StrContains(weaponClass, "weapon_m203_", false) != 0
		&& StrContains(weaponClass, "weapon_gp25_", false) != 0
		&& !StrEqual(weaponClass, "weapon_riotshield")
		&& !StrEqual(weaponClass, "weapon_suicide_bomb_melee")
		&& !StrEqual(weaponClass, "weapon_p2a1")
		&& !StrEqual(weaponClass, "weapon_firesupport");
}

int GetGeneratedUpgradeCategory(const char[] upgradeName) {
	if (StrContains(upgradeName, "ammo_", false) == 0 || StrContains(upgradeName, "base_ammo", false) == 0)
		return UpgradeCategory_Ammo;
	if (StrContains(upgradeName, "optic_", false) == 0 || StrEqual(upgradeName, "trijicon_optics", false))
		return UpgradeCategory_Scope;
	if (StrContains(upgradeName, "magazine_", false) == 0)
		return UpgradeCategory_Magazine;
	if (StrContains(upgradeName, "underbarrel_", false) == 0 || StrEqual(upgradeName, "base_bipod", false))
		return UpgradeCategory_Underbarrel;
	if (StrContains(upgradeName, "siderail_", false) == 0 || StrContains(upgradeName, "base_flashlight", false) == 0 || StrContains(upgradeName, "base_lasersight", false) == 0)
		return UpgradeCategory_Siderail;
	if (StrContains(upgradeName, "barrel_", false) == 0 || StrContains(upgradeName, "brake_", false) == 0 || StrContains(upgradeName, "base_silencer", false) == 0 || StrEqual(upgradeName, "base_heavybarrel", false))
		return UpgradeCategory_Barrel;
	if (StrContains(upgradeName, "stock_", false) == 0 || StrContains(upgradeName, "sling", false) != -1 || StrContains(upgradeName, "holster", false) != -1 || StrEqual(upgradeName, "base_recoilstock", false))
		return UpgradeCategory_Stock;

	return UpgradeCategory_Aesthetic;
}

void GetGeneratedWeaponSlot(int client, int weapon, const char[] weaponClass, char[] buffer, int maxLength) {
	for (int slot = 0; slot < 6; slot++) {
		if (GetPlayerWeaponSlot(client, slot) != weapon)
			continue;

		strcopy(buffer, maxLength, slot == 1 ? "secondary" : "primary");
		return;
	}

	strcopy(buffer, maxLength, IsKnownSecondaryWeapon(weaponClass) ? "secondary" : "primary");
}

bool IsKnownSecondaryWeapon(const char[] weaponClass) {
	return StrEqual(weaponClass, "weapon_m9")
		|| StrEqual(weaponClass, "weapon_makarov")
		|| StrEqual(weaponClass, "weapon_taurusjudge")
		|| StrEqual(weaponClass, "weapon_sigp226")
		|| StrEqual(weaponClass, "weapon_mp443")
		|| StrEqual(weaponClass, "weapon_m45seriespistol")
		|| StrEqual(weaponClass, "weapon_sigp220")
		|| StrEqual(weaponClass, "weapon_9mmsidearm")
		|| StrEqual(weaponClass, "weapon_beretta93r")
		|| StrEqual(weaponClass, "weapon_combatcommander")
		|| StrEqual(weaponClass, "weapon_glock33")
		|| StrEqual(weaponClass, "weapon_fiveseven")
		|| StrEqual(weaponClass, "weapon_cobra")
		|| StrEqual(weaponClass, "weapon_deagle")
		|| StrEqual(weaponClass, "weapon_glock18")
		|| StrEqual(weaponClass, "weapon_glock17")
		|| StrEqual(weaponClass, "weapon_hkusp");
}

void ShowLoadoutMenu(int client) {
	Menu menu = new Menu(MenuHandler_Loadout);
	menu.SetTitle(g_bModeActive ? "Weapon Vote Loadout (active)" : "Weapon Vote Loadout");

	if (g_bModeActive && !g_cvAllowRevote.BoolValue) {
		menu.AddItem("disable", "Vote to disable current voted loadout");
		menu.Display(client, MENU_TIME_FOREVER);
		return;
	}

	char label[160];
	Format(label, sizeof(label), "Primary: %s", HasSelectedWeapon(client, WeaponSlot_Primary) ? ga_sSelectedWeaponNames[client][WeaponSlot_Primary] : "Not selected");
	menu.AddItem("slot:0", label);
	Format(label, sizeof(label), "Secondary: %s", HasSelectedWeapon(client, WeaponSlot_Secondary) ? ga_sSelectedWeaponNames[client][WeaponSlot_Secondary] : "Not selected");
	menu.AddItem("slot:1", label);
	menu.AddItem("start", "Start Vote", HasSelectedWeapon(client, WeaponSlot_Primary) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	if (g_bModeActive)
		menu.AddItem("disable", "Vote to disable current voted loadout");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Loadout(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "disable")) {
			if (CanStartDisableVote(client))
				ShowDisableVoteConfirmation(client);
		} else if (!CanEditSelection(client))
			return 0;
		else if (StrEqual(info, "start"))
			StartWeaponVote(client);
		else
			ShowWeaponChoiceMenu(client, info[5] - '0');
	} else if (action == MenuAction_End)
		delete menu;

	return 0;
}

void ShowDisableVoteConfirmation(int client) {
	Menu menu = new Menu(MenuHandler_DisableVoteConfirmation);
	menu.SetTitle("Start a vote to disable the current loadout?");
	menu.AddItem("confirm", "Yes, start disable vote");
	menu.AddItem("cancel", "No, go back");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_DisableVoteConfirmation(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "confirm") && CanStartDisableVote(client))
			StartDisableWeaponVote(client);
		else if (StrEqual(info, "cancel") && IsEligibleVoter(client))
			ShowLoadoutMenu(client);
	} else if (action == MenuAction_End)
		delete menu;

	return 0;
}

void ShowWeaponChoiceMenu(int client, int slot) {
	Menu menu = new Menu(MenuHandler_ChooseWeapon);
	menu.SetTitle("Select %s weapon", slot == WeaponSlot_Primary ? "primary" : "secondary");

	char info[MAX_WEAPON_CLASSNAME + 8];
	char weaponClass[MAX_WEAPON_CLASSNAME];
	char weaponName[MAX_WEAPON_DISPLAY_NAME];
	int found;
	for (int index = 0; index < g_aWeaponClasses.Length; index++) {
		if ((g_aWeaponSlots.Get(index) & (1 << slot)) == 0)
			continue;

		g_aWeaponClasses.GetString(index, weaponClass, sizeof(weaponClass));
		g_aWeaponNames.GetString(index, weaponName, sizeof(weaponName));
		Format(info, sizeof(info), "%d:%s", slot, weaponClass);
		menu.AddItem(info, weaponName);
		found++;
	}

	if (found == 0) {
		delete menu;
		PrintToChat(client, "\x04[Weapon Vote]\x01 No %s weapons are configured.", slot == WeaponSlot_Primary ? "primary" : "secondary");
		ShowLoadoutMenu(client);
		return;
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ChooseWeapon(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		if (!CanEditSelection(client))
			return 0;

		char info[MAX_WEAPON_CLASSNAME + 8];
		menu.GetItem(item, info, sizeof(info));
		int slot = info[0] - '0';
		int index = g_aWeaponClasses.FindString(info[2]);
		if (index != -1) {
			SelectWeapon(client, slot, index);
			ShowUpgradeMenu(client, slot);
		}
	} else if (action == MenuAction_Cancel) {
		if (item == MenuCancel_ExitBack && IsEligibleVoter(client))
			ShowLoadoutMenu(client);
	} else if (action == MenuAction_End)
		delete menu;

	return 0;
}

void ShowUpgradeMenu(int client, int slot, int firstItem = 0) {
	KeyValues config = OpenWeaponConfig();
	if (config == null)
		return;

	Menu menu = new Menu(MenuHandler_Upgrades);
	menu.SetTitle("%s upgrades: %s", slot == WeaponSlot_Primary ? "Primary" : "Secondary", ga_sSelectedWeaponNames[client][slot]);
	char info[48];
	char display[128];
	char upgradeName[MAX_WEAPON_DISPLAY_NAME];
	bool found;
	int rawEntryCount;
	int recognisedEntryCount;
	for (int category = 0; category < UpgradeCategory_Count; category++) {
		bool hasCategory;
		if (config.JumpToKey(ga_sSelectedWeapons[client][slot]) && config.JumpToKey("upgrades") && config.GotoFirstSubKey()) {
			do {
				rawEntryCount++;
				char categoryName[32];
				config.GetString("category", categoryName, sizeof(categoryName));
				if (GetUpgradeCategory(categoryName) != category)
					continue;

				int upgrade = config.GetNum("id", -1);
				if (upgrade < 1)
					continue;

				recognisedEntryCount++;

				if (!hasCategory) {
					char categoryLabel[32];
					GetUpgradeCategoryName(category, categoryLabel, sizeof(categoryLabel));
					Format(display, sizeof(display), "%s:", categoryLabel);
					menu.AddItem("header", display, ITEMDRAW_DISABLED);
					hasCategory = true;
				}

				config.GetString("name", upgradeName, sizeof(upgradeName), "Unnamed upgrade");
				Format(info, sizeof(info), "%d:%d:%d", slot, category, upgrade);
				Format(display, sizeof(display), "%s%s", ga_iSelectedUpgrades[client][slot][category] == upgrade ? "[x] " : "[ ] ", upgradeName);
				menu.AddItem(info, display);
				found = true;
			} while (config.GotoNextKey());
		}

		config.Rewind();
	}

	delete config;
	if (!found) {
		PrintToChat(client, "\x04[Weapon Vote]\x01 No valid upgrades read for %s. Raw entries: %d, recognised entries: %d.", ga_sSelectedWeaponNames[client][slot], rawEntryCount / UpgradeCategory_Count, recognisedEntryCount);
		LogMessage("[Weapon Vote] Upgrade lookup for %s: raw entries %d, recognised entries %d.", ga_sSelectedWeapons[client][slot], rawEntryCount / UpgradeCategory_Count, recognisedEntryCount);
		ShowLoadoutMenu(client);
		return;
	}

	menu.AddItem("main", "Finish upgrades / Back to loadout menu");
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int MenuHandler_Upgrades(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		if (!CanEditSelection(client))
			return 0;

		int firstItem = GetMenuSelectionPosition();
		char info[48];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "main"))
			ShowLoadoutMenu(client);
		else {
			char fields[3][16];
			if (ExplodeString(info, ":", fields, sizeof(fields), sizeof(fields[])) != 3)
				return 0;

			int slot = StringToInt(fields[0]);
			int category = StringToInt(fields[1]);
			int upgrade = StringToInt(fields[2]);
			ga_iSelectedUpgrades[client][slot][category] = ga_iSelectedUpgrades[client][slot][category] == upgrade ? -1 : upgrade;
			ShowUpgradeMenu(client, slot, firstItem);
		}
	} else if (action == MenuAction_Cancel) {
		if (item == MenuCancel_ExitBack && IsEligibleVoter(client))
			ShowLoadoutMenu(client);
	} else if (action == MenuAction_End)
		delete menu;

	return 0;
}

void StartWeaponVote(int client) {
	CopyClientSelectionToPending(client);
	g_iVotesYes = 0;
	g_iVotesNo = 0;
	g_bDisableVote = false;
	g_bVoteRunning = true;
	g_fNextVoteAt = GetGameTime() + g_cvCooldown.FloatValue;

	for (int target = 1; target <= MaxClients; target++)
		g_bClientVoted[target] = false;

	Menu menu = new Menu(MenuHandler_WeaponVote, MenuAction_Select | MenuAction_VoteEnd | MenuAction_VoteCancel | MenuAction_End);
	char loadout[160];
	BuildLoadoutDescription(g_sPendingWeaponNames[WeaponSlot_Primary], g_sPendingWeaponNames[WeaponSlot_Secondary], loadout, sizeof(loadout));
	menu.SetTitle("Use this loadout?\n%s", loadout);
	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");
	menu.ExitButton = false;
	VoteMenuToAll(menu, g_cvVoteTime.IntValue);

	PrintToChatAll("\x04[Weapon Vote]\x01 %N started a vote for %s.", client, loadout);
	char starter[128];
	GetVoteStarterIdentity(client, starter, sizeof(starter));
	LogWeaponVote("%s started a loadout vote for %s.", starter, loadout);
	PlayVoteSound(SOUND_VOTE_START);
}

void StartDisableWeaponVote(int client) {
	g_iVotesYes = 0;
	g_iVotesNo = 0;
	g_bDisableVote = true;
	g_bVoteRunning = true;
	g_fNextVoteAt = GetGameTime() + g_cvCooldown.FloatValue;

	for (int target = 1; target <= MaxClients; target++)
		g_bClientVoted[target] = false;

	Menu menu = new Menu(MenuHandler_WeaponVote, MenuAction_Select | MenuAction_VoteEnd | MenuAction_VoteCancel | MenuAction_End);
	char loadout[160];
	BuildLoadoutDescription(g_sActiveWeaponNames[WeaponSlot_Primary], g_sActiveWeaponNames[WeaponSlot_Secondary], loadout, sizeof(loadout));
	menu.SetTitle("Disable this loadout?\n%s", loadout);
	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");
	menu.ExitButton = false;
	VoteMenuToAll(menu, g_cvVoteTime.IntValue);

	PrintToChatAll("\x04[Weapon Vote]\x01 %N started a vote to disable %s.", client, loadout);
	char starter[128];
	GetVoteStarterIdentity(client, starter, sizeof(starter));
	LogWeaponVote("%s started a disable vote for %s.", starter, loadout);
	PlayVoteSound(SOUND_VOTE_START);
}

public int MenuHandler_WeaponVote(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		if (client < 1 || client > MaxClients || g_bClientVoted[client])
			return 0;

		g_bClientVoted[client] = true;

		char choice[8];
		menu.GetItem(item, choice, sizeof(choice));
		if (StrEqual(choice, "yes"))
			g_iVotesYes++;
		else
			g_iVotesNo++;
	} else if (action == MenuAction_VoteEnd) {
		int votesCast = g_iVotesYes + g_iVotesNo;
		int requiredYes = RoundToCeil(float(votesCast) * g_cvRequiredRatio.FloatValue);
		bool passed = votesCast >= g_cvMinVoters.IntValue && g_iVotesYes >= requiredYes;
		g_bVoteRunning = false;
		char loadout[160];
		if (g_bDisableVote)
			BuildLoadoutDescription(g_sActiveWeaponNames[WeaponSlot_Primary], g_sActiveWeaponNames[WeaponSlot_Secondary], loadout, sizeof(loadout));
		else
			BuildLoadoutDescription(g_sPendingWeaponNames[WeaponSlot_Primary], g_sPendingWeaponNames[WeaponSlot_Secondary], loadout, sizeof(loadout));

		if (passed) {
			if (g_bDisableVote) {
				EndWeaponMode();
				PrintToChatAll("\x04[Weapon Vote]\x01 Disable vote passed: %d Yes, %d No. Needed %d Yes from %d votes. Weapon loadout restriction ended.", g_iVotesYes, g_iVotesNo, requiredYes, votesCast);
				LogWeaponVote("Disable vote passed for %s: %d yes, %d no. Needed %d yes from %d votes.", loadout, g_iVotesYes, g_iVotesNo, requiredYes, votesCast);
				PlayVoteSound(SOUND_VOTE_PASSED);
			} else {
				LogWeaponVote("Loadout vote passed for %s: %d yes, %d no. Needed %d yes from %d votes.", loadout, g_iVotesYes, g_iVotesNo, requiredYes, votesCast);
				EnableWeaponMode(votesCast, requiredYes);
			}
		} else {
			if (votesCast < g_cvMinVoters.IntValue)
				PrintToChatAll("\x04[Weapon Vote]\x01 %s vote failed: only %d/%d votes were cast (%d Yes, %d No).", g_bDisableVote ? "Disable" : "Loadout", votesCast, g_cvMinVoters.IntValue, g_iVotesYes, g_iVotesNo);
			else
				PrintToChatAll("\x04[Weapon Vote]\x01 %s vote failed: %d Yes, %d No. Needed %d Yes from %d votes.", g_bDisableVote ? "Disable" : "Loadout", g_iVotesYes, g_iVotesNo, requiredYes, votesCast);

			LogWeaponVote("%s vote failed for %s: %d yes, %d no. Needed %d yes from %d votes; minimum voters %d.", g_bDisableVote ? "Disable" : "Loadout", loadout, g_iVotesYes, g_iVotesNo, requiredYes, votesCast, g_cvMinVoters.IntValue);
			PlayVoteSound(SOUND_VOTE_FAILED);
		}
		g_bDisableVote = false;
	} else if (action == MenuAction_VoteCancel) {
		g_bVoteRunning = false;
		g_bDisableVote = false;
		PrintToChatAll("\x04[Weapon Vote]\x01 Vote cancelled.");
		LogWeaponVote("Weapon vote cancelled.");
	} else if (action == MenuAction_End)
		delete menu;

	return 0;
}

void EnableWeaponMode(int votesCast, int requiredYes) {
	g_bModeActive = true;
	CopyPendingLoadoutToActive();
	g_iRoundsRemaining = g_cvRounds.IntValue;

	char loadout[160];
	BuildLoadoutDescription(g_sActiveWeaponNames[WeaponSlot_Primary], g_sActiveWeaponNames[WeaponSlot_Secondary], loadout, sizeof(loadout));
	PrintToChatAll("\x04[Weapon Vote]\x01 Loadout vote passed: %d Yes, %d No. Needed %d Yes from %d votes. Loadout: %s.", g_iVotesYes, g_iVotesNo, requiredYes, votesCast, loadout);
	PlayVoteSound(SOUND_VOTE_PASSED);
	LogMessage("[Weapon Vote] Enabled %s for %d round(s).", loadout, g_iRoundsRemaining);

	for (int client = 1; client <= MaxClients; client++)
		if (IsEligibleVoter(client) && IsPlayerAlive(client))
			RequestFrame(Frame_ApplyWeaponMode, GetClientUserId(client));
}

void EndWeaponMode() {
	char loadout[160];
	BuildLoadoutDescription(g_sActiveWeaponNames[WeaponSlot_Primary], g_sActiveWeaponNames[WeaponSlot_Secondary], loadout, sizeof(loadout));
	LogMessage("[Weapon Vote] Ended %s.", loadout);
	g_bModeActive = false;
	g_iRoundsRemaining = 0;
	ResetActiveLoadout();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bModeActive)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsEligibleVoter(client))
		RequestFrame(Frame_ApplyWeaponMode, GetClientUserId(client));
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bModeActive || g_iRoundsRemaining == 0)
		return;

	g_iRoundsRemaining--;
	if (g_iRoundsRemaining == 0) {
		PrintToChatAll("\x04[Weapon Vote]\x01 Weapon loadout mode ended.");
		EndWeaponMode();
	}
}

public MRESReturn Detour_PlayerResupply_Post(int client, DHookReturn hReturn, DHookParam hParams) {
	if (!g_bModeActive || !hReturn.Value || !IsEligibleVoter(client) || !IsPlayerAlive(client))
		return MRES_Ignored;

	// Native resupply has already cleared direct-granted weapons by this point.
	RequestFrame(Frame_GiveWeaponModeAndEquipPrimary, GetClientUserId(client));
	return MRES_Ignored;
}

void Frame_ApplyWeaponMode(any data) {
	int client = GetClientOfUserId(data);
	if (!g_bModeActive || !IsEligibleVoter(client) || !IsPlayerAlive(client))
		return;

	RemovePlayerPrimaryAndSecondary(client);
	RequestFrame(Frame_GiveWeaponModeAndEquipPrimary, GetClientUserId(client));
}

void Frame_GiveWeaponMode(any data) {
	int client = GetClientOfUserId(data);
	if (!g_bModeActive || !IsEligibleVoter(client) || !IsPlayerAlive(client))
		return;

	GiveWeaponModeToPlayer(client, false);
}

void Frame_GiveWeaponModeAndEquipPrimary(any data) {
	int client = GetClientOfUserId(data);
	if (!g_bModeActive || !IsEligibleVoter(client) || !IsPlayerAlive(client))
		return;

	GiveWeaponModeToPlayer(client, true);
}

void GiveWeaponModeToPlayer(int client, bool equipPrimary) {
	int primaryWeapon = -1;
	int suppliedAmmoTypes[WeaponSlot_Count];
	int suppliedAmmoCount;
	for (int slot = 0; slot < WeaponSlot_Count; slot++) {
		if (g_iActiveWeaponDefinitions[slot] < 1)
			continue;

		int weapon = GivePlayerItem(client, g_sActiveWeapons[slot]);
		if (weapon <= MaxClients || !IsValidEntity(weapon)) {
			LogError("[Weapon Vote] Failed to give %s to %N. Check the configured classname and loaded theater.", g_sActiveWeapons[slot], client);
			continue;
		}

		InstallSelectedUpgrades(client, weapon, slot);
		int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
		int magazineCapacity = GetEntProp(weapon, Prop_Send, "m_iClip1");
		if (ammoType >= 0 && magazineCapacity > 0 && !HasSuppliedAmmoType(ammoType, suppliedAmmoTypes, suppliedAmmoCount)) {
			int reloadCount = g_cvReserveAmmo.IntValue;
			if (reloadCount > 0) {
				int magazinesBefore = SDKCall(g_hGetMagazines, client, ammoType);
				SDKCall(g_hGiveAmmo, client, magazineCapacity, ammoType, reloadCount, true, -1);
				int magazinesAfter = SDKCall(g_hGetMagazines, client, ammoType);
				if (reloadCount > 1 && magazinesAfter <= magazinesBefore)
					SDKCall(g_hGiveAmmo, client, magazineCapacity * (reloadCount - 1), ammoType, 0, true, -1);
			}
			suppliedAmmoTypes[suppliedAmmoCount++] = ammoType;
		}

		if (slot == WeaponSlot_Primary)
			primaryWeapon = weapon;
	}

	if (equipPrimary && primaryWeapon > MaxClients && IsValidEntity(primaryWeapon))
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", primaryWeapon);
}

bool HasSuppliedAmmoType(int ammoType, int[] suppliedAmmoTypes, int suppliedAmmoCount) {
	for (int index = 0; index < suppliedAmmoCount; index++)
		if (suppliedAmmoTypes[index] == ammoType)
			return true;

	return false;
}

void RemovePlayerPrimaryAndSecondary(int client) {
	DestroyCarriedRestrictedWeapons(client);

	Address inventory = GetEntityAddress(client) + view_as<Address>(g_iPlayerInventoryOffset);
	Address purchases = view_as<Address>(LoadFromAddress(inventory + view_as<Address>(PURCHASES_OFFSET), NumberType_Int32));
	int purchaseCount = LoadFromAddress(inventory + view_as<Address>(PURCHASE_COUNT_OFFSET), NumberType_Int32);
	if (purchases == Address_Null || purchaseCount < 1 || purchaseCount > MAX_NATIVE_PURCHASES)
		return;

	for (int index = purchaseCount - 1; index >= 0; index--) {
		Address purchase = purchases + view_as<Address>(index * PURCHASE_SIZE);
		int slot = LoadFromAddress(purchase + view_as<Address>(PURCHASE_SLOT_OFFSET), NumberType_Int32);
		if (slot == WeaponSlot_Primary || slot == WeaponSlot_Secondary)
			SDKCall(g_hRefundWeapon, inventory, index);
	}
}

void DestroyCarriedRestrictedWeapons(int client) {
	int weaponRefs[MAX_PLAYER_WEAPONS];
	int weaponCount;

	for (int offset = 0; offset < MAX_PLAYER_WEAPONS * 4; offset += 4) {
		int weapon = GetEntDataEnt2(client, g_iMyWeaponsOffset + offset);
		if (weapon <= MaxClients || !IsValidEntity(weapon))
			continue;

		char weaponClass[MAX_WEAPON_CLASSNAME];
		GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));
		if (IsAllowedUtilityWeapon(weaponClass))
			continue;

		int weaponRef = EntIndexToEntRef(weapon);
		bool found;
		for (int index = 0; index < weaponCount; index++)
			if (weaponRefs[index] == weaponRef) {
				found = true;
				break;
			}

		if (!found)
			weaponRefs[weaponCount++] = weaponRef;
	}

	for (int index = 0; index < weaponCount; index++) {
		int weapon = EntRefToEntIndex(weaponRefs[index]);
		if (weapon > MaxClients && IsValidEntity(weapon))
			SDKCall(g_hDestroyItem, weapon);
	}
}

public Action CommandListener_BuyWeapon(int client, const char[] command, int argc) {
	if (!g_bModeActive || !IsEligibleVoter(client))
		return Plugin_Continue;

	// The command provides a definition ID but not its inventory slot. Let the
	// engine add the purchase, then remove it only if it is primary or secondary.
	RequestFrame(Frame_EnforceVotedWeaponSlots, GetClientUserId(client));
	return Plugin_Continue;
}

void Frame_EnforceVotedWeaponSlots(any data) {
	int client = GetClientOfUserId(data);
	if (!g_bModeActive || !IsEligibleVoter(client) || !HasNativePrimaryOrSecondaryPurchase(client))
		return;

	RemovePlayerPrimaryAndSecondary(client);
	RequestFrame(Frame_GiveWeaponMode, GetClientUserId(client));
	PrintToChat(client, "\x04[Weapon Vote]\x01 Primary and secondary weapon purchases are disabled while the voted loadout is active.");
}

bool HasNativePrimaryOrSecondaryPurchase(int client) {
	Address inventory = GetEntityAddress(client) + view_as<Address>(g_iPlayerInventoryOffset);
	Address purchases = view_as<Address>(LoadFromAddress(inventory + view_as<Address>(PURCHASES_OFFSET), NumberType_Int32));
	int purchaseCount = LoadFromAddress(inventory + view_as<Address>(PURCHASE_COUNT_OFFSET), NumberType_Int32);
	if (purchases == Address_Null || purchaseCount < 1 || purchaseCount > MAX_NATIVE_PURCHASES)
		return false;

	for (int index = 0; index < purchaseCount; index++) {
		Address purchase = purchases + view_as<Address>(index * PURCHASE_SIZE);
		int slot = LoadFromAddress(purchase + view_as<Address>(PURCHASE_SLOT_OFFSET), NumberType_Int32);
		if (slot == WeaponSlot_Primary || slot == WeaponSlot_Secondary)
			return true;
	}

	return false;
}

public Action Hook_WeaponEquip(int client, int weapon) {
	if (!g_bModeActive || !IsEligibleVoter(client) || weapon <= MaxClients || !IsValidEntity(weapon))
		return Plugin_Continue;

	char weaponClass[MAX_WEAPON_CLASSNAME];
	GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));
	if (StrEqual(weaponClass, g_sActiveWeapons[WeaponSlot_Primary])
		|| StrEqual(weaponClass, g_sActiveWeapons[WeaponSlot_Secondary])
		|| IsAllowedUtilityWeapon(weaponClass))
		return Plugin_Continue;

	RequestFrame(Frame_DropRestrictedWeapon, EntIndexToEntRef(weapon));
	return Plugin_Continue;
}

void Frame_DropRestrictedWeapon(any data) {
	int weapon = EntRefToEntIndex(data);
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return;

	int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	if (!g_bModeActive || !IsEligibleVoter(client))
		return;

	char weaponClass[MAX_WEAPON_CLASSNAME];
	GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));
	if (StrEqual(weaponClass, g_sActiveWeapons[WeaponSlot_Primary])
		|| StrEqual(weaponClass, g_sActiveWeapons[WeaponSlot_Secondary])
		|| IsAllowedUtilityWeapon(weaponClass))
		return;

	SDKHooks_DropWeapon(client, weapon, NULL_VECTOR, NULL_VECTOR);
	RequestFrame(Frame_ReselectVotedWeapon, GetClientUserId(client));
}

void Frame_ReselectVotedWeapon(any data) {
	int client = GetClientOfUserId(data);
	if (!g_bModeActive || !IsEligibleVoter(client) || !IsPlayerAlive(client))
		return;

	int weapon = FindCarriedVotedWeapon(client, WeaponSlot_Primary);
	if (weapon == -1)
		weapon = FindCarriedVotedWeapon(client, WeaponSlot_Secondary);
	if (weapon != -1)
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
}

int FindCarriedVotedWeapon(int client, int slot) {
	for (int offset = 0; offset < MAX_PLAYER_WEAPONS * 4; offset += 4) {
		int weapon = GetEntDataEnt2(client, g_iMyWeaponsOffset + offset);
		if (weapon <= MaxClients || !IsValidEntity(weapon))
			continue;

		char weaponClass[MAX_WEAPON_CLASSNAME];
		GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));
		if (StrEqual(weaponClass, g_sActiveWeapons[slot]))
			return weapon;
	}

	return -1;
}

bool IsAllowedUtilityWeapon(const char[] weaponClass) {
	return StrEqual(weaponClass, "weapon_kabar")
		|| StrEqual(weaponClass, "weapon_gurkha")
		|| StrEqual(weaponClass, "weapon_knife")
		|| StrEqual(weaponClass, "weapon_kukri")
		|| StrEqual(weaponClass, "weapon_katana")
		|| StrEqual(weaponClass, "weapon_defib")
		|| StrEqual(weaponClass, "weapon_healthkit")
		|| StrEqual(weaponClass, "weapon_m67")
		|| StrEqual(weaponClass, "weapon_m26a2")
		|| StrEqual(weaponClass, "weapon_f1")
		|| StrEqual(weaponClass, "weapon_anm14")
		|| StrEqual(weaponClass, "weapon_m18")
		|| StrEqual(weaponClass, "weapon_m84")
		|| StrEqual(weaponClass, "weapon_molotov")
		|| StrEqual(weaponClass, "weapon_rpg7")
		|| StrEqual(weaponClass, "weapon_at4")
		|| StrEqual(weaponClass, "weapon_rifle_grenade")
		|| StrEqual(weaponClass, "weapon_m203_he")
		|| StrEqual(weaponClass, "weapon_m203_incid")
		|| StrEqual(weaponClass, "weapon_m203_smoke")
		|| StrEqual(weaponClass, "weapon_gp25_he")
		|| StrEqual(weaponClass, "weapon_gp25_smoke")
		|| StrEqual(weaponClass, "weapon_c4_clicker")
		|| StrEqual(weaponClass, "weapon_c4_tripmine")
		|| StrEqual(weaponClass, "weapon_c4_ied");
}

bool IsEligibleVoter(int client) {
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) > 1;
}

void LoadWeaponConfig() {
	g_aWeaponClasses.Clear();
	g_aWeaponNames.Clear();
	g_aWeaponDefinitions.Clear();
	g_aWeaponSlots.Clear();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), CONFIG_FILE);

	KeyValues config = new KeyValues("WeaponVoteWeapons");
	if (!config.ImportFromFile(path)) {
		delete config;
		SetFailState("[Weapon Vote] Missing %s", path);
	}

	if (config.GotoFirstSubKey()) {
		do {
			char weaponClass[MAX_WEAPON_CLASSNAME];
			char weaponName[MAX_WEAPON_DISPLAY_NAME];
			char slotName[16];
			config.GetSectionName(weaponClass, sizeof(weaponClass));
			config.GetString("name", weaponName, sizeof(weaponName), weaponClass);
			config.GetString("slot", slotName, sizeof(slotName), "both");
			int weaponDefinition = config.GetNum("definition", -1);

			if (StrContains(weaponClass, "weapon_", false) != 0 || weaponDefinition < 1) {
				LogError("[Weapon Vote] Ignoring '%s': each entry needs a valid classname and positive definition ID.", weaponClass);
				continue;
			}

			g_aWeaponClasses.PushString(weaponClass);
			g_aWeaponNames.PushString(weaponName);
			g_aWeaponDefinitions.Push(weaponDefinition);
			g_aWeaponSlots.Push(GetWeaponSlotMask(slotName));
		} while (config.GotoNextKey());
	}

	delete config;

	if (g_aWeaponClasses.Length == 0)
		SetFailState("[Weapon Vote] %s contains no weapon entries.", path);
}

void ResetClientSelection(int client) {
	if (client < 1 || client > MaxClients)
		return;

	for (int slot = 0; slot < WeaponSlot_Count; slot++) {
		ga_sSelectedWeapons[client][slot][0] = '\0';
		ga_sSelectedWeaponNames[client][slot][0] = '\0';
		ga_iSelectedWeaponDefinitions[client][slot] = 0;
		for (int category = 0; category < UpgradeCategory_Count; category++)
			ga_iSelectedUpgrades[client][slot][category] = -1;
	}
}

void ResetPendingLoadout() {
	for (int slot = 0; slot < WeaponSlot_Count; slot++) {
		g_sPendingWeapons[slot][0] = '\0';
		g_sPendingWeaponNames[slot][0] = '\0';
		g_iPendingWeaponDefinitions[slot] = 0;
		for (int category = 0; category < UpgradeCategory_Count; category++)
			g_iPendingUpgrades[slot][category] = -1;
	}
}

void ResetActiveLoadout() {
	for (int slot = 0; slot < WeaponSlot_Count; slot++) {
		g_sActiveWeapons[slot][0] = '\0';
		g_sActiveWeaponNames[slot][0] = '\0';
		g_iActiveWeaponDefinitions[slot] = 0;
		for (int category = 0; category < UpgradeCategory_Count; category++)
			g_iActiveUpgrades[slot][category] = -1;
	}
}

bool HasSelectedWeapon(int client, int slot) {
	return ga_iSelectedWeaponDefinitions[client][slot] > 0;
}

bool CanEditSelection(int client) {
	return IsEligibleVoter(client) && GetGameTime() >= g_fVoteEnableAt && (!g_bModeActive || g_cvAllowRevote.BoolValue) && !g_bVoteRunning && !IsVoteInProgress() && GetGameTime() >= g_fNextVoteAt;
}

bool CanStartDisableVote(int client) {
	return IsEligibleVoter(client) && g_bModeActive && !g_bVoteRunning && !IsVoteInProgress() && GetGameTime() >= g_fNextVoteAt;
}

void SelectWeapon(int client, int slot, int index) {
	g_aWeaponClasses.GetString(index, ga_sSelectedWeapons[client][slot], sizeof(ga_sSelectedWeapons[][]));
	g_aWeaponNames.GetString(index, ga_sSelectedWeaponNames[client][slot], sizeof(ga_sSelectedWeaponNames[][]));
	ga_iSelectedWeaponDefinitions[client][slot] = g_aWeaponDefinitions.Get(index);
	for (int category = 0; category < UpgradeCategory_Count; category++)
		ga_iSelectedUpgrades[client][slot][category] = -1;
}

void CopyClientSelectionToPending(int client) {
	for (int slot = 0; slot < WeaponSlot_Count; slot++) {
		strcopy(g_sPendingWeapons[slot], sizeof(g_sPendingWeapons[]), ga_sSelectedWeapons[client][slot]);
		strcopy(g_sPendingWeaponNames[slot], sizeof(g_sPendingWeaponNames[]), ga_sSelectedWeaponNames[client][slot]);
		g_iPendingWeaponDefinitions[slot] = ga_iSelectedWeaponDefinitions[client][slot];
		for (int category = 0; category < UpgradeCategory_Count; category++)
			g_iPendingUpgrades[slot][category] = ga_iSelectedUpgrades[client][slot][category];
	}
}

void CopyPendingLoadoutToActive() {
	for (int slot = 0; slot < WeaponSlot_Count; slot++) {
		strcopy(g_sActiveWeapons[slot], sizeof(g_sActiveWeapons[]), g_sPendingWeapons[slot]);
		strcopy(g_sActiveWeaponNames[slot], sizeof(g_sActiveWeaponNames[]), g_sPendingWeaponNames[slot]);
		g_iActiveWeaponDefinitions[slot] = g_iPendingWeaponDefinitions[slot];
		for (int category = 0; category < UpgradeCategory_Count; category++)
			g_iActiveUpgrades[slot][category] = g_iPendingUpgrades[slot][category];
	}
}

void InstallSelectedUpgrades(int client, int weapon, int slot) {
	for (int category = 0; category < UpgradeCategory_Count; category++) {
		int upgrade = g_iActiveUpgrades[slot][category];
		if (upgrade < 1)
			continue;

		if (!SDKCall(g_hInstallWeaponUpgrade, weapon, upgrade, true))
			LogError("[Weapon Vote] Failed to install upgrade %d on %s for %N.", upgrade, g_sActiveWeapons[slot], client);
	}
}

void BuildLoadoutDescription(const char[] primary, const char[] secondary, char[] buffer, int maxLength) {
	if (secondary[0] == '\0') {
		strcopy(buffer, maxLength, primary);
		return;
	}

	Format(buffer, maxLength, "%s + %s", primary, secondary);
}

void LogWeaponVote(const char[] format, any ...) {
	char directory[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, directory, sizeof(directory), LOG_DIRECTORY);
	if (!DirExists(directory))
		CreateDirectory(directory, 511);

	char date[16];
	FormatTime(date, sizeof(date), "%Y%m%d");
	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof(path), "%s/weapon_vote_%s.log", directory, date);

	char message[512];
	VFormat(message, sizeof(message), format, 2);
	LogToFileEx(path, "%s", message);
}

void GetVoteStarterIdentity(int client, char[] buffer, int maxLength) {
	char name[MAX_NAME_LENGTH];
	char steamId[32];
	GetClientName(client, name, sizeof(name));
	if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true))
		strcopy(steamId, sizeof(steamId), "STEAM_ID_PENDING");

	Format(buffer, maxLength, "%s <%s>", name, steamId);
}

KeyValues OpenWeaponConfig() {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), CONFIG_FILE);
	KeyValues config = new KeyValues("WeaponVoteWeapons");
	if (config.ImportFromFile(path))
		return config;

	delete config;
	LogError("[Weapon Vote] Missing %s", path);
	return null;
}

int GetUpgradeCategory(const char[] categoryName) {
	if (StrEqual(categoryName, "ammo", false)) return UpgradeCategory_Ammo;
	if (StrEqual(categoryName, "scope", false)) return UpgradeCategory_Scope;
	if (StrEqual(categoryName, "barrel", false)) return UpgradeCategory_Barrel;
	if (StrEqual(categoryName, "aesthetic", false)) return UpgradeCategory_Aesthetic;
	if (StrEqual(categoryName, "siderail", false)) return UpgradeCategory_Siderail;
	if (StrEqual(categoryName, "underbarrel", false)) return UpgradeCategory_Underbarrel;
	if (StrEqual(categoryName, "magazine", false)) return UpgradeCategory_Magazine;
	if (StrEqual(categoryName, "stock", false)) return UpgradeCategory_Stock;
	return -1;
}

int GetWeaponSlotMask(const char[] slotName) {
	if (StrEqual(slotName, "primary", false)) return 1 << WeaponSlot_Primary;
	if (StrEqual(slotName, "secondary", false)) return 1 << WeaponSlot_Secondary;
	return (1 << WeaponSlot_Primary) | (1 << WeaponSlot_Secondary);
}

void GetUpgradeCategoryName(int category, char[] buffer, int maxLength) {
	switch (category) {
		case UpgradeCategory_Ammo: strcopy(buffer, maxLength, "Ammo");
		case UpgradeCategory_Scope: strcopy(buffer, maxLength, "Scope");
		case UpgradeCategory_Barrel: strcopy(buffer, maxLength, "Barrel");
		case UpgradeCategory_Aesthetic: strcopy(buffer, maxLength, "Aesthetic");
		case UpgradeCategory_Siderail: strcopy(buffer, maxLength, "Siderail");
		case UpgradeCategory_Underbarrel: strcopy(buffer, maxLength, "Underbarrel");
		case UpgradeCategory_Magazine: strcopy(buffer, maxLength, "Magazine");
		case UpgradeCategory_Stock: strcopy(buffer, maxLength, "Stock");
		default: strcopy(buffer, maxLength, "Unknown");
	}
}
