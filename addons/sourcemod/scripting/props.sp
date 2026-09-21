#pragma semicolon 1
#pragma newdecls required

// Custom props require the Workshop asset pack on the server and clients:
// https://steamcommunity.com/sharedfiles/filedetails/?id=3800828440

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <dbi>
#define RESUPPLY_GAMEDATA_FILE "insurgency-bm.games"
#include <props_sentry>

#define PL_VERSION		"3.82.1"
#define BM_PROPS_LIBRARY "bm_props"
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
#define SND_BIPOD_DEPLOY "weapons/universal/uni_bipoddeploy.wav"
#define SND_BIPOD_RETRACT "weapons/universal/uni_bipodretract.wav"
#define PROP_BIPOD_HINT "\nSupports bipod mounting"
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
#define FIRING_SHUTTER_PLATE_MODEL "models/botmassacre/fortifications/bm_firing_shutter_plate.mdl"
#define OUTPOST_GATE_LEAF_MODEL "models/botmassacre/outpost/bm_outpost_gate_leaf.mdl"
#define OUTPOST_GATE_TRAVEL 98.0
#define OUTPOST_GATE_SPEED 56.0
#define FIRING_SHUTTER_TRAVEL 26.0
#define FIRING_SHUTTER_SPEED 32.0
#define FIRING_SHUTTER_USE_DISTANCE 150.0
#define SECURITY_DOOR_IMPACT_SOUND_COOLDOWN 3.0
#define PROP_GLOWHP_PERCENT			0.25
#define PROP_HALFHP_PERCENT			0.50
#define PROP_HALFHP_FLASH_TIME		1.00
#define PROP_HEALTH					6000
#define PROP_HOLD_DISTANCE			130.0
#define HEAVY_COVER_HOLD_DISTANCE	260.0
#define HEAVY_LADDER_MODEL "models/botmassacre/heavy_cover/bm_hc_ladder_surface.mdl"
#define LIFT_HOLD_DISTANCE			260.0 // Horizontal preview distance and maximum lift pickup reach, in Source units.
// Lift placement/search distances are Source units, not metres. Increasing search budgets costs more trace work.
#define BL_CALLS_PER_DIRECTION 2 // Maximum extra call stops above/below home; 2 means furthest + nearest halfway.
#define BL_LANDING_TRACE_LENGTH 96.0 // Extra outward search beyond the default post position; permits gaps before a supported landing.
#define BL_LANDING_OUTWARD_STEP 16.0 // Spacing between outward search columns; must be > 0. Smaller = finer search, more work.
#define BL_LANDING_FLOOR_SLACK 16.0 // Allowed floor-height variation and footing beyond travel endpoints; also merges nearby candidate heights.
#define BL_LANDING_MIN_NORMAL 0.7 // Minimum upward ground-normal component (1 = flat); lower values permit steeper slopes.
#define BL_LANDING_MIN_SPACING 64.0 // Minimum vertical separation between selected stops, including the home stop.
#define BL_LANDING_SCAN_STEP 8.0 // Minimum downward advance when a search ray starts inside solid geometry; not floor-height snapping.
#define BL_LANDING_SCAN_BUDGET 16 // Maximum vertical scan passes per held-preview update (every 0.25 seconds); each pass can run several traces.
#define BL_LANDING_SCAN_LIMIT 512 // Hard pass limit across all search columns; exceeding it rejects placement and keeps the preview.
#define BL_MAX_CANDIDATES 128 // Maximum validated landing candidates stored before choosing stops; exceeding it rejects placement.
#define BL_MAX_STOPS (1 + 2 * BL_CALLS_PER_DIRECTION) // Total station capacity: one home + both directions (5 by default).
#define BL_CALL_X 54.0 // Call post's local sideways offset from cabin origin, placing it beside the boarding step.
#define BL_CALL_Y -147.0 // Default post's local front/back offset; negative is outside the doorway, farther search goes more negative.
#define BL_CALL_Z 60.0 // Button housing centre above its post base, used by USE/preview; must match the compiled call model.
#define PROP_LIMIT					10		// Prop limit per player
#define PROP_PLAYER_DISTANCE		50.0
#define PROP_PICKUP_DISTANCE		200.0
#define PROP_SELECTION_RADIUS_DEFAULT	250.0
#define PROP_SELECTION_MAX_DEFAULT		5
#define PROP_SELECTION_R			70
#define PROP_SELECTION_G			160
#define PROP_SELECTION_B			255
#define PROP_BATCH_DATA_SIZE		10
#define RECENT_PROP_COUNT		10
#define PROP_MENU_NAVIGATION_HINT	"LEAN LEFT: Back | LEAN RIGHT: Next"

#define BLUEPRINT_SLOT_COUNT		10
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
#define MENU_STAYOPENTIME			60

#define SND_SUPPLYREFUND		"ui/receivedsupply.wav"
#define SND_PROP_PAGE_ROLLOVER "ui/buttonrollover.wav"
#define SND_BUYBUILDPOINTS		"ui/menu_click.wav"
#define SND_CANTBUY				"ui/vote_no.wav"

#define AMMO_CACHE_MODEL		"models/botmassacre/props/bm_resupply_bag.mdl"
#define AMMO_ICON_SPRITE		"sprites/bm/ammobag.vmt"	// https://steamcommunity.com/sharedfiles/filedetails/?id=1581225279
#define AMMO_ICON_ZOFFSET		54.0

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
	char displayName[48];
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
	Prop_FortLowWall,
	Prop_FortTallWall,
	Prop_FortCorner,
	Prop_FortWindow,
	Prop_FortDoorway,
	Prop_FortEndPost,
	Prop_FiringShutter,
	Prop_FortCeiling,
	Prop_FortRamp,
	Prop_WindowInsert,
	Prop_GuardPlatform,
	Prop_ProneBunker,
	Prop_BallisticShield,
	Prop_CornerShield,
	Prop_CrawlTunnel,
	Prop_OutpostEarthWall,
	Prop_OutpostFiringPosition,
	Prop_OutpostShelter,
	Prop_OutpostGate,
	Prop_OutpostPlatform,
	Prop_OutpostRamp,

	Prop_ArmoredLift,
	Prop_Heavy01,
	Prop_Heavy02,
	Prop_Heavy03,
	Prop_Heavy04,
	Prop_Heavy05,
	Prop_Heavy06,
	Prop_Heavy07,
	Prop_Heavy08,
	Prop_Heavy09,
	Prop_Heavy10,
	Prop_Heavy11,
	Prop_Heavy12,
	Prop_Heavy13,
	Prop_Heavy14,
	Prop_Heavy15,
	Prop_Heavy16,
	Prop_Heavy17,
	Prop_Heavy18,
	Prop_Heavy19,
	Prop_Heavy20,
	Prop_Heavy21,
	Prop_Heavy22,
	Prop_Heavy23,
	Prop_Heavy24,
	Prop_Heavy25,
	Prop_Heavy26,
	Prop_Heavy27,
	Prop_Heavy28,
	Prop_Heavy29,
	Prop_Heavy30,
	Prop_Heavy31,
	Prop_Heavy32,
	Prop_Heavy33,
	Prop_Heavy34,
	Prop_Heavy35,
	Prop_Heavy36,
	Prop_Heavy37,
	Prop_Heavy38,
	Prop_Heavy39,
	Prop_Heavy40,
	Prop_Heavy41,
	Prop_Heavy42,
	Prop_Heavy43,
	Prop_Heavy44,
	Prop_Heavy45,
	Prop_Heavy46,
	Prop_Heavy47,
	Prop_Heavy48,
	Prop_Heavy49,
	Prop_Heavy50,
	Prop_Field31,
	Prop_Field33,
	Prop_Field34,
	Prop_Field40,
	Prop_Field46,
	Prop_Field49,
	Prop_Field50,
	Prop_Field53,
	Prop_SentryGun,
	Prop_Count
};

#define MID(%1) (view_as<int>(%1))

// model, cost, blocks explosive damage?, HP, display name
static const PropDef g_PropDefs[] = {
	{ "models/fortifications/barbed_wire_02b.mdl",			3, false, 4000, "Barbed wire" },
	{ "models/static_fortifications/sandbagwall01.mdl",		1, true, 5000, "Sandbag wall" },
	{ "models/iraq/ir_twall_01.mdl",						3, true, 6000, "Concrete T-wall" },
	{ "models/iraq/ir_hesco_basket_01_row.mdl",				4, true, 7000, "HESCO barrier" },
	{ "models/static_afghan/prop_panj_stairs.mdl",			1, false, 2000, "Stairs" },
	{ "models/static_afghan/prop_interior_mattress_a.mdl",	3, false, 2000, "Mattress" },
	{ "models/static_props/container_01_open2.mdl",			6, true, 6000, "Open container" },
	{ "models/embassy/embassy_center_02.mdl",				8, true, 8000, "Embassy structure" },
	{ "models/botmassacre/props/bm_field_jammer.mdl",			5, false, 1000, "IED jammer" }, // 1 entity
	{ AMMO_CACHE_MODEL,										8, false, 1000, "Ammo bag" }, // 3 entities: bag + icon holder + sprite
	{ "models/static_props/prop_market_prison_door.mdl",	2, false, 4000, "Sliding security door" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_low_wall.mdl", 2, true, 5000, "Fort low wall" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_tall_wall.mdl", 3, true, 6000, "Fort tall wall" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_corner.mdl", 4, true, 7000, "Fort corner" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_window.mdl", 3, true, 5000, "Fort firing window" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_doorway.mdl", 2, true, 4000, "Fort doorway" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_end_post.mdl", 1, true, 2500, "Fort end post" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_firing_shutter.mdl", 4, true, 6000, "Firing shutter" }, // 2 entities: frame + shutter
	{ "models/botmassacre/fortifications/bm_fort_ceiling.mdl", 3, true, 6000, "Fort ceiling" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_ramp.mdl", 3, true, 6000, "Fort ramp" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_window_insert.mdl", 2, true, 5000, "Window insert" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_guard_platform.mdl", 4, true, 8000, "Guard platform" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_prone_bunker.mdl", 4, true, 7000, "Prone firing bunker" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_ballistic_shield.mdl", 2, true, 4000, "Steel barricade" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_corner_shield.mdl", 3, true, 6000, "Corner barricade" }, // 1 entity
	{ "models/botmassacre/fortifications/bm_fort_crawl_tunnel.mdl", 4, true, 6000, "Crawl tunnel" }, // 1 entity
	{ "models/botmassacre/outpost/bm_outpost_earth_wall.mdl", 3, true, 6000, "Outpost earth wall" }, // 1 entity
	{ "models/botmassacre/outpost/bm_outpost_firing_position.mdl", 4, true, 6000, "Outpost firing position" }, // 1 entity
	{ "models/botmassacre/outpost/bm_outpost_shelter.mdl", 5, true, 7000, "Outpost shelter" }, // 1 entity
	{ "models/botmassacre/outpost/bm_outpost_sliding_gate.mdl", 5, true, 7000, "Outpost sliding gate" }, // 2 entities: frame + gate
	{ "models/botmassacre/outpost/bm_outpost_platform.mdl", 4, true, 7000, "Outpost observation platform" }, // 1 entity
	{ "models/botmassacre/outpost/bm_outpost_ramp.mdl", 3, true, 5000, "Outpost ramp" }, // 1 entity
	{ "models/botmassacre/armored_lift_v2/bm_lift_cabin.mdl", 10, true, 50000, "Armored lift (1/player)" }, // 15 + call buttons: 16-20 entities (1-5 stations)
	{ "models/botmassacre/heavy_cover/bm_hc_01_chevron_cover.mdl", 5, true, 8000, "Chevron Cover" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_02_dogleg_entry.mdl", 5, true, 8000, "Dogleg Entry" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_03_armored_footbridge.mdl", 5, true, 8000, "Armored Footbridge" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_04_covered_stair_module.mdl", 3, true, 6000, "Covered Stair Module" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_05_twin_peek_screen.mdl", 3, true, 6000, "Twin Peek Screen" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_06_rescue_alcove.mdl", 3, true, 6000, "Rescue Alcove" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_07_horseshoe_fighting_bay.mdl", 5, true, 8000, "Horseshoe Fighting Bay" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_08_overhead_cover_module.mdl", 3, true, 6000, "Overhead Cover Module" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_09_cross_cover_block.mdl", 5, true, 8000, "Cross Cover Block" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_10_recessed_sniper_booth.mdl", 3, true, 6000, "Recessed Sniper Booth" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_11_armored_ramp.mdl", 5, true, 8000, "Armored Ramp" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_12_trench_elbow.mdl", 5, true, 8000, "Trench Elbow" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_13_t_junction_cover.mdl", 5, true, 8000, "T-Junction Cover" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_14_switchback_stairs.mdl", 5, true, 8000, "Switchback Stairs" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_15_covered_bridge.mdl", 5, true, 8000, "Covered Bridge" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_16_stepped_firing_line.mdl", 5, true, 8000, "Stepped Firing Line" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_17_prone_firing_wedge.mdl", 3, true, 6000, "Prone Firing Wedge" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_18_culvert_shelter.mdl", 3, true, 6000, "Culvert Shelter" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_19_checkpoint_chicane.mdl", 5, true, 8000, "Checkpoint Chicane" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_20_firing_balcony.mdl", 3, true, 6000, "Firing Balcony" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_21_octagonal_pillbox.mdl", 5, true, 8000, "Octagonal Pillbox" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_22_blast_deflector.mdl", 5, true, 8000, "Blast Deflector" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_23_utility_block_cover.mdl", 5, true, 8000, "Utility Block Cover" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_24_armored_bench.mdl", 5, true, 8000, "Armored Bench" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_25_recessed_door_screen.mdl", 3, true, 6000, "Recessed Door Screen" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_26_split_level_cover.mdl", 5, true, 8000, "Split-Level Cover" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_27_covered_corner_nest.mdl", 3, true, 6000, "Covered Corner Nest" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_28_roofed_passage.mdl", 5, true, 8000, "Roofed Passage" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_29_staggered_cover_islands.mdl", 5, true, 8000, "Staggered Cover Islands" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_30_observation_perch.mdl", 5, true, 8000, "Observation Perch" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_31_curved_breastwork.mdl", 5, true, 8000, "Curved Breastwork" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_32_angled_crawlway.mdl", 5, true, 8000, "Angled Crawlway" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_33_bridge_elbow.mdl", 5, true, 8000, "Bridge Elbow" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_34_ramp_landing.mdl", 5, true, 8000, "Ramp Landing" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_35_split_firing_nest.mdl", 5, true, 8000, "Split Firing Nest" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_36_blast_drum.mdl", 3, true, 6000, "Blast Drum" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_37_covered_zigzag.mdl", 5, true, 8000, "Covered Zigzag" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_38_armored_workbench.mdl", 3, true, 6000, "Armored Workbench" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_39_sentry_ring.mdl", 5, true, 8000, "Sentry Ring" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_40_two_way_firing_screen.mdl", 5, true, 8000, "Two-Way Firing Screen" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_41_stairhead_shield.mdl", 3, true, 6000, "Stairhead Shield" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_42_underpass_block.mdl", 5, true, 8000, "Underpass Block" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_43_sloped_roof_shelter.mdl", 3, true, 6000, "Sloped Roof Shelter" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_44_offset_peek_wall.mdl", 3, true, 6000, "Offset Peek Wall" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_45_corner_buttress.mdl", 3, true, 6000, "Corner Buttress" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_46_twin_ramp_crossing.mdl", 5, true, 8000, "Twin Ramp Crossing" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_47_trench_endcap.mdl", 3, true, 6000, "Trench Endcap" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_48_three_sided_firing_post.mdl", 5, true, 8000, "Three-Sided Firing Post" }, // 1 entity; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_49_protected_ladder_bay.mdl", 4, true, 8000, "Protected Ladder Bay" }, // 2 entities: bay + native ladder surface; 35-unit armor
	{ "models/botmassacre/heavy_cover/bm_hc_50_command_redoubt.mdl", 5, true, 8000, "Command Redoubt" }, // 1 entity; 35-unit armor
	// Field Fortifications: each prop uses one parent and one native ladder surface.
	{ "models/botmassacre/field_fortifications/bm_ff_31_square_roof_post.mdl", 5, true, 8000, "Square Roof Post" },
	{ "models/botmassacre/field_fortifications/bm_ff_33_octagon_roof_post.mdl", 5, true, 8000, "Octagon Roof Post" },
	{ "models/botmassacre/field_fortifications/bm_ff_34_corner_watch_deck.mdl", 5, true, 8000, "Corner Watch Deck" },
	{ "models/botmassacre/field_fortifications/bm_ff_40_long_wall_walk.mdl", 5, true, 8000, "Long Wall Walk" },
	{ "models/botmassacre/field_fortifications/bm_ff_46_wall_end_lookout.mdl", 5, true, 8000, "Wall-End Lookout" },
	{ "models/botmassacre/field_fortifications/bm_ff_49_narrow_observation_post.mdl", 5, true, 8000, "Narrow Observation Post" },
	{ "models/botmassacre/field_fortifications/bm_ff_50_broad_command_deck.mdl", 5, true, 8000, "Broad Command Deck" },
	{ "models/botmassacre/field_fortifications/bm_ff_53_tall_steel_ladder.mdl", 2, false, 3000, "Tall Steel Ladder" },
	{ "models/botmassacre/sentry_v1/bm_sentry_assembly.mdl", 10, false, 4000, "Sentry Gun" }
};

#define PROP_COUNT (sizeof(g_PropDefs))

enum PropCategory {
	Category_Favourites,
	Category_Recent,
	Category_Walls,
	Category_Firing,
	Category_Shelters,
	Category_Movement,
	Category_Utilities,
	Category_All,
	Category_Count
};

#define PROP_LIST_PAGE_SIZE 6
static const char g_sPropCategoryNames[][] = {
	"Favourites", "Recent props", "Walls & cover", "Firing positions",
	"Shelters & bunkers", "Movement & access", "Utilities", "All props"
};
PropCategory ga_iPropCategory[MAXPLAYERS + 1] = {Category_All, ...};
int ga_iPropCategoryPage[MAXPLAYERS + 1][Category_Count];
bool ga_bFavouriteProp[MAXPLAYERS + 1][PROP_COUNT];
bool ga_bFavouritesLoaded[MAXPLAYERS + 1];
bool ga_bFavouritesLoading[MAXPLAYERS + 1];
bool ga_bFavouriteSaving[MAXPLAYERS + 1];
int ga_iFavouriteGeneration[MAXPLAYERS + 1];
int ga_iRotationMenuGeneration[MAXPLAYERS + 1];
bool ga_bRefreshingRotationMenu[MAXPLAYERS + 1];
bool g_bFavouriteDbReady;


int g_iHeavyLadderRef[MAXENTITIES + 1] = {INVALID_ENT_REFERENCE, ...};
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
int		ga_iMattressLaunchGeneration[MAXPLAYERS + 1];
int		g_iMattressLaunchEpoch;

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
float	ga_fShopMenuCooldown[MAXPLAYERS + 1] = {0.0, ...};
float	ga_fWireSoundCooldown[MAXENTITIES + 1] = {0.0, ...};
float	ga_fSecurityDoorNextTouch[MAXENTITIES + 1] = {0.0, ...};
float	ga_fSecurityDoorImpactSound[MAXENTITIES + 1] = {0.0, ...};
float	ga_fSecurityDoorClosedOrigin[MAXENTITIES + 1][3];
bool	ga_bSecurityDoorOpen[MAXENTITIES + 1] = {false, ...};
Handle	ga_hSecurityDoorCloseTimer[MAXENTITIES + 1] = {INVALID_HANDLE, ...};
int ga_iShutterPlateRef[MAXENTITIES + 1] = {INVALID_ENT_REFERENCE, ...};
int ga_iShutterFrameRef[MAXENTITIES + 1] = {INVALID_ENT_REFERENCE, ...};
Handle ga_hShutterMoveTimer[MAXENTITIES + 1];
float ga_fShutterOffset[MAXENTITIES + 1];
float ga_fShutterGoal[MAXENTITIES + 1];
float ga_fShutterMoveTime[MAXENTITIES + 1];
float ga_fShutterNextUse[MAXENTITIES + 1];
int ga_iShutterUserId[MAXENTITIES + 1];

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
Handle	g_hSetBipodState = null;
Handle	ga_hFortBipodTimer[MAXPLAYERS + 1];
int		ga_iFortBipodRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iFortBipodWeaponRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
bool	ga_bFortBipodMounted[MAXPLAYERS + 1];
bool	ga_bFortBipodButtonConsumed[MAXPLAYERS + 1];
bool	ga_bPropBipodSoundActive[MAXPLAYERS + 1];
int		ga_iBipodCapabilityWeaponRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
bool	ga_bCachedBipodCapability[MAXPLAYERS + 1];
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
	RegPluginLibrary(BM_PROPS_LIBRARY);
	CreateNative("BMProps_FindPlacedJammer", Native_FindPlacedJammer);
	CreateNative("BMProps_IsSentryBotTargeting", SGB_NativeControlsBot);
	return APLRes_Success;
}

// Lift model paths. Replacement models must match the dimensions, origins and skins expected by the lift code.
#define LIFT_MODEL "models/botmassacre/armored_lift_v2/bm_lift_cabin.mdl" // Main cabin: mover collision and separate visible shell.
#define SHUTTER_MODEL "models/botmassacre/armored_lift_v2/bm_lift_shutter.mdl" // Shared model for the three sliding window shutters.
#define DOOR_MODEL "models/botmassacre/armored_lift_v2/bm_lift_door.mdl" // Shared model for the two sliding entrance doors.
#define CALL_MODEL "models/botmassacre/armored_lift_v2/bm_lift_call.mdl" // Outside call button and post; non-solid and damage-immune.
#define FLOOR_HATCH_L_MODEL "models/botmassacre/armored_lift_v2/bm_lift_floor_hatch_l.mdl" // Left sliding floor-hatch leaf.
#define FLOOR_HATCH_R_MODEL "models/botmassacre/armored_lift_v2/bm_lift_floor_hatch_r.mdl" // Right sliding floor-hatch leaf.
#define ROOF_HATCH_L_MODEL "models/botmassacre/armored_lift_v2/bm_lift_roof_hatch_l.mdl" // Left sliding roof-hatch leaf.
#define ROOF_HATCH_R_MODEL "models/botmassacre/armored_lift_v2/bm_lift_roof_hatch_r.mdl" // Right sliding roof-hatch leaf.
#define CLIMB_MODEL "models/botmassacre/armored_lift_v2/bm_lift_climb.mdl" // Hidden climb/collision mesh enabled when the roof ladder is deployed.
#define BUTTON_CLICK "ui/buttonclick.wav" // Click sound for cabin buttons and outside call buttons; paths omit sound/.
#define LIFT_SPEED 96.0 // Cabin's vertical travel speed in Source units per second.
#define DECK_HALF 108.0 // Legacy half-width constant, currently unused; changing it does not resize the lift.
#define DECK_TOP 35.0 // Cabin floor surface above model origin; used by rider checks and guides, not a model-resize setting.


// Lift sound paths are relative to sound/. Volumes are set at the EmitSoundToAll calls, not here.
#define BL_BELL "soundscape/emitters/oneshot/lift_bell.ogg" // Cabin bell when an outside call starts a trip.
#define BL_TRAVEL "soundscape/emitters/loop/elevator_moving_loop.wav" // Travel loop started with movement and stopped when the lift stops.
#define BL_DOOR "physics/doors/rollerdoors/roller_door_05_moving.wav" // Sound played when the front doors start moving.
#define BL_COLLAPSE "soundscape/emitters/oneshot/building_near_collapse_01.ogg" // One-time warning when the lift first reaches red/low health.

enum struct BMLift {
	char OwnerSteamID[32];
	int OwnerTeam;
	int Lift;
	int Visual;
	bool Moving;
	bool Removing;
	bool Failed;
	bool Red;
	bool DoorSound;
	float Home[3];
	float Height;
	float Depth;
	int TargetStop;
	float Yaw;
	float TargetZ;
	float LastZ;
	float LastProgress;
	Handle Timer;
	Handle PanelTimer;
	int Panels[5];
	int Calls[BL_MAX_STOPS];
	int StopCount;
	float Stops[BL_MAX_STOPS];
	float CallY[BL_MAX_STOPS];
	float CallBase[BL_MAX_STOPS];
	int Hatches[4];
	int Ladder[3];
	int Climb;
	bool LadderEnabled;
	float HatchOffset[2];
	float HatchGoal[2];
	float PanelOffset[5];
	float PanelGoal[5];
	float PanelTime;
	int BlastTick;
	int BlastSource;
	float BlastDamage;
}
// Detached lifts use slots beyond player indices. Each lift needs at least 16 entities.
#define BL_SLOT_COUNT (MAXPLAYERS + 1 + MAXENTITIES / 16)
BMLift g_BL[BL_SLOT_COUNT];
Handle g_BLPendingTimer;
enum struct BMLiftScan {
	int PreviewRef;
	float Origin[3];
	float Yaw;
	float Height;
	float Depth;
	float Cursor;
	float Outward;
	float NextScan;
	bool Done;
	bool Overflow;
	int Steps;
	int Count;
	int Surfaces;
	int ClearanceRejected;
	int SupportRejected;
	float Candidates[BL_MAX_CANDIDATES];
	float CandidateY[BL_MAX_CANDIDATES];
	float CandidateBase[BL_MAX_CANDIDATES];
	int StopCount;
	float Stops[BL_MAX_STOPS];
	float CallY[BL_MAX_STOPS];
	float CallBase[BL_MAX_STOPS];
}
BMLiftScan g_BLScan[MAXPLAYERS + 1];
int g_BLHeldOwnerSerial[MAXPLAYERS + 1];
bool g_BLHeldRed[MAXPLAYERS + 1];
float g_BLNextGuide[MAXPLAYERS + 1];
float g_BLNextGuideHint[MAXPLAYERS + 1];
char g_BLLastGuideHint[MAXPLAYERS + 1][192];
int g_BLBeam;
bool g_BLReady;
int g_BLSlot[MAXENTITIES + 1];
int g_BLRef[MAXENTITIES + 1];
static const char g_BLHatchModels[][] = {FLOOR_HATCH_L_MODEL, FLOOR_HATCH_R_MODEL, ROOF_HATCH_L_MODEL, ROOF_HATCH_R_MODEL};
static const char g_BLLadderModels[][] = {"models/botmassacre/armored_lift_v2/bm_lift_ladder0.mdl", "models/botmassacre/armored_lift_v2/bm_lift_ladder1.mdl", "models/botmassacre/armored_lift_v2/bm_lift_ladder2.mdl"};
static const float g_BLPanelClosed[5][3] = {{0.0,105.0,83.0}, {-105.0,0.0,83.0}, {105.0,0.0,83.0}, {-22.0,-105.0,35.0}, {22.0,-106.0,35.0}};
static const float g_BLPanelTravel[5] = {24.0,24.0,24.0,30.0,30.0};
static const float g_BLPanelYaw[5] = {0.0,90.0,-90.0,0.0,0.0};


public void OnGameFrame() {
	SG_OnGameFrame();
	SGB_OnGameFrame();
}

public void OnPluginStart() {
	SG_Init();
	for (int slot = 1; slot < BL_SLOT_COUNT; slot++) {
		BL_InitSlot(slot);
	}
	int enumCount  = view_as<int>(Prop_Count);
	int arrayCount = PROP_COUNT;

	if (enumCount != arrayCount) {
		SetFailState("PropId count (%d) != g_PropDefs count (%d). Update the enum or the array order.", enumCount, arrayCount);
		return;
	}

	SetupConVars();
	SetupSDKCalls();
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
	HookEvent("weapon_deploy",     Event_PropBipodWeaponDeploy, EventHookMode_Post);
	HookEvent("player_pick_squad", Event_PlayerPickSquad);
	HookEvent("player_team", Event_LiftOwnerTeam, EventHookMode_Post);
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
	}

	g_iOffLaggedMovementValue = FindSendPropInfo("CBasePlayer", "m_flLaggedMovementValue");

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart() {
	SG_ResetSentries();
	PrecacheFiles();
	for (int client = 1; client <= MaxClients; client++) {
		ga_iBipodCapabilityWeaponRef[client] = INVALID_ENT_REFERENCE;
		ga_bPropBipodSoundActive[client] = false;
	}

	if (g_hAmmoCacheRefs != null)
		delete g_hAmmoCacheRefs;
	g_hAmmoCacheRefs = new ArrayList();

	if (g_hMattressRefs != null)
		delete g_hMattressRefs;
	g_hMattressRefs = new ArrayList();

	for (int i = 0; i <= MAXENTITIES; i++) {
		ga_fWireSoundCooldown[i] = 0.0;
		ga_iShutterPlateRef[i] = INVALID_ENT_REFERENCE;
		ga_iShutterFrameRef[i] = INVALID_ENT_REFERENCE;
		ga_hShutterMoveTimer[i] = null;
		ga_fShutterOffset[i] = 0.0;
		ga_fShutterGoal[i] = 0.0;
		ga_fShutterNextUse[i] = 0.0;
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

	SG_HookClient(client);

	ga_fLastTouchTime[client]    = 0.0;
	ga_fShopMenuCooldown[client] = 0.0;
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
	ga_iPropCategory[client] = Category_All;
	for (int category; category < view_as<int>(Category_Count); category++)
		ga_iPropCategoryPage[client][category] = 0;
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
		RequestFrame(BL_ReclaimDeferred, GetClientSerial(client));
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
	SGB_ResetClient(client);
	SG_OwnerLeaving(client);
	BL_OwnerLeaving(client, true);
	g_BLNextGuide[client] = 0.0;

	ga_bPropBipodSoundActive[client] = false;
	StopFortBipod(client);
	ga_bFortBipodButtonConsumed[client] = false;
	ga_iBipodCapabilityWeaponRef[client] = INVALID_ENT_REFERENCE;
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
		BL_OwnerLeaving(client);
		DeconstructAllProps(client);
		ga_bPlayerRefund[client] = true;
	}

	ga_iTokensSpent[client] = 0;
	RestoreBuildPoints(client);
	SetModelIndex(client);
	RequestFrame(BL_ReclaimDeferred, GetClientSerial(client));

	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	SG_RemoveAllSentries();
	BL_ClearPending();
	g_iMattressLaunchEpoch++;
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

	SGB_ResetClient(client);
	ga_iMattressLaunchGeneration[client]++;
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

	SGB_ResetClient(victim);
	ga_bPropBipodSoundActive[victim] = false;
	StopFortBipod(victim);
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
			int sentry = SG_DamageSentry(0, inflictor);
			if (sentry && event.GetInt("attacker") == SG_g_Sentries[sentry].Owner) {
				int killer = GetClientOfUserId(event.GetInt("attacker"));
				if (killer > 0 && IsClientInGame(killer) && !IsFakeClient(killer) && GetClientTeam(killer) != GetClientTeam(victim))
					LogToGame("\"%L\" triggered \"sentry_kill\"", killer);
				event.SetString("weapon", "Sentry Gun");
				return Plugin_Changed;
			}
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

static int GetPlayerLift(int client) {
	int ground = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	int slot = BL_Find(ground);
	if (!slot && IsValidNonClientEntity(ground) && GetTrackedPropId(ground) == MID(Prop_AmmoCacheSmall))
		slot = BL_Find(GetEntPropEnt(ground, Prop_Data, "m_hMoveParent"));
	return slot > 0 && !BL_IsCallStation(slot, ground) ? slot : 0;
}

static bool IsLiftPlacementBlocked(int client) {
	return GetPlayerLift(client) > 0 && (ga_iModelIndex[client] != Prop_AmmoCacheSmall
		|| ga_bHoldingBlueprint[client]
		|| (ga_hBatchMoveData[client] != null && ga_hBatchMoveData[client].Length > 0));
}

void GetHeldPositionInFront(int client, float position[3], const float eyeAngles[3]) {
	if (ga_iModelIndex[client] == Prop_ArmoredLift) {
		float horizontalAngles[3];
		horizontalAngles[1] = eyeAngles[1];
		GetClientAbsOrigin(client, position);
		GetPositionInFront(position, horizontalAngles, LIFT_HOLD_DISTANCE);
	} else
		GetPositionInFront(position, eyeAngles, ga_iModelIndex[client] >= Prop_Heavy01 && ga_iModelIndex[client] <= Prop_Field53 ? HEAVY_COVER_HOLD_DISTANCE : PROP_HOLD_DISTANCE);
}

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
	if (!IsPlayerOnGround(client) || IsLiftPlacementBlocked(client))
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
	int root = SG_Root(ent);
	if (root != -1) {
		SG_UpdateDamageColor(SG_EntitySlot(root), GetEntProp(root, Prop_Data, "m_iHealth"), true);
		return;
	}

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
		if (GetTrackedPropId(ent) == MID(Prop_AmmoCacheSmall) || GetTrackedPropId(ent) == MID(Prop_SentryGun))
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
	GetHeldPositionInFront(client, vPos, vAng);
	CreateProp(client, vPos, NULL_VECTOR);
}

static void TouchLaggedMovementValue(int client) {
	if (g_iOffLaggedMovementValue <= 0)
		return;
	float cur = GetEntDataFloat(client, g_iOffLaggedMovementValue);
	SetEntDataFloat(client, g_iOffLaggedMovementValue, cur, true);
}

void StopHolding(int client, bool now = false, bool keepGroupPreview = false) {
	g_BLScan[client].PreviewRef = INVALID_ENT_REFERENCE;
	g_BLNextGuideHint[client] = 0.0;
	if (g_BLHeldOwnerSerial[client]) {
		g_BLHeldOwnerSerial[client] = 0;
		g_BLHeldRed[client] = false;
		ga_iPropOwner[client] = 0;
	}
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

	// Preview cleanup must never delete a registered part of a built lift.
	int held = EntRefToEntIndex(ref);
	if (BL_Find(held)) {
		LogError("[BM lift] Prevented held-preview cleanup from deleting lift part %d (client %d, ref %d).", held, client, ref);
		return;
	}

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
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;
	if (IsFakeClient(client))
		return SGB_RunCmd(client, buttons, angles);

	if (ga_bPropBipodSoundActive[client] && !(GetEntProp(client, Prop_Send, "m_iPlayerFlags") & PF_DEPLOY_BIPOD))
		PlayPropBipodSound(client, false);

	int inputButtons = buttons;
	bool buttonsChanged = false;
	if (!(inputButtons & BTN_SPECIAL1))
		ga_bFortBipodButtonConsumed[client] = false;
	if (ga_bFortBipodButtonConsumed[client]) {
		buttons &= ~BTN_SPECIAL1;
		buttonsChanged = true;
	}
	SyncPropMenuWeaponLock(client);
	if (AnyPropMenuFlagOpen(client) && (inputButtons & (BTN_SPRINT | BTN_SPRINT_TOGGLE))) {
		CloseAllPropMenus(client);
		ga_iLastButtons[client] = inputButtons;
		return Plugin_Continue;
	}

	int pressed = inputButtons & ~ga_iLastButtons[client];
	if (ga_iFortBipodRef[client] != INVALID_ENT_REFERENCE
		&& (inputButtons & (BTN_JUMP | BTN_DUCK | BTN_DUCK_TOGGLE | BTN_FORWARD | BTN_BACKWARD | BTN_LEFT | BTN_RIGHT | BTN_SPRINT | BTN_SPRINT_TOGGLE)))
		StopFortBipod(client);
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
	if (pressed & BTN_SPECIAL1) {
		if (HandleFortBipodButton(client, inputButtons)) {
			ga_bFortBipodButtonConsumed[client] = true;
			buttons &= ~BTN_SPECIAL1;
			buttonsChanged = true;
		}
		else
			OnButtonPress(client, BTN_SPECIAL1, vel);
	}
	if (pressed & (BTN_DUCK | BTN_DUCK_TOGGLE | BTN_FORWARD | BTN_BACKWARD | BTN_LEFT | BTN_RIGHT))
		OnButtonPress(client, pressed & (BTN_DUCK | BTN_DUCK_TOGGLE | BTN_FORWARD | BTN_BACKWARD | BTN_LEFT | BTN_RIGHT), vel);
	if (pressed & BTN_FIREMODE)
		OnButtonPress(client, BTN_FIREMODE, vel);

	ga_iLastButtons[client] = inputButtons;

	if ((pressed & BTN_USE)
		&& ga_iPropHolding[client] == INVALID_ENT_REFERENCE && !AnyPropMenuFlagOpen(client)) {
		if (!ga_bHoldingMeleeWeapon[client])
			QueueFiringShutterUse(client);
		RequestFrame(BL_Use, GetClientSerial(client));
	}

	if (!ga_bHoldingMeleeWeapon[client]) {
		if (ga_hHighlightedMattressRefs[client] != null && ga_hHighlightedMattressRefs[client].Length > 0)
			ClearMattressStackHighlights(client);
		return buttonsChanged ? Plugin_Changed : Plugin_Continue;
	}

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
		if (g_BLHeldOwnerSerial[client])
			StopHolding(client);
		ga_iPropHolding[client] = INVALID_ENT_REFERENCE;
		ga_bHeldPreviewPosValid[client] = false;
		ClearMattressStackHighlights(client);
		return buttonsChanged ? Plugin_Changed : Plugin_Continue;
	}

	float vAng[3];
	GetClientEyeAngles(client, vAng);

	float vPos[3];
	GetClientEyePosition(client, vPos);
	GetHeldPositionInFront(client, vPos, vAng);

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
	if (BL_HoldingLift(client))
		BL_DrawGuides(client, ent, heldAngles[1]);
	UpdateHeldPropPreviewColor(client, ent, vPos, heldAngles, vel);
	UpdateBatchMovePreviews(client, vPos, heldAngles, vel);
	UpdateMattressStackHighlights(client, vPos);

	return buttonsChanged ? Plugin_Changed : Plugin_Continue;
}

static void QueuePropSelectionToggle(int client) {
	if (ga_bSelectionQueued[client])
		return;

	int target = ResolveFiringShutterFrame(GetClientAimTarget(client, false));
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
		|| GetTrackedPropId(target) == MID(Prop_AmmoCacheSmall) || GetTrackedPropId(target) == MID(Prop_ArmoredLift) || GetTrackedPropId(target) == MID(Prop_SentryGun))
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
		if (ResolveFiringShutterFrame(GetEntPropEnt(client, Prop_Send, "m_hGroundEntity")) == prop)
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
	if (modelId == MID(Prop_ArmoredLift)) {
		BL_Pickup(client, target);
		return;
	}
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
		if (ga_bHoldingMeleeWeapon[client]) {
			if (AnyPropMenuFlagOpen(client)) {
				if (ga_iPropHolding[client] == INVALID_ENT_REFERENCE) {
					CloseAllPropMenus(client, false);
					OpenPropSelectionMenu(client);
				}
				return;
			}

			OpenPropSelectionMenu(client);
		}
		return;
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
			
			int target = ResolveFiringShutterFrame(GetClientAimTarget(client, false));

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
				
				float pickupDistance = modelId == MID(Prop_ArmoredLift) ? LIFT_HOLD_DISTANCE : PROP_PICKUP_DISTANCE;
				if (GetVectorDistance(vEye, vPos, true) > pickupDistance * pickupDistance) {
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

			if (IsLiftPlacementBlocked(client)) {
				PrintCenterText(client, "You can only place an ammo bag while standing on a lift.");
				EndPlaceLock(client);
				return;
			}

			if (vel[0] != 0.0 || vel[1] != 0.0 || vel[2] != 0.0) { EndPlaceLock(client); return; }

			float vAng[3];
			GetClientEyeAngles(client, vAng);
			float vPos[3];
			GetClientEyePosition(client, vPos);
			GetHeldPositionInFront(client, vPos, vAng);

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

			if (ga_iModelIndex[client] == Prop_SentryGun) {
				bool relocating = ga_iPropOwner[client] > 0;
				if (CreateProp(client, vPos, vAng, GetEntProp(ent, Prop_Data, "m_iHealth"), true)) {
					StopHolding(client);
					CloseAllPropMenus(client);
					if (!relocating)
						RecordRecentPropModel(client, MID(Prop_SentryGun));
				}
				EndPlaceLock(client);
				RequestFrame(ClearJustPlaced_NextFrame, GetClientSerial(client));
				return;
			}

			if (ga_iModelIndex[client] == Prop_ArmoredLift) {
				bool relocating = g_BLHeldOwnerSerial[client] != 0;
				bool placed = CreateProp(client, vPos, vAng, GetEntProp(ent, Prop_Data, "m_iHealth"), true);
				if (placed) {
					StopHolding(client);
					CloseAllPropMenus(client);
					if (!relocating)
						RecordRecentPropModel(client, MID(Prop_ArmoredLift));
				}
				EndPlaceLock(client);
				RequestFrame(ClearJustPlaced_NextFrame, GetClientSerial(client));
				return;
			}

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

			if (placed && selectedModelId != MID(Prop_ArmoredLift) && !holdingBlueprint && !movingBatch && !movingExisting && (g_iAllFree == 1 || HasEnoughResources(client, selectedCost))) {
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
	GetEntPropVector(prop, Prop_Data, "m_vecAbsOrigin", vPos);

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

public void OnConfigsExecuted() {
	if (g_bLateLoad) {
		RebuildPlacedPropTracking();
		g_bLateLoad = false;
	}
}

static void RebuildPlacedPropTracking() {
	char name[64];
	if (g_hJammers == null)
		g_hJammers = new ArrayList();
	else
		g_hJammers.Clear();

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
		else if (modelId == MID(Prop_IedJammer) && IsSolidPlacedJammer(ent)) {
			JC_AddJammer(ent);
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
	if (solid && IsLiftPlacementBlocked(client)) {
		PrintCenterText(client, "You can only place an ammo bag while standing on a lift.");
		return false;
	}
	if (!IsPlayerOnGround(client)) {
		PrintCenterText(client, "You cannot build a prop while falling!");
		return false;
	}

	bool bMovingExisting = (ga_iPropOwner[client] > 0);

	PropId modelId = ga_iModelIndex[client];
	int mid = MID(modelId);
	int buildCost = (g_iAllFree == 1) ? 0 : g_PropDefs[mid].cost;
	if (modelId == Prop_ArmoredLift) {
		int owner = BL_PlacementOwner(client);
		if (BL_FindPending(owner)) {
			PrintToChat(client, "[BM lift] Your previous lift still has passengers. Return to its team to reclaim it, or wait until it is removed.");
			return false;
		}
		if ((g_BL[owner].Lift != INVALID_ENT_REFERENCE && (solid || !g_BLHeldOwnerSerial[client]))
			|| BL_OwnerHasHeldLift(owner, client)) {
			PrintToChat(client, "[BM lift] You can't build more than one lift per owner, including a picked-up lift.");
			return false;
		}
	}

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

	if (modelId == Prop_SentryGun) {
		if (!SG_CanBuild(client, solid))
			return false;
		if (solid)
			return SG_Build(client, vPos, vAng, oldhealth);
	}

	if (modelId == Prop_ArmoredLift && solid) {
		if (FloatAbs(vAng[0]) > 0.1 || FloatAbs(vAng[2]) > 0.1) {
			PrintToChat(client, "[BM lift] Lift supports spin only. Reset pitch and roll before building.");
			return false;
		}
		return BL_Build(client, vPos, vAng[1], oldhealth);
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

	if (solid && IsMovingPanelProp(mid) && !CreateFiringShutterPlate(prop, modelId == Prop_OutpostGate)) {
		SafeKillIdx(prop);
		PrintCenterText(client, "Unable to create the moving panel. No build points spent.");
		return false;
	}
	if (solid && IsNativeLadderProp(mid) && !CreateHeavyLadderSurface(prop, mid)) {
		SafeKillIdx(prop);
		PrintCenterText(client, "Unable to create the ladder surface. No build points spent.");
		return false;
	}

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
			}

			if (!ClearOldestPropIfLimitReached(client)) {
				SafeKillIdx(prop);
				return false;
			}
			if (g_iAllFree != 1)
				ga_iPlayerBuildPoints[client] -= g_PropDefs[mid].cost;

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
				if (!ClearOldestPropIfLimitReached(client)) {
					SafeKillIdx(prop);
					return false;
				}

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
					PrintCenterText(client, "%s built by: %N\nHealth: %d/%d%s", modelName, owner, hp, maxHealth, IsFortBipodProp(mid) ? PROP_BIPOD_HINT : "");
				OpenRotationMenu(client);
			} else {
				if (mattressStack > 1)
					PrintCenterText(client, "%s\nHealth: %d/%d\nStack x%d - boost %.0f", modelName, hp, maxHealth, mattressStack, mattressBoost);
				else
					PrintCenterText(client, "%s\nHealth: %d/%d%s", modelName, hp, maxHealth, IsFortBipodProp(mid) ? PROP_BIPOD_HINT : "");
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
		BL_AttachAmmoBag(client, prop);
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

	if (solid && IsMovingPanelProp(mid)) {
		SetEntProp(prop, Prop_Send, "m_nBody", 1);
		UpdateFiringShutterPosition(prop);
	}

	if (solid && IsNativeLadderProp(mid)) {
		int ladder = EntRefToEntIndex(g_iHeavyLadderRef[prop]);
		float zero[3];
		SetVariantString("!activator");
		AcceptEntityInput(ladder, "SetParent", prop, ladder);
		TeleportEntity(ladder, zero, zero, NULL_VECTOR);
	}

	// A moved prop is recreated internally, so only log genuinely new builds.
	if (solid && !bMovingExisting)
		LogPropBuild(client, modelId);

	return true;
}

static int ResolveFiringShutterFrame(int entity) {
	int sentry = SG_Root(entity);
	if (sentry != -1)
		return sentry;
	int lift = BL_Find(entity);
	if (lift)
		return BL_LiftEntity(lift);
	if (!IsValidNonClientEntity(entity))
		return entity;
	int parent = GetEntPropEnt(entity, Prop_Data, "m_hMoveParent");
	if (IsValidNonClientEntity(parent) && g_iHeavyLadderRef[parent] == EntIndexToEntRef(entity))
		return parent;

	int frame = EntRefToEntIndex(ga_iShutterFrameRef[entity]);
	return IsValidNonClientEntity(frame) ? frame : entity;
}

static bool IsNativeLadderProp(int modelId) {
	return modelId == MID(Prop_Heavy49) || (modelId >= MID(Prop_Field31) && modelId <= MID(Prop_Field53));
}

static void GetNativeLadderModel(int modelId, char[] model, int maxLength) {
	if (modelId == MID(Prop_Heavy49)) {
		strcopy(model, maxLength, HEAVY_LADDER_MODEL);
		return;
	}
	strcopy(model, maxLength, g_PropDefs[modelId].model);
	ReplaceString(model, maxLength, ".mdl", "_ladder.mdl");
}

static bool CreateHeavyLadderSurface(int frame, int modelId) {
	int ladder = CreateEntityByName("prop_dynamic_override");
	if (!IsValidNonClientEntity(ladder))
		return false;
	char model[PLATFORM_MAX_PATH];
	GetNativeLadderModel(modelId, model, sizeof(model));
	DispatchKeyValue(ladder, "model", model);
	DispatchKeyValue(ladder, "solid", "6");
	DispatchKeyValue(ladder, "disableshadows", "1");
	if (!DispatchSpawn(ladder)) {
		SafeKillIdx(ladder);
		return false;
	}
	SetEntProp(ladder, Prop_Send, "m_fEffects", GetEntProp(ladder, Prop_Send, "m_fEffects") | 32);
	SetEntProp(ladder, Prop_Data, "m_takedamage", DAMAGE_NO);
	SetEntityMoveType(ladder, MOVETYPE_NONE);
	g_iHeavyLadderRef[frame] = EntIndexToEntRef(ladder);
	return true;
}

static bool IsMovingPanelProp(int modelId) {
	return modelId == MID(Prop_FiringShutter) || modelId == MID(Prop_OutpostGate);
}

static bool CreateFiringShutterPlate(int frame, bool outpostGate) {
	int plate = CreateEntityByName("prop_dynamic_override");
	if (!IsValidNonClientEntity(plate))
		return false;

	DispatchKeyValue(plate, "model", outpostGate ? OUTPOST_GATE_LEAF_MODEL : FIRING_SHUTTER_PLATE_MODEL);
	DispatchKeyValue(plate, "solid", "6");
	DispatchKeyValue(plate, "physdamagescale", "0.0");
	DispatchKeyValue(plate, "targetname", outpostGate ? "bm_outpost_gate_leaf" : "bm_firing_shutter_plate");
	if (!DispatchSpawn(plate)) {
		SafeKillIdx(plate);
		return false;
	}

	SetEntityMoveType(plate, MOVETYPE_NONE);
	SetEntProp(plate, Prop_Data, "m_takedamage", DAMAGE_YES);
	SetEntProp(plate, Prop_Data, "m_iHealth", 6000);
	ga_iShutterPlateRef[frame] = EntIndexToEntRef(plate);
	ga_iShutterFrameRef[plate] = EntIndexToEntRef(frame);
	ga_fShutterOffset[frame] = 0.0;
	ga_fShutterGoal[frame] = 0.0;
	ga_fShutterNextUse[frame] = 0.0;
	SDKHook(plate, SDKHook_OnTakeDamage, SHook_ShutterPlateDamage);
	SDKHook(plate, SDKHook_Touch, SHook_ShutterPlateTouch);
	return true;
}

static void UpdateFiringShutterPosition(int frame) {
	int plate = EntRefToEntIndex(ga_iShutterPlateRef[frame]);
	if (!IsValidNonClientEntity(plate))
		return;

	float origin[3], angles[3], axisForward[3], right[3], up[3];
	GetEntPropVector(frame, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(frame, Prop_Send, "m_angRotation", angles);
	GetAngleVectors(angles, axisForward, right, up);
	if (GetTrackedPropId(frame) == MID(Prop_OutpostGate)) {
		for (int axis = 0; axis < 3; axis++)
			origin[axis] += axisForward[axis] * ga_fShutterOffset[frame];
	} else {
		for (int axis = 0; axis < 3; axis++)
			origin[axis] += right[axis] * 5.25 + up[axis] * (65.0 + ga_fShutterOffset[frame]);
	}
	TeleportEntity(plate, origin, angles, NULL_VECTOR);
}

static bool FiringShutterSweepHitsPlayer(int frame, float nextOffset) {
	float origin[3], angles[3], axisForward[3], right[3], up[3];
	GetEntPropVector(frame, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(frame, Prop_Send, "m_angRotation", angles);
	GetAngleVectors(angles, axisForward, right, up);
	ScaleVector(right, -1.0);
	float low = ga_fShutterOffset[frame] < nextOffset ? ga_fShutterOffset[frame] : nextOffset;
	float high = ga_fShutterOffset[frame] > nextOffset ? ga_fShutterOffset[frame] : nextOffset;
	if (GetTrackedPropId(frame) == MID(Prop_OutpostGate)) {
		float gateMins[3] = {-52.0, -11.75, 0.0};
		float gateMaxs[3] = {52.0, -5.0, 95.0};
		gateMins[0] += low;
		gateMaxs[0] += high;
		return SecurityDoorBoxWouldTrapAnyPlayer(origin, gateMins, gateMaxs, axisForward, right, up);
	}
	float mins[3] = {-20.0, -6.5, 0.0};
	float maxs[3] = {20.0, -4.0, 0.0};
	mins[2] = 52.5 + low;
	maxs[2] = 77.5 + high;
	return SecurityDoorBoxWouldTrapAnyPlayer(origin, mins, maxs, axisForward, right, up);
}

static void QueueFiringShutterUse(int client) {
	if (GetClientTeam(client) != TEAM_SECURITY)
		return;

	int frame = ResolveFiringShutterFrame(GetClientAimTarget(client, false));
	if (!IsValidNonClientEntity(frame) || !IsMovingPanelProp(GetTrackedPropId(frame)))
		return;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(EntIndexToEntRef(frame));
	RequestFrame(NF_UseFiringShutter, pack);
}

static void NF_UseFiringShutter(any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	int frame = EntRefToEntIndex(pack.ReadCell());
	delete pack;
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client)
		|| GetClientTeam(client) != TEAM_SECURITY || ga_bHoldingMeleeWeapon[client]
		|| ga_iPropHolding[client] != INVALID_ENT_REFERENCE || AnyPropMenuFlagOpen(client)
		|| !IsValidNonClientEntity(frame) || !IsMovingPanelProp(GetTrackedPropId(frame))
		|| ResolveFiringShutterFrame(GetClientAimTarget(client, false)) != frame)
		return;

	float eye[3], origin[3];
	bool outpostGate = GetTrackedPropId(frame) == MID(Prop_OutpostGate);
	GetClientEyePosition(client, eye);
	GetEntPropVector(frame, Prop_Data, "m_vecAbsOrigin", origin);
	float useDistance = outpostGate ? 200.0 : FIRING_SHUTTER_USE_DISTANCE;
	if (GetVectorDistance(eye, origin, true) > useDistance * useDistance) {
		PrintCenterText(client, "Move closer to operate the %s.", outpostGate ? "gate" : "shutter");
		return;
	}
	if (ga_fShutterNextUse[frame] > GetGameTime() || !IsValidNonClientEntity(EntRefToEntIndex(ga_iShutterPlateRef[frame])))
		return;

	ga_fShutterNextUse[frame] = GetGameTime() + 0.35;
	float goal = ga_fShutterGoal[frame] > 0.0 ? 0.0 : (outpostGate ? OUTPOST_GATE_TRAVEL : FIRING_SHUTTER_TRAVEL);
	if (outpostGate && FiringShutterSweepHitsPlayer(frame, goal)) {
		PrintCenterText(client, "Gate cannot move: a player is in its path.");
		return;
	}
	ga_fShutterGoal[frame] = goal;
	StopFortBipodsOnFrame(frame);
	ga_fShutterMoveTime[frame] = GetGameTime();
	ga_iShutterUserId[frame] = GetClientUserId(client);
	if (ga_hShutterMoveTimer[frame] == null)
		ga_hShutterMoveTimer[frame] = CreateTimer(0.04, Timer_MoveFiringShutter, EntIndexToEntRef(frame), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	PlaySecurityDoorSound(frame, ga_fShutterGoal[frame] > 0.0 ? SECURITY_DOOR_OPEN_SOUND : SECURITY_DOOR_CLOSE_SOUND, 0.45);
}

public Action Timer_MoveFiringShutter(Handle timer, int frameRef) {
	int frame = EntRefToEntIndex(frameRef);
	if (!IsValidNonClientEntity(frame) || ga_hShutterMoveTimer[frame] != timer)
		return Plugin_Stop;
	if (!IsValidNonClientEntity(EntRefToEntIndex(ga_iShutterPlateRef[frame]))) {
		ga_hShutterMoveTimer[frame] = null;
		return Plugin_Stop;
	}

	float now = GetGameTime();
	float speed = GetTrackedPropId(frame) == MID(Prop_OutpostGate) ? OUTPOST_GATE_SPEED : FIRING_SHUTTER_SPEED;
	float step = speed * (now - ga_fShutterMoveTime[frame]);
	ga_fShutterMoveTime[frame] = now;
	float goal = ga_fShutterGoal[frame];
	float next = ga_fShutterOffset[frame];
	if (next < goal) {
		next += step;
		if (next > goal)
			next = goal;
	} else {
		next -= step;
		if (next < goal)
			next = goal;
	}
	if (FiringShutterSweepHitsPlayer(frame, next)) {
		ga_hShutterMoveTimer[frame] = null;
		int client = GetClientOfUserId(ga_iShutterUserId[frame]);
		if (client > 0 && IsClientInGame(client))
			PrintCenterText(client, "%s stopped: a player is in its path.", GetTrackedPropId(frame) == MID(Prop_OutpostGate) ? "Gate" : "Shutter");
		return Plugin_Stop;
	}
	ga_fShutterOffset[frame] = next;
	UpdateFiringShutterPosition(frame);
	if (EntRefToEntIndex(frameRef) != frame || ga_hShutterMoveTimer[frame] != timer)
		return Plugin_Stop;
	if (next == goal) {
		ga_hShutterMoveTimer[frame] = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action SHook_ShutterPlateDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float force[3], float position[3]) {
	int frame = ResolveFiringShutterFrame(entity);
	// The frame already receives radial blast damage; do not charge it twice.
	if (frame != entity && IsValidNonClientEntity(frame) && !(damagetype & DMG_BLAST))
		SDKHooks_TakeDamage(frame, inflictor, attacker, damage, damagetype, weapon, force, position, false);
	return Plugin_Handled;
}

public Action SHook_ShutterPlateTouch(int entity, int touch) {
	int frame = ResolveFiringShutterFrame(entity);
	if (frame != entity && IsValidNonClientEntity(frame))
		return SHook_OnTouchPropTakeDamage(frame, touch);
	return Plugin_Continue;
}

static void RemoveFiringShutterParts(int entity) {
	if (ga_hShutterMoveTimer[entity] != null) {
		KillTimer(ga_hShutterMoveTimer[entity]);
		ga_hShutterMoveTimer[entity] = null;
	}
	int plateRef = ga_iShutterPlateRef[entity];
	ga_iShutterPlateRef[entity] = INVALID_ENT_REFERENCE;
	int plate = EntRefToEntIndex(plateRef);
	if (IsValidNonClientEntity(plate)) {
		ga_iShutterFrameRef[plate] = INVALID_ENT_REFERENCE;
		SafeKillRef(plateRef);
	}
	int frameRef = ga_iShutterFrameRef[entity];
	ga_iShutterFrameRef[entity] = INVALID_ENT_REFERENCE;
	int frame = EntRefToEntIndex(frameRef);
	if (IsValidNonClientEntity(frame)) {
		ga_iShutterPlateRef[frame] = INVALID_ENT_REFERENCE;
		SafeKillRef(frameRef);
	}
	ga_fShutterOffset[entity] = 0.0;
	ga_fShutterGoal[entity] = 0.0;
	ga_fShutterNextUse[entity] = 0.0;
}

static void StopFiringShutters(bool removePlates) {
	for (int entity = MaxClients + 1; entity <= MAXENTITIES; entity++) {
		if (ga_hShutterMoveTimer[entity] != null) {
			KillTimer(ga_hShutterMoveTimer[entity]);
			ga_hShutterMoveTimer[entity] = null;
		}
		if (removePlates) {
			int ref = ga_iShutterPlateRef[entity];
			ga_iShutterPlateRef[entity] = INVALID_ENT_REFERENCE;
			int plate = EntRefToEntIndex(ref);
			if (IsValidNonClientEntity(plate)) {
				ga_iShutterFrameRef[plate] = INVALID_ENT_REFERENCE;
				KillNowRef(ref);
			}
		}
	}
}

static void LogPropBuild(int client, PropId modelId) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;
	if (modelId < Prop_BarbWire || modelId >= Prop_Count)
		return;

	// Keep existing generic awards alongside the new zero-point prop categories.
	if (modelId >= Prop_MarketPrisonDoor)
		LogToGame("\"%L\" triggered \"build_prop\"", client);

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
		case Prop_MarketPrisonDoor: strcopy(action, sizeof(action), "build_market_prison_door");
		case Prop_FortLowWall: strcopy(action, sizeof(action), "build_fort_low_wall");
		case Prop_FortTallWall: strcopy(action, sizeof(action), "build_fort_tall_wall");
		case Prop_FortCorner: strcopy(action, sizeof(action), "build_fort_corner");
		case Prop_FortWindow: strcopy(action, sizeof(action), "build_fort_window");
		case Prop_FortDoorway: strcopy(action, sizeof(action), "build_fort_doorway");
		case Prop_FortEndPost: strcopy(action, sizeof(action), "build_fort_end_post");
		case Prop_FiringShutter: strcopy(action, sizeof(action), "build_firing_shutter");
		case Prop_FortCeiling: strcopy(action, sizeof(action), "build_fort_ceiling");
		case Prop_FortRamp: strcopy(action, sizeof(action), "build_fort_ramp");
		case Prop_WindowInsert: strcopy(action, sizeof(action), "build_window_insert");
		case Prop_GuardPlatform: strcopy(action, sizeof(action), "build_guard_platform");
		case Prop_ProneBunker: strcopy(action, sizeof(action), "build_prone_bunker");
		case Prop_BallisticShield: strcopy(action, sizeof(action), "build_ballistic_shield");
		case Prop_CornerShield: strcopy(action, sizeof(action), "build_corner_shield");
		case Prop_CrawlTunnel: strcopy(action, sizeof(action), "build_crawl_tunnel");
		case Prop_OutpostEarthWall: strcopy(action, sizeof(action), "build_outpost_earth_wall");
		case Prop_OutpostFiringPosition: strcopy(action, sizeof(action), "build_outpost_firing_position");
		case Prop_OutpostShelter: strcopy(action, sizeof(action), "build_outpost_shelter");
		case Prop_OutpostGate: strcopy(action, sizeof(action), "build_outpost_gate");
		case Prop_OutpostPlatform: strcopy(action, sizeof(action), "build_outpost_platform");
		case Prop_OutpostRamp: strcopy(action, sizeof(action), "build_outpost_ramp");
		case Prop_ArmoredLift: strcopy(action, sizeof(action), "build_armored_lift");
		case Prop_Heavy01: strcopy(action, sizeof(action), "build_heavy01");
		case Prop_Heavy02: strcopy(action, sizeof(action), "build_heavy02");
		case Prop_Heavy03: strcopy(action, sizeof(action), "build_heavy03");
		case Prop_Heavy04: strcopy(action, sizeof(action), "build_heavy04");
		case Prop_Heavy05: strcopy(action, sizeof(action), "build_heavy05");
		case Prop_Heavy06: strcopy(action, sizeof(action), "build_heavy06");
		case Prop_Heavy07: strcopy(action, sizeof(action), "build_heavy07");
		case Prop_Heavy08: strcopy(action, sizeof(action), "build_heavy08");
		case Prop_Heavy09: strcopy(action, sizeof(action), "build_heavy09");
		case Prop_Heavy10: strcopy(action, sizeof(action), "build_heavy10");
		case Prop_Heavy11: strcopy(action, sizeof(action), "build_heavy11");
		case Prop_Heavy12: strcopy(action, sizeof(action), "build_heavy12");
		case Prop_Heavy13: strcopy(action, sizeof(action), "build_heavy13");
		case Prop_Heavy14: strcopy(action, sizeof(action), "build_heavy14");
		case Prop_Heavy15: strcopy(action, sizeof(action), "build_heavy15");
		case Prop_Heavy16: strcopy(action, sizeof(action), "build_heavy16");
		case Prop_Heavy17: strcopy(action, sizeof(action), "build_heavy17");
		case Prop_Heavy18: strcopy(action, sizeof(action), "build_heavy18");
		case Prop_Heavy19: strcopy(action, sizeof(action), "build_heavy19");
		case Prop_Heavy20: strcopy(action, sizeof(action), "build_heavy20");
		case Prop_Heavy21: strcopy(action, sizeof(action), "build_heavy21");
		case Prop_Heavy22: strcopy(action, sizeof(action), "build_heavy22");
		case Prop_Heavy23: strcopy(action, sizeof(action), "build_heavy23");
		case Prop_Heavy24: strcopy(action, sizeof(action), "build_heavy24");
		case Prop_Heavy25: strcopy(action, sizeof(action), "build_heavy25");
		case Prop_Heavy26: strcopy(action, sizeof(action), "build_heavy26");
		case Prop_Heavy27: strcopy(action, sizeof(action), "build_heavy27");
		case Prop_Heavy28: strcopy(action, sizeof(action), "build_heavy28");
		case Prop_Heavy29: strcopy(action, sizeof(action), "build_heavy29");
		case Prop_Heavy30: strcopy(action, sizeof(action), "build_heavy30");
		case Prop_Heavy31: strcopy(action, sizeof(action), "build_heavy31");
		case Prop_Heavy32: strcopy(action, sizeof(action), "build_heavy32");
		case Prop_Heavy33: strcopy(action, sizeof(action), "build_heavy33");
		case Prop_Heavy34: strcopy(action, sizeof(action), "build_heavy34");
		case Prop_Heavy35: strcopy(action, sizeof(action), "build_heavy35");
		case Prop_Heavy36: strcopy(action, sizeof(action), "build_heavy36");
		case Prop_Heavy37: strcopy(action, sizeof(action), "build_heavy37");
		case Prop_Heavy38: strcopy(action, sizeof(action), "build_heavy38");
		case Prop_Heavy39: strcopy(action, sizeof(action), "build_heavy39");
		case Prop_Heavy40: strcopy(action, sizeof(action), "build_heavy40");
		case Prop_Heavy41: strcopy(action, sizeof(action), "build_heavy41");
		case Prop_Heavy42: strcopy(action, sizeof(action), "build_heavy42");
		case Prop_Heavy43: strcopy(action, sizeof(action), "build_heavy43");
		case Prop_Heavy44: strcopy(action, sizeof(action), "build_heavy44");
		case Prop_Heavy45: strcopy(action, sizeof(action), "build_heavy45");
		case Prop_Heavy46: strcopy(action, sizeof(action), "build_heavy46");
		case Prop_Heavy47: strcopy(action, sizeof(action), "build_heavy47");
		case Prop_Heavy48: strcopy(action, sizeof(action), "build_heavy48");
		case Prop_Heavy49: strcopy(action, sizeof(action), "build_heavy49");
		case Prop_Heavy50: strcopy(action, sizeof(action), "build_heavy50");
		case Prop_Field31: strcopy(action, sizeof(action), "build_field31");
		case Prop_Field33: strcopy(action, sizeof(action), "build_field33");
		case Prop_Field34: strcopy(action, sizeof(action), "build_field34");
		case Prop_Field40: strcopy(action, sizeof(action), "build_field40");
		case Prop_Field46: strcopy(action, sizeof(action), "build_field46");
		case Prop_Field49: strcopy(action, sizeof(action), "build_field49");
		case Prop_Field50: strcopy(action, sizeof(action), "build_field50");
		case Prop_Field53: strcopy(action, sizeof(action), "build_field53");
		case Prop_SentryGun: strcopy(action, sizeof(action), "build_sentry_gun");
		default: return;
	}

	LogToGame("\"%L\" triggered \"%s\"", client, action);
}

bool ClearOldestPropIfLimitReached(int client) {
	ArrayList list = ga_hPropPlaced[client];
	if (list == null)
		return true;

	int index;
	while (list.Length >= PROP_LIMIT && index < list.Length) {
		int ref = list.Get(index);
		if (BL_HasHumanRider(ref)) {
			index++;
			continue;
		}
		int ent = EntRefToEntIndex(ref);
		if (ent > MaxClients && IsValidEntity(ent)) {
			DispatchKeyValue(ent, "targetname", "bmprop_deleted");
			SafeKillRef(ref);
		}
		list.Erase(index);
	}
	if (list.Length < PROP_LIMIT)
		return true;
	PrintToChat(client, "[BM lift] Can't make room for another prop while players are inside or on the lift. Your preview is kept.");
	return false;
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
	SDKHooks_TakeDamage(entity, client, client, PROP_DAMAGE_TAKE, DMG_SLASH, -1, NULL_VECTOR, NULL_VECTOR, BL_Find(entity) != 0 || SG_EntitySlot(entity) != 0);
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

	// Base velocity has a limited network range; apply strong launches outside the touch callback.
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(++ga_iMattressLaunchGeneration[client]);
	pack.WriteCell(g_iMattressLaunchEpoch);
	pack.WriteFloat(velocity[0]);
	pack.WriteFloat(velocity[1]);
	pack.WriteFloat(velocity[2]);
	RequestFrame(NF_ApplyMattressBoost, pack);
}

static void NF_ApplyMattressBoost(any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	int generation = pack.ReadCell();
	int epoch = pack.ReadCell();
	float boost[3];
	boost[0] = pack.ReadFloat();
	boost[1] = pack.ReadFloat();
	boost[2] = pack.ReadFloat();
	delete pack;

	if (client < 1 || client > MaxClients || epoch != g_iMattressLaunchEpoch)
		return;
	if (generation != ga_iMattressLaunchGeneration[client] || !IsClientInGame(client) || !IsPlayerAlive(client))
		return;

	MoveType moveType = GetEntityMoveType(client);
	if (moveType == MOVETYPE_NONE || moveType == MOVETYPE_NOCLIP || moveType == MOVETYPE_OBSERVER || moveType == MOVETYPE_LADDER)
		return;

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	velocity[0] += boost[0];
	velocity[1] += boost[1];
	velocity[2] = boost[2];

	// Ground movement would otherwise clear the new upward velocity.
	SetEntPropEnt(client, Prop_Send, "m_hGroundEntity", -1);
	SetEntityFlags(client, GetEntityFlags(client) & ~FL_ONGROUND);
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
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
	Action result = SG_g_SentryCount > 0 ? SG_FilterBotDamage(victim, attacker, inflictor) : Plugin_Continue;
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
	return result;
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
				int hitPropId = GetTrackedPropId(ResolveFiringShutterFrame(hitEnt));
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
	SG_Destroyed(entity);
	BL_Destroyed(entity);
	int ladderRef = g_iHeavyLadderRef[entity];
	g_iHeavyLadderRef[entity] = INVALID_ENT_REFERENCE;
	if (IsValidNonClientEntity(EntRefToEntIndex(ladderRef)))
		SafeKillRef(ladderRef);

	if (IsFortBipodProp(ga_iTrackedPropId[entity]))
		StopFortBipodsOnFrame(entity);

	RemoveFiringShutterParts(entity);

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
	DrawPanelText(panel, "Use = Toggle your prop selection (blue)");
	DrawPanelText(panel, "Move a selected prop = Move the whole group");
	DrawPanelText(panel, "Rotation menu: Reload = Reset rotation");
	DrawPanelText(panel, "Lean Left = Back | Lean Right = Next page");
	DrawPanelText(panel, "Lean Left from Rotation = Place built prop if valid");
	DrawPanelText(panel, "Bipod = Build menu | Cycle Firemode = Shop");
	DrawPanelText(panel, "With firearm: Use = Open/close shutter or gate");
	DrawPanelText(panel, " ");
	DrawPanelText(panel, "[B] in build menu = Bipod support");
	DrawPanelText(panel, " ");
	DrawPanelItem(panel, "Sprint or Shoot = Cancel/close");
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

static void PlayPropBipodSound(int client, bool deployed) {
	if (ga_bPropBipodSoundActive[client] == deployed)
		return;
	ga_bPropBipodSoundActive[client] = deployed;
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
		return;
	EmitSoundToClient(client, deployed ? SND_BIPOD_DEPLOY : SND_BIPOD_RETRACT, client, SNDCHAN_ITEM, SNDLEVEL_NORMAL);
}

static void StopFortBipod(int client) {
	if (ga_iFortBipodRef[client] == INVALID_ENT_REFERENCE)
		return;
	delete ga_hFortBipodTimer[client];
	if (ga_bFortBipodMounted[client] && IsClientInGame(client) && IsPlayerAlive(client) && g_hSetBipodState != null)
		SDKCall(g_hSetBipodState, client, false);
	if (ga_bFortBipodMounted[client])
		PlayPropBipodSound(client, false);
	ga_iFortBipodRef[client] = INVALID_ENT_REFERENCE;
	ga_iFortBipodWeaponRef[client] = INVALID_ENT_REFERENCE;
	ga_bFortBipodMounted[client] = false;
	ga_bBipodForced[client] = false;
	ga_iEntIdBipodDeployedOn[client] = INVALID_ENT_REFERENCE;
}

static void StopFortBipodsOnFrame(int frame) {
	for (int client = 1; client <= MaxClients; client++)
		if (ga_iFortBipodRef[client] != INVALID_ENT_REFERENCE && ga_iEntIdBipodDeployedOn[client] == frame)
			StopFortBipod(client);
}

public bool Trace_FortBipod(int entity, int contentsMask, any client) {
	return entity != client;
}

static bool IsFortBipodProp(int modelId) {
	return modelId == MID(Prop_FortLowWall) || modelId == MID(Prop_SandbagWall)
		|| modelId == MID(Prop_GuardPlatform) || modelId == MID(Prop_OutpostPlatform);
}

static bool HeldPropSupportsBipod(int client) {
	int prop = EntRefToEntIndex(ga_iPropHolding[client]);
	return IsValidNonClientEntity(prop) && IsFortBipodProp(GetTrackedPropId(prop));
}

static bool FortBipodViewClear(int client) {
	float eye[3], angles[3], direction[3], end[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	for (int axis; axis < 3; axis++)
		end[axis] = eye[axis] + direction[axis] * 12.0;
	Handle trace = TR_TraceRayFilterEx(eye, end, MASK_SHOT, RayType_EndPoint, Trace_FortBipod, client);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace);
	delete trace;
	return clear;
}

static bool FortBipodRay(int client, const float eye[3], const float direction[3], const float origin[3], const float axisX[3], const float axisY[3], const float axisZ[3], float halfWidth, float minZ, float maxZ, float nearPlane = -4.5, float farPlane = 4.5) {
	// After deployment, support checks and the short actual-eye trace replace the aperture test.
	if (ga_bFortBipodMounted[client])
		return true;
	float delta[3];
	SubtractVectors(eye, origin, delta);
	float y = GetVectorDotProduct(delta, axisY);
	float dy = GetVectorDotProduct(direction, axisY);
	float dz = GetVectorDotProduct(direction, axisZ);
	if (FloatAbs(dy) < 0.5 || y * dy >= 0.0)
		return false;
	float x = GetVectorDotProduct(delta, axisX);
	float z = GetVectorDotProduct(delta, axisZ);
	float dx = GetVectorDotProduct(direction, axisX);
	float farDistance;
	for (int face = 0; face < 2; face++) {
		float plane = face == 0 ? nearPlane : farPlane;
		float distance = (plane - y) / dy;
		float hitX = x + distance * dx;
		float hitZ = z + distance * dz;
		if (distance <= 0.0 || distance > 90.0 || FloatAbs(hitX) > halfWidth
			|| hitZ < minZ || hitZ > maxZ)
			return false;
		if (distance > farDistance)
			farDistance = distance;
	}
	float end[3];
	for (int axis = 0; axis < 3; axis++)
		end[axis] = eye[axis] + direction[axis] * farDistance;
	Handle trace = TR_TraceRayFilterEx(eye, end, MASK_SHOT, RayType_EndPoint, Trace_FortBipod, client);
	bool clear = !TR_DidHit(trace);
	delete trace;
	return clear;
}

static float FortBipodSafeHeight(int client, float desiredHeight) {
	float eye[3], feet[3];
	GetClientEyePosition(client, eye);
	GetClientAbsOrigin(client, feet);
	// Raising only the camera lets the player fire from behind solid cover without exposing their body.
	float currentHeight = eye[2] - feet[2];
	return desiredHeight < currentHeight ? desiredHeight : currentHeight;
}

static bool CanMountSandbagBipod(int client, int sandbag, float &viewHeight) {
	float origin[3], feet[3];
	GetEntPropVector(sandbag, Prop_Send, "m_vecOrigin", origin);
	GetClientAbsOrigin(client, feet);
	if (GetVectorDistance(origin, feet, true) > 43.0 * 43.0 || FloatAbs(feet[2] - origin[2]) > 10.0)
		return false;
	viewHeight = FortBipodSafeHeight(client, 55.0);
	return ga_bFortBipodMounted[client] || GetClientAimTarget(client, false) == sandbag;
}

static bool CanMountAddedFortBipod(int client, int frame, int modelId, float &viewHeight) {
	float origin[3], angles[3], axisX[3], axisY[3], axisZ[3], feet[3], delta[3];
	GetEntPropVector(frame, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(frame, Prop_Send, "m_angRotation", angles);
	GetAngleVectors(angles, axisX, axisY, axisZ);
	ScaleVector(axisY, -1.0);
	if (axisZ[2] < 0.9962)
		return false;
	GetClientAbsOrigin(client, feet);
	SubtractVectors(feet, origin, delta);
	float feetZ = GetVectorDotProduct(delta, axisZ);
	bool platform = modelId == MID(Prop_GuardPlatform) || modelId == MID(Prop_OutpostPlatform);
	if (FloatAbs(feetZ - (platform ? 48.0 : 0.0)) > (platform ? 4.0 : 10.0))
		return false;
	if (platform && (FloatAbs(GetVectorDotProduct(delta, axisX)) > 40.0 || FloatAbs(GetVectorDotProduct(delta, axisY)) > 40.0))
		return false;

	float halfWidth = 19.0, minZ = 30.5, maxZ = 39.5, mountZ = 36.0;
	float offsetY = 0.0, nearPlane = -4.5, farPlane = 4.5;
	if (platform) {
		halfWidth = 38.0;
		minZ = modelId == MID(Prop_GuardPlatform) ? 92.5 : 95.0;
		maxZ = minZ + 26.0;
		mountZ = minZ + 6.5;
		offsetY = -45.0;
		nearPlane = -3.5;
		farPlane = 3.5;
	}

	float eye[3], direction[3], mountedEye[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	viewHeight = FortBipodSafeHeight(client, (mountZ - feetZ) / axisZ[2]);
	for (int axis; axis < 3; axis++)
		mountedEye[axis] = eye[axis];
	mountedEye[2] = feet[2] + viewHeight;
	// Low openings require a suitable stance; do not pull a standing view through cover.
	if (!ga_bFortBipodMounted[client]) {
		if (FloatAbs(mountedEye[2] - eye[2]) > 18.0)
			return false;
		Handle trace = TR_TraceRayFilterEx(eye, mountedEye, MASK_SHOT, RayType_EndPoint, Trace_FortBipod, client);
		bool blocked = TR_DidHit(trace) || TR_StartSolid(trace);
		delete trace;
		if (blocked)
			return false;
	}

	// Each edge has its own local plane. Platforms allow only the deck side, not the stairs or outside.
	for (int edge; edge < (platform ? 3 : 1); edge++) {
		float ledge[3], along[3], inward[3];
		for (int axis; axis < 3; axis++) {
			along[axis] = edge == 0 ? axisX[axis] : axisY[axis];
			inward[axis] = edge == 0 ? axisY[axis] : (edge == 1 ? axisX[axis] : -axisX[axis]);
			ledge[axis] = origin[axis] + inward[axis] * offsetY;
		}
		SubtractVectors(feet, ledge, delta);
		float side = GetVectorDotProduct(delta, inward);
		if (side < 12.0 || side > 43.0 || FloatAbs(GetVectorDotProduct(delta, along)) > halfWidth)
			continue;
		if (FortBipodRay(client, mountedEye, direction, ledge, along, inward, axisZ, halfWidth, minZ, maxZ, nearPlane, farPlane))
			return true;
	}
	return false;
}


static bool CanMountFortBipod(int client, int frame, float &viewHeight) {
	if (!IsValidNonClientEntity(frame) || GetPropOwner(frame) < 1)
		return false;
	int modelId = GetTrackedPropId(frame);
	if (!IsFortBipodProp(modelId))
		return false;
	if (ga_bFortBipodMounted[client] && !FortBipodViewClear(client))
		return false;
	if (modelId == MID(Prop_SandbagWall))
		return CanMountSandbagBipod(client, frame, viewHeight);
	if (modelId == MID(Prop_GuardPlatform) || modelId == MID(Prop_OutpostPlatform))
		return CanMountAddedFortBipod(client, frame, modelId, viewHeight);
	float halfWidth = 41.0, minZ = 48.5, maxZ = 74.0, mountZ = 55.0;

	float origin[3], angles[3], axisX[3], axisY[3], axisZ[3], feet[3], delta[3];
	GetEntPropVector(frame, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(frame, Prop_Send, "m_angRotation", angles);
	GetAngleVectors(angles, axisX, axisY, axisZ);
	ScaleVector(axisY, -1.0);
	if (axisZ[2] < 0.9962)
		return false;
	GetClientAbsOrigin(client, feet);
	SubtractVectors(feet, origin, delta);
	float side = FloatAbs(GetVectorDotProduct(delta, axisY));
	if (side < 12.0 || side > 43.0 || FloatAbs(GetVectorDotProduct(delta, axisX)) > halfWidth
		|| FloatAbs(GetVectorDotProduct(delta, axisZ)) > 10.0)
		return false;

	float eye[3], direction[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	if (!FortBipodRay(client, eye, direction, origin, axisX, axisY, axisZ, halfWidth, minZ, maxZ))
		return false;
	viewHeight = FortBipodSafeHeight(client, (mountZ - GetVectorDotProduct(delta, axisZ)) / axisZ[2]);
	if (FloatAbs(eye[2] - feet[2] - viewHeight) < 0.1)
		return true;
	eye[2] = feet[2] + viewHeight;
	return FortBipodRay(client, eye, direction, origin, axisX, axisY, axisZ, halfWidth, minZ, maxZ);
}

static bool HandleFortBipodButton(int client, int buttons) {
	if (ga_iFortBipodRef[client] != INVALID_ENT_REFERENCE) {
		StopFortBipod(client);
		return true;
	}
	if (g_hSetBipodState == null || ga_bHoldingMeleeWeapon[client] || ga_bBipodForced[client]
		|| GetClientTeam(client) != TEAM_SECURITY || AnyPropMenuFlagOpen(client)
		|| ga_iPropHolding[client] != INVALID_ENT_REFERENCE || !WeaponWithBipod(client)
		|| (GetEntProp(client, Prop_Send, "m_iPlayerFlags") & PF_DEPLOY_BIPOD)
		|| (buttons & (BTN_JUMP | BTN_DUCK | BTN_DUCK_TOGGLE | BTN_FORWARD | BTN_BACKWARD | BTN_LEFT | BTN_RIGHT | BTN_SPRINT | BTN_SPRINT_TOGGLE)))
		return false;
	float height;
	int limit = GetMaxEntities();
	if (limit > MAXENTITIES + 1)
		limit = MAXENTITIES + 1;
	for (int frame = MaxClients + 1; frame < limit; frame++) {
		if (!IsFortBipodProp(ga_iTrackedPropId[frame]) || !CanMountFortBipod(client, frame, height))
			continue;
		ga_iFortBipodRef[client] = EntIndexToEntRef(frame);
		ga_iFortBipodWeaponRef[client] = EntIndexToEntRef(GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"));
		ga_iEntIdBipodDeployedOn[client] = frame;
		float angles[3];
		GetClientEyeAngles(client, angles);
		SetEntPropFloat(client, Prop_Send, "m_flPivotYaw", angles[1]);
		SetEntPropFloat(client, Prop_Send, "m_flViewOffsetBipod", height);
		SetEntProp(client, Prop_Send, "m_iPlayerFlags", GetEntProp(client, Prop_Send, "m_iPlayerFlags") | PF_DEPLOY_BIPOD);
		ga_bBipodForced[client] = true;
		ga_bFortBipodMounted[client] = true;
		PlayPropBipodSound(client, true);
		ga_hFortBipodTimer[client] = CreateTimer(0.50, Timer_FortBipod, GetClientSerial(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		return true;
	}
	return false;
}

public Action Timer_FortBipod(Handle timer, int serial) {
	int client = GetClientFromSerial(serial);
	if (client < 1 || ga_hFortBipodTimer[client] != timer)
		return Plugin_Stop;
	float height;
	int frame = EntRefToEntIndex(ga_iFortBipodRef[client]);
	bool valid = IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SECURITY
		&& ga_bFortBipodMounted[client] && (GetEntProp(client, Prop_Send, "m_iPlayerFlags") & PF_DEPLOY_BIPOD)
		&& EntRefToEntIndex(ga_iFortBipodWeaponRef[client]) == GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")
		&& WeaponWithBipod(client) && !AnyPropMenuFlagOpen(client)
		&& CanMountFortBipod(client, frame, height);
	if (!valid) {
		ga_hFortBipodTimer[client] = null;
		StopFortBipod(client);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

bool WeaponWithBipod(int client) {
	int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (iWeapon <= MaxClients || !IsValidEntity(iWeapon))
		return false;
	int ref = EntIndexToEntRef(iWeapon);
	if (ga_iBipodCapabilityWeaponRef[client] != ref) {
		ga_iBipodCapabilityWeaponRef[client] = ref;
		ga_bCachedBipodCapability[client] = DetectPropWeaponBipod(iWeapon);
	}
	return ga_bCachedBipodCapability[client];
}

public void Event_PropBipodWeaponDeploy(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0) {
		ga_iBipodCapabilityWeaponRef[client] = INVALID_ENT_REFERENCE;
		SGB_WeaponDeploy(client);
	}
}

static bool DetectPropWeaponBipod(int iWeapon) {
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

		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", pos);
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
	StopFortBipod(client);
	PlayPropBipodSound(client, false);
	ga_iBipodCapabilityWeaponRef[client] = INVALID_ENT_REFERENCE;
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
	SG_PrecacheSentryModels();
	BL_Precache();
	PrecacheModel(FIRING_SHUTTER_PLATE_MODEL, true);
	PrecacheModel(OUTPOST_GATE_LEAF_MODEL, true);
	for (int i = 0; i < PROP_COUNT; i++) {
		PrecacheModel(g_PropDefs[i].model, true);
		if (IsNativeLadderProp(i)) {
			char model[PLATFORM_MAX_PATH];
			GetNativeLadderModel(i, model, sizeof(model));
			PrecacheModel(model, true);
		}
	}

	for (int i = 0; i < NUM_WIRESOUNDS; i++)
		PrecacheSound(ga_sBarbWire[i], true);

	for (int i = 0; i < sizeof(JC_Sounds); i++)
		PrecacheSound(JC_Sounds[i], true);

	PrecacheSound(SND_SUPPLYREFUND, true);
	PrecacheSound(SND_PROP_PAGE_ROLLOVER, true);
	PrecacheSound(SND_BUYBUILDPOINTS, true);
	PrecacheSound(SND_CANTBUY, true);
	PrecacheSound(SECURITY_DOOR_OPEN_SOUND, true);
	PrecacheSound(SECURITY_DOOR_CLOSE_SOUND, true);
	PrecacheSound(SECURITY_DOOR_IMPACT_SOUND, true);
	PrecacheSound(SND_BIPOD_DEPLOY, true);
	PrecacheSound(SND_BIPOD_RETRACT, true);

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
			bool keptLift = DeconstructAllProps(client, true);
			RefundAllSupply(client, false, false, keptLift ? g_PropDefs[MID(Prop_ArmoredLift)].cost : 0);
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

bool DeconstructAllProps(int client, bool protectLift = false) {
	ArrayList list = ga_hPropPlaced[client];
	if (list == null) return false;

	bool keptLift;
	for (int i = list.Length - 1; i >= 0; i--) {
		if (protectLift && BL_HasHumanRider(list.Get(i))) {
			keptLift = true;
			continue;
		}
		SafeKillRef(list.Get(i));
		list.Erase(i);
	}

	if (keptLift)
		PrintToChat(client, "[BM lift] Lift wasn't deconstructed because players are inside or on top of it.");
	return keptLift;
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

void RefundAllSupply(int client, bool immediateKill = false, bool silent = false, int retainedSupply = 0) {
	StopHolding(client, immediateKill);

	if (retainedSupply > ga_iTokensSpent[client])
		retainedSupply = ga_iTokensSpent[client];
	int refund = ga_iTokensSpent[client] - retainedSupply;
	if (retainedSupply > 0 && !silent)
		PrintToChat(client, "[BM lift] %d supply kept invested in the retained lift. Refund again after it can be deconstructed.", retainedSupply);
	if (ga_iTokensSpent[client] == 0)
		return;

	SetEntProp(client, Prop_Send, "m_nAvailableTokens",
		GetEntProp(client, Prop_Send, "m_nAvailableTokens") + refund);

	if (!silent) {
		PrintToChat(client, "You have been refunded %d supply points.", refund);
		EmitSoundToClient(client, SND_SUPPLYREFUND, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
	}

	ga_iTokensSpent[client] = retainedSupply;
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

static void SelectPropForHolding(int client, int modelId) {
	ga_bBuildMenuOpen[client] = false;
	ga_iModelIndex[client] = view_as<PropId>(modelId);

	char modelName[64];
	GetModelName(g_PropDefs[modelId].model, modelName, sizeof(modelName));
	int maxHealth = g_PropDefs[modelId].health;
	if (maxHealth < 1)
		maxHealth = PROP_HEALTH;

	PrintCenterText(client, "Selected prop: %s (Cost: %d)\nHealth: %d/%d%s", modelName, g_PropDefs[modelId].cost, maxHealth, maxHealth, IsFortBipodProp(modelId) ? PROP_BIPOD_HINT : "");

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

static PropCategory GetPropCategory(int modelId) {
	switch (view_as<PropId>(modelId)) {
		case Prop_FortWindow, Prop_FiringShutter, Prop_WindowInsert, Prop_GuardPlatform, Prop_ProneBunker, Prop_BallisticShield,
			Prop_OutpostFiringPosition, Prop_OutpostPlatform, Prop_Heavy05, Prop_Heavy07,
			Prop_Heavy10, Prop_Heavy16, Prop_Heavy17, Prop_Heavy20, Prop_Heavy21,
			Prop_Heavy26, Prop_Heavy27, Prop_Heavy30, Prop_Heavy35, Prop_Heavy39,
			Prop_Heavy40, Prop_Heavy44, Prop_Heavy48, Prop_Heavy50,
			Prop_Field31, Prop_Field33, Prop_Field46, Prop_Field49, Prop_Field50: return Category_Firing;
		case Prop_ContainerOpen2, Prop_FortCeiling,
			Prop_OutpostShelter, Prop_Heavy06, Prop_Heavy08, Prop_Heavy18,
			Prop_Heavy43: return Category_Shelters;
		case Prop_PanjStairs, Prop_MarketPrisonDoor, Prop_FortDoorway, Prop_FortRamp,
			Prop_CrawlTunnel, Prop_OutpostGate, Prop_OutpostRamp, Prop_ArmoredLift,
			Prop_Heavy02, Prop_Heavy03, Prop_Heavy04, Prop_Heavy11, Prop_Heavy14,
			Prop_Heavy15, Prop_Heavy28, Prop_Heavy32, Prop_Heavy33,
			Prop_Heavy34, Prop_Heavy37, Prop_Heavy41, Prop_Heavy42, Prop_Heavy46,
			Prop_Heavy49, Prop_Field34, Prop_Field40, Prop_Field53: return Category_Movement;
		case Prop_BarbWire, Prop_Mattress, Prop_IedJammer, Prop_AmmoCacheSmall, Prop_SentryGun: return Category_Utilities;
	}
	return Category_Walls;
}

static int CollectCategoryProps(int client, PropCategory category, int models[PROP_COUNT]) {
	int count;
	if (category == Category_Recent) {
		NormalizeRecentPropModels(client);
		for (int slot; slot < RECENT_PROP_COUNT; slot++) {
			int modelId = ga_iRecentPropModels[client][slot];
			if (modelId >= 0 && modelId < PROP_COUNT)
				models[count++] = modelId;
		}
		return count;
	}
	for (int modelId; modelId < PROP_COUNT; modelId++)
		if (category == Category_All || (category == Category_Favourites ? ga_bFavouriteProp[client][modelId] : GetPropCategory(modelId) == category))
			models[count++] = modelId;
	for (int i = 1; i < count; i++) {
		int modelId = models[i];
		int position = i;
		while (position > 0 && g_PropDefs[models[position - 1]].cost > g_PropDefs[modelId].cost) {
			models[position] = models[position - 1];
			position--;
		}
		models[position] = modelId;
	}
	return count;
}

void OpenPropSelectionMenu(int client) {
	ga_bBuildMenuOpen[client] = true;
	SetPropMenuWeaponLock(client, true);
	LoadClientFavourites(client);
	Menu menu = new Menu(PropCategoryMenuHandler);
	menu.SetTitle("Build menu\nBuild points: %d | Choose a category\n%s", ga_iPlayerBuildPoints[client], PROP_MENU_NAVIGATION_HINT);
	char info[24], label[80];
	int models[PROP_COUNT];
	for (int category; category < view_as<int>(Category_Count); category++) {
		FormatEx(info, sizeof(info), "category:%d", category);
		int count = CollectCategoryProps(client, view_as<PropCategory>(category), models);
		if (category == view_as<int>(Category_Favourites) && !ga_bFavouritesLoaded[client])
			FormatEx(label, sizeof(label), "%s (%s)", g_sPropCategoryNames[category], g_bFavouriteDbReady ? "loading" : "database unavailable");
		else
			FormatEx(label, sizeof(label), "%s (%d)", g_sPropCategoryNames[category], count);
		menu.AddItem(info, label);
	}
	menu.AddItem("blueprints", "Blueprints");
	menu.AddItem("shop", "Open shop menu (Cycle Firemode)");
	menu.AddItem("deconstruct", "Deconstruct all props", ga_hPropPlaced[client] != null && ga_hPropPlaced[client].Length > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.Display(client, MENU_STAYOPENTIME);
}

public int PropCategoryMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		char info[24];
		int style;
		if (!menu.GetItem(param, info, sizeof(info), style) || (style & ITEMDRAW_DISABLED))
			return 0;
		if (StrContains(info, "category:") == 0) {
			int category = StringToInt(info[9]);
			if (category >= 0 && category < view_as<int>(Category_Count))
				OpenPropCategoryMenu(client, view_as<PropCategory>(category));
		}
		else {
			ga_bBuildMenuOpen[client] = false;
			if (StrEqual(info, "blueprints"))
				OpenBlueprintMenu(client);
			else if (StrEqual(info, "deconstruct"))
				OpenDeconstructConfirmMenu(client);
			else if (StrEqual(info, "shop")) {
				if (ga_iPropHolding[client] != INVALID_ENT_REFERENCE)
					StopHolding(client);
				OpenShopMenu(client, true, true);
			}
		}
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients)
		ga_bBuildMenuOpen[client] = false;
	return 0;
}

static void OpenPropCategoryMenu(int client, PropCategory category) {
	if (category < Category_Favourites || category >= Category_Count)
		category = Category_All;
	ga_iPropCategory[client] = category;
	ga_bBuildMenuOpen[client] = true;
	SetPropMenuWeaponLock(client, true);
	if (category == Category_Favourites)
		LoadClientFavourites(client);

	int models[PROP_COUNT], count = CollectCategoryProps(client, category, models);
	int pages = (count + PROP_LIST_PAGE_SIZE - 1) / PROP_LIST_PAGE_SIZE;
	if (pages < 1)
		pages = 1;
	int page = ga_iPropCategoryPage[client][category];
	if (page >= pages)
		page = pages - 1;
	if (page < 0)
		page = 0;
	ga_iPropCategoryPage[client][category] = page;

	Menu menu = new Menu(PropSelectionMenuHandler);
	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = false;
	int placed = ga_hPropPlaced[client] != null ? ga_hPropPlaced[client].Length : 0;
	menu.SetTitle("%s | Page %d/%d\nBuild points: %d | Props: %d/%d\n[B] = Bipod | [F] = Favourite\n%s",
		g_sPropCategoryNames[category], page + 1, pages, ga_iPlayerBuildPoints[client], placed, PROP_LIMIT, PROP_MENU_NAVIGATION_HINT);
	char info[24], label[160], name[64];
	for (int slot; slot < PROP_LIST_PAGE_SIZE; slot++) {
		int index = page * PROP_LIST_PAGE_SIZE + slot;
		if (index >= count) {
			if (slot == 0) {
				if (category == Category_Favourites && !ga_bFavouritesLoaded[client])
					menu.AddItem("empty", "Favourites loading/unavailable. Reopen to retry.", ITEMDRAW_DISABLED);
				else
					menu.AddItem("empty", category == Category_Favourites ? "No favourites yet.\nSelect a prop from another category.\nIn Rotation, use Next page if needed,\nthen choose 'Add to favourites'." : "No props in this list yet.", ITEMDRAW_DISABLED);
			}
			else
				menu.AddItem("spacer", " ", ITEMDRAW_SPACER);
			continue;
		}
		int modelId = models[index];
		bool affordable = g_iAllFree != 0 || HasEnoughResources(client, g_PropDefs[modelId].cost);
		bool ownLift = modelId == MID(Prop_ArmoredLift) && g_BL[client].Lift != INVALID_ENT_REFERENCE;
		bool ownSentry = modelId == MID(Prop_SentryGun) && SG_OwnerHasSentry(client);
		int hp = g_PropDefs[modelId].health > 0 ? g_PropDefs[modelId].health : PROP_HEALTH;
		GetModelName(g_PropDefs[modelId].model, name, sizeof(name));
		FormatEx(label, sizeof(label), "%s (HP: %d)%s%s - Cost: %d%s", name, hp,
			IsFortBipodProp(modelId) ? " [B]" : "", ga_bFavouriteProp[client][modelId] ? " [F]" : "",
			g_iAllFree != 0 ? 0 : g_PropDefs[modelId].cost, ownSentry ? " (Already own sentry)" : (ownLift ? " (Already own lift)" : (!affordable ? " (Can't afford)" : "")));
		FormatEx(info, sizeof(info), "prop:%d", modelId);
		menu.AddItem(info, label, affordable && !ownLift && !ownSentry ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	menu.AddItem(page > 0 ? "previous" : "categories", page > 0 ? "Previous page" : "Back to categories");
	menu.AddItem(page + 1 < pages ? "next" : "first", "Next page", pages > 1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("exit", "Exit");
	menu.Display(client, MENU_STAYOPENTIME);
}

public int PropSelectionMenuHandler(Menu menu, MenuAction action, int client, int param) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select) {
		char info[24];
		int style;
		if (!menu.GetItem(param, info, sizeof(info), style) || (style & ITEMDRAW_DISABLED))
			return 0;
		PropCategory category = ga_iPropCategory[client];
		if (StrEqual(info, "categories"))
			OpenPropSelectionMenu(client);
		else if (StrEqual(info, "exit"))
			ga_bBuildMenuOpen[client] = false;
		else if (StrEqual(info, "first")) {
			ga_iPropCategoryPage[client][category] = 0;
			OpenPropCategoryMenu(client, category);
			EmitSoundToClient(client, SND_PROP_PAGE_ROLLOVER, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NONE);
		}
		else if (StrEqual(info, "previous") || StrEqual(info, "next")) {
			ga_iPropCategoryPage[client][category] += StrEqual(info, "next") ? 1 : -1;
			OpenPropCategoryMenu(client, category);
		}
		else if (StrContains(info, "prop:") == 0) {
			int modelId = StringToInt(info[5]);
			if (modelId < 0 || modelId >= PROP_COUNT)
				return 0;
			if ((g_iAllFree == 0 && !HasEnoughResources(client, g_PropDefs[modelId].cost))
				|| (modelId == MID(Prop_ArmoredLift) && g_BL[client].Lift != INVALID_ENT_REFERENCE)
				|| (modelId == MID(Prop_SentryGun) && SG_OwnerHasSentry(client))) {
				PrintToChat(client, "That prop cannot be built right now.");
				OpenPropCategoryMenu(client, category);
				return 0;
			}
			SelectPropForHolding(client, modelId);
		}
	}
	else if (action == MenuAction_Cancel && client >= 1 && client <= MaxClients)
		ga_bBuildMenuOpen[client] = false;
	return 0;
}

void OpenRotationMenu(int client, int firstItem = 0) {
	LoadClientFavourites(client);
	ga_bPropRotateMenuOpen[client] = true;
	ga_bRotationMenuVisible[client] = true;
	SetPropMenuWeaponLock(client, true);

	Menu rotationMenu = new Menu(RotationMenuHandler, MENU_ACTIONS_DEFAULT | MenuAction_Display);
	char modelName[64];
	GetModelName(g_PropDefs[MID(ga_iModelIndex[client])].model, modelName, sizeof(modelName));
	float step = ga_fPropRotateStep[client];
	if (step <= 0.0)
		step = PROP_ROTATE_STEP;

	if (BL_HoldingLift(client)) {
		char item[64];
		rotationMenu.SetTitle("%s: automatic travel\nPlacement = middle/home\nGuides: green=top, cyan=home, orange=bottom\nRed=no safe travel | small box=call button\nAIM: Place | RELOAD: Reset spin\n%s", modelName, PROP_MENU_NAVIGATION_HINT);
		rotationMenu.AddItem("y+", "+Spin");
		rotationMenu.AddItem("y-", "-Spin");
		FormatEx(item, sizeof(item), "Spin step: %.1f° (change)", step);
		rotationMenu.AddItem("rotstep", item);
		AddFavouriteRotationItem(rotationMenu, client);
		rotationMenu.ExitBackButton = true;
		rotationMenu.DisplayAt(client, firstItem, 60);
		return;
	}

	if (ga_iModelIndex[client] == Prop_SentryGun) {
		rotationMenu.SetTitle("Sentry Gun\nAIM: Place and activate | RELOAD: Reset spin\n%s", PROP_MENU_NAVIGATION_HINT);
		rotationMenu.AddItem("y+", "+Spin");
		rotationMenu.AddItem("y-", "-Spin");
		rotationMenu.AddItem("rotstep", "Change rotation step");
		rotationMenu.ExitBackButton = true;
		rotationMenu.DisplayAt(client, firstItem, 60);
		return;
	}

	rotationMenu.SetTitle("Rotation: %s\nStep: %.1f°\nAIM: Place\n%s\nRELOAD: Reset rotation%s", modelName, step, PROP_MENU_NAVIGATION_HINT, HeldPropSupportsBipod(client) ? PROP_BIPOD_HINT : "");

	rotationMenu.AddItem("y+", "+Yaw");
	rotationMenu.AddItem("y-", "-Yaw");
	rotationMenu.AddItem("x+", "+Pitch");
	rotationMenu.AddItem("x-", "-Pitch");
	rotationMenu.AddItem("z+", "+Roll");
	rotationMenu.AddItem("z-", "-Roll");
	rotationMenu.AddItem("reset", "Reset Rotation");
	AddFavouriteRotationItem(rotationMenu, client);
	rotationMenu.AddItem("saveblueprint", "Save Blueprint");
	rotationMenu.AddItem("spacer", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);

	char stepItem[64];
	FormatEx(stepItem, sizeof(stepItem), "Rotation step: %.1f° (change)", step);
	rotationMenu.AddItem("rotstep", stepItem);

	rotationMenu.ExitBackButton = true;
	rotationMenu.DisplayAt(client, firstItem, 60);
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
	PrintCenterText(client, "Rotation reset\nHealth: %d/%d%s", hp, maxHealth, HeldPropSupportsBipod(client) ? PROP_BIPOD_HINT : "");

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
	else if (action == MenuAction_Display)
		ga_iRotationMenuGeneration[client]++;
	else if (action == MenuAction_Select) {
		if (param < 0)
			return 0;

		char item[16], display[64];
		int style;
		if (!menu.GetItem(param, item, sizeof(item), style, display, sizeof(display)))
			return 0;
		if (style & ITEMDRAW_DISABLED)
			return 0;

		if (BL_HoldingLift(client) && !StrEqual(item, "y+") && !StrEqual(item, "y-")
			&& !StrEqual(item, "reset") && !StrEqual(item, "rotstep") && !StrEqual(item, "favourite"))
			return 0;
		if (StrEqual(item, "favourite")) {
			int page = GetMenuSelectionPosition();
			TogglePropFavourite(client, page);
			OpenRotationMenu(client, page);
			return 0;
		}
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

		if (BL_HoldingLift(client) || ga_iModelIndex[client] == Prop_SentryGun) {
			vRot[0] = 0.0;
			vRot[2] = 0.0;
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
		PrintCenterText(client, "Rotation: Yaw: %.1f°, Pitch: %.1f°, Roll: %.1f°\nHealth: %d/%d%s", vRot[1], vRot[0], vRot[2], hp, maxHealth, HeldPropSupportsBipod(client) ? PROP_BIPOD_HINT : "");

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
		if (param == MenuCancel_Interrupted && ga_bRefreshingRotationMenu[client])
			return 0;
		ga_iRotationMenuGeneration[client]++;
		ga_bPropRotateMenuOpen[client] = false;
		ga_bRotationMenuVisible[client] = false;
		if (param == MenuCancel_ExitBack && !TryPlaceExistingHeldPropOnBack(client))
			StopHolding(client);
		ga_iPropOwner[client] = 0;
		if (param == MenuCancel_ExitBack)
			OpenPropCategoryMenu(client, ga_iPropCategory[client]);
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
			if (!DeconstructAllProps(client, true))
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
	int modelId = FindPropIdByModel(fullPath);
	if (modelId != -1) {
		strcopy(modelName, maxLen, g_PropDefs[modelId].displayName);
		return;
	}

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
		if (modelId < 0 || modelId == MID(Prop_AmmoCacheSmall) || modelId == MID(Prop_ArmoredLift) || modelId == MID(Prop_SentryGun))
			return -1;
		totalCost += g_PropDefs[modelId].cost;
	}

	return totalCost;
}

static void ClearClientFavourites(int client) {
	ga_iFavouriteGeneration[client]++;
	ga_bFavouritesLoaded[client] = false;
	ga_bFavouritesLoading[client] = false;
	ga_bFavouriteSaving[client] = false;
	for (int modelId; modelId < PROP_COUNT; modelId++)
		ga_bFavouriteProp[client][modelId] = false;
}

static void SetupFavouriteTable() {
	char driver[16];
	g_hBlueprintDb.Driver.GetIdentifier(driver, sizeof(driver));
	if (StrEqual(driver, "mysql"))
		SQL_TQuery(g_hBlueprintDb, SQL_CreateFavouriteTable,
			"CREATE TABLE IF NOT EXISTS bm_props_favourites (steamid VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, model VARCHAR(260) CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL, PRIMARY KEY (steamid, model))");
	else
		SQL_TQuery(g_hBlueprintDb, SQL_CreateFavouriteTable,
			"CREATE TABLE IF NOT EXISTS bm_props_favourites (steamid TEXT NOT NULL, model TEXT COLLATE NOCASE NOT NULL, PRIMARY KEY (steamid, model))");
}

public void SQL_CreateFavouriteTable(Database db, DBResultSet results, const char[] error, any data) {
	if (error[0] != '\0') {
		LogError("Unable to create props favourites table: %s", error);
		return;
	}
	g_bFavouriteDbReady = true;
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && !IsFakeClient(client))
			LoadClientFavourites(client);
}

static void LoadClientFavourites(int client) {
	if (g_hBlueprintDb == null || !g_bFavouriteDbReady || client < 1 || client > MaxClients
		|| !IsClientInGame(client) || IsFakeClient(client) || ga_bFavouritesLoaded[client]
		|| ga_bFavouritesLoading[client] || ga_bFavouriteSaving[client])
		return;

	char steamId[64], escapedSteamId[129], query[256];
	if (!GetBlueprintSteamId(client, steamId, sizeof(steamId)))
		return;
	SQL_EscapeString(g_hBlueprintDb, steamId, escapedSteamId, sizeof(escapedSteamId));
	FormatEx(query, sizeof(query), "SELECT model FROM bm_props_favourites WHERE steamid = '%s'", escapedSteamId);
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(ga_iFavouriteGeneration[client]);
	ga_bFavouritesLoading[client] = true;
	SQL_TQuery(g_hBlueprintDb, SQL_LoadClientFavourites, query, pack);
}

public void SQL_LoadClientFavourites(Database db, DBResultSet results, const char[] error, any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	int generation = pack.ReadCell();
	delete pack;
	if (client < 1 || !IsClientInGame(client) || generation != ga_iFavouriteGeneration[client])
		return;
	ga_bFavouritesLoading[client] = false;
	if (error[0] != '\0' || results == null) {
		LogError("Unable to load props favourites for client %d: %s", client, error);
		return;
	}

	for (int modelId; modelId < PROP_COUNT; modelId++)
		ga_bFavouriteProp[client][modelId] = false;
	char model[PLATFORM_MAX_PATH];
	while (results.FetchRow()) {
		results.FetchString(0, model, sizeof(model));
		int modelId = FindPropIdByModel(model);
		// Keep unknown paths in the database so removed/reordered props never become another favourite.
		if (modelId >= 0)
			ga_bFavouriteProp[client][modelId] = true;
	}
	ga_bFavouritesLoaded[client] = true;
}

static bool CanFavouriteHeldProp(int client) {
	int modelId = MID(ga_iModelIndex[client]);
	int ent = EntRefToEntIndex(ga_iPropHolding[client]);
	return modelId >= 0 && modelId < PROP_COUNT && ent > MaxClients && IsValidEntity(ent)
		&& !ga_bHoldingBlueprint[client] && (ga_hBatchMoveData[client] == null || ga_hBatchMoveData[client].Length == 0);
}

static void AddFavouriteRotationItem(Menu menu, int client) {
	if (!CanFavouriteHeldProp(client))
		menu.AddItem("favourite", "Favourites: select a single prop", ITEMDRAW_DISABLED);
	else if (!g_bFavouriteDbReady)
		menu.AddItem("favourite", "Favourites: database unavailable", ITEMDRAW_DISABLED);
	else if (!ga_bFavouritesLoaded[client])
		menu.AddItem("favourite", "Favourites: loading", ITEMDRAW_DISABLED);
	else if (ga_bFavouriteSaving[client])
		menu.AddItem("favourite", "Saving favourite...", ITEMDRAW_DISABLED);
	else
		menu.AddItem("favourite", ga_bFavouriteProp[client][MID(ga_iModelIndex[client])] ? "Remove from favourites" : "Add to favourites");
}

static void TogglePropFavourite(int client, int page) {
	if (g_hBlueprintDb == null || !g_bFavouriteDbReady || !ga_bFavouritesLoaded[client]
		|| ga_bFavouriteSaving[client] || !CanFavouriteHeldProp(client))
		return;
	char steamId[64], escapedSteamId[129], escapedModel[PLATFORM_MAX_PATH * 2 + 1], query[1024];
	if (!GetBlueprintSteamId(client, steamId, sizeof(steamId)))
		return;
	int modelId = MID(ga_iModelIndex[client]);
	bool favourite = !ga_bFavouriteProp[client][modelId];
	SQL_EscapeString(g_hBlueprintDb, steamId, escapedSteamId, sizeof(escapedSteamId));
	SQL_EscapeString(g_hBlueprintDb, g_PropDefs[modelId].model, escapedModel, sizeof(escapedModel));
	if (favourite)
		FormatEx(query, sizeof(query), "REPLACE INTO bm_props_favourites (steamid, model) VALUES ('%s', '%s')", escapedSteamId, escapedModel);
	else
		FormatEx(query, sizeof(query), "DELETE FROM bm_props_favourites WHERE steamid = '%s' AND model = '%s'", escapedSteamId, escapedModel);
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(ga_iFavouriteGeneration[client]);
	pack.WriteString(g_PropDefs[modelId].model);
	pack.WriteCell(favourite);
	pack.WriteCell(ga_iPropHolding[client]);
	pack.WriteCell(ga_iRotationMenuGeneration[client] + 1);
	pack.WriteCell(page);
	ga_bFavouriteSaving[client] = true;
	SQL_TQuery(g_hBlueprintDb, SQL_SavePropFavourite, query, pack);
}

public void SQL_SavePropFavourite(Database db, DBResultSet results, const char[] error, any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	int generation = pack.ReadCell();
	char model[PLATFORM_MAX_PATH];
	pack.ReadString(model, sizeof(model));
	bool favourite = view_as<bool>(pack.ReadCell());
	int heldRef = pack.ReadCell();
	int menuGeneration = pack.ReadCell();
	int page = pack.ReadCell();
	delete pack;
	if (client < 1 || !IsClientInGame(client) || generation != ga_iFavouriteGeneration[client])
		return;
	ga_bFavouriteSaving[client] = false;
	if (error[0] != '\0') {
		LogError("Unable to save props favourite for client %d: %s", client, error);
		PrintToChat(client, "Could not save your favourite. Please try again.");
	}
	else {
		int modelId = FindPropIdByModel(model);
		if (modelId >= 0)
			ga_bFavouriteProp[client][modelId] = favourite;
		PrintToChat(client, favourite ? "Prop added to favourites." : "Prop removed from favourites.");
	}
	// Refresh only the saving menu, never reopen it after the player has left or changed props.
	if (ga_bRotationMenuVisible[client] && ga_iPropHolding[client] == heldRef
		&& ga_iRotationMenuGeneration[client] == menuGeneration) {
		ga_bRefreshingRotationMenu[client] = true;
		OpenRotationMenu(client, page);
		ga_bRefreshingRotationMenu[client] = false;
	}
}

static void ClearClientBlueprints(int client) {
	if (client < 1 || client > MaxClients)
		return;
	ClearClientFavourites(client);

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
	g_bFavouriteDbReady = false;
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
	SetupFavouriteTable();
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsFakeClient(client))
			LoadClientBlueprints(client);
	}
}

static void LoadClientBlueprints(int client) {
	LoadClientFavourites(client);
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
	if (rootModelId < 0 || rootModelId == MID(Prop_AmmoCacheSmall) || rootModelId == MID(Prop_ArmoredLift) || rootModelId == MID(Prop_SentryGun))
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
		if (modelId < 0 || modelId == MID(Prop_AmmoCacheSmall) || modelId == MID(Prop_ArmoredLift) || modelId == MID(Prop_SentryGun)) {
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

	return GetPropOwner(ResolveFiringShutterFrame(groundEntity)) > 0;
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
	AddUniqueEntityRef(g_hJammers, ent);
}

static bool IsSolidPlacedJammer(int entity) {
	return ga_iTrackedPropId[entity] == MID(Prop_IedJammer)
		&& GetEntProp(entity, Prop_Data, "m_nSolidType") != 0
		&& (GetEntProp(entity, Prop_Data, "m_usSolidFlags") & 0x0004) == 0;
}

public any Native_FindPlacedJammer(Handle plugin, int numParams) {
	SetNativeCellRef(3, 0);
	float range = view_as<float>(GetNativeCell(2));
	if (!(range >= 0.0) || g_hJammers == null)
		return INVALID_ENT_REFERENCE;

	float origin[3], pos[3];
	GetNativeArray(1, origin, sizeof(origin));
	float rangeSquared = range * range;
	int selected = -1;
	int selectedRef = INVALID_ENT_REFERENCE;
	for (int i = g_hJammers.Length - 1; i >= 0; i--) {
		int reference = g_hJammers.Get(i);
		int entity = EntRefToEntIndex(reference);
		if (!IsValidNonClientEntity(entity)) {
			g_hJammers.Erase(i);
			continue;
		}
		if ((selected != -1 && entity >= selected) || !IsSolidPlacedJammer(entity))
			continue;

		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		if (GetVectorDistance(origin, pos, true) <= rangeSquared) {
			selected = entity;
			selectedRef = reference;
		}
	}
	if (selected != -1) {
		int owner = ga_iTrackedPropOwner[selected];
		if (owner >= 1 && owner <= MaxClients && IsClientInGame(owner)
		 && RefListContainsEntity(ga_hPropPlaced[owner], selected))
			SetNativeCellRef(3, GetClientUserId(owner));
	}
	return selectedRef;
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
	SG_RemoveAllSentries();
	BL_ClearAll();
	for (int client = 1; client <= MaxClients; client++) {
		ga_bPropBipodSoundActive[client] = false;
		StopFortBipod(client);
		ga_bFortBipodButtonConsumed[client] = false;
	}
	StopFiringShutters(false);
	g_iMattressLaunchEpoch++;
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
	SG_RemoveAllSentries();
	BL_ClearAll();
	for (int client = 1; client <= MaxClients; client++) {
		ga_bPropBipodSoundActive[client] = false;
		StopFortBipod(client);
	}
	StopFiringShutters(true);
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
	delete g_hSetBipodState;

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

	g_cvPropSelectionRadius = CreateConVar("sm_props_selection_radius", "300",
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

void SetupSDKCalls() {
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
	StartPrepSDKCall(SDKCall_Player);
	if (PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CINSPlayer::SetBipodState")) {
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
		g_hSetBipodState = EndPrepSDKCall();
	}
	if (g_hSetBipodState == null)
		LogError("Fortification bipod support disabled: missing CINSPlayer::SetBipodState in %s.", RESUPPLY_GAMEDATA_FILE);
	delete config;

	if (g_hDirectResupply == null)
		SetFailState("Unable to prepare CINSPlayer::Resupply.");
}

stock void SafeKillIdx(int ent) {
	SG_QueueRemoveEntity(ent);
	if (ent <= MaxClients || ent > MAXENTITIES) return;
	int ref = EntIndexToEntRef(ent);
	if (ref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, ref);
}

stock void SafeKillRef(int entref) {
	SG_QueueRemoveEntity(EntRefToEntIndex(entref));
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

void BL_AttachAmmoBag(int client, int bag) {
	int slot = GetPlayerLift(client);
	if (!slot || g_BL[slot].Failed || g_BL[slot].Removing)
		return;
	int mover = BL_LiftEntity(slot);
	if (mover == -1)
		return;
	float position[3], angles[3], origin[3], local[3];
	GetEntPropVector(bag, Prop_Data, "m_vecAbsOrigin", position);
	GetEntPropVector(bag, Prop_Send, "m_angRotation", angles);
	GetEntPropVector(mover, Prop_Data, "m_vecAbsOrigin", origin);
	SubtractVectors(position, origin, local);
	SetVariantString("!activator");
	if (!AcceptEntityInput(bag, "SetParent", mover, bag) || GetEntPropEnt(bag, Prop_Data, "m_hMoveParent") != mover) {
		LogError("Unable to attach ammo bag %d to lift %d.", bag, mover);
		return;
	}
	// The mover has zero angles; cabin yaw is baked into its parts. Keep the bag's world orientation.
	TeleportEntity(bag, local, angles, NULL_VECTOR);
}

void BL_RemoveLift(int slot) {
	if (g_BL[slot].Removing)
		return;
	g_BL[slot].Removing = true;
	BL_StopDoorSound(slot);
	for (int entity = MaxClients + 1; entity <= MAXENTITIES; entity++)
		if (g_BLSlot[entity] == slot) {
			g_BLSlot[entity] = 0;
			g_BLRef[entity] = INVALID_ENT_REFERENCE;
		}
	BL_FreezeLift(slot);
	delete g_BL[slot].PanelTimer;
	for (int i = 0; i < 4; i++)
		if (BL_RefEntity(g_BL[slot].Hatches[i]) != -1)
			AcceptEntityInput(BL_RefEntity(g_BL[slot].Hatches[i]), "Kill");
	for (int i = 0; i < 3; i++)
		if (BL_RefEntity(g_BL[slot].Ladder[i]) != -1)
			AcceptEntityInput(BL_RefEntity(g_BL[slot].Ladder[i]), "Kill");
	if (BL_RefEntity(g_BL[slot].Climb) != -1)
		AcceptEntityInput(BL_RefEntity(g_BL[slot].Climb), "Kill");
	BL_ResetHatches(slot);
	for (int i; i < sizeof(g_BL[slot].Calls); i++) {
		int station = BL_RefEntity(g_BL[slot].Calls[i]);
		if (station != -1)
			AcceptEntityInput(station, "Kill");
		g_BL[slot].Calls[i] = INVALID_ENT_REFERENCE;
	}
	for (int i = 0; i < 5; i++) {
		int panel = BL_RefEntity(g_BL[slot].Panels[i]);
		if (panel != -1)
			AcceptEntityInput(panel, "Kill");
		g_BL[slot].Panels[i] = INVALID_ENT_REFERENCE;
	}
	int visual = BL_VisualEntity(slot);
	if (visual != -1)
		AcceptEntityInput(visual, "Kill");
	int entity = BL_LiftEntity(slot);
	if (entity != -1)
		AcceptEntityInput(entity, "Kill");
	g_BL[slot].Visual = INVALID_ENT_REFERENCE;
	g_BL[slot].Lift = INVALID_ENT_REFERENCE;
	g_BL[slot].Removing = false;
}

int BL_LiftEntity(int slot) {
	int entity = EntRefToEntIndex(g_BL[slot].Lift);
	return entity > MaxClients && IsValidEntity(entity) ? entity : -1;
}

int BL_VisualEntity(int slot) {
	int entity = EntRefToEntIndex(g_BL[slot].Visual);
	return entity > MaxClients && IsValidEntity(entity) ? entity : -1;
}

bool BL_CreateLiftVisual(int slot, int mover, const float origin[3]) {
	int visual = CreateEntityByName("prop_dynamic_override");
	if (visual == -1)
		return false;
	DispatchKeyValue(visual, "model", LIFT_MODEL);
	DispatchKeyValue(visual, "targetname", "bm_lift_test_visual");
	DispatchKeyValue(visual, "solid", "0");
	DispatchKeyValueVector(visual, "origin", origin);
	DispatchKeyValue(visual, "angles", "0 0 0");
	if (!DispatchSpawn(visual)) {
		AcceptEntityInput(visual, "Kill");
		return false;
	}
	ActivateEntity(visual);
	SetEntityMoveType(visual, MOVETYPE_NONE);
	SetEntProp(visual, Prop_Send, "m_nSolidType", 0);
	SetEntProp(visual, Prop_Data, "m_takedamage", 0);
	SetVariantString("!activator");
	if (!AcceptEntityInput(visual, "SetParent", mover, visual) || GetEntPropEnt(visual, Prop_Data, "m_hMoveParent") != mover) {
		AcceptEntityInput(visual, "Kill");
		return false;
	}
	// TeleportEntity positions are parent-local once SetParent has succeeded.
	float localOrigin[3], angles[3];
	TeleportEntity(visual, localOrigin, angles, NULL_VECTOR);
	g_BL[slot].Visual = EntIndexToEntRef(visual);
	return true;
}

int BL_RefEntity(int reference) {
	int entity = EntRefToEntIndex(reference);
	return entity > MaxClients && IsValidEntity(entity) ? entity : -1;
}

bool BL_IsCallStation(int slot, int entity) {
	if (!slot || entity <= MaxClients)
		return false;
	for (int i; i < g_BL[slot].StopCount; i++)
		if (entity == BL_RefEntity(g_BL[slot].Calls[i]))
			return true;
	return false;
}

bool BL_IsLiftPart(int slot, int entity) {
	if (entity <= MaxClients)
		return false;
	if (entity == BL_LiftEntity(slot) || entity == BL_VisualEntity(slot))
		return true;
	if (entity == BL_RefEntity(g_BL[slot].Climb))
		return true;
	for (int i = 0; i < 4; i++)
		if (entity == BL_RefEntity(g_BL[slot].Hatches[i]))
			return true;
	for (int i = 0; i < 3; i++)
		if (entity == BL_RefEntity(g_BL[slot].Ladder[i]))
			return true;
	for (int i; i < sizeof(g_BL[slot].Calls); i++)
		if (entity == BL_RefEntity(g_BL[slot].Calls[i]))
			return true;
	for (int i = 0; i < 5; i++)
		if (entity == BL_RefEntity(g_BL[slot].Panels[i]))
			return true;
	return false;
}

bool BL_PanelsReady(int slot) {
	for (int i; i < g_BL[slot].StopCount; i++)
		if (BL_RefEntity(g_BL[slot].Calls[i]) == -1)
			return false;
	if (BL_RefEntity(g_BL[slot].Climb) == -1)
		return false;
	for (int i = 0; i < 4; i++)
		if (BL_RefEntity(g_BL[slot].Hatches[i]) == -1)
			return false;
	for (int i = 0; i < 3; i++)
		if (BL_RefEntity(g_BL[slot].Ladder[i]) == -1)
			return false;
	for (int i = 0; i < 5; i++)
		if (BL_RefEntity(g_BL[slot].Panels[i]) == -1)
			return false;
	return true;
}

void BL_PanelLocalPosition(int index, float offset, float local[3]) {
	for (int axis = 0; axis < 3; axis++)
		local[axis] = g_BLPanelClosed[index][axis];
	if (index < 3)
		local[2] += offset;
	else
		local[0] += index == 3 ? -offset : offset;
}

void BL_PanelPosition(int index, float offset, const float cabin[3], float world[3]) {
	BL_PanelLocalPosition(index, offset, world);
	for (int axis = 0; axis < 3; axis++)
		world[axis] += cabin[axis];
}

bool BL_CreateParts(int slot, int mover, const float origin[3]) {
	for (int i = 0; i < 5; i++) {
		g_BL[slot].PanelOffset[i] = i < 3 ? 0.0 : g_BLPanelTravel[i];
		g_BL[slot].PanelGoal[i] = g_BL[slot].PanelOffset[i];
		int panel = CreateEntityByName("prop_dynamic_override");
		if (panel == -1)
			return false;
		g_BL[slot].Panels[i] = EntIndexToEntRef(panel);
		DispatchKeyValue(panel, "model", i < 3 ? SHUTTER_MODEL : DOOR_MODEL);
		DispatchKeyValue(panel, "solid", "6");
		DispatchKeyValue(panel, "physdamagescale", "0");
		DispatchKeyValue(panel, "targetname", "bm_lift_test_panel");
		float position[3], angles[3];
		BL_PanelPosition(i, g_BL[slot].PanelOffset[i], origin, position);
		angles[1] = g_BLPanelYaw[i];
		DispatchKeyValueVector(panel, "origin", position);
		DispatchKeyValueVector(panel, "angles", angles);
		if (!DispatchSpawn(panel))
			return false;
		ActivateEntity(panel);
		SetEntityMoveType(panel, MOVETYPE_NONE);
		SetEntProp(panel, Prop_Data, "m_takedamage", 0);
		SetVariantString("!activator");
		if (!AcceptEntityInput(panel, "SetParent", mover, panel) || GetEntPropEnt(panel, Prop_Data, "m_hMoveParent") != mover)
			return false;
		BL_PanelLocalPosition(i, g_BL[slot].PanelOffset[i], position);
		TeleportEntity(panel, position, angles, NULL_VECTOR);
	}
	return BL_ConfigureCalls(slot, origin, g_BL[slot].Yaw)
		&& BL_CreateHatches(slot, mover, origin);
}


bool BL_ConfigureCalls(int slot, const float home[3], float yaw) {
	for (int i; i < g_BL[slot].StopCount; i++) {
		if (GetEntityCount() > GetMaxEntities() - 80)
			return false;
		int station = CreateEntityByName("prop_dynamic_override");
		if (station == -1)
			return false;
		g_BL[slot].Calls[i] = EntIndexToEntRef(station);
		DispatchKeyValue(station, "model", CALL_MODEL);
		DispatchKeyValue(station, "solid", "0");
		DispatchKeyValue(station, "targetname", "bm_lift_call_station");
		float position[3] = {BL_CALL_X, BL_CALL_Y, 0.0}, rotation[3];
		position[1] = g_BL[slot].CallY[i];
		position[2] = g_BL[slot].CallBase[i];
		BL_RotateXY(position, yaw);
		AddVectors(position, home, position);
		rotation[1] = yaw;
		DispatchKeyValueVector(station, "origin", position);
		DispatchKeyValueVector(station, "angles", rotation);
		if (!DispatchSpawn(station))
			return false;
		ActivateEntity(station);
		SetEntityMoveType(station, MOVETYPE_NONE);
		SetEntProp(station, Prop_Send, "m_nSolidType", 0);
		SetEntProp(station, Prop_Data, "m_takedamage", 0);
	}
	return true;
}

void BL_ResetHatches(int slot) {
	for (int i = 0; i < 4; i++)
		g_BL[slot].Hatches[i] = INVALID_ENT_REFERENCE;
	for (int i = 0; i < 2; i++) {
		g_BL[slot].HatchOffset[i] = 0.0;
		g_BL[slot].HatchGoal[i] = 0.0;
	}
	for (int i = 0; i < 3; i++)
		g_BL[slot].Ladder[i] = INVALID_ENT_REFERENCE;
	g_BL[slot].Climb = INVALID_ENT_REFERENCE;
	g_BL[slot].LadderEnabled = false;
}

int BL_CreateHatchPart(int mover, const float origin[3], const char[] model, bool solid, bool hidden = false) {
	int entity = CreateEntityByName("prop_dynamic_override");
	if (entity == -1)
		return INVALID_ENT_REFERENCE;
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", solid ? "6" : "0");
	DispatchKeyValueVector(entity, "origin", origin);
	if (!DispatchSpawn(entity)) {
		AcceptEntityInput(entity, "Kill");
		return INVALID_ENT_REFERENCE;
	}
	ActivateEntity(entity);
	SetEntityMoveType(entity, MOVETYPE_NONE);
	SetEntProp(entity, Prop_Data, "m_takedamage", 0);
	if (hidden)
		SetEntityRenderMode(entity, RENDER_NONE);
	SetVariantString("!activator");
	if (!AcceptEntityInput(entity, "SetParent", mover, entity) || GetEntPropEnt(entity, Prop_Data, "m_hMoveParent") != mover) {
		AcceptEntityInput(entity, "Kill");
		return INVALID_ENT_REFERENCE;
	}
	return EntIndexToEntRef(entity);
}

void BL_HatchTransform(int index, float progress, float position[3], float angles[3]) {
	int side = index % 2;
	position[0] = (side == 0 ? -1.0 : 1.0) * (22.0 + BL_FloatMin(progress, 1.0) * 28.0);
	position[1] = 0.0;
	// Separate leaf layers avoid flicker while sliding behind the fixed floor/ceiling.
	position[2] = index < 2 ? -0.25 - float(side) * 0.25 : 162.25 + float(side) * 0.25;
	angles[0] = 0.0;
	angles[1] = 0.0;
	angles[2] = 0.0;
}

void BL_LadderTransform(int index, float progress, float position[3], float angles[3]) {
	float angle = BL_FloatMin(BL_FloatMax(progress - 1.0, 0.0), 1.0) * 90.0;
	float extension = BL_FloatMin(BL_FloatMax(progress - 2.0, 0.0), 1.0);
	float a = DegToRad(angle);
	float layer = 4.0 + float(index) * 3.0 * (1.0 - extension);
	position[0] = 0.0;
	position[1] = 24.0 - 8.0 * Cosine(a) - layer * Sine(a);
	position[2] = 186.0 - 8.0 * Sine(a) + layer * Cosine(a) - float(index) * 42.0 * extension;
	angles[0] = 0.0;
	angles[1] = 0.0;
	angles[2] = angle - 90.0;
}

void BL_UpdateHatchParts(int slot, int index) {
	float position[3], angles[3];
	for (int side = 0; side < 2; side++) {
		int leaf = index * 2 + side;
		BL_HatchTransform(leaf, g_BL[slot].HatchOffset[index], position, angles);
		TeleportEntity(BL_RefEntity(g_BL[slot].Hatches[leaf]), position, angles, NULL_VECTOR);
	}
	if (index != 1)
		return;
	for (int i = 0; i < 3; i++) {
		BL_LadderTransform(i, g_BL[slot].HatchOffset[1], position, angles);
		TeleportEntity(BL_RefEntity(g_BL[slot].Ladder[i]), position, angles, NULL_VECTOR);
	}
	bool enabled = g_BL[slot].HatchOffset[1] >= 3.0;
	if (enabled != g_BL[slot].LadderEnabled) {
		AcceptEntityInput(BL_RefEntity(g_BL[slot].Climb), enabled ? "EnableCollision" : "DisableCollision");
		AcceptEntityInput(BL_RefEntity(g_BL[slot].Ladder[0]), enabled ? "EnableCollision" : "DisableCollision");
		g_BL[slot].LadderEnabled = enabled;
	}
}

bool BL_CreateHatches(int slot, int mover, const float origin[3]) {
	for (int i = 0; i < 4; i++)
		g_BL[slot].Hatches[i] = BL_CreateHatchPart(mover, origin, g_BLHatchModels[i], true);
	for (int i = 0; i < 3; i++)
		g_BL[slot].Ladder[i] = BL_CreateHatchPart(mover, origin, g_BLLadderModels[i], i == 0);
	g_BL[slot].Climb = BL_CreateHatchPart(mover, origin, CLIMB_MODEL, true, true);
	if (!BL_PanelsReady(slot))
		return false;
	float position[3] = {0.0,20.0,24.0}, angles[3];
	TeleportEntity(BL_RefEntity(g_BL[slot].Climb), position, angles, NULL_VECTOR);
	if (!AcceptEntityInput(BL_RefEntity(g_BL[slot].Climb), "DisableCollision"))
		return false;
	if (!AcceptEntityInput(BL_RefEntity(g_BL[slot].Ladder[0]), "DisableCollision"))
		return false;
	BL_UpdateHatchParts(slot, 0);
	BL_UpdateHatchParts(slot, 1);
	return true;
}

void BL_RotatedBounds(float yaw, const float position[3], float roll, const float low[3], const float high[3], float mins[3], float maxs[3]) {
	float a = DegToRad(roll);
	for (int corner = 0; corner < 8; corner++) {
		float x = corner & 1 ? high[0] : low[0];
		float y = corner & 2 ? high[1] : low[1];
		float z = corner & 4 ? high[2] : low[2];
		float point[3];
		point[0] = position[0] + x;
		point[1] = position[1] + y * Cosine(a) - z * Sine(a);
		point[2] = position[2] + y * Sine(a) + z * Cosine(a);
		BL_RotateXY(point, yaw);
		for (int axis = 0; axis < 3; axis++) {
			mins[axis] = BL_FloatMin(mins[axis], point[axis] - 0.1);
			maxs[axis] = BL_FloatMax(maxs[axis], point[axis] + 0.1);
		}
	}
}

bool BL_HatchStepClear(int slot, int index, float next) {
	float cabin[3];
	GetEntPropVector(BL_LiftEntity(slot), Prop_Data, "m_vecAbsOrigin", cabin);
	int count = index == 0 ? 2 : 5;
	for (int part = 0; part < count; part++) {
		float mins[3] = {9999.0,9999.0,9999.0}, maxs[3] = {-9999.0,-9999.0,-9999.0};
		float low[3], high[3];
		if (part < 2) {
			low[0] = -23.0;
			high[0] = -low[0];
			low[1] = index == 0 ? -44.0 : -48.0;
			high[1] = -low[1];
			low[2] = index == 0 ? 0.0 : -11.0;
			high[2] = index == 0 ? 35.0 : 24.0;
		} else {
			high[0] = 22.5 - float(part - 2) * 3.0;
			low[0] = -high[0];
			low[1] = -2.0;
			high[1] = 2.0;
			low[2] = part == 4 ? -59.0 : -48.0;
			high[2] = part == 2 ? 28.0 : 0.0;
		}
		float previous[3], previousAngles[3];
		bool moved;
		for (int frame = 0; frame < 2; frame++) {
			float progress = frame == 0 ? g_BL[slot].HatchOffset[index] : next;
			float position[3], angles[3];
			if (part < 2)
				BL_HatchTransform(index * 2 + part, progress, position, angles);
			else
				BL_LadderTransform(part - 2, progress, position, angles);
			if (frame == 0) {
				previous = position;
				previousAngles = angles;
			} else
				moved = GetVectorDistance(previous, position) > 0.00001 || GetVectorDistance(previousAngles, angles) > 0.00001;
			BL_RotatedBounds(g_BL[slot].Yaw, position, angles[2], low, high, mins, maxs);
		}
		if (!moved)
			continue;
		Handle trace = TR_TraceHullFilterEx(cabin, cabin, mins, maxs, MASK_PLAYERSOLID, BL_TracePanelTravel, slot);
		bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
		delete trace;
		if (!clear)
			return false;
	}
	return true;
}

void BL_StartPanelTimer(int slot) {
	if (g_BL[slot].PanelTimer != null)
		return;
	g_BL[slot].PanelTime = GetGameTime();
	g_BL[slot].PanelTimer = CreateTimer(0.04, BL_Timer_Panels, g_BL[slot].Lift, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void BL_ToggleHatch(int slot, int client, int index) {
	if (BL_LiftEntity(slot) == -1 || !BL_PanelsReady(slot)) {
		ReplyToCommand(client, "[BM lift] Lift is incomplete or unavailable. Rebuild it.");
		return;
	}
	bool opening = g_BL[slot].HatchGoal[index] < 0.5;
	g_BL[slot].HatchGoal[index] = opening ? (index == 0 ? 1.0 : 3.0) : 0.0;
	BL_StartPanelTimer(slot);
}

public bool BL_TracePanelTravel(int entity, int contentsMask, any slot) {
	return !BL_IsLiftPart(slot, entity);
}

bool BL_ClosingDoorClear(int slot, int index, float offset) {
	int mover = BL_LiftEntity(slot);
	if (mover == -1)
		return false;
	float cabin[3], start[3], finish[3];
	GetEntPropVector(mover, Prop_Data, "m_vecAbsOrigin", cabin);
	BL_PanelPosition(index, g_BL[slot].PanelOffset[index], cabin, start);
	BL_PanelPosition(index, offset, cabin, finish);
	SubtractVectors(start, cabin, start);
	SubtractVectors(finish, cabin, finish);
	BL_RotateXY(start, g_BL[slot].Yaw);
	BL_RotateXY(finish, g_BL[slot].Yaw);
	AddVectors(start, cabin, start);
	AddVectors(finish, cabin, finish);
	float mins[3] = {-25.0,-15.0,-1.0};
	float maxs[3] = {25.0,25.0,98.0};
	BL_YawBounds(g_BL[slot].Yaw, mins, maxs);
	Handle trace = TR_TraceHullFilterEx(start, finish, mins, maxs, MASK_PLAYERSOLID, BL_TraceLivingPlayer, _, TRACE_ENTITIES_ONLY);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	delete trace;
	return clear;
}

public bool BL_TraceLivingPlayer(int entity, int contentsMask) {
	return entity >= 1 && entity <= MaxClients && IsClientInGame(entity) && IsPlayerAlive(entity);
}

void BL_TogglePanels(int slot, int client, int first, int last) {
	if (!BL_PanelsReady(slot) || BL_LiftEntity(slot) == -1) {
		ReplyToCommand(client, "[BM lift] Lift is incomplete or unavailable. Rebuild it.");
		return;
	}
	bool opening = g_BL[slot].PanelGoal[first] < g_BLPanelTravel[first] * 0.5;
	for (int i = first; i <= last; i++)
		g_BL[slot].PanelGoal[i] = opening ? g_BLPanelTravel[i] : 0.0;
	BL_StartPanelTimer(slot);
	if (first >= 3) {
		BL_StopDoorSound(slot);
		EmitSoundToAll(BL_DOOR, BL_VisualEntity(slot), SNDCHAN_BODY, SNDLEVEL_NORMAL);
		g_BL[slot].DoorSound = true;
	}
}

public Action BL_Timer_Panels(Handle timer, any reference) {
	int slot = BL_Find(BL_RefEntity(reference));
	if (!slot)
		return Plugin_Stop;
	int mover = BL_LiftEntity(slot);
	if (mover == -1 || !BL_PanelsReady(slot)) {
		g_BL[slot].PanelTimer = null;
		return Plugin_Stop;
	}
	float now = GetGameTime();
	float step = BL_FloatMin(now - g_BL[slot].PanelTime, 0.08) * 32.0;
	g_BL[slot].PanelTime = now;
	bool active;
	for (int i = 0; i < 5; i++) {
		float difference = g_BL[slot].PanelGoal[i] - g_BL[slot].PanelOffset[i];
		if (FloatAbs(difference) < 0.01)
			continue;
		float next = g_BL[slot].PanelOffset[i] + (difference > 0.0 ? BL_FloatMin(step, difference) : -BL_FloatMin(step, -difference));
		if (i >= 3 && difference < 0.0 && !BL_ClosingDoorClear(slot, i, next)) {
			if (i >= 3) {
				g_BL[slot].PanelGoal[3] = g_BL[slot].PanelOffset[3];
				g_BL[slot].PanelGoal[4] = g_BL[slot].PanelOffset[4];
			} else
				g_BL[slot].PanelGoal[i] = g_BL[slot].PanelOffset[i];
			BL_Notice(slot, "[BM lift] Panel blocked. Step away from the opening, then toggle it again.");
			continue;
		}
		float position[3];
		BL_PanelLocalPosition(i, next, position);
		TeleportEntity(BL_RefEntity(g_BL[slot].Panels[i]), position, NULL_VECTOR, NULL_VECTOR);
		g_BL[slot].PanelOffset[i] = next;
		if (FloatAbs(g_BL[slot].PanelGoal[i] - next) >= 0.01)
			active = true;
	}
	if (FloatAbs(g_BL[slot].PanelGoal[3] - g_BL[slot].PanelOffset[3]) < 0.01
		&& FloatAbs(g_BL[slot].PanelGoal[4] - g_BL[slot].PanelOffset[4]) < 0.01)
		BL_StopDoorSound(slot);
	for (int i = 0; i < 2; i++) {
		float difference = g_BL[slot].HatchGoal[i] - g_BL[slot].HatchOffset[i];
		if (FloatAbs(difference) < 0.0001)
			continue;
		float hatchStep = step / 32.0;
		float next = g_BL[slot].HatchOffset[i] + (difference > 0.0 ? BL_FloatMin(hatchStep, difference) : -BL_FloatMin(hatchStep, -difference));
		if (!BL_HatchStepClear(slot, i, next)) {
			g_BL[slot].HatchGoal[i] = g_BL[slot].HatchOffset[i];
			BL_Notice(slot, "[BM lift] Hatch/ladder blocked. Clear the opening or ladder, then toggle again.");
			continue;
		}
		g_BL[slot].HatchOffset[i] = next;
		BL_UpdateHatchParts(slot, i);
		if (FloatAbs(g_BL[slot].HatchGoal[i] - next) >= 0.0001)
			active = true;
	}
	if (!active) {
		g_BL[slot].PanelTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

bool BL_CanUseCabinControls(int slot, int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return false;
	int entity = BL_LiftEntity(slot);
	if (entity == -1)
		return false;
	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	return BL_NearDeck(slot, client, origin);
}

void BL_PressCabinButton(int slot, int client, const float worldEye[3], const float worldHit[3]) {
	if (!BL_CanUseCabinControls(slot, client))
		return;
	float origin[3];
	GetEntPropVector(BL_LiftEntity(slot), Prop_Data, "m_vecAbsOrigin", origin);
	float eye[3], hit[3];
	eye = worldEye;
	hit = worldHit;
	BL_ToLocal(slot, origin, eye);
	BL_ToLocal(slot, origin, hit);
	float planeY = -75.0;
	if (eye[1] <= planeY || hit[1] >= eye[1])
		return;
	// The decorative controls sit in front of the cabin's collision wall.
	float fraction = (planeY - eye[1]) / (hit[1] - eye[1]);
	if (fraction < 0.0 || fraction > 1.0)
		return;
	float press[3];
	for (int axis = 0; axis < 3; axis++)
		press[axis] = eye[axis] + (hit[axis] - eye[axis]) * fraction;
	if (GetVectorDistance(eye, press) > 96.0 || FloatAbs(press[0] + 64.0) > 8.0)
		return;
	static const float heights[] = {101.0,86.0,71.0};
	for (int button = 0; button < sizeof(heights); button++) {
		if (FloatAbs(press[2] - heights[button]) > 4.0)
			continue;
		BL_RotateXY(press, g_BL[slot].Yaw);
		AddVectors(press, origin, press);
		EmitSoundToAll(BUTTON_CLICK, BL_VisualEntity(slot), SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, press);
		switch (button) {
			case 0: BL_MoveLift(slot, client, true);
			case 1: BL_MoveLift(slot, client, false);
			case 2: BL_StopLiftCommand(slot, client);
		}
		return;
	}
}

public bool BL_TraceGround(int entity, int contentsMask, any client) {
	return entity != client;
}

bool BL_NearDeck(int slot, int client, const float origin[3]) {
	float feet[3];
	GetClientAbsOrigin(client, feet);
	BL_ToLocal(slot, origin, feet);
	return FloatAbs(feet[0]) <= 80.0 && FloatAbs(feet[1]) <= 80.0
		&& feet[2] >= DECK_TOP - 4.0 && feet[2] < 151.0;
}

float BL_FloatMin(float a, float b) {
	return a < b ? a : b;
}

float BL_FloatMax(float a, float b) {
	return a > b ? a : b;
}

void BL_UpdateButtonLights(int slot, int state) {
	int visual = BL_VisualEntity(slot);
	if (visual != -1)
		SetEntProp(visual, Prop_Send, "m_nSkin", state);
	for (int i; i < sizeof(g_BL[slot].Calls); i++) {
		int call = BL_RefEntity(g_BL[slot].Calls[i]);
		if (call != -1)
			SetEntProp(call, Prop_Send, "m_nSkin", g_BL[slot].Moving && i == g_BL[slot].TargetStop ? 1 : 0);
	}
}

void BL_FreezeLift(int slot) {
	int soundEntity = BL_VisualEntity(slot);
	if (soundEntity != -1)
		StopSound(soundEntity, SNDCHAN_STATIC, BL_TRAVEL);
	delete g_BL[slot].Timer;
	g_BL[slot].Moving = false;
	BL_UpdateButtonLights(slot, 3);
	int entity = BL_LiftEntity(slot);
	if (entity == -1)
		return;
	float origin[3], zero[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	// Cancel the native arrival callback as well as velocity, or it can snap to the old stop.
	SetEntPropFloat(entity, Prop_Data, "m_flMoveDoneTime", -1.0);
	SetEntPropVector(entity, Prop_Data, "m_vecFinalDest", origin);
	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, zero);
	SetEntityMoveType(entity, MOVETYPE_NONE);
}

void BL_Arrived(int slot) {
	if (!g_BL[slot].Moving)
		return;
	int stop = g_BL[slot].TargetStop;
	BL_FreezeLift(slot);
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
			continue;
		if (!BL_CanUseCabinControls(slot, client)) {
			int ground = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
			if (BL_Find(ground) != slot || BL_IsCallStation(slot, ground))
				continue;
		}
		if (stop < 0)
			PrintToChat(client, "[BM lift] Reached safe travel limit. Use UP/DOWN to return.");
		else
			PrintToChat(client, "[BM lift] Arrived at landing %d/%d%s.", stop + 1, g_BL[slot].StopCount, FloatAbs(g_BL[slot].Stops[stop]) < 0.1 ? " (home)" : "");
	}
}

public void BL_OnArrived(const char[] output, int caller, int activator, float delay) {
	int slot = BL_Find(caller);
	if (!slot || caller != BL_LiftEntity(slot) || !g_BL[slot].Moving)
		return;
	float origin[3];
	GetEntPropVector(caller, Prop_Data, "m_vecAbsOrigin", origin);
	if (FloatAbs(origin[2] - g_BL[slot].TargetZ) < 0.05)
		BL_Arrived(slot);
}

public Action BL_Timer_Movement(Handle timer, any reference) {
	int slot = BL_Find(BL_RefEntity(reference));
	if (!slot)
		return Plugin_Stop;
	int entity = BL_LiftEntity(slot);
	if (entity == -1 || !g_BL[slot].Moving) {
		g_BL[slot].Timer = null;
		BL_FreezeLift(slot);
		return Plugin_Stop;
	}
	if (BL_VisualEntity(slot) == -1 || !BL_PanelsReady(slot)) {
		g_BL[slot].Timer = null;
		BL_FreezeLift(slot);
		BL_Notice(slot, "[BM lift] Stopped: a lift component is missing. Rebuild the lift.");
		return Plugin_Stop;
	}
	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	float remaining = g_BL[slot].TargetZ - origin[2];
	if (FloatAbs(remaining) < 0.05) {
		g_BL[slot].Timer = null;
		BL_Arrived(slot);
		return Plugin_Stop;
	}
	if (FloatAbs(origin[2] - g_BL[slot].LastZ) >= 0.5) {
		g_BL[slot].LastProgress = GetGameTime();
		g_BL[slot].LastZ = origin[2];
	} else if (GetGameTime() - g_BL[slot].LastProgress > 1.0) {
		g_BL[slot].Timer = null;
		BL_FreezeLift(slot);
		BL_Notice(slot, "[BM lift] Stopped: engine mover made no progress. Check server errors.");
		//LogMessage("Lift stalled at Z %.2f, target %.2f", origin[2], g_BL[slot].TargetZ);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

bool BL_OutsideBusyLift(int slot, int client) {
	int entity = BL_LiftEntity(slot);
	if (!g_BL[slot].Moving || entity == -1 || client == 0)
		return false;
	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	return !IsClientInGame(client) || !IsPlayerAlive(client) || !BL_NearDeck(slot, client, origin);
}

void BL_StopLiftCommand(int slot, int client) {
	if (BL_OutsideBusyLift(slot, client)) {
		ReplyToCommand(client, "[BM lift] Busy: outside controls cannot interrupt a trip.");
		return;
	}
	BL_FreezeLift(slot);
	ReplyToCommand(client, "[BM lift] Stopped. Use up/down to resume.");
}

void BL_MoveLift(int slot, int client, bool up) {
	int entity = BL_LiftEntity(slot);
	if (entity == -1)
		return;
	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	int selected = -1;
	float nearest = 99999.0;
	for (int stop; stop < g_BL[slot].StopCount; stop++) {
		float delta = g_BL[slot].Home[2] + g_BL[slot].Stops[stop] - origin[2];
		if ((up ? delta > 0.1 : delta < -0.1) && FloatAbs(delta) < nearest) {
			nearest = FloatAbs(delta);
			selected = stop;
		}
	}
	if (selected == -1) {
		float limit = g_BL[slot].Home[2] + (up ? g_BL[slot].Height : -g_BL[slot].Depth);
		if (up ? limit > origin[2] + 0.1 : limit < origin[2] - 0.1)
			BL_MoveToStop(slot, client, -1, up);
		else
			ReplyToCommand(client, "[BM lift] Already at the safe %s limit.", up ? "upper" : "lower");
		return;
	}
	BL_MoveToStop(slot, client, selected);
}

void BL_MoveToStop(int slot, int client, int stop, bool limitUp = false) {
	if (BL_OutsideBusyLift(slot, client)) {
		ReplyToCommand(client, "[BM lift] Busy: outside controls cannot interrupt a trip.");
		return;
	}
	int entity = BL_LiftEntity(slot);
	if (entity == -1 || stop < -1 || stop >= g_BL[slot].StopCount)
		return;
	if (BL_VisualEntity(slot) == -1 || !BL_PanelsReady(slot)) {
		BL_FreezeLift(slot);
		ReplyToCommand(client, "[BM lift] Visible platform missing. Rebuild the lift.");
		return;
	}
	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	float offset = stop == -1 ? (limitUp ? g_BL[slot].Height : -g_BL[slot].Depth) : g_BL[slot].Stops[stop];
	float target = g_BL[slot].Home[2] + offset;
	if (FloatAbs(target - origin[2]) < 0.1) {
		ReplyToCommand(client, "[BM lift] Already at that stop.");
		return;
	}
	BL_FreezeLift(slot);
	g_BL[slot].TargetZ = target;
	g_BL[slot].TargetStop = stop;
	g_BL[slot].LastZ = origin[2];
	g_BL[slot].LastProgress = GetGameTime();
	SetEntityMoveType(entity, MOVETYPE_PUSH);
	// Native SetPosition interpolates between the bottom and top endpoints.
	SetVariantFloat((offset + g_BL[slot].Depth) / (g_BL[slot].Height + g_BL[slot].Depth));
	if (!AcceptEntityInput(entity, "SetPosition", client > 0 ? client : -1)) {
		BL_FreezeLift(slot);
		ReplyToCommand(client, "[BM lift] Engine rejected the movement input.");
		return;
	}
	g_BL[slot].Moving = true;
	EmitSoundToAll(BL_TRAVEL, BL_VisualEntity(slot), SNDCHAN_STATIC, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
	BL_UpdateButtonLights(slot, target > origin[2] ? 1 : 2);
	g_BL[slot].Timer = CreateTimer(0.05, BL_Timer_Movement, g_BL[slot].Lift, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	if (stop == -1)
		ReplyToCommand(client, "[BM lift] Moving %s to safe limit (no outside button there). Use STOP to stop.", limitUp ? "up" : "down");
	else
		ReplyToCommand(client, "[BM lift] Moving %s to landing %d/%d. Use STOP to stop.", target > origin[2] ? "up" : "down", stop + 1, g_BL[slot].StopCount);
}

int BL_Find(int entity) {
	if (entity <= MaxClients || entity > MAXENTITIES || !IsValidEntity(entity))
		return 0;
	int slot = g_BLSlot[entity];
	return slot > 0 && g_BLRef[entity] == EntIndexToEntRef(entity) && !g_BL[slot].Removing ? slot : 0;
}

void BL_Notice(int slot, const char[] format, any ...) {
	char text[192];
	VFormat(text, sizeof(text), format, 3);
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && !IsFakeClient(client) && (client == slot || BL_CanUseCabinControls(slot, client)))
			PrintToChat(client, "%s", text);
}

void BL_StopDoorSound(int slot) {
	int visual = BL_VisualEntity(slot);
	if (g_BL[slot].DoorSound && visual != -1)
		StopSound(visual, SNDCHAN_BODY, BL_DOOR);
	g_BL[slot].DoorSound = false;
}

void BL_InitSlot(int slot) {
	g_BL[slot].OwnerSteamID[0] = '\0';
	g_BL[slot].OwnerTeam = 0;
	g_BL[slot].Yaw = 0.0;
	g_BL[slot].Height = 0.0;
	g_BL[slot].Depth = 0.0;
	g_BL[slot].TargetStop = 0;
	g_BL[slot].StopCount = 0;
	g_BL[slot].Lift = INVALID_ENT_REFERENCE;
	g_BL[slot].Visual = INVALID_ENT_REFERENCE;
	g_BL[slot].Failed = false;
	g_BL[slot].Red = false;
	g_BL[slot].Moving = false;
	g_BL[slot].Removing = false;
	g_BL[slot].DoorSound = false;
	g_BL[slot].Timer = null;
	g_BL[slot].PanelTimer = null;
	g_BL[slot].BlastTick = -1;
	BL_ResetHatches(slot);
	for (int i; i < 5; i++)
		g_BL[slot].Panels[i] = INVALID_ENT_REFERENCE;
	for (int i; i < sizeof(g_BL[slot].Calls); i++)
		g_BL[slot].Calls[i] = INVALID_ENT_REFERENCE;
}

void BL_Precache() {
	g_BLBeam = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	g_BLReady = true;
	static const char models[][] = {LIFT_MODEL, SHUTTER_MODEL, DOOR_MODEL, CALL_MODEL, FLOOR_HATCH_L_MODEL, FLOOR_HATCH_R_MODEL, ROOF_HATCH_L_MODEL, ROOF_HATCH_R_MODEL, CLIMB_MODEL};
	for (int i; i < sizeof(models); i++)
		if (!FileExists(models[i], true) || !PrecacheModel(models[i], true)) {
			g_BLReady = false;
			LogError("Missing lift asset: %s", models[i]);
		}
	for (int i; i < 3; i++)
		if (!FileExists(g_BLLadderModels[i], true) || !PrecacheModel(g_BLLadderModels[i], true))
			g_BLReady = false;
	PrecacheSound(BUTTON_CLICK, true);
	PrecacheSound(BL_BELL, true);
	PrecacheSound(BL_TRAVEL, true);
	PrecacheSound(BL_DOOR, true);
	PrecacheSound(BL_COLLAPSE, true);
	for (int slot = 1; slot < BL_SLOT_COUNT; slot++)
		BL_InitSlot(slot);
	for (int client = 1; client <= MaxClients; client++) {
		g_BLNextGuide[client] = 0.0;
		g_BLNextGuideHint[client] = 0.0;
	}
	for (int entity; entity <= MAXENTITIES; entity++) {
		g_BLSlot[entity] = 0;
		g_BLRef[entity] = INVALID_ENT_REFERENCE;
	}
}

void BL_ClearAll() {
	delete g_BLPendingTimer;
	for (int holder = 1; holder <= MaxClients; holder++)
		if (g_BLHeldOwnerSerial[holder])
			StopHolding(holder, true);
	for (int slot = 1; slot < BL_SLOT_COUNT; slot++)
		BL_RemoveLift(slot);
}

public bool BL_TraceHeight(int entity, int mask, any slot) {
	if (entity == 0)
		return true;
	if (entity <= MaxClients)
		return false;
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	return StrContains(classname, "weapon_") != 0 && StrContains(classname, "ragdoll") == -1;
}

bool BL_HasHumanRider(int reference, int exceptClient = 0) {
	int entity = EntRefToEntIndex(reference);
	int slot = BL_Find(entity);
	if (!slot || entity != BL_LiftEntity(slot))
		return false;
	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	for (int player = 1; player <= MaxClients; player++) {
		if (player == exceptClient || !IsClientInGame(player) || IsFakeClient(player) || !IsPlayerAlive(player))
			continue;
		float feet[3];
		GetClientAbsOrigin(player, feet);
		BL_ToLocal(slot, origin, feet);
		// Include the roof, a jumping rider, and the projecting entrance step.
		if ((FloatAbs(feet[0]) <= 123.0 && FloatAbs(feet[1]) <= 123.0
			&& feet[2] >= DECK_TOP - 4.0 && feet[2] <= 266.0)
			|| (FloatAbs(feet[0]) <= 48.0 && feet[1] >= -147.0 && feet[1] < -107.0
			&& feet[2] >= 8.0 && feet[2] <= 84.0))
			return true;
	}
	return false;
}

bool BL_ClearForRelocation(const float origin[3], float yaw) {
	for (int player = 1; player <= MaxClients; player++) {
		if (!IsClientInGame(player) || !IsPlayerAlive(player))
			continue;
		float feet[3];
		GetClientAbsOrigin(player, feet);
		SubtractVectors(feet, origin, feet);
		BL_RotateXY(feet, -yaw);
		if (FloatAbs(feet[0]) < 167.0 && feet[1] > -161.0 && feet[1] < 139.0
			&& feet[2] > -72.0 && feet[2] < 306.0)
			return false;
	}
	return true;
}

int BL_FindPending(int client) {
	char steamID[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, steamID, sizeof(steamID)))
		return 0;
	for (int slot = MAXPLAYERS + 1; slot < BL_SLOT_COUNT; slot++)
		if (BL_LiftEntity(slot) != -1 && StrEqual(g_BL[slot].OwnerSteamID, steamID))
			return slot;
	return 0;
}

void BL_MoveStorage(int from, int to, int owner) {
	// Movement/panel timers carry entity references, so they survive a slot transfer.
	g_BL[to] = g_BL[from];
	BL_InitSlot(from);
	for (int entity = MaxClients + 1; entity <= MAXENTITIES; entity++)
		if (g_BLSlot[entity] == from)
			g_BLSlot[entity] = to;
	int root = BL_LiftEntity(to);
	char name[64];
	FormatEx(name, sizeof(name), "bmprop_c#%d_m#%d", owner, MID(Prop_ArmoredLift));
	DispatchKeyValue(root, "targetname", name);
	TrackSolidProp(root, owner, Prop_ArmoredLift);
}

void BL_OwnerLeaving(int client, bool disconnecting = false) {
	int root = BL_LiftEntity(client);
	if (root == -1)
		return;
	if (g_BL[client].Failed || !BL_HasHumanRider(g_BL[client].Lift, disconnecting ? client : 0)) {
		BL_RemoveLift(client);
		return;
	}
	int pending;
	for (int slot = MAXPLAYERS + 1; slot < BL_SLOT_COUNT; slot++)
		if (g_BL[slot].Lift == INVALID_ENT_REFERENCE) {
			pending = slot;
			break;
		}
	if (!pending) {
		LogError("[BM lift] Pending lift storage exhausted (entity-cap invariant broken).");
		return;
	}
	RemoveEntityRef(ga_hPropPlaced[client], root);
	BL_MoveStorage(client, pending, 0);
	for (int player = 1; player <= MaxClients; player++)
		if ((!disconnecting || player != client) && IsClientInGame(player) && !IsFakeClient(player) && IsPlayerAlive(player)
			&& (BL_CanUseCabinControls(pending, player) || BL_Find(GetEntPropEnt(player, Prop_Send, "m_hGroundEntity")) == pending))
			PrintToChat(player, "[BM lift] Owner left. This lift will be removed when everyone exits.");
	if (g_BLPendingTimer == null)
		g_BLPendingTimer = CreateTimer(2.0, BL_Timer_Pending, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action BL_Timer_Pending(Handle timer) {
	bool remaining;
	for (int slot = MAXPLAYERS + 1; slot < BL_SLOT_COUNT; slot++) {
		if (g_BL[slot].Lift == INVALID_ENT_REFERENCE)
			continue;
		if (!BL_HasHumanRider(g_BL[slot].Lift))
			BL_RemoveLift(slot);
		else
			remaining = true;
	}
	if (remaining)
		return Plugin_Continue;
	g_BLPendingTimer = null;
	return Plugin_Stop;
}

void BL_ClearPending() {
	delete g_BLPendingTimer;
	for (int slot = MAXPLAYERS + 1; slot < BL_SLOT_COUNT; slot++)
		if (g_BL[slot].Lift != INVALID_ENT_REFERENCE)
			BL_RemoveLift(slot);
}

public void BL_ReclaimDeferred(any serial) {
	int client = GetClientFromSerial(serial);
	if (!client || !IsClientInGame(client) || IsFakeClient(client))
		return;
	int pending = BL_FindPending(client);
	if (!pending || g_BL[pending].Failed || GetClientTeam(client) != g_BL[pending].OwnerTeam
		|| g_BL[client].Lift != INVALID_ENT_REFERENCE || BL_OwnerHasHeldLift(client, 0))
		return;
	if (!ClearOldestPropIfLimitReached(client))
		return;
	BL_MoveStorage(pending, client, client);
	if (ga_hPropPlaced[client] == null)
		ga_hPropPlaced[client] = new ArrayList();
	AddUniqueEntityRef(ga_hPropPlaced[client], BL_LiftEntity(client));
	PrintToChat(client, "[BM lift] Welcome back. Your surviving lift is yours again; pending removal cancelled.");
}

public void Event_LiftOwnerTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || IsFakeClient(client) || event.GetBool("disconnect"))
		return;
	if (BL_LiftEntity(client) != -1 && event.GetInt("team") != g_BL[client].OwnerTeam)
		BL_OwnerLeaving(client);
	RequestFrame(BL_ReclaimDeferred, GetClientSerial(client));
}

int BL_PlacementOwner(int client) {
	int owner = g_BLHeldOwnerSerial[client] ? GetClientFromSerial(g_BLHeldOwnerSerial[client]) : 0;
	return owner > 0 && IsClientInGame(owner) ? owner : client;
}

bool BL_OwnerHasHeldLift(int owner, int exceptClient) {
	int serial = GetClientSerial(owner);
	for (int holder = 1; holder <= MaxClients; holder++)
		if (holder != exceptClient && g_BLHeldOwnerSerial[holder] == serial && BL_HoldingLift(holder))
			return true;
	return false;
}

void BL_Pickup(int client, int target) {
	int owner = BL_Find(target);
	if (!owner || owner > MaxClients || g_BL[owner].Failed || !BL_PanelsReady(owner))
		return;
	int mover = BL_LiftEntity(owner);
	if (mover == -1)
		return;
	float origin[3], eye[3], angles[3];
	GetEntPropVector(mover, Prop_Data, "m_vecAbsOrigin", origin);
	GetClientEyePosition(client, eye);
	if (GetVectorDistance(eye, origin) > LIFT_HOLD_DISTANCE)
		return;
	if (!BL_ClearForRelocation(origin, g_BL[owner].Yaw)) {
		PrintToChat(client, "[BM lift] Clear players from inside, on top of, and beside the lift before picking it up.");
		return;
	}
	if (GetEntityCount() > GetMaxEntities() - 80) {
		PrintToChat(client, "[BM lift] Too few free entity slots to pick up the lift.");
		return;
	}
	PropId previousModel = ga_iModelIndex[client];
	int previousOwner = ga_iPropOwner[client];
	ga_iModelIndex[client] = Prop_ArmoredLift;
	ga_iPropOwner[client] = owner;
	g_BLHeldOwnerSerial[client] = GetClientSerial(owner);
	g_BLHeldRed[client] = g_BL[owner].Red;
	angles[1] = g_BL[owner].Yaw;
	if (!CreateProp(client, origin, angles, GetEntProp(mover, Prop_Data, "m_iHealth"))
		|| BL_RefEntity(ga_iPropHolding[client]) == -1) {
		g_BLHeldOwnerSerial[client] = 0;
		g_BLHeldRed[client] = false;
		ga_iModelIndex[client] = previousModel;
		ga_iPropOwner[client] = previousOwner;
		return;
	}
	ClearPropSelections(client);
	BL_RemoveLift(owner);
	PrintToChat(client, "[BM lift] Picked up. AIM places it for free; Sprint or attack deletes it.");
}



bool BL_HoldingLift(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)
		|| ga_iModelIndex[client] != Prop_ArmoredLift || ga_bHoldingBlueprint[client])
		return false;
	int entity = EntRefToEntIndex(ga_iPropHolding[client]);
	return entity > MaxClients && IsValidEntity(entity)
		&& (ga_hBatchMoveData[client] == null || ga_hBatchMoveData[client].Length == 0);
}





public bool BL_TraceLanding(int entity, int mask, any client) {
	if (entity > MaxClients && entity == BL_RefEntity(ga_iPropHolding[client]))
		return false;
	return BL_TraceHeight(entity, mask, client);
}

bool BL_LandingSupport(int entity) {
	if (entity == 0)
		return true;
	return entity > MaxClients && !BL_Find(entity) && GetEntityMoveType(entity) == MOVETYPE_NONE
		&& GetEntPropEnt(entity, Prop_Data, "m_hMoveParent") == -1;
}

bool BL_ValidLanding(int client, const float home[3], float yaw, float offset, float callY, float ground, float &base) {
	float start[3], end[3], highest = ground - 1.0, postLow = 99999.0, postHigh = -99999.0;
	// Only the destination needs footing; the span back to the step may be a jumpable gap.
	static const float feet[][2] = {{-16.0,-16.0},{16.0,-16.0},{-16.0,16.0},{16.0,16.0},{0.0,0.0},
		{-2.0,-2.0},{2.0,-2.0},{-2.0,2.0},{2.0,2.0}};
	for (int point; point < sizeof(feet); point++) {
		start[0] = feet[point][0]; start[1] = callY + feet[point][1];
		start[2] = ground + BL_LANDING_FLOOR_SLACK + 1.0;
		if (point >= 5)
			start[0] += BL_CALL_X;
		BL_RotateXY(start, yaw);
		AddVectors(start, home, start);
		end = start; end[2] = home[2] + ground - BL_LANDING_FLOOR_SLACK - 2.0;
		Handle trace = TR_TraceRayFilterEx(start, end, MASK_PLAYERSOLID, RayType_EndPoint, BL_TraceLanding, client);
		float hit[3], normal[3];
		TR_GetEndPosition(hit, trace);
		TR_GetPlaneNormal(trace, normal);
		float floorZ = hit[2] - home[2];
		bool supported = TR_DidHit(trace) && !TR_StartSolid(trace) && normal[2] >= BL_LANDING_MIN_NORMAL
			&& !(TR_GetSurfaceFlags(trace) & SURF_SKY) && BL_LandingSupport(TR_GetEntityIndex(trace))
			&& FloatAbs(floorZ - (ground - 1.0)) <= BL_LANDING_FLOOR_SLACK;
		delete trace;
		if (!supported) {
			g_BLScan[client].SupportRejected++;
			return false;
		}
		if (point < 5)
			highest = BL_FloatMax(highest, floorZ);
		else {
			postLow = BL_FloatMin(postLow, floorZ);
			postHigh = BL_FloatMax(postHigh, floorZ);
		}
	}
	base = postLow + 0.5;
	for (int part; part < 4; part++) {
		float mins[3] = {-16.0,-16.0,0.0}, maxs[3] = {16.0,16.0,72.0};
		start[0] = 0.0; start[1] = callY; start[2] = highest + 1.0;
		end = start;
		if (part == 1) {
			// Clear body-height space over the gap, without tracing through the slope below it.
			start[1] = -139.0;
			start[2] = end[2] = BL_FloatMax(offset + DECK_TOP, highest + 1.0);
			mins[1] = -1.0; maxs[1] = 1.0;
		} else if (part >= 2) {
			start[0] = BL_CALL_X;
			start[2] = part == 2 ? postHigh + 1.0 : base + BL_CALL_Z - 4.5;
			mins[0] = part == 2 ? -2.0 : -9.0;
			maxs[0] = -mins[0];
			mins[1] = part == 2 ? -2.0 : -3.0;
			maxs[1] = -mins[1];
			maxs[2] = part == 2 ? base + BL_CALL_Z - 4.5 - start[2] : 9.0;
			end = start;
		}
		BL_RotateXY(start, yaw);
		BL_RotateXY(end, yaw);
		AddVectors(start, home, start);
		AddVectors(end, home, end);
		BL_YawBounds(yaw, mins, maxs);
		Handle trace = TR_TraceHullFilterEx(start, end, mins, maxs, MASK_PLAYERSOLID, BL_TraceLanding, client);
		bool clear = !TR_StartSolid(trace) && !TR_AllSolid(trace) && !TR_DidHit(trace);
		delete trace;
		if (!clear) {
			g_BLScan[client].ClearanceRejected++;
			return false;
		}
	}
	return true;
}

void BL_AddLanding(int client, int candidate) {
	int stop = g_BLScan[client].StopCount++;
	g_BLScan[client].Stops[stop] = g_BLScan[client].Candidates[candidate];
	g_BLScan[client].CallY[stop] = g_BLScan[client].CandidateY[candidate];
	g_BLScan[client].CallBase[stop] = g_BLScan[client].CandidateBase[candidate];
}

void BL_SelectLandings(int client) {
	g_BLScan[client].StopCount = 1;
	g_BLScan[client].Stops[0] = g_BLScan[client].CallBase[0] = 0.0;
	g_BLScan[client].CallY[0] = BL_CALL_Y;
	for (int direction = -1; direction <= 1; direction += 2) {
		float furthest;
		int extreme = -1;
		for (int i; i < g_BLScan[client].Count; i++) {
			float distance = g_BLScan[client].Candidates[i] * direction;
			if (distance > furthest) {
				furthest = distance;
				extreme = i;
			}
		}
		if (furthest < BL_LANDING_MIN_SPACING)
			continue;
		BL_AddLanding(client, extreme);
		for (int intermediate = 1; intermediate < BL_CALLS_PER_DIRECTION; intermediate++) {
			float target = furthest * intermediate / BL_CALLS_PER_DIRECTION;
			float bestDistance = 99999.0;
			int selected = -1;
			for (int i; i < g_BLScan[client].Count; i++) {
				float candidate = g_BLScan[client].Candidates[i];
				if (candidate * direction <= 0.0)
					continue;
				bool spaced = true;
				for (int stop; stop < g_BLScan[client].StopCount; stop++)
					if (FloatAbs(candidate - g_BLScan[client].Stops[stop]) < BL_LANDING_MIN_SPACING)
						spaced = false;
				float distance = FloatAbs(candidate * direction - target);
				if (spaced && distance < bestDistance) {
					bestDistance = distance;
					selected = i;
				}
			}
			if (selected != -1)
				BL_AddLanding(client, selected);
		}
	}
	for (int i = 1; i < g_BLScan[client].StopCount; i++)
		for (int j = i; j > 0 && g_BLScan[client].Stops[j] < g_BLScan[client].Stops[j-1]; j--) {
			float value = g_BLScan[client].Stops[j];
			g_BLScan[client].Stops[j] = g_BLScan[client].Stops[j-1];
			g_BLScan[client].Stops[j-1] = value;
			value = g_BLScan[client].CallY[j];
			g_BLScan[client].CallY[j] = g_BLScan[client].CallY[j-1];
			g_BLScan[client].CallY[j-1] = value;
			value = g_BLScan[client].CallBase[j];
			g_BLScan[client].CallBase[j] = g_BLScan[client].CallBase[j-1];
			g_BLScan[client].CallBase[j-1] = value;
		}
}

void BL_BeginLandingScan(int client, const float origin[3], float yaw) {
	g_BLScan[client].Origin = origin;
	g_BLScan[client].Yaw = yaw;
	g_BLScan[client].PreviewRef = ga_iPropHolding[client];
	g_BLScan[client].Count = 0;
	g_BLScan[client].Steps = 0;
	g_BLScan[client].Surfaces = 0;
	g_BLScan[client].ClearanceRejected = 0;
	g_BLScan[client].SupportRejected = 0;
	g_BLScan[client].Done = false;
	g_BLScan[client].Overflow = false;
	g_BLScan[client].NextScan = GetGameTime() + 2.0;
	g_BLScan[client].Outward = 0.0;
	BL_AutoTravel(client, origin, yaw, g_BLScan[client].Height, g_BLScan[client].Depth);
	g_BLScan[client].Cursor = origin[2] + g_BLScan[client].Height + BL_LANDING_FLOOR_SLACK + 8.0;
	BL_SelectLandings(client);
}

void BL_NextLandingColumn(int client) {
	g_BLScan[client].Outward += BL_LANDING_OUTWARD_STEP;
	g_BLScan[client].Done = g_BLScan[client].Outward > BL_LANDING_TRACE_LENGTH;
	if (g_BLScan[client].Done)
		g_BLScan[client].NextScan = GetGameTime() + 2.0;
	g_BLScan[client].Cursor = g_BLScan[client].Origin[2] + g_BLScan[client].Height + BL_LANDING_FLOOR_SLACK + 8.0;
}

void BL_AdvanceLandingScan(int client, int budget) {
	// Extend past the travel endpoint to find nearby uneven footing before clamping the cabin stop.
	float bottom = g_BLScan[client].Origin[2] - g_BLScan[client].Depth - 1.0 - BL_LANDING_SCAN_STEP - BL_LANDING_FLOOR_SLACK;
	for (int pass; pass < budget && !g_BLScan[client].Done; pass++) {
		if (++g_BLScan[client].Steps > BL_LANDING_SCAN_LIMIT) {
			g_BLScan[client].Done = g_BLScan[client].Overflow = true;
			g_BLScan[client].NextScan = GetGameTime() + 2.0;
			break;
		}
		if (g_BLScan[client].Cursor <= bottom) {
			BL_NextLandingColumn(client);
			continue;
		}
		float start[3] = {BL_CALL_X, BL_CALL_Y, 0.0}, end[3];
		float callY = BL_CALL_Y - g_BLScan[client].Outward;
		start[1] = callY;
		BL_RotateXY(start, g_BLScan[client].Yaw);
		AddVectors(start, g_BLScan[client].Origin, start);
		start[2] = g_BLScan[client].Cursor;
		end = start; end[2] = bottom;
		Handle trace = TR_TraceRayFilterEx(start, end, MASK_PLAYERSOLID, RayType_EndPoint, BL_TraceLanding, client);
		if (TR_AllSolid(trace) || !TR_DidHit(trace)) {
			BL_NextLandingColumn(client);
			delete trace;
			continue;
		}
		if (TR_StartSolid(trace)) {
			float exitDistance = (start[2] - bottom) * TR_GetFractionLeftSolid(trace);
			g_BLScan[client].Cursor -= BL_FloatMax(BL_LANDING_SCAN_STEP, exitDistance + 0.5);
			delete trace;
			continue;
		}
		float hit[3], normal[3];
		TR_GetEndPosition(hit, trace);
		TR_GetPlaneNormal(trace, normal);
		bool ground = normal[2] >= BL_LANDING_MIN_NORMAL && !(TR_GetSurfaceFlags(trace) & SURF_SKY) && BL_LandingSupport(TR_GetEntityIndex(trace));
		delete trace;
		g_BLScan[client].Cursor = hit[2] - 0.5;
		float floorOffset = hit[2] + 1.0 - g_BLScan[client].Origin[2];
		if (!ground || floorOffset < -g_BLScan[client].Depth - BL_LANDING_FLOOR_SLACK
			|| floorOffset > g_BLScan[client].Height + BL_LANDING_FLOOR_SLACK)
			continue;
		float offset = BL_FloatMax(-g_BLScan[client].Depth, BL_FloatMin(g_BLScan[client].Height, floorOffset));
		if (FloatAbs(offset) < BL_LANDING_MIN_SPACING)
			continue;
		g_BLScan[client].Surfaces++;
		// Search near to far and retain the closer validated site on the same uneven floor.
		bool duplicate;
		for (int i; i < g_BLScan[client].Count; i++)
			if (FloatAbs(g_BLScan[client].Candidates[i] - offset) <= BL_LANDING_FLOOR_SLACK)
				duplicate = true;
		float base;
		if (duplicate || !BL_ValidLanding(client, g_BLScan[client].Origin, g_BLScan[client].Yaw, offset, callY, floorOffset, base))
			continue;
		if (g_BLScan[client].Count == BL_MAX_CANDIDATES) {
			g_BLScan[client].Done = g_BLScan[client].Overflow = true;
			g_BLScan[client].NextScan = GetGameTime() + 2.0;
			break;
		}
		int candidate = g_BLScan[client].Count++;
		g_BLScan[client].Candidates[candidate] = offset;
		g_BLScan[client].CandidateY[candidate] = callY;
		g_BLScan[client].CandidateBase[candidate] = base;
	}
	BL_SelectLandings(client);
}

void BL_AutoTravel(int client, const float origin[3], float yaw, float &height, float &depth) {
	height = BL_MaxHeight(client, origin, yaw);
	depth = BL_MaxHeight(client, origin, yaw, false);
	if (height < 64.0)
		height = 0.0;
	if (depth < 64.0)
		depth = 0.0;
}

bool BL_ResolveTravel(int client, const float origin[3], float yaw, float &height, float &depth) {
	BL_AutoTravel(client, origin, yaw, height, depth);
	if (height == 0.0 && depth == 0.0) {
		PrintToChat(client, "[BM lift] No safe travel here. Move the preview to clear space with at least 64 units above or below. Your preview is kept.");
		return false;
	}
	return true;
}

void BL_RotateXY(float point[3], float yaw) {
	float angle = DegToRad(yaw), x = point[0], y = point[1];
	point[0] = x * Cosine(angle) - y * Sine(angle);
	point[1] = x * Sine(angle) + y * Cosine(angle);
}

void BL_GuideLine(int client, const float origin[3], float yaw, float start[3], float end[3], const int color[4]) {
	BL_RotateXY(start, yaw);
	BL_RotateXY(end, yaw);
	AddVectors(start, origin, start);
	AddVectors(end, origin, end);
	TE_SetupBeamPoints(start, end, g_BLBeam, 0, 0, 0, 0.4, 1.5, 1.5, 0, 0.0, color, 0);
	TE_SendToClient(client);
}

void BL_DrawGuides(int client, int entity, float yaw) {
	float now = GetGameTime();
	if (g_BLBeam <= 0 || now < g_BLNextGuide[client])
		return;
	g_BLNextGuide[client] = now + 0.25;
	float origin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	origin[2] += 1.0;
	float deltaYaw = FloatAbs(yaw - g_BLScan[client].Yaw);
	deltaYaw = FloatAbs(deltaYaw - 360.0 * RoundToNearest(deltaYaw / 360.0));
	bool newPreview = g_BLScan[client].PreviewRef != ga_iPropHolding[client];
	bool changed = newPreview
		|| GetVectorDistance(origin, g_BLScan[client].Origin) >= 4.0 || deltaYaw >= 2.0;
	if (changed || (g_BLScan[client].Done && now >= g_BLScan[client].NextScan))
		BL_BeginLandingScan(client, origin, yaw);
	BL_AdvanceLandingScan(client, BL_LANDING_SCAN_BUDGET);
	origin = g_BLScan[client].Origin;
	yaw = g_BLScan[client].Yaw;

	float height = g_BLScan[client].Height, depth = g_BLScan[client].Depth;
	char hint[192];
	FormatEx(hint, sizeof(hint), "[BM lift] %s | %d landings | safe up %.0f / down %.0f",
		g_BLScan[client].Overflow ? "Scan limit reached: move preview" : (g_BLScan[client].Done ? "Landing scan ready" : "Scanning landings..."),
		g_BLScan[client].StopCount, height, depth);
	// Update changed information immediately; only throttle identical hint refreshes.
	if (newPreview || now >= g_BLNextGuideHint[client] || !StrEqual(hint, g_BLLastGuideHint[client])) {
		PrintHintText(client, "%s", hint);
		strcopy(g_BLLastGuideHint[client], sizeof(g_BLLastGuideHint[]), hint);
		g_BLNextGuideHint[client] = now + 6.0;
	}
		
	// Show full travel independently of detected landings, just outside the cabin silhouette.
	for (int direction = -1; direction <= 1; direction += 2) {
		float offset = direction > 0 ? height : -depth;
		if (FloatAbs(offset) < 64.0)
			continue;
		int color[4] = {80, 255, 80, 230};
		if (direction < 0) {
			color[0] = 255; color[1] = 160; color[2] = 40;
		}
		if (g_BLScan[client].Overflow) {
			color[0] = 255; color[1] = 50; color[2] = 50;
		}
		for (int edge; edge < 4; edge++) {
			float start[3], end[3];
			start[0] = (edge == 1 || edge == 2) ? 121.0 : -121.0;
			start[1] = edge >= 2 ? 121.0 : -121.0;
			int next = (edge + 1) % 4;
			end[0] = (next == 1 || next == 2) ? 121.0 : -121.0;
			end[1] = next >= 2 ? 121.0 : -121.0;
			start[2] = end[2] = offset + DECK_TOP;
			BL_GuideLine(client, origin, yaw, start, end, color);
			// BL_GuideLine transforms its arguments; rebuild local endpoints for the vertical line.
			start[0] = (edge == 1 || edge == 2) ? 121.0 : -121.0;
			start[1] = edge >= 2 ? 121.0 : -121.0;
			start[2] = DECK_TOP;
			end = start;
			end[2] += offset;
			BL_GuideLine(client, origin, yaw, start, end, color);
		}
	}
	for (int stop; stop < g_BLScan[client].StopCount; stop++) {
		float offset = g_BLScan[client].Stops[stop];
		float callY = g_BLScan[client].CallY[stop], callBase = g_BLScan[client].CallBase[stop];
		int color[4] = {50, 210, 255, 230};
		bool valid = !g_BLScan[client].Overflow && (height >= 64.0 || depth >= 64.0);
		if (!valid) {
			color[0] = 255; color[1] = 50; color[2] = 50;
		} else if (offset < -0.1) {
			color[0] = 255; color[1] = 160; color[2] = 40;
		} else if (offset > 0.1) {
			color[0] = 80; color[1] = 255; color[2] = 80;
		}
		for (int edge; edge < 4; edge++) {
			float start[3], end[3];
			start[0] = (edge == 1 || edge == 2) ? 115.0 : -115.0;
			start[1] = edge >= 2 ? 115.0 : -115.0;
			int next = (edge + 1) % 4;
			end[0] = (next == 1 || next == 2) ? 115.0 : -115.0;
			end[1] = next >= 2 ? 115.0 : -115.0;
			start[2] = end[2] = offset + DECK_TOP;
			BL_GuideLine(client, origin, yaw, start, end, color);
		}
		for (int edge; edge < 4; edge++) {
			float start[3], end[3];
			start[0] = (edge == 1 || edge == 2) ? BL_CALL_X + 9.0 : BL_CALL_X - 9.0;
			start[2] = callBase + (edge >= 2 ? BL_CALL_Z + 4.5 : BL_CALL_Z - 4.5);
			int next = (edge + 1) % 4;
			end[0] = (next == 1 || next == 2) ? BL_CALL_X + 9.0 : BL_CALL_X - 9.0;
			end[2] = callBase + (next >= 2 ? BL_CALL_Z + 4.5 : BL_CALL_Z - 4.5);
			start[1] = end[1] = callY - 3.0;
			BL_GuideLine(client, origin, yaw, start, end, color);
		}
		float postBottom[3] = {BL_CALL_X,BL_CALL_Y,0.0}, postTop[3] = {BL_CALL_X,BL_CALL_Y,0.0};
		postBottom[1] = postTop[1] = callY;
		postBottom[2] = callBase;
		postTop[2] = callBase + BL_CALL_Z - 4.5;
		BL_GuideLine(client, origin, yaw, postBottom, postTop, color);
	}
}

void BL_ToLocal(int slot, const float origin[3], float point[3]) {
	SubtractVectors(point, origin, point);
	BL_RotateXY(point, -g_BL[slot].Yaw);
}

void BL_YawBounds(float yaw, float mins[3], float maxs[3]) {
	float low[3], high[3];
	low = mins;
	high = maxs;
	mins[0] = mins[1] = 99999.0;
	maxs[0] = maxs[1] = -99999.0;
	for (int corner = 0; corner < 4; corner++) {
		float point[3];
		point[0] = corner & 1 ? high[0] : low[0];
		point[1] = corner & 2 ? high[1] : low[1];
		BL_RotateXY(point, yaw);
		for (int axis = 0; axis < 2; axis++) {
			mins[axis] = BL_FloatMin(mins[axis], point[axis]);
			maxs[axis] = BL_FloatMax(maxs[axis], point[axis]);
		}
	}
}

float BL_MaxHeight(int slot, const float origin[3], float yaw, bool up = true) {
	float end[3];
	end = origin;
	end[2] = up ? 16380.0 - 306.0 : -16380.0;
	if ((up && end[2] <= origin[2]) || (!up && end[2] >= origin[2]))
		return 0.0;
	// Sweep the cabin and narrow step separately, not a full-width box through the landing/post area.
	float limit = FloatAbs(end[2] - origin[2]);
	for (int part; part < 2; part++) {
		float mins[3] = {-119.0,-117.0,1.0}, maxs[3] = {119.0,119.0,306.0};
		if (part == 1) {
			mins[0] = -42.0; mins[1] = -141.0;
			maxs[0] = 42.0; maxs[1] = -115.0; maxs[2] = 26.0;
		}
		BL_YawBounds(yaw, mins, maxs);
		Handle trace = TR_TraceHullFilterEx(origin, end, mins, maxs, MASK_PLAYERSOLID, BL_TraceHeight, slot);
		// The lower hull starts at +1: a 2-unit trace margin leaves the deck base 1 above ground.
		float clearance = TR_StartSolid(trace) || TR_AllSolid(trace) ? 0.0 : FloatAbs(end[2] - origin[2]) * TR_GetFraction(trace) - (up ? 4.0 : 2.0);
		delete trace;
		limit = BL_FloatMin(limit, clearance);
	}
	return BL_FloatMax(0.0, limit);
}

void BL_Destroyed(int entity) {
	int slot = g_BLSlot[entity];
	g_BLSlot[entity] = 0;
	g_BLRef[entity] = INVALID_ENT_REFERENCE;
	if (!slot || g_BL[slot].Removing || g_BL[slot].Failed)
		return;
	g_BL[slot].Failed = true;
	BL_FreezeLift(slot);
	BL_StopDoorSound(slot);
	DataPack pack = new DataPack();
	pack.WriteCell(slot);
	pack.WriteCell(g_BL[slot].Lift);
	RequestFrame(BL_RemoveDeferred, pack);
}

public void BL_RemoveDeferred(any data) {
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int slot = pack.ReadCell();
	int reference = pack.ReadCell();
	delete pack;
	if (g_BL[slot].Lift == reference)
		BL_RemoveLift(slot);
}

public Action BL_Touch(int entity, int touch) {
	int slot = BL_Find(entity);
	if (BL_IsCallStation(slot, entity))
		return Plugin_Continue;
	int root = slot ? BL_LiftEntity(slot) : -1;
	return root == -1 ? Plugin_Continue : SHook_OnTouchPropTakeDamage(root, touch);
}

public Action BL_Damage(int victim, int &attacker, int &inflictor, float &damage, int &damageType) {
	int slot = BL_Find(victim);
	int root = slot ? BL_LiftEntity(slot) : -1;
	if (root == -1 || g_BL[slot].Failed || damage <= 0.0 || BL_IsCallStation(slot, victim))
		return Plugin_Handled;
	if (attacker >= 1 && attacker <= MaxClients && IsClientInGame(attacker)
		&& GetClientTeam(attacker) == g_BL[slot].OwnerTeam)
		return Plugin_Handled;
	// CINSGameMovement::TracePlayerBBox applies this breakable-prop hit while jumping.
	if (damageType == DMG_DIRECT && FloatAbs(damage - 1000.0) < 0.01
		&& attacker >= 1 && attacker <= MaxClients && inflictor == attacker && IsClientInGame(attacker))
		return Plugin_Handled;
	// An explosion may touch several child panels; charge the greatest hit only once per blast/tick.
	if (damageType & DMG_BLAST) {
		int tick = GetGameTickCount();
		int source = inflictor > MaxClients && IsValidEntity(inflictor) ? EntIndexToEntRef(inflictor) : inflictor;
		if (g_BL[slot].BlastTick == tick && g_BL[slot].BlastSource == source) {
			float total = damage;
			damage = BL_FloatMax(0.0, damage - g_BL[slot].BlastDamage);
			g_BL[slot].BlastDamage = BL_FloatMax(g_BL[slot].BlastDamage, total);
		} else {
			g_BL[slot].BlastTick = tick;
			g_BL[slot].BlastSource = source;
			g_BL[slot].BlastDamage = damage;
		}
	}
	int health = GetEntProp(root, Prop_Data, "m_iHealth") - RoundToCeil(damage);
	SetEntProp(root, Prop_Data, "m_iHealth", health > 0 ? health : 1);
	if (!g_BL[slot].Red && health <= g_PropDefs[MID(Prop_ArmoredLift)].health / 4) {
		g_BL[slot].Red = true;
		EmitSoundToAll(BL_COLLAPSE, BL_VisualEntity(slot), SNDCHAN_AUTO, SNDLEVEL_NORMAL);
		for (int entity = MaxClients + 1; entity <= MAXENTITIES; entity++)
			if (BL_Find(entity) == slot && entity != root && entity != BL_RefEntity(g_BL[slot].Climb))
				SetEntityRenderColor(entity, 255, 0, 0, PROP_ALPHA);
	}
	if (health <= 0 && !g_BL[slot].Failed) {
		g_BL[slot].Failed = true;
		BL_FreezeLift(slot);
		DataPack pack = new DataPack();
		pack.WriteCell(slot);
		pack.WriteCell(g_BL[slot].Lift);
		RequestFrame(BL_RemoveDeferred, pack);
	}
	return Plugin_Handled;
}

int BL_TraceCallButton(const float eye[3], const float angles[3], float limit, float hit[3]) {
	float aim[3];
	GetAngleVectors(angles, aim, NULL_VECTOR, NULL_VECTOR);
	int target = -1;
	for (int slot = 1; slot < BL_SLOT_COUNT; slot++) {
		if (g_BL[slot].Failed || BL_LiftEntity(slot) == -1)
			continue;
		for (int i; i < g_BL[slot].StopCount; i++) {
			int station = BL_RefEntity(g_BL[slot].Calls[i]);
			if (station == -1)
				continue;
			float origin[3], local[3], direction[3];
			GetEntPropVector(station, Prop_Send, "m_vecOrigin", origin);
			local = eye;
			BL_ToLocal(slot, origin, local);
			local[2] -= BL_CALL_Z;
			direction = aim;
			BL_RotateXY(direction, -g_BL[slot].Yaw);
			float halfSize[3] = {9.0, 3.0, 4.5}, near = 0.0, far = limit;
			bool intersects = true;
			for (int axis; axis < 3; axis++) {
				if (FloatAbs(direction[axis]) < 0.000001) {
					if (FloatAbs(local[axis]) > halfSize[axis])
						intersects = false;
					continue;
				}
				float a = (-halfSize[axis] - local[axis]) / direction[axis];
				float b = (halfSize[axis] - local[axis]) / direction[axis];
				near = BL_FloatMax(near, BL_FloatMin(a, b));
				far = BL_FloatMin(far, BL_FloatMax(a, b));
			}
			if (!intersects || near > far || near >= limit)
				continue;
			limit = near;
			target = station;
		}
	}
	if (target != -1)
		for (int axis; axis < 3; axis++)
			hit[axis] = eye[axis] + aim[axis] * limit;
	return target;
}

public void BL_Use(any serial) {
	int client = GetClientFromSerial(serial);
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client)
		|| ga_iPropHolding[client] != INVALID_ENT_REFERENCE || AnyPropMenuFlagOpen(client))
		return;
	float eye[3], angles[3], hit[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	Handle trace = TR_TraceRayFilterEx(eye, angles, MASK_SOLID, RayType_Infinite, BL_TraceGround, client);
	int target = TR_GetEntityIndex(trace);
	TR_GetEndPosition(hit, trace);
	bool close = TR_DidHit(trace) && GetVectorDistance(eye, hit) <= 128.0;
	float limit = TR_DidHit(trace) ? BL_FloatMin(128.0, GetVectorDistance(eye, hit)) : 128.0;
	delete trace;
	// Non-solid call housings need an aim test, bounded by the nearest solid obstruction.
	int station = BL_TraceCallButton(eye, angles, limit, hit);
	if (station != -1) {
		target = station;
		close = true;
	}
	int slot = BL_Find(target);
	if (!close || !slot || g_BL[slot].Failed) {
		if (ga_bHoldingMeleeWeapon[client])
			QueuePropSelectionToggle(client);
		return;
	}
	for (int i; i < sizeof(g_BL[slot].Calls); i++)
		if (target == BL_RefEntity(g_BL[slot].Calls[i])) {
			float localHit[3];
			localHit = hit;
			BL_ToLocal(slot, g_BL[slot].Home, localHit);
			float buttonZ = BL_CALL_Z + g_BL[slot].CallBase[i];
			if (FloatAbs(localHit[2] - buttonZ) > 4.5 || FloatAbs(localHit[0] - BL_CALL_X) > 9.0)
				return;
			EmitSoundToAll(BUTTON_CLICK, target, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, hit);
			if (g_BL[slot].Moving)
				PrintToChat(client, "[BM lift] Busy: wait for the current trip to finish.");
			else {
				BL_MoveToStop(slot, client, i);
				if (g_BL[slot].Moving)
					EmitSoundToAll(BL_BELL, BL_VisualEntity(slot), SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
			}
			return;
		}
	for (int i; i < 4; i++)
		if (target == BL_RefEntity(g_BL[slot].Hatches[i])) {
			BL_ToggleHatch(slot, client, i / 2);
			return;
		}
	if (target == BL_RefEntity(g_BL[slot].Climb)) {
		BL_ToggleHatch(slot, client, 1);
		return;
	}
	for (int i; i < 5; i++)
		if (target == BL_RefEntity(g_BL[slot].Panels[i])) {
			BL_TogglePanels(slot, client, i >= 3 ? 3 : i, i >= 3 ? 4 : i);
			return;
		}
	if (target == BL_LiftEntity(slot) || target == BL_VisualEntity(slot))
		BL_PressCabinButton(slot, client, eye, hit);
}


bool BL_Build(int client, const float position[3], float yaw, int oldhealth = 0) {
	int slot = BL_PlacementOwner(client);
	if (BL_FindPending(slot))
		return false;
	bool movingExisting = g_BLHeldOwnerSerial[client] != 0;
	int entities = GetEntityCount();
	if (entities >= 1900 || entities > GetMaxEntities() - 80) {
		PrintToChat(client, "[BM lift] Cannot build: server entity count is too high (%d/%d). Lifts are blocked at 1900 entities to keep space for gameplay.", entities, GetMaxEntities());
		return false;
	}
	if (!g_BLReady || g_BL[slot].Lift != INVALID_ENT_REFERENCE || BL_OwnerHasHeldLift(slot, client)) {
		PrintToChat(client, "[BM lift] One lift per player. Assets and free entity slots are required.");
		return false;
	}
	BL_InitSlot(slot);
	if (!GetClientAuthId(slot, AuthId_SteamID64, g_BL[slot].OwnerSteamID, sizeof(g_BL[].OwnerSteamID))) {
		PrintToChat(client, "[BM lift] Your Steam authentication is not ready. Try placing again shortly.");
		return false;
	}
	g_BL[slot].OwnerTeam = GetClientTeam(slot);
	g_BL[slot].Yaw = yaw;
	float origin[3], top[3];
	origin = position;
	origin[2] += 1.0;
	float height, depth;
	if (!BL_ResolveTravel(client, origin, yaw, height, depth))
		return false;
	// Never build from a stale or partially completed preview scan.
	BL_BeginLandingScan(client, origin, yaw);
	BL_AdvanceLandingScan(client, BL_LANDING_SCAN_LIMIT + 1);
	if (!g_BLScan[client].Done || g_BLScan[client].Overflow) {
		PrintToChat(client, "[BM lift] Landing scan incomplete or limit reached; move the preview. Your preview is kept.");
		return false;
	}
	if (GetEntityCount() + 15 + g_BLScan[client].StopCount > GetMaxEntities() - 80) {
		PrintToChat(client, "[BM lift] Not enough entity capacity for the complete lift (%d parts) plus gameplay reserve. Your preview is kept.", 15 + g_BLScan[client].StopCount);
		return false;
	}
	g_BL[slot].StopCount = g_BLScan[client].StopCount;
	for (int stop; stop < g_BL[slot].StopCount; stop++) {
		g_BL[slot].Stops[stop] = g_BLScan[client].Stops[stop];
		g_BL[slot].CallY[stop] = g_BLScan[client].CallY[stop];
		g_BL[slot].CallBase[stop] = g_BLScan[client].CallBase[stop];
	}
	if (movingExisting && !BL_ClearForRelocation(origin, yaw)) {
		PrintToChat(client, "[BM lift] Clear players from the new position before placing the lift.");
		return false;
	}
	float bottom[3];
	bottom = origin;
	bottom[2] -= depth;
	top = origin;
	top[2] += height;
	int entity = CreateEntityByName("func_movelinear");
	if (entity == -1) {
		ReplyToCommand(client, "[BM lift] Could not create the lift mover (func_movelinear). Check the server console.");
		return false;
	}
	DispatchKeyValue(entity, "model", LIFT_MODEL);
	// Brush movers cannot render studio models. Only the non-solid child draws the deck.
	SetEntityRenderMode(entity, RENDER_NONE);
	DispatchKeyValue(entity, "targetname", "bm_lift_test_platform");
	DispatchKeyValue(entity, "movedir", "-90 0 0");
	DispatchKeyValue(entity, "startposition", "0");
	DispatchKeyValue(entity, "blockdamage", "0");
	DispatchKeyValueFloat(entity, "movedistance", height + depth);
	DispatchKeyValueFloat(entity, "speed", LIFT_SPEED);
	// Endpoints are calculated inside Spawn from the initial origin.
	DispatchKeyValueVector(entity, "origin", origin);
	DispatchKeyValue(entity, "angles", "0 0 0");
	if (!DispatchSpawn(entity)) {
		AcceptEntityInput(entity, "Kill");
		ReplyToCommand(client, "[BM lift] Platform spawn failed. Check the server console.");
		return false;
	}
	ActivateEntity(entity);
	SetEntityRenderMode(entity, RENDER_NONE);
	if (!HasEntProp(entity, Prop_Data, "m_flMoveDoneTime") || !HasEntProp(entity, Prop_Data, "m_vecFinalDest")
		|| !HasEntProp(entity, Prop_Data, "m_vecPosition1") || !HasEntProp(entity, Prop_Data, "m_vecPosition2")
		|| !HasEntProp(entity, Prop_Send, "m_nSolidType") || GetEntityMoveType(entity) != MOVETYPE_PUSH) {
		AcceptEntityInput(entity, "Kill");
		ReplyToCommand(client, "[BM lift] Required engine movement properties are unavailable. Placement cancelled.");
		return false;
	}
	g_BL[slot].Home = origin;
	g_BL[slot].Height = height;
	g_BL[slot].Depth = depth;
	g_BL[slot].Lift = EntIndexToEntRef(entity);
	SetEntProp(entity, Prop_Data, "m_takedamage", 0);
	SetEntPropVector(entity, Prop_Data, "m_vecPosition1", bottom);
	SetEntPropVector(entity, Prop_Data, "m_vecPosition2", top);
	if (!BL_CreateLiftVisual(slot, entity, origin) || !BL_CreateParts(slot, entity, origin)) {
		BL_RemoveLift(slot);
		ReplyToCommand(client, "[BM lift] Could not assemble the complete lift. Placement cancelled.");
		return false;
	}
	HookSingleEntityOutput(entity, "OnFullyOpen", BL_OnArrived);
	HookSingleEntityOutput(entity, "OnFullyClosed", BL_OnArrived);
	BL_FreezeLift(slot);
	float rotation[3];
	rotation[1] = yaw;
	TeleportEntity(entity, NULL_VECTOR, rotation, NULL_VECTOR);

	int health = g_PropDefs[MID(Prop_ArmoredLift)].health;
	SetEntProp(entity, Prop_Data, "m_iMaxHealth", health);
	int restoredHealth = movingExisting && oldhealth > 0 ? oldhealth : health;
	if (restoredHealth > health)
		restoredHealth = health;
	SetEntProp(entity, Prop_Data, "m_iHealth", restoredHealth);
	g_BL[slot].Red = movingExisting && (g_BLHeldRed[client] || restoredHealth <= health / 4);
	char name[64];
	FormatEx(name, sizeof(name), "bmprop_c#%d_m#%d", slot, MID(Prop_ArmoredLift));
	DispatchKeyValue(entity, "targetname", name);
	if (!ClearOldestPropIfLimitReached(slot)) {
		BL_RemoveLift(slot);
		return false;
	}
	if (ga_hPropPlaced[slot] == null)
		ga_hPropPlaced[slot] = new ArrayList();
	ga_hPropPlaced[slot].Push(EntIndexToEntRef(entity));
	TrackSolidProp(entity, slot, Prop_ArmoredLift);
	for (int part = MaxClients + 1; part < GetMaxEntities() && part <= MAXENTITIES; part++)
		if (IsValidEntity(part) && BL_IsLiftPart(slot, part)) {
			g_BLSlot[part] = slot;
			g_BLRef[part] = EntIndexToEntRef(part);
			bool callStation = BL_IsCallStation(slot, part);
			SetEntProp(part, Prop_Data, "m_takedamage", callStation ? 0 : 2);
			if (!callStation) {
				SDKHook(part, SDKHook_OnTakeDamage, BL_Damage);
				SDKHook(part, SDKHook_Touch, BL_Touch);
			}
			if (g_BL[slot].Red && part != entity && part != BL_RefEntity(g_BL[slot].Climb))
				SetEntityRenderColor(part, 255, 0, 0, PROP_ALPHA);
		}
	if (!movingExisting && g_iAllFree != 1)
		ga_iPlayerBuildPoints[client] -= g_PropDefs[MID(Prop_ArmoredLift)].cost;
	ga_iPropOwner[client] = 0;
	g_BLHeldOwnerSerial[client] = 0;
	g_BLHeldRed[client] = false;
	if (!movingExisting)
		LogPropBuild(client, Prop_ArmoredLift);
	PrintToChat(client, "[BM lift] %s: %d landings. UP/DOWN selects the next landing.", movingExisting ? "Replaced (health preserved; no charge)" : "Built", g_BL[slot].StopCount);
	if (g_BL[slot].StopCount == 1) {
		PrintToChat(client, "[BM lift] Home call button only: no extra supported landings found. UP/DOWN still uses safe travel limits.");
		//LogMessage("[BM lift] Home-only landing scan: pos=%.1f,%.1f,%.1f yaw=%.1f up=%.1f down=%.1f surfaces=%d clearance_rejected=%d support_rejected=%d passes=%d", origin[0], origin[1], origin[2], yaw, height, depth, g_BLScan[client].Surfaces, g_BLScan[client].ClearanceRejected, g_BLScan[client].SupportRejected, g_BLScan[client].Steps);
	}
	return true;
}

bool SG_Ready;

void SG_Init() {
	SG_g_EntitySlots = new ArrayList();
	SG_ResetSentries();
	SG_InitSettings();
	SG_Ready = SG_PrepareBulletEffects();
	SGB_Ready = SGB_Prepare();
	HookEvent("weapon_fire_on_empty", SGB_FireOnEmpty, EventHookMode_Post);
	HookEntityOutput("func_tank", "OnFire", SG_OnTankFire);
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client))
			SG_HookClient(client);
}

void SG_HookClient(int client) {
	SGB_ResetClient(client);
	SDKHook(client, SDKHook_WeaponCanUse, SG_BlockTurretPickup);
}

void SG_UnregisterRoot(int slot, int reference) {
	ArrayList list = ga_hPropPlaced[slot];
	if (list == null || reference == INVALID_ENT_REFERENCE)
		return;
	for (int i = list.Length - 1; i >= 0; i--)
		if (list.Get(i) == reference) {
			list.Erase(i);
			break;
		}
}

int SG_Root(int entity) {
	int slot = SG_EntitySlot(entity);
	if (!slot)
		return -1;
	int root = EntRefToEntIndex(SG_g_Sentries[slot].SentryBase);
	return IsValidNonClientEntity(root) ? root : -1;
}

bool SG_OwnerHasSentry(int owner, int exceptHolder = 0) {
	if (SG_g_Sentries[owner].Tank != INVALID_ENT_REFERENCE)
		return true;
	for (int client = 1; client <= MaxClients; client++)
		if (client != exceptHolder && ga_iModelIndex[client] == Prop_SentryGun
			&& ga_iPropOwner[client] == owner && IsValidNonClientEntity(EntRefToEntIndex(ga_iPropHolding[client])))
			return true;
	return false;
}

int SG_PlacementOwner(int client) {
	int owner = ga_iPropOwner[client];
	return owner > 0 && owner <= MaxClients && IsClientInGame(owner) ? owner : client;
}

bool SG_CanBuild(int client, bool solid) {
	if (!SG_g_BuildEnabled && !ga_iPropOwner[client]) {
		PrintToChat(client, "[Sentry Gun] Building new sentries is disabled by the server.");
		return false;
	}
	int owner = SG_PlacementOwner(client);
	if (!SG_Ready) {
		PrintToChat(client, "[Sentry Gun] Unavailable: update %s.txt and check server errors.", RESUPPLY_GAMEDATA_FILE);
		return false;
	}
	if (GetClientTeam(owner) < TEAM_SECURITY || GetClientTeam(client) != GetClientTeam(owner)) {
		PrintToChat(client, "[Sentry Gun] The builder and owner must be on the same playing team.");
		return false;
	}
	if ((solid || !ga_iPropOwner[client]) && SG_OwnerHasSentry(owner, client)) {
		PrintToChat(client, "[Sentry Gun] One per owner, including a picked-up sentry.");
		return false;
	}
	int reserved;
	for (int other = 1; other <= MaxClients; other++)
		if (SG_OwnerHasSentry(other))
			reserved++;
	if (!SG_OwnerHasSentry(owner) && reserved >= SG_MAX_SENTRIES) {
		PrintToChat(client, "[Sentry Gun] Server limit: %d sentries, including picked-up sentries.", SG_MAX_SENTRIES);
		return false;
	}
	return true;
}

// Conservative boxes enclosing the current sentry collision meshes, relative to its base.
static const float SG_PlacementMins[3][3] = {
	{-22.8, -24.8, 0.1}, {-8.5, -11.1, 12.9}, {-12.0, -5.6, 21.1}
};
static const float SG_PlacementMaxs[3][3] = {
	{22.8, 14.8, 12.9}, {8.5, 7.1, 29.1}, {28.6, 5.6, 32.3}
};

public bool SG_TracePlacement(int entity, int contentsMask, any client) {
	if (entity > 0 && entity <= MaxClients)
		return false;
	return entity <= 0 || entity != EntRefToEntIndex(ga_iPropHolding[client]);
}

bool SG_ClearPlacement(int client, const float position[3], float yaw) {
	float eye[3], target[3];
	GetClientEyePosition(client, eye);
	target = position;
	target[2] += 8.0;
	if (TR_PointOutsideWorld(target))
		return false;
	Handle trace = TR_TraceRayFilterEx(eye, target, MASK_SOLID, RayType_EndPoint, SG_TracePlacement, client);
	bool blocked = TR_StartSolid(trace) || TR_AllSolid(trace) || TR_DidHit(trace);
	delete trace;
	if (blocked)
		return false;
	float sine = Sine(DegToRad(yaw)), cosine = Cosine(DegToRad(yaw));
	for (int part = 0; part < sizeof(SG_PlacementMins); part++) {
		float centerX = (SG_PlacementMins[part][0] + SG_PlacementMaxs[part][0]) * 0.5;
		float centerY = (SG_PlacementMins[part][1] + SG_PlacementMaxs[part][1]) * 0.5;
		float halfX = (SG_PlacementMaxs[part][0] - SG_PlacementMins[part][0]) * 0.5;
		float halfY = (SG_PlacementMaxs[part][1] - SG_PlacementMins[part][1]) * 0.5;
		float extentX = FloatAbs(cosine) * halfX + FloatAbs(sine) * halfY;
		float extentY = FloatAbs(sine) * halfX + FloatAbs(cosine) * halfY;
		float origin[3], mins[3], maxs[3];
		origin[0] = position[0] + centerX * cosine - centerY * sine;
		origin[1] = position[1] + centerX * sine + centerY * cosine;
		origin[2] = position[2];
		mins[0] = -extentX;
		mins[1] = -extentY;
		mins[2] = SG_PlacementMins[part][2];
		maxs[0] = extentX;
		maxs[1] = extentY;
		maxs[2] = SG_PlacementMaxs[part][2];
		trace = TR_TraceHullFilterEx(origin, origin, mins, maxs, MASK_SOLID, SG_TracePlacement, client);
		blocked = TR_StartSolid(trace) || TR_AllSolid(trace) || TR_DidHit(trace);
		delete trace;
		if (blocked)
			return false;
	}
	return true;
}

bool SG_Build(int client, const float position[3], const float angles[3], int oldHealth) {
	if (FloatAbs(angles[0]) > 0.1 || FloatAbs(angles[2]) > 0.1) {
		PrintToChat(client, "[Sentry Gun] Reset pitch and roll before placing; the base supports spin only.");
		return false;
	}
	if (!SG_ClearPlacement(client, position, angles[1])) {
		PrintToChat(client, "[Sentry Gun] Keep the whole sentry clear of walls, floors and solid props, with its base visible to you.");
		return false;
	}
	int entityCount = GetEntityCount();
	if (entityCount + 5 > GetMaxEntities() - 80 || entityCount >= 1900) {
		PrintToChat(client, "[Sentry Gun] Not enough free entities. Your preview is kept.");
		return false;
	}
	if (!SG_PrecacheSentryModels()) {
		PrintToChat(client, "[Sentry Gun] Install the BM sentry models and collision files on the server and clients.");
		return false;
	}
	int slot = SG_PlacementOwner(client);
	bool moving = ga_iPropOwner[client] > 0;
	if (!SG_SpawnTank(slot, position, angles[1]))
		return false;
	if (!ClearOldestPropIfLimitReached(slot)) {
		SG_RemoveTank(slot);
		return false;
	}
	int root = EntRefToEntIndex(SG_g_Sentries[slot].SentryBase);
	int maxHealth = g_PropDefs[MID(Prop_SentryGun)].health;
	int health = moving && oldHealth > 0 && oldHealth < maxHealth ? oldHealth : maxHealth;
	SetEntProp(root, Prop_Data, "m_iHealth", health);
	SetEntProp(root, Prop_Data, "m_iMaxHealth", maxHealth);
	SG_g_Sentries[slot].LowHpThreshold = RoundToFloor(float(maxHealth) * PROP_GLOWHP_PERCENT);
	char name[64];
	FormatEx(name, sizeof(name), "bmprop_c#%d_m#%d", slot, MID(Prop_SentryGun));
	DispatchKeyValue(root, "targetname", name);
	TrackSolidProp(root, slot, Prop_SentryGun);
	if (ga_hPropPlaced[slot] == null)
		ga_hPropPlaced[slot] = new ArrayList();
	ga_hPropPlaced[slot].Push(SG_g_Sentries[slot].SentryBase);
	int refs[3];
	refs[0] = SG_g_Sentries[slot].SentryBase;
	refs[1] = SG_g_Sentries[slot].SentryYaw;
	refs[2] = SG_g_Sentries[slot].Visual;
	for (int i = 0; i < sizeof(refs); i++) {
		int part = EntRefToEntIndex(refs[i]);
		SetEntProp(part, Prop_Data, "m_iMaxHealth", maxHealth);
		SetEntProp(part, Prop_Data, "m_takedamage", DAMAGE_YES);
		SDKHook(part, SDKHook_OnTakeDamage, SG_PropDamage);
		SDKHook(part, SDKHook_Touch, SG_PropTouch);
	}
	SG_UpdateDamageColor(slot, health, true);
	if (!moving && g_iAllFree != 1)
		ga_iPlayerBuildPoints[client] -= g_PropDefs[MID(Prop_SentryGun)].cost;
	ga_iPropOwner[client] = 0;
	SG_g_Sentries[slot].Enabled = true;
	if (!moving)
		LogPropBuild(client, Prop_SentryGun);
	return true;
}

void SG_QueueRemove(int slot) {
	if (SG_g_Sentries[slot].Tank == INVALID_ENT_REFERENCE || SG_g_Sentries[slot].Removing)
		return;
	SGB_RemoveTarget(slot);
	SG_g_Sentries[slot].Removing = true;
	SG_g_Sentries[slot].Enabled = false;
	SG_g_Sentries[slot].Active = false;
	SG_g_Sentries[slot].ShotEpoch++;
	DataPack pack = new DataPack();
	pack.WriteCell(slot);
	pack.WriteCell(SG_g_Sentries[slot].Tank);
	RequestFrame(SG_RemoveDeferred, pack);
}

void SG_QueueRemoveEntity(int entity) {
	int slot = SG_EntitySlot(entity);
	if (slot)
		SG_QueueRemove(slot);
}

public void SG_RemoveDeferred(DataPack pack) {
	pack.Reset();
	int slot = pack.ReadCell();
	int reference = pack.ReadCell();
	delete pack;
	if (SG_g_Sentries[slot].Tank == reference && SG_g_Sentries[slot].Removing)
		SG_RemoveTank(slot);
}

void SG_Destroyed(int entity) {
	int slot = SG_EntitySlot(entity);
	if (!slot)
		return;
	SG_g_EntitySlots.Set(entity, 0);
	SG_QueueRemove(slot);
}

void SG_OwnerLeaving(int client) {
	SG_QueueRemove(client);
	for (int holder = 1; holder <= MaxClients; holder++)
		if (ga_iModelIndex[holder] == Prop_SentryGun && ga_iPropOwner[holder] == client) {
			StopHolding(holder);
			ga_iPropOwner[holder] = 0;
		}
}

public Action SG_PropTouch(int entity, int other) {
	int root = SG_Root(entity);
	if (root != -1)
		return SHook_OnTouchPropTakeDamage(root, other);
	return Plugin_Continue;
}

void SG_UpdateDamageColor(int slot, int health, bool force = false) {
	bool red = health <= SG_g_Sentries[slot].LowHpThreshold;
	if (!force && red == SG_g_Sentries[slot].LowHpRed)
		return;
	SG_g_Sentries[slot].LowHpRed = red;
	int refs[3];
	refs[0] = SG_g_Sentries[slot].SentryBase;
	refs[1] = SG_g_Sentries[slot].SentryYaw;
	refs[2] = SG_g_Sentries[slot].Visual;
	for (int i = 0; i < sizeof(refs); i++) {
		int part = EntRefToEntIndex(refs[i]);
		if (IsValidNonClientEntity(part))
			SetEntityRenderColor(part, 255, red ? 0 : 255, red ? 0 : 255, red ? PROP_ALPHA : 255);
	}
}

public Action SG_PropDamage(int entity, int &attacker, int &inflictor, float &damage, int &damageType) {
	int slot = SG_EntitySlot(entity);
	int root = SG_Root(entity);
	if (!slot || root == -1 || SG_g_Sentries[slot].Removing || damage <= 0.0)
		return Plugin_Handled;
	if (attacker >= 1 && attacker <= MaxClients && IsClientInGame(attacker)
		&& GetClientTeam(attacker) == SG_g_Sentries[slot].Team)
		return Plugin_Handled;
	// Multiple solid parts share health; count the greatest hit once per blast/tick.
	if (damageType & DMG_BLAST) {
		int tick = GetGameTickCount();
		int source = IsValidNonClientEntity(inflictor) ? EntIndexToEntRef(inflictor) : inflictor;
		if (SG_g_Sentries[slot].BlastTick == tick && SG_g_Sentries[slot].BlastSource == source) {
			float previous = SG_g_Sentries[slot].BlastDamage;
			if (damage > previous) {
				SG_g_Sentries[slot].BlastDamage = damage;
				damage -= previous;
			} else
				return Plugin_Handled;
		} else {
			SG_g_Sentries[slot].BlastTick = tick;
			SG_g_Sentries[slot].BlastSource = source;
			SG_g_Sentries[slot].BlastDamage = damage;
		}
	}
	int health = GetEntProp(root, Prop_Data, "m_iHealth") - RoundToCeil(damage);
	SetEntProp(root, Prop_Data, "m_iHealth", health > 0 ? health : 1);
	SG_UpdateDamageColor(slot, health);
	if (health <= 0)
		SG_QueueRemove(slot);
	return Plugin_Handled;
}
