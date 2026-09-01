#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <dbi>

#define PL_VERSION		"3.45"
#define RESUPPLY_GAMEDATA_FILE "insurgency-bm.games"
// Optional MySQL entry in databases.cfg. Local SQLite is used when it is not configured.
#define BLUEPRINT_DATABASE_CONFIG "props_blueprints"

#define MAXENTITIES		2048

#define MAX_BUTTONS         30
#define BTN_ATTACK1         (1 << 0)
#define BTN_JUMP            (1 << 1)
#define BTN_DUCK            (1 << 2)
#define BTN_PRONE           (1 << 3)
#define BTN_FORWARD         (1 << 4)
#define BTN_BACKWARD        (1 << 5)
#define BTN_USE             (1 << 6)
#define BTN_LEFT            (1 << 9)
#define BTN_RIGHT           (1 << 10)
#define BTN_RELOAD          (1 << 11)
#define BTN_FIREMODE        (1 << 12)
#define BTN_LEAN_LEFT       (1 << 13)
#define BTN_LEAN_RIGHT      (1 << 14)
#define BTN_SPRINT          (1 << 15)
#define BTN_WALK            (1 << 16)
#define BTN_SPECIAL1        (1 << 17)
#define BTN_AIM             (1 << 18)
#define BTN_SCOREBOARD      (1 << 19)
#define BTN_FLASHLIGHT      (1 << 22)
#define BTN_DUCK_TOGGLE     (1 << 24)
#define BTN_SPRINT_TOGGLE   (1 << 26)
#define BTN_AIM_TOGGLE      (1 << 27)
#define BTN_ACCESSORY       (1 << 28)
#define BTN_STANCE_TOGGLE   (1 << 29)

#define PF_DEPLOY_BIPOD			(1 << 1)
#define PF_WEAPON_RESTRICTED	(1 << 10)

#define DAMAGE_NO					0
#define DAMAGE_EVENTS_ONLY			1
#define DAMAGE_YES					2
#define DAMAGE_AIM					3

#define STARTBUILDPOINTS			3	// Free starting build points for all players

#define PROP_ALPHA					110
#define PROP_PREVIEW_PLACEABLE_R	80
#define PROP_PREVIEW_PLACEABLE_G	255
#define PROP_PREVIEW_PLACEABLE_B	80
#define PROP_PREVIEW_BLOCKED_R		255
#define PROP_PREVIEW_BLOCKED_G		60
#define PROP_PREVIEW_BLOCKED_B		60
#define PROP_ROTATE_STEP			30.0
#define PROP_DAMAGE_TAKE			100.0	// Amount of damage the prop takes each time a bot touches it, limited by PROP_TOUCH_COOLDOWN.
#define PROP_TOUCH_COOLDOWN			0.50
#define SECURITY_DOOR_OPEN_SOUND		"physics/doors/metaldoors/metal_door_01_open.wav"
#define SECURITY_DOOR_CLOSE_SOUND		"physics/doors/metaldoors/metal_door_01_close.wav"
#define SECURITY_DOOR_IMPACT_SOUND	"physics/metal/metalbox_bullet_impact_03.wav"
#define SECURITY_DOOR_MOVE_VOLUME	0.75
#define SECURITY_DOOR_SLIDE_DISTANCE_FALLBACK	96.0
#define SECURITY_DOOR_PLAYER_HULL_RADIUS	24.0
#define SECURITY_DOOR_CLOSE_DELAY		2.0
#define SECURITY_DOOR_CLOSE_RETRY		0.25
#define SECURITY_DOOR_TOUCH_COOLDOWN	0.25
#define SECURITY_DOOR_IMPACT_SOUND_COOLDOWN 3.0
#define PROP_GLOWHP_PERCENT			0.25
#define PROP_HALFHP_PERCENT			0.50
#define PROP_HALFHP_FLASH_TIME		1.00
#define PROP_HEALTH					6000
#define PROP_HOLD_DISTANCE			130.0
#define PROP_LIMIT					10		// Prop limit per player
#define PROP_PLAYER_DISTANCE		50.0
#define PROP_PICKUP_DISTANCE		170.0
#define PROP_SELECTION_RADIUS_DEFAULT	250.0
#define PROP_SELECTION_MAX_DEFAULT		5
#define PROP_SELECTION_R			70
#define PROP_SELECTION_G			160
#define PROP_SELECTION_B			255
#define PROP_BATCH_DATA_SIZE		10
#define RECENT_PROP_COUNT		5
#define PROP_MENU_NAVIGATION_HINT	"LEAN LEFT: Back | LEAN RIGHT: Next"

#define BLUEPRINT_SLOT_COUNT		5
#define BLUEPRINT_MIN_PROPS		2
#define BLUEPRINT_MAX_PROPS		PROP_SELECTION_MAX_DEFAULT
#define BLUEPRINT_NAME_MAX_CHARS	32
#define BLUEPRINT_NAME_LENGTH		(BLUEPRINT_NAME_MAX_CHARS * 4 + 1)
#define BLUEPRINT_RECORD_LENGTH	512
#define BLUEPRINT_LAYOUT_LENGTH	(BLUEPRINT_RECORD_LENGTH * BLUEPRINT_MAX_PROPS)
#define BLUEPRINT_SAVE_COOLDOWN	1.5
#define BLUEPRINT_LOAD_COOLDOWN	0.5

#define BOT_BLEED_WIREDAMAGE		10.0	// Amount of bleed damage bot takes from a barbed wire

#define MENU_COOLDOWN				1.0
#define MENU_STAYOPENTIME			25

#define SND_SUPPLYREFUND		"ui/receivedsupply.wav"
#define SND_BUYBUILDPOINTS		"ui/menu_click.wav"
#define SND_CANTBUY				"ui/vote_no.wav"

#define AMMO_CACHE_MODEL		"models/sernix/ammo_cache/ammo_cache_small.mdl"
#define AMMO_ICON_SPRITE		"sprites/bm/ammobag.vmt"	// https://steamcommunity.com/sharedfiles/filedetails/?id=1581225279
#define AMMO_ICON_ZOFFSET		38.0

#define TEAM_SPECTATOR	1
#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

static const char JC_Sounds[][] = {
	"soundscape/emitters/oneshot/mil_radio_01.ogg",
	"soundscape/emitters/oneshot/mil_radio_02.ogg",
	"soundscape/emitters/oneshot/mil_radio_03.ogg",
	"soundscape/emitters/oneshot/mil_radio_04.ogg",
	"player/voip_end_transmit_beep_01.wav",
	"player/voip_end_transmit_beep_02.wav",
	"player/voip_end_transmit_beep_03.wav",
	"player/voip_end_transmit_beep_04.wav",
	"player/voip_end_transmit_beep_05.wav",
	"player/voip_end_transmit_beep_06.wav",
	"player/voip_end_transmit_beep_07.wav",
	"player/voip_end_transmit_beep_08.wav"
};

static const float JC_MinDelay = 15.0;
static const float JC_MaxDelay = 25.0;

static const float MATTRESS_FALL_WINDOW = 4.0;					// Seconds after a mattress launch where fall damage can be credited to the mattress owner.
static const float MATTRESS_BASE_BOOST = 700.0;					// Upward velocity from a single mattress.
static const float MATTRESS_STACK_BONUS = 275.0;					// Extra upward velocity added for each mattress contributing to the stack.
static const float MATTRESS_STACK_RADIUS = 75.0;					// Horizontal distance for another mattress to count as part of the stack.
static const float MATTRESS_STACK_Z_RANGE = 160.0;				// Maximum vertical distance for another mattress to count as stacked.
static const float MATTRESS_STACK_MIN_Z_GAP = 12.0;				// Minimum vertical gap; prevents same-height mattresses from counting as stacked.
static const float MATTRESS_AUTO_REBOUNCE_BASE = 1.0;			// Base seconds that auto-rebounce stays armed after a mattress launch.
static const float MATTRESS_AUTO_REBOUNCE_STACK_BONUS = 0.65;	// Extra auto-rebounce time per additional stacked mattress.
static const float MATTRESS_ANGLE_PUSH_FRACTION = 0.40;			// Portion of launch strength converted into sideways push from mattress angle.
static const float MATTRESS_HUMAN_ANGLE_PUSH_SCALE = 1.0;		// Multiplier for sideways angle push applied to human players.
static const float MATTRESS_HORIZONTAL_MAX = 250.0;				// Maximum sideways velocity added by angled mattresses.
static const float MATTRESS_HIGHLIGHT_INTERVAL = 0.25;			// Seconds between stack highlight/text updates while holding a mattress.
static const int MATTRESS_MAX_STACK_COUNT = 5;					// Maximum mattresses counted in one stack, including the mattress being held/touched.

ArrayList	g_hJammers = null;
Handle		g_hJammerTimer = INVALID_HANDLE;

ArrayList	ga_hPropPlaced[MAXPLAYERS + 1];
ConVar		g_cvAllFree = null;

Handle		g_hCookiePropRotateStep = null;
float		ga_fPropRotateStep[MAXPLAYERS + 1] = {PROP_ROTATE_STEP, ...};

Handle		g_hTipTimer = null;

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
	int  health;
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
	Prop_MarketPrisonDoor,

	Prop_Count
};

#define MID(%1) (view_as<int>(%1))

// model, cost, blocks explosive damage?, HP
static const PropDef g_PropDefs[] = {
	{ "models/fortifications/barbed_wire_02b.mdl",			3, false, 4000 },
	{ "models/static_fortifications/sandbagwall01.mdl",		1, true, 5000 },
	{ "models/iraq/ir_twall_01.mdl",						3, true, PROP_HEALTH },
	{ "models/iraq/ir_hesco_basket_01_row.mdl",				4, true, 7000 },
	{ "models/static_afghan/prop_panj_stairs.mdl",			1, false, 2000 },
	{ "models/static_afghan/prop_interior_mattress_a.mdl",	3, false, 2000 },
	{ "models/static_props/container_01_open2.mdl",			6, true, PROP_HEALTH },
	{ "models/embassy/embassy_center_02.mdl",				8, true, 8000 },
	{ "models/sernix/ied_jammer/ied_jammer.mdl",			5, false, 1000 },
	{ AMMO_CACHE_MODEL,										8, false, 1000 },
	{ "models/static_props/prop_market_prison_door.mdl",	2, false,	4000}
};

#define PROP_COUNT (sizeof(g_PropDefs))
PropId ga_iModelIndex[MAXPLAYERS + 1] = {Prop_BarbWire, ...};
int ga_iRecentPropModels[MAXPLAYERS + 1][RECENT_PROP_COUNT];

int		ga_iPropHolding[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iHoldHp[MAXPLAYERS + 1];
int		ga_iHoldMaxHp[MAXPLAYERS + 1];
int		ga_iLastButtons[MAXPLAYERS + 1];

int		g_iOffLaggedMovementValue = -1;
int		ga_iLastInflictor[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iEntIdBipodDeployedOn[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iPlayerBuildPoints[MAXPLAYERS + 1] = {STARTBUILDPOINTS, ...};
int		ga_iPropOwner[MAXPLAYERS + 1] = {0, ...};
int		ga_iTokensSpent[MAXPLAYERS + 1] = {0, ...};
int		g_iAllFree;

int		ga_iLastMattressOwner[MAXPLAYERS + 1];
float	ga_fLastMattressLaunchTime[MAXPLAYERS + 1];
bool	ga_bMattressDeath[MAXPLAYERS + 1];
int		ga_iMattressKiller[MAXPLAYERS + 1];

bool	ga_bHelpMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool	ga_bPropRotateMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool	ga_bRotationMenuVisible[MAXPLAYERS + 1] = {false, ...};
bool	ga_bBuildMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool	ga_bShopMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool	ga_bShopOpenedFromPropMenu[MAXPLAYERS + 1] = {false, ...};
bool	ga_bPropAuxMenuOpen[MAXPLAYERS + 1] = {false, ...};
bool	ga_bPropMenuWeaponLockApplied[MAXPLAYERS + 1] = {false, ...};
bool	ga_bPropMenuWasWeaponRestricted[MAXPLAYERS + 1] = {false, ...};
bool	ga_bHoldingMeleeWeapon[MAXPLAYERS + 1] = {false, ...};
bool	g_bLateLoad;
bool	ga_bBipodForced[MAXPLAYERS + 1] = {false, ...};
bool	ga_bPlayerRefund[MAXPLAYERS + 1] = {false, ...};
bool	ga_bFirstTimeJoinedSquad[MAXPLAYERS + 1] = {true, ...};

bool	ga_bPlacingNow[MAXPLAYERS + 1] = { false, ... };
bool	ga_bPlaceQueued[MAXPLAYERS + 1] = { false, ... };
float	ga_fLastPlaceTime[MAXPLAYERS + 1] = { 0.0, ... };
bool	ga_bJustPlaced[MAXPLAYERS + 1] = { false, ... };
const float gc_fPlaceDebounce = 0.20;
const float gc_fHeldPropTeleportMinDeltaSqr = 1.0;

float	ga_fPropRotations[MAXPLAYERS + 1][PROP_COUNT][3];
float	ga_fLastHeldPreviewPos[MAXPLAYERS + 1][3];
float	ga_fLastTouchTime[MAXPLAYERS + 1] = {0.0, ...};
float	ga_fPressedJumpTime[MAXPLAYERS + 1] = {0.0, ...};
float	ga_fPropMenuCooldown[MAXPLAYERS + 1] = {0.0, ...};
float	ga_fShopMenuCooldown[MAXPLAYERS + 1] = {0.0, ...};
float	ga_fWireSoundCooldown[MAXENTITIES + 1] = {0.0, ...};
float	ga_fSecurityDoorNextTouch[MAXENTITIES + 1] = {0.0, ...};
float	ga_fSecurityDoorImpactSound[MAXENTITIES + 1] = {0.0, ...};
float	ga_fSecurityDoorClosedOrigin[MAXENTITIES + 1][3];
bool	ga_bSecurityDoorOpen[MAXENTITIES + 1] = {false, ...};
Handle	ga_hSecurityDoorCloseTimer[MAXENTITIES + 1] = {INVALID_HANDLE, ...};

float	g_fAmmoResupplyRange;
float	g_fAmmoResupplyRangeSqr;
int		g_iAmmoAmount;
int		g_iResupplyDelay;
bool	g_bAmmoOnce;

int		ga_iResupplyCounter[MAXPLAYERS + 1];
int		ga_iAmmoAmount[MAXENTITIES + 1];
int		ga_iAmmoIconHolderRef[MAXENTITIES + 1];
int		ga_iAmmoIconSpriteRef[MAXENTITIES + 1];
int		ga_iLastInflictorPropId[MAXPLAYERS + 1] = {-1, ...};
bool	ga_bHeldPreviewPosValid[MAXPLAYERS + 1] = {false, ...};
bool	ga_bPickupQueued[MAXPLAYERS + 1] = {false, ...};
bool	ga_bSelectionQueued[MAXPLAYERS + 1] = {false, ...};
bool	ga_bMattressJumpArmed[MAXPLAYERS + 1] = {false, ...};
float	ga_fNextMattressHighlightUpdate[MAXPLAYERS + 1] = {0.0, ...};

int		ga_iTrackedPropOwner[MAXENTITIES + 1];
int		ga_iTrackedPropId[MAXENTITIES + 1];
bool	ga_bPropHalfHpWarned[MAXENTITIES + 1] = {false, ...};

ArrayList g_hAmmoCacheRefs = null;
ArrayList g_hMattressRefs = null;
ArrayList ga_hUsedAmmoCacheRefs[MAXPLAYERS + 1];
ArrayList ga_hHighlightedMattressRefs[MAXPLAYERS + 1];
ArrayList ga_hSelectedPropRefs[MAXPLAYERS + 1];
ArrayList ga_hSelectableFlashRefs[MAXPLAYERS + 1];
ArrayList ga_hBatchMoveData[MAXPLAYERS + 1];
float ga_fBatchLeadAngles[MAXPLAYERS + 1][3];
Handle ga_hSelectableFlashTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
float ga_fNextSelectableFlash[MAXPLAYERS + 1] = {0.0, ...};

Database g_hBlueprintDb = null;
bool g_bBlueprintDbReady = false;
ArrayList ga_hBlueprintProps[MAXPLAYERS + 1][BLUEPRINT_SLOT_COUNT];
char ga_sBlueprintName[MAXPLAYERS + 1][BLUEPRINT_SLOT_COUNT][BLUEPRINT_NAME_LENGTH];
bool ga_bBlueprintsLoaded[MAXPLAYERS + 1] = {false, ...};
bool ga_bBlueprintsLoading[MAXPLAYERS + 1] = {false, ...};
ArrayList ga_hPendingBlueprintProps[MAXPLAYERS + 1];
int ga_iPendingBlueprintSlot[MAXPLAYERS + 1] = {-1, ...};
Handle ga_hPendingBlueprintNameTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
float ga_fNextBlueprintSave[MAXPLAYERS + 1] = {0.0, ...};
float ga_fNextBlueprintLoad[MAXPLAYERS + 1] = {0.0, ...};

bool ga_bHoldingBlueprint[MAXPLAYERS + 1] = {false, ...};
ArrayList ga_hBlueprintHoldData[MAXPLAYERS + 1];
float ga_fBlueprintLeadAngles[MAXPLAYERS + 1][3];

Handle	g_hDirectResupply = null;
int		g_iLastResupplyTimeOffset = -1;
int		g_iResupplyPenaltyTimeOffset = -1;
int		g_iResupplyCountOffset = -1;

ConVar	g_cvAmmoResupplyRange = null;
ConVar	g_cvAmmoAmount = null;
ConVar	g_cvResupplyDelay = null;
ConVar	g_cvAmmoOnce = null;
ConVar	g_cvPropSelectionMax = null;
ConVar	g_cvPropSelectionRadius = null;
int		g_iPropSelectionMax = PROP_SELECTION_MAX_DEFAULT;
float	g_fPropSelectionRadius = PROP_SELECTION_RADIUS_DEFAULT;

public Plugin myinfo = {
	name = "props",
	author = "Nullifidian, Owned|Myself, Linothorax, GPT/Codex",
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
	SetupDirectResupply();
	SetupBlueprintDatabase();

	if (g_hAmmoCacheRefs == null)
		g_hAmmoCacheRefs = new ArrayList();
	if (g_hMattressRefs == null)
		g_hMattressRefs = new ArrayList();
	for (int i = 0; i <= MAXENTITIES; i++) {
		ga_iTrackedPropOwner[i] = 0;
		ga_iTrackedPropId[i] = -1;
		ga_iAmmoAmount[i] = 0;
		ga_iAmmoIconHolderRef[i] = INVALID_ENT_REFERENCE;
		ga_iAmmoIconSpriteRef[i] = INVALID_ENT_REFERENCE;
		ga_bPropHalfHpWarned[i] = false;
		ga_fSecurityDoorNextTouch[i] = 0.0;
		ga_fSecurityDoorImpactSound[i] = 0.0;
		ga_bSecurityDoorOpen[i] = false;
		ga_hSecurityDoorCloseTimer[i] = INVALID_HANDLE;
	}
	g_hCookiePropRotateStep = RegClientCookie("bm_prop_rotate_step", "Props: rotation step (degrees)", CookieAccess_Private);

	HookEvent("player_death",      Event_PlayerDeath_Pre, EventHookMode_Pre);
	HookEvent("round_start",       Event_RoundStart);
	HookEvent("player_spawn",      Event_PlayerSpawn);
	HookEvent("player_pick_squad", Event_PlayerPickSquad);
	HookEvent("object_destroyed",  Event_ObjectiveDone, EventHookMode_PostNoCopy);
	HookEvent("controlpoint_captured", Event_ObjectiveDone, EventHookMode_PostNoCopy);

	RegConsoleCmd("prophelp",           cmd_prophelp, "Open help menu.");
	AddCommandListener(Command_BlueprintNameSay, "say");
	AddCommandListener(Command_BlueprintNameSay, "say_team");

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i))
				continue;

			ga_fPropRotateStep[i] = PROP_ROTATE_STEP;
			LoadRotateStepCookie(i);

			ga_iLastMattressOwner[i]      = 0;
			ga_fLastMattressLaunchTime[i] = 0.0;
			ga_bMattressDeath[i]          = false;
			ga_iMattressKiller[i]         = 0;
			ga_bMattressJumpArmed[i]      = false;
			ga_iLastInflictorPropId[i]    = -1;
			ResetRecentPropModels(i);

			ga_iResupplyCounter[i] = g_iResupplyDelay;

			ArrayList usedAmmo = EnsureUsedAmmoCacheList(i);
			if (usedAmmo != null)
				usedAmmo.Clear();

			if (IsFakeClient(i)) {
				SDKHook(i, SDKHook_OnTakeDamage, BotOnTakeDamage);
				continue;
			}

			SDKHook(i, SDKHook_OnTakeDamage, PlayerOnTakeDamage);

			if (ga_hPropPlaced[i] != null)
				delete ga_hPropPlaced[i];

			ga_hPropPlaced[i] = new ArrayList();

			if (ga_hPropPlaced[i] == null)
				LogError("Failed to create array for client %d", i);

			SDKHook(i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitch);
			UpdateClientWeaponState(i);
			SetModelIndex(i);
			LoadClientBlueprints(i);
		}

		EnsureTipTimer();
		RebuildAmmoCacheIcons();
	}

	g_iOffLaggedMovementValue = FindSendPropInfo("CBasePlayer", "m_flLaggedMovementValue");

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart() {
	PrecacheFiles();

	if (g_hAmmoCacheRefs != null)
		delete g_hAmmoCacheRefs;
	g_hAmmoCacheRefs = new ArrayList();

	if (g_hMattressRefs != null)
		delete g_hMattressRefs;
	g_hMattressRefs = new ArrayList();

	for (int i = 0; i <= MAXENTITIES; i++) {
		ga_fWireSoundCooldown[i] = 0.0;
		ga_iAmmoAmount[i]        = 0;
		ga_iAmmoIconHolderRef[i] = INVALID_ENT_REFERENCE;
		ga_iAmmoIconSpriteRef[i] = INVALID_ENT_REFERENCE;
		ga_iTrackedPropOwner[i]  = 0;
		ga_iTrackedPropId[i]     = -1;
		ga_bPropHalfHpWarned[i]  = false;
		ga_fSecurityDoorNextTouch[i] = 0.0;
		ga_fSecurityDoorImpactSound[i] = 0.0;
		ga_bSecurityDoorOpen[i] = false;
		ga_hSecurityDoorCloseTimer[i] = INVALID_HANDLE;
	}

	if (g_hJammers != null)
		delete g_hJammers;

	g_hJammers = new ArrayList();

	JC_ScheduleNext(15.0);

	CreateTimer(1.0, Timer_AmmoResupply, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	for (int client = 1; client <= MaxClients; client++) {
		ClearPropSelections(client);
		ClearSelectablePropFlash(client);
		ga_fNextSelectableFlash[client] = 0.0;
		ClearBatchMove(client);
		ga_iResupplyCounter[client] = g_iResupplyDelay;

		ArrayList usedAmmo = EnsureUsedAmmoCacheList(client);
		if (usedAmmo != null)
			usedAmmo.Clear();
	}

	UpdateAmmoRangeCache();
}

public void OnClientPostAdminCheck(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	ga_fLastTouchTime[client]    = 0.0;
	ga_fShopMenuCooldown[client] = 0.0;
	ga_fPropMenuCooldown[client] = 0.0;
	ga_fPressedJumpTime[client]  = 0.0;
	ga_bPlacingNow[client]       = false;
	ga_bPlaceQueued[client]      = false;
	ga_fLastPlaceTime[client]    = 0.0;
	ga_bJustPlaced[client]       = false;
	ga_bPickupQueued[client]     = false;
	ga_bSelectionQueued[client]  = false;
	ga_bHeldPreviewPosValid[client] = false;
	ga_bRotationMenuVisible[client] = false;
	ga_bShopOpenedFromPropMenu[client] = false;
	ga_bPropMenuWeaponLockApplied[client] = false;
	ga_bPropMenuWasWeaponRestricted[client] = false;
	ClearPropSelections(client);
	ClearSelectablePropFlash(client);
	ga_fNextSelectableFlash[client] = 0.0;
	ClearBatchMove(client);
	ClearClientBlueprints(client);

	ga_fPropRotateStep[client]    = PROP_ROTATE_STEP;
	LoadRotateStepCookie(client);

	ga_iLastMattressOwner[client]      = 0;
	ga_fLastMattressLaunchTime[client] = 0.0;
	ga_bMattressDeath[client]          = false;
	ga_iMattressKiller[client]         = 0;
	ga_bMattressJumpArmed[client]      = false;
	ga_iLastInflictorPropId[client]    = -1;
	ResetRecentPropModels(client);

	ga_iResupplyCounter[client] = g_iResupplyDelay;

	ArrayList usedAmmo = EnsureUsedAmmoCacheList(client);
	if (usedAmmo != null)
		usedAmmo.Clear();

	if (!IsFakeClient(client)) {
		SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitch);
		SDKHook(client, SDKHook_OnTakeDamage, PlayerOnTakeDamage);

		if (ga_hPropPlaced[client] != null)
			delete ga_hPropPlaced[client];

		ga_hPropPlaced[client] = new ArrayList();

		if (ga_hPropPlaced[client] == null)
			LogError("Failed to create array for client %d", client);

		ga_bBipodForced[client] = false;
		ga_bFirstTimeJoinedSquad[client] = true;
		UpdateClientWeaponState(client);
		LoadClientBlueprints(client);
	}
	else SDKHook(client, SDKHook_OnTakeDamage, BotOnTakeDamage);
}

public void OnClientCookiesCached(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	LoadRotateStepCookie(client);
}

public void OnClientDisconnect(int client) {
	if (client < 1 || client > MaxClients)
		return;

	ga_iLastButtons[client] = 0;
	ga_bRotationMenuVisible[client] = false;
	ga_bShopOpenedFromPropMenu[client] = false;
	ga_bPickupQueued[client] = false;
	ga_bSelectionQueued[client] = false;
	ga_bPlaceQueued[client] = false;
	ga_bHeldPreviewPosValid[client] = false;
	ga_bPropAuxMenuOpen[client] = false;
	ga_bPropMenuWeaponLockApplied[client] = false;
	ga_bPropMenuWasWeaponRestricted[client] = false;
	ga_iLastInflictorPropId[client] = -1;
	ResetRecentPropModels(client);

	ga_iLastMattressOwner[client]      = 0;
	ga_fLastMattressLaunchTime[client] = 0.0;
	ga_bMattressDeath[client]          = false;
	ga_iMattressKiller[client]         = 0;
	ga_bMattressJumpArmed[client]      = false;

	if (IsFakeClient(client))
		return;

	StopHolding(client);
	ClearPropSelections(client);
	ClearSelectablePropFlash(client);
	ga_fNextSelectableFlash[client] = 0.0;
	ClearBatchMove(client);
	ClearClientBlueprints(client);

	if (ga_hHighlightedMattressRefs[client] != null) {
		delete ga_hHighlightedMattressRefs[client];
		ga_hHighlightedMattressRefs[client] = null;
	}
	if (ga_hSelectedPropRefs[client] != null) {
		delete ga_hSelectedPropRefs[client];
		ga_hSelectedPropRefs[client] = null;
	}
	if (ga_hSelectableFlashRefs[client] != null) {
		delete ga_hSelectableFlashRefs[client];
		ga_hSelectableFlashRefs[client] = null;
	}
	if (ga_hBatchMoveData[client] != null) {
		delete ga_hBatchMoveData[client];
		ga_hBatchMoveData[client] = null;
	}

	ArrayList list = ga_hPropPlaced[client];
	ga_hPropPlaced[client] = null;

	if (list != null) {
		for (int i = 0; i < list.Length; i++)
			SafeKillRef(list.Get(i));

		delete list;
	}

	if (ga_hUsedAmmoCacheRefs[client] != null)
		ga_hUsedAmmoCacheRefs[client].Clear();

	for (int i = 1; i <= MaxClients; i++) {
		if (ga_iPropOwner[i] == client)
			ga_iPropOwner[i] = 0;
	}
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

		StopHolding(i);
		DeconstructAllProps(i);
		ga_iPropOwner[i] = 0;
		ga_bPlayerRefund[i] = false;
		ga_bPlacingNow[i] = false;
		ga_fLastPlaceTime[i] = 0.0;
		ga_bJustPlaced[i] = false;
		ga_bMattressJumpArmed[i] = false;
		ga_bSelectionQueued[i] = false;
		ga_bPlaceQueued[i] = false;
		ClearPropSelections(i);
		ClearSelectablePropFlash(i);
		ga_fNextSelectableFlash[i] = 0.0;
		ClearBatchMove(i);
		RestoreBuildPoints(i);
	}

	EnsureTipTimer();

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Continue;

	ga_iResupplyCounter[client] = g_iResupplyDelay;
	ga_iLastInflictorPropId[client] = -1;
	ga_bMattressJumpArmed[client] = false;
	SetPropMenuWeaponLock(client, false);
	UpdateClientWeaponState(client);
	return Plugin_Continue;
}

public Action Event_PlayerDeath_Pre(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || !IsClientInGame(victim))
		return Plugin_Continue;

	if (IsFakeClient(victim)) {
		if (ga_bMattressDeath[victim] && ga_iMattressKiller[victim] > 0) {
			int killer = ga_iMattressKiller[victim];

			if (IsClientInGame(killer) && GetClientTeam(killer) != GetClientTeam(victim)) {
				event.SetInt("attacker", GetClientUserId(killer));
				if (!IsFakeClient(killer))
					LogToGame("\"%L\" triggered \"mattress_kill\"", killer);
			}

			event.SetString("weapon", "Mattress");

			ga_bMattressDeath[victim] = false;
			ga_iMattressKiller[victim] = 0;

			return Plugin_Changed;
		}

		int inflictor = EntRefToEntIndex(ga_iLastInflictor[victim]);
		
		if (IsValidNonClientEntity(inflictor)) {
			if (GetTrackedPropId(inflictor) == MID(Prop_BarbWire)) {
				int killer = GetClientOfUserId(event.GetInt("attacker"));
				if (killer > 0 && IsClientInGame(killer) && !IsFakeClient(killer) && GetClientTeam(killer) != GetClientTeam(victim))
					LogToGame("\"%L\" triggered \"barbed_wire_kill\"", killer);
				event.SetString("weapon", "Barbed Wire");
				return Plugin_Changed;
			}
		}
		else if (ga_iLastInflictorPropId[victim] == MID(Prop_BarbWire)) {
			int killer = GetClientOfUserId(event.GetInt("attacker"));
			if (killer > 0 && IsClientInGame(killer) && !IsFakeClient(killer) && GetClientTeam(killer) != GetClientTeam(victim))
				LogToGame("\"%L\" triggered \"barbed_wire_kill\"", killer);
			event.SetString("weapon", "Barbed Wire");
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}

	ClearPropSelections(victim);
	ClearSelectablePropFlash(victim);
	ga_fNextSelectableFlash[victim] = 0.0;
	SetPropMenuWeaponLock(victim, false);
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

void GetPositionInFront(float vPos[3], const float vAng[3], float distance) {
	float vecForward[3];
	GetAngleVectors(vAng, vecForward, NULL_VECTOR, NULL_VECTOR);

	vPos[0] += vecForward[0] * distance;
	vPos[1] += vecForward[1] * distance;
	vPos[2] += vecForward[2] * distance;
}

int IsPlayerOnGround(int client) { return GetEntityFlags(client) & FL_ONGROUND; }

static bool BeginPlaceLock(int client) {
	if (ga_bPlacingNow[client]) return false;
	ga_bPlacingNow[client] = true;
	return true;
}

static void EndPlaceLock(int client) { ga_bPlacingNow[client] = false; }

static bool CanPlaceNow(int client) {
	float now = GetGameTime();
	if (now - ga_fLastPlaceTime[client] < gc_fPlaceDebounce) return false;
	ga_fLastPlaceTime[client] = now;
	return true;
}

static bool CanPreviewPlaceProp(int client, const float vPos[3], const float vel[3]) {
	if (!IsPlayerOnGround(client))
		return false;
	if (vel[0] != 0.0 || vel[1] != 0.0 || vel[2] != 0.0)
		return false;
	if (IsCollidingWithPlayer(client, vPos))
		return false;

	return true;
}

static void UpdateHeldPropPreviewColor(int client, int ent, const float vPos[3], const float vAng[3], const float vel[3]) {
	if (CanPreviewPlaceBatch(client, vPos, vAng, vel))
		SetEntityRenderColor(ent, PROP_PREVIEW_PLACEABLE_R, PROP_PREVIEW_PLACEABLE_G, PROP_PREVIEW_PLACEABLE_B, PROP_ALPHA);
	else
		SetEntityRenderColor(ent, PROP_PREVIEW_BLOCKED_R, PROP_PREVIEW_BLOCKED_G, PROP_PREVIEW_BLOCKED_B, PROP_ALPHA);
}

static ArrayList EnsureHighlightedMattressList(int client) {
	if (client < 1 || client > MaxClients)
		return null;

	if (ga_hHighlightedMattressRefs[client] == null)
		ga_hHighlightedMattressRefs[client] = new ArrayList();

	return ga_hHighlightedMattressRefs[client];
}

static ArrayList EnsureSelectedPropList(int client) {
	if (client < 1 || client > MaxClients)
		return null;

	if (ga_hSelectedPropRefs[client] == null)
		ga_hSelectedPropRefs[client] = new ArrayList();

	return ga_hSelectedPropRefs[client];
}

static bool IsPropSelectedByAnyClient(int ent) {
	if (!IsValidNonClientEntity(ent))
		return false;

	for (int client = 1; client <= MaxClients; client++) {
		if (RefListContainsEntity(ga_hSelectedPropRefs[client], ent))
			return true;
	}
	return false;
}

static void RestoreMattressRenderColor(int ent) {
	if (!IsValidNonClientEntity(ent))
		return;

	if (IsPropSelectedByAnyClient(ent)) {
		SetEntityRenderColor(ent, PROP_SELECTION_R, PROP_SELECTION_G, PROP_SELECTION_B, 255);
		return;
	}

	SetEntityRenderColor(ent, 255, 255, 255, 255);
	GlowLowHp(ent, GetEntProp(ent, Prop_Data, "m_iHealth"));
}

static void ClearPropSelections(int client) {
	if (client < 1 || client > MaxClients)
		return;

	ArrayList list = ga_hSelectedPropRefs[client];
	if (list == null)
		return;

	for (int i = list.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(list.Get(i));
		list.Erase(i);
		if (IsValidNonClientEntity(ent))
			RestoreMattressRenderColor(ent);
	}
}

static void ClearSelectablePropFlash(int client) {
	if (client < 1 || client > MaxClients)
		return;

	if (ga_hSelectableFlashTimer[client] != INVALID_HANDLE) {
		KillTimer(ga_hSelectableFlashTimer[client]);
		ga_hSelectableFlashTimer[client] = INVALID_HANDLE;
	}

	ArrayList list = ga_hSelectableFlashRefs[client];
	if (list == null)
		return;

	for (int i = list.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(list.Get(i));
		if (IsValidNonClientEntity(ent))
			RestoreMattressRenderColor(ent);
	}
	list.Clear();
}

static void FlashNearbySelectableProps(int client, int selectedProp, const float selectedPos[3]) {
	float now = GetGameTime();
	if (ga_fNextSelectableFlash[client] > now)
		return;
	ga_fNextSelectableFlash[client] = now + 0.75;

	ClearSelectablePropFlash(client);
	ArrayList props = ga_hPropPlaced[client];
	if (props == null)
		return;

	if (ga_hSelectableFlashRefs[client] == null)
		ga_hSelectableFlashRefs[client] = new ArrayList();

	for (int i = 0; i < props.Length; i++) {
		int ent = EntRefToEntIndex(props.Get(i));
		if (!IsValidNonClientEntity(ent) || ent == selectedProp)
			continue;
		if (GetTrackedPropId(ent) == MID(Prop_AmmoCacheSmall))
			continue;

		float pos[3];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
		if (GetVectorDistance(pos, selectedPos, true) > (g_fPropSelectionRadius * g_fPropSelectionRadius))
			continue;

		SetEntityRenderColor(ent, 100, 190, 255, 190);
		AddUniqueEntityRef(ga_hSelectableFlashRefs[client], ent);
	}

	if (ga_hSelectableFlashRefs[client].Length > 0)
		ga_hSelectableFlashTimer[client] = CreateTimer(0.55, Timer_RestoreSelectablePropFlash, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RestoreSelectablePropFlash(Handle timer, int userId) {
	int client = GetClientOfUserId(userId);
	if (client < 1 || client > MaxClients)
		return Plugin_Stop;

	ga_hSelectableFlashTimer[client] = INVALID_HANDLE;
	ArrayList list = ga_hSelectableFlashRefs[client];
	if (list == null)
		return Plugin_Stop;

	for (int i = list.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(list.Get(i));
		if (IsValidNonClientEntity(ent))
			RestoreMattressRenderColor(ent);
	}
	list.Clear();
	return Plugin_Stop;
}

static void ClearBatchMove(int client, bool immediate = false) {
	if (client < 1 || client > MaxClients)
		return;

	ArrayList batch = ga_hBatchMoveData[client];
	if (batch != null) {
		for (int i = batch.Length - 1; i >= 0; i--) {
			int previewRef = batch.Get(i, 7);
			if (immediate)
				KillNowRef(previewRef);
			else {
				int preview = EntRefToEntIndex(previewRef);
				if (IsValidNonClientEntity(preview))
					SafeKillIdx(preview);
			}
		}
		batch.Clear();
	}
}

static void ClearBlueprintHold(int client, bool immediate = false) {
	if (client < 1 || client > MaxClients)
		return;

	ArrayList list = ga_hBlueprintHoldData[client];
	if (list != null) {
		for (int i = list.Length - 1; i >= 0; i--) {
			int previewRef = list.Get(i, 7);
			if (immediate)
				KillNowRef(previewRef);
			else
				SafeKillRef(previewRef);
		}
		list.Clear();
	}
	ga_bHoldingBlueprint[client] = false;
}

static int CreateBatchPreview(int modelId) {
	if (modelId < 0 || modelId >= PROP_COUNT)
		return INVALID_ENT_REFERENCE;

	int preview = CreateEntityByName("prop_dynamic_override");
	if (preview == -1)
		return INVALID_ENT_REFERENCE;

	DispatchKeyValue(preview, "solid", "0");
	DispatchKeyValue(preview, "disableshadows", "1");
	DispatchKeyValue(preview, "disableshadowdepth", "1");
	DispatchKeyValue(preview, "model", g_PropDefs[modelId].model);
	DispatchSpawn(preview);
	SetEntityRenderMode(preview, RENDER_TRANSCOLOR);
	SetEntityRenderColor(preview, 255, 255, 255, PROP_ALPHA);
	SetEntityMoveType(preview, MOVETYPE_NONE);
	return EntIndexToEntRef(preview);
}

static bool StartBatchMovePreviews(int client) {
	ArrayList batch = ga_hBatchMoveData[client];
	if (batch == null || batch.Length == 0)
		return false;

	for (int i = 0; i < batch.Length; i++) {
		int previewRef = CreateBatchPreview(batch.Get(i, 8));
		if (previewRef == INVALID_ENT_REFERENCE) {
			ClearBatchMove(client);
			return false;
		}

		batch.Set(i, previewRef, 7);
	}

	PrintCenterText(client, "Moving %d props", batch.Length + 1);
	return true;
}

static void RemoveBatchSourceProps(int client, int leader) {
	SafeKillIdx(leader);

	ArrayList batch = ga_hBatchMoveData[client];
	if (batch == null)
		return;

	for (int i = 0; i < batch.Length; i++)
		SafeKillRef(batch.Get(i, 0));
}

static void TransformBatchOffset(int client, const float offset[3], const float leadPosition[3], const float leadAngles[3], float position[3]) {
	float oldForward[3], oldRight[3], oldUp[3];
	float newForward[3], newRight[3], newUp[3];
	if (ga_bHoldingBlueprint[client])
		GetAngleVectors(ga_fBlueprintLeadAngles[client], oldForward, oldRight, oldUp);
	else
		GetAngleVectors(ga_fBatchLeadAngles[client], oldForward, oldRight, oldUp);
	GetAngleVectors(leadAngles, newForward, newRight, newUp);

	float localForward = (offset[0] * oldForward[0]) + (offset[1] * oldForward[1]) + (offset[2] * oldForward[2]);
	float localRight = (offset[0] * oldRight[0]) + (offset[1] * oldRight[1]) + (offset[2] * oldRight[2]);
	float localUp = (offset[0] * oldUp[0]) + (offset[1] * oldUp[1]) + (offset[2] * oldUp[2]);

	position[0] = leadPosition[0] + (newForward[0] * localForward) + (newRight[0] * localRight) + (newUp[0] * localUp);
	position[1] = leadPosition[1] + (newForward[1] * localForward) + (newRight[1] * localRight) + (newUp[1] * localUp);
	position[2] = leadPosition[2] + (newForward[2] * localForward) + (newRight[2] * localRight) + (newUp[2] * localUp);
}

static bool CanPreviewPlaceBatch(int client, const float leadPosition[3], const float leadAngles[3], const float vel[3]) {
	if (!CanPreviewPlaceProp(client, leadPosition, vel))
		return false;

	ArrayList batch = ga_bHoldingBlueprint[client] ? ga_hBlueprintHoldData[client] : ga_hBatchMoveData[client];
	if (batch == null || batch.Length == 0)
		return true;

	for (int i = 0; i < batch.Length; i++) {
		float offset[3], position[3];
		offset[0] = view_as<float>(batch.Get(i, 1));
		offset[1] = view_as<float>(batch.Get(i, 2));
		offset[2] = view_as<float>(batch.Get(i, 3));
		TransformBatchOffset(client, offset, leadPosition, leadAngles, position);

		if (IsCollidingWithPlayer(client, position))
			return false;
	}

	return true;
}

static void UpdateBatchMovePreviews(int client, const float leadPosition[3], const float leadAngles[3], const float vel[3]) {
	ArrayList batch = ga_bHoldingBlueprint[client] ? ga_hBlueprintHoldData[client] : ga_hBatchMoveData[client];
	if (batch == null || batch.Length == 0)
		return;

	bool placeable = CanPreviewPlaceBatch(client, leadPosition, leadAngles, vel);

	for (int i = 0; i < batch.Length; i++) {
		int preview = EntRefToEntIndex(batch.Get(i, 7));
		if (!IsValidNonClientEntity(preview))
			continue;

		float offset[3], angles[3], position[3];
		offset[0] = view_as<float>(batch.Get(i, 1));
		offset[1] = view_as<float>(batch.Get(i, 2));
		offset[2] = view_as<float>(batch.Get(i, 3));
		float baseAngles[3];
		if (ga_bHoldingBlueprint[client]) {
			baseAngles[0] = ga_fBlueprintLeadAngles[client][0];
			baseAngles[1] = ga_fBlueprintLeadAngles[client][1];
			baseAngles[2] = ga_fBlueprintLeadAngles[client][2];
		} else {
			baseAngles[0] = ga_fBatchLeadAngles[client][0];
			baseAngles[1] = ga_fBatchLeadAngles[client][1];
			baseAngles[2] = ga_fBatchLeadAngles[client][2];
		}
		angles[0] = view_as<float>(batch.Get(i, 4)) + leadAngles[0] - baseAngles[0];
		angles[1] = view_as<float>(batch.Get(i, 5)) + leadAngles[1] - baseAngles[1];
		angles[2] = view_as<float>(batch.Get(i, 6)) + leadAngles[2] - baseAngles[2];
		TransformBatchOffset(client, offset, leadPosition, leadAngles, position);

		TeleportEntity(preview, position, angles, NULL_VECTOR);
		if (placeable)
			SetEntityRenderColor(preview, PROP_PREVIEW_PLACEABLE_R, PROP_PREVIEW_PLACEABLE_G, PROP_PREVIEW_PLACEABLE_B, PROP_ALPHA);
		else
			SetEntityRenderColor(preview, PROP_PREVIEW_BLOCKED_R, PROP_PREVIEW_BLOCKED_G, PROP_PREVIEW_BLOCKED_B, PROP_ALPHA);
	}
}

static bool IsMattressHighlightedByAnyClient(int ent) {
	if (!IsValidNonClientEntity(ent))
		return false;

	for (int client = 1; client <= MaxClients; client++) {
		if (RefListContainsEntity(ga_hHighlightedMattressRefs[client], ent))
			return true;
	}
	return false;
}

static void ClearMattressStackHighlights(int client) {
	if (client < 1 || client > MaxClients)
		return;

	ArrayList list = ga_hHighlightedMattressRefs[client];
	if (list == null)
		return;

	for (int i = list.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(list.Get(i));
		if (IsValidNonClientEntity(ent))
			RestoreMattressRenderColor(ent);
	}

	list.Clear();
	ga_fNextMattressHighlightUpdate[client] = 0.0;
}

static bool IsMattressInStackRange(const float origin[3], int ent) {
	if (!IsValidNonClientEntity(ent) || GetTrackedPropId(ent) != MID(Prop_Mattress))
		return false;

	float pos[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);

	float dx = pos[0] - origin[0];
	float dy = pos[1] - origin[1];
	if ((dx * dx) + (dy * dy) > (MATTRESS_STACK_RADIUS * MATTRESS_STACK_RADIUS))
		return false;
	float zGap = FloatAbs(pos[2] - origin[2]);
	if (zGap < MATTRESS_STACK_MIN_Z_GAP || zGap > MATTRESS_STACK_Z_RANGE)
		return false;

	return true;
}

static void UpdateMattressStackHighlights(int client, const float origin[3]) {
	if (MID(ga_iModelIndex[client]) != MID(Prop_Mattress)) {
		if (ga_hHighlightedMattressRefs[client] != null && ga_hHighlightedMattressRefs[client].Length > 0)
			ClearMattressStackHighlights(client);
		return;
	}

	float now = GetGameTime();
	if (ga_fNextMattressHighlightUpdate[client] > now)
		return;

	ClearMattressStackHighlights(client);
	ga_fNextMattressHighlightUpdate[client] = now + MATTRESS_HIGHLIGHT_INTERVAL;

	if (g_hMattressRefs == null)
		return;

	ArrayList highlighted = EnsureHighlightedMattressList(client);
	if (highlighted == null)
		return;

	int maxContributors = MATTRESS_MAX_STACK_COUNT - 1;
	int contributorCount = 0;

	for (int i = g_hMattressRefs.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(g_hMattressRefs.Get(i));
		if (!IsValidNonClientEntity(ent) || GetTrackedPropId(ent) != MID(Prop_Mattress)) {
			g_hMattressRefs.Erase(i);
			continue;
		}
		if (!IsMattressInStackRange(origin, ent))
			continue;

		if (!IsPropSelectedByAnyClient(ent))
			SetEntityRenderColor(ent, PROP_PREVIEW_PLACEABLE_R, PROP_PREVIEW_PLACEABLE_G, PROP_PREVIEW_PLACEABLE_B, 255);
		AddUniqueEntityRef(highlighted, ent);
		contributorCount++;
		if (contributorCount >= maxContributors)
			break;
	}

	int stackCount = contributorCount + 1;
	if (stackCount > 1) {
		float boost = GetMattressStackBoost(stackCount);
		float bonus = boost - MATTRESS_BASE_BOOST;
		PrintCenterText(client, "Mattress stack: %d/%d\nBoost: %.0f (+%.0f)", stackCount, MATTRESS_MAX_STACK_COUNT, boost, bonus);
	}
}

void HoldProp(int client) {
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
		return;

	if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
		StopHolding(client);

	ga_bHeldPreviewPosValid[client] = false;

	float vPos[3], vAng[3];
	GetClientEyePosition(client, vPos);
	GetClientEyeAngles(client, vAng);
	GetPositionInFront(vPos, vAng, PROP_HOLD_DISTANCE);
	CreateProp(client, vPos, NULL_VECTOR);
}

static void TouchLaggedMovementValue(int client) {
	if (g_iOffLaggedMovementValue <= 0)
		return;
	float cur = GetEntDataFloat(client, g_iOffLaggedMovementValue);
	SetEntDataFloat(client, g_iOffLaggedMovementValue, cur, true);
}

void StopHolding(int client, bool now = false, bool keepGroupPreview = false) {
	ClearMattressStackHighlights(client);
	if (!keepGroupPreview) {
		ClearBatchMove(client);
		ClearBlueprintHold(client);
	}
	ga_bHeldPreviewPosValid[client] = false;
	ga_bPickupQueued[client] = false;
	ga_bPlaceQueued[client] = false;

	int ref = ga_iPropHolding[client];
	if (ref == INVALID_ENT_REFERENCE)
		return;

	ga_iPropHolding[client] = INVALID_ENT_REFERENCE;
	ga_iHoldHp[client] = 0;
	ga_iHoldMaxHp[client] = 0;

	if (now)
		KillNowRef(ref);
	else
		SafeKillRef(ref);
}

static bool HandlePropMenuNavigation(int client, int pressed, int &buttons, bool &buttonsChanged) {
	bool holdingProp = ga_iPropHolding[client] != INVALID_ENT_REFERENCE;
	if (!AnyPropMenuFlagOpen(client))
		return false;
	if (holdingProp && !ga_bPropRotateMenuOpen[client])
		return false;
	if (GetClientMenu(client) != MenuSource_Normal)
		return false;
	if (pressed & (BTN_SPRINT | BTN_SPRINT_TOGGLE))
		return false;

	if (pressed & BTN_LEAN_LEFT) {
		ClientCommand(client, "slot7");
		return true;
	}
	if (pressed & BTN_LEAN_RIGHT) {
		ClientCommand(client, "slot8");
		return true;
	}

	return false;
}

static bool HandleRotationReset(int client, int pressed, int &buttons) {
	if (!(pressed & BTN_RELOAD) || !ga_bRotationMenuVisible[client] || ga_iPropHolding[client] == INVALID_ENT_REFERENCE)
		return false;

	buttons &= ~BTN_RELOAD;
	ResetHeldPropRotation(client);
	return true;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
		return Plugin_Continue;

	int inputButtons = buttons;
	bool buttonsChanged = false;
	SyncPropMenuWeaponLock(client);
	if (AnyPropMenuFlagOpen(client) && (inputButtons & (BTN_SPRINT | BTN_SPRINT_TOGGLE))) {
		CloseAllPropMenus(client);
		ga_iLastButtons[client] = inputButtons;
		return Plugin_Continue;
	}

	int pressed = inputButtons & ~ga_iLastButtons[client];
	if (HandleRotationReset(client, pressed, buttons)) {
		ga_iLastButtons[client] = inputButtons;
		return Plugin_Changed;
	}
	if (HandlePropMenuNavigation(client, pressed, buttons, buttonsChanged)) {
		ga_iLastButtons[client] = inputButtons;
		return buttonsChanged ? Plugin_Changed : Plugin_Continue;
	}

	if (pressed & BTN_JUMP)
		OnButtonPress(client, BTN_JUMP, vel);
	if (pressed & (BTN_SPRINT | BTN_SPRINT_TOGGLE | BTN_ATTACK1))
		OnButtonPress(client, pressed & (BTN_SPRINT | BTN_SPRINT_TOGGLE | BTN_ATTACK1), vel);
	if (pressed & (BTN_AIM | BTN_AIM_TOGGLE))
		OnButtonPress(client, pressed & (BTN_AIM | BTN_AIM_TOGGLE), vel);
	if (pressed & BTN_SPECIAL1)
		OnButtonPress(client, BTN_SPECIAL1, vel);
	if (pressed & (BTN_DUCK | BTN_DUCK_TOGGLE | BTN_FORWARD | BTN_BACKWARD | BTN_LEFT | BTN_RIGHT))
		OnButtonPress(client, pressed & (BTN_DUCK | BTN_DUCK_TOGGLE | BTN_FORWARD | BTN_BACKWARD | BTN_LEFT | BTN_RIGHT), vel);
	if (pressed & BTN_FIREMODE)
		OnButtonPress(client, BTN_FIREMODE, vel);

	ga_iLastButtons[client] = inputButtons;

	if (!ga_bHoldingMeleeWeapon[client]) {
		if (ga_hHighlightedMattressRefs[client] != null && ga_hHighlightedMattressRefs[client].Length > 0)
			ClearMattressStackHighlights(client);
		return buttonsChanged ? Plugin_Changed : Plugin_Continue;
	}

	if ((pressed & BTN_USE) && ga_iPropHolding[client] == INVALID_ENT_REFERENCE)
		QueuePropSelectionToggle(client);
	if (pressed & (BTN_AIM | BTN_AIM_TOGGLE)) {
		if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE)
			OnButtonPress(client, BTN_USE, vel);
		else {
			QueueHeldPropPlacement(client, vel);
			buttons &= ~(BTN_AIM | BTN_AIM_TOGGLE);
			buttonsChanged = true;
		}
	}

	int ent = EntRefToEntIndex(ga_iPropHolding[client]);
	if (ent <= MaxClients || !IsValidEntity(ent)) {
		ga_iPropHolding[client] = INVALID_ENT_REFERENCE;
		ga_bHeldPreviewPosValid[client] = false;
		ClearMattressStackHighlights(client);
		return buttonsChanged ? Plugin_Changed : Plugin_Continue;
	}

	float vAng[3];
	GetClientEyeAngles(client, vAng);

	float vPos[3];
	GetClientEyePosition(client, vPos);
	GetPositionInFront(vPos, vAng, PROP_HOLD_DISTANCE);

	// Avoid mutating nearby props during the engine's PlayerUse scan.
	if (buttons & BTN_USE)
		return buttonsChanged ? Plugin_Changed : Plugin_Continue;

	if (!ga_bHeldPreviewPosValid[client]
		|| GetVectorDistance(vPos, ga_fLastHeldPreviewPos[client], true) > gc_fHeldPropTeleportMinDeltaSqr) {
		TeleportEntity(ent, vPos, NULL_VECTOR, NULL_VECTOR);
		ga_fLastHeldPreviewPos[client][0] = vPos[0];
		ga_fLastHeldPreviewPos[client][1] = vPos[1];
		ga_fLastHeldPreviewPos[client][2] = vPos[2];
		ga_bHeldPreviewPosValid[client] = true;
	}

	float heldAngles[3];
	GetEntPropVector(ent, Prop_Send, "m_angRotation", heldAngles);
	UpdateHeldPropPreviewColor(client, ent, vPos, heldAngles, vel);
	UpdateBatchMovePreviews(client, vPos, heldAngles, vel);
	UpdateMattressStackHighlights(client, vPos);

	return buttonsChanged ? Plugin_Changed : Plugin_Continue;
}

static void QueuePropSelectionToggle(int client) {
	if (ga_bSelectionQueued[client])
		return;

	int target = GetClientAimTarget(client, false);
	if (!IsValidNonClientEntity(target))
		return;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(EntIndexToEntRef(target));
	ga_bSelectionQueued[client] = true;
	RequestFrame(NF_DeferredPropSelectionToggle, pack);
}

static void QueueHeldPropPlacement(int client, const float vel[3]) {
	if (ga_bPlaceQueued[client])
		return;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(ga_iPropHolding[client]);
	pack.WriteFloat(vel[0]);
	pack.WriteFloat(vel[1]);
	pack.WriteFloat(vel[2]);
	ga_bPlaceQueued[client] = true;
	RequestFrame(NF_DeferredHeldPropPlacement, pack);
}

static void NF_DeferredHeldPropPlacement(any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = GetClientFromSerial(pack.ReadCell());
	int heldRef = pack.ReadCell();
	float vel[3];
	vel[0] = pack.ReadFloat();
	vel[1] = pack.ReadFloat();
	vel[2] = pack.ReadFloat();
	delete pack;

	if (client < 1 || client > MaxClients)
		return;

	ga_bPlaceQueued[client] = false;
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client)
		|| !ga_bHoldingMeleeWeapon[client] || ga_iPropHolding[client] != heldRef)
		return;

	OnButtonPress(client, BTN_USE, vel);
}

static void NF_DeferredPropSelectionToggle(any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = GetClientOfUserId(pack.ReadCell());
	int targetRef = pack.ReadCell();
	delete pack;

	if (client < 1 || client > MaxClients)
		return;

	ga_bSelectionQueued[client] = false;
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client)
		|| !ga_bHoldingMeleeWeapon[client] || ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
		return;

	int target = EntRefToEntIndex(targetRef);
	if (!IsValidNonClientEntity(target) || GetTrackedPropId(target) < 0
		|| GetTrackedPropId(target) == MID(Prop_AmmoCacheSmall))
		return;

	if (GetPropOwner(target) != client) {
		PrintCenterText(client, "You can only select your own props.");
		return;
	}

	float eye[3], targetPos[3];
	GetClientEyePosition(client, eye);
	GetEntPropVector(target, Prop_Send, "m_vecOrigin", targetPos);
	if (GetVectorDistance(eye, targetPos, true) > (PROP_PICKUP_DISTANCE * PROP_PICKUP_DISTANCE)) {
		PrintCenterText(client, "Too far away to select that prop.");
		return;
	}

	ArrayList selected = EnsureSelectedPropList(client);
	if (selected == null)
		return;

	if (RefListContainsEntity(selected, target)) {
		RemoveEntityRef(selected, target);
		RestoreMattressRenderColor(target);
		PrintCenterText(client, "Prop unselected. Selected: %d/%d", selected.Length, g_iPropSelectionMax);
		return;
	}

	if (selected.Length >= g_iPropSelectionMax) {
		PrintCenterText(client, "You can select up to %d props.", g_iPropSelectionMax);
		return;
	}

	if (selected.Length > 0) {
		int anchor = EntRefToEntIndex(selected.Get(0));
		if (!IsValidNonClientEntity(anchor)) {
			selected.Erase(0);
		} else {
			float anchorPos[3];
			GetEntPropVector(anchor, Prop_Send, "m_vecOrigin", anchorPos);
			if (GetVectorDistance(anchorPos, targetPos, true) > (g_fPropSelectionRadius * g_fPropSelectionRadius)) {
				PrintCenterText(client, "Selected props must be within %.0f units of the first prop.", g_fPropSelectionRadius);
				return;
			}
		}
	}

	AddUniqueEntityRef(selected, target);
	SetEntityRenderColor(target, PROP_SELECTION_R, PROP_SELECTION_G, PROP_SELECTION_B, 255);
	if (selected.Length == 1)
		FlashNearbySelectableProps(client, target, targetPos);
	PrintCenterText(client, "Prop selected. Selected: %d/%d", selected.Length, g_iPropSelectionMax);
}

static bool PrepareBatchMove(int client, int leader) {
	ClearBatchMove(client);

	ArrayList selected = ga_hSelectedPropRefs[client];
	if (selected == null || selected.Length < 2 || !RefListContainsEntity(selected, leader))
		return false;

	float leadOrigin[3];
	GetEntPropVector(leader, Prop_Send, "m_vecOrigin", leadOrigin);
	GetEntPropVector(leader, Prop_Send, "m_angRotation", ga_fBatchLeadAngles[client]);
	if (ga_hBatchMoveData[client] == null)
		ga_hBatchMoveData[client] = new ArrayList(PROP_BATCH_DATA_SIZE);
	for (int i = selected.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(selected.Get(i));
		if (!IsValidNonClientEntity(ent) || GetPropOwner(ent) != client) {
			selected.Erase(i);
			continue;
		}
		if (ent == leader)
			continue;

		float origin[3], angles[3];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", origin);
		GetEntPropVector(ent, Prop_Send, "m_angRotation", angles);
		int modelId = GetTrackedPropId(ent);
		int health = GetEntProp(ent, Prop_Data, "m_iHealth");

		int data[PROP_BATCH_DATA_SIZE];
		data[0] = EntIndexToEntRef(ent);
		data[1] = view_as<int>(origin[0] - leadOrigin[0]);
		data[2] = view_as<int>(origin[1] - leadOrigin[1]);
		data[3] = view_as<int>(origin[2] - leadOrigin[2]);
		data[4] = view_as<int>(angles[0]);
		data[5] = view_as<int>(angles[1]);
		data[6] = view_as<int>(angles[2]);
		data[7] = INVALID_ENT_REFERENCE;
		data[8] = modelId;
		data[9] = health;
		ga_hBatchMoveData[client].PushArray(data, sizeof(data));
	}

	return ga_hBatchMoveData[client].Length > 0;
}

static bool IsOtherPlayerStandingOnProp(int mover, int prop) {
	for (int client = 1; client <= MaxClients; client++) {
		if (client == mover || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
			continue;
		if (GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == prop)
			return true;
	}

	return false;
}

static bool IsOtherPlayerStandingOnBatch(int mover, int leader) {
	if (IsOtherPlayerStandingOnProp(mover, leader))
		return true;

	ArrayList batch = ga_hBatchMoveData[mover];
	if (batch == null)
		return false;

	for (int i = 0; i < batch.Length; i++) {
		int prop = EntRefToEntIndex(batch.Get(i, 0));
		if (IsValidNonClientEntity(prop) && IsOtherPlayerStandingOnProp(mover, prop))
			return true;
	}

	return false;
}

static void FinishBatchMove(int client, const float leadPosition[3], const float leadAngles[3]) {
	ArrayList batch = ga_hBatchMoveData[client];
	if (batch == null || batch.Length == 0)
		return;

	PropId previousModel = ga_iModelIndex[client];
	int previousOwner = ga_iPropOwner[client];

	for (int i = 0; i < batch.Length; i++) {
		int modelId = batch.Get(i, 8);
		if (modelId < 0 || modelId >= PROP_COUNT)
			continue;

		float offset[3], angles[3], position[3];
		offset[0] = view_as<float>(batch.Get(i, 1));
		offset[1] = view_as<float>(batch.Get(i, 2));
		offset[2] = view_as<float>(batch.Get(i, 3));
		angles[0] = view_as<float>(batch.Get(i, 4)) + leadAngles[0] - ga_fBatchLeadAngles[client][0];
		angles[1] = view_as<float>(batch.Get(i, 5)) + leadAngles[1] - ga_fBatchLeadAngles[client][1];
		angles[2] = view_as<float>(batch.Get(i, 6)) + leadAngles[2] - ga_fBatchLeadAngles[client][2];
		TransformBatchOffset(client, offset, leadPosition, leadAngles, position);

		int health = batch.Get(i, 9);
		ga_iModelIndex[client] = view_as<PropId>(modelId);
		ga_iPropOwner[client] = client;
		CreateProp(client, position, angles, health, true);
	}

	ga_iModelIndex[client] = previousModel;
	ga_iPropOwner[client] = previousOwner;
	ClearBatchMove(client);
}

static void QueueExistingPropPickup(int client, int target) {
	if (ga_bPickupQueued[client] || target <= MaxClients || !IsValidEntity(target))
		return;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(EntIndexToEntRef(target));
	ga_bPickupQueued[client] = true;
	RequestFrame(NF_DeferredPickupExistingProp, pack);
}

static void NF_DeferredPickupExistingProp(any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = GetClientOfUserId(pack.ReadCell());
	int targetRef = pack.ReadCell();
	delete pack;

	if (client < 1 || client > MaxClients)
		return;

	ga_bPickupQueued[client] = false;

	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client) || !ga_bHoldingMeleeWeapon[client])
		return;
	if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
		return;
	if (GetClientButtons(client) & (BTN_SPRINT | BTN_SPRINT_TOGGLE | BTN_ATTACK1))
		return;
	if (!IsPlayerOnGround(client) || IsPlayerOnProp(client))
		return;

	int target = EntRefToEntIndex(targetRef);
	if (target <= MaxClients || !IsValidEntity(target))
		return;

	int modelId = GetTrackedPropId(target);
	if (modelId < 0 || modelId >= PROP_COUNT || modelId == MID(Prop_AmmoCacheSmall))
		return;

	float vPos[3], vAng[3], vEye[3];
	GetEntPropVector(target, Prop_Send, "m_vecOrigin", vPos);
	GetEntPropVector(target, Prop_Send, "m_angRotation", vAng);
	GetClientEyePosition(client, vEye);
	if (GetVectorDistance(vEye, vPos, true) > (PROP_PICKUP_DISTANCE * PROP_PICKUP_DISTANCE))
		return;

	int health = GetEntProp(target, Prop_Data, "m_iHealth");
	int propOwner = GetPropOwner(target);
	// Keep a non-zero owner sentinel for orphaned props so repositioning them is
	// still treated as a move, not as a newly purchased/built prop.
	if (propOwner < 1 || propOwner > MaxClients)
		propOwner = client;

	PropId previousModel = ga_iModelIndex[client];
	int previousOwner = ga_iPropOwner[client];
	bool movingBatch = PrepareBatchMove(client, target);
	if (movingBatch && IsOtherPlayerStandingOnBatch(client, target)) {
		ClearBatchMove(client);
		PrintCenterText(client, "You cannot move the group while a player is standing on it.");
		return;
	}

	ga_iModelIndex[client] = view_as<PropId>(modelId);
	ga_iPropOwner[client] = propOwner;
	if (!CreateProp(client, vPos, vAng, health)) {
		ClearBatchMove(client);
		ga_iModelIndex[client] = previousModel;
		ga_iPropOwner[client] = previousOwner;
		return;
	}

	if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE) {
		ClearBatchMove(client);
		ga_iModelIndex[client] = previousModel;
		ga_iPropOwner[client] = previousOwner;
		return;
	}

	ClearPropSelections(client);
	if (movingBatch)
		movingBatch = StartBatchMovePreviews(client);
	if (!movingBatch) {
		ClearBatchMove(client);
		SafeKillIdx(target);
	}
	else
		RemoveBatchSourceProps(client, target);
}

static bool IsPlayerGroundedOnMattress(int client) {
	int groundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	return GetTrackedPropId(groundEntity) == MID(Prop_Mattress);
}

void OnButtonPress(int client, int button, float vel[3]) {
	if (button & BTN_JUMP) {
		float GameTime = GetGameTime();
		if (GameTime - ga_fPressedJumpTime[client] <= 1.0) {
			ga_fPressedJumpTime[client] = 0.0;
			ga_bMattressJumpArmed[client] = false;
		}
		else {
			ga_fPressedJumpTime[client] = GameTime;
			ga_bMattressJumpArmed[client] = IsPlayerGroundedOnMattress(client);
		}
	}

	if ((button & BTN_SPRINT) || (button & BTN_SPRINT_TOGGLE) || (button & BTN_ATTACK1)) {
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

						if (GetPropOwner(target) < 1)
							return;

						if (GetTrackedPropId(target) != MID(Prop_SandbagWall))
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
								hDatapack.WriteCell(GetClientUserId(client));
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
		if ((button & BTN_JUMP) || (button & BTN_DUCK) || (button & BTN_DUCK_TOGGLE) || (button & BTN_FORWARD) || (button & BTN_BACKWARD) || (button & BTN_LEFT) || (button & BTN_RIGHT)) {
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

	if (button & BTN_USE) {
		if (!ga_bHoldingMeleeWeapon[client])
			return;

		if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE) {
			if (GetClientButtons(client) & BTN_SPRINT) {
				PrintCenterText(client, "You can't pick up props while sprinting.");
				return;
			}
			
			int target = GetClientAimTarget(client, false);

			if (target <= MaxClients || !IsValidEntity(target))
				return;

			int modelId = GetTrackedPropId(target);
			if (modelId >= 0) {
				if (modelId == MID(Prop_AmmoCacheSmall))
					return;

				if (IsPlayerOnProp(client)) {
					PrintCenterText(client, "You cannot move props while standing on one.");
					return;
				}

				if (!IsPlayerOnGround(client))
					return;

				float vPos[3], vAng[3];
				GetEntPropVector(target, Prop_Send, "m_vecOrigin", vPos);
				GetEntPropVector(target, Prop_Send, "m_angRotation", vAng);

				float vEye[3];
				GetClientEyePosition(client, vEye);
				
				if (GetVectorDistance(vEye, vPos, true) > (PROP_PICKUP_DISTANCE * PROP_PICKUP_DISTANCE)) {
					PrintCenterText(client, "Too far away to pick up that prop.");
					return;
				}

				QueueExistingPropPickup(client, target);
			}
			return;
		}
		else {
			if (!(button & BTN_USE))
				return;
			if (ga_bJustPlaced[client])
				return;

			if (!BeginPlaceLock(client))
				return;

			if (!CanPlaceNow(client)) {
				EndPlaceLock(client);
				return;
			}

			int ent = EntRefToEntIndex(ga_iPropHolding[client]);
			if (ent <= MaxClients || !IsValidEntity(ent)) { EndPlaceLock(client); return; }

			if (vel[0] != 0.0 || vel[1] != 0.0 || vel[2] != 0.0) { EndPlaceLock(client); return; }

			float vAng[3];
			GetClientEyeAngles(client, vAng);
			float vPos[3];
			GetClientEyePosition(client, vPos);
			GetPositionInFront(vPos, vAng, PROP_HOLD_DISTANCE);

			float heldAngles[3];
			GetEntPropVector(ent, Prop_Send, "m_angRotation", heldAngles);
			if (!CanPreviewPlaceBatch(client, vPos, heldAngles, vel)) {
				PrintCenterText(client, "The prop group is too close to another player.");
				EndPlaceLock(client);
				return;
			}
			bool movingBatch = ga_hBatchMoveData[client] != null && ga_hBatchMoveData[client].Length > 0;
			bool holdingBlueprint = ga_bHoldingBlueprint[client];
			if (holdingBlueprint) {
				int blueprintCost = GetBlueprintHoldCost(client);
				if (blueprintCost < 0 || (g_iAllFree == 0 && !HasEnoughResources(client, blueprintCost))) {
					PrintCenterText(client, "You can no longer afford this blueprint.");
					EndPlaceLock(client);
					return;
				}
			}

			ga_bJustPlaced[client] = true;

			TeleportEntity(ent, vPos, NULL_VECTOR, NULL_VECTOR);

			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
			GetEntPropVector(ent, Prop_Send, "m_angRotation", vAng);

			int health = GetEntProp(ent, Prop_Data, "m_iHealth");
			bool movingExisting = ga_iPropOwner[client] > 0;
			StopHolding(client, false, movingBatch || holdingBlueprint);
			bool placed = CreateProp(client, vPos, vAng, health, true, holdingBlueprint);
			if (placed && holdingBlueprint)
				FinishBlueprintPlacement(client, vPos, vAng);
			else if (placed && movingBatch)
				FinishBatchMove(client, vPos, vAng);
			else {
				ClearBatchMove(client);
				ClearBlueprintHold(client);
			}

			EndPlaceLock(client);

			RequestFrame(ClearJustPlaced_NextFrame, GetClientSerial(client));

			PrintCenterText(client, "Prop: %d/%d", (ga_hPropPlaced[client] != null) ? ga_hPropPlaced[client].Length : 0, PROP_LIMIT);
			int selectedModelId = MID(ga_iModelIndex[client]);
			int selectedCost = g_PropDefs[selectedModelId].cost;
			if (placed && !holdingBlueprint && !movingBatch && !movingExisting)
				RecordRecentPropModel(client, selectedModelId);

			if (placed && !holdingBlueprint && !movingBatch && !movingExisting && (g_iAllFree == 1 || HasEnoughResources(client, selectedCost))) {
				DataPack pack;
				CreateDataTimer(0.10, Timer_RepeatSinglePropPlacement, pack, TIMER_FLAG_NO_MAPCHANGE);
				pack.WriteCell(GetClientSerial(client));
				pack.WriteCell(selectedModelId);
			}
		}
		return;
	}
}

static void RemoveIcon(int prop) {
	if (prop <= MaxClients || prop > MAXENTITIES)
		return;

	SafeKillRef(ga_iAmmoIconSpriteRef[prop]);
	SafeKillRef(ga_iAmmoIconHolderRef[prop]);

	ga_iAmmoIconSpriteRef[prop] = INVALID_ENT_REFERENCE;
	ga_iAmmoIconHolderRef[prop] = INVALID_ENT_REFERENCE;
}

public Action Hook_SetTransmit_AmmoIcon(int entity, int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Handled;

	float vOrigin[3];
	float vClient[3];

	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vOrigin);
	GetClientAbsOrigin(client, vClient);

	if (GetVectorDistance(vOrigin, vClient, true) > g_fAmmoResupplyRangeSqr)
		return Plugin_Handled;

	return Plugin_Continue;
}

static void CreateIcon(int prop) {
	if (prop <= MaxClients || prop > MAXENTITIES || !IsValidEntity(prop))
		return;

	RemoveIcon(prop);

	PrecacheModel(AMMO_ICON_SPRITE, true);

	float vPos[3];
	GetEntPropVector(prop, Prop_Send, "m_vecOrigin", vPos);

	float vSpritePos[3];
	vSpritePos[0] = vPos[0];
	vSpritePos[1] = vPos[1];
	vSpritePos[2] = vPos[2] + AMMO_ICON_ZOFFSET;

	// Holder isolates the sprite from any glow effects on the prop itself.
	int holder = CreateEntityByName("info_target");
	if (holder == -1)
		return;

	DispatchSpawn(holder);
	TeleportEntity(holder, vPos, NULL_VECTOR, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(holder, "SetParent", prop, holder);

	int sprite = CreateEntityByName("env_sprite");
	if (sprite == -1) {
		SafeKillIdx(holder);
		return;
	}

	DispatchKeyValue(sprite, "model", AMMO_ICON_SPRITE);
	DispatchKeyValue(sprite, "spawnflags", "1");
	DispatchKeyValue(sprite, "scale", "0.25");
	DispatchKeyValue(sprite, "rendermode", "1");
	DispatchKeyValue(sprite, "renderamt", "255");
	DispatchKeyValue(sprite, "rendercolor", "255 255 255");
	DispatchSpawn(sprite);

	TeleportEntity(sprite, vSpritePos, NULL_VECTOR, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(sprite, "SetParent", holder, sprite);

	SDKHook(sprite, SDKHook_SetTransmit, Hook_SetTransmit_AmmoIcon);

	ga_iAmmoIconHolderRef[prop] = EntIndexToEntRef(holder);
	ga_iAmmoIconSpriteRef[prop] = EntIndexToEntRef(sprite);
}

static void RebuildAmmoCacheIcons() {
	char name[64];

	if (g_hAmmoCacheRefs == null)
		g_hAmmoCacheRefs = new ArrayList();
	else
		g_hAmmoCacheRefs.Clear();

	if (g_hMattressRefs == null)
		g_hMattressRefs = new ArrayList();
	else
		g_hMattressRefs.Clear();

	for (int ent = MaxClients + 1; ent <= MAXENTITIES; ent++) {
		if (!IsValidEntity(ent))
			continue;

		GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
		if (StrContains(name, "bmprop_c#", true) == -1)
			continue;

		int owner = GetNumber(name, "_c#");
		int modelId = GetNumber(name, "_m#");
		if (owner < 1 || owner > MaxClients || modelId < 0 || modelId >= PROP_COUNT)
			continue;

		ga_iTrackedPropOwner[ent] = owner;
		ga_iTrackedPropId[ent] = modelId;

		if (ga_hPropPlaced[owner] != null)
			AddUniqueEntityRef(ga_hPropPlaced[owner], ent);

		if (modelId == MID(Prop_AmmoCacheSmall)) {
			AddUniqueEntityRef(g_hAmmoCacheRefs, ent);
			if (ga_iAmmoIconSpriteRef[ent] == INVALID_ENT_REFERENCE)
				CreateIcon(ent);
		}
		else if (modelId == MID(Prop_Mattress)) {
			AddUniqueEntityRef(g_hMattressRefs, ent);
		}
	}
}

static void UpdateAmmoRangeCache() {
	g_fAmmoResupplyRangeSqr = g_fAmmoResupplyRange * g_fAmmoResupplyRange;
}

static bool RefListContainsEntity(ArrayList list, int entity) {
	if (list == null || entity <= MaxClients)
		return false;

	for (int i = 0; i < list.Length; i++) {
		if (EntRefToEntIndex(list.Get(i)) == entity)
			return true;
	}
	return false;
}

static void AddUniqueEntityRef(ArrayList list, int entity) {
	if (list == null || entity <= MaxClients || !IsValidEntity(entity))
		return;

	if (!RefListContainsEntity(list, entity))
		list.Push(EntIndexToEntRef(entity));
}

static ArrayList EnsureUsedAmmoCacheList(int client) {
	if (client < 1 || client > MaxClients)
		return null;

	if (ga_hUsedAmmoCacheRefs[client] == null)
		ga_hUsedAmmoCacheRefs[client] = new ArrayList();

	return ga_hUsedAmmoCacheRefs[client];
}

static void RemoveEntityRef(ArrayList list, int entity) {
	if (list == null || entity <= MaxClients)
		return;

	for (int i = list.Length - 1; i >= 0; i--) {
		if (EntRefToEntIndex(list.Get(i)) == entity)
			list.Erase(i);
	}
}

static bool IsValidNonClientEntity(int entity) {
	return entity > MaxClients && entity <= MAXENTITIES && IsValidEntity(entity);
}

static void TrackSolidProp(int entity, int owner, PropId modelId) {
	if (entity <= MaxClients || entity > MAXENTITIES)
		return;

	ga_iTrackedPropOwner[entity] = owner;
	ga_iTrackedPropId[entity] = MID(modelId);

	if (modelId == Prop_AmmoCacheSmall)
		AddUniqueEntityRef(g_hAmmoCacheRefs, entity);
	else if (modelId == Prop_Mattress)
		AddUniqueEntityRef(g_hMattressRefs, entity);
}

static void UntrackSolidProp(int entity) {
	if (entity <= MaxClients || entity > MAXENTITIES)
		return;

	RemoveEntityRef(g_hAmmoCacheRefs, entity);
	RemoveEntityRef(g_hMattressRefs, entity);
	ga_iTrackedPropOwner[entity] = 0;
	ga_iTrackedPropId[entity] = -1;
	ga_bPropHalfHpWarned[entity] = false;
}

static int GetTrackedPropId(int entity) {
	if (entity <= MaxClients || entity > MAXENTITIES)
		return -1;

	int trackedId = ga_iTrackedPropId[entity];
	if (trackedId >= 0 && trackedId < PROP_COUNT)
		return trackedId;

	if (!IsValidEntity(entity))
		return -1;

	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));
	if (StrContains(sName, "bmprop_c#", false) == -1)
		return -1;

	int modelId = GetNumber(sName, "_m#");
	if (modelId < 0 || modelId >= PROP_COUNT)
		return -1;

	ga_iTrackedPropId[entity] = modelId;
	return modelId;
}

static bool PropIdBlocksExplosion(int modelId) {
	return (modelId >= 0 && modelId < PROP_COUNT) ? g_PropDefs[modelId].blocksExplosive : false;
}

static bool HasUsedAmmoCache(int client, int entity) {
	ArrayList list = EnsureUsedAmmoCacheList(client);
	if (list == null || entity <= MaxClients)
		return false;

	for (int i = list.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(list.Get(i));
		if (ent <= MaxClients || !IsValidEntity(ent)) {
			list.Erase(i);
			continue;
		}

		if (ent == entity)
			return true;
	}
	return false;
}

static void MarkAmmoCacheUsed(int client, int entity) {
	ArrayList list = EnsureUsedAmmoCacheList(client);
	if (list == null || entity <= MaxClients || !IsValidEntity(entity))
		return;

	AddUniqueEntityRef(list, entity);
}

static void UpdateClientWeaponState(int client, int entity = -1) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	if (entity == -1)
		entity = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	ga_bHoldingMeleeWeapon[client] = (entity > 0 && GetPlayerWeaponSlot(client, 2) == entity);
}

bool CreateProp(int client, float vPos[3], float vAng[3], int oldhealth = 0, bool solid = false, bool usePlacementAngles = false) {
	if (!IsPlayerOnGround(client)) {
		PrintCenterText(client, "You cannot build a prop while falling!");
		return false;
	}

	bool bMovingExisting = (ga_iPropOwner[client] > 0);

	PropId modelId = ga_iModelIndex[client];
	int mid = MID(modelId);
	int buildCost = (g_iAllFree == 1) ? 0 : g_PropDefs[mid].cost;

	if (!ga_iPropOwner[client] && !HasEnoughResources(client, buildCost)) {
		if (solid) {
			PrintCenterText(client, "You don't have enough resources to build. Press 'Cycle Firemode' to open the shop menu.");
			return false;
		} else if (SetModelIndex(client)) {
			modelId = ga_iModelIndex[client];
			mid = MID(modelId);
			buildCost = g_PropDefs[mid].cost;
		} else {
			PrintCenterText(client, "You don't have enough resources to build. Press 'Cycle Firemode' to open the shop menu.");
			return false;
		}
	}

	int prop = CreateEntityByName("prop_dynamic_override");
	if (prop == -1) {
		PrintCenterText(client, "Failed to create prop.");
		return false;
	}

	bool bDoAmmoGlowAndIcon = false;
	bool bDoJammerGlow = false;
	int trackedOwner = 0;

	DispatchKeyValue(prop, "physdamagescale", "0.0");
	DispatchKeyValue(prop, "model", g_PropDefs[mid].model);

	if (solid) {
		char PropName[64];
		DispatchKeyValue(prop, "solid", "6");

		if (!ga_iPropOwner[client]) {
			if (g_iAllFree != 1) {
				int buildCostActual = g_PropDefs[mid].cost;
				if (!HasEnoughResources(client, buildCostActual)) {
					PrintCenterText(client, "Not enough resources.");
					SafeKillIdx(prop);
					return false;
				}
				ga_iPlayerBuildPoints[client] -= buildCostActual;
			}

			ClearOldestPropIfLimitReached(client);

			if (ga_hPropPlaced[client] == null)
				ga_hPropPlaced[client] = new ArrayList();

			ga_hPropPlaced[client].Push(EntIndexToEntRef(prop));
			FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", client, mid);
			trackedOwner = client;
		} else {
			if (ga_hPropPlaced[ga_iPropOwner[client]] != null) {
				ga_hPropPlaced[ga_iPropOwner[client]].Push(EntIndexToEntRef(prop));
				FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", ga_iPropOwner[client], mid);
				trackedOwner = ga_iPropOwner[client];
			} else {
				ClearOldestPropIfLimitReached(client);

				if (ga_hPropPlaced[client] == null)
					ga_hPropPlaced[client] = new ArrayList();

				ga_hPropPlaced[client].Push(EntIndexToEntRef(prop));
				FormatEx(PropName, sizeof(PropName), "bmprop_c#%d_m#%d", client, mid);
				oldhealth = 0;
				trackedOwner = client;
			}
			ga_iPropOwner[client] = 0;
		}

		switch (modelId) {
			case Prop_AmmoCacheSmall: {
				bDoAmmoGlowAndIcon = true;
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			}
			case Prop_IedJammer: {
				bDoJammerGlow = true;
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			}
			case Prop_BarbWire: {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchWire);
			}
			case Prop_Mattress: {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchMattress);
			}
			case Prop_MarketPrisonDoor: {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchSecurityDoor);
			}
			default: {
				SDKHook(prop, SDKHook_Touch, SHook_OnTouchPropTakeDamage);
			}
		}

		DispatchKeyValue(prop, "targetname", PropName);
		SDKHook(prop, SDKHook_OnTakeDamage, PropOnTakeDamage);
	} else {
		DispatchKeyValue(prop, "solid", "0");
		DispatchKeyValue(prop, "disableshadows", "1");
		DispatchKeyValue(prop, "disableshadowdepth", "1");

		SetEntityRenderMode(prop, RENDER_TRANSCOLOR);
		SetEntityRenderColor(prop, 255, 255, 255, PROP_ALPHA);

		ga_iPropHolding[client] = EntIndexToEntRef(prop);
		TouchLaggedMovementValue(client);
	}

	DispatchSpawn(prop);

	if (solid)
		TrackSolidProp(prop, trackedOwner, modelId);

	if (solid) {
		if (!bMovingExisting && !usePlacementAngles)
			TeleportEntity(prop, vPos, ga_fPropRotations[client][mid], NULL_VECTOR);
		else
			TeleportEntity(prop, vPos, vAng, NULL_VECTOR);

		if (ga_bPropRotateMenuOpen[client]) {
			ClientCommand(client, "slot9");
			ga_bPropRotateMenuOpen[client] = false;
		}
	} else {
		if (bMovingExisting) {
			char modelName[64];
			GetModelName(g_PropDefs[mid].model, modelName, sizeof(modelName));

			int maxHealth = g_PropDefs[mid].health;
			if (maxHealth < 1)
				maxHealth = PROP_HEALTH;

			int hp = (oldhealth > 0) ? oldhealth : maxHealth;
			if (hp > maxHealth)
				hp = maxHealth;
			else if (hp < 0)
				hp = 0;

			ga_iHoldHp[client] = hp;
			ga_iHoldMaxHp[client] = maxHealth;

			TeleportEntity(prop, vPos, vAng, NULL_VECTOR);

			int mattressStack = 0;
			float mattressBoost = MATTRESS_BASE_BOOST;
			if (modelId == Prop_Mattress) {
				mattressStack = CountMattressStackNearPosition(vPos);
				if (mattressStack < 1)
					mattressStack = 1;
				if (mattressStack > MATTRESS_MAX_STACK_COUNT)
					mattressStack = MATTRESS_MAX_STACK_COUNT;
				mattressBoost = GetMattressStackBoost(mattressStack);
			}

			int owner = ga_iPropOwner[client];
			if (owner >= 1 && owner <= MaxClients && IsClientInGame(owner)) {
				if (mattressStack > 1)
					PrintCenterText(client, "%s built by: %N\nHealth: %d/%d\nStack x%d - boost %.0f", modelName, owner, hp, maxHealth, mattressStack, mattressBoost);
				else
					PrintCenterText(client, "%s built by: %N\nHealth: %d/%d", modelName, owner, hp, maxHealth);
				OpenRotationMenu(client);
			} else {
				if (mattressStack > 1)
					PrintCenterText(client, "%s\nHealth: %d/%d\nStack x%d - boost %.0f", modelName, hp, maxHealth, mattressStack, mattressBoost);
				else
					PrintCenterText(client, "%s\nHealth: %d/%d", modelName, hp, maxHealth);
			}
		} else {
			TeleportEntity(prop, vPos, ga_fPropRotations[client][mid], NULL_VECTOR);
		}
	}

	SetEntityMoveType(prop, MOVETYPE_NONE);
	SetEntProp(prop, Prop_Data, "m_takedamage", DAMAGE_YES);

	int maxHealth = g_PropDefs[mid].health;
	if (maxHealth < 1)
		maxHealth = PROP_HEALTH;

	SetEntProp(prop, Prop_Data, "m_iMaxHealth", maxHealth);

	if (oldhealth > 0) {
		if (oldhealth > maxHealth)
			oldhealth = maxHealth;

		SetEntProp(prop, Prop_Data, "m_iHealth", oldhealth);
		GlowLowHp(prop, oldhealth);
	} else {
		SetEntProp(prop, Prop_Data, "m_iHealth", maxHealth);
	}

	if (!solid && ga_iPropHolding[client] != INVALID_ENT_REFERENCE && EntRefToEntIndex(ga_iPropHolding[client]) == prop) {
		ga_iHoldHp[client] = GetEntProp(prop, Prop_Data, "m_iHealth");
		ga_iHoldMaxHp[client] = maxHealth;
	}

	if (bDoAmmoGlowAndIcon) {
		int col[4];
		col[0] = 255;
		col[1] = 255;
		col[2] = 102;
		col[3] = 255;

		SetVariantColor(col);
		SetEntityRenderMode(prop, RENDER_NORMAL);
		SetEntityRenderColor(prop, 255, 255, 255, 255);
		AcceptEntityInput(prop, "SetGlowColor");
		SetEntProp(prop, Prop_Send, "m_bShouldGlow", true);
		SetEntPropFloat(prop, Prop_Send, "m_flGlowMaxDist", 4000.0);

		CreateIcon(prop);
	}

	if (bDoJammerGlow) {
		int col[4];
		col[0] = 80;
		col[1] = 210;
		col[2] = 255;
		col[3] = 255;

		SetVariantColor(col);
		SetEntityRenderMode(prop, RENDER_NORMAL);
		AcceptEntityInput(prop, "SetGlowColor");
		SetEntProp(prop, Prop_Send, "m_bShouldGlow", true);
		SetEntPropFloat(prop, Prop_Send, "m_flGlowMaxDist", 600.0);

		JC_AddJammer(prop);
	}

	// A moved prop is recreated internally, so only log genuinely new builds.
	if (solid && !bMovingExisting)
		LogPropBuild(client, modelId);

	return true;
}

static void LogPropBuild(int client, PropId modelId) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	char action[32];
	switch (modelId) {
		case Prop_BarbWire:          strcopy(action, sizeof(action), "build_wire");
		case Prop_SandbagWall:       strcopy(action, sizeof(action), "build_sandbag");
		case Prop_TWall:             strcopy(action, sizeof(action), "build_twall");
		case Prop_HescoBasket:       strcopy(action, sizeof(action), "build_hesco");
		case Prop_PanjStairs:        strcopy(action, sizeof(action), "build_stairs");
		case Prop_Mattress:          strcopy(action, sizeof(action), "build_mattress");
		case Prop_ContainerOpen2:    strcopy(action, sizeof(action), "build_container");
		case Prop_EmbassyCenter02:   strcopy(action, sizeof(action), "build_embassy");
		case Prop_IedJammer:         strcopy(action, sizeof(action), "build_jammer");
		case Prop_AmmoCacheSmall:    strcopy(action, sizeof(action), "build_cache");
		default:                     strcopy(action, sizeof(action), "build_prop");
	}

	LogToGame("\"%L\" triggered \"%s\"", client, action);
}

void ClearOldestPropIfLimitReached(int client) {
	ArrayList list = ga_hPropPlaced[client];
	if (list == null)
		return;

	while (list.Length >= PROP_LIMIT) {
		int ref = list.Get(0);
		int ent = EntRefToEntIndex(ref);
		if (ent > MaxClients && IsValidEntity(ent)) {
			DispatchKeyValue(ent, "targetname", "bmprop_deleted");
			SafeKillRef(ref);
		}
		list.Erase(0);
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

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch) || GetClientTeam(touch) != TEAM_INSURGENT)
		return Plugin_Continue;

	float GameTime = GetGameTime();
	if (ga_fLastTouchTime[touch] > GameTime)
		return Plugin_Continue;

	ga_fLastTouchTime[touch] = GameTime + PROP_TOUCH_COOLDOWN;
	DoDamageToEnt(entity, touch);
	return Plugin_Continue;
}

public Action SHook_OnTouchSecurityDoor(int entity, int touch) {
	if (touch < 1 || touch > MaxClients || !IsClientInGame(touch) || !IsPlayerAlive(touch))
		return Plugin_Continue;

	if (IsFakeClient(touch) || GetClientTeam(touch) != TEAM_SECURITY) {
		if (GetClientTeam(touch) == TEAM_INSURGENT) {
			float gameTime = GetGameTime();
			if (ga_fLastTouchTime[touch] <= gameTime) {
				ga_fLastTouchTime[touch] = gameTime + PROP_TOUCH_COOLDOWN;
				DoDamageToEnt(entity, touch);
				if (ga_fSecurityDoorImpactSound[entity] <= gameTime) {
					ga_fSecurityDoorImpactSound[entity] = gameTime + SECURITY_DOOR_IMPACT_SOUND_COOLDOWN;
					PlaySecurityDoorSound(entity, SECURITY_DOOR_IMPACT_SOUND);
				}
			}
		}
		return Plugin_Continue;
	}
	if (IsAnyPlayerStandingOnEntity(entity))
		return Plugin_Continue;

	float gameTime = GetGameTime();
	if (ga_fSecurityDoorNextTouch[entity] > gameTime)
		return Plugin_Continue;

	ga_fSecurityDoorNextTouch[entity] = gameTime + SECURITY_DOOR_TOUCH_COOLDOWN;
	if (ga_bSecurityDoorOpen[entity]) {
		ScheduleSecurityDoorClose(entity, SECURITY_DOOR_CLOSE_DELAY);
		return Plugin_Continue;
	}

	float closedOrigin[3];
	float doorAngles[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", closedOrigin);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", doorAngles);

	float playerOrigin[3];
	float right[3];
	GetClientAbsOrigin(touch, playerOrigin);
	GetAngleVectors(doorAngles, NULL_VECTOR, right, NULL_VECTOR);

	float playerOffsetX = playerOrigin[0] - closedOrigin[0];
	float playerOffsetY = playerOrigin[1] - closedOrigin[1];
	float firstDirection = ((playerOffsetX * right[0]) + (playerOffsetY * right[1]) >= 0.0) ? -1.0 : 1.0;
	float slideDistance = GetSecurityDoorSlideDistance(entity);

	for (int i = 0; i < 2; i++) {
		float direction = (i == 0) ? firstDirection : -firstDirection;
		float openOrigin[3];
		openOrigin[0] = closedOrigin[0] + (right[0] * slideDistance * direction);
		openOrigin[1] = closedOrigin[1] + (right[1] * slideDistance * direction);
		openOrigin[2] = closedOrigin[2];

		if (GetVectorDistance(openOrigin, closedOrigin, true) < 1.0)
			continue;
		if (SecurityDoorWouldTrapPlayer(entity, openOrigin))
			continue;

		ga_fSecurityDoorClosedOrigin[entity][0] = closedOrigin[0];
		ga_fSecurityDoorClosedOrigin[entity][1] = closedOrigin[1];
		ga_fSecurityDoorClosedOrigin[entity][2] = closedOrigin[2];
		ga_bSecurityDoorOpen[entity] = true;
		TeleportEntity(entity, openOrigin, NULL_VECTOR, NULL_VECTOR);
		PlaySecurityDoorSound(entity, SECURITY_DOOR_OPEN_SOUND, SECURITY_DOOR_MOVE_VOLUME);
		ScheduleSecurityDoorClose(entity, SECURITY_DOOR_CLOSE_DELAY);
		break;
	}

	return Plugin_Continue;
}

static bool SecurityDoorWouldTrapPlayer(int entity, const float doorOrigin[3]) {
	float doorMins[3], doorMaxs[3];
	if (!GetSecurityDoorBounds(entity, doorMins, doorMaxs))
		return SecurityDoorWouldTrapPlayerCircular(entity, doorOrigin);

	float doorAngles[3];
	GetEntPropVector(entity, Prop_Send, "m_angRotation", doorAngles);

	float axisForward[3], axisRight[3], axisUp[3];
	GetAngleVectors(doorAngles, axisForward, axisRight, axisUp);

	return SecurityDoorBoxWouldTrapAnyPlayer(doorOrigin, doorMins, doorMaxs, axisForward, axisRight, axisUp);
}

static bool GetSecurityDoorBounds(int entity, float mins[3], float maxs[3]) {
	if (!HasEntProp(entity, Prop_Send, "m_vecMins") || !HasEntProp(entity, Prop_Send, "m_vecMaxs"))
		return false;

	GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
	float doorWidth = maxs[1] - mins[1];
	mins[1] += doorWidth;
	maxs[1] += doorWidth;
	return true;
}

static bool SecurityDoorBoxWouldTrapAnyPlayer(const float doorOrigin[3], const float doorMins[3], const float doorMaxs[3], const float axisForward[3], const float axisRight[3], const float axisUp[3]) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (SecurityDoorBoxWouldTrapPlayer(client, doorOrigin, doorMins, doorMaxs, axisForward, axisRight, axisUp))
			return true;
	}
	return false;
}

static float GetSecurityDoorSlideDistance(int entity) {
	float doorMins[3], doorMaxs[3];
	if (!GetSecurityDoorBounds(entity, doorMins, doorMaxs))
		return SECURITY_DOOR_SLIDE_DISTANCE_FALLBACK;

	float slideDistance = FloatAbs(doorMaxs[1] - doorMins[1]);
	return (slideDistance > 0.0) ? slideDistance : SECURITY_DOOR_SLIDE_DISTANCE_FALLBACK;
}

static bool SecurityDoorBoxWouldTrapPlayer(int client, const float doorOrigin[3], const float doorMins[3], const float doorMaxs[3], const float axisForward[3], const float axisRight[3], const float axisUp[3]) {
	float playerOrigin[3], playerMins[3], playerMaxs[3], playerCenter[3];
	GetClientAbsOrigin(client, playerOrigin);
	GetClientMins(client, playerMins);
	GetClientMaxs(client, playerMaxs);
	for (int axis = 0; axis < 3; axis++)
		playerCenter[axis] = playerOrigin[axis] + ((playerMins[axis] + playerMaxs[axis]) * 0.5);

	float relative[3];
	relative[0] = playerCenter[0] - doorOrigin[0];
	relative[1] = playerCenter[1] - doorOrigin[1];
	relative[2] = playerCenter[2] - doorOrigin[2];

	float playerExtentX = (playerMaxs[0] - playerMins[0]) * 0.5;
	float playerExtentY = (playerMaxs[1] - playerMins[1]) * 0.5;
	float playerExtentZ = (playerMaxs[2] - playerMins[2]) * 0.5;
	float localX = (relative[0] * axisForward[0]) + (relative[1] * axisForward[1]) + (relative[2] * axisForward[2]);
	float localY = (relative[0] * axisRight[0]) + (relative[1] * axisRight[1]) + (relative[2] * axisRight[2]);
	float localZ = (relative[0] * axisUp[0]) + (relative[1] * axisUp[1]) + (relative[2] * axisUp[2]);
	float expandX = (FloatAbs(axisForward[0]) * playerExtentX) + (FloatAbs(axisForward[1]) * playerExtentY) + (FloatAbs(axisForward[2]) * playerExtentZ);
	float expandY = (FloatAbs(axisRight[0]) * playerExtentX) + (FloatAbs(axisRight[1]) * playerExtentY) + (FloatAbs(axisRight[2]) * playerExtentZ);
	float expandZ = (FloatAbs(axisUp[0]) * playerExtentX) + (FloatAbs(axisUp[1]) * playerExtentY) + (FloatAbs(axisUp[2]) * playerExtentZ);

	if (localX < doorMins[0] - expandX || localX > doorMaxs[0] + expandX)
		return false;
	if (localY < doorMins[1] - expandY || localY > doorMaxs[1] + expandY)
		return false;
	if (localZ < doorMins[2] - expandZ || localZ > doorMaxs[2] + expandZ)
		return false;

	return true;
}

static bool SecurityDoorWouldTrapPlayerCircular(int entity, const float doorOrigin[3]) {
	float clearance = GetSecurityDoorPlayerClearance(entity);
	float clearanceSqr = clearance * clearance;
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (SecurityDoorCircularWouldTrapPlayer(client, doorOrigin, clearanceSqr))
			return true;
	}
	return false;
}

static bool SecurityDoorCircularWouldTrapPlayer(int client, const float doorOrigin[3], float clearanceSqr) {
	float playerOrigin[3];
	GetClientAbsOrigin(client, playerOrigin);
	if (FloatAbs(playerOrigin[2] - doorOrigin[2]) > 128.0)
		return false;

	float offsetX = playerOrigin[0] - doorOrigin[0];
	float offsetY = playerOrigin[1] - doorOrigin[1];
	return (offsetX * offsetX) + (offsetY * offsetY) < clearanceSqr;
}

static float GetSecurityDoorPlayerClearance(int entity) {
	float mins[3], maxs[3];
	if (!GetSecurityDoorBounds(entity, mins, maxs))
		return GetSecurityDoorSlideDistance(entity);

	float horizontalX = FloatAbs(mins[0]);
	float horizontalY = FloatAbs(mins[1]);
	if (FloatAbs(maxs[0]) > horizontalX)
		horizontalX = FloatAbs(maxs[0]);
	if (FloatAbs(maxs[1]) > horizontalY)
		horizontalY = FloatAbs(maxs[1]);

	return SquareRoot((horizontalX * horizontalX) + (horizontalY * horizontalY)) + SECURITY_DOOR_PLAYER_HULL_RADIUS;
}

static bool IsAnyPlayerStandingOnEntity(int entity) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;
		if (GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == entity)
			return true;
	}
	return false;
}

static void ScheduleSecurityDoorClose(int entity, float delay) {
	if (ga_hSecurityDoorCloseTimer[entity] != INVALID_HANDLE)
		KillTimer(ga_hSecurityDoorCloseTimer[entity]);

	ga_hSecurityDoorCloseTimer[entity] = CreateTimer(delay, Timer_CloseSecurityDoor, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CloseSecurityDoor(Handle timer, int doorRef) {
	int entity = EntRefToEntIndex(doorRef);
	if (!IsValidNonClientEntity(entity) || ga_hSecurityDoorCloseTimer[entity] != timer)
		return Plugin_Stop;

	ga_hSecurityDoorCloseTimer[entity] = INVALID_HANDLE;
	if (!ga_bSecurityDoorOpen[entity])
		return Plugin_Stop;

	if (SecurityDoorWouldTrapPlayer(entity, ga_fSecurityDoorClosedOrigin[entity])) {
		ScheduleSecurityDoorClose(entity, SECURITY_DOOR_CLOSE_RETRY);
		return Plugin_Stop;
	}

	TeleportEntity(entity, ga_fSecurityDoorClosedOrigin[entity], NULL_VECTOR, NULL_VECTOR);
	ga_bSecurityDoorOpen[entity] = false;
	PlaySecurityDoorSound(entity, SECURITY_DOOR_CLOSE_SOUND, SECURITY_DOOR_MOVE_VOLUME);
	return Plugin_Stop;
}

static void PlaySecurityDoorSound(int entity, const char[] sound, float volume = SNDVOL_NORMAL) {
	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	EmitAmbientSound(sound, origin, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, SND_NOFLAGS, volume);
}

void DoDamageToEnt(int entity, int client) {
	SDKHooks_TakeDamage(entity, client, client, PROP_DAMAGE_TAKE, DMG_SLASH, -1, NULL_VECTOR, NULL_VECTOR, false);
}

static int CountMattressStackNearPosition(const float origin[3], int ignoreEnt = 0) {
	int count = 0;
	float pos[3];
	float radiusSqr = MATTRESS_STACK_RADIUS * MATTRESS_STACK_RADIUS;

	if (g_hMattressRefs == null)
		return 0;

	for (int i = g_hMattressRefs.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(g_hMattressRefs.Get(i));
		if (!IsValidNonClientEntity(ent) || GetTrackedPropId(ent) != MID(Prop_Mattress)) {
			g_hMattressRefs.Erase(i);
			continue;
		}
		if (ent == ignoreEnt)
			continue;

		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
		float dx = pos[0] - origin[0];
		float dy = pos[1] - origin[1];
		if ((dx * dx) + (dy * dy) > radiusSqr)
			continue;
		float zGap = FloatAbs(pos[2] - origin[2]);
		if (zGap < MATTRESS_STACK_MIN_Z_GAP || zGap > MATTRESS_STACK_Z_RANGE)
			continue;

		count++;
		if (count >= MATTRESS_MAX_STACK_COUNT)
			return MATTRESS_MAX_STACK_COUNT;
	}

	return count;
}

static int CountMattressStack(int entity) {
	if (!IsValidNonClientEntity(entity))
		return 1;

	float origin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);

	int count = 1 + CountMattressStackNearPosition(origin, entity);
	if (count > MATTRESS_MAX_STACK_COUNT)
		count = MATTRESS_MAX_STACK_COUNT;

	return count;
}

static float GetMattressStackBoost(int stackCount) {
	if (stackCount < 1)
		stackCount = 1;
	if (stackCount > MATTRESS_MAX_STACK_COUNT)
		stackCount = MATTRESS_MAX_STACK_COUNT;

	return MATTRESS_BASE_BOOST + (float(stackCount - 1) * MATTRESS_STACK_BONUS);
}

static float GetMattressAutoRebounceTime(int stackCount) {
	if (stackCount < 1)
		stackCount = 1;
	if (stackCount > MATTRESS_MAX_STACK_COUNT)
		stackCount = MATTRESS_MAX_STACK_COUNT;

	return MATTRESS_AUTO_REBOUNCE_BASE + (float(stackCount - 1) * MATTRESS_AUTO_REBOUNCE_STACK_BONUS);
}

static bool IsMattressBounceContact(int mattress, int touch) {
	if (mattress != GetEntPropEnt(touch, Prop_Send, "m_hGroundEntity"))
		return false;
	if (GetEntProp(touch, Prop_Send, "m_iCurrentStance") != 0)
		return false;
	if (IsFakeClient(touch))
		return true;

	return ga_bMattressJumpArmed[touch];
}

static void ApplyMattressBoost(int client, int mattress, float boost, float anglePushScale = 1.0) {
	float velocity[3], ang[3], vecForward[3], vecRight[3], vecUp[3];
	velocity[0] = 0.0;
	velocity[1] = 0.0;
	velocity[2] = boost;

	if (IsValidNonClientEntity(mattress)) {
		GetEntPropVector(mattress, Prop_Send, "m_angRotation", ang);
		GetAngleVectors(ang, vecForward, vecRight, vecUp);

		if (vecUp[2] < 0.0) {
			vecUp[0] = -vecUp[0];
			vecUp[1] = -vecUp[1];
			vecUp[2] = -vecUp[2];
		}

		float horizontal[3];
		horizontal[0] = vecUp[0];
		horizontal[1] = vecUp[1];
		horizontal[2] = 0.0;

		float horizontalLen = GetVectorLength(horizontal);
		if (horizontalLen > 0.001) {
			NormalizeVector(horizontal, horizontal);

			float horizontalSpeed = boost * MATTRESS_ANGLE_PUSH_FRACTION * anglePushScale * horizontalLen;
			if (horizontalSpeed > MATTRESS_HORIZONTAL_MAX)
				horizontalSpeed = MATTRESS_HORIZONTAL_MAX;

			velocity[0] = horizontal[0] * horizontalSpeed;
			velocity[1] = horizontal[1] * horizontalSpeed;
		}
	}

	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", velocity);
}

public Action SHook_OnTouchMattress(int entity, int touch) {
	if (touch < 1 || touch > MaxClients)
		return Plugin_Continue;

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch))
		return Plugin_Continue;

	float GameTime = GetGameTime();
	if (ga_fLastTouchTime[touch] > GameTime)
		return Plugin_Continue;

	if (IsMattressBounceContact(entity, touch)) {
		int stackCount = CountMattressStack(entity);
		float boost = GetMattressStackBoost(stackCount);

		if (!IsFakeClient(touch)) {
			if (GameTime - ga_fPressedJumpTime[touch] <= 1.0) {
				ga_fPressedJumpTime[touch] = GameTime + GetMattressAutoRebounceTime(stackCount);
				ga_bMattressJumpArmed[touch] = true;
				ApplyMattressBoost(touch, entity, boost, MATTRESS_HUMAN_ANGLE_PUSH_SCALE);
				PlayWireSound(entity);

				if (stackCount > 1)
					PrintCenterText(touch, "Mattress stack x%d\nLaunch boost: %.0f", stackCount, boost);
			}
		}
		else {
			ApplyMattressBoost(touch, entity, boost);
			PlayWireSound(entity);
			DoDamageToEnt(entity, touch);
		}

		int propOwner = GetPropOwner(entity);
		if (propOwner > 0 && IsClientInGame(propOwner)) {
			ga_iLastMattressOwner[touch] = propOwner;
			ga_fLastMattressLaunchTime[touch] = GameTime;
		}
		else {
			ga_iLastMattressOwner[touch] = 0;
			ga_fLastMattressLaunchTime[touch] = 0.0;
		}
	}

	ga_fLastTouchTime[touch] = GameTime + PROP_TOUCH_COOLDOWN;
	return Plugin_Continue;
}

static bool ShouldFlashHalfHp(int entity, int currentHealth, float damage) {
	if (!IsValidNonClientEntity(entity) || entity > MAXENTITIES || ga_bPropHalfHpWarned[entity])
		return false;

	int maxHealth = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
	if (maxHealth <= 0)
		maxHealth = PROP_HEALTH;

	if (currentHealth <= 0)
		return false;
	if ((float(currentHealth) / float(maxHealth)) <= PROP_HALFHP_PERCENT)
		return false;

	int predictedHealth = currentHealth - RoundToCeil(damage);
	if (predictedHealth < 0)
		predictedHealth = 0;

	return (float(predictedHealth) / float(maxHealth)) <= PROP_HALFHP_PERCENT;
}

static void FlashPropHalfHp(int entity) {
	if (!IsValidNonClientEntity(entity) || entity > MAXENTITIES)
		return;

	ga_bPropHalfHpWarned[entity] = true;
	SetEntityRenderColor(entity, 255, 220, 0, 255);
	CreateTimer(PROP_HALFHP_FLASH_TIME, Timer_RestorePropHalfHpFlash, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RestorePropHalfHpFlash(Handle timer, int entityRef) {
	int entity = EntRefToEntIndex(entityRef);
	if (!IsValidNonClientEntity(entity))
		return Plugin_Stop;

	int health = GetEntProp(entity, Prop_Data, "m_iHealth");
	if (IsMattressHighlightedByAnyClient(entity))
		return Plugin_Stop;
	if (!GlowLowHp(entity, health))
		SetEntityRenderColor(entity, 255, 255, 255, 255);

	return Plugin_Stop;
}

public Action SHook_OnTouchWire(int entity, int touch) {
	if (touch < 1 || touch > MaxClients)
		return Plugin_Continue;

	if (!IsClientInGame(touch) || !IsPlayerAlive(touch) || GetClientTeam(touch) != TEAM_INSURGENT)
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
	if (entity > 0 && entity <= MAXENTITIES && IsValidEntity(entity)) {
		float vPos[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vPos);
		EmitAmbientSound(ga_sBarbWire[GetRandomInt(0, NUM_WIRESOUNDS - 1)], vPos);
	}
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
	SafeKillRef(particleRef);
	return Plugin_Stop;
}

public Action PropOnTakeDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (GetTrackedPropId(entity) == MID(Prop_MarketPrisonDoor)
		&& attacker >= 1
		&& attacker <= MaxClients
		&& IsClientInGame(attacker)
		&& GetClientTeam(attacker) == TEAM_SECURITY) {
		return Plugin_Handled;
	}

	int health = GetEntProp(entity, Prop_Data, "m_iHealth");
	if (ShouldFlashHalfHp(entity, health, damage))
		FlashPropHalfHp(entity);

	if (GlowLowHp(entity, health))
		SDKUnhook(entity, SDKHook_OnTakeDamage, PropOnTakeDamage);
	return Plugin_Continue;
}

public Action BotOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (IsValidNonClientEntity(inflictor)) {
		ga_iLastInflictor[victim] = EntIndexToEntRef(inflictor);
		ga_iLastInflictorPropId[victim] = GetTrackedPropId(inflictor);
	}
	else {
		ga_iLastInflictor[victim] = INVALID_ENT_REFERENCE;
		ga_iLastInflictorPropId[victim] = -1;
	}

	ga_bMattressDeath[victim] = false;
	ga_iMattressKiller[victim] = 0;

	if (damagetype & DMG_FALL) {
		int owner = ga_iLastMattressOwner[victim];

		if (owner > 0 && IsClientInGame(owner)) {
			float now = GetGameTime();

			if (GetClientTeam(victim) == TEAM_INSURGENT && GetClientTeam(owner) != GetClientTeam(victim) && (now - ga_fLastMattressLaunchTime[victim] <= MATTRESS_FALL_WINDOW)) {
				ga_bMattressDeath[victim] = true;
				ga_iMattressKiller[victim] = owner;
				attacker = owner;
				inflictor = 0;
			}
		}
	}
	return Plugin_Continue;
}

public Action PlayerOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (damagetype & DMG_FALL) {
		int groundEntity = GetEntPropEnt(victim, Prop_Send, "m_hGroundEntity");
		if (GetTrackedPropId(groundEntity) == MID(Prop_Mattress)) {
			PrintCenterText(victim, "Mattress cushioned your fall!");
			return Plugin_Handled;
		}
	}

	if ((damagetype & DMG_BLAST) && IsValidNonClientEntity(inflictor)) {
		float vStart[3], vEnd[3];
		GetClientEyePosition(victim, vStart);
		GetEntPropVector(inflictor, Prop_Data, "m_vecAbsOrigin", vEnd);

		Handle trace = TR_TraceRayFilterEx(vStart, vEnd, MASK_SOLID, RayType_EndPoint, TraceEntityFilterPlayers, victim);
		if (TR_DidHit(trace)) {
			float frac = TR_GetFraction(trace);
			if (TR_StartSolid(trace) || TR_AllSolid(trace) || frac <= 0.02) {
				CloseHandle(trace);
				return Plugin_Continue;
			}

			int hitEnt = TR_GetEntityIndex(trace);
			if (hitEnt != victim && IsValidNonClientEntity(hitEnt)) {
				int hitPropId = GetTrackedPropId(hitEnt);
				if (!PropIdBlocksExplosion(hitPropId)) {
					CloseHandle(trace);
					return Plugin_Continue;
				}

				char shortName[64];
				GetModelName(g_PropDefs[hitPropId].model, shortName, sizeof(shortName));
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

bool GlowLowHp(int entity, int health) {
	int maxHealth = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
	if (maxHealth <= 0)
		maxHealth = PROP_HEALTH;

	float healthPercentage = float(health) / float(maxHealth);
	if (healthPercentage <= PROP_GLOWHP_PERCENT) {
		SetEntityRenderColor(entity, 255, 0, 0, PROP_ALPHA);
		return true;
	}
	return false;
}

public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients || entity > MAXENTITIES)
		return;

	ga_fSecurityDoorNextTouch[entity] = 0.0;
	ga_fSecurityDoorImpactSound[entity] = 0.0;
	ga_bSecurityDoorOpen[entity] = false;
	ga_hSecurityDoorCloseTimer[entity] = INVALID_HANDLE;

	int trackedPropId = GetTrackedPropId(entity);
	JC_RemoveJammer(entity);

	RemoveIcon(entity);

	int propOwner = GetPropOwner(entity);
	UntrackSolidProp(entity);
	ga_iAmmoAmount[entity] = 0;
	if (propOwner < 1)
		return;

	for (int i = 1; i <= MaxClients; i++) {
		if (EntRefToEntIndex(ga_iLastInflictor[i]) == entity) {
			ga_iLastInflictorPropId[i] = trackedPropId;
			ga_iLastInflictor[i] = INVALID_ENT_REFERENCE;
		}

		if (ga_iEntIdBipodDeployedOn[i] == entity)
			ga_iEntIdBipodDeployedOn[i] = INVALID_ENT_REFERENCE;
	}

	if (propOwner > 0 && ga_hPropPlaced[propOwner] != null) {
		int iArraySize = ga_hPropPlaced[propOwner].Length;
		if (iArraySize < 1)
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
	if (entity <= MaxClients || entity > MAXENTITIES)
		return -1;

	if (entity > MaxClients && entity <= MAXENTITIES) {
		int trackedOwner = ga_iTrackedPropOwner[entity];
		if (trackedOwner >= 1 && trackedOwner <= MaxClients)
			return trackedOwner;
	}

	if (!IsValidEntity(entity))
		return -1;

	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));
	if (StrContains(sName, "bmprop_c#", false) == -1)
		return -1;

	int propOwner = GetNumber(sName, "_c#");
	if (propOwner < 1 || propOwner > MaxClients)
		return -1;

	if (entity > MaxClients && entity <= MAXENTITIES) {
		ga_iTrackedPropOwner[entity] = propOwner;

		int modelId = GetNumber(sName, "_m#");
		if (modelId >= 0 && modelId < PROP_COUNT)
			ga_iTrackedPropId[entity] = modelId;
	}

	return propOwner;
}

public Action Panel_HelpInfo(int client) {
	Panel panel = new Panel();
	char sPropLimit[64];
	FormatEx(sPropLimit, sizeof(sPropLimit), "Prop limit: %d/%d \n(at max oldest deleted)", (ga_hPropPlaced[client] != null) ? ga_hPropPlaced[client].Length : 0, PROP_LIMIT);
	DrawPanelText(panel, sPropLimit);
	DrawPanelText(panel, " ");
	DrawPanelText(panel, "Knife controls:");
	DrawPanelText(panel, "Aim = Pick up or place a prop");
	DrawPanelText(panel, "Use = Highlight/unhighlight your prop (blue)");
	DrawPanelText(panel, "Move a selected prop = Move the whole group");
	DrawPanelText(panel, "Rotation menu: Reload = Reset rotation");
	DrawPanelText(panel, "Lean Left = Back | Lean Right = Next page");
	DrawPanelText(panel, "Lean Left from Rotation = Place built prop if valid");
	DrawPanelText(panel, "Bipod = Build menu | Cycle Firemode = Shop");
	DrawPanelText(panel, "!prophelp = Open this help");
	DrawPanelText(panel, " ");
	DrawPanelItem(panel, "Sprint or Shoot = Cancel and close menu");
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
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));
	for (int count = 0; count < sizeof(ga_sLmgWeapons); count++) {
		if (strcmp(sWeapon, ga_sLmgWeapons[count], false) == 0)
			return true;
	}
	return false;
}

public Action Timer_ForceDeployBipod(Handle timer, DataPack hDatapack) {
	hDatapack.Reset();
	int client = GetClientOfUserId(hDatapack.ReadCell());
	int sandbag = EntRefToEntIndex(hDatapack.ReadCell());
	float pivot = hDatapack.ReadFloat();

	if (client < 1 || client > MaxClients || !IsValidNonClientEntity(sandbag) || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;

	SetEntPropFloat(client, Prop_Send, "m_flPivotYaw", pivot);
	SetEntPropFloat(client, Prop_Send, "m_flViewOffsetBipod", 55.0);
	SetEntProp(client, Prop_Send, "m_iPlayerFlags", GetEntProp(client, Prop_Send, "m_iPlayerFlags") | PF_DEPLOY_BIPOD);
	ga_bBipodForced[client] = true;
	ga_iEntIdBipodDeployedOn[client] = sandbag;

	return Plugin_Stop;
}

public Action Timer_AmmoResupply(Handle timer) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client)
			|| !IsPlayerAlive(client)
			|| GetClientTeam(client) != TEAM_SECURITY) {
			ResetAmmoResupplyProgress(client);
			continue;
		}

		if (!ga_bHoldingMeleeWeapon[client]) {
			ResetAmmoResupplyProgress(client);
			continue;
		}

		if ((GetClientButtons(client) & BTN_RELOAD) == 0) {
			ResetAmmoResupplyProgress(client);
			continue;
		}

		int validAmmoCache = FindValidProp_InDistance(client);
		if (validAmmoCache == -1) {
			ResetAmmoResupplyProgress(client);
			continue;
		}

		if (g_bAmmoOnce && HasUsedAmmoCache(client, validAmmoCache)) {
			ResetAmmoResupplyProgress(client);
			PrintHintText(client, "You are not allowed to resupply from the same ammo cache more than once!");
			continue;
		}

		if (ga_iAmmoAmount[validAmmoCache] <= 0)
			ga_iAmmoAmount[validAmmoCache] = g_iAmmoAmount;

		ga_iResupplyCounter[client]--;
		PrintHintText(client, "Resupplying ammo in %d seconds | Supply left: %d",
			ga_iResupplyCounter[client], ga_iAmmoAmount[validAmmoCache]);

		if (ga_iResupplyCounter[client] > 0)
			continue;

		ResetAmmoResupplyProgress(client);
		if (!ResupplyPlayerPreservingCooldown(client)) {
			PrintHintText(client, "Unable to rearm right now.");
			continue;
		}

		int cacheOwner = ga_iTrackedPropOwner[validAmmoCache];
		if (cacheOwner > 0 && cacheOwner <= MaxClients && cacheOwner != client && IsClientInGame(cacheOwner) && !IsFakeClient(cacheOwner))
			LogToGame("\"%L\" triggered \"ammo_resupplied\" against \"%L\"", cacheOwner, client);

		ga_iAmmoAmount[validAmmoCache]--;
		if (ga_iAmmoAmount[validAmmoCache] <= 0) {
			SafeKillIdx(validAmmoCache);
		}
		else {
			MarkAmmoCacheUsed(client, validAmmoCache);
		}

		PrintHintText(client, "Rearmed! Ammo Supply left: %d", ga_iAmmoAmount[validAmmoCache]);
		PrintToChat(client, "\x01Rearmed! Ammo Supply left: \x070088cc%d", ga_iAmmoAmount[validAmmoCache]);
	}
	return Plugin_Continue;
}

static void ResetAmmoResupplyProgress(int client) {
	if (client < 1 || client > MaxClients)
		return;

	ga_iResupplyCounter[client] = g_iResupplyDelay;
}

bool ResupplyPlayerPreservingCooldown(int client) {
	float lastResupplyTime = GetEntDataFloat(client, g_iLastResupplyTimeOffset);
	float penaltyTime = GetEntDataFloat(client, g_iResupplyPenaltyTimeOffset);
	int resupplyCount = GetEntData(client, g_iResupplyCountOffset, 4);

	bool resupplied = view_as<bool>(SDKCall(g_hDirectResupply, client, true));

	// Resupply(true) skips the engine gate but records a new resupply. Restore
	// every field used by normal resupply cooldown and penalty calculations.
	SetEntDataFloat(client, g_iLastResupplyTimeOffset, lastResupplyTime, false);
	SetEntDataFloat(client, g_iResupplyPenaltyTimeOffset, penaltyTime, false);
	SetEntData(client, g_iResupplyCountOffset, resupplyCount, 4, false);

	return resupplied;
}

int FindValidProp_InDistance(int client) {
	if (!IsClientInGame(client))
		return -1;

	float eye[3];
	GetClientEyePosition(client, eye);

	float bestDistSqr = g_fAmmoResupplyRangeSqr + 1.0;

	int bestEnt = -1;
	float pos[3];
	if (g_hAmmoCacheRefs == null || g_hAmmoCacheRefs.Length == 0)
		return -1;

	for (int i = g_hAmmoCacheRefs.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(g_hAmmoCacheRefs.Get(i));
		if (ent <= MaxClients || !IsValidEntity(ent) || ga_iTrackedPropId[ent] != MID(Prop_AmmoCacheSmall)) {
			g_hAmmoCacheRefs.Erase(i);
			continue;
		}

		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
		float distSqr = GetVectorDistance(eye, pos, true);
		if (distSqr > g_fAmmoResupplyRangeSqr)
			continue;

		if (distSqr < bestDistSqr) {
			bestDistSqr = distSqr;
			bestEnt = ent;
		}
	}

	return bestEnt;
}

public Action Hook_WeaponSwitch(int client, int entity) {
	UpdateClientWeaponState(client, entity);

	if (ga_bHoldingMeleeWeapon[client]) {
		ga_bHoldingMeleeWeapon[client] = true;
		PrintCenterText(client, "Bipod = Build menu | AIM = Pick up prop | !prophelp = Help");
	}
	else {
		ga_bHoldingMeleeWeapon[client] = false;
		SetPropMenuWeaponLock(client, false);
		ClearPropSelections(client);
		StopHolding(client);
	}
	return Plugin_Continue;
}

void PrecacheFiles() {
	for (int i = 0; i < PROP_COUNT; i++)
		PrecacheModel(g_PropDefs[i].model, true);

	for (int i = 0; i < NUM_WIRESOUNDS; i++)
		PrecacheSound(ga_sBarbWire[i], true);

	for (int i = 0; i < sizeof(JC_Sounds); i++)
		PrecacheSound(JC_Sounds[i], true);

	PrecacheSound(SND_SUPPLYREFUND, true);
	PrecacheSound(SND_BUYBUILDPOINTS, true);
	PrecacheSound(SND_CANTBUY, true);
	PrecacheSound(SECURITY_DOOR_OPEN_SOUND, true);
	PrecacheSound(SECURITY_DOOR_CLOSE_SOUND, true);
	PrecacheSound(SECURITY_DOOR_IMPACT_SOUND, true);

	PrecacheModel(AMMO_ICON_SPRITE, true);
}

bool IsCollidingWithPlayer(int client, const float vPos[3]) {
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

void OpenShopMenu(int client, bool cooldown = true, bool openedFromPropMenu = false) {
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
	if (cooldown)
		ga_bShopOpenedFromPropMenu[client] = openedFromPropMenu;

	int playerTokens = GetEntProp(client, Prop_Send, "m_nAvailableTokens");
	Menu buyMenu = new Menu(BuyMenuHandler);
	buyMenu.SetTitle("Buy build points. (You have: %d)\n%s", ga_iPlayerBuildPoints[client], PROP_MENU_NAVIGATION_HINT);

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
	SetPropMenuWeaponLock(client, true);
	buyMenu.Display(client, MENU_STAYOPENTIME);
}

public int BuyMenuHandler(Menu menu, MenuAction action, int client, int param) {
	switch (action) {
		case MenuAction_End:
			delete menu;
		case MenuAction_Cancel: {
			if (client >= 1 && client <= MaxClients) {
				bool returnToPropMenu = ga_bShopOpenedFromPropMenu[client] && param == MenuCancel_ExitBack;
				ga_bShopMenuOpen[client] = false;
				ga_bShopOpenedFromPropMenu[client] = false;
				if (returnToPropMenu)
					OpenPropSelectionMenu(client);
			}
		}
		case MenuAction_Select: {
			if (client < 1 || client > MaxClients)
				return 0;
			if (param < 0) {
				ga_bShopMenuOpen[client] = false;
				ga_bShopOpenedFromPropMenu[client] = false;
				return 0;
			}

			char item[16], display[128];
			int style;
			if (!menu.GetItem(param, item, sizeof(item), style, display, sizeof(display))) {
				ga_bShopMenuOpen[client] = false;
				ga_bShopOpenedFromPropMenu[client] = false;
				return 0;
			}
			if (style & ITEMDRAW_SPACER || style & ITEMDRAW_DISABLED) {
				ga_bShopMenuOpen[client] = false;
				ga_bShopOpenedFromPropMenu[client] = false;
				return 0;
			}

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
			else if (strcmp(item, "refund", false) == 0) {
				ga_bShopMenuOpen[client] = false;
				OpenRefundConfirmMenu(client);
			}
		}
	}
	return 0;
}

void OpenRefundConfirmMenu(int client) {
	ga_bPropAuxMenuOpen[client] = true;
	SetPropMenuWeaponLock(client, true);
	Menu confirm = new Menu(RefundConfirmHandler);
	confirm.SetTitle("Refund %d supply and destroy ALL your props?\n%s\n\nAre you sure?", ga_iTokensSpent[client], PROP_MENU_NAVIGATION_HINT);
	confirm.AddItem("yes", "Yes - refund and deconstruct");
	confirm.AddItem("no", "No - go back");
	confirm.ExitBackButton = true;
	confirm.Display(client, 10);
}

public int RefundConfirmHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		ga_bPropAuxMenuOpen[client] = false;
		if (param == MenuCancel_ExitBack)
			OpenShopMenu(client, false);
	}
	else if (action == MenuAction_Select) {
		ga_bPropAuxMenuOpen[client] = false;
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
			ga_bShopOpenedFromPropMenu[client] = false;
			CancelClientMenu(client);
		}
		else
			OpenShopMenu(client, false);
	}
	return 0;
}

bool AnyPropMenuFlagOpen(int client) {
	return ga_bHelpMenuOpen[client] || ga_bPropRotateMenuOpen[client] || ga_bBuildMenuOpen[client] || ga_bShopMenuOpen[client] || ga_bPropAuxMenuOpen[client];
}

static void SetPropMenuWeaponLock(int client, bool enable) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	int flags = GetEntProp(client, Prop_Send, "m_iPlayerFlags");
	if (enable) {
		if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE && !ga_bPropRotateMenuOpen[client])
			return;
		if (ga_bPropMenuWeaponLockApplied[client])
			return;

		ga_bPropMenuWasWeaponRestricted[client] = (flags & PF_WEAPON_RESTRICTED) != 0;
		ga_bPropMenuWeaponLockApplied[client] = true;
		if (!ga_bPropMenuWasWeaponRestricted[client])
			SetEntProp(client, Prop_Send, "m_iPlayerFlags", flags | PF_WEAPON_RESTRICTED);
		return;
	}

	if (!ga_bPropMenuWeaponLockApplied[client])
		return;

	if (!ga_bPropMenuWasWeaponRestricted[client])
		SetEntProp(client, Prop_Send, "m_iPlayerFlags", flags & ~PF_WEAPON_RESTRICTED);

	ga_bPropMenuWeaponLockApplied[client] = false;
	ga_bPropMenuWasWeaponRestricted[client] = false;
}

static void SyncPropMenuWeaponLock(int client) {
	bool shouldLock = ga_bHoldingMeleeWeapon[client]
		&& (ga_iPropHolding[client] == INVALID_ENT_REFERENCE || ga_bPropRotateMenuOpen[client])
		&& AnyPropMenuFlagOpen(client)
		&& GetClientMenu(client) == MenuSource_Normal;
	SetPropMenuWeaponLock(client, shouldLock);
}

void CloseAllPropMenus(int client, bool sendSlot9IfNeeded = true) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	bool bOurMenuOpen = AnyPropMenuFlagOpen(client);
	if (bOurMenuOpen) {
		if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
			StopHolding(client);
		ga_iPropOwner[client] = 0;
	}

	if (bOurMenuOpen && GetClientMenu(client) != MenuSource_None)
		CancelClientMenu(client);

	if (sendSlot9IfNeeded && bOurMenuOpen)
		ClientCommand(client, "slot9");

	ga_bHelpMenuOpen[client] = false;
	ga_bPropRotateMenuOpen[client] = false;
	ga_bRotationMenuVisible[client] = false;
	ga_bBuildMenuOpen[client] = false;
	ga_bShopMenuOpen[client] = false;
	ga_bShopOpenedFromPropMenu[client] = false;
	ga_bPropAuxMenuOpen[client] = false;
	SetPropMenuWeaponLock(client, false);
}

void DeconstructAllProps(int client) {
	ArrayList list = ga_hPropPlaced[client];
	if (list == null) return;

	for (int i = list.Length - 1; i >= 0; i--) {
		SafeKillRef(list.Get(i));
	}

	list.Clear();
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

void RefundAllSupply(int client, bool immediateKill = false, bool silent = false) {
	StopHolding(client, immediateKill);

	if (ga_iTokensSpent[client] == 0)
		return;

	SetEntProp(client, Prop_Send, "m_nAvailableTokens",
		GetEntProp(client, Prop_Send, "m_nAvailableTokens") + ga_iTokensSpent[client]);

	if (!silent) {
		PrintToChat(client, "You have been refunded %d supply points.", ga_iTokensSpent[client]);
		EmitSoundToClient(client, SND_SUPPLYREFUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
	}

	ga_iTokensSpent[client] = 0;
	RestoreBuildPoints(client);
}

public Action cmd_prophelp(int client, int args) {
	if (client > 0 && IsClientInGame(client) && !ga_bHelpMenuOpen[client]) {
		ga_bHelpMenuOpen[client] = true;
		SetPropMenuWeaponLock(client, true);
		Panel_HelpInfo(client);
	}
	return Plugin_Handled;
}

static bool HasRecentPropModels(int client) {
	for (int slot = 0; slot < RECENT_PROP_COUNT; slot++) {
		if (ga_iRecentPropModels[client][slot] >= 0 && ga_iRecentPropModels[client][slot] < PROP_COUNT)
			return true;
	}

	return false;
}

static void SelectPropForHolding(int client, int modelId) {
	ga_bBuildMenuOpen[client] = false;
	ga_iModelIndex[client] = view_as<PropId>(modelId);

	char modelName[64];
	GetModelName(g_PropDefs[modelId].model, modelName, sizeof(modelName));
	int maxHealth = g_PropDefs[modelId].health;
	if (maxHealth < 1)
		maxHealth = PROP_HEALTH;

	PrintCenterText(client, "Selected prop: %s (Cost: %d)\nHealth: %d/%d", modelName, g_PropDefs[modelId].cost, maxHealth, maxHealth);

	int ent = EntRefToEntIndex(ga_iPropHolding[client]);
	if (ent <= MaxClients || !IsValidEntity(ent)) {
		HoldProp(client);
		OpenRotationMenu(client);
		return;
	}

	float vPos[3], vAng[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", vPos);
	GetEntPropVector(ent, Prop_Send, "m_angRotation", vAng);

	StopHolding(client);

	if (!ga_iPropOwner[client])
		CreateProp(client, vPos, vAng);
	else
		ga_iPropOwner[client] = 0;

	OpenRotationMenu(client);
}

void OpenPropSelectionMenu(int client) {
	ga_bBuildMenuOpen[client] = true;
	SetPropMenuWeaponLock(client, true);
	NormalizeRecentPropModels(client);

	Menu propMenu = new Menu(PropSelectionMenuHandler);
	propMenu.SetTitle("Select Prop.\n(build points: %d)\n%s", ga_iPlayerBuildPoints[client], PROP_MENU_NAVIGATION_HINT);

	char itemBuffer[128], modelName[64], indexStr[8];
	propMenu.AddItem("97", "Blueprints");
	if (HasRecentPropModels(client))
		propMenu.AddItem("96", "Recent props");

	for (int i = 0; i < PROP_COUNT; i++) {
		if (g_iAllFree == 0 && !HasEnoughResources(client, g_PropDefs[i].cost))
			continue;

		int maxHealth = g_PropDefs[i].health;
		if (maxHealth < 1)
			maxHealth = PROP_HEALTH;

		GetModelName(g_PropDefs[i].model, modelName, sizeof(modelName));
		FormatEx(itemBuffer, sizeof(itemBuffer), "%s (HP: %d) - Cost: %d", modelName, maxHealth, (g_iAllFree == 0 ? g_PropDefs[i].cost : 0));
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

			int maxHealth = g_PropDefs[i].health;
			if (maxHealth < 1)
				maxHealth = PROP_HEALTH;

			GetModelName(g_PropDefs[i].model, modelName, sizeof(modelName));
			FormatEx(itemBuffer, sizeof(itemBuffer), "%s (HP: %d) - Cost: %d (Can't afford)", modelName, maxHealth, g_PropDefs[i].cost);
			IntToString(i, indexStr, sizeof(indexStr));
			propMenu.AddItem(indexStr, itemBuffer, ITEMDRAW_DISABLED);
		}
	}

	propMenu.ExitBackButton = true;
	propMenu.Display(client, MENU_STAYOPENTIME);
}

static void OpenRecentPropsMenu(int client) {
	Menu recentMenu = new Menu(RecentPropsMenuHandler);
	recentMenu.SetTitle("Recent props\n(build points: %d)\n%s", ga_iPlayerBuildPoints[client], PROP_MENU_NAVIGATION_HINT);

	char itemBuffer[128], modelName[64], indexStr[8];
	for (int slot = 0; slot < RECENT_PROP_COUNT; slot++) {
		int modelId = ga_iRecentPropModels[client][slot];
		if (modelId < 0 || modelId >= PROP_COUNT)
			continue;

		int maxHealth = g_PropDefs[modelId].health;
		if (maxHealth < 1)
			maxHealth = PROP_HEALTH;

		GetModelName(g_PropDefs[modelId].model, modelName, sizeof(modelName));
		IntToString(modelId, indexStr, sizeof(indexStr));
		if (g_iAllFree == 0 && !HasEnoughResources(client, g_PropDefs[modelId].cost)) {
			FormatEx(itemBuffer, sizeof(itemBuffer), "%s (HP: %d) - Cost: %d (Can't afford)", modelName, maxHealth, g_PropDefs[modelId].cost);
			recentMenu.AddItem(indexStr, itemBuffer, ITEMDRAW_DISABLED);
		}
		else {
			FormatEx(itemBuffer, sizeof(itemBuffer), "%s (HP: %d) - Cost: %d", modelName, maxHealth, (g_iAllFree == 0 ? g_PropDefs[modelId].cost : 0));
			recentMenu.AddItem(indexStr, itemBuffer);
		}
	}

	recentMenu.ExitBackButton = true;
	recentMenu.Display(client, MENU_STAYOPENTIME);
}

public int RecentPropsMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		char indexStr[8];
		int style;
		if (!menu.GetItem(param, indexStr, sizeof(indexStr), style) || style & ITEMDRAW_DISABLED) {
			ga_bBuildMenuOpen[client] = false;
			return 0;
		}

		int modelId = StringToInt(indexStr);
		if (modelId >= 0 && modelId < PROP_COUNT)
			SelectPropForHolding(client, modelId);
		else {
			ga_bBuildMenuOpen[client] = false;
			PrintToChat(client, "Invalid prop selection.");
		}
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		if (param == MenuCancel_ExitBack)
			OpenPropSelectionMenu(client);
		else
			ga_bBuildMenuOpen[client] = false;
	}
	return 0;
}

public int PropSelectionMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		if (param < 0) {
			ga_bBuildMenuOpen[client] = false;
			return 0;
		}

		char indexStr[8], display[96];
		int style;
		if (!menu.GetItem(param, indexStr, sizeof(indexStr), style, display, sizeof(display))) {
			ga_bBuildMenuOpen[client] = false;
			return 0;
		}
		if (style & ITEMDRAW_DISABLED) {
			ga_bBuildMenuOpen[client] = false;
			return 0;
		}

		int selectedIndex = StringToInt(indexStr);
		if (selectedIndex >= 0 && selectedIndex < PROP_COUNT)
			SelectPropForHolding(client, selectedIndex);
		else if (selectedIndex == 99) {
			ga_bBuildMenuOpen[client] = false;
			OpenDeconstructConfirmMenu(client);
		}
		else if (selectedIndex == 98) {
			ga_bBuildMenuOpen[client] = false;
			if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
				StopHolding(client);

			OpenShopMenu(client, true, true);
		}
		else if (selectedIndex == 97) {
			ga_bBuildMenuOpen[client] = false;
			OpenBlueprintMenu(client);
		}
		else if (selectedIndex == 96)
			OpenRecentPropsMenu(client);
		else {
			ga_bBuildMenuOpen[client] = false;
			PrintToChat(client, "Invalid prop selection.");
		}
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients)
		ga_bBuildMenuOpen[client] = false;
	return 0;
}

void OpenRotationMenu(int client) {
	ga_bPropRotateMenuOpen[client] = true;
	ga_bRotationMenuVisible[client] = true;
	SetPropMenuWeaponLock(client, true);

	Menu rotationMenu = new Menu(RotationMenuHandler);
	float step = ga_fPropRotateStep[client];
	if (step <= 0.0)
		step = PROP_ROTATE_STEP;

	rotationMenu.SetTitle("Rotation\nStep: %.1f°\nAIM: Place\n%s\nRELOAD: Reset rotation", step, PROP_MENU_NAVIGATION_HINT);

	rotationMenu.AddItem("y+", "+Yaw");
	rotationMenu.AddItem("y-", "-Yaw");
	rotationMenu.AddItem("x+", "+Pitch");
	rotationMenu.AddItem("x-", "-Pitch");
	rotationMenu.AddItem("z+", "+Roll");
	rotationMenu.AddItem("z-", "-Roll");
	rotationMenu.AddItem("reset", "Reset Rotation");
	rotationMenu.AddItem("spacer", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);
	rotationMenu.AddItem("saveblueprint", "Save Blueprint");
	rotationMenu.AddItem("spacer", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);

	char stepItem[64];
	FormatEx(stepItem, sizeof(stepItem), "Rotation step: %.1f° (change)", step);
	rotationMenu.AddItem("rotstep", stepItem);

	rotationMenu.ExitBackButton = true;
	rotationMenu.Display(client, 60);
}

static bool IsValidRotateStep(float step) {
	int deg = RoundToNearest(step);
	if (FloatAbs(step - float(deg)) > 0.01)
		return false;
	if (deg < 5 || deg > 180)
		return false;
	if ((deg % 5) != 0)
		return false;
	return true;
}

static float BM_NormalizeAngle360(float ang) {
	ang -= 360.0 * float(RoundToFloor(ang / 360.0));
	if (ang < 0.0)
		ang += 360.0;
	return ang;
}

static void LoadRotateStepCookie(int client) {
	if (g_hCookiePropRotateStep == null)
		return;
	if (client < 1 || client > MaxClients || IsFakeClient(client))
		return;
	if (!AreClientCookiesCached(client))
		return;

	char s[16];
	GetClientCookie(client, g_hCookiePropRotateStep, s, sizeof(s));

	float step = StringToFloat(s);
	if (!IsValidRotateStep(step))
		step = PROP_ROTATE_STEP;

	ga_fPropRotateStep[client] = step;
}

static void SaveRotateStepCookie(int client) {
	if (g_hCookiePropRotateStep == null)
		return;
	if (client < 1 || client > MaxClients || IsFakeClient(client))
		return;

	char s[16];
	FormatEx(s, sizeof(s), "%.2f", ga_fPropRotateStep[client]);
	SetClientCookie(client, g_hCookiePropRotateStep, s);
}

void OpenRotateStepMenu(int client) {
	ga_bRotationMenuVisible[client] = false;
	Menu m = new Menu(RotateStepMenuHandler);

	float cur = ga_fPropRotateStep[client];
	if (!IsValidRotateStep(cur))
		cur = PROP_ROTATE_STEP;

	m.SetTitle("Rotation step\nCurrent: %.0f°\n%s", cur, PROP_MENU_NAVIGATION_HINT);

	int curDeg = RoundToNearest(cur);

	char info[16], disp[64];

	for (int deg = 5; deg <= 180; deg += 5) {
		IntToString(deg, info, sizeof(info));

		if (deg == curDeg) {
			FormatEx(disp, sizeof(disp), "%d° (current)", deg);
			m.AddItem(info, disp, ITEMDRAW_DISABLED);
		}
		else {
			FormatEx(disp, sizeof(disp), "%d°", deg);
			m.AddItem(info, disp);
		}
	}

	m.ExitBackButton = true;
	m.Display(client, MENU_STAYOPENTIME);
}

public int RotateStepMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(param, info, sizeof(info));

		int deg = StringToInt(info);
		float step = float(deg);

		if (!IsValidRotateStep(step)) {
			PrintToChat(client, "Invalid rotation step.");
			OpenRotationMenu(client);
			return 0;
		}

		ga_fPropRotateStep[client] = step;
		SaveRotateStepCookie(client);

		PrintToChat(client, "Rotation step set to %d°.", deg);
		OpenRotationMenu(client);
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		if (param == MenuCancel_ExitBack)
			OpenRotationMenu(client);
		else {
			ga_bPropRotateMenuOpen[client] = false;
			ga_bRotationMenuVisible[client] = false;
		}
	}
	return 0;
}

static void ResetHeldPropRotation(int client, bool reopenMenu = false) {
	int ent = EntRefToEntIndex(ga_iPropHolding[client]);
	if (ent <= MaxClients || !IsValidEntity(ent)) {
		ga_bPropRotateMenuOpen[client] = false;
		ga_bRotationMenuVisible[client] = false;
		return;
	}

	float vRot[3] = {0.0, 0.0, 0.0};
	SetEntPropVector(ent, Prop_Send, "m_angRotation", vRot);

	int hp = ga_iHoldHp[client];
	int maxHealth = ga_iHoldMaxHp[client];
	if (maxHealth <= 0) {
		hp = GetEntProp(ent, Prop_Data, "m_iHealth");
		maxHealth = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
		if (maxHealth <= 0)
			maxHealth = PROP_HEALTH;
		if (hp < 0)
			hp = 0;

		ga_iHoldHp[client] = hp;
		ga_iHoldMaxHp[client] = maxHealth;
	}
	PrintCenterText(client, "Rotation reset\nHealth: %d/%d", hp, maxHealth);

	if (!ga_bHoldingBlueprint[client] && (ga_hBatchMoveData[client] == null || ga_hBatchMoveData[client].Length == 0)) {
		int mid = MID(ga_iModelIndex[client]);
		ga_fPropRotations[client][mid][0] = 0.0;
		ga_fPropRotations[client][mid][1] = 0.0;
		ga_fPropRotations[client][mid][2] = 0.0;
	}

	if (reopenMenu)
		OpenRotationMenu(client);
}

static bool TryPlaceExistingHeldPropOnBack(int client) {
	if (ga_iPropOwner[client] < 1 || ga_iPropHolding[client] == INVALID_ENT_REFERENCE)
		return false;
	if (!IsPlayerOnGround(client))
		return false;

	int ent = EntRefToEntIndex(ga_iPropHolding[client]);
	if (!IsValidNonClientEntity(ent))
		return false;

	float vel[3] = {0.0, 0.0, 0.0};
	float lastPlaceTime = ga_fLastPlaceTime[client];
	ga_fLastPlaceTime[client] = 0.0;
	OnButtonPress(client, BTN_USE, vel);

	if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE) {
		ga_fLastPlaceTime[client] = lastPlaceTime;
		return false;
	}

	return true;
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

		if (strcmp(item, "rotstep", false) == 0) {
			OpenRotateStepMenu(client);
			return 0;
		}
		if (strcmp(item, "saveblueprint", false) == 0) {
			float now = GetGameTime();
			if (ga_fNextBlueprintSave[client] > now) {
				PrintToChat(client, "Please wait %.1f seconds before saving another blueprint.", ga_fNextBlueprintSave[client] - now);
				OpenRotationMenu(client);
				return 0;
			}
			if (g_hBlueprintDb == null || !g_bBlueprintDbReady) {
				PrintToChat(client, "Blueprints are unavailable because the database could not be opened.");
				OpenRotationMenu(client);
				return 0;
			}
			if (!ga_bBlueprintsLoaded[client]) {
				LoadClientBlueprints(client);
				PrintToChat(client, "Blueprints are loading. Try Save Blueprint again in a moment.");
				OpenRotationMenu(client);
				return 0;
			}
			if (ga_hPendingBlueprintProps[client] != null) {
				delete ga_hPendingBlueprintProps[client];
				ga_hPendingBlueprintProps[client] = null;
			}
			if (!CaptureHeldBlueprintLayout(client, ga_hPendingBlueprintProps[client])) {
				PrintToChat(client, "You can save blueprints only while holding a group of %d to %d props.", BLUEPRINT_MIN_PROPS, BLUEPRINT_MAX_PROPS);
				OpenRotationMenu(client);
				return 0;
			}
			ga_fNextBlueprintSave[client] = now + BLUEPRINT_SAVE_COOLDOWN;
			OpenBlueprintSaveSlotsMenu(client);
			return 0;
		}

		int ent = EntRefToEntIndex(ga_iPropHolding[client]);
		if (ent <= MaxClients || !IsValidEntity(ent)) {
			ga_bPropRotateMenuOpen[client] = false;
			ga_bRotationMenuVisible[client] = false;
			return 0;
		}

		float vRot[3];
		GetEntPropVector(ent, Prop_Send, "m_angRotation", vRot);

		float step = ga_fPropRotateStep[client];
		if (step <= 0.0)
			step = PROP_ROTATE_STEP;

		if (strcmp(item, "y+") == 0)
			vRot[1] += step;
		else if (strcmp(item, "y-") == 0)
			vRot[1] -= step;
		else if (strcmp(item, "x+") == 0)
			vRot[0] += step;
		else if (strcmp(item, "x-") == 0)
			vRot[0] -= step;
		else if (strcmp(item, "z+") == 0)
			vRot[2] += step;
		else if (strcmp(item, "z-") == 0)
			vRot[2] -= step;
		else if (strcmp(item, "reset") == 0) {
			ResetHeldPropRotation(client, true);
			return 0;
		}

		vRot[0] = BM_NormalizeAngle360(vRot[0]);
		vRot[1] = BM_NormalizeAngle360(vRot[1]);
		vRot[2] = BM_NormalizeAngle360(vRot[2]);

		SetEntPropVector(ent, Prop_Send, "m_angRotation", vRot);

		int hp = ga_iHoldHp[client];
		int maxHealth = ga_iHoldMaxHp[client];
		if (maxHealth <= 0) {
			hp = GetEntProp(ent, Prop_Data, "m_iHealth");
			maxHealth = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
			if (maxHealth <= 0)
				maxHealth = PROP_HEALTH;
			if (hp < 0)
				hp = 0;

			ga_iHoldHp[client] = hp;
			ga_iHoldMaxHp[client] = maxHealth;
		}
		PrintCenterText(client, "Rotation: Yaw: %.1f°, Pitch: %.1f°, Roll: %.1f°\nHealth: %d/%d", vRot[1], vRot[0], vRot[2], hp, maxHealth);

		// A mass move rotates the current group only. Do not make its lead prop
		// change the saved default rotation for later single prop builds.
		if (!ga_bHoldingBlueprint[client] && (ga_hBatchMoveData[client] == null || ga_hBatchMoveData[client].Length == 0)) {
			int mid = MID(ga_iModelIndex[client]);
			ga_fPropRotations[client][mid][0] = vRot[0];
			ga_fPropRotations[client][mid][1] = vRot[1];
			ga_fPropRotations[client][mid][2] = vRot[2];
		}

		OpenRotationMenu(client);
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		ga_bPropRotateMenuOpen[client] = false;
		ga_bRotationMenuVisible[client] = false;
		if (param == MenuCancel_ExitBack && !TryPlaceExistingHeldPropOnBack(client))
			StopHolding(client);
		ga_iPropOwner[client] = 0;
		if (param == MenuCancel_ExitBack)
			OpenPropSelectionMenu(client);
	}
	return 0;
}

void OpenDeconstructConfirmMenu(int client) {
	int count = (ga_hPropPlaced[client] != null) ? ga_hPropPlaced[client].Length : 0;

	ga_bPropAuxMenuOpen[client] = true;
	SetPropMenuWeaponLock(client, true);
	Menu confirm = new Menu(DeconstructConfirmHandler);
	confirm.SetTitle("Deconstruct ALL your props? (%d placed)\n%s\n\nAre you sure?", count, PROP_MENU_NAVIGATION_HINT);
	confirm.AddItem("yes", "Yes - deconstruct all props");
	confirm.AddItem("no",  "No - go back");
	confirm.ExitBackButton = true;
	confirm.Display(client, 10);
}

public int DeconstructConfirmHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		ga_bPropAuxMenuOpen[client] = false;
		if (param == MenuCancel_ExitBack)
			OpenPropSelectionMenu(client);
	}
	else if (action == MenuAction_Select) {
		ga_bPropAuxMenuOpen[client] = false;
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

static bool GetBlueprintSteamId(int client, char[] steamId, int maxLen) {
	return client >= 1 && client <= MaxClients && IsClientInGame(client)
		&& GetClientAuthId(client, AuthId_Steam2, steamId, maxLen, true);
}

static int FindPropIdByModel(const char[] model) {
	for (int i = 0; i < PROP_COUNT; i++) {
		if (StrEqual(g_PropDefs[i].model, model, false))
			return i;
	}
	return -1;
}

static ArrayList EnsureBlueprintPropList(int client, int slot) {
	if (client < 1 || client > MaxClients || slot < 0 || slot >= BLUEPRINT_SLOT_COUNT)
		return null;

	if (ga_hBlueprintProps[client][slot] == null)
		ga_hBlueprintProps[client][slot] = new ArrayList(ByteCountToCells(BLUEPRINT_RECORD_LENGTH));
	return ga_hBlueprintProps[client][slot];
}

static bool ParseBlueprintRecord(const char[] record, char[] model, int modelLen, float offset[3], float angles[3]) {
	char fields[7][PLATFORM_MAX_PATH];
	if (ExplodeString(record, "|", fields, sizeof(fields), sizeof(fields[])) != 7)
		return false;

	strcopy(model, modelLen, fields[0]);
	offset[0] = StringToFloat(fields[1]);
	offset[1] = StringToFloat(fields[2]);
	offset[2] = StringToFloat(fields[3]);
	angles[0] = StringToFloat(fields[4]);
	angles[1] = StringToFloat(fields[5]);
	angles[2] = StringToFloat(fields[6]);
	return model[0] != '\0';
}

static void MakeBlueprintRecord(const char[] model, const float offset[3], const float angles[3], char[] record, int maxLen) {
	FormatEx(record, maxLen, "%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", model,
		offset[0], offset[1], offset[2], angles[0], angles[1], angles[2]);
}

static int GetBlueprintCost(int client, int slot) {
	if (slot < 0 || slot >= BLUEPRINT_SLOT_COUNT)
		return -1;

	ArrayList list = ga_hBlueprintProps[client][slot];
	if (list == null || list.Length < BLUEPRINT_MIN_PROPS)
		return -1;

	int totalCost = 0;
	for (int i = 0; i < list.Length; i++) {
		char record[BLUEPRINT_RECORD_LENGTH], model[PLATFORM_MAX_PATH];
		float offset[3], angles[3];
		list.GetString(i, record, sizeof(record));
		if (!ParseBlueprintRecord(record, model, sizeof(model), offset, angles))
			return -1;

		int modelId = FindPropIdByModel(model);
		if (modelId < 0 || modelId == MID(Prop_AmmoCacheSmall))
			return -1;
		totalCost += g_PropDefs[modelId].cost;
	}

	return totalCost;
}

static void ClearClientBlueprints(int client) {
	if (client < 1 || client > MaxClients)
		return;

	for (int slot = 0; slot < BLUEPRINT_SLOT_COUNT; slot++) {
		if (ga_hBlueprintProps[client][slot] != null) {
			delete ga_hBlueprintProps[client][slot];
			ga_hBlueprintProps[client][slot] = null;
		}
		ga_sBlueprintName[client][slot][0] = '\0';
	}
	ga_bBlueprintsLoaded[client] = false;
	ga_bBlueprintsLoading[client] = false;
	ga_fNextBlueprintSave[client] = 0.0;
	ga_fNextBlueprintLoad[client] = 0.0;

	if (ga_hPendingBlueprintNameTimer[client] != INVALID_HANDLE) {
		KillTimer(ga_hPendingBlueprintNameTimer[client]);
		ga_hPendingBlueprintNameTimer[client] = INVALID_HANDLE;
	}
	if (ga_hPendingBlueprintProps[client] != null) {
		delete ga_hPendingBlueprintProps[client];
		ga_hPendingBlueprintProps[client] = null;
	}
	ga_iPendingBlueprintSlot[client] = -1;
	ClearBlueprintHold(client, true);
}

static void SetupBlueprintDatabase() {
	g_bBlueprintDbReady = false;
	if (SQL_CheckConfig(BLUEPRINT_DATABASE_CONFIG)) {
		Database.Connect(SQL_ConnectBlueprintDatabase, BLUEPRINT_DATABASE_CONFIG);
		return;
	}

	SetupLocalBlueprintDatabase();
}

public void SQL_ConnectBlueprintDatabase(Database db, const char[] error, any data) {
	if (db == null) {
		LogError("Unable to connect to the props blueprint database '%s': %s", BLUEPRINT_DATABASE_CONFIG, error);
		return;
	}

	g_hBlueprintDb = db;
	SQL_TQuery(g_hBlueprintDb, SQL_CreateBlueprintTable,
		"CREATE TABLE IF NOT EXISTS bm_props_blueprints (steamid VARCHAR(64) NOT NULL, slot TINYINT UNSIGNED NOT NULL, name VARCHAR(128) NOT NULL, layout TEXT NOT NULL, PRIMARY KEY (steamid, slot)) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
}

static void SetupLocalBlueprintDatabase() {
	g_bBlueprintDbReady = false;
	char error[256];
	g_hBlueprintDb = SQLite_UseDatabase("props_blueprints", error, sizeof(error));
	if (g_hBlueprintDb == null) {
		LogError("Unable to open local props blueprint database: %s", error);
		return;
	}

	SQL_TQuery(g_hBlueprintDb, SQL_CreateBlueprintTable,
		"CREATE TABLE IF NOT EXISTS bm_props_blueprints (steamid TEXT NOT NULL, slot INTEGER NOT NULL, name TEXT NOT NULL, layout TEXT NOT NULL, PRIMARY KEY (steamid, slot))");
}

public void SQL_CreateBlueprintTable(Database db, DBResultSet results, const char[] error, any data) {
	if (error[0] != '\0') {
		LogError("Unable to create props blueprint table: %s", error);
		delete g_hBlueprintDb;
		g_hBlueprintDb = null;
		g_bBlueprintDbReady = false;
		return;
	}

	g_bBlueprintDbReady = true;
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsFakeClient(client))
			LoadClientBlueprints(client);
	}
}

static void LoadClientBlueprints(int client) {
	if (g_hBlueprintDb == null || !g_bBlueprintDbReady || client < 1 || client > MaxClients || !IsClientInGame(client)
		|| IsFakeClient(client) || ga_bBlueprintsLoading[client] || ga_bBlueprintsLoaded[client])
		return;

	char steamId[64], escapedSteamId[128], query[256];
	if (!GetBlueprintSteamId(client, steamId, sizeof(steamId)))
		return;

	SQL_EscapeString(g_hBlueprintDb, steamId, escapedSteamId, sizeof(escapedSteamId));
	FormatEx(query, sizeof(query), "SELECT slot, name, layout FROM bm_props_blueprints WHERE steamid = '%s' ORDER BY slot ASC", escapedSteamId);
	ga_bBlueprintsLoading[client] = true;
	SQL_TQuery(g_hBlueprintDb, SQL_LoadClientBlueprints, query, GetClientUserId(client));
}

public void SQL_LoadClientBlueprints(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	ga_bBlueprintsLoading[client] = false;
	if (error[0] != '\0') {
		LogError("Unable to load props blueprints for client %d: %s", client, error);
		return;
	}

	for (int slot = 0; slot < BLUEPRINT_SLOT_COUNT; slot++) {
		if (ga_hBlueprintProps[client][slot] != null) {
			delete ga_hBlueprintProps[client][slot];
			ga_hBlueprintProps[client][slot] = null;
		}
		ga_sBlueprintName[client][slot][0] = '\0';
	}

	while (results != null && results.FetchRow()) {
		int slot = results.FetchInt(0) - 1;
		if (slot < 0 || slot >= BLUEPRINT_SLOT_COUNT)
			continue;

		results.FetchString(1, ga_sBlueprintName[client][slot], BLUEPRINT_NAME_LENGTH);
		char layout[BLUEPRINT_LAYOUT_LENGTH];
		results.FetchString(2, layout, sizeof(layout));

		char records[BLUEPRINT_MAX_PROPS][BLUEPRINT_RECORD_LENGTH];
		int count = ExplodeString(layout, ";", records, sizeof(records), sizeof(records[]));
		if (count < BLUEPRINT_MIN_PROPS || count > BLUEPRINT_MAX_PROPS)
			continue;

		ArrayList list = EnsureBlueprintPropList(client, slot);
		for (int i = 0; i < count; i++)
			list.PushString(records[i]);
	}

	ga_bBlueprintsLoaded[client] = true;
}

static ArrayList GetHeldGroupData(int client) {
	return ga_bHoldingBlueprint[client] ? ga_hBlueprintHoldData[client] : ga_hBatchMoveData[client];
}

static bool CaptureHeldBlueprintLayout(int client, ArrayList &layout) {
	ArrayList group = GetHeldGroupData(client);
	if (group == null || group.Length + 1 < BLUEPRINT_MIN_PROPS || group.Length + 1 > BLUEPRINT_MAX_PROPS)
		return false;

	int lead = EntRefToEntIndex(ga_iPropHolding[client]);
	int leadModelId = MID(ga_iModelIndex[client]);
	if (!IsValidNonClientEntity(lead) || leadModelId < 0 || leadModelId >= PROP_COUNT)
		return false;

	float leadPosition[3], leadAngles[3], zeroOffset[3];
	GetEntPropVector(lead, Prop_Send, "m_vecOrigin", leadPosition);
	GetEntPropVector(lead, Prop_Send, "m_angRotation", leadAngles);
	zeroOffset[0] = 0.0;
	zeroOffset[1] = 0.0;
	zeroOffset[2] = 0.0;

	layout = new ArrayList(ByteCountToCells(BLUEPRINT_RECORD_LENGTH));
	char record[BLUEPRINT_RECORD_LENGTH];
	MakeBlueprintRecord(g_PropDefs[leadModelId].model, zeroOffset, leadAngles, record, sizeof(record));
	layout.PushString(record);

	for (int i = 0; i < group.Length; i++) {
		int preview = EntRefToEntIndex(group.Get(i, 7));
		int modelId = group.Get(i, 8);
		if (!IsValidNonClientEntity(preview) || modelId < 0 || modelId >= PROP_COUNT) {
			delete layout;
			layout = null;
			return false;
		}

		float position[3], angles[3], offset[3];
		GetEntPropVector(preview, Prop_Send, "m_vecOrigin", position);
		GetEntPropVector(preview, Prop_Send, "m_angRotation", angles);
		offset[0] = position[0] - leadPosition[0];
		offset[1] = position[1] - leadPosition[1];
		offset[2] = position[2] - leadPosition[2];
		MakeBlueprintRecord(g_PropDefs[modelId].model, offset, angles, record, sizeof(record));
		layout.PushString(record);
	}

	return true;
}

static void ResetRecentPropModels(int client) {
	for (int slot = 0; slot < RECENT_PROP_COUNT; slot++)
		ga_iRecentPropModels[client][slot] = -1;
}

static void NormalizeRecentPropModels(int client) {
	int uniqueModels[RECENT_PROP_COUNT];
	int uniqueCount = 0;

	for (int slot = 0; slot < RECENT_PROP_COUNT; slot++) {
		int modelId = ga_iRecentPropModels[client][slot];
		if (modelId < 0 || modelId >= PROP_COUNT)
			continue;

		bool duplicate = false;
		for (int previous = 0; previous < uniqueCount; previous++) {
			if (uniqueModels[previous] == modelId) {
				duplicate = true;
				break;
			}
		}
		if (duplicate)
			continue;

		uniqueModels[uniqueCount] = modelId;
		uniqueCount++;
	}

	for (int slot = 0; slot < RECENT_PROP_COUNT; slot++)
		ga_iRecentPropModels[client][slot] = (slot < uniqueCount) ? uniqueModels[slot] : -1;
}

static void RecordRecentPropModel(int client, int modelId) {
	if (modelId < 0 || modelId >= PROP_COUNT)
		return;

	NormalizeRecentPropModels(client);

	int remaining[RECENT_PROP_COUNT];
	int remainingCount = 0;
	for (int slot = 0; slot < RECENT_PROP_COUNT && remainingCount < RECENT_PROP_COUNT - 1; slot++) {
		int recentModelId = ga_iRecentPropModels[client][slot];
		if (recentModelId < 0 || recentModelId >= PROP_COUNT || recentModelId == modelId)
			continue;

		remaining[remainingCount] = recentModelId;
		remainingCount++;
	}

	ga_iRecentPropModels[client][0] = modelId;
	for (int slot = 1; slot < RECENT_PROP_COUNT; slot++)
		ga_iRecentPropModels[client][slot] = (slot - 1 < remainingCount) ? remaining[slot - 1] : -1;
}

static void OpenBlueprintSaveSlotsMenu(int client) {
	ga_bRotationMenuVisible[client] = false;
	Menu menu = new Menu(BlueprintSaveSlotMenuHandler);
	menu.SetTitle("Save Blueprint\nChoose a slot\n%s", PROP_MENU_NAVIGATION_HINT);

	for (int slot = 0; slot < BLUEPRINT_SLOT_COUNT; slot++) {
		char info[8], display[192];
		IntToString(slot, info, sizeof(info));
		if (ga_hBlueprintProps[client][slot] == null || ga_hBlueprintProps[client][slot].Length == 0) {
			FormatEx(display, sizeof(display), "Slot %d: Empty", slot + 1);
		} else {
			int cost = GetBlueprintCost(client, slot);
			if (cost < 0)
				FormatEx(display, sizeof(display), "Slot %d: %s (Unavailable)", slot + 1, ga_sBlueprintName[client][slot]);
			else
				FormatEx(display, sizeof(display), "Slot %d: %s (%d props, Cost: %d)", slot + 1,
					ga_sBlueprintName[client][slot], ga_hBlueprintProps[client][slot].Length, cost);
		}
		menu.AddItem(info, display);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_STAYOPENTIME);
}

static void PromptBlueprintName(int client, int slot) {
	ga_iPendingBlueprintSlot[client] = slot;
	if (ga_hPendingBlueprintNameTimer[client] != INVALID_HANDLE)
		KillTimer(ga_hPendingBlueprintNameTimer[client]);
	ga_hPendingBlueprintNameTimer[client] = CreateTimer(30.0, Timer_BlueprintNameTimeout, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	PrintToChat(client, "Type a name for Blueprint Slot %d in chat (max %d characters).", slot + 1, BLUEPRINT_NAME_MAX_CHARS);
	FakeClientCommand(client, "messagemode");
}

public int BlueprintSaveSlotMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param, info, sizeof(info));
		int slot = StringToInt(info);
		if (slot < 0 || slot >= BLUEPRINT_SLOT_COUNT)
			return 0;

		if (ga_hBlueprintProps[client][slot] != null && ga_hBlueprintProps[client][slot].Length > 0) {
			Menu confirm = new Menu(BlueprintOverwriteMenuHandler);
			char yesInfo[8];
			IntToString(slot, yesInfo, sizeof(yesInfo));
			confirm.SetTitle("Overwrite Blueprint Slot %d?\n%s", slot + 1, PROP_MENU_NAVIGATION_HINT);
			confirm.AddItem(yesInfo, "Yes, overwrite");
			confirm.AddItem("-1", "No");
			confirm.ExitBackButton = true;
			confirm.Display(client, MENU_STAYOPENTIME);
		} else {
			PromptBlueprintName(client, slot);
		}
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		if (param == MenuCancel_ExitBack)
			OpenRotationMenu(client);
	}
	return 0;
}

public int BlueprintOverwriteMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param, info, sizeof(info));
		int slot = StringToInt(info);
		if (slot >= 0 && slot < BLUEPRINT_SLOT_COUNT)
			PromptBlueprintName(client, slot);
		else
			OpenRotationMenu(client);
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		if (param == MenuCancel_ExitBack)
			OpenBlueprintSaveSlotsMenu(client);
	}
	return 0;
}

public Action Timer_BlueprintNameTimeout(Handle timer, int userId) {
	int client = GetClientOfUserId(userId);
	if (client < 1 || client > MaxClients)
		return Plugin_Stop;

	ga_hPendingBlueprintNameTimer[client] = INVALID_HANDLE;
	if (ga_iPendingBlueprintSlot[client] >= 0) {
		ga_iPendingBlueprintSlot[client] = -1;
		if (ga_hPendingBlueprintProps[client] != null) {
			delete ga_hPendingBlueprintProps[client];
			ga_hPendingBlueprintProps[client] = null;
		}
		PrintToChat(client, "Blueprint save cancelled because no name was entered.");
	}
	return Plugin_Stop;
}

static bool IsBlueprintNameCharacter(int character) {
	if ((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9'))
		return true;

	// Ordinary label punctuation only. This keeps blueprint names readable in
	// menus and chat while SQL_EscapeString remains a second line of defence.
	switch (character) {
		case 32, 33, 38, 39, 40, 41, 43, 44, 45, 46, 63, 91, 93, 95:
			return true;
	}
	return false;
}

static bool IsValidBlueprintUtf8(const char[] text, int start, int &bytes) {
	int first = text[start] & 0xFF;
	if (first >= 0xC2 && first <= 0xDF)
		bytes = 2;
	else if (first >= 0xE0 && first <= 0xEF)
		bytes = 3;
	else if (first >= 0xF0 && first <= 0xF4)
		bytes = 4;
	else
		return false;

	for (int i = 1; i < bytes; i++) {
		int next = text[start + i] & 0xFF;
		if (next == 0 || (next & 0xC0) != 0x80)
			return false;
	}

	int second = text[start + 1] & 0xFF;
	if ((first == 0xE0 && second < 0xA0) || (first == 0xED && second > 0x9F)
		|| (first == 0xF0 && second < 0x90) || (first == 0xF4 && second > 0x8F))
		return false;

	return true;
}

static void SanitizeBlueprintName(char[] name, int maxLen) {
	char clean[BLUEPRINT_NAME_LENGTH];
	int read = 0;
	int write = 0;
	int characters = 0;

	while (name[read] != '\0' && characters < BLUEPRINT_NAME_MAX_CHARS) {
		int character = name[read] & 0xFF;
		if (character < 0x80) {
			if (IsBlueprintNameCharacter(character)) {
				clean[write++] = character;
				characters++;
			}
			read++;
			continue;
		}

		int bytes;
		if (!IsValidBlueprintUtf8(name, read, bytes)) {
			read++;
			continue;
		}
		if (write + bytes >= sizeof(clean))
			break;

		for (int i = 0; i < bytes; i++)
			clean[write++] = name[read + i];
		characters++;
		read += bytes;
	}

	clean[write] = '\0';
	strcopy(name, maxLen, clean);
	TrimString(name);
}

public Action Command_BlueprintNameSay(int client, const char[] command, int args) {
	if (client < 1 || client > MaxClients || ga_iPendingBlueprintSlot[client] < 0 || ga_hPendingBlueprintProps[client] == null)
		return Plugin_Continue;

	char name[BLUEPRINT_NAME_LENGTH];
	GetCmdArgString(name, sizeof(name));
	StripQuotes(name);
	TrimString(name);
	ReplaceString(name, sizeof(name), "\n", "");
	ReplaceString(name, sizeof(name), "\r", "");
	ReplaceString(name, sizeof(name), "\x01", "");
	ReplaceString(name, sizeof(name), "\x03", "");
	ReplaceString(name, sizeof(name), "\x04", "");
	SanitizeBlueprintName(name, sizeof(name));
	if (name[0] == '\0')
		FormatEx(name, sizeof(name), "Blueprint %d", ga_iPendingBlueprintSlot[client] + 1);

	SavePendingBlueprint(client, name);
	return Plugin_Handled;
}

static void SavePendingBlueprint(int client, const char[] name) {
	int slot = ga_iPendingBlueprintSlot[client];
	ArrayList pending = ga_hPendingBlueprintProps[client];
	if (slot < 0 || slot >= BLUEPRINT_SLOT_COUNT || pending == null)
		return;

	if (ga_hPendingBlueprintNameTimer[client] != INVALID_HANDLE) {
		KillTimer(ga_hPendingBlueprintNameTimer[client]);
		ga_hPendingBlueprintNameTimer[client] = INVALID_HANDLE;
	}

	if (ga_hBlueprintProps[client][slot] != null)
		delete ga_hBlueprintProps[client][slot];
	ga_hBlueprintProps[client][slot] = new ArrayList(ByteCountToCells(BLUEPRINT_RECORD_LENGTH));
	for (int i = 0; i < pending.Length; i++) {
		char record[BLUEPRINT_RECORD_LENGTH];
		pending.GetString(i, record, sizeof(record));
		ga_hBlueprintProps[client][slot].PushString(record);
	}
	strcopy(ga_sBlueprintName[client][slot], BLUEPRINT_NAME_LENGTH, name);

	char layout[BLUEPRINT_LAYOUT_LENGTH];
	layout[0] = '\0';
	for (int i = 0; i < pending.Length; i++) {
		char record[BLUEPRINT_RECORD_LENGTH];
		pending.GetString(i, record, sizeof(record));
		if (i > 0)
			StrCat(layout, sizeof(layout), ";");
		StrCat(layout, sizeof(layout), record);
	}

	char steamId[64], escapedSteamId[128], escapedName[BLUEPRINT_NAME_LENGTH * 2], escapedLayout[BLUEPRINT_LAYOUT_LENGTH * 2], query[BLUEPRINT_LAYOUT_LENGTH * 2 + 512];
	if (g_hBlueprintDb == null || !g_bBlueprintDbReady || !GetBlueprintSteamId(client, steamId, sizeof(steamId))) {
		PrintToChat(client, "Blueprint save failed because the database is unavailable.");
		delete ga_hPendingBlueprintProps[client];
		ga_hPendingBlueprintProps[client] = null;
		ga_iPendingBlueprintSlot[client] = -1;
		return;
	}

	SQL_EscapeString(g_hBlueprintDb, steamId, escapedSteamId, sizeof(escapedSteamId));
	SQL_EscapeString(g_hBlueprintDb, name, escapedName, sizeof(escapedName));
	SQL_EscapeString(g_hBlueprintDb, layout, escapedLayout, sizeof(escapedLayout));
	FormatEx(query, sizeof(query), "REPLACE INTO bm_props_blueprints (steamid, slot, name, layout) VALUES ('%s', %d, '%s', '%s')", escapedSteamId, slot + 1, escapedName, escapedLayout);
	SQL_TQuery(g_hBlueprintDb, SQL_SaveClientBlueprint, query, GetClientUserId(client));

	delete ga_hPendingBlueprintProps[client];
	ga_hPendingBlueprintProps[client] = null;
	ga_iPendingBlueprintSlot[client] = -1;
	PrintToChat(client, "Saved Blueprint Slot %d: %s", slot + 1, name);
	OpenRotationMenu(client);
}

public void SQL_SaveClientBlueprint(Database db, DBResultSet results, const char[] error, any data) {
	if (error[0] != '\0')
		LogError("Unable to save props blueprint for userid %d: %s", data, error);
}

static int GetBlueprintHoldCost(int client) {
	ArrayList list = ga_hBlueprintHoldData[client];
	if (list == null)
		return -1;

	int leadModelId = MID(ga_iModelIndex[client]);
	if (leadModelId < 0 || leadModelId >= PROP_COUNT)
		return -1;

	int cost = g_PropDefs[leadModelId].cost;
	for (int i = 0; i < list.Length; i++) {
		int modelId = list.Get(i, 8);
		if (modelId < 0 || modelId >= PROP_COUNT)
			return -1;
		cost += g_PropDefs[modelId].cost;
	}
	return cost;
}

static void FinishBlueprintPlacement(int client, const float leadPosition[3], const float leadAngles[3]) {
	ArrayList list = ga_hBlueprintHoldData[client];
	if (list == null)
		return;

	PropId previousModel = ga_iModelIndex[client];
	for (int i = 0; i < list.Length; i++) {
		int modelId = list.Get(i, 8);
		if (modelId < 0 || modelId >= PROP_COUNT)
			continue;

		float offset[3], angles[3], position[3];
		offset[0] = view_as<float>(list.Get(i, 1));
		offset[1] = view_as<float>(list.Get(i, 2));
		offset[2] = view_as<float>(list.Get(i, 3));
		angles[0] = view_as<float>(list.Get(i, 4)) + leadAngles[0] - ga_fBlueprintLeadAngles[client][0];
		angles[1] = view_as<float>(list.Get(i, 5)) + leadAngles[1] - ga_fBlueprintLeadAngles[client][1];
		angles[2] = view_as<float>(list.Get(i, 6)) + leadAngles[2] - ga_fBlueprintLeadAngles[client][2];
		TransformBatchOffset(client, offset, leadPosition, leadAngles, position);

		ga_iModelIndex[client] = view_as<PropId>(modelId);
		ga_iPropOwner[client] = 0;
		CreateProp(client, position, angles, 0, true, true);
	}

	ga_iModelIndex[client] = previousModel;
	ClearBlueprintHold(client);
}

static bool StartBlueprintHold(int client, int slot) {
	float now = GetGameTime();
	if (ga_fNextBlueprintLoad[client] > now) {
		PrintToChat(client, "Please wait %.1f seconds before loading another blueprint.", ga_fNextBlueprintLoad[client] - now);
		return false;
	}

	int cost = GetBlueprintCost(client, slot);
	ArrayList saved = (slot >= 0 && slot < BLUEPRINT_SLOT_COUNT) ? ga_hBlueprintProps[client][slot] : null;
	if (saved == null || cost < 0 || saved.Length < BLUEPRINT_MIN_PROPS || saved.Length > BLUEPRINT_MAX_PROPS) {
		PrintToChat(client, "That blueprint is unavailable because one of its props no longer exists.");
		return false;
	}
	if (g_iAllFree == 0 && !HasEnoughResources(client, cost)) {
		PrintToChat(client, "You cannot afford that blueprint.");
		return false;
	}

	ga_fNextBlueprintLoad[client] = now + BLUEPRINT_LOAD_COOLDOWN;
	ClearPropSelections(client);
	if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
		StopHolding(client);

	char rootRecord[BLUEPRINT_RECORD_LENGTH], rootModel[PLATFORM_MAX_PATH];
	float rootOffset[3], rootAngles[3];
	saved.GetString(0, rootRecord, sizeof(rootRecord));
	if (!ParseBlueprintRecord(rootRecord, rootModel, sizeof(rootModel), rootOffset, rootAngles))
		return false;

	int rootModelId = FindPropIdByModel(rootModel);
	if (rootModelId < 0 || rootModelId == MID(Prop_AmmoCacheSmall))
		return false;

	float rootPosition[3], eyeAngles[3];
	GetClientEyePosition(client, rootPosition);
	GetClientEyeAngles(client, eyeAngles);
	GetPositionInFront(rootPosition, eyeAngles, PROP_HOLD_DISTANCE);
	ga_iModelIndex[client] = view_as<PropId>(rootModelId);
	ga_iPropOwner[client] = 0;
	if (!CreateProp(client, rootPosition, rootAngles))
		return false;

	int lead = EntRefToEntIndex(ga_iPropHolding[client]);
	if (!IsValidNonClientEntity(lead))
		return false;
	TeleportEntity(lead, rootPosition, rootAngles, NULL_VECTOR);

	if (ga_hBlueprintHoldData[client] != null)
		delete ga_hBlueprintHoldData[client];
	ga_hBlueprintHoldData[client] = new ArrayList(PROP_BATCH_DATA_SIZE);
	ga_bHoldingBlueprint[client] = true;
	ga_fBlueprintLeadAngles[client][0] = rootAngles[0];
	ga_fBlueprintLeadAngles[client][1] = rootAngles[1];
	ga_fBlueprintLeadAngles[client][2] = rootAngles[2];

	for (int i = 1; i < saved.Length; i++) {
		char record[BLUEPRINT_RECORD_LENGTH], model[PLATFORM_MAX_PATH];
		float offset[3], angles[3], position[3];
		saved.GetString(i, record, sizeof(record));
		if (!ParseBlueprintRecord(record, model, sizeof(model), offset, angles)) {
			StopHolding(client);
			return false;
		}

		int modelId = FindPropIdByModel(model);
		if (modelId < 0 || modelId == MID(Prop_AmmoCacheSmall)) {
			StopHolding(client);
			return false;
		}

		int previewRef = CreateBatchPreview(modelId);
		if (previewRef == INVALID_ENT_REFERENCE) {
			StopHolding(client);
			return false;
		}

		int data[PROP_BATCH_DATA_SIZE];
		data[0] = INVALID_ENT_REFERENCE;
		data[1] = view_as<int>(offset[0]);
		data[2] = view_as<int>(offset[1]);
		data[3] = view_as<int>(offset[2]);
		data[4] = view_as<int>(angles[0]);
		data[5] = view_as<int>(angles[1]);
		data[6] = view_as<int>(angles[2]);
		data[7] = previewRef;
		data[8] = modelId;
		data[9] = 0;
		ga_hBlueprintHoldData[client].PushArray(data, sizeof(data));

		TransformBatchOffset(client, offset, rootPosition, rootAngles, position);
		int preview = EntRefToEntIndex(previewRef);
		if (IsValidNonClientEntity(preview))
			TeleportEntity(preview, position, angles, NULL_VECTOR);
	}

	PrintCenterText(client, "Loaded blueprint: %s\nCost: %d", ga_sBlueprintName[client][slot], cost);
	OpenRotationMenu(client);
	return true;
}

static void OpenBlueprintMenu(int client) {
	if (g_hBlueprintDb == null || !g_bBlueprintDbReady) {
		PrintToChat(client, "Blueprints are unavailable because the database could not be opened.");
		return;
	}
	if (!ga_bBlueprintsLoaded[client]) {
		LoadClientBlueprints(client);
		PrintToChat(client, "Blueprints are loading. Open the build menu again in a moment.");
		return;
	}

	int blueprintCount = 0;
	Menu menu = new Menu(BlueprintMenuHandler);
	menu.SetTitle("Blueprints\nBuild points: %d\n%s", ga_iPlayerBuildPoints[client], PROP_MENU_NAVIGATION_HINT);
	for (int slot = 0; slot < BLUEPRINT_SLOT_COUNT; slot++) {
		ArrayList list = ga_hBlueprintProps[client][slot];
		if (list == null || list.Length == 0)
			continue;

		blueprintCount++;
		char info[8], display[192];
		IntToString(slot, info, sizeof(info));
		int cost = GetBlueprintCost(client, slot);
		if (cost < 0) {
			FormatEx(display, sizeof(display), "Slot %d: %s (Unavailable)", slot + 1, ga_sBlueprintName[client][slot]);
			menu.AddItem(info, display, ITEMDRAW_DISABLED);
		} else {
			FormatEx(display, sizeof(display), "Slot %d: %s (Cost: %d)", slot + 1, ga_sBlueprintName[client][slot], cost);
			menu.AddItem(info, display, (g_iAllFree == 1 || HasEnoughResources(client, cost)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		}
	}

	if (blueprintCount == 0) {
		delete menu;
		PrintToChat(client, "You have no blueprints. Hold a group of 2 to 5 props, open Rotation page 2, then choose Save Blueprint.");
		return;
	}

	menu.ExitBackButton = true;
	ga_bPropAuxMenuOpen[client] = true;
	SetPropMenuWeaponLock(client, true);
	menu.Display(client, MENU_STAYOPENTIME);
}

public int BlueprintMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		ga_bPropAuxMenuOpen[client] = false;
		char info[8];
		menu.GetItem(param, info, sizeof(info));
		StartBlueprintHold(client, StringToInt(info));
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients) {
		ga_bPropAuxMenuOpen[client] = false;
		if (param == MenuCancel_ExitBack)
			OpenPropSelectionMenu(client);
	}
	return 0;
}

bool IsPlayerOnProp(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return false;

	int groundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	if (groundEntity <= MaxClients || groundEntity > MAXENTITIES || !IsValidEntity(groundEntity))
		return false;

	return GetPropOwner(groundEntity) > 0;
}

void JC_Stop() {
	if (g_hJammerTimer != INVALID_HANDLE) {
		KillTimer(g_hJammerTimer);
		g_hJammerTimer = INVALID_HANDLE;
	}
}

void JC_ScheduleNext(float delay = -1.0) {
	JC_Stop();
	if (delay < 0.0)
		delay = GetRandomFloat(JC_MinDelay, JC_MaxDelay);
	g_hJammerTimer = CreateTimer(delay, JC_Timer_Play, _, TIMER_FLAG_NO_MAPCHANGE);
}

void JC_AddJammer(int ent) {
	if (g_hJammers == null)
		g_hJammers = new ArrayList();
	g_hJammers.Push(EntIndexToEntRef(ent));
}

void JC_RemoveJammer(int ent) {
	if (g_hJammers == null)
		return;

	for (int i = g_hJammers.Length - 1; i >= 0; i--) {
		int idx = EntRefToEntIndex(g_hJammers.Get(i));
		if (idx == ent || idx == INVALID_ENT_REFERENCE)
			g_hJammers.Erase(i);
	}
}

int JC_PlayRandomFromAll() {
	if (g_hJammers == null || g_hJammers.Length == 0)
		return 0;

	int played = 0;
	int pick = GetRandomInt(0, sizeof(JC_Sounds) - 1);

	for (int i = g_hJammers.Length - 1; i >= 0; i--) {
		int ent = EntRefToEntIndex(g_hJammers.Get(i));
		if (ent == INVALID_ENT_REFERENCE || ent <= MaxClients || !IsValidEntity(ent)) {
			g_hJammers.Erase(i);
			continue;
		}

		EmitSoundToAll(JC_Sounds[pick], ent, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.30);
		played++;
	}

	return played;
}

public Action JC_Timer_Play(Handle timer) {
	g_hJammerTimer = INVALID_HANDLE;
	JC_PlayRandomFromAll();
	JC_ScheduleNext();
	return Plugin_Stop;
}

static bool HasAnyHumans() {
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			return true;
	return false;
}

static void EnsureTipTimer() {
	if (g_hTipTimer != null) return;
	if (!HasAnyHumans()) return;

	float delay = GetRandomFloat(600.0, 1200.0);
	g_hTipTimer = CreateTimer(delay, Timer_BuildTip, _, TIMER_FLAG_NO_MAPCHANGE);
}

static void KillTipTimer() {
	if (g_hTipTimer != null) {
		CloseHandle(g_hTipTimer);
		g_hTipTimer = null;
	}
}

public Action Timer_BuildTip(Handle timer, any data) {
	g_hTipTimer = null;

	if (HasAnyHumans()) {
		BroadcastBuildTip();
		EnsureTipTimer();
	}
	return Plugin_Stop;
}

static void BroadcastBuildTip() {
	PrintToChatAll("\x04Build:\x01 With your knife out, press \x03secondary fire\x01 / \x03bipod\x01 to open the build menu.");
	PrintToChatAll("\x04Menu keys not working?\x01 In the game console: \x03bind 5 slot5\x01 (use any key + slot5..slot9).");
}

public void OnMapEnd() {
	JC_Stop();
	if (g_hJammers != null) {
		delete g_hJammers;
		g_hJammers = null;
	}
	for (int i = 1; i <= MaxClients; i++) {
		if (ga_hUsedAmmoCacheRefs[i] != null) {
			delete ga_hUsedAmmoCacheRefs[i];
			ga_hUsedAmmoCacheRefs[i] = null;
		}
		if (ga_hHighlightedMattressRefs[i] != null) {
			ClearMattressStackHighlights(i);
			delete ga_hHighlightedMattressRefs[i];
			ga_hHighlightedMattressRefs[i] = null;
		}
		if (ga_hSelectedPropRefs[i] != null) {
			ClearPropSelections(i);
			delete ga_hSelectedPropRefs[i];
			ga_hSelectedPropRefs[i] = null;
		}
		ClearSelectablePropFlash(i);
		ga_fNextSelectableFlash[i] = 0.0;
		if (ga_hSelectableFlashRefs[i] != null) {
			delete ga_hSelectableFlashRefs[i];
			ga_hSelectableFlashRefs[i] = null;
		}
		if (ga_hBatchMoveData[i] != null) {
			delete ga_hBatchMoveData[i];
			ga_hBatchMoveData[i] = null;
		}
		if (ga_hPendingBlueprintNameTimer[i] != INVALID_HANDLE) {
			KillTimer(ga_hPendingBlueprintNameTimer[i]);
			ga_hPendingBlueprintNameTimer[i] = INVALID_HANDLE;
		}
		if (ga_hPendingBlueprintProps[i] != null) {
			delete ga_hPendingBlueprintProps[i];
			ga_hPendingBlueprintProps[i] = null;
		}
		ga_iPendingBlueprintSlot[i] = -1;
		ga_bPlaceQueued[i] = false;
		ClearBlueprintHold(i, true);
	}
	if (g_hAmmoCacheRefs != null) {
		delete g_hAmmoCacheRefs;
		g_hAmmoCacheRefs = null;
	}
	if (g_hMattressRefs != null) {
		delete g_hMattressRefs;
		g_hMattressRefs = null;
	}
	KillTipTimer();
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		SetPropMenuWeaponLock(i, false);

		// Deferred entity cleanup will not run after a plugin reload.
		KillNowRef(ga_iPropHolding[i]);
		ga_iPropHolding[i] = INVALID_ENT_REFERENCE;
		ClearBatchMove(i, true);
		ClearBlueprintHold(i, true);

		RefundAllSupply(i, true, true);

		if (ga_hPropPlaced[i] != null) {
			for (int j = ga_hPropPlaced[i].Length - 1; j >= 0; j--)
				KillNowRef(ga_hPropPlaced[i].Get(j));
			delete ga_hPropPlaced[i];
			ga_hPropPlaced[i] = null;
		}
	}

	JC_Stop();
	if (g_hJammers != null) {
		delete g_hJammers;
		g_hJammers = null;
	}
	for (int i = 1; i <= MaxClients; i++) {
		if (ga_hUsedAmmoCacheRefs[i] != null) {
			delete ga_hUsedAmmoCacheRefs[i];
			ga_hUsedAmmoCacheRefs[i] = null;
		}
		if (ga_hHighlightedMattressRefs[i] != null) {
			ClearMattressStackHighlights(i);
			delete ga_hHighlightedMattressRefs[i];
			ga_hHighlightedMattressRefs[i] = null;
		}
		ClearClientBlueprints(i);
		ClearSelectablePropFlash(i);
		if (ga_hSelectableFlashRefs[i] != null) {
			delete ga_hSelectableFlashRefs[i];
			ga_hSelectableFlashRefs[i] = null;
		}
	}
	if (g_hAmmoCacheRefs != null) {
		delete g_hAmmoCacheRefs;
		g_hAmmoCacheRefs = null;
	}
	if (g_hMattressRefs != null) {
		delete g_hMattressRefs;
		g_hMattressRefs = null;
	}
	delete g_hBlueprintDb;
	delete g_hDirectResupply;

	KillTipTimer();
}

void SetupConVars() {
	g_cvAllFree = CreateConVar("sm_props_allfree", "0", "Make all props free?; 0 - disabled, 1 - enabled", _, true, 0.0, true, 1.0);
	g_iAllFree = g_cvAllFree.IntValue;
	g_cvAllFree.AddChangeHook(OnConVarChanged);

	g_cvAmmoResupplyRange = CreateConVar("sm_ammo_resupply_range", "100",
		"Range to resupply near ammo cache");
	g_fAmmoResupplyRange = g_cvAmmoResupplyRange.FloatValue;
	g_cvAmmoResupplyRange.AddChangeHook(OnConVarChanged);

	g_cvAmmoAmount = CreateConVar("sm_ammo_resupply_amount", "4",
		"How many resupplies an ammo cache holds");
	g_iAmmoAmount = g_cvAmmoAmount.IntValue;
	g_cvAmmoAmount.AddChangeHook(OnConVarChanged);

	g_cvResupplyDelay = CreateConVar("sm_resupply_delay", "8",
		"Delay (seconds) while holding reload to resupply");
	g_iResupplyDelay = g_cvResupplyDelay.IntValue;
	g_cvResupplyDelay.AddChangeHook(OnConVarChanged);

	g_cvAmmoOnce = CreateConVar("sm_ammo_resupply_once", "1",
		"If 1, players may only resupply once per ammo cache");
	g_bAmmoOnce = g_cvAmmoOnce.BoolValue;
	g_cvAmmoOnce.AddChangeHook(OnConVarChanged);

	g_cvPropSelectionMax = CreateConVar("sm_props_selection_max", "5",
		"Maximum number of owned props a player can move as one group", _, true, 1.0, true, float(PROP_LIMIT));
	g_iPropSelectionMax = g_cvPropSelectionMax.IntValue;
	g_cvPropSelectionMax.AddChangeHook(OnConVarChanged);

	g_cvPropSelectionRadius = CreateConVar("sm_props_selection_radius", "250",
		"Maximum distance between the first selected prop and other selected props", _, true, 50.0, true, 1000.0);
	g_fPropSelectionRadius = g_cvPropSelectionRadius.FloatValue;
	g_cvPropSelectionRadius.AddChangeHook(OnConVarChanged);

}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvAllFree)
		g_iAllFree = g_cvAllFree.IntValue;
	else if (convar == g_cvAmmoResupplyRange) {
		g_fAmmoResupplyRange = g_cvAmmoResupplyRange.FloatValue;
		UpdateAmmoRangeCache();
	}
	else if (convar == g_cvAmmoAmount)
		g_iAmmoAmount = g_cvAmmoAmount.IntValue;
	else if (convar == g_cvResupplyDelay)
		g_iResupplyDelay = g_cvResupplyDelay.IntValue;
	else if (convar == g_cvAmmoOnce)
		g_bAmmoOnce = g_cvAmmoOnce.BoolValue;
	else if (convar == g_cvPropSelectionMax)
		g_iPropSelectionMax = g_cvPropSelectionMax.IntValue;
	else if (convar == g_cvPropSelectionRadius)
		g_fPropSelectionRadius = g_cvPropSelectionRadius.FloatValue;
}

void SetupDirectResupply() {
	GameData config = LoadGameConfigFile(RESUPPLY_GAMEDATA_FILE);
	if (config == null)
		SetFailState("Missing gamedata: addons/sourcemod/gamedata/%s.txt", RESUPPLY_GAMEDATA_FILE);

	g_iLastResupplyTimeOffset = config.GetOffset("CINSPlayer::LastResupplyTime");
	g_iResupplyPenaltyTimeOffset = config.GetOffset("CINSPlayer::ResupplyPenaltyTime");
	g_iResupplyCountOffset = config.GetOffset("CINSPlayer::ResupplyCount");
	if (g_iLastResupplyTimeOffset == -1
		|| g_iResupplyPenaltyTimeOffset == -1
		|| g_iResupplyCountOffset == -1) {
		delete config;
		SetFailState("Missing one or more CINSPlayer resupply offsets in %s.", RESUPPLY_GAMEDATA_FILE);
	}

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CINSPlayer::Resupply")) {
		delete config;
		SetFailState("Missing CINSPlayer::Resupply signature in %s.", RESUPPLY_GAMEDATA_FILE);
	}

	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_hDirectResupply = EndPrepSDKCall();
	delete config;

	if (g_hDirectResupply == null)
		SetFailState("Unable to prepare CINSPlayer::Resupply.");
}

stock void SafeKillIdx(int ent) {
	if (ent <= MaxClients || ent > MAXENTITIES) return;
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

stock void KillNowRef(int entref) {
	int ent = EntRefToEntIndex(entref);
	if (ent > MaxClients && IsValidEntity(ent)) {
		if (!AcceptEntityInput(ent, "Kill"))
			RemoveEntity(ent);
	}
}

static void ClearJustPlaced_NextFrame(any serial) {
	int client = GetClientFromSerial(serial);
	if (client >= 1 && client <= MaxClients)
		ga_bJustPlaced[client] = false;
}

public Action Timer_RepeatSinglePropPlacement(Handle timer, DataPack pack) {
	pack.Reset();

	int client = GetClientFromSerial(pack.ReadCell());
	int modelId = pack.ReadCell();

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;
	if (modelId < 0 || modelId >= PROP_COUNT || ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
		return Plugin_Stop;
	if (!ga_bHoldingMeleeWeapon[client])
		return Plugin_Stop;
	if (g_iAllFree == 0 && !HasEnoughResources(client, g_PropDefs[modelId].cost))
		return Plugin_Stop;

	ga_iModelIndex[client] = view_as<PropId>(modelId);
	HoldProp(client);
	OpenRotationMenu(client);
	return Plugin_Stop;
}
