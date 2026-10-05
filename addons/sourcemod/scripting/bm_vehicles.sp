#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <adminmenu>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "1.4.19"

native bool ThirdPerson_IsClientActive(int client);
Handle g_PassengerSetLayers;
Handle g_PassengerGetMuzzle;
int g_PassengerOverlayOffset = -1;
Handle g_AimControlTimer[MAXPLAYERS + 1];
int g_AimControlStep[MAXPLAYERS + 1];
int g_AimControlWeapon[MAXPLAYERS + 1];
bool g_AimControlHeld[MAXPLAYERS + 1];
bool g_AimControlLifted[MAXPLAYERS + 1];
float g_AimControlOrigin[MAXPLAYERS + 1][3];
#define ATV_WRECK_MODEL "models/botmassacre/atv_wreck_v1/wreck.mdl"
#define VEHICLE_WRECK_MODEL "models/botmassacre/humvee_wreck_v1/wreck.mdl"
#define VEHICLE_DEBRIS_LIFETIME 15.0 // Seconds before loose wheels and panels are removed.
#define VEHICLE_DEBRIS_LIMIT 28 // Maximum live vehicle debris pieces across the server.
#define VEHICLE_DEBRIS_PARTS 7
#define VEHICLE_DEBRIS_LAUNCH_SPEED 300.0 // Outward launch speed in units/second, varied by 15% per piece.
#define VEHICLE_DEBRIS_LAUNCH_LIFT 320.0 // Upward launch speed in units/second, varied by 15% per piece.
#define VEHICLE_MODEL "models/botmassacre/humvee_v6/bm_humvee.mdl"
#define HUMVEE_CAMERA_HEIGHT 70.0 // Cockpit eye height above the vehicle origin; fits the stock side windows.
#define HUMVEE_CAMERA_FRONT 15.0 // Forward position for the driver/front passenger; higher moves toward the windshield.
#define HUMVEE_CAMERA_REAR -21.0 // Forward position for rear passengers, aligned with their side windows.
#define HUMVEE_CAMERA_LEAN 4.0 // Small sideways look offset to keep the rider's head behind the camera.
// Compiled Humvee: reference=0, steering idle=1.
#define VEHICLE_IDLE_SEQUENCE 1
// Speeds in units/second; acceleration and deceleration in units/second squared.
#define VEHICLE_HEALTH 50000.0 // Maximum HP when spawned or repaired; glass damage scales with this value.
#define VEHICLE_SMOKE_HEALTH 0.5 // Smoke below this fraction of maximum HP.
#define VEHICLE_FIRE_HEALTH 0.25 // Engine fire below this fraction of maximum HP.
#define VEHICLE_WRECK_EFFECT_LIFETIME 45.0 // Seconds allowed for the destruction effect and its lingering particles.
#define VEHICLE_FORWARD_SPEED 400.0
#define VEHICLE_REVERSE_SPEED 90.0
#define VEHICLE_ACCELERATION 160.0
#define VEHICLE_COAST_DECELERATION 120.0 // Slowdown with no throttle or brake, in units/second squared; higher stops sooner.
#define VEHICLE_BRAKE_DECELERATION 500.0
#define VEHICLE_STEP_HEIGHT 32.0 // Maximum curb/step climb height in Source units.
#define VEHICLE_SUSPENSION_TRAVEL 32.0 // Maximum suspension extension/uneven ground allowance in Source units.
#define VEHICLE_MIN_GROUND_Z 0.707107 // Slope limit: value = cos(degrees * PI / 180); degrees = acos(value) * 180 / PI. 0.707107 = 45 degrees; lower allows steeper slopes.
#define VEHICLE_IMPACT_INTERVAL 0.25 // Seconds between pushes to the same target from this vehicle.
#define VEHICLE_IMPACT_BOT_DAMAGE 100.0 // Damage per push to a bot on the opposing team.
#define VEHICLE_IMPACT_PUSH_SCALE 1.3 // Player and bot push speed multiplier.
#define VEHICLE_IMPACT_MAX_PUSH 650.0 // Maximum horizontal player and bot push, in units/second.
#define VEHICLE_PUSH_DURATION 0.35 // Horizontal external force; eases out over the final half.
#define VEHICLE_PUSH_LOOKAHEAD 16.0 // Contact lead distance in Source units, giving players time to move clear.
#define EF_NOINTERP 8
#define DRIVER_POSE "rifle_crouch_relaxed_idle"
#define DRIVER_RIG_MODEL "models/botmassacre/humvee_driver_v2/bm_driver_ranger.mdl"
#define DRIVER_SEATED_POSE "seated_idle"
#define DRIVER_IDLE_SEQUENCE 1
#define DRIVER_BONEMERGE_EFFECTS (1 | 128)
#define ENGINE_SAMPLE ")soundscape/emitters/loop/car_engine_loop_01.wav"
#define VEHICLE_HORN_SAMPLE ")botmassacre/vehicles/horn_01.wav"
#define VEHICLE_HORN_COOLDOWN 5.0 // Seconds between horn activations per player.
#define VEHICLE_HORN_SOUND_LEVEL 100 // Higher carries farther; sample volume is normalized separately.
#define VEHICLE_HORN_VOLUME 1.0
#define VEHICLE_ENGINE_IDLE_PITCH 90 // Idle pitch; 100 is the sample's original pitch.
#define VEHICLE_ENGINE_MAX_PITCH 135 // Pitch at full driving speed and throttle.
#define VEHICLE_ENGINE_SOUND_LEVEL 85 // Engine sound attenuation level in dB; higher carries farther.
#define VEHICLE_ENGINE_IDLE_VOLUME 0.85 // Loop volume at idle, from 0.0 to 1.0.
#define VEHICLE_ENGINE_MAX_VOLUME 1.0 // Loop volume at full load, from 0.0 to 1.0.
#define VEHICLE_FIRE_SAMPLE ")weapons/vehicleexplode/vehicle_fire_loop.wav"
#define VEHICLE_FIRE_SOUND_LEVEL 85 // Fire sound attenuation level in dB.
#define VEHICLE_WRECK_FIRE_VOLUME 0.85 // Burning wreck volume until effect cleanup.
#define VEHICLE_EXPLOSION_SOUND_LEVEL 110 // Explosion attenuation level in dB.
#define VEHICLE_EXPLOSION_VOLUME 1.0 // One explosion sound per destruction.
#define VEHICLE_EXPLOSION_DEATH_NAME "Vehicle Explosion" // Death-message label for this plugin's blast kills.
#define VEHICLE_EXPLOSION_RADIUS 450.0 // Blast radius in Source units; walls and solid props block damage.
#define VEHICLE_EXPLOSION_DAMAGE 200.0 // Maximum blast damage, falling linearly to zero at the radius.
#define EF_NODRAW 32
#define VEHICLE_HUD_BITS 1025

#define BTN_ATTACK1         (1 << 0)
#define BTN_JUMP            (1 << 1)
#define BTN_FORWARD         (1 << 4)
#define BTN_BACKWARD        (1 << 5)
#define BTN_USE             (1 << 6)
#define BTN_LEFT            (1 << 9)
#define BTN_RIGHT           (1 << 10)
#define BTN_RELOAD          (1 << 11)
#define BTN_DUCK            (1 << 2)
#define BTN_PRONE           (1 << 3)
#define BTN_TURN_LEFT       (1 << 7)
#define BTN_TURN_RIGHT      (1 << 8)
#define BTN_LEAN_LEFT       (1 << 13)
#define BTN_LEAN_RIGHT      (1 << 14)
#define BTN_SPRINT          (1 << 15)
#define BTN_WALK            (1 << 16)
#define BTN_SPECIAL1        (1 << 17)
#define BTN_DUCK_TOGGLE     (1 << 24)
#define BTN_SPRINT_TOGGLE   (1 << 26)
#define BTN_STANCE_TOGGLE   (1 << 29)
#define ATV_PASSENGER_BLOCKED_BUTTONS (BTN_JUMP | BTN_DUCK | BTN_PRONE | BTN_FORWARD | BTN_BACKWARD | BTN_USE \
	| BTN_TURN_LEFT | BTN_TURN_RIGHT | BTN_LEFT | BTN_RIGHT | BTN_LEAN_LEFT | BTN_LEAN_RIGHT | BTN_SPRINT | BTN_WALK \
	| BTN_SPECIAL1 | BTN_DUCK_TOGGLE | BTN_SPRINT_TOGGLE | BTN_STANCE_TOGGLE)


#define PASSENGER_RIG_MODEL "models/botmassacre/humvee_passenger_v3/bm_passenger_ranger.mdl"
#define MAX_VEHICLES 16
#define SEATS 4
#define PF_WEAPON_RESTRICTED (1 << 10)

// Dashboard refresh interval and mph conversion (one world unit treated as one inch).
#define VEHICLE_DASH_UPDATE_INTERVAL 0.1
#define VEHICLE_UNITS_TO_MPH (3600.0 / 63360.0)

#define VEHICLE_GROUND_TILT_RATE 180.0 // Degrees per second when following ramp surfaces.
#define VEHICLE_EXIT_DROP 320.0 // Search distance below the vehicle for a safe exit landing.
#define VEHICLE_HUMVEE 0
#define VEHICLE_ATV 1
#define VEHICLE_TYPES 2
#define ATV_MODEL "models/botmassacre/atv_v4/bm_atv.mdl"
#define ATV_RIDER_MODEL "models/botmassacre/atv_rider_v3/bm_atv_ranger.mdl"
#define ATV_PASSENGER_ANIM_MODEL "models/botmassacre/atv_passenger_v2/animations_player_%c.mdl"
#define ATV_PASSENGER_YAW 80.0
#define ATV_PASSENGER_REAR -34.0
#define ATV_PASSENGER_HEIGHT 10.0
#define ATV_HEALTH 10000.0 // Exposed rider receives normal damage; this HP belongs to the ATV only.
#define ATV_FORWARD_SPEED 500.0 // Source units per second.
#define ATV_REVERSE_SPEED 110.0
#define ATV_ACCELERATION 220.0 // Source units per second squared.
#define ATV_COAST_DECELERATION 150.0
#define ATV_BRAKE_DECELERATION 600.0
#define ATV_TURN_RATE 100.0 // Degrees per second at full steering and sufficient speed.
#define ATV_STEERING_RESPONSE 6.0 // Steering pose change per second.
#define ATV_STEP_HEIGHT 32.0 // Maximum curb height, in Source units.
#define ATV_SUSPENSION_TRAVEL 32.0 // Ground-height variation allowed while the chassis tilts.
#define ATV_WHEEL_TRAVEL 6.0 // Actual extension authored into the wheel pose; keep matched to the model.
#define ATV_MIN_GROUND_Z 0.707107 // cos(degrees * PI / 180); degrees = acos(value) * 180 / PI. 45 degrees.
#define ATV_EXPLOSION_RADIUS 350.0
#define ATV_EXPLOSION_DAMAGE 170.0

enum struct VehicleProfile {
	int Seats;
	float Health;
	float ForwardSpeed;
	float ReverseSpeed;
	float Acceleration;
	float Coast;
	float Brake;
	float TurnRate;
	float SteeringResponse;
	float StepHeight;
	float Suspension;
	float WheelTravel;
	float GroundZ;
	float WheelRadius;
	float ChaseDistance;
	float HalfWidth;
	float HalfLength;
	float Height;
	float PlaceDistance;
	float ExplosionRadius;
	float ExplosionDamage;
	int EngineIdlePitch;
	int EngineMaxPitch;
	bool Ready;
}

VehicleProfile g_Types[VEHICLE_TYPES];
char g_TypeNames[VEHICLE_TYPES][16] = {"Humvee", "ATV"};
char g_TypeKeys[VEHICLE_TYPES][16] = {"humvee", "atv"};
char g_TypeModels[VEHICLE_TYPES][128] = {VEHICLE_MODEL, ATV_MODEL};
bool g_ATVRiderReady;
bool g_ATVPassengerReady[3];
char g_ATVPassengerModels[3][PLATFORM_MAX_PATH] = {
	"models/botmassacre/atv_passenger_v2/ranger.mdl",
	"models/botmassacre/atv_passenger_v2/ranger_des.mdl",
	"models/botmassacre/atv_passenger_v2/ranger_shad.mdl"
};

void InitVehicleProfiles() {
	g_Types[VEHICLE_HUMVEE].Seats = 4;
	g_Types[VEHICLE_HUMVEE].Health = VEHICLE_HEALTH;
	g_Types[VEHICLE_HUMVEE].ForwardSpeed = VEHICLE_FORWARD_SPEED;
	g_Types[VEHICLE_HUMVEE].ReverseSpeed = VEHICLE_REVERSE_SPEED;
	g_Types[VEHICLE_HUMVEE].Acceleration = VEHICLE_ACCELERATION;
	g_Types[VEHICLE_HUMVEE].Coast = VEHICLE_COAST_DECELERATION;
	g_Types[VEHICLE_HUMVEE].Brake = VEHICLE_BRAKE_DECELERATION;
	g_Types[VEHICLE_HUMVEE].TurnRate = 70.0;
	g_Types[VEHICLE_HUMVEE].SteeringResponse = 4.0;
	g_Types[VEHICLE_HUMVEE].StepHeight = VEHICLE_STEP_HEIGHT;
	g_Types[VEHICLE_HUMVEE].Suspension = VEHICLE_SUSPENSION_TRAVEL;
	g_Types[VEHICLE_HUMVEE].WheelTravel = VEHICLE_SUSPENSION_TRAVEL;
	g_Types[VEHICLE_HUMVEE].GroundZ = VEHICLE_MIN_GROUND_Z;
	g_Types[VEHICLE_HUMVEE].WheelRadius = 19.93;
	g_Types[VEHICLE_HUMVEE].ChaseDistance = 210.0;
	g_Types[VEHICLE_HUMVEE].HalfWidth = 62.0;
	g_Types[VEHICLE_HUMVEE].HalfLength = 113.0;
	g_Types[VEHICLE_HUMVEE].Height = 88.0;
	g_Types[VEHICLE_HUMVEE].PlaceDistance = 210.0;
	g_Types[VEHICLE_HUMVEE].ExplosionRadius = VEHICLE_EXPLOSION_RADIUS;
	g_Types[VEHICLE_HUMVEE].ExplosionDamage = VEHICLE_EXPLOSION_DAMAGE;
	g_Types[VEHICLE_HUMVEE].EngineIdlePitch = VEHICLE_ENGINE_IDLE_PITCH;
	g_Types[VEHICLE_HUMVEE].EngineMaxPitch = VEHICLE_ENGINE_MAX_PITCH;
	g_Types[VEHICLE_ATV] = g_Types[VEHICLE_HUMVEE];
	g_Types[VEHICLE_ATV].Seats = 2;
	g_Types[VEHICLE_ATV].Health = ATV_HEALTH;
	g_Types[VEHICLE_ATV].ForwardSpeed = ATV_FORWARD_SPEED;
	g_Types[VEHICLE_ATV].ReverseSpeed = ATV_REVERSE_SPEED;
	g_Types[VEHICLE_ATV].Acceleration = ATV_ACCELERATION;
	g_Types[VEHICLE_ATV].Coast = ATV_COAST_DECELERATION;
	g_Types[VEHICLE_ATV].Brake = ATV_BRAKE_DECELERATION;
	g_Types[VEHICLE_ATV].TurnRate = ATV_TURN_RATE;
	g_Types[VEHICLE_ATV].SteeringResponse = ATV_STEERING_RESPONSE;
	g_Types[VEHICLE_ATV].StepHeight = ATV_STEP_HEIGHT;
	g_Types[VEHICLE_ATV].Suspension = ATV_SUSPENSION_TRAVEL;
	g_Types[VEHICLE_ATV].WheelTravel = ATV_WHEEL_TRAVEL;
	g_Types[VEHICLE_ATV].GroundZ = ATV_MIN_GROUND_Z;
	g_Types[VEHICLE_ATV].WheelRadius = 13.2;
	g_Types[VEHICLE_ATV].ChaseDistance = 145.0;
	g_Types[VEHICLE_ATV].HalfWidth = 30.0;
	g_Types[VEHICLE_ATV].HalfLength = 49.0;
	g_Types[VEHICLE_ATV].Height = 49.0;
	g_Types[VEHICLE_ATV].PlaceDistance = 125.0;
	g_Types[VEHICLE_ATV].ExplosionRadius = ATV_EXPLOSION_RADIUS;
	g_Types[VEHICLE_ATV].ExplosionDamage = ATV_EXPLOSION_DAMAGE;
	g_Types[VEHICLE_ATV].EngineIdlePitch = 105;
	g_Types[VEHICLE_ATV].EngineMaxPitch = 155;
}

void WheelLocal(int type, int wheel, float local[3]) {
	local[0] = type == VEHICLE_ATV ? (wheel % 2 ? 22.0 : -22.0) : (wheel % 2 ? 40.79 : -41.74);
	local[1] = type == VEHICLE_ATV ? (wheel < 2 ? 26.0 : -26.0) : (wheel < 2 ? 76.93 : -71.84);
	local[2] = 0.0;
}
public Plugin myinfo = {
	name = "BM Vehicles",
	author = "Nullifidian, GPT/Codex",
	description = "Humvees and two-seat ATVs with armed rear passengers, admin placement and per-map saved vehicles.",
	version = PLUGIN_VERSION,
	url = ""
};

enum struct VehicleState {
	int Type;
	int VehicleRef;
	int SavedId;
	int Occupants[SEATS];
	int DriveButtons;
	int LastBlockEntity;
	int GroundBlocks;
	int HullBlocks;
	int BodyTraces;
	bool Airborne;
	float FlightVelocity[3];
	float GroundNormal[3];
	float NextRampRecovery;
	float NextSupportCheck;
	int SupportMask;
	int SupportCount;
	int Jumps;
	int Landings;
	int RampRecoveries;
	float Speed;
	float StepDistance;
	float DisplayDistance;
	float DisplayElapsed;
	int DisplayMPH;
	float GaugeSpeed;
	float GaugeRPM;
	float Health;
	float NextImpact[MAXPLAYERS + 1];
	int ImpactUserId[MAXPLAYERS + 1];
	int ImpactContacts;
	int ImpactPushes;
	int PushSteps;
	bool BrakeLights;
	int VisualSkin;
	int DamageEffectStage;
	int DamageEffectRef;
	Handle DamageEffectTimer;
	bool Destroyed;
	bool ExplosionApplied;
	bool WreckHidden;
	bool WreckHadPhysics;
	bool WreckPhysicsRemoved;
	int DebrisRefs[VEHICLE_DEBRIS_PARTS];
	Handle DebrisTimer;
	int DebrisSpawned;
	int DebrisBlocked;
	int DebrisFailed;
	int DebrisLaunched;
	int DebrisMoved;
	float DebrisTravel;
	int DebrisFlightBlocked;
	float WheelCycle;
	float LastMove;
	float Steering;
	float LastStepTime;
	int ReplayedDriveCmds;
	int SteerOverrides;
	int AnimationRepairs;
	int AnimTimeOffset;
	int CurbSteps;
	int LastTurnButtons;
	float LastTurnTime;
	char LastBlockReason[64];
	int BlockedMoves;
	bool EngineSound;
	int EnginePitch;
	float EngineVolume;
	bool FireSound;
}

enum struct RiderState {
	int Vehicle;
	int Seat;
	int UserId;
	int CameraRef;
	bool ChaseView;
	bool SavedDrawViewmodel;
	int DriverAnimTimeOffset;
	float HeadYaw;
	float HeadPitch;
	float LookYaw;
	float LookPitch;
	float LastInputYaw;
	int DisplayRef;
	int DriverRigRef;
	bool SeatedPose;
	float EnteredAt;
	float EntryOrigin[3];
	float EntryAngles[3];
	MoveType SavedMoveType;
	int SavedHud;
	int SavedNoDraw;
	int SavedWeaponRef;
	int SavedWeaponNoDraw;
	bool Changing;
	int LastDriveCmd;
	bool WeaponLockApplied;
	bool ArmorApplied;
	int SavedTakeDamage;
	bool WasWeaponRestricted;
	bool PassengerModelApplied;
	bool PassengerMotionApplied;
	bool SoloDrive;
	float SoloDriveEnds;
	float SoloDriveInputTime;
	int PassengerSupportRef;
	int PassengerCollisionVehicleRef;
	int PassengerSavedVehicleOwnerRef;
	int PassengerWeaponRef;
	int PassengerWeaponNoDraw;
	int AimTestStep;
	int AimTestWeaponRef;
	Handle AimTestTimer;
	float AimTestOrigin[3];
	float AimTestOutside[3];
	char SavedModel[PLATFORM_MAX_PATH];
	int SavedSkin;
	int SavedBody;
}

enum struct Placement {
	int Type;
	int Id;
	float Origin[3];
	float Yaw;
}

VehicleState g_V[MAX_VEHICLES];
ConVar g_VehicleGravity;
RiderState g_R[MAXPLAYERS + 1];
enum struct PlayerPushState {
	bool Hooked;
	bool Applied;
	int VehicleRef;
	float EndsAt;
	float Strength;
	float Direction[3];
	float Previous[3];
	float Written[3];
}

PlayerPushState g_Push[MAXPLAYERS + 1];
Placement g_Saved[MAX_VEHICLES];
int g_SavedCount;
int g_NextSavedId = 1;
int g_Count;
int g_MapSerial;
int g_LastButtons[MAXPLAYERS + 1];
float g_NextUse[MAXPLAYERS + 1];
float g_NextHorn[MAXPLAYERS + 1];

bool g_DriverRigReady;
bool g_PassengerRigReady;
bool g_SoundReady;
bool g_HornSoundReady;
bool g_DamageEffectsReady;
bool g_WreckReady;
bool g_DebrisReady[VEHICLE_DEBRIS_PARTS];
int g_DebrisEntityRefs[2049];
char g_DebrisModels[VEHICLE_DEBRIS_PARTS][PLATFORM_MAX_PATH] = {
	"models/botmassacre/humvee_wreck_v1/wheel_fl.mdl",
	"models/botmassacre/humvee_wreck_v1/wheel_fr.mdl",
	"models/botmassacre/humvee_wreck_v1/wheel_rl.mdl",
	"models/botmassacre/humvee_wreck_v1/wheel_rr.mdl",
	"models/botmassacre/humvee_wreck_v1/hood.mdl",
	"models/botmassacre/humvee_wreck_v1/door_left.mdl",
	"models/botmassacre/humvee_wreck_v1/door_right.mdl"
};
float g_DebrisCenters[VEHICLE_DEBRIS_PARTS][3] = {
	{-41.7397, 76.9355, 20.0754}, {40.7914, 76.9305, 20.0731},
	{-41.7397, -71.8335, 20.8133}, {40.7914, -71.8334, 20.8133},
	{0.0, 77.7040, 53.7253}, {-51.2125, 30.5, 54.9}, {50.7135, 30.5, 54.9}
};
char g_DamageEffects[3][32] = {"smoke_burning_engine_01", "burning_engine_01", "ins_car_explosion"};
bool g_EndingMap;
bool g_ConfigReady;
char g_ConfigPath[PLATFORM_MAX_PATH];
char g_PlacementReason[128];
Handle g_Watch;
TopMenu g_AdminMenu;
ArrayList g_SecuritySpawns;
char g_SeatNames[SEATS][24] = {"Driver", "Front passenger", "Rear left", "Rear right"};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax) {
	MarkNativeAsOptional("ThirdPerson_IsClientActive");
	return APLRes_Success;
}

public void OnPluginStart() {
	if (GetEngineVersion() != Engine_Insurgency)
		SetFailState("BM Vehicles is for Insurgency 2014 only.");
	InitVehicleProfiles();
	PrepareWreckPhysics();
	PreparePassengerDisplay();
	for (int v = 0; v < MAX_VEHICLES; v++)
		ResetVehicle(v);
	for (int client = 1; client <= MaxClients; client++)
		ResetRider(client);
	RegAdminCmd("sm_atvpassengerdrive", Command_PassengerDrive, ADMFLAG_ROOT, "Toggle a 60-second solo rear-seat driving test");
	RegAdminCmd("sm_atvaimcontrol", Command_AimControl, ADMFLAG_ROOT, "Run or cancel an on-foot ADS ground-contact control test");
	RegAdminCmd("sm_atvaimtest", Command_PassengerAimTest, ADMFLAG_ROOT, "Compare passenger position, display entities and native view setup");
	RegAdminCmd("sm_atvpassengerstatus", Command_PassengerStatus, ADMFLAG_ROOT, "Show seated passenger velocity and animation state");
	RegAdminCmd("sm_vehicles", Command_AdminVehicles, ADMFLAG_ROOT, "Vehicle administration menu");
	HookEvent("player_death", Event_VehicleDeath, EventHookMode_Pre);
	HookEvent("player_team", Event_RiderLeave, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void OnAllPluginsLoaded() {
	if (LibraryExists("adminmenu")) {
		TopMenu menu = GetAdminTopMenu();
		if (menu != null)
			OnAdminMenuReady(menu);
	}
}

public void OnAdminMenuReady(Handle handle) {
	TopMenu menu = TopMenu.FromHandle(handle);
	if (menu == g_AdminMenu)
		return;
	g_AdminMenu = menu;
	TopMenuObject category = menu.FindCategory(ADMINMENU_SERVERCOMMANDS);
	if (category != INVALID_TOPMENUOBJECT)
		menu.AddItem("bm_vehicles", AdminTopHandler, category, "sm_vehicles", ADMFLAG_RCON);
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "adminmenu"))
		g_AdminMenu = null;
}

public void AdminTopHandler(TopMenu menu, TopMenuAction action, TopMenuObject objectId, int param, char[] buffer, int length) {
	if (action == TopMenuAction_DisplayOption)
		strcopy(buffer, length, "Vehicles");
	else if (action == TopMenuAction_SelectOption && IsVehicleAdmin(param))
		ShowAdminMenu(param);
}

public void OnMapStart() {
	for (int client = 1; client <= MaxClients; client++)
		g_NextHorn[client] = 0.0;
	delete g_SecuritySpawns;
	g_EndingMap = false;
	g_MapSerial++;
	for (int type = 0; type < VEHICLE_TYPES; type++) {
		g_Types[type].Ready = FileExists(g_TypeModels[type], true) && PrecacheModel(g_TypeModels[type], true) > 0;
		if (!g_Types[type].Ready)
			LogError("%s model unavailable: %s", g_TypeNames[type], g_TypeModels[type]);
	}
	g_ATVRiderReady = FileExists(ATV_RIDER_MODEL, true) && PrecacheModel(ATV_RIDER_MODEL, true) > 0;
	bool passengerAnimReady = true;
	for (int animation = 0; animation < 5; animation++) {
		char model[PLATFORM_MAX_PATH], data[PLATFORM_MAX_PATH];
		Format(model, sizeof(model), ATV_PASSENGER_ANIM_MODEL, 'a' + animation);
		strcopy(data, sizeof(data), model);
		ReplaceString(data, sizeof(data), ".mdl", ".ani");
		if (!FileExists(model, true) || !FileExists(data, true) || PrecacheModel(model, true) <= 0) {
			passengerAnimReady = false;
			LogError("ATV passenger animation unavailable: %s / %s", model, data);
		}
	}
	for (int modelIndex = 0; modelIndex < sizeof(g_ATVPassengerModels); modelIndex++)
		g_ATVPassengerReady[modelIndex] = passengerAnimReady && FileExists(g_ATVPassengerModels[modelIndex], true) && PrecacheModel(g_ATVPassengerModels[modelIndex], true) > 0;
	g_DriverRigReady = FileExists(DRIVER_RIG_MODEL, true) && PrecacheModel(DRIVER_RIG_MODEL, true) > 0;
	g_PassengerRigReady = FileExists(PASSENGER_RIG_MODEL, true) && PrecacheModel(PASSENGER_RIG_MODEL, true) > 0;
	PrepareVehicleSounds();
	if (!g_ATVRiderReady)
		LogError("ATV rider rig unavailable; ATV entry disabled until the full package is installed.");
	PrepareVehicleDamageEffects();
	PrepareVehicleWrecks();
	LoadPlacements();
}

public void OnConfigsExecuted() {
	// Late loads and maps without a round_start event still get their saved vehicles.
	SpawnSavedPlacements();
}

public void OnMapEnd() {
	for (int client = 1; client <= MaxClients; client++)
		StopAimControl(client);
	ClearVehicles();
	delete g_SecuritySpawns;
	g_EndingMap = true;
	g_ConfigReady = false;
	for (int type = 0; type < VEHICLE_TYPES; type++)
		g_Types[type].Ready = false;
	g_ATVRiderReady = false;
	for (int modelIndex = 0; modelIndex < sizeof(g_ATVPassengerReady); modelIndex++)
		g_ATVPassengerReady[modelIndex] = false;
	g_DamageEffectsReady = false;
	g_MapSerial++;
	delete g_Watch;
}

public void OnPluginEnd() {
	for (int client = 1; client <= MaxClients; client++)
		StopAimControl(client);
	ClearVehicles();
	delete g_SecuritySpawns;
}

public void OnClientPutInServer(int client) {
	ResetRider(client);
	g_LastButtons[client] = 0;
	g_NextUse[client] = 0.0;
	g_NextHorn[client] = 0.0;
}

public void OnClientDisconnect(int client) {
	StopAimControl(client);
	StopPlayerPush(client);
	ExitRider(client, true);
	ResetRider(client);
}

int g_ExplosionVictimUserId;
int g_ImpactVictimUserId;
int g_ImpactAttackerUserId;
int g_ImpactVehicleType = -1;

public Action Event_VehicleDeath(Event event, const char[] name, bool dontBroadcast) {
	int userId = event.GetInt("userid");
	bool blast = userId > 0 && userId == g_ExplosionVictimUserId
		&& event.GetInt("attacker") == 0 && (event.GetInt("damagebits") & DMG_BLAST) != 0;
	if (blast) {
		g_ExplosionVictimUserId = 0;
		event.SetString("weapon", VEHICLE_EXPLOSION_DEATH_NAME);
	}
	bool impact = userId > 0 && userId == g_ImpactVictimUserId
		&& event.GetInt("attacker") == g_ImpactAttackerUserId && (event.GetInt("damagebits") & DMG_VEHICLE) != 0
		&& g_ImpactVehicleType >= 0 && g_ImpactVehicleType < VEHICLE_TYPES;
	if (impact) {
		g_ImpactVictimUserId = 0;
		event.SetString("weapon", g_TypeNames[g_ImpactVehicleType]);
	}
	Event_RiderLeave(event, name, dontBroadcast);
	return blast || impact ? Plugin_Changed : Plugin_Continue;
}

public void Event_RiderLeave(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0) {
		StopAimControl(client);
		StopPlayerPush(client);
		ExitRider(client, true);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for (int client = 1; client <= MaxClients; client++)
		StopAimControl(client);
	ClearVehicles();
	RequestFrame(Frame_SpawnSaved, g_MapSerial);
}

public void Frame_SpawnSaved(any serial) {
	if (!g_EndingMap && serial == g_MapSerial)
		SpawnSavedPlacements();
}

void ResetVehicle(int v) {
	VehicleState blank;
	g_V[v] = blank;
	g_V[v].VehicleRef = INVALID_ENT_REFERENCE;
	g_V[v].VisualSkin = -1;
	g_V[v].DamageEffectRef = INVALID_ENT_REFERENCE;
	for (int i = 0; i < VEHICLE_DEBRIS_PARTS; i++)
		g_V[v].DebrisRefs[i] = INVALID_ENT_REFERENCE;
	g_V[v].AnimTimeOffset = -1;
	g_V[v].LastBlockEntity = -1;
}

void ResetRider(int client) {
	RiderState blank;
	g_R[client] = blank;
	g_R[client].Vehicle = -1;
	g_R[client].AimTestStep = -1;
	g_R[client].CameraRef = INVALID_ENT_REFERENCE;
	g_R[client].DisplayRef = INVALID_ENT_REFERENCE;
	g_R[client].DriverRigRef = INVALID_ENT_REFERENCE;
	g_R[client].SavedWeaponRef = INVALID_ENT_REFERENCE;
	g_R[client].PassengerWeaponRef = INVALID_ENT_REFERENCE;
	g_R[client].PassengerSupportRef = INVALID_ENT_REFERENCE;
	g_R[client].PassengerCollisionVehicleRef = INVALID_ENT_REFERENCE;
	g_R[client].PassengerSavedVehicleOwnerRef = INVALID_ENT_REFERENCE;
	g_R[client].DriverAnimTimeOffset = -1;
}

int Vehicle(int v) {
	if (v < 0 || v >= MAX_VEHICLES)
		return -1;
	int entity = EntRefToEntIndex(g_V[v].VehicleRef);
	return entity > MaxClients && IsValidEntity(entity) ? entity : -1;
}

int VehicleByRef(int reference) {
	if (reference == INVALID_ENT_REFERENCE)
		return -1;
	for (int v = 0; v < MAX_VEHICLES; v++) {
		if (g_V[v].VehicleRef == reference)
			return v;
	}
	return -1;
}

int RiderInSeat(int v, int seat) {
	int client = GetClientOfUserId(g_V[v].Occupants[seat]);
	return client > 0 && g_R[client].Vehicle == v && g_R[client].Seat == seat ? client : 0;
}

int DrivingClient(int v) {
	int driver = RiderInSeat(v, 0);
	if (driver != 0 || !IsATV(v))
		return driver;
	int passenger = RiderInSeat(v, 1);
	return passenger > 0 && g_R[passenger].SoloDrive ? passenger : 0;
}

void StopPassengerDrive(int client) {
	if (!g_R[client].SoloDrive)
		return;
	g_R[client].SoloDrive = false;
	int v = g_R[client].Vehicle;
	if (v != -1 && Vehicle(v) != -1 && RiderInSeat(v, 0) == 0)
		StopEngine(v);
}

public Action Command_PassengerDrive(int client, int args) {
	if (!HumanAlive(client) || !ArmedATVPassenger(client)) {
		ReplyToCommand(client, "[Vehicles] Run this while sitting in the ATV rear passenger seat.");
		return Plugin_Handled;
	}
	if (g_R[client].SoloDrive) {
		StopPassengerDrive(client);
		ReplyToCommand(client, "[Vehicles] Solo driving test stopped.");
		return Plugin_Handled;
	}
	int v = g_R[client].Vehicle;
	int vehicle = Vehicle(v);
	if (vehicle == -1 || g_V[v].Destroyed || g_V[v].Health <= 0.0 || g_V[v].Airborne
		|| FloatAbs(g_V[v].Speed) > 0.1 || RiderInSeat(v, 0) != 0 || g_R[client].Changing) {
		ReplyToCommand(client, "[Vehicles] Use a stopped, working ATV with an empty driver seat.");
		return Plugin_Handled;
	}
	StopPassengerAimTest(client);
	if (!ArmedATVPassenger(client))
		return Plugin_Handled;
	g_R[client].SoloDrive = true;
	g_R[client].SoloDriveEnds = GetGameTime() + 60.0;
	g_R[client].SoloDriveInputTime = GetGameTime();
	g_V[v].DriveButtons = 0;
	g_V[v].LastMove = GetGameTime();
	StartVehicleEngineSound(v, vehicle);
	ReplyToCommand(client, "[Vehicles] Solo driving test: WASD drives the ATV, Space brakes; aim and fire normally. Speed capped at 120 units/s. Stops after 60 seconds, on exit, or by repeating sm_atvpassengerdrive.");
	return Plugin_Handled;
}

bool Occupied(int v) {
	for (int s = 0; s < VehicleSeats(v); s++) {
		if (g_V[v].Occupants[s] != 0)
			return true;
	}
	return false;
}

void SeatLocal(int v, int seat, float local[3], int kind = 0) {
	if (IsATV(v)) {
		if (seat == 1) {
			local[0] = 0.0;
			local[1] = kind == 3 ? -52.0 : ATV_PASSENGER_REAR;
			local[2] = kind == 3 ? 48.0 : (kind == 2 ? 76.0 : ATV_PASSENGER_HEIGHT);
			return;
		}
		local[0] = 0.0;
		local[1] = kind == 0 ? 0.0 : -12.0;
		local[2] = kind == 0 ? 0.0 : (kind == 2 ? 70.0 : (kind == 3 ? 35.0 : 4.0));
		return;
	}
	local[0] = seat % 2 ? 28.0 : -28.0;
	local[1] = seat < 2 ? 13.0 : -23.0;
	local[2] = 9.0;
	if (kind == 1) {
		local[1] -= 7.0;
		local[2] += 13.0;
	} else if (kind == 2) {
		local[1] -= 5.0;
		local[2] += 57.0;
	} else if (kind == 3) {
		local[0] = seat % 2 ? 60.0 : -60.0;
		local[2] = 44.0;
	}
}

void CameraLocal(int client, float local[3]) {
	if (!IsATV(g_R[client].Vehicle) && !g_R[client].ChaseView) {
		SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local);
		local[1] = g_R[client].Seat < 2 ? HUMVEE_CAMERA_FRONT : HUMVEE_CAMERA_REAR;
		local[2] = HUMVEE_CAMERA_HEIGHT;
		// Keep the eye aligned with the window instead of orbiting behind the frame.
		local[0] -= HUMVEE_CAMERA_LEAN * Sine(DegToRad(g_R[client].LookYaw));
		return;
	}
	if (!g_R[client].SeatedPose) {
		SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local, 2);
		return;
	}
	SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local);
	if (IsATV(g_R[client].Vehicle)) {
		ATVCameraLocal(client, local);
		return;
	}
	// Ranger head envelope: rotate its center with the pose, then look from outside it.
	float headYaw = DegToRad(g_R[client].HeadYaw);
	float headPitch = DegToRad(g_R[client].HeadPitch);
	float centerY = 0.30 * Cosine(headPitch) + 4.15 * Sine(headPitch);
	local[0] += -0.23 * Cosine(headYaw) - centerY * Sine(headYaw);
	local[1] += -14.69 - 0.23 * Sine(headYaw) + centerY * Cosine(headYaw);
	local[2] += 59.72 - 0.30 * Sine(headPitch) + 4.15 * Cosine(headPitch);
	local[2] = FloatMax(local[2] + 2.0, 74.0);
	float yaw = DegToRad(g_R[client].LookYaw);
	local[0] -= 12.0 * Sine(yaw);
	local[1] += 12.0 * Cosine(yaw);
}

public bool FilterVehicle(int entity, int contentsMask, any v) {
	if (IsVehicleDebris(entity))
		return false;
	if (entity == Vehicle(v))
		return false;
	for (int s = 0; s < VehicleSeats(v); s++) {
		int client = RiderInSeat(v, s);
		if (client == 0)
			continue;
		if (entity == client || entity == EntRefToEntIndex(g_R[client].DisplayRef)
			|| entity == EntRefToEntIndex(g_R[client].CameraRef) || entity == EntRefToEntIndex(g_R[client].DriverRigRef)
			|| entity == EntRefToEntIndex(g_R[client].PassengerSupportRef))
			return false;
	}
	return true;
}

bool AttachedToVehicle(int entity, int vehicle) {
	for (int remaining = GetMaxEntities(); remaining > 0 && entity > 0 && IsValidEntity(entity); remaining--) {
		if (entity == vehicle)
			return true;
		if (!HasEntProp(entity, Prop_Data, "m_hMoveParent"))
			return false;
		entity = GetEntPropEnt(entity, Prop_Data, "m_hMoveParent");
	}
	return false;
}

public bool FilterDriving(int entity, int contentsMask, any v) {
	if (entity > 0 && entity <= MaxClients)
		return false;
	if (!FilterVehicle(entity, contentsMask, v))
		return false;
	if (entity <= MaxClients || !IsValidEntity(entity))
		return true;
	// Attached explosives must not become obstacles or supporting ground for their own vehicle.
	if (AttachedToVehicle(entity, Vehicle(v)))
		return false;
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	if (StrEqual(classname, "prop_ragdoll")) {
		char targetname[64];
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		// Medic bodies must not obstruct driving or act as wheel support.
		if (StrContains(targetname, "playervital_ragdoll_", false) == 0)
			return false;
	}
	if (StrContains(classname, "weapon_") != 0 || !HasEntProp(entity, Prop_Send, "m_hOwnerEntity"))
		return true;
	return GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") != -1
		|| GetEntPropEnt(entity, Prop_Data, "m_hMoveParent") != -1;
}

public bool FilterEntry(int entity, int contentsMask, any data) {
	int client = data & 255;
	int v = data >> 8;
	return entity != client && FilterVehicle(entity, contentsMask, v);
}

bool EntryReachable(int client, int v, int seat, float &distance) {
	float eye[3], origin[3], angles[3], local[3], door[3];
	int vehicle = Vehicle(v);
	GetClientEyePosition(client, eye);
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	SeatLocal(v, seat, local, 3);
	VehiclePoint(origin, angles, local, door);
	distance = GetVectorDistance(eye, door, true);
	if (distance > 10000.0)
		return false;
	Handle trace = TR_TraceRayFilterEx(eye, door, MASK_SOLID, RayType_EndPoint, FilterEntry, (v << 8) | client);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	delete trace;
	return clear;
}

void EnterNearestSeat(int client, bool quiet = false) {
	if (!HumanAlive(client) || g_R[client].Vehicle != -1)
		return;
	int bestV = -1, bestSeat = -1;
	float best = 10001.0;
	for (int v = 0; v < MAX_VEHICLES; v++) {
		if (Vehicle(v) == -1 || g_V[v].Health <= 0.0 || FloatAbs(g_V[v].Speed) > 40.0)
			continue;
		for (int s = 0; s < VehicleSeats(v); s++) {
			float distance;
			if (g_V[v].Occupants[s] == 0 && EntryReachable(client, v, s, distance) && distance < best) {
				best = distance;
				bestV = v;
				bestSeat = s;
			}
		}
	}
	if (bestV != -1)
		EnterSeat(client, bestV, bestSeat);
	else if (!quiet)
		PrintToChat(client, "[Vehicles] Approach an available seat of a stopped, working vehicle.");
}

bool EnterSeat(int client, int v, int seat) {
	StopAimControl(client);
	int vehicle = Vehicle(v);
	if (vehicle == -1 || !HumanAlive(client) || g_R[client].Vehicle != -1 || g_R[client].Changing)
		return false;
	if (seat < 0 || seat >= VehicleSeats(v))
		return false;
	bool armedPassenger = IsATV(v) && seat == 1;
	int passengerVariant = -1;
	if (IsATV(v)) {
		char model[PLATFORM_MAX_PATH];
		GetClientModel(client, model, sizeof(model));
		passengerVariant = ATVPassengerVariant(model);
		if (!SupportsSeatedDriver(model) || (!armedPassenger && !g_ATVRiderReady)
			|| (armedPassenger && (passengerVariant == -1 || !g_ATVPassengerReady[passengerVariant]))) {
			PrintToChat(client, "[Vehicles] ATV rider pose unavailable for your model. Supported: Ranger woodland, desert and shadow variants.");
			return false;
		}
		float origin[3], angles[3], fraction = 1.0, surface = -999999.0;
		GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
		GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
		if (!TraceATVRider(v, origin, origin, angles, angles, fraction, surface, false, seat)) {
			PrintToChat(client, "[Vehicles] Not enough clearance above the ATV for a rider.");
			return false;
		}
	}
	if (armedPassenger && (g_PassengerSetLayers == null || g_PassengerOverlayOffset <= 0)) {
		PrintToChat(client, "[Vehicles] Rear passenger display unavailable; check passenger gamedata.");
		return false;
	}
	if (armedPassenger && GetEntProp(client, Prop_Send, "m_iCurrentStance") != 0) {
		PrintToChat(client, "[Vehicles] Stand up before entering the rear passenger seat.");
		return false;
	}
	if (g_V[v].Health <= 0.0 || FloatAbs(g_V[v].Speed) > 40.0 || g_V[v].Occupants[seat] != 0)
		return false;
	float distance;
	if (!EntryReachable(client, v, seat, distance))
		return false;
	int view = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
	if ((GetEntityFlags(client) & FL_FROZEN) || (view > 0 && view != client)
		|| GetEntPropEnt(client, Prop_Send, "m_hVehicle") != -1
		|| GetEntPropEnt(client, Prop_Data, "m_hMoveParent") != -1 || GetEntityMoveType(client) != MOVETYPE_WALK) {
		PrintToChat(client, "[Vehicles] Return to normal walking and exit other cameras before entering.");
		return false;
	}
	if (GetEntityCount() + 4 >= GetMaxEntities() - 80) {
		PrintToChat(client, "[Vehicles] Not enough free entities for another passenger.");
		return false;
	}
	if (!HasEntProp(client, Prop_Send, "m_iPlayerFlags")) {
		PrintToChat(client, "[Vehicles] Weapon restriction is unavailable; entry cancelled.");
		return false;
	}
	if (seat == 0 && IsATV(v)) {
		int passenger = RiderInSeat(v, 1);
		if (passenger > 0)
			StopPassengerDrive(passenger);
	}
	StopPlayerPush(client);
	ResetRider(client);
	g_R[client].Vehicle = v;
	g_R[client].Seat = seat;
	g_R[client].UserId = GetClientUserId(client);
	g_V[v].Occupants[seat] = g_R[client].UserId;
	GetClientAbsOrigin(client, g_R[client].EntryOrigin);
	GetClientEyeAngles(client, g_R[client].EntryAngles);
	g_R[client].SavedMoveType = GetEntityMoveType(client);
	g_R[client].SavedHud = GetEntProp(client, Prop_Send, "m_iHideHUD");
	g_R[client].SavedNoDraw = GetEntProp(client, Prop_Send, "m_fEffects") & EF_NODRAW;
	g_R[client].SavedDrawViewmodel = GetEntProp(client, Prop_Send, "m_bDrawViewmodel") != 0;
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon > MaxClients) {
		g_R[client].SavedWeaponRef = EntIndexToEntRef(weapon);
		g_R[client].SavedWeaponNoDraw = GetEntProp(weapon, Prop_Send, "m_fEffects") & EF_NODRAW;
	}
	g_R[client].EnteredAt = GetGameTime();
	g_R[client].LastInputYaw = g_R[client].EntryAngles[1];
	g_NextUse[client] = GetGameTime() + 0.75;
	// Queue rollback before any helper or player-state native can fail.
	RequestFrame(Frame_VerifyEntry, g_R[client].UserId);
	if (armedPassenger) {
		GetClientModel(client, g_R[client].SavedModel, PLATFORM_MAX_PATH);
		g_R[client].SavedSkin = GetEntProp(client, Prop_Send, "m_nSkin");
		g_R[client].SavedBody = GetEntProp(client, Prop_Send, "m_nBody");
		g_R[client].PassengerModelApplied = true;
		SetEntityModel(client, g_ATVPassengerModels[passengerVariant]);
		SetEntProp(client, Prop_Send, "m_nSkin", g_R[client].SavedSkin);
		SetEntProp(client, Prop_Send, "m_nBody", g_R[client].SavedBody);
		SetEntityMoveType(client, MOVETYPE_NONE);
		g_R[client].PassengerMotionApplied = true;
		if (!CreatePassengerSupport(client, vehicle)) {
			ExitRider(client, true);
			PrintToChat(client, "[Vehicles] Rear passenger ground support unavailable; entry cancelled.");
			return false;
		}
		int owner = GetEntPropEnt(vehicle, Prop_Send, "m_hOwnerEntity");
		g_R[client].PassengerCollisionVehicleRef = EntIndexToEntRef(vehicle);
		g_R[client].PassengerSavedVehicleOwnerRef = owner == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(owner);
		// Native client/server traces skip owned entities; the support remains ownerless.
		SetEntPropEnt(vehicle, Prop_Send, "m_hOwnerEntity", client);
		FollowPassengerSeat(client, true);
		if (!SDKHookEx(client, SDKHook_PreThinkPost, Hook_PassengerMotion)
			|| !SDKHookEx(client, SDKHook_PostThink, Hook_PassengerAnimate)
			|| !SDKHookEx(client, SDKHook_PostThinkPost, Hook_PassengerPostThink)) {
			ExitRider(client, true);
			PrintToChat(client, "[Vehicles] Passenger movement setup failed; entry cancelled.");
			return false;
		}
		HoldPassengerMotion(client);
		if (!CreatePassengerDisplay(client, vehicle, passengerVariant)) {
			ExitRider(client, true);
			PrintToChat(client, "[Vehicles] Rear passenger display setup failed; entry cancelled.");
			return false;
		}
		g_R[client].LastInputYaw = PassengerRearYaw(client);
		g_V[v].LastMove = GetGameTime();
		PrintToChat(client, "[Vehicles] Rear passenger. Normal weapon controls | Mouse: aim behind and to either side | Use: exit.");
		return true;
	}
	if (!CreateDriverDisplay(client, vehicle) || !CreateCamera(client, vehicle) || !ApplySeatWeaponLock(client) || (!IsATV(v) && !ApplySeatArmor(client))) {
		ExitRider(client, true);
		PrintToChat(client, "[Vehicles] Seat display, camera, weapon restriction or armor protection failed; entry cancelled.");
		return false;
	}
	g_R[client].Changing = true;
	SetEntityMoveType(client, MOVETYPE_NONE);
	SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") | EF_NODRAW);
	SetEntProp(client, Prop_Send, "m_iHideHUD", g_R[client].SavedHud | VEHICLE_HUD_BITS);
	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
	if (weapon > MaxClients)
		SetEntProp(weapon, Prop_Send, "m_fEffects", GetEntProp(weapon, Prop_Send, "m_fEffects") | EF_NODRAW);
	float local[3];
	SeatLocal(v, seat, local, 1);
	ParentAtLocal(client, vehicle, local, 90.0);
	float inputAngles[3];
	GetClientEyeAngles(client, inputAngles);
	g_R[client].LastInputYaw = inputAngles[1];
	int camera = EntRefToEntIndex(g_R[client].CameraRef);
	SetEntPropEnt(client, Prop_Send, "m_hViewEntity", camera);
	SetClientViewEntity(client, camera);
	g_R[client].Changing = false;
	g_V[v].LastMove = GetGameTime();
	if (seat == 0)
		StartVehicleEngineSound(v, vehicle);
	PrintToChat(client, "[Vehicles] %s. Mouse: look | Use: exit | Reload: cockpit/chase view.", g_SeatNames[seat]);
	if (seat == 0)
		PrintToChat(client, "[Vehicles] WASD: drive | Space: brake | Primary fire: horn (%.0fs cooldown).", VEHICLE_HORN_COOLDOWN);
	return true;
}

bool ExitRider(int client, bool forced) {
	int v = g_R[client].Vehicle;
	if (v == -1)
		return true;
	if (g_R[client].Changing && !forced)
		return false;
	int seat = g_R[client].Seat;
	if (IsClientInGame(client)) {
		float point[3], angles[3];
		bool safe = FindExit(client, point);
		if (!safe && !forced) {
			PrintToChat(client, "[Vehicles] No clear exit space nearby.");
			return false;
		}
		if (!safe)
			safe = EmergencyExit(client, point);
		g_R[client].Changing = true;
		GetClientEyeAngles(client, angles);
		angles[0] = angles[2] = 0.0;
		AcceptEntityInput(client, "ClearParent");
		float zero[3];
		TeleportEntity(client, point, angles, zero);
		RestoreDriver(client);
		// Clear occupancy before a death callback can re-enter cleanup.
		g_V[v].Occupants[seat] = 0;
		g_R[client].Vehicle = -1;
		if (!safe && IsPlayerAlive(client) && !StandingClear(client, point)) {
			ForcePlayerSuicide(client);
			LogMessage("No safe forced exit for userid %d; killed trapped player as a last resort.", g_R[client].UserId);
		}
	}
	g_V[v].Occupants[seat] = 0;
	ReleaseSeatWeaponLock(client);
	ReleaseSeatArmor(client);
	ClearDriverDisplay(client);
	ResetRider(client);
	g_NextUse[client] = GetGameTime() + 0.75;
	if (seat == 0)
		StopEngine(v);
	return true;
}

bool ApplySeatArmor(int client) {
	if (!HasEntProp(client, Prop_Data, "m_takedamage"))
		return false;
	g_R[client].SavedTakeDamage = GetEntProp(client, Prop_Data, "m_takedamage");
	g_R[client].ArmorApplied = true;
	SetEntProp(client, Prop_Data, "m_takedamage", 0);
	return true;
}

void ReleaseSeatArmor(int client) {
	if (!g_R[client].ArmorApplied)
		return;
	g_R[client].ArmorApplied = false;
	if (IsClientInGame(client) && HasEntProp(client, Prop_Data, "m_takedamage")
		&& GetEntProp(client, Prop_Data, "m_takedamage") == 0)
		SetEntProp(client, Prop_Data, "m_takedamage", g_R[client].SavedTakeDamage);
}

bool ApplySeatWeaponLock(int client) {
	if (!SDKHookEx(client, SDKHook_PreThinkPost, Hook_SeatWeaponLock))
		return false;
	int flags = GetEntProp(client, Prop_Send, "m_iPlayerFlags");
	g_R[client].WasWeaponRestricted = (flags & PF_WEAPON_RESTRICTED) != 0;
	g_R[client].WeaponLockApplied = true;
	if (!g_R[client].WasWeaponRestricted)
		SetEntProp(client, Prop_Send, "m_iPlayerFlags", flags | PF_WEAPON_RESTRICTED);
	return true;
}

public void Hook_SeatWeaponLock(int client) {
	if (!g_R[client].WeaponLockApplied || g_R[client].Vehicle == -1 || !IsPlayerAlive(client))
		return;
	// Reassert after game PreThink updates player flags, before weapon processing.
	int flags = GetEntProp(client, Prop_Send, "m_iPlayerFlags");
	if (!(flags & PF_WEAPON_RESTRICTED))
		SetEntProp(client, Prop_Send, "m_iPlayerFlags", flags | PF_WEAPON_RESTRICTED);
}

void ReleaseSeatWeaponLock(int client) {
	if (!g_R[client].WeaponLockApplied)
		return;
	g_R[client].WeaponLockApplied = false;
	if (IsClientInGame(client)) {
		SDKUnhook(client, SDKHook_PreThinkPost, Hook_SeatWeaponLock);
		int flags = GetEntProp(client, Prop_Send, "m_iPlayerFlags");
		if (!g_R[client].WasWeaponRestricted && (flags & PF_WEAPON_RESTRICTED))
			SetEntProp(client, Prop_Send, "m_iPlayerFlags", flags & ~PF_WEAPON_RESTRICTED);
	}
	g_R[client].WasWeaponRestricted = false;
}

public void Frame_VerifyEntry(any userid) {
	int client = GetClientOfUserId(userid);
	if (g_EndingMap || client == 0 || g_R[client].Vehicle == -1)
		return;
	if (ArmedATVPassenger(client) && HumanAlive(client) && AttachedDriver(client, Vehicle(g_R[client].Vehicle)) && PassengerViewReady(client))
		return;
	if (!g_R[client].Changing && HumanAlive(client) && AttachedDriver(client, Vehicle(g_R[client].Vehicle))
		&& EntRefToEntIndex(g_R[client].CameraRef) != -1 && EntRefToEntIndex(g_R[client].DisplayRef) != -1
		&& GetEntPropEnt(client, Prop_Send, "m_hViewEntity") == EntRefToEntIndex(g_R[client].CameraRef))
		return;
	ExitRider(client, true);
	PrintToChat(client, "[Vehicles] Incomplete entry cancelled; player state restored. Check server errors.");
}

void CaptureInput(int client, int buttons, const float angles[3], int cmdnum) {
	int v = g_R[client].Vehicle;
	bool passenger = ArmedATVPassenger(client);
	if (passenger && (!g_R[client].SoloDrive || DrivingClient(v) != client))
		return;
	if (cmdnum <= g_R[client].LastDriveCmd) {
		if (g_R[client].Seat == 0)
			g_V[v].ReplayedDriveCmds++;
		return;
	}
	g_R[client].LastDriveCmd = cmdnum;
	if (g_R[client].Seat == 0 || passenger) {
		g_V[v].DriveButtons = buttons;
		if (passenger)
			g_R[client].SoloDriveInputTime = GetGameTime();
		if (buttons & (BTN_LEFT | BTN_RIGHT)) {
			g_V[v].LastTurnButtons = buttons;
			g_V[v].LastTurnTime = GetGameTime();
		}
	}
	if (passenger)
		return;
	float change = NormalizeYaw(angles[1] - g_R[client].LastInputYaw);
	g_R[client].LastInputYaw = angles[1];
	g_R[client].LookYaw = ClampFloat(g_R[client].LookYaw + change, -110.0, 110.0);
	g_R[client].LookPitch = ClampFloat(angles[0], -45.0, IsATV(g_R[client].Vehicle) ? 75.0 : 50.0);
}

public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3],
	int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2]) {
	if (!g_EndingMap && g_R[client].Vehicle != -1 && HumanAlive(client))
		CaptureInput(client, buttons, angles, cmdnum);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3],
	int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	int pressed = buttons & ~g_LastButtons[client];
	g_LastButtons[client] = buttons;
	if (g_EndingMap || g_Count == 0 || !HumanAlive(client))
		return Plugin_Continue;
	bool seated = g_R[client].Vehicle != -1;
	if ((pressed & BTN_USE) && GetGameTime() >= g_NextUse[client]) {
		g_NextUse[client] = GetGameTime() + 0.5;
		if (seated)
			ExitRider(client, false);
		else
			EnterNearestSeat(client, true);
	}
	if (ArmedATVPassenger(client)) {
		float rearYaw = PassengerRearYaw(client);
		if (!seated) {
			angles[0] = 0.0;
			angles[1] = rearYaw;
		}
		float yaw = NormalizeYaw(angles[1] - rearYaw);
		float clampedYaw = ClampFloat(yaw, -ATV_PASSENGER_YAW, ATV_PASSENGER_YAW);
		float pitch = ClampFloat(angles[0], -50.0, 45.0);
		bool snap = FloatAbs(yaw - clampedYaw) > 0.01 || FloatAbs(angles[0] - pitch) > 0.01;
		angles[0] = pitch;
		angles[1] = NormalizeYaw(rearYaw + clampedYaw);
		angles[2] = 0.0;
		g_R[client].LookYaw = clampedYaw;
		g_R[client].LookPitch = pitch;
		if (snap)
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
		HoldPassengerMotion(client);
		buttons &= ~ATV_PASSENGER_BLOCKED_BUTTONS;
		vel[0] = vel[1] = vel[2] = 0.0;
		return Plugin_Changed;
	}
	if (seated && g_R[client].Vehicle != -1 && !g_R[client].Changing && (pressed & BTN_RELOAD)) {
		g_R[client].ChaseView = !g_R[client].ChaseView;
		UpdateCamera(client, Vehicle(g_R[client].Vehicle));
	}
	if (seated && (pressed & BTN_ATTACK1))
		TryVehicleHorn(client);
	if (!seated && g_R[client].Vehicle != -1)
		CaptureInput(client, buttons, angles, cmdnum);
	if (seated || g_R[client].Vehicle != -1) {
		buttons &= BTN_FORWARD | BTN_BACKWARD | BTN_LEFT | BTN_RIGHT;
		weapon = impulse = 0;
		vel[0] = vel[1] = vel[2] = 0.0;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void OnGameFrame() {
	if (g_EndingMap || g_Count == 0)
		return;
	float now = GetGameTime();
	for (int v = 0; v < MAX_VEHICLES; v++) {
		int vehicle = Vehicle(v);
		if (vehicle == -1 || g_V[v].Destroyed || (!Occupied(v) && !g_V[v].Airborne))
			continue;
		int passenger = IsATV(v) ? RiderInSeat(v, 1) : 0;
		if (passenger > 0 && g_R[passenger].SoloDrive
			&& (now >= g_R[passenger].SoloDriveEnds || now - g_R[passenger].SoloDriveInputTime > 0.5
				|| !HumanAlive(passenger) || g_R[passenger].Changing || !AttachedDriver(passenger, vehicle)
				|| RiderInSeat(v, 0) != 0 || g_V[v].Health <= 0.0)) {
			StopPassengerDrive(passenger);
			if (IsClientInGame(passenger))
				PrintToChat(passenger, "[Vehicles] Solo driving test stopped.");
		}
		float elapsed = now - g_V[v].LastMove;
		if (elapsed <= 0.0)
			continue;
		g_V[v].LastMove = now;
		float dt = FloatMin(elapsed, 0.05);
		g_V[v].LastStepTime = dt;
		int driver = DrivingClient(v);
		if (g_V[v].Airborne || (driver > 0 && !g_R[driver].Changing && HumanAlive(driver) && AttachedDriver(driver, vehicle))) {
			DriveVehicleStep(v, vehicle, dt);
			if (Vehicle(v) != vehicle)
				continue;
			UpdateVehicleDashboard(v, vehicle, elapsed);
			SyncWheelAnimation(v, vehicle);
		}
		for (int s = 0; s < VehicleSeats(v); s++) {
			int client = RiderInSeat(v, s);
			if (client == 0 || g_R[client].Changing || !HumanAlive(client))
				continue;
			if (ArmedATVPassenger(client)) {
				if (g_R[client].AimTestStep != -1 && (FloatAbs(g_V[v].Speed) > 0.1 || g_V[v].Airborne)) {
					StopPassengerAimTest(client);
					PrintToChat(client, "[Vehicles] ADS comparison cancelled because the ATV moved; seated state restored.");
				}
				FollowPassengerSeat(client);
				continue;
			}
			UpdateDriverPose(client, dt);
			UpdateCamera(client, vehicle);
		}
	}
}

void StartWatch() {
	if (g_Watch == null)
		g_Watch = CreateTimer(0.2, Timer_Watch, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Watch(Handle timer) {
	if (g_EndingMap || g_Count == 0) {
		g_Watch = null;
		return Plugin_Stop;
	}
	for (int v = 0; v < MAX_VEHICLES; v++) {
		int vehicle = Vehicle(v);
		if (g_V[v].VehicleRef != INVALID_ENT_REFERENCE && vehicle == -1)
			RemoveVehicle(v);
		else if (vehicle != -1) {
			UpdateVehicleEngineSound(v, vehicle);
			CheckVehicleFireSound(v);
		}
	}
	for (int client = 1; client <= MaxClients; client++) {
		int v = g_R[client].Vehicle;
		if (v == -1)
			continue;
		if (ArmedATVPassenger(client)) {
			if (!HumanAlive(client) || !AttachedDriver(client, Vehicle(v)) || !PassengerViewReady(client))
				ExitRider(client, true);
			continue;
		}
		if (!HumanAlive(client) || !AttachedDriver(client, Vehicle(v)) || EntRefToEntIndex(g_R[client].DisplayRef) == -1
			|| EntRefToEntIndex(g_R[client].CameraRef) == -1 || (g_R[client].SeatedPose && EntRefToEntIndex(g_R[client].DriverRigRef) == -1))
			ExitRider(client, true);
	}
	return Plugin_Continue;
}

public Action Hook_VehicleDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	int v = VehicleByRef(EntIndexToEntRef(victim));
	if (v == -1)
		return Plugin_Continue;
	// Insurgency's movement collision uses pure DMG_DIRECT to break props (including 1000-damage checks).
	if (damagetype == DMG_DIRECT && attacker == inflictor && attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)) {
		damage = 0.0;
		return Plugin_Handled;
	}
	if (damage > 0.0 && g_V[v].Health > 0.0) {
		g_V[v].Health = FloatMax(0.0, g_V[v].Health - damage);
		UpdateVehicleSkin(v, victim);
		if (g_V[v].Health == 0.0)
			RequestFrame(Frame_DisabledVehicle, g_V[v].VehicleRef);
		else
			UpdateVehicleDamageEffects(v, victim);
	}
	return Plugin_Handled;
}

public void Frame_DisabledVehicle(any reference) {
	int v = VehicleByRef(reference);
	if (v == -1 || Vehicle(v) == -1 || g_V[v].Health > 0.0 || g_V[v].Destroyed)
		return;
	// Humvee occupants retain armor; exposed ATV riders take the blast before ejection.
	DamageVehicleExplosion(v);
	v = VehicleByRef(reference);
	if (g_EndingMap || v == -1 || Vehicle(v) == -1 || g_V[v].Health > 0.0 || g_V[v].Destroyed)
		return;
	EjectRiders(v);
	StopEngine(v);
	UpdateVehicleDamageEffects(v, Vehicle(v));
	CreateVehicleWreck(v);
}

void EjectRiders(int v) {
	for (int client = 1; client <= MaxClients; client++) {
		if (g_R[client].Vehicle == v)
			ExitRider(client, true);
	}
}

void RemoveVehicle(int v) {
	if (g_V[v].VehicleRef == INVALID_ENT_REFERENCE)
		return;
	EjectRiders(v);
	StopEngine(v);
	int entity = Vehicle(v);
	ClearVehicleDamageEffect(v);
	ClearVehicleDebris(v);
	ResetVehicle(v);
	g_Count--;
	if (entity != -1)
		RemoveEntity(entity);
}

void ClearVehicles() {
	for (int client = 1; client <= MaxClients; client++)
		StopPlayerPush(client);
	for (int v = 0; v < MAX_VEHICLES; v++)
		RemoveVehicle(v);
	ClearDebrisFlights();
	delete g_Watch;
}

public void OnEntityDestroyed(int entity) {
	if (g_EndingMap || g_Count == 0)
		return;
	for (int v = 0; v < MAX_VEHICLES; v++) {
		if (g_V[v].VehicleRef != INVALID_ENT_REFERENCE && EntRefToEntIndex(g_V[v].VehicleRef) == entity) {
			RequestFrame(Frame_MissingVehicle, g_V[v].VehicleRef);
			return;
		}
	}
}

public void Frame_MissingVehicle(any reference) {
	int v = VehicleByRef(reference);
	if (!g_EndingMap && v != -1 && Vehicle(v) == -1)
		RemoveVehicle(v);
}

bool AdminPlacement(int client, float origin[3], float &yaw, int ignore = -1, int type = VEHICLE_HUMVEE) {
	if (!HumanAlive(client) || g_R[client].Vehicle != -1) {
		strcopy(g_PlacementReason, sizeof(g_PlacementReason), "exit the vehicle and spawn as a player first");
		PrintToChat(client, "[Vehicles] Spawn as a player and exit the vehicle before placing it.");
		return false;
	}
	float eye[3], angles[3], direction[3], end[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	angles[0] = angles[2] = 0.0;
	yaw = NormalizeYaw(angles[1] - 90.0);
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	for (int i = 0; i < 3; i++)
		end[i] = eye[i] + direction[i] * g_Types[type].PlaceDistance;
	Handle trace = TR_TraceRayFilterEx(eye, end, MASK_SOLID, RayType_EndPoint, FilterPlacement, client);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	delete trace;
	if (!clear) {
		strcopy(g_PlacementReason, sizeof(g_PlacementReason), "the area ahead is obstructed");
		PrintToChat(client, "[Vehicles] Face an open area at least %.0f units ahead.", g_Types[type].PlaceDistance);
		return false;
	}
	origin = end;
	origin[2] -= 240.0;
	trace = TR_TraceRayFilterEx(end, origin, MASK_SOLID, RayType_EndPoint, FilterPlacement, ignore);
	bool hit = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	if (hit)
		TR_GetEndPosition(origin, trace);
	delete trace;
	origin[2] += 1.0;
	if (!hit) {
		strcopy(g_PlacementReason, sizeof(g_PlacementReason), "no supporting ground below the placement point");
		PrintToChat(client, "[Vehicles] No supporting ground below the placement point.");
		return false;
	}
	if (!SettlePlacement(origin, yaw, ignore, type) || !PlacementClear(origin, yaw, ignore, type)) {
		PrintToChat(client, "[Vehicles] Cannot place here: %s.", g_PlacementReason);
		return false;
	}
	return SecuritySpawnClear(origin, yaw, client, type);
}

int SpawnVehicle(const float origin[3], float yaw, int savedId = 0, int replace = -1, int type = VEHICLE_HUMVEE) {
	if (type < 0 || type >= VEHICLE_TYPES)
		return -1;
	if (replace != -1 && (Vehicle(replace) == -1 || g_V[replace].Health > 0.0 || Occupied(replace)))
		return -1;
	if (!g_Types[type].Ready || g_EndingMap || (replace == -1 && g_Count >= MAX_VEHICLES) || GetEntityCount() + 14 >= GetMaxEntities() - 80)
		return -1;
	if (!PlacementClear(origin, yaw, Vehicle(replace), type))
		return -1;
	int v = replace;
	for (int i = 0; v == -1 && i < MAX_VEHICLES; i++) {
		if (g_V[i].VehicleRef == INVALID_ENT_REFERENCE) {
			v = i;
			break;
		}
	}
	if (v == -1)
		return -1;
	int entity = CreateEntityByName("prop_dynamic_override");
	if (entity == -1)
		return -1;
	DispatchKeyValue(entity, "targetname", type == VEHICLE_ATV ? "bm_vehicles_atv" : "bm_vehicles_humvee");
	DispatchKeyValue(entity, "model", g_TypeModels[type]);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "DefaultAnim", "idle");
	DispatchKeyValue(entity, "DisableBoneFollowers", "1");
	float angles[3];
	angles[1] = yaw;
	TeleportEntity(entity, origin, angles, NULL_VECTOR);
	if (!DispatchSpawn(entity)) {
		RemoveEntity(entity);
		return -1;
	}
	ActivateEntity(entity);
	int physicsOffset = FindDataMapInfo(entity, "m_pPhysicsObject");
	int animOffset = FindDataMapInfo(entity, "m_flAnimTime");
	if (physicsOffset < 0 || GetEntData(entity, physicsOffset, 4) == 0 || animOffset <= 0 || !HasEntProp(entity, Prop_Send, "m_flPoseParameter")) {
		RemoveEntity(entity);
		LogError("Vehicle physics/animation unavailable. Check model .phy and matching server files.");
		return -1;
	}
	if (replace != -1)
		RemoveVehicle(replace);
	ResetVehicle(v);
	g_V[v].Type = type;
	g_V[v].VehicleRef = EntIndexToEntRef(entity);
	g_V[v].SavedId = savedId;
	g_V[v].AnimTimeOffset = animOffset;
	g_V[v].Health = g_Types[type].Health;
	g_V[v].WheelCycle = 0.5;
	g_V[v].LastMove = GetGameTime();
	strcopy(g_V[v].LastBlockReason, sizeof(g_V[].LastBlockReason), "none");
	SetEntityMoveType(entity, MOVETYPE_NONE);
	SetVariantString("idle");
	AcceptEntityInput(entity, "SetAnimation");
	for (int wheel = 0; wheel < 4; wheel++) {
		SetEntPropFloat(entity, Prop_Send, "m_flPoseParameter", 0.0, wheel * 2);
		SetEntPropFloat(entity, Prop_Send, "m_flPoseParameter", 0.5, wheel * 2 + 1);
	}
	SetPlacementWheels(entity, origin, yaw, type);
	SetEntPropFloat(entity, Prop_Send, "m_flPoseParameter", 0.5, 8);
	SyncWheelAnimation(v, entity);
	UpdateVehicleSkin(v, entity);
	// Custom ray tests use the model's metal/glass hitboxes; hull movement keeps VPhysics.
	if (type == VEHICLE_HUMVEE)
		SetEntProp(entity, Prop_Send, "m_usSolidFlags", GetEntProp(entity, Prop_Send, "m_usSolidFlags") | 1); // FSOLID_CUSTOMRAYTEST
	SetEntProp(entity, Prop_Data, "m_takedamage", 2);
	SDKHook(entity, SDKHook_OnTakeDamage, Hook_VehicleDamage);
	g_Count++;
	StartWatch();
	return v;
}


bool g_ATVWreckReady;
bool g_ATVDebrisReady[VEHICLE_DEBRIS_PARTS];
char g_ATVDebrisModels[VEHICLE_DEBRIS_PARTS][PLATFORM_MAX_PATH] = {
	"models/botmassacre/atv_wreck_v1/wheel_fl.mdl",
	"models/botmassacre/atv_wreck_v1/wheel_fr.mdl",
	"models/botmassacre/atv_wreck_v1/wheel_rl.mdl",
	"models/botmassacre/atv_wreck_v1/wheel_rr.mdl",
	"models/botmassacre/atv_wreck_v1/front_cover.mdl",
	"models/botmassacre/atv_wreck_v1/rear_cover.mdl",
	"models/botmassacre/atv_wreck_v1/saddle.mdl"
};
float g_ATVDebrisCenters[VEHICLE_DEBRIS_PARTS][3] = {
	{-22.000000, 26.000000, 13.000000},
	{22.000000, 26.000000, 13.000000},
	{-22.000000, -26.000000, 13.000000},
	{22.000000, -26.000000, 13.000000},
	{-0.000000, 28.050000, 28.682870},
	{-0.000000, -27.425000, 24.084544},
	{-0.000000, -9.500000, 34.900000}
};
float g_ATVDebrisHalf[VEHICLE_DEBRIS_PARTS][3] = {
	{5.500000, 13.719955, 13.303760},
	{5.500000, 13.719955, 13.303760},
	{5.500000, 13.719955, 13.303760},
	{5.500000, 13.719955, 13.303760},
	{28.500000, 19.850000, 9.182870},
	{28.500000, 19.425000, 14.581195},
	{7.600000, 21.500000, 2.900000}
};
bool IsATV(int v) {
	return v >= 0 && v < MAX_VEHICLES && g_V[v].Type == VEHICLE_ATV;
}

bool ArmedATVPassenger(int client) {
	return g_R[client].Seat == 1 && IsATV(g_R[client].Vehicle);
}

int ATVPassengerVariant(const char[] model) {
	if (StrEqual(model, "models/characters/us_ranger_infantry_00.mdl", false))
		return 0;
	if (StrEqual(model, "models/characters/us_ranger_infantry_00_des.mdl", false))
		return 1;
	if (StrEqual(model, "models/characters/us_ranger_infantry_00_shad.mdl", false))
		return 2;
	return -1;
}

bool PassengerViewReady(int client) {
	int view = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
	if (view > 0 && view != client)
		return false;
	int modelIndex = ATVPassengerVariant(g_R[client].SavedModel);
	char model[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	return EntRefToEntIndex(g_R[client].PassengerSupportRef) > MaxClients
		&& (PassengerAimTestNoDisplay(client) || EntRefToEntIndex(g_R[client].DisplayRef) > MaxClients)
		&& modelIndex != -1 && g_R[client].PassengerModelApplied && StrEqual(model, g_R[client].AimTestStep == 4 ? g_R[client].SavedModel : g_ATVPassengerModels[modelIndex], false);
}

float PassengerRearYaw(int client) {
	float angles[3];
	int vehicle = Vehicle(g_R[client].Vehicle);
	if (vehicle != -1)
		GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	return NormalizeYaw(angles[1] - 90.0);
}

void FollowPassengerSeat(int client, bool entering = false) {
	int vehicle = Vehicle(g_R[client].Vehicle);
	if (!AttachedDriver(client, vehicle))
		return;
	float origin[3], angles[3], local[3], point[3], current[3], zero[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local, 1);
	VehiclePoint(origin, angles, local, point);
	if (g_R[client].AimTestStep == 1)
		point = g_R[client].AimTestOutside;
	GetClientAbsOrigin(client, current);
	if (entering) {
		float view[3];
		view[1] = NormalizeYaw(angles[1] - 90.0);
		TeleportEntity(client, point, view, zero);
	} else if (GetVectorDistance(current, point, true) > 0.0001) {
		// Keep native view and muzzle coordinates unparented; only the display is parented.
		TeleportEntity(client, point, NULL_VECTOR, zero);
		if (GetVectorDistance(current, point, true) <= 4096.0)
			SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") & ~EF_NOINTERP);
	}
}

bool CreatePassengerSupport(int client, int vehicle) {
	int support = CreateEntityByName("prop_dynamic_override");
	if (support == -1)
		return false;
	g_R[client].PassengerSupportRef = EntIndexToEntRef(support);
	DispatchKeyValue(support, "targetname", "bm_atv_passenger_support");
	DispatchKeyValue(support, "model", g_TypeModels[VEHICLE_ATV]);
	DispatchKeyValue(support, "solid", "0");
	DispatchKeyValue(support, "DisableBoneFollowers", "1");
	DispatchKeyValue(support, "disableshadows", "1");
	DispatchKeyValue(support, "disableshadowdepth", "1");
	if (!DispatchSpawn(support))
		return false;
	SetEntityMoveType(support, MOVETYPE_NONE);
	SetEntityRenderMode(support, RENDER_NONE);
	SetEntProp(support, Prop_Data, "m_takedamage", 0);
	SetEntProp(support, Prop_Send, "m_CollisionGroup", 0);
	float mins[3] = {-8.0, -8.0, -4.0};
	float maxs[3] = {8.0, 8.0, -0.5};
	SetEntPropVector(support, Prop_Send, "m_vecMins", mins);
	SetEntPropVector(support, Prop_Send, "m_vecMaxs", maxs);
	SetEntProp(support, Prop_Send, "m_nSolidType", 2); // SOLID_BBOX, without VPhysics.
	SetEntProp(support, Prop_Send, "m_nSurroundType", 0);
	SetEntProp(support, Prop_Send, "m_usSolidFlags", 4 | 64); // NOT_SOLID until enabled; FORCE_WORLD_ALIGNED.
	float local[3];
	SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local, 1);
	ParentAtLocal(support, vehicle, local, 0.0);
	// The native input registers the bbox in the server collision partition.
	AcceptEntityInput(support, "EnableCollision");
	ActivateEntity(support);
	// Keep this networked and ownerless so the passenger's prediction can collide with it.
	SetEdictFlags(support, GetEdictFlags(support) | FL_EDICT_ALWAYS);
	return GetEntProp(support, Prop_Send, "m_nSolidType") == 2
		&& (GetEntProp(support, Prop_Send, "m_usSolidFlags") & 4) == 0;
}

void SetPassengerGrounded(int client, bool grounded) {
	int offset = FindDataMapInfo(client, "m_fFlags");
	int flags = GetEntData(client, offset, 4);
	// Insurgency's raw ground bit is 1. Preserve other bits and notify clients; SetEntityFlags does neither reliably.
	SetEntData(client, offset, grounded ? (flags | 1) : (flags & ~1), 4, true);
}

void HoldPassengerMotion(int client) {
	int vehicle = Vehicle(g_R[client].Vehicle);
	if (vehicle == -1 || !AttachedDriver(client, vehicle))
		return;
	// Usercmd velocity is only input; native walking and spread read entity velocity.
	float zero[3];
	SetEntDataVector(client, FindDataMapInfo(client, "m_vecVelocity"), zero, true);
	SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", zero);
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", zero);
	SetEntPropFloat(client, Prop_Send, "m_flFallVelocity", 0.0);
	SetEntProp(client, Prop_Send, "m_bJumping", 0);
	int support = EntRefToEntIndex(g_R[client].PassengerSupportRef);
	SetEntPropEnt(client, Prop_Send, "m_hGroundEntity", support);
	SetPassengerGrounded(client, support > MaxClients);
}

public void Hook_PassengerAnimate(int client) {
	if (!g_EndingMap && ArmedATVPassenger(client) && HumanAlive(client) && !g_R[client].Changing) {
		// EF_NODRAW makes ShouldUpdateAnimState skip the native animation update.
		SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") & ~EF_NODRAW);
		HoldPassengerMotion(client);
	}
}

public void Hook_PassengerPostThink(int client) {
	if (g_EndingMap || !ArmedATVPassenger(client) || !HumanAlive(client) || g_R[client].Changing)
		return;
	HoldPassengerMotion(client);
	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	SetEntProp(client, Prop_Send, "m_fEffects", g_R[client].AimTestStep == 4 ? ((effects & ~EF_NODRAW) | g_R[client].SavedNoDraw) : (effects | EF_NODRAW));
	if (!PassengerAimTestNoDisplay(client) && !UpdatePassengerDisplay(client)) {
		LogError("Rear passenger display update failed for client %d; safely exiting seat.", client);
		ExitRider(client, true);
	}
}

public void Hook_PassengerMotion(int client) {
	if (!g_EndingMap && ArmedATVPassenger(client) && HumanAlive(client) && !g_R[client].Changing) {
		FollowPassengerSeat(client);
		HoldPassengerMotion(client);
	}
}

int VehicleSeats(int v) {
	return g_Types[g_V[v].Type].Seats;
}

void ATVCameraLocal(int client, float local[3]) {
	float headYaw = DegToRad(g_R[client].HeadYaw);
	float headPitch = DegToRad(g_R[client].HeadPitch);
	float centerY = 0.66 * Cosine(headPitch) + 4.24 * Sine(headPitch);
	local[0] = -0.33 * Cosine(headYaw) - centerY * Sine(headYaw);
	local[1] = -4.52 - 0.33 * Sine(headYaw) + centerY * Cosine(headYaw);
	local[2] = FloatMax(71.31 - 0.66 * Sine(headPitch) + 4.24 * Cosine(headPitch) + 2.0, 79.0);
	float yaw = DegToRad(g_R[client].LookYaw);
	local[0] -= 12.0 * Sine(yaw);
	local[1] += 12.0 * Cosine(yaw);
}

bool HumanAlive(int client) {
	return client > 0 && client <= MaxClients && IsClientInGame(client)
		&& !IsFakeClient(client) && IsPlayerAlive(client);
}

bool AttachedDriver(int client, int vehicle) {
	if (client <= 0 || !IsClientInGame(client) || vehicle <= MaxClients)
		return false;
	int parent = GetEntPropEnt(client, Prop_Data, "m_hMoveParent");
	if (ArmedATVPassenger(client))
		return parent == -1 && g_R[client].PassengerMotionApplied
			&& Vehicle(g_R[client].Vehicle) == vehicle && GetEntityMoveType(client) == MOVETYPE_NONE;
	return parent == vehicle;
}

public bool FilterPlacement(int entity, int contentsMask, any client) {
	return entity != client && !IsVehicleDebris(entity);
}

bool StandingClear(int client, const float position[3]) {
	float mins[3] = {-16.0, -16.0, 0.0};
	float maxs[3] = {16.0, 16.0, 74.0};
	Handle trace = TR_TraceHullFilterEx(position, position, mins, maxs, MASK_PLAYERSOLID, FilterPlacement, client);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	delete trace;
	return clear;
}

float ClampFloat(float value, float low, float high) {
	return value < low ? low : (value > high ? high : value);
}

float NormalizeYaw(float yaw) {
	while (yaw > 180.0)
		yaw -= 360.0;
	while (yaw < -180.0)
		yaw += 360.0;
	return yaw;
}

float ApproachSpeed(float value, float target, float amount) {
	if (value < target)
		return FloatMin(value + amount, target);
	return FloatMax(value - amount, target);
}

float FloatMin(float a, float b) {
	return a < b ? a : b;
}

float FloatMax(float a, float b) {
	return a > b ? a : b;
}

void MoveContinuous(int entity, const float position[3], const float angles[3]) {
	float old[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", old);
	TeleportEntity(entity, position, angles, NULL_VECTOR);
	// Teleport marks EF_NOINTERP. Allow interpolation only for these small, checked updates.
	if (GetVectorDistance(old, position, true) <= 4096.0)
		SetEntProp(entity, Prop_Send, "m_fEffects", GetEntProp(entity, Prop_Send, "m_fEffects") & ~EF_NOINTERP);
}

void LocalPoint(const float origin[3], float yaw, const float local[3], float world[3]) {
	float radians = DegToRad(yaw);
	float ca = Cosine(radians), sa = Sine(radians);
	world[0] = origin[0] + ca * local[0] - sa * local[1];
	world[1] = origin[1] + sa * local[0] + ca * local[1];
	world[2] = origin[2] + local[2];
}

void ParentAtLocal(int entity, int parent, const float local[3], float localYaw) {
	float angles[3];
	angles[1] = localYaw;
	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", parent, parent);
	// Engine Teleport uses SetLocalOrigin/SetLocalAngles for parented entities.
	TeleportEntity(entity, local, angles, NULL_VECTOR);
}

bool SupportsSeatedDriver(const char[] model) {
	return StrEqual(model, "models/characters/us_ranger_infantry_00.mdl", false)
		|| StrEqual(model, "models/characters/us_ranger_infantry_00_des.mdl", false)
		|| StrEqual(model, "models/characters/us_ranger_infantry_00_shad.mdl", false);
}

bool EmergencyExit(int client, float result[3]) {
	result = g_R[client].EntryOrigin;
	result[2] += 2.0;
	if (StandingClear(client, result))
		return true;
	// Only forced cleanup uses this wider search around the original entry location.
	for (int ring = 1; ring <= 4; ring++) {
		for (int side = 0; side < 8; side++) {
			float radians = float(side) * FLOAT_PI / 4.0;
			float top[3], bottom[3];
			top = g_R[client].EntryOrigin;
			top[0] += Cosine(radians) * float(ring * 40);
			top[1] += Sine(radians) * float(ring * 40);
			top[2] += 60.0;
			bottom = top;
			bottom[2] -= 120.0;
			Handle trace = TR_TraceRayFilterEx(top, bottom, MASK_PLAYERSOLID, RayType_EndPoint, FilterPlacement, client);
			bool hit = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
			float normal[3];
			if (hit) {
				TR_GetEndPosition(result, trace);
				TR_GetPlaneNormal(trace, normal);
			}
			delete trace;
			if (!hit || normal[2] < 0.7)
				continue;
			result[2] += 2.0;
			if (StandingClear(client, result))
				return true;
		}
	}
	result = g_R[client].EntryOrigin;
	return false;
}

void RestorePassengerVehicleOwner(int client) {
	int vehicle = EntRefToEntIndex(g_R[client].PassengerCollisionVehicleRef);
	int owner = EntRefToEntIndex(g_R[client].PassengerSavedVehicleOwnerRef);
	g_R[client].PassengerCollisionVehicleRef = INVALID_ENT_REFERENCE;
	g_R[client].PassengerSavedVehicleOwnerRef = INVALID_ENT_REFERENCE;
	if (vehicle > MaxClients && IsValidEntity(vehicle)
		&& GetEntPropEnt(vehicle, Prop_Send, "m_hOwnerEntity") == client)
		SetEntPropEnt(vehicle, Prop_Send, "m_hOwnerEntity", owner);
}

void RestoreDriver(int client) {
	StopPassengerDrive(client);
	StopPassengerAimTest(client);
	RestorePassengerWeapon(client);
	RestorePassengerVehicleOwner(client);
	if (client < 1 || !IsClientInGame(client))
		return;
	ReleaseSeatWeaponLock(client);
	ReleaseSeatArmor(client);
	if (g_R[client].PassengerMotionApplied) {
		SDKUnhook(client, SDKHook_PreThinkPost, Hook_PassengerMotion);
		SDKUnhook(client, SDKHook_PostThink, Hook_PassengerAnimate);
		SDKUnhook(client, SDKHook_PostThinkPost, Hook_PassengerPostThink);
		g_R[client].PassengerMotionApplied = false;
		SetEntPropEnt(client, Prop_Send, "m_hGroundEntity", -1);
		SetPassengerGrounded(client, false);
	}
	if (g_R[client].PassengerModelApplied) {
		int modelIndex = ATVPassengerVariant(g_R[client].SavedModel);
		char model[PLATFORM_MAX_PATH];
		GetClientModel(client, model, sizeof(model));
		if (modelIndex != -1 && StrEqual(model, g_ATVPassengerModels[modelIndex], false)) {
			int skin = GetEntProp(client, Prop_Send, "m_nSkin");
			int body = GetEntProp(client, Prop_Send, "m_nBody");
			SetEntityModel(client, g_R[client].SavedModel);
			SetEntProp(client, Prop_Send, "m_nSkin", skin);
			SetEntProp(client, Prop_Send, "m_nBody", body);
		}
		g_R[client].PassengerModelApplied = false;
	}
	SetEntPropEnt(client, Prop_Send, "m_hViewEntity", -1);
	SetClientViewEntity(client, client);
	SetEntProp(client, Prop_Send, "m_fEffects", (GetEntProp(client, Prop_Send, "m_fEffects") & ~EF_NODRAW) | g_R[client].SavedNoDraw);
	SetEntProp(client, Prop_Send, "m_iHideHUD", (GetEntProp(client, Prop_Send, "m_iHideHUD") & ~VEHICLE_HUD_BITS) | (g_R[client].SavedHud & VEHICLE_HUD_BITS));
	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", g_R[client].SavedDrawViewmodel);
	if (IsPlayerAlive(client))
		SetEntityMoveType(client, g_R[client].SavedMoveType);
	int activeWeapon = ArmedATVPassenger(client) ? -1 : EntRefToEntIndex(g_R[client].SavedWeaponRef);
	if (activeWeapon > MaxClients && IsValidEntity(activeWeapon))
		SetEntProp(activeWeapon, Prop_Send, "m_fEffects", (GetEntProp(activeWeapon, Prop_Send, "m_fEffects") & ~EF_NODRAW) | g_R[client].SavedWeaponNoDraw);
}

void ClearDriverDisplay(int client) {
	StopPassengerDrive(client);
	StopPassengerAimTest(client);
	RestorePassengerWeapon(client);
	RestorePassengerVehicleOwner(client);
	int support = EntRefToEntIndex(g_R[client].PassengerSupportRef);
	g_R[client].PassengerSupportRef = INVALID_ENT_REFERENCE;
	if (support > MaxClients && IsValidEntity(support))
		RemoveEntity(support);
	int camera = EntRefToEntIndex(g_R[client].CameraRef);
	g_R[client].CameraRef = INVALID_ENT_REFERENCE;
	if (camera > MaxClients && IsValidEntity(camera))
		RemoveEntity(camera);
	int display = EntRefToEntIndex(g_R[client].DisplayRef);
	g_R[client].DisplayRef = INVALID_ENT_REFERENCE;
	if (display > MaxClients && IsValidEntity(display))
		RemoveEntity(display);
	int rig = EntRefToEntIndex(g_R[client].DriverRigRef);
	g_R[client].DriverRigRef = INVALID_ENT_REFERENCE;
	g_R[client].DriverAnimTimeOffset = -1;
	g_R[client].HeadYaw = 0.0;
	g_R[client].HeadPitch = 0.0;
	g_R[client].SeatedPose = false;
	if (rig > MaxClients && IsValidEntity(rig))
		RemoveEntity(rig);
}

bool CreateCamera(int client, int vehicle) {
	int camera = CreateEntityByName("info_target");
	if (camera == -1)
		return false;
	// Match guided_rockets.sp: network this camera, including outside the body PVS.
	DispatchKeyValue(camera, "spawnflags", "3");
	if (!DispatchSpawn(camera)) {
		RemoveEntity(camera);
		return false;
	}
	g_R[client].CameraRef = EntIndexToEntRef(camera);
	float local[3];
	CameraLocal(client, local);
	float origin[3], angles[3], world[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	VehiclePoint(origin, angles, local, world);
	float viewAngles[3];
	VehicleLookAngles(angles, 0.0, 0.0, viewAngles);
	// Unparented camera: UpdateCamera supplies world positions and angles.
	TeleportEntity(camera, world, viewAngles, NULL_VECTOR);
	return true;
}

bool CreateDriverRig(int client, int vehicle) {
	int rig = CreateEntityByName("prop_dynamic_override");
	if (rig == -1)
		return false;
	DispatchKeyValue(rig, "model", IsATV(g_R[client].Vehicle) ? ATV_RIDER_MODEL : (g_R[client].Seat == 0 ? DRIVER_RIG_MODEL : PASSENGER_RIG_MODEL));
	DispatchKeyValue(rig, "solid", "0");
	DispatchKeyValue(rig, "DefaultAnim", DRIVER_SEATED_POSE);
	DispatchKeyValue(rig, "disableshadows", "1");
	DispatchKeyValue(rig, "DisableBoneFollowers", "1");
	if (!DispatchSpawn(rig)) {
		RemoveEntity(rig);
		return false;
	}
	g_R[client].DriverAnimTimeOffset = FindDataMapInfo(rig, "m_flAnimTime");
	if (g_R[client].DriverAnimTimeOffset <= 0) {
		RemoveEntity(rig);
		LogError("Seated driver animation time is unavailable.");
		return false;
	}
	g_R[client].HeadYaw = 0.0;
	g_R[client].HeadPitch = 0.0;
	g_R[client].DriverRigRef = EntIndexToEntRef(rig);
	SetEntityMoveType(rig, MOVETYPE_NONE);
	float local[3];
	SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local);
	ParentAtLocal(rig, vehicle, local, 0.0);
	SetVariantString(DRIVER_SEATED_POSE);
	AcceptEntityInput(rig, "SetAnimation");
	ActivateEntity(rig);
	UpdateDriverPose(client, 0.0);
	return true;
}

bool CreateDriverDisplay(int client, int vehicle) {
	char model[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	g_R[client].SeatedPose = false;
	if ((IsATV(g_R[client].Vehicle) ? g_ATVRiderReady : (g_R[client].Seat == 0 ? g_DriverRigReady : g_PassengerRigReady)) && SupportsSeatedDriver(model)) {
		if (!CreateDriverRig(client, vehicle))
			return false;
		g_R[client].SeatedPose = true;
	} else {
		PrintToChat(client, "[Vehicles] Seated rig unavailable for this model; using the previous crouch pose. See status.");
		LogMessage("Seated driver fallback: model='%s', rig ready=%d", model, g_DriverRigReady);
	}
	int display = CreateEntityByName("prop_dynamic_override");
	if (display == -1)
		return false;
	DispatchKeyValue(display, "model", model);
	DispatchKeyValue(display, "solid", "0");
	DispatchKeyValue(display, "DisableBoneFollowers", "1");
	DispatchKeyValue(display, "DefaultAnim", DRIVER_POSE);
	DispatchKeyValue(display, "disableshadows", "1");
	if (!DispatchSpawn(display)) {
		RemoveEntity(display);
		return false;
	}
	g_R[client].DisplayRef = EntIndexToEntRef(display);
	SetEntProp(display, Prop_Send, "m_nSkin", GetEntProp(client, Prop_Send, "m_nSkin"));
	SetEntProp(display, Prop_Send, "m_nBody", GetEntProp(client, Prop_Send, "m_nBody"));
	SetVariantString(DRIVER_POSE);
	AcceptEntityInput(display, "SetAnimation");
	if (g_R[client].SeatedPose) {
		// IsFollowingEntity rejects bone merging while the prop retains MOVETYPE_PUSH.
		SetEntityMoveType(display, MOVETYPE_NONE);
		float local[3];
		ParentAtLocal(display, EntRefToEntIndex(g_R[client].DriverRigRef), local, 0.0);
		// The carrier supplies matching bones; retain the player's original mesh and appearance.
		SetEntProp(display, Prop_Send, "m_fEffects", GetEntProp(display, Prop_Send, "m_fEffects") | DRIVER_BONEMERGE_EFFECTS);
	} else {
		float local[3];
		SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local, 1);
		ParentAtLocal(display, vehicle, local, 90.0);
	}
	ActivateEntity(display);
	SetEntityRenderMode(display, RENDER_NORMAL);
	SetEntityRenderColor(display, 255, 255, 255, 255);
	return true;
}

void UpdateDriverPose(int client, float dt) {
	int rig = EntRefToEntIndex(g_R[client].DriverRigRef);
	if (rig <= MaxClients || !IsValidEntity(rig) || g_R[client].DriverAnimTimeOffset <= 0)
		return;
	float yaw = g_R[client].LookYaw;
	float pitch = g_R[client].LookPitch;
	if (yaw < -70.0)
		yaw = -70.0;
	else if (yaw > 70.0)
		yaw = 70.0;
	if (pitch < -35.0)
		pitch = -35.0;
	else if (pitch > 35.0)
		pitch = 35.0;
	g_R[client].HeadYaw = ApproachSpeed(g_R[client].HeadYaw, yaw, 180.0 * dt);
	g_R[client].HeadPitch = ApproachSpeed(g_R[client].HeadPitch, pitch, 120.0 * dt);
	SetEntPropFloat(rig, Prop_Send, "m_flPoseParameter", g_R[client].Seat == 0 ? (g_V[g_R[client].Vehicle].Steering + 1.0) * 0.5 : 0.5, 0);
	SetEntPropFloat(rig, Prop_Send, "m_flPoseParameter", (g_R[client].HeadYaw + 70.0) / 140.0, 1);
	SetEntPropFloat(rig, Prop_Send, "m_flPoseParameter", (g_R[client].HeadPitch + 35.0) / 70.0, 2);
	if (GetEntProp(rig, Prop_Send, "m_bClientSideAnimation"))
		SetEntProp(rig, Prop_Send, "m_bClientSideAnimation", 0);
	if (GetEntProp(rig, Prop_Send, "m_nSequence") != DRIVER_IDLE_SEQUENCE) {
		SetVariantString(DRIVER_SEATED_POSE);
		AcceptEntityInput(rig, "SetAnimation");
		if (GetEntProp(rig, Prop_Send, "m_nSequence") != DRIVER_IDLE_SEQUENCE) {
			SetEntProp(rig, Prop_Send, "m_nSequence", DRIVER_IDLE_SEQUENCE);
			SetEntPropFloat(rig, Prop_Send, "m_flCycle", 0.0);
			SetEntProp(rig, Prop_Send, "m_nNewSequenceParity", (GetEntProp(rig, Prop_Send, "m_nNewSequenceParity") + 1) & 7);
		}
	}
	SetEntDataFloat(rig, g_R[client].DriverAnimTimeOffset, GetGameTime(), true);
}

void UpdateCamera(int client, int vehicle) {
	int camera = EntRefToEntIndex(g_R[client].CameraRef);
	if (camera == -1 || vehicle == -1)
		return;
	float origin[3], angles[3], seat[3];
	float local[3];
	CameraLocal(client, local);
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	VehiclePoint(origin, angles, local, seat);
	float viewAngles[3];
	VehicleLookAngles(angles, g_R[client].LookPitch, g_R[client].LookYaw, viewAngles);
	if (!g_R[client].ChaseView) {
		MoveContinuous(camera, seat, viewAngles);
		return;
	}
	angles[1] += 90.0 + g_R[client].LookYaw;
	angles[2] = 0.0;
	angles[0] = ClampFloat(g_R[client].LookPitch + 15.0, -10.0, 65.0);
	float direction[3], desired[3];
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	for (int i = 0; i < 3; i++)
		desired[i] = seat[i] - direction[i] * g_Types[g_V[g_R[client].Vehicle].Type].ChaseDistance;
	float mins[3] = {-4.0, -4.0, -4.0};
	float maxs[3] = {4.0, 4.0, 4.0};
	Handle trace = TR_TraceHullFilterEx(seat, desired, mins, maxs, MASK_SOLID, FilterVehicle, g_R[client].Vehicle);
	if (TR_StartSolid(trace) || TR_AllSolid(trace))
		desired = seat;
	else if (TR_DidHit(trace))
		TR_GetEndPosition(desired, trace);
	delete trace;
	MoveContinuous(camera, desired, angles);
}

bool ExitRouteClear(int v, const float seat[3], const float feet[3]) {
	float eye[3];
	eye = feet;
	eye[2] += 57.0;
	Handle trace = TR_TraceRayFilterEx(seat, eye, MASK_PLAYERSOLID, RayType_EndPoint, FilterVehicle, v);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	delete trace;
	if (clear)
		return true;
	// Reach over a low ramp edge, but check both vertical legs as well as the crossing.
	float highSeat[3], highEye[3];
	highSeat = seat;
	highEye = eye;
	highSeat[2] = highEye[2] = FloatMax(seat[2], eye[2]) + 48.0;
	for (int leg = 0; leg < 3; leg++) {
		float a[3], b[3];
		if (leg == 0) {
			a = seat;
			b = highSeat;
		} else if (leg == 1) {
			a = highSeat;
			b = highEye;
		} else {
			a = highEye;
			b = eye;
		}
		trace = TR_TraceRayFilterEx(a, b, MASK_PLAYERSOLID, RayType_EndPoint, FilterVehicle, v);
		clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
		delete trace;
		if (!clear)
			return false;
	}
	return true;
}

bool FindExit(int client, float result[3]) {
	int v = g_R[client].Vehicle;
	int vehicle = Vehicle(v);
	if (vehicle == -1)
		return false;
	float origin[3], angles[3], seat[3], local[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	SeatLocal(v, g_R[client].Seat, local, 2);
	VehiclePoint(origin, angles, local, seat);
	float mins[3] = {-16.0, -16.0, 0.0}, maxs[3] = {16.0, 16.0, 74.0};
	for (int ring = 0; ring < 3; ring++) {
		for (int side = 0; side < 12; side++) {
			float yaw = DegToRad(angles[1] + float(side) * 30.0 + (g_R[client].Seat % 2 == 0 ? 180.0 : 0.0));
			float across = (IsATV(v) ? 56.0 : 96.0) + float(ring) * 48.0;
			float along = (IsATV(v) ? 80.0 : 154.0) + float(ring) * 48.0;
			float relative = DegToRad(float(side) * 30.0);
			float radius = 1.0 / SquareRoot(Pow(Cosine(relative) / across, 2.0) + Pow(Sine(relative) / along, 2.0));
			float top[3], bottom[3];
			top = origin;
			top[0] += Cosine(yaw) * radius;
			top[1] += Sine(yaw) * radius;
			top[2] = FloatMax(origin[2] + 110.0, seat[2] + 40.0);
			bottom = top;
			bottom[2] = origin[2] - VEHICLE_EXIT_DROP;
			float highest = top[2];
			for (int level = 0; level < 3; level++) {
				top[2] = level == 0 ? origin[2] + 24.0 : (level == 1 ? origin[2] + 64.0 : highest);
				Handle trace = TR_TraceHullFilterEx(top, bottom, mins, maxs, MASK_PLAYERSOLID, FilterVehicle, v);
				bool hit = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
				float normal[3];
				if (hit) {
					TR_GetEndPosition(result, trace);
					TR_GetPlaneNormal(trace, normal);
				}
				delete trace;
				if (hit && normal[2] >= 0.7) {
					result[2] += 2.0;
					if (StandingClear(client, result) && ExitRouteClear(v, seat, result))
						return true;
				}
			}
			// A midair exit needs empty space, not ground beneath the car.
			if (g_V[v].Airborne && ring == 0) {
				result = top;
				result[2] = seat[2] - 40.0;
				if (StandingClear(client, result) && ExitRouteClear(v, seat, result))
					return true;
			}
		}
	}
	return false;
}

void PrepareVehicleDamageEffects() {
	g_DamageEffectsReady = false;
	int table = FindStringTable("ParticleEffectNames");
	if (table == INVALID_STRING_TABLE) {
		LogError("Vehicle damage effects unavailable: ParticleEffectNames table is missing.");
		return;
	}
	bool locked = LockStringTables(false);
	for (int i = 0; i < sizeof(g_DamageEffects); i++) {
		if (FindStringIndex(table, g_DamageEffects[i]) == INVALID_STRING_INDEX)
			AddToStringTable(table, g_DamageEffects[i]);
	}
	LockStringTables(locked);
	for (int i = 0; i < sizeof(g_DamageEffects); i++) {
		if (FindStringIndex(table, g_DamageEffects[i]) == INVALID_STRING_INDEX) {
			LogError("Could not register vehicle particle %s.", g_DamageEffects[i]);
			return;
		}
	}
	g_DamageEffectsReady = true;
}

void ClearVehicleDamageEffect(int v) {
	StopVehicleFireSound(v);
	delete g_V[v].DamageEffectTimer;
	int particle = EntRefToEntIndex(g_V[v].DamageEffectRef);
	g_V[v].DamageEffectRef = INVALID_ENT_REFERENCE;
	if (particle != -1) {
		AcceptEntityInput(particle, "Stop");
		RemoveEntity(particle);
	}
}

void UpdateVehicleDamageEffects(int v, int vehicle) {
	int stage = g_V[v].Health <= 0.0 ? 3 : (g_V[v].Health < g_Types[g_V[v].Type].Health * VEHICLE_FIRE_HEALTH ? 2
		: (g_V[v].Health < g_Types[g_V[v].Type].Health * VEHICLE_SMOKE_HEALTH ? 1 : 0));
	if (stage == g_V[v].DamageEffectStage)
		return;
	ClearVehicleDamageEffect(v);
	g_V[v].DamageEffectStage = stage;
	PlayVehicleExplosionSound(vehicle, stage);
	if (stage == 0 || !g_DamageEffectsReady || vehicle == -1)
		return;
	int entities = GetEntityCount();
	if (entities >= 1900 || entities + 1 > GetMaxEntities() - 80)
		return;
	int particle = CreateEntityByName("info_particle_system");
	if (particle == -1)
		return;
	DispatchKeyValue(particle, "effect_name", g_DamageEffects[stage - 1]);
	DispatchKeyValue(particle, "start_active", "0");
	if (!DispatchSpawn(particle)) {
		RemoveEntity(particle);
		return;
	}
	float local[3];
	local[1] = IsATV(v) ? 0.0 : (stage == 3 ? 0.0 : 70.0);
	local[2] = IsATV(v) ? 24.0 : (stage == 3 ? 35.0 : 59.0);
	ParentAtLocal(particle, vehicle, local, 0.0);
	ActivateEntity(particle);
	g_V[v].DamageEffectRef = EntIndexToEntRef(particle);
	AcceptEntityInput(particle, "Start");
	if (stage == 3)
		StartVehicleWreckFireSound(v, vehicle);
}

public Action Timer_EndVehicleDamageEffect(Handle timer, any reference) {
	int v = VehicleByRef(reference);
	if (v != -1 && g_V[v].DamageEffectTimer == timer) {
		g_V[v].DamageEffectTimer = null;
		ClearVehicleDamageEffect(v);
		int vehicle = Vehicle(v);
		if (vehicle != -1 && g_V[v].Destroyed) {
			SetEntProp(vehicle, Prop_Send, "m_fEffects", GetEntProp(vehicle, Prop_Send, "m_fEffects") | EF_NODRAW);
			g_V[v].WreckHidden = true;
		}
	}
	return Plugin_Stop;
}

int VehicleGlassStage(int v) {
	return g_V[v].Health <= g_Types[g_V[v].Type].Health * 0.25 ? 3 : (g_V[v].Health <= g_Types[g_V[v].Type].Health * 0.5 ? 2 : (g_V[v].Health <= g_Types[g_V[v].Type].Health * 0.75 ? 1 : 0));
}

void UpdateVehicleSkin(int v, int vehicle) {
	if (g_V[v].Destroyed)
		return;
	int skin = (IsATV(v) ? 0 : VehicleGlassStage(v) * 2) + (g_V[v].BrakeLights ? 1 : 0);
	if (skin != g_V[v].VisualSkin) {
		SetEntProp(vehicle, Prop_Send, "m_nSkin", skin);
		g_V[v].VisualSkin = skin;
	}
}

void UpdateVehicleDashboard(int v, int vehicle, float elapsed) {
	if (g_V[v].Destroyed)
		return;
	g_V[v].DisplayDistance += g_V[v].StepDistance;
	g_V[v].DisplayElapsed += elapsed;
	if (g_V[v].DisplayElapsed < VEHICLE_DASH_UPDATE_INTERVAL)
		return;
	float mph = g_V[v].DisplayDistance / g_V[v].DisplayElapsed * VEHICLE_UNITS_TO_MPH;
	if (IsATV(v)) {
		int digits = RoundToNearest(ClampFloat(mph, 0.0, 99.0));
		if (digits != g_V[v].DisplayMPH) {
			// Ones bodygroup base 1, tens base 10. Brake lights still use m_nSkin.
			SetEntProp(vehicle, Prop_Send, "m_nBody", digits);
			g_V[v].DisplayMPH = digits;
		}
	} else {
		// Dial scales: 120 mph and 4000 RPM. RPM follows the existing simulated engine load.
		float speed = ApproachSpeed(g_V[v].GaugeSpeed, ClampFloat(mph, 0.0, 120.0), 120.0 * g_V[v].DisplayElapsed);
		float rpm = ApproachSpeed(g_V[v].GaugeRPM, 800.0 + VehicleEngineLoad(v) * 2800.0, 2500.0 * g_V[v].DisplayElapsed);
		if (FloatAbs(speed - g_V[v].GaugeSpeed) > 0.001)
			SetEntPropFloat(vehicle, Prop_Send, "m_flPoseParameter", speed / 120.0, 9);
		if (FloatAbs(rpm - g_V[v].GaugeRPM) > 0.01)
			SetEntPropFloat(vehicle, Prop_Send, "m_flPoseParameter", rpm / 4000.0, 10);
		g_V[v].GaugeSpeed = speed;
		g_V[v].GaugeRPM = rpm;
	}
	g_V[v].DisplayDistance = 0.0;
	g_V[v].DisplayElapsed = 0.0;
}

void SyncWheelAnimation(int v, int vehicle) {
	if (g_V[v].Destroyed)
		return;
	// Pose interpolation is latched to animation time, not the driving position update.
	if (GetEntProp(vehicle, Prop_Send, "m_bClientSideAnimation"))
		SetEntProp(vehicle, Prop_Send, "m_bClientSideAnimation", 0);
	if (GetEntProp(vehicle, Prop_Send, "m_nSequence") != VEHICLE_IDLE_SEQUENCE) {
		SetVariantString("idle");
		AcceptEntityInput(vehicle, "SetAnimation");
		if (GetEntProp(vehicle, Prop_Send, "m_nSequence") != VEHICLE_IDLE_SEQUENCE) {
			SetEntProp(vehicle, Prop_Send, "m_nSequence", VEHICLE_IDLE_SEQUENCE);
			SetEntPropFloat(vehicle, Prop_Send, "m_flCycle", 0.0);
			SetEntProp(vehicle, Prop_Send, "m_nNewSequenceParity", (GetEntProp(vehicle, Prop_Send, "m_nNewSequenceParity") + 1) & 7);
		}
		g_V[v].AnimationRepairs++;
	}
	// FIELD_TIME is a float in memory, but its SendProp uses integer tick encoding.
	SetEntDataFloat(vehicle, g_V[v].AnimTimeOffset, GetGameTime(), true);
}

void StopEngine(int v) {
	if (g_V[v].Destroyed)
		return;
	g_V[v].BrakeLights = false;
	if (Vehicle(v) != -1)
		UpdateVehicleSkin(v, Vehicle(v));
	g_V[v].Speed = 0.0;
	g_V[v].StepDistance = 0.0;
	g_V[v].DisplayDistance = 0.0;
	g_V[v].DisplayElapsed = 0.0;
	g_V[v].DisplayMPH = 0;
	g_V[v].GaugeSpeed = 0.0;
	g_V[v].GaugeRPM = 0.0;
	if (Vehicle(v) != -1) {
		if (IsATV(v))
			SetEntProp(Vehicle(v), Prop_Send, "m_nBody", 0);
		else {
			SetEntPropFloat(Vehicle(v), Prop_Send, "m_flPoseParameter", 0.0, 9);
			SetEntPropFloat(Vehicle(v), Prop_Send, "m_flPoseParameter", 0.0, 10);
		}
	}
	g_V[v].DriveButtons = 0;
	g_V[v].Steering = 0.0;
	int vehicle = Vehicle(v);
	if (vehicle == -1) {
		g_V[v].EngineSound = false;
		return;
	}
	if (g_V[v].EngineSound)
		StopSound(vehicle, SNDCHAN_STATIC, ENGINE_SAMPLE);
	SetEntPropFloat(vehicle, Prop_Send, "m_flPoseParameter", 0.5, 8);
	SyncWheelAnimation(v, vehicle);
	g_V[v].EngineSound = false;
}

// A blocked suspension tilt must not prevent driving back out of a clear position.
bool TrySlopeEscape(int v, const float origin[3], float next[3], const float oldAngles[3], float angles[3],
	const float groundNormal[3], float contact[4], float dt) {
	float dx = next[0] - origin[0], dy = next[1] - origin[1];
	if (dx * dx + dy * dy < 0.000001)
		return false;
	float rise = -(groundNormal[0] * dx + groundNormal[1] * dy) / FloatMax(groundNormal[2], 0.1);
	for (int attempt = 0; attempt < 2; attempt++) {
		float retry[3];
		retry = next;
		retry[2] = origin[2] + (attempt == 0 ? rise : 0.0);
		if (FloatAbs(retry[2] - origin[2]) > g_Types[g_V[v].Type].StepHeight)
			continue;
		if (!SweepBody(v, origin, retry, oldAngles, oldAngles) || !SweepVehicleWheels(v, origin, retry, oldAngles, oldAngles))
			continue;
		angles = oldAngles;
		float floor;
		g_V[v].GroundNormal = groundNormal;
		if (!GroundHeight(v, retry, angles, dt, floor, contact, false))
			g_V[v].SupportMask = g_V[v].SupportCount = 0;
		next = retry;
		return true;
	}
	return false;
}

bool TryCurbStep(int v, const float origin[3], float next[3], const float oldAngles[3], const float newAngles[3], const float contact[4]) {
	float lowest = contact[0];
	for (int wheel = 1; wheel < 4; wheel++)
		lowest = FloatMin(lowest, contact[wheel]);
	float top[3], across[3];
	top = origin;
	top[2] = FloatMin(origin[2] + g_Types[g_V[v].Type].StepHeight, lowest + g_Types[g_V[v].Type].Suspension + 1.0);
	if (top[2] <= FloatMax(origin[2], next[2]) + 0.01)
		return false;
	across = next;
	across[2] = top[2];
	if (!SweepBody(v, origin, top, oldAngles, oldAngles) || !SweepVehicleWheels(v, origin, top, oldAngles, oldAngles)
		|| !SweepBody(v, top, across, oldAngles, newAngles) || !SweepVehicleWheels(v, top, across, oldAngles, newAngles))
		return false;
	float fraction, surface;
	if (!TraceBody(v, across, next, newAngles, newAngles, fraction, surface, true))
		return false;
	float wheelFraction, normal[3];
	if (!TraceVehicleWheels(v, across, next, newAngles, newAngles, wheelFraction, normal))
		return false;
	if (wheelFraction < 1.0) {
		if (normal[2] < g_Types[g_V[v].Type].GroundZ)
			return false;
		fraction = FloatMin(fraction, wheelFraction);
	}
	if (surface > lowest + g_Types[g_V[v].Type].StepHeight + 0.01) {
		strcopy(g_V[v].LastBlockReason, sizeof(g_V[v].LastBlockReason), "step surface above curb limit");
		return false;
	}
	float landing[3];
	landing = next;
	landing[2] = across[2] + (next[2] - across[2]) * fraction;
	if (fraction < 1.0)
		landing[2] += 0.1;
	if (landing[2] > lowest + g_Types[g_V[v].Type].Suspension + 1.0 || !SweepBody(v, landing, landing, newAngles, newAngles)
		|| !SweepVehicleWheels(v, landing, landing, newAngles, newAngles))
		return false;
	next = landing;
	g_V[v].CurbSteps++;
	return true;
}

float VehicleGravity() {
	if (g_VehicleGravity == null)
		g_VehicleGravity = FindConVar("sv_gravity");
	return g_VehicleGravity == null ? 800.0 : FloatMax(0.0, g_VehicleGravity.FloatValue);
}

void AnimateVehicleTravel(int v, int vehicle, const float origin[3], const float next[3], const float angles[3], const float contact[4]) {
	float dx = next[0] - origin[0], dy = next[1] - origin[1];
	float distance = SquareRoot(dx * dx + dy * dy);
	g_V[v].StepDistance = distance;
	g_V[v].WheelCycle += (g_V[v].Speed < 0.0 ? -distance : distance) / (2.0 * FLOAT_PI * g_Types[g_V[v].Type].WheelRadius);
	g_V[v].WheelCycle -= float(RoundToFloor(g_V[v].WheelCycle));
	float up[3];
	GetAngleVectors(angles, NULL_VECTOR, NULL_VECTOR, up);
	for (int wheel = 0; wheel < 4; wheel++) {
		SetEntPropFloat(vehicle, Prop_Send, "m_flPoseParameter", g_V[v].WheelCycle, wheel * 2 + 1);
		float extension = 1.0;
		if (!g_V[v].Airborne && (g_V[v].SupportMask & (1 << wheel)))
			extension = ClampFloat((next[2] - 1.0 - contact[wheel]) / (g_Types[g_V[v].Type].WheelTravel * FloatMax(up[2], 0.1)), 0.0, 1.0);
		SetEntPropFloat(vehicle, Prop_Send, "m_flPoseParameter", extension, wheel * 2);
	}
}

void FlyVehicleStep(int v, int vehicle, float dt) {
	float origin[3], next[3], angles[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	for (int axis = 0; axis < 3; axis++)
		next[axis] = origin[axis] + g_V[v].FlightVelocity[axis] * dt;
	float gravity = VehicleGravity();
	next[2] -= 0.5 * gravity * dt * dt;
	g_V[v].FlightVelocity[2] -= gravity * dt;
	g_V[v].SupportMask = g_V[v].SupportCount = 0;
	float fraction, normal[3];
	if (!TraceVehicleWheels(v, origin, next, angles, angles, fraction, normal)) {
		g_V[v].FlightVelocity[0] = g_V[v].FlightVelocity[1] = g_V[v].FlightVelocity[2] = 0.0;
		g_V[v].Speed = 0.0;
		g_V[v].HullBlocks++;
		g_V[v].BlockedMoves++;
		return;
	}
	bool wheelHit = fraction < 1.0;
	bool landed = wheelHit && normal[2] > 0.01;
	if (wheelHit)
		fraction = FloatMax(0.0, fraction - 0.1 / FloatMax(GetVectorDistance(origin, next), 0.1));
	float destination[3];
	for (int axis = 0; axis < 3; axis++)
		destination[axis] = origin[axis] + (next[axis] - origin[axis]) * fraction;
	float bodyFraction, surface;
	if (!TraceBody(v, origin, destination, angles, angles, bodyFraction, surface, g_V[v].FlightVelocity[2] <= 0.0)) {
		if (StrEqual(g_V[v].LastBlockReason, "body starts solid") && GetGameTime() >= g_V[v].NextRampRecovery) {
			g_V[v].NextRampRecovery = GetGameTime() + 0.25;
			if (RecoverVehicleSupport(v, vehicle, origin, angles)) {
				g_V[v].Airborne = false;
				g_V[v].FlightVelocity[2] = 0.0;
				return;
			}
		}
		g_V[v].FlightVelocity[0] = g_V[v].FlightVelocity[1] = 0.0;
		g_V[v].FlightVelocity[2] = FloatMin(0.0, g_V[v].FlightVelocity[2]);
		g_V[v].Speed = 0.0;
		g_V[v].HullBlocks++;
		g_V[v].BlockedMoves++;
		return;
	}
	if (bodyFraction < 1.0) {
		bodyFraction = FloatMax(0.0, bodyFraction - 0.1 / FloatMax(GetVectorDistance(origin, destination), 0.1));
		for (int axis = 0; axis < 3; axis++)
			destination[axis] = origin[axis] + (destination[axis] - origin[axis]) * bodyFraction;
		landed = true;
		wheelHit = false;
	}
	if (wheelHit && normal[2] < g_Types[g_V[v].Type].GroundZ) {
		g_V[v].HullBlocks++;
		g_V[v].BlockedMoves++;
	}
	if (landed) {
		float settled[3];
		settled = destination;
		settled[2] += 1.0;
		if (SweepBody(v, destination, settled, angles, angles) && SweepVehicleWheels(v, destination, settled, angles, angles))
			destination = settled;
		g_V[v].Airborne = false;
		g_V[v].FlightVelocity[0] = g_V[v].FlightVelocity[1] = g_V[v].FlightVelocity[2] = 0.0;
		g_V[v].GroundNormal[0] = g_V[v].GroundNormal[1] = 0.0;
		g_V[v].GroundNormal[2] = 1.0;
		if (wheelHit && normal[2] >= g_Types[g_V[v].Type].GroundZ)
			g_V[v].GroundNormal = normal;
		g_V[v].Landings++;
		if (DrivingClient(v) == 0 || (wheelHit && normal[2] < g_Types[g_V[v].Type].GroundZ))
			g_V[v].Speed = 0.0;
	} else if (wheelHit) {
		g_V[v].FlightVelocity[0] = g_V[v].FlightVelocity[1] = 0.0;
		if (normal[2] < -0.01)
			g_V[v].FlightVelocity[2] = FloatMin(0.0, g_V[v].FlightVelocity[2]);
		g_V[v].Speed = 0.0;
	}
	if (!VehiclePlayerContacts(v, vehicle, origin, destination, angles, angles))
		return;
	MoveContinuous(vehicle, destination, angles);
	float contact[4];
	AnimateVehicleTravel(v, vehicle, origin, destination, angles, contact);
}

void BeginVehicleFlight(int v, int vehicle, float dt) {
	g_V[v].Airborne = true;
	g_V[v].Jumps++;
	FlyVehicleStep(v, vehicle, dt);
}

void DriveVehicleStep(int v, int vehicle, float dt) {
	g_V[v].StepDistance = 0.0;
	g_V[v].BodyTraces = 0;
	if (g_V[v].Airborne) {
		FlyVehicleStep(v, vehicle, dt);
		return;
	}
	float throttle;
	if (g_V[v].DriveButtons & BTN_FORWARD)
		throttle += 1.0;
	if (g_V[v].DriveButtons & BTN_BACKWARD)
		throttle -= 1.0;
	bool brake = (g_V[v].DriveButtons & BTN_JUMP) != 0;
	float targetSpeed = throttle > 0.0 ? g_Types[g_V[v].Type].ForwardSpeed : (throttle < 0.0 ? -g_Types[g_V[v].Type].ReverseSpeed : 0.0);
	int controller = DrivingClient(v);
	if (controller > 0 && g_R[controller].SoloDrive)
		targetSpeed = ClampFloat(targetSpeed, -120.0, 120.0);
	float acceleration = throttle == 0.0 ? g_Types[g_V[v].Type].Coast : g_Types[g_V[v].Type].Acceleration;
	g_V[v].BrakeLights = brake || g_V[v].Speed * throttle < 0.0;
	UpdateVehicleSkin(v, vehicle);
	if (g_V[v].BrakeLights || g_V[v].Health <= 0.0) {
		targetSpeed = 0.0;
		acceleration = g_Types[g_V[v].Type].Brake;
	}
	g_V[v].Speed = ApproachSpeed(g_V[v].Speed, targetSpeed, acceleration * dt);
	float steering;
	if (g_V[v].DriveButtons & BTN_LEFT)
		steering += 1.0;
	if (g_V[v].DriveButtons & BTN_RIGHT)
		steering -= 1.0;
	if (FloatAbs(GetEntPropFloat(vehicle, Prop_Send, "m_flPoseParameter", 8) - (g_V[v].Steering + 1.0) * 0.5) > 0.01)
		g_V[v].SteerOverrides++;
	g_V[v].Steering = ApproachSpeed(g_V[v].Steering, steering, g_Types[g_V[v].Type].SteeringResponse * dt);
	SetEntPropFloat(vehicle, Prop_Send, "m_flPoseParameter", (g_V[v].Steering + 1.0) * 0.5, 8);
	if (FloatAbs(g_V[v].Speed) < 0.01) {
		if (GetGameTime() < g_V[v].NextSupportCheck)
			return;
		g_V[v].NextSupportCheck = GetGameTime() + 0.1;
	}
	float origin[3], next[3], angles[3], oldAngles[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	oldAngles = angles;
	float turn = g_V[v].Steering * g_Types[g_V[v].Type].TurnRate * dt * FloatMin(FloatAbs(g_V[v].Speed) / 80.0, 1.0);
	angles[1] = NormalizeYaw(angles[1] + (g_V[v].Speed < 0.0 ? -turn : turn));
	float heading = DegToRad(angles[1] + 90.0);
	g_V[v].FlightVelocity[0] = Cosine(heading) * g_V[v].Speed;
	g_V[v].FlightVelocity[1] = Sine(heading) * g_V[v].Speed;
	float up[3];
	up = g_V[v].GroundNormal;
	g_V[v].FlightVelocity[2] = -(up[0] * g_V[v].FlightVelocity[0] + up[1] * g_V[v].FlightVelocity[1]) / FloatMax(up[2], 0.1);
	next = origin;
	next[0] += g_V[v].FlightVelocity[0] * dt;
	next[1] += g_V[v].FlightVelocity[1] * dt;
	float floor, contact[4];
	bool supported = GroundHeight(v, next, angles, dt, floor, contact);
	float ballisticHeight = origin[2] + g_V[v].FlightVelocity[2] * dt - 0.5 * VehicleGravity() * dt * dt;
	if (!supported || floor + 1.0 < origin[2] - g_Types[g_V[v].Type].StepHeight
		|| (g_V[v].FlightVelocity[2] > 20.0 && floor + 1.0 < ballisticHeight - 2.0)) {
		g_V[v].GroundNormal = up;
		BeginVehicleFlight(v, vehicle, dt);
		return;
	}
	if (floor + 1.0 > origin[2] + g_Types[g_V[v].Type].StepHeight) {
		g_V[v].GroundNormal = up;
		g_V[v].Speed = 0.0;
		g_V[v].GroundBlocks++;
		g_V[v].BlockedMoves++;
		strcopy(g_V[v].LastBlockReason, sizeof(g_V[v].LastBlockReason), "ground rise above curb limit");
		return;
	}
	next[2] = floor + 1.0;
	if (!SweepBody(v, origin, next, oldAngles, angles) || !SweepVehicleWheels(v, origin, next, oldAngles, angles)) {
		char blocked[64];
		strcopy(blocked, sizeof(blocked), g_V[v].LastBlockReason);
		int blockEntity = g_V[v].LastBlockEntity;
		if (!TrySlopeEscape(v, origin, next, oldAngles, angles, up, contact, dt)
			&& !TryCurbStep(v, origin, next, oldAngles, angles, contact)) {
			g_V[v].GroundNormal = up;
			strcopy(g_V[v].LastBlockReason, sizeof(g_V[v].LastBlockReason), blocked);
			g_V[v].LastBlockEntity = blockEntity;
			if (StrEqual(blocked, "body starts solid") && GetGameTime() >= g_V[v].NextRampRecovery) {
				g_V[v].NextRampRecovery = GetGameTime() + 0.25;
				if (RecoverVehicleSupport(v, vehicle, origin, oldAngles))
					return;
			}
			g_V[v].Speed = 0.0;
			g_V[v].BlockedMoves++;
			g_V[v].HullBlocks++;
			return;
		}
	}
	if (!VehiclePlayerContacts(v, vehicle, origin, next, oldAngles, angles))
		return;
	MoveContinuous(vehicle, next, angles);
	AnimateVehicleTravel(v, vehicle, origin, next, angles, contact);
}

bool g_FireSoundReady;
char g_ExplosionSamples[5][PLATFORM_MAX_PATH];
int g_ExplosionSoundCount;

bool PrecacheVehicleSound(const char[] sample) {
	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof(path), "sound/%s", sample[1]); // Samples use the spatial sound prefix.
	bool ready = FileExists(path, true) && PrecacheSound(sample, true);
	if (!ready)
		LogError("Vehicle sound unavailable: %s", path);
	return ready;
}

void PrepareVehicleSounds() {
	g_SoundReady = PrecacheVehicleSound(ENGINE_SAMPLE);
	g_HornSoundReady = PrecacheVehicleSound(VEHICLE_HORN_SAMPLE);
	g_FireSoundReady = PrecacheVehicleSound(VEHICLE_FIRE_SAMPLE);
	g_ExplosionSoundCount = 0;
	for (int i = 1; i <= sizeof(g_ExplosionSamples); i++) {
		char sample[PLATFORM_MAX_PATH];
		Format(sample, sizeof(sample), ")weapons/vehicleexplode/vehicle_explode_%02d.wav", i);
		if (PrecacheVehicleSound(sample)) {
			strcopy(g_ExplosionSamples[g_ExplosionSoundCount], PLATFORM_MAX_PATH, sample);
			g_ExplosionSoundCount++;
		}
	}
}

void TryVehicleHorn(int client) {
	int v = g_R[client].Vehicle;
	if (!g_HornSoundReady || v == -1 || g_R[client].Seat != 0 || g_R[client].Changing)
		return;
	int vehicle = Vehicle(v);
	if (vehicle == -1 || !AttachedDriver(client, vehicle) || g_V[v].Destroyed || g_V[v].Health <= 0.0)
		return;
	float now = GetGameTime();
	if (now < g_NextHorn[client])
		return;
	g_NextHorn[client] = now + VEHICLE_HORN_COOLDOWN;
	EmitSoundToAll(VEHICLE_HORN_SAMPLE, vehicle, SNDCHAN_ITEM, VEHICLE_HORN_SOUND_LEVEL, SND_NOFLAGS, VEHICLE_HORN_VOLUME);
}

void StartVehicleEngineSound(int v, int vehicle) {
	if (!g_SoundReady || g_V[v].EngineSound)
		return;
	g_V[v].EnginePitch = g_Types[g_V[v].Type].EngineIdlePitch;
	g_V[v].EngineVolume = VEHICLE_ENGINE_IDLE_VOLUME;
	EmitSoundToAll(ENGINE_SAMPLE, vehicle, SNDCHAN_STATIC, VEHICLE_ENGINE_SOUND_LEVEL, SND_NOFLAGS,
		g_V[v].EngineVolume, g_V[v].EnginePitch);
	g_V[v].EngineSound = true;
}

float VehicleEngineLoad(int v) {
	float speed = g_V[v].Speed;
	float ratio = FloatMin(1.0, FloatAbs(speed) / FloatMax(1.0, g_Types[g_V[v].Type].ForwardSpeed));
	int buttons = g_V[v].DriveButtons;
	bool throttle = !(buttons & BTN_JUMP) && (((buttons & BTN_FORWARD) && speed >= 0.0)
		|| ((buttons & BTN_BACKWARD) && speed <= 0.0));
	return FloatMin(1.0, ratio * 0.85 + (throttle ? 0.15 : 0.0));
}

void UpdateVehicleEngineSound(int v, int vehicle) {
	if (!g_V[v].EngineSound || g_V[v].Destroyed)
		return;
	float load = VehicleEngineLoad(v);
	int targetPitch = RoundToNearest(float(g_Types[g_V[v].Type].EngineIdlePitch)
		+ float(g_Types[g_V[v].Type].EngineMaxPitch - g_Types[g_V[v].Type].EngineIdlePitch) * load);
	int pitch = g_V[v].EnginePitch;
	if (targetPitch > pitch)
		pitch += targetPitch - pitch > 6 ? 6 : targetPitch - pitch;
	else
		pitch -= pitch - targetPitch > 6 ? 6 : pitch - targetPitch;
	float targetVolume = VEHICLE_ENGINE_IDLE_VOLUME + (VEHICLE_ENGINE_MAX_VOLUME - VEHICLE_ENGINE_IDLE_VOLUME) * load;
	float volume = g_V[v].EngineVolume + FloatMax(-0.05, FloatMin(0.05, targetVolume - g_V[v].EngineVolume));
	if (pitch == g_V[v].EnginePitch && FloatAbs(volume - g_V[v].EngineVolume) < 0.01)
		return;
	EmitSoundToAll(ENGINE_SAMPLE, vehicle, SNDCHAN_STATIC, VEHICLE_ENGINE_SOUND_LEVEL, SND_CHANGEPITCH | SND_CHANGEVOL, volume, pitch);
	g_V[v].EnginePitch = pitch;
	g_V[v].EngineVolume = volume;
}

void StopVehicleFireSound(int v) {
	if (!g_V[v].FireSound)
		return;
	int vehicle = Vehicle(v);
	if (vehicle != -1)
		StopSound(vehicle, SNDCHAN_BODY, VEHICLE_FIRE_SAMPLE);
	g_V[v].FireSound = false;
}

void PlayVehicleExplosionSound(int vehicle, int stage) {
	if (stage != 3 || vehicle == -1)
		return;
	if (g_ExplosionSoundCount > 0)
		EmitSoundToAll(g_ExplosionSamples[GetRandomInt(0, g_ExplosionSoundCount - 1)], vehicle,
			SNDCHAN_AUTO, VEHICLE_EXPLOSION_SOUND_LEVEL, SND_NOFLAGS, VEHICLE_EXPLOSION_VOLUME);
}

bool VehicleFireParticleActive(int v) {
	int particle = EntRefToEntIndex(g_V[v].DamageEffectRef);
	return particle != -1 && g_V[v].DamageEffectStage == 3
		&& (!HasEntProp(particle, Prop_Send, "m_bActive") || GetEntProp(particle, Prop_Send, "m_bActive") != 0);
}

void StartVehicleWreckFireSound(int v, int vehicle) {
	if (!g_FireSoundReady || g_V[v].FireSound || !VehicleFireParticleActive(v))
		return;
	EmitSoundToAll(VEHICLE_FIRE_SAMPLE, vehicle, SNDCHAN_BODY, VEHICLE_FIRE_SOUND_LEVEL, SND_NOFLAGS, VEHICLE_WRECK_FIRE_VOLUME);
	g_V[v].FireSound = true;
}

void CheckVehicleFireSound(int v) {
	if (g_V[v].FireSound && !VehicleFireParticleActive(v))
		StopVehicleFireSound(v);
}

public void OnClientPostAdminCheck(int client) {
	if (!IsClientInGame(client) || IsFakeClient(client) || g_EndingMap)
		return;
	for (int v = 0; v < MAX_VEHICLES; v++) {
		int vehicle = Vehicle(v);
		if (vehicle == -1)
			continue;
		if (g_V[v].EngineSound)
			EmitSoundToClient(client, ENGINE_SAMPLE, vehicle, SNDCHAN_STATIC, VEHICLE_ENGINE_SOUND_LEVEL, SND_NOFLAGS,
				g_V[v].EngineVolume, g_V[v].EnginePitch);
		CheckVehicleFireSound(v);
		if (g_V[v].FireSound)
			EmitSoundToClient(client, VEHICLE_FIRE_SAMPLE, vehicle, SNDCHAN_BODY, VEHICLE_FIRE_SOUND_LEVEL, SND_NOFLAGS,
				VEHICLE_WRECK_FIRE_VOLUME);
	}
}
Handle g_WreckDestroyPhysics;

void PrepareWreckPhysics() {
	GameData config = new GameData("insurgency-bm.games");
	if (config != null) {
		StartPrepSDKCall(SDKCall_Entity);
		if (PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CBaseEntity::VPhysicsDestroyObject"))
			g_WreckDestroyPhysics = EndPrepSDKCall();
		delete config;
	}
	if (g_WreckDestroyPhysics == null)
		LogError("Vehicle wreck physics teardown unavailable: install addons/sourcemod/gamedata/insurgency-bm.games.txt and reload the plugin.");
}

void PrepareVehicleWrecks() {
	g_WreckReady = FileExists(VEHICLE_WRECK_MODEL, true) && PrecacheModel(VEHICLE_WRECK_MODEL, true) > 0;
	g_ATVWreckReady = FileExists(ATV_WRECK_MODEL, true) && PrecacheModel(ATV_WRECK_MODEL, true) > 0;
	for (int i = 0; i < sizeof(g_DebrisEntityRefs); i++)
		g_DebrisEntityRefs[i] = INVALID_ENT_REFERENCE;
	bool missing = !g_WreckReady || !g_ATVWreckReady;
	for (int i = 0; i < VEHICLE_DEBRIS_PARTS; i++) {
		g_DebrisReady[i] = FileExists(g_DebrisModels[i], true) && PrecacheModel(g_DebrisModels[i], true) > 0;
		g_ATVDebrisReady[i] = FileExists(g_ATVDebrisModels[i], true) && PrecacheModel(g_ATVDebrisModels[i], true) > 0;
		missing = missing || !g_DebrisReady[i] || !g_ATVDebrisReady[i];
	}
	if (missing)
		LogError("Some vehicle wreck models are missing. Install the current full vehicle package; destroyed vehicles will still become non-solid.");
}

bool IsVehicleDebris(int entity) {
	return entity > MaxClients && entity < sizeof(g_DebrisEntityRefs)
		&& g_DebrisEntityRefs[entity] != INVALID_ENT_REFERENCE
		&& EntRefToEntIndex(g_DebrisEntityRefs[entity]) == entity;
}

void ClearVehicleDebris(int v) {
	StopVehicleDebrisFlights(g_V[v].VehicleRef);
	delete g_V[v].DebrisTimer;
	for (int i = 0; i < VEHICLE_DEBRIS_PARTS; i++) {
		int entity = EntRefToEntIndex(g_V[v].DebrisRefs[i]);
		g_V[v].DebrisRefs[i] = INVALID_ENT_REFERENCE;
		if (entity == -1)
			continue;
		g_DebrisEntityRefs[entity] = INVALID_ENT_REFERENCE;
		RemoveEntity(entity);
	}
}

int CountVehicleDebris() {
	int count;
	for (int v = 0; v < MAX_VEHICLES; v++) {
		for (int i = 0; i < VEHICLE_DEBRIS_PARTS; i++) {
			if (EntRefToEntIndex(g_V[v].DebrisRefs[i]) != -1)
				count++;
		}
	}
	return count;
}

public Action Timer_ClearVehicleDebris(Handle timer, any reference) {
	int v = VehicleByRef(reference);
	if (v != -1 && g_V[v].DebrisTimer == timer) {
		g_V[v].DebrisTimer = null;
		ClearVehicleDebris(v);
	}
	return Plugin_Stop;
}

bool RemoveWreckPhysics(int vehicle) {
	int offset = FindDataMapInfo(vehicle, "m_pPhysicsObject");
	if (offset < 0)
		return false;
	if (GetEntData(vehicle, offset, 4) != 0) {
		if (g_WreckDestroyPhysics == null)
			return false;
		SDKCall(g_WreckDestroyPhysics, vehicle);
	}
	return GetEntData(vehicle, offset, 4) == 0;
}

void CreateVehicleWreck(int v) {
	int vehicle = Vehicle(v);
	float origin[3], angles[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	g_V[v].Destroyed = true;
	g_V[v].Airborne = false;
	int physicsOffset = FindDataMapInfo(vehicle, "m_pPhysicsObject");
	g_V[v].WreckHadPhysics = physicsOffset >= 0 && GetEntData(vehicle, physicsOffset, 4) != 0;
	// A visual model swap does not tear down the original solid vehicle's physics hull.
	RemoveWreckPhysics(vehicle);
	AcceptEntityInput(vehicle, "DisableCollision");
	SetEntProp(vehicle, Prop_Send, "m_nSolidType", 0);
	SetEntProp(vehicle, Prop_Send, "m_usSolidFlags", 4); // FSOLID_NOT_SOLID; clear custom bullet ray tests.
	SetEntProp(vehicle, Prop_Data, "m_takedamage", 0);
	bool atv = IsATV(v);
	if (atv ? g_ATVWreckReady : g_WreckReady) {
		SetEntityModel(vehicle, atv ? ATV_WRECK_MODEL : VEHICLE_WRECK_MODEL);
		SetEntityRenderColor(vehicle, 255, 255, 255, 255);
		SetEntProp(vehicle, Prop_Send, "m_nBody", 0);
		SetEntProp(vehicle, Prop_Send, "m_nSkin", 0);
		SetVariantString("idle");
		AcceptEntityInput(vehicle, "SetAnimation");
		SetEntProp(vehicle, Prop_Send, "m_nSequence", 0);
		SetEntPropFloat(vehicle, Prop_Send, "m_flPlaybackRate", 0.0);
		AcceptEntityInput(vehicle, "DisableCollision");
		SetEntProp(vehicle, Prop_Send, "m_nSolidType", 0);
		SetEntProp(vehicle, Prop_Send, "m_usSolidFlags", 4);
	} else {
		SetEntProp(vehicle, Prop_Send, "m_fEffects", GetEntProp(vehicle, Prop_Send, "m_fEffects") | EF_NODRAW);
		g_V[v].WreckHidden = true;
	}
	g_V[v].WreckPhysicsRemoved = RemoveWreckPhysics(vehicle);
	if (!g_V[v].WreckPhysicsRemoved)
		LogError("Could not remove vehicle wreck physics; loose debris will be skipped. Update insurgency-bm.games.txt.");
	// Keep the non-solid entity as an admin respawn record after its visuals expire.
	g_V[v].DamageEffectTimer = CreateTimer(VEHICLE_WRECK_EFFECT_LIFETIME, Timer_EndVehicleDamageEffect,
		g_V[v].VehicleRef, TIMER_FLAG_NO_MAPCHANGE);
	int available = VEHICLE_DEBRIS_LIMIT - CountVehicleDebris();
	int entities = GetEntityCount();
	bool spawned;
	for (int i = 0; i < VEHICLE_DEBRIS_PARTS && available > 0; i++) {
		if (!g_V[v].WreckPhysicsRemoved || !(atv ? g_ATVDebrisReady[i] : g_DebrisReady[i]) || entities >= 1900 || entities + 1 > GetMaxEntities() - 80) {
			g_V[v].DebrisFailed++;
			continue;
		}
		float position[3], mins[3], maxs[3];
		if (atv) {
			VehiclePoint(origin, angles, g_ATVDebrisCenters[i], position);
			DebrisFlightBounds(g_ATVDebrisHalf[i], angles, mins, maxs);
		} else {
			VehiclePoint(origin, angles, g_DebrisCenters[i], position);
			float radius = i < 4 ? 21.0 : (i == 4 ? 48.0 : 34.0);
			for (int axis = 0; axis < 3; axis++) {
				maxs[axis] = radius;
				mins[axis] = -radius;
			}
		}
		position[2] += i < 4 ? 5.0 : 0.0;
		Handle trace = TR_TraceHullFilterEx(position, position, mins, maxs, MASK_SOLID, FilterDriving, v);
		bool blocked = TR_DidHit(trace) || TR_StartSolid(trace) || TR_AllSolid(trace);
		delete trace;
		if (blocked) {
			g_V[v].DebrisBlocked++;
			continue;
		}
		int part = CreateEntityByName("prop_dynamic_override");
		if (part == -1) {
			g_V[v].DebrisFailed++;
			continue;
		}
		if (part >= sizeof(g_DebrisEntityRefs)) {
			g_V[v].DebrisFailed++;
			RemoveEntity(part);
			continue;
		}
		DispatchKeyValue(part, "targetname", "bm_vehicle_debris");
		DispatchKeyValue(part, "model", atv ? g_ATVDebrisModels[i] : g_DebrisModels[i]);
		DispatchKeyValue(part, "solid", "0");
		DispatchKeyValue(part, "RandomAnimation", "0");
		TeleportEntity(part, position, angles, NULL_VECTOR);
		if (!DispatchSpawn(part)) {
			g_V[v].DebrisFailed++;
			RemoveEntity(part);
			continue;
		}
		ActivateEntity(part);
		SetEntityMoveType(part, MOVETYPE_NONE);
		SetEntProp(part, Prop_Send, "m_nSolidType", 0);
		SetEntProp(part, Prop_Send, "m_usSolidFlags", 4);
		SetEntProp(part, Prop_Data, "m_takedamage", 0);
		g_V[v].DebrisRefs[i] = EntIndexToEntRef(part);
		g_DebrisEntityRefs[part] = g_V[v].DebrisRefs[i];
		g_V[v].DebrisSpawned++;
		entities++;
		available--;
		spawned = true;
	}
	if (spawned) {
		LaunchVehicleDebris(v);
		g_V[v].DebrisTimer = CreateTimer(VEHICLE_DEBRIS_LIFETIME, Timer_ClearVehicleDebris,
			g_V[v].VehicleRef, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void LaunchVehicleDebris(int v) {
	float origin[3];
	GetEntPropVector(Vehicle(v), Prop_Data, "m_vecAbsOrigin", origin);
	for (int i = 0; i < VEHICLE_DEBRIS_PARTS; i++) {
		int part = EntRefToEntIndex(g_V[v].DebrisRefs[i]);
		if (part == -1 || !IsVehicleDebris(part))
			continue;
		float position[3], velocity[3];
		GetEntPropVector(part, Prop_Data, "m_vecAbsOrigin", position);
		MakeVectorFromPoints(origin, position, velocity);
		velocity[2] = 0.0;
		NormalizeVector(velocity, velocity);
		ScaleVector(velocity, VEHICLE_DEBRIS_LAUNCH_SPEED * GetRandomFloat(0.85, 1.15));
		velocity[2] = VEHICLE_DEBRIS_LAUNCH_LIFT * GetRandomFloat(0.85, 1.15);
		float spin[3];
		for (int axis = 0; axis < 3; axis++)
			spin[axis] = GetRandomFloat(-180.0, 180.0);
		StartDebrisFlight(v, part, velocity, spin);
	}
}

bool RespawnVehicle(int v, int client) {
	int vehicle = Vehicle(v);
	if (vehicle == -1 || g_V[v].Health > 0.0 || Occupied(v))
		return false;
	float origin[3], angles[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	if (!SettlePlacement(origin, angles[1], vehicle, g_V[v].Type) || !PlacementClear(origin, angles[1], vehicle, g_V[v].Type))
		return false;
	if (!SecuritySpawnClear(origin, angles[1], client, g_V[v].Type)) {
		strcopy(g_PlacementReason, sizeof(g_PlacementReason), "the vehicle overlaps a Security spawn area");
		return false;
	}
	strcopy(g_PlacementReason, sizeof(g_PlacementReason), "assets, entity limits or vehicle physics unavailable");
	return SpawnVehicle(origin, angles[1], g_V[v].SavedId, v, g_V[v].Type) != -1;
}

enum struct DebrisFlight {
	bool Active;
	bool Moved;
	int Reference;
	int VehicleRef;
	float Position[3];
	float Start[3];
	float Angles[3];
	float Half[3];
	float Velocity[3];
	float Spin[3];
}

DebrisFlight g_DebrisFlights[VEHICLE_DEBRIS_LIMIT];
Handle g_DebrisFlightTimer;
float g_DebrisFlightTime;
ConVar g_DebrisGravity;

void ClearDebrisFlights() {
	delete g_DebrisFlightTimer;
	for (int i = 0; i < VEHICLE_DEBRIS_LIMIT; i++)
		g_DebrisFlights[i].Active = false;
}

void StopVehicleDebrisFlights(int reference) {
	bool active;
	for (int i = 0; i < VEHICLE_DEBRIS_LIMIT; i++) {
		if (g_DebrisFlights[i].VehicleRef == reference)
			g_DebrisFlights[i].Active = false;
		active = active || g_DebrisFlights[i].Active;
	}
	if (!active)
		delete g_DebrisFlightTimer;
}

void DebrisFlightBounds(const float half[3], const float angles[3], float mins[3], float maxs[3]) {
	float ahead[3], right[3], up[3];
	GetAngleVectors(angles, ahead, right, up);
	for (int axis = 0; axis < 3; axis++) {
		maxs[axis] = FloatAbs(ahead[axis]) * half[0] + FloatAbs(right[axis]) * half[1] + FloatAbs(up[axis]) * half[2];
		mins[axis] = -maxs[axis];
	}
}

void StartDebrisFlight(int v, int entity, const float velocity[3], const float spin[3]) {
	int slot = -1;
	for (int i = 0; i < VEHICLE_DEBRIS_LIMIT; i++) {
		if (!g_DebrisFlights[i].Active) {
			slot = i;
			break;
		}
	}
	if (slot == -1)
		return;
	DebrisFlight flight;
	flight.Reference = EntIndexToEntRef(entity);
	flight.VehicleRef = g_V[v].VehicleRef;
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", flight.Position);
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", flight.Angles);
	float mins[3], maxs[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
	for (int axis = 0; axis < 3; axis++) {
		flight.Start[axis] = flight.Position[axis];
		flight.Half[axis] = FloatMax(FloatAbs(mins[axis]), FloatAbs(maxs[axis]));
		flight.Velocity[axis] = velocity[axis];
		flight.Spin[axis] = spin[axis];
	}
	DebrisFlightBounds(flight.Half, flight.Angles, mins, maxs);
	Handle trace = TR_TraceHullFilterEx(flight.Position, flight.Position, mins, maxs, MASK_SOLID, FilterDriving, v);
	bool blocked = TR_StartSolid(trace) || TR_AllSolid(trace);
	delete trace;
	if (blocked) {
		g_V[v].DebrisFlightBlocked++;
		return;
	}
	flight.Active = true;
	g_DebrisFlights[slot] = flight;
	g_V[v].DebrisLaunched++;
	if (g_DebrisFlightTimer == null) {
		if (g_DebrisGravity == null)
			g_DebrisGravity = FindConVar("sv_gravity");
		g_DebrisFlightTime = GetGameTime();
		g_DebrisFlightTimer = CreateTimer(0.05, Timer_DebrisFlights, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_DebrisFlights(Handle timer) {
	float now = GetGameTime();
	float dt = FloatMin(0.1, FloatMax(0.0, now - g_DebrisFlightTime));
	g_DebrisFlightTime = now;
	float gravity = g_DebrisGravity == null ? 800.0 : g_DebrisGravity.FloatValue;
	bool active;
	for (int i = 0; i < VEHICLE_DEBRIS_LIMIT; i++) {
		if (!g_DebrisFlights[i].Active)
			continue;
		DebrisFlight flight;
		flight = g_DebrisFlights[i];
		int entity = EntRefToEntIndex(flight.Reference);
		int v = VehicleByRef(flight.VehicleRef);
		if (g_EndingMap || entity == -1 || !IsVehicleDebris(entity) || v == -1 || !g_V[v].Destroyed) {
			g_DebrisFlights[i].Active = false;
			continue;
		}
		float destination[3], angles[3], mins[3], maxs[3];
		for (int axis = 0; axis < 3; axis++) {
			destination[axis] = flight.Position[axis] + flight.Velocity[axis] * dt;
			angles[axis] = flight.Angles[axis] + flight.Spin[axis] * dt;
		}
		destination[2] -= 0.5 * gravity * dt * dt;
		flight.Velocity[2] -= gravity * dt;
		// Translation uses the current hull. Rotation is checked separately at the resulting position.
		DebrisFlightBounds(flight.Half, flight.Angles, mins, maxs);
		Handle trace = TR_TraceHullFilterEx(flight.Position, destination, mins, maxs, MASK_SOLID, FilterDriving, v);
		if (TR_StartSolid(trace) || TR_AllSolid(trace)) {
			g_V[v].DebrisFlightBlocked++;
			g_DebrisFlights[i].Active = false;
			delete trace;
			continue;
		}
		bool hit = TR_DidHit(trace);
		if (hit) {
			float normal[3];
			TR_GetEndPosition(destination, trace);
			TR_GetPlaneNormal(trace, normal);
			float into = GetVectorDotProduct(flight.Velocity, normal);
			if (into < 0.0) {
				for (int axis = 0; axis < 3; axis++)
					flight.Velocity[axis] = (flight.Velocity[axis] - into * normal[axis]) * 0.65 - into * normal[axis] * 0.3;
			}
			ScaleVector(flight.Spin, 0.5);
			if (normal[2] > 0.5 && GetVectorLength(flight.Velocity) < 70.0)
				flight.Active = false;
		}
		delete trace;
		DebrisFlightBounds(flight.Half, angles, mins, maxs);
		trace = TR_TraceHullFilterEx(destination, destination, mins, maxs, MASK_SOLID, FilterDriving, v);
		if (!TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace))
			flight.Angles = angles;
		delete trace;
		flight.Position = destination;
		TeleportEntity(entity, flight.Position, flight.Angles, NULL_VECTOR);
		float distance = GetVectorDistance(flight.Start, flight.Position);
		g_V[v].DebrisTravel = FloatMax(g_V[v].DebrisTravel, distance);
		if (!flight.Moved && distance > 8.0) {
			flight.Moved = true;
			g_V[v].DebrisMoved++;
		}
		g_DebrisFlights[i] = flight;
		active = active || flight.Active;
	}
	if (!active) {
		g_DebrisFlightTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

void DamageVehicleExplosion(int v) {
	if (g_V[v].ExplosionApplied)
		return;
	g_V[v].ExplosionApplied = true;
	int vehicle = Vehicle(v);
	if (vehicle == -1 || g_Types[g_V[v].Type].ExplosionRadius <= 0.0 || g_Types[g_V[v].Type].ExplosionDamage <= 0.0)
		return;
	int reference = g_V[v].VehicleRef;
	float origin[3], angles[3], local[3], blast[3];
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(vehicle, Prop_Data, "m_angAbsRotation", angles);
	local[2] = IsATV(v) ? 24.0 : 35.0;
	VehiclePoint(origin, angles, local, blast);
	float radiusSquared = g_Types[g_V[v].Type].ExplosionRadius * g_Types[g_V[v].Type].ExplosionRadius;
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) <= 1 || (g_R[client].Vehicle != -1 && !IsATV(g_R[client].Vehicle)))
			continue;
		// Damage hooks can remove/replace the wreck or end the round during this loop.
		if (VehicleByRef(reference) != v || Vehicle(v) != vehicle || g_EndingMap)
			return;
		float target[3], mins[3], maxs[3];
		GetClientAbsOrigin(client, target);
		GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
		for (int axis = 0; axis < 3; axis++)
			target[axis] += (mins[axis] + maxs[axis]) * 0.5;
		float distanceSquared = GetVectorDistance(blast, target, true);
		if (distanceSquared >= radiusSquared)
			continue;
		Handle trace = TR_TraceRayFilterEx(blast, target, MASK_SOLID, RayType_EndPoint, FilterVehicleBlast, vehicle);
		bool blocked = TR_DidHit(trace) || TR_StartSolid(trace) || TR_AllSolid(trace);
		delete trace;
		if (blocked)
			continue;
		float damage = g_Types[g_V[v].Type].ExplosionDamage * (1.0 - SquareRoot(distanceSquared) / g_Types[g_V[v].Type].ExplosionRadius);
		// Death events fire inside this call; never leave a marker on a surviving client.
		int previousVictim = g_ExplosionVictimUserId;
		g_ExplosionVictimUserId = GetClientUserId(client);
		SDKHooks_TakeDamage(client, vehicle, 0, damage, DMG_BLAST, -1, NULL_VECTOR, blast, false);
		g_ExplosionVictimUserId = previousVictim;
	}
}

public bool FilterVehicleBlast(int entity, int contentsMask, any vehicle) {
	if (entity == vehicle || (entity > 0 && entity <= MaxClients) || IsVehicleDebris(entity))
		return false;
	return true;
}
void RotatedVector(const float angles[3], const float local[3], float world[3]) {
	float axisForward[3], right[3], up[3];
	GetAngleVectors(angles, axisForward, right, up);
	for (int i = 0; i < 3; i++)
		world[i] = axisForward[i] * local[0] - right[i] * local[1] + up[i] * local[2];
}

void VehiclePoint(const float origin[3], const float angles[3], const float local[3], float world[3]) {
	RotatedVector(angles, local, world);
	AddVectors(origin, world, world);
}

void VehicleLookAngles(const float vehicleAngles[3], float pitch, float yaw, float result[3]) {
	float local[3], axisForward[3], up[3], worldForward[3], worldUp[3], right[3], levelUp[3];
	local[0] = pitch;
	local[1] = 90.0 + yaw;
	GetAngleVectors(local, axisForward, NULL_VECTOR, up);
	RotatedVector(vehicleAngles, axisForward, worldForward);
	RotatedVector(vehicleAngles, up, worldUp);
	GetVectorAngles(worldForward, result);
	GetAngleVectors(result, NULL_VECTOR, right, levelUp);
	result[2] = RadToDeg(ArcTangent2(GetVectorDotProduct(worldUp, right), GetVectorDotProduct(worldUp, levelUp)));
}

bool GroundHeight(int v, const float position[3], float angles[3], float dt, float &height, float contact[4], bool tilt = true) {
	float points[4][3], normals[4][3], locals[4][3], normal[3];
	int mask, count;
	for (int wheel = 0; wheel < 4; wheel++) {
		WheelLocal(g_V[v].Type, wheel, locals[wheel]);
		float top[3], bottom[3];
		VehiclePoint(position, angles, locals[wheel], top);
		bottom = top;
		top[2] += g_Types[g_V[v].Type].StepHeight + 4.0;
		bottom[2] -= g_Types[g_V[v].Type].StepHeight + 8.0;
		Handle trace = TR_TraceRayFilterEx(top, bottom, MASK_SOLID, RayType_EndPoint, FilterDriving, v);
		bool hit = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
		if (hit) {
			TR_GetEndPosition(points[wheel], trace);
			TR_GetPlaneNormal(trace, normals[wheel]);
		}
		delete trace;
		if (!hit || normals[wheel][2] < g_Types[g_V[v].Type].GroundZ)
			continue;
		mask |= 1 << wheel;
		count++;
		AddVectors(normal, normals[wheel], normal);
	}
	g_V[v].SupportMask = mask;
	g_V[v].SupportCount = count;
	if (count < 2)
		return false;
	NormalizeVector(normal, normal);
	if (count == 4) {
		float side[3], ahead[3], fitted[3];
		for (int i = 0; i < 3; i++) {
			side[i] = points[1][i] + points[3][i] - points[0][i] - points[2][i];
			ahead[i] = points[0][i] + points[1][i] - points[2][i] - points[3][i];
		}
		GetVectorCrossProduct(side, ahead, fitted);
		NormalizeVector(fitted, fitted);
		if (fitted[2] >= g_Types[g_V[v].Type].GroundZ)
			normal = fitted;
	}
	g_V[v].GroundNormal = normal;
	float target[3], yaw = DegToRad(angles[1]);
	float nx = normal[0] * Cosine(yaw) + normal[1] * Sine(yaw);
	float ny = -normal[0] * Sine(yaw) + normal[1] * Cosine(yaw);
	target[0] = RadToDeg(ArcTangent2(nx, normal[2]));
	target[2] = RadToDeg(ArcTangent2(-ny, SquareRoot(nx * nx + normal[2] * normal[2])));
	if (tilt) {
		angles[0] = ApproachSpeed(angles[0], target[0], VEHICLE_GROUND_TILT_RATE * dt);
		angles[2] = ApproachSpeed(angles[2], target[2], VEHICLE_GROUND_TILT_RATE * dt);
	}
	height = -999999.0;
	for (int wheel = 0; wheel < 4; wheel++) {
		if (!(mask & (1 << wheel)))
			continue;
		float offset[3];
		RotatedVector(angles, locals[wheel], offset);
		float dx = position[0] + offset[0] - points[wheel][0];
		float dy = position[1] + offset[1] - points[wheel][1];
		contact[wheel] = points[wheel][2] - (normals[wheel][0] * dx + normals[wheel][1] * dy) / normals[wheel][2] - offset[2];
		height = FloatMax(height, contact[wheel]);
	}
	// A wheel over a seam or beyond a ramp edge can extend without stopping the car.
	for (int wheel = 0; wheel < 4; wheel++) {
		if (!(mask & (1 << wheel)) || height - contact[wheel] > g_Types[g_V[v].Type].Suspension) {
			g_V[v].SupportMask &= ~(1 << wheel);
			contact[wheel] = height - g_Types[g_V[v].Type].WheelTravel;
		}
	}
	g_V[v].SupportCount = 0;
	for (int wheel = 0; wheel < 4; wheel++)
		if (g_V[v].SupportMask & (1 << wheel))
			g_V[v].SupportCount++;
	return g_V[v].SupportCount >= 2;
}

// Collision is independent of the driving slope limit and the direction of travel.
bool TraceVehicleWheels(int v, const float start[3], const float finish[3], const float oldAngles[3], const float newAngles[3],
	float &fraction, float normal[3]) {
	fraction = 1.0;
	normal[0] = normal[1] = normal[2] = 0.0;
	float turn;
	for (int axis = 0; axis < 3; axis++)
		turn += FloatAbs(NormalizeYaw(newAngles[axis] - oldAngles[axis]));
	int segments = RoundToCeil(turn / 4.0);
	segments = segments < 1 ? 1 : (segments > 16 ? 16 : segments);
	float segmentTurn = DegToRad(turn / float(segments));
	for (int wheel = 0; wheel < 4; wheel++) {
		float local[3], a[3], mins[3], maxs[3];
		WheelLocal(g_V[v].Type, wheel, local);
		VehiclePoint(start, oldAngles, local, a);
		// Cover the small rotation arc between straight trace segments.
		float pad = 0.25 + GetVectorLength(local) * segmentTurn * segmentTurn * 0.125;
		for (int axis = 0; axis < 3; axis++) {
			mins[axis] = -pad;
			maxs[axis] = pad;
		}
		for (int segment = 1; segment <= segments; segment++) {
			float t = float(segment) / float(segments), position[3], angles[3], b[3];
			for (int axis = 0; axis < 3; axis++) {
				position[axis] = start[axis] + (finish[axis] - start[axis]) * t;
				angles[axis] = oldAngles[axis] + NormalizeYaw(newAngles[axis] - oldAngles[axis]) * t;
			}
			VehiclePoint(position, angles, local, b);
			Handle trace = TR_TraceHullFilterEx(a, b, mins, maxs, MASK_SOLID, FilterDriving, v);
			g_V[v].BodyTraces++;
			bool solid = TR_StartSolid(trace) || TR_AllSolid(trace);
			if (solid || TR_DidHit(trace)) {
				float hit = solid ? 0.0 : (float(segment - 1) + TR_GetFraction(trace)) / float(segments);
				if (solid || hit < fraction) {
					fraction = hit;
					g_V[v].LastBlockEntity = TR_GetEntityIndex(trace);
					strcopy(g_V[v].LastBlockReason, sizeof(g_V[v].LastBlockReason), solid ? "wheel starts solid" : "wheel obstructed");
					if (!solid)
						TR_GetPlaneNormal(trace, normal);
				}
				delete trace;
				if (solid)
					return false;
				break;
			}
			delete trace;
			a = b;
		}
	}
	return true;
}

bool SweepVehicleWheels(int v, const float start[3], const float finish[3], const float oldAngles[3], const float newAngles[3]) {
	float fraction, normal[3];
	return TraceVehicleWheels(v, start, finish, oldAngles, newAngles, fraction, normal) && fraction >= 1.0;
}

// A small upward recovery is allowed only over a drivable surface, never through a wall.
bool RecoverVehicleSupport(int v, int vehicle, const float origin[3], const float angles[3]) {
	for (float lift = 2.0; lift <= g_Types[g_V[v].Type].StepHeight; lift += 4.0) {
		float top[3], fraction, surface;
		top = origin;
		top[2] += lift;
		if (!SweepBody(v, top, top, angles, angles) || !SweepVehicleWheels(v, top, top, angles, angles))
			continue;
		if (!TraceBody(v, top, origin, angles, angles, fraction, surface, true) || fraction >= 1.0)
			return false;
		top[2] = surface + 1.0;
		if (!SweepBody(v, top, top, angles, angles) || !SweepVehicleWheels(v, top, top, angles, angles))
			continue;
		MoveContinuous(vehicle, top, angles);
		g_V[v].RampRecoveries++;
		return true;
	}
	return false;
}

bool SplitBodyCell(int v, const float start[3], const float finish[3], const float oldAngles[3], const float newAngles[3],
	const float center[3], const float half[3], int axis, int depth, float &fraction, float &surface, bool landing) {
	float childHalf[3], child[3];
	childHalf = half;
	childHalf[axis] *= 0.5;
	for (int side = -1; side <= 1; side += 2) {
		child = center;
		child[axis] += float(side) * childHalf[axis];
		if (!TraceBodyCell(v, start, finish, oldAngles, newAngles, child, childHalf, depth + 1, fraction, surface, landing))
			return false;
	}
	return true;
}

bool TraceBodyCell(int v, const float start[3], const float finish[3], const float oldAngles[3], const float newAngles[3],
	const float center[3], const float half[3], int depth, float &fraction, float &surface, bool landing) {
	float bounds[3], splitWeight[2];
	for (int sample = 0; sample < 3; sample++) {
		float angles[3], axis[3][3];
		for (int i = 0; i < 3; i++)
			angles[i] = oldAngles[i] + NormalizeYaw(newAngles[i] - oldAngles[i]) * float(sample) * 0.5;
		GetAngleVectors(angles, axis[0], axis[1], axis[2]);
		for (int i = 0; i < 3; i++) {
			float extent;
			for (int j = 0; j < 3; j++)
				extent += FloatAbs(axis[j][i]) * half[j];
			bounds[i] = FloatMax(bounds[i], extent + 0.25);
		}
		for (int j = 0; j < 2; j++) {
			float weight;
			for (int i = 0; i < 3; i++)
				weight += FloatAbs(axis[2][i] * axis[j][i]) * half[j];
			splitWeight[j] = FloatMax(splitWeight[j], weight);
		}
	}
	float oldUp[3], newUp[3];
	GetAngleVectors(oldAngles, NULL_VECTOR, NULL_VECTOR, oldUp);
	GetAngleVectors(newAngles, NULL_VECTOR, NULL_VECTOR, newUp);
	float oldBottom = center[2], newBottom = center[2];
	for (int i = 0; i < 3; i++) {
		oldBottom -= FloatAbs(oldUp[i]) * bounds[i];
		newBottom -= FloatAbs(newUp[i]) * bounds[i];
	}
	// Split only where an axis-aligned proxy would bite into a drivable hillside.
	if (depth < 8 && FloatMin(oldBottom, newBottom) < 3.0) {
		int axis = splitWeight[0] > splitWeight[1] ? 0 : 1;
		return SplitBodyCell(v, start, finish, oldAngles, newAngles, center, half, axis, depth, fraction, surface, landing);
	}
	float a[3], b[3], mins[3];
	VehiclePoint(start, oldAngles, center, a);
	VehiclePoint(finish, newAngles, center, b);
	for (int i = 0; i < 3; i++)
		mins[i] = -bounds[i];
	Handle trace = TR_TraceHullFilterEx(a, b, mins, bounds, MASK_SOLID, FilterDriving, v);
	g_V[v].BodyTraces++;
	bool solid = TR_StartSolid(trace) || TR_AllSolid(trace);
	if (solid || TR_DidHit(trace)) {
		if (depth < 8) {
			delete trace;
			return SplitBodyCell(v, start, finish, oldAngles, newAngles, center, half, half[0] > half[1] ? 0 : 1, depth, fraction, surface, landing);
		}
		g_V[v].LastBlockEntity = TR_GetEntityIndex(trace);
		if (!landing || solid) {
			strcopy(g_V[v].LastBlockReason, sizeof(g_V[v].LastBlockReason), solid ? "body starts solid" : "body obstructed");
			delete trace;
			return false;
		}
		float normal[3], point[3];
		TR_GetPlaneNormal(trace, normal);
		TR_GetEndPosition(point, trace);
		if (normal[2] < g_Types[g_V[v].Type].GroundZ) {
			strcopy(g_V[v].LastBlockReason, sizeof(g_V[v].LastBlockReason), "step landing too steep");
			delete trace;
			return false;
		}
		fraction = FloatMin(fraction, TR_GetFraction(trace));
		float offset[3];
		RotatedVector(newAngles, center, offset);
		surface = FloatMax(surface, point[2] - offset[2]);
	}
	delete trace;
	return true;
}

bool TraceATVRider(int v, const float start[3], const float finish[3], const float oldAngles[3], const float newAngles[3],
	float &fraction, float &surface, bool landing = false, int enteringSeat = -1) {
	float center[3] = {0.0, -8.0, 62.0};
	float half[3] = {18.0, 14.0, 21.0};
	if ((RiderInSeat(v, 0) != 0 || enteringSeat == 0)
		&& !TraceBodyCell(v, start, finish, oldAngles, newAngles, center, half, 0, fraction, surface, landing))
		return false;
	if (RiderInSeat(v, 1) == 0 && enteringSeat != 1)
		return true;
	center[1] = ATV_PASSENGER_REAR;
	center[2] = 63.0;
	half[0] = 22.0;
	half[1] = 20.0;
	if (!TraceBodyCell(v, start, finish, oldAngles, newAngles, center, half, 0, fraction, surface, landing))
		return false;
	center[1] = ATV_PASSENGER_REAR - 19.0;
	center[2] = 32.0;
	half[0] = 19.0;
	half[1] = 14.0;
	half[2] = 15.0;
	return TraceBodyCell(v, start, finish, oldAngles, newAngles, center, half, 0, fraction, surface, landing);
}

bool TraceBody(int v, const float start[3], const float finish[3], const float oldAngles[3], const float newAngles[3],
	float &fraction, float &surface, bool landing = false) {
	fraction = 1.0;
	surface = -999999.0;
	for (int section = -1; section <= 1; section++) {
		float floor = IsATV(v) ? (section == 0 ? 10.0 : ATV_STEP_HEIGHT + 1.0) : (section == 0 ? 20.0 : VEHICLE_STEP_HEIGHT + 1.0);
		float center[3], half[3];
		center[1] = section < 0 ? -72.0 : (section > 0 ? 75.0 : 0.0);
		center[2] = (85.0 + floor) * 0.5;
		half[0] = section == 0 ? 61.0 : 50.0;
		half[1] = section == 0 ? 43.0 : 37.0;
		half[2] = (85.0 - floor) * 0.5;
		if (IsATV(v)) {
			center[1] = float(section) * 31.0;
			center[2] = (49.0 + floor) * 0.5;
			half[0] = section == 0 ? 24.5 : 29.5;
			half[1] = section == 0 ? 14.0 : 17.0;
			half[2] = (49.0 - floor) * 0.5;
		}
		if (!TraceBodyCell(v, start, finish, oldAngles, newAngles, center, half, 0, fraction, surface, landing))
			return false;
	}
	if (IsATV(v) && Occupied(v))
		return TraceATVRider(v, start, finish, oldAngles, newAngles, fraction, surface, landing);
	return true;
}

bool SweepBody(int v, const float start[3], const float finish[3], const float oldAngles[3], const float newAngles[3]) {
	float fraction, surface;
	return TraceBody(v, start, finish, oldAngles, newAngles, fraction, surface);
}
void StartPlayerPush(int client, int vehicle, const float direction[3], float strength, float now) {
	if (!g_Push[client].Hooked) {
		SDKHook(client, SDKHook_PreThinkPost, Hook_PushPreThink);
		SDKHook(client, SDKHook_PostThinkPost, Hook_PushPostThink);
		g_Push[client].Hooked = true;
	}
	g_Push[client].VehicleRef = EntIndexToEntRef(vehicle);
	g_Push[client].Direction = direction;
	g_Push[client].Strength = strength;
	g_Push[client].EndsAt = now + VEHICLE_PUSH_DURATION;
}

void RestorePushBaseVelocity(int client) {
	if (!g_Push[client].Applied)
		return;
	g_Push[client].Applied = false;
	if (!IsClientInGame(client))
		return;
	float base[3];
	GetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", base);
	// Restore only the horizontal values we wrote, leaving engine/other-plugin changes alone.
	for (int axis = 0; axis < 2; axis++) {
		if (base[axis] == g_Push[client].Written[axis])
			base[axis] = g_Push[client].Previous[axis];
	}
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", base);
}

void StopPlayerPush(int client) {
	if (!g_Push[client].Hooked)
		return;
	RestorePushBaseVelocity(client);
	if (IsClientInGame(client)) {
		SDKUnhook(client, SDKHook_PreThinkPost, Hook_PushPreThink);
		SDKUnhook(client, SDKHook_PostThinkPost, Hook_PushPostThink);
	}
	PlayerPushState blank;
	g_Push[client] = blank;
}

public void Hook_PushPreThink(int client) {
	RestorePushBaseVelocity(client);
	int v = VehicleByRef(g_Push[client].VehicleRef);
	float remaining = g_Push[client].EndsAt - GetGameTime();
	if (g_EndingMap || v == -1 || !IsPlayerAlive(client) || g_R[client].Vehicle != -1
		|| remaining <= 0.0 || GetEntityMoveType(client) != MOVETYPE_WALK || (GetEntityFlags(client) & FL_FROZEN)) {
		StopPlayerPush(client);
		return;
	}
	float base[3], velocity[3], direction[3];
	GetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", base);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	g_Push[client].Previous = base;
	direction = g_Push[client].Direction;
	AddVectors(velocity, base, velocity);
	float fade = FloatMin(1.0, remaining / (VEHICLE_PUSH_DURATION * 0.5));
	float impulse = FloatMax(0.0, g_Push[client].Strength * fade - GetVectorDotProduct(velocity, direction));
	for (int axis = 0; axis < 2; axis++)
		base[axis] += direction[axis] * impulse;
	g_Push[client].Written = base;
	g_Push[client].Applied = true;
	// WalkMove adds base velocity after its walking-speed cap. Scope it to this movement step.
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", base);
	g_V[v].PushSteps++;
}

public void Hook_PushPostThink(int client) {
	RestorePushBaseVelocity(client);
}

bool VehiclePlayerContacts(int v, int vehicle, const float start[3], const float finish[3], const float oldAngles[3], const float angles[3]) {
	int driver = DrivingClient(v);
	if (driver == 0 || !HumanAlive(driver) || g_V[v].Health <= 0.0)
		return true;
	int team = GetClientTeam(driver);
	if (team <= 1)
		return true;
	int reference = g_V[v].VehicleRef;
	int driverUserId = GetClientUserId(driver);
	float speed = FloatAbs(g_V[v].Speed);
	float now = GetGameTime();
	float delta[3], side[3], movement[3];
	SubtractVectors(finish, start, delta);
	float step = GetVectorLength(delta);
	if (step < 0.001)
		return true;
	movement = delta;
	movement[2] = 0.0;
	NormalizeVector(movement, movement);
	GetAngleVectors(angles, side, NULL_VECTOR, NULL_VECTOR);
	side[2] = 0.0;
	NormalizeVector(side, side);
	// Enclose the small rotation during this step as well as the translated sweep.
	float rotation = FloatAbs(NormalizeYaw(angles[0] - oldAngles[0]))
		+ FloatAbs(NormalizeYaw(angles[1] - oldAngles[1])) + FloatAbs(NormalizeYaw(angles[2] - oldAngles[2]));
	float padding = (IsATV(v) ? 75.0 : 160.0) * DegToRad(rotation);
	float radius = (IsATV(v) ? 135.0 : 220.0) + step + padding + VEHICLE_PUSH_LOOKAHEAD;
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || g_R[client].Vehicle != -1 || GetClientTeam(client) <= 1)
			continue;
		MoveType moveType = GetEntityMoveType(client);
		if (moveType != MOVETYPE_WALK)
			continue;
		int userid = GetClientUserId(client);
		if (g_V[v].ImpactUserId[client] == userid && now < g_V[v].NextImpact[client])
			continue;
		float position[3];
		GetClientAbsOrigin(client, position);
		if (GetVectorDistance(position, finish, true) > radius * radius)
			continue;
		float mins[3], maxs[3], sweepMins[3], sweepMaxs[3], relativeStart[3];
		GetClientMins(client, mins);
		GetClientMaxs(client, maxs);
		for (int axis = 0; axis < 3; axis++) {
			sweepMins[axis] = mins[axis] - padding;
			sweepMaxs[axis] = maxs[axis] + padding;
			relativeStart[axis] = position[axis] - delta[axis] - movement[axis] * VEHICLE_PUSH_LOOKAHEAD;
		}
		Handle trace = TR_ClipRayHullToEntityEx(position, relativeStart, sweepMins, sweepMaxs, MASK_PLAYERSOLID, vehicle);
		bool hit = TR_DidHit(trace) || TR_StartSolid(trace) || TR_AllSolid(trace);
		delete trace;
		if (!hit)
			continue;
		g_V[v].ImpactContacts++;
		float center[3], contact[3];
		center = position;
		center[2] += (mins[2] + maxs[2]) * 0.5;
		contact = start;
		contact[2] += ClampFloat(center[2] - start[2], IsATV(v) ? 12.0 : 20.0, IsATV(v) ? 45.0 : 80.0);
		trace = TR_TraceRayFilterEx(contact, center, MASK_SOLID, RayType_EndPoint, FilterDriving, v);
		bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
		delete trace;
		if (!clear)
			continue;
		g_V[v].ImpactUserId[client] = userid;
		g_V[v].NextImpact[client] = now + VEHICLE_IMPACT_INTERVAL;
		float offset[3];
		SubtractVectors(position, finish, offset);
		float lateral = GetVectorDotProduct(offset, side);
		float sign = lateral < 0.0 ? -1.0 : 1.0;
		float push[3];
		float sideways = speed * VEHICLE_IMPACT_PUSH_SCALE * 0.6;
		// Match and slightly exceed the car's forward/reverse motion while sliding to the side.
		for (int axis = 0; axis < 2; axis++)
			push[axis] = side[axis] * sign * sideways + movement[axis] * speed * 1.1;
		float strength = NormalizeVector(push, push);
		strength = FloatMin(strength, VEHICLE_IMPACT_MAX_PUSH);
		StartPlayerPush(client, vehicle, push, strength, now);
		g_V[v].ImpactPushes++;
		if (strength > 0.0 && IsFakeClient(client) && GetClientTeam(client) != team) {
			// Scope death attribution to this damage call, including nested damage callbacks.
			int previousVictim = g_ImpactVictimUserId;
			int previousAttacker = g_ImpactAttackerUserId;
			int previousType = g_ImpactVehicleType;
			g_ImpactVictimUserId = userid;
			g_ImpactAttackerUserId = driverUserId;
			g_ImpactVehicleType = g_V[v].Type;
			SDKHooks_TakeDamage(client, vehicle, driver, VEHICLE_IMPACT_BOT_DAMAGE, DMG_VEHICLE, -1, NULL_VECTOR, center, false);
			g_ImpactVictimUserId = previousVictim;
			g_ImpactAttackerUserId = previousAttacker;
			g_ImpactVehicleType = previousType;
			// A kill can end the round, remove the vehicle, or eject its driver.
			if (g_EndingMap || g_V[v].VehicleRef != reference || Vehicle(v) != vehicle || g_V[v].Health <= 0.0
				|| DrivingClient(v) != driver || !HumanAlive(driver) || GetClientUserId(driver) != driverUserId
				|| GetClientTeam(driver) != team)
				return false;
		}
	}
	return true;
}
void CacheSecuritySpawns() {
	if (g_SecuritySpawns != null)
		return;
	g_SecuritySpawns = new ArrayList(3);
	int entity = -1;
	float origin[3];
	while ((entity = FindEntityByClassname(entity, "ins_spawnpoint")) != -1) {
		if (GetEntProp(entity, Prop_Data, "m_iTeamNum") != 2)
			continue;
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
		g_SecuritySpawns.PushArray(origin, 3);
	}
}

bool SecuritySpawnClear(const float origin[3], float yaw, int client = 0, int type = VEHICLE_HUMVEE) {
	CacheSecuritySpawns();
	float radians = DegToRad(yaw);
	float ca = Cosine(radians), sa = Sine(radians);
	float padding = 24.0 * (FloatAbs(ca) + FloatAbs(sa));
	float spawn[3];
	for (int i = 0; i < g_SecuritySpawns.Length; i++) {
		g_SecuritySpawns.GetArray(i, spawn, 3);
		if (spawn[2] + 72.0 < origin[2] || spawn[2] > origin[2] + g_Types[type].Height)
			continue;
		float dx = spawn[0] - origin[0], dy = spawn[1] - origin[1];
		if (FloatAbs(ca * dx + sa * dy) > g_Types[type].HalfWidth + padding || FloatAbs(-sa * dx + ca * dy) > g_Types[type].HalfLength + padding)
			continue;
		strcopy(g_PlacementReason, sizeof(g_PlacementReason), "vehicle overlaps a Security spawn point");
		if (client > 0)
			PrintToChat(client, "[Vehicles] Placement overlaps a Security spawn point. Move the vehicle farther away.");
		return false;
	}
	return true;
}
bool PlacementGround(const float origin[3], float yaw, float heights[4], int ignore, int type = VEHICLE_HUMVEE) {
	float lowest = 999999.0, highest = -999999.0;
	for (int wheel = 0; wheel < 4; wheel++) {
		float local[3], top[3], bottom[3], point[3], normal[3];
		WheelLocal(type, wheel, local);
		LocalPoint(origin, yaw, local, top);
		bottom = top;
		top[2] += 20.0;
		bottom[2] -= 32.0;
		Handle trace = TR_TraceRayFilterEx(top, bottom, MASK_SOLID, RayType_EndPoint, FilterPlacement, ignore);
		bool hit = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
		if (hit) {
			TR_GetEndPosition(point, trace);
			TR_GetPlaneNormal(trace, normal);
		}
		delete trace;
		if (!hit || normal[2] < g_Types[type].GroundZ) {
			Format(g_PlacementReason, sizeof(g_PlacementReason), "wheel %d has %s", wheel + 1, !hit ? "no nearby supporting ground" : "ground that is too steep");
			return false;
		}
		heights[wheel] = point[2];
		lowest = FloatMin(lowest, point[2]);
		highest = FloatMax(highest, point[2]);
	}
	if (highest - lowest > g_Types[type].Suspension) {
		Format(g_PlacementReason, sizeof(g_PlacementReason), "ground varies by %.0f units under the wheels (maximum %.0f)", highest - lowest, g_Types[type].Suspension);
		return false;
	}
	return true;
}

bool SettlePlacement(float origin[3], float yaw, int ignore = -1, int type = VEHICLE_HUMVEE) {
	float heights[4];
	if (!PlacementGround(origin, yaw, heights, ignore, type))
		return false;
	origin[2] = heights[0] + 1.0;
	for (int wheel = 1; wheel < 4; wheel++)
		origin[2] = FloatMax(origin[2], heights[wheel] + 1.0);
	return true;
}

bool PlacementCell(const float origin[3], float yaw, const float center[3], const float half[3], int ignore, int depth = 0) {
	float ca = FloatAbs(Cosine(DegToRad(yaw))), sa = FloatAbs(Sine(DegToRad(yaw)));
	float position[3], mins[3], maxs[3];
	LocalPoint(origin, yaw, center, position);
	maxs[0] = ca * half[0] + sa * half[1];
	maxs[1] = sa * half[0] + ca * half[1];
	maxs[2] = half[2];
	for (int i = 0; i < 3; i++)
		mins[i] = -maxs[i];
	Handle trace = TR_TraceHullFilterEx(position, position, mins, maxs, MASK_SOLID, FilterPlacement, ignore);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	int hit = clear ? -1 : TR_GetEntityIndex(trace);
	delete trace;
	if (clear)
		return true;
	if (depth < 4 && ca * sa > 0.01) {
		int axis = half[0] > half[1] ? 0 : 1;
		float child[3], size[3];
		size = half;
		size[axis] *= 0.5;
		for (int side = -1; side <= 1; side += 2) {
			child = center;
			child[axis] += float(side) * size[axis];
			if (!PlacementCell(origin, yaw, child, size, ignore, depth + 1))
				return false;
		}
		return true;
	}
	if (hit > 0 && hit <= MaxClients)
		strcopy(g_PlacementReason, sizeof(g_PlacementReason), "a player is inside the vehicle's space");
	else if (hit > MaxClients && IsValidEntity(hit)) {
		char classname[64];
		GetEntityClassname(hit, classname, sizeof(classname));
		Format(g_PlacementReason, sizeof(g_PlacementReason), "the body or a wheel overlaps %s", classname);
	} else
		strcopy(g_PlacementReason, sizeof(g_PlacementReason), "the body or a wheel overlaps map geometry");
	return false;
}

bool PlacementClear(const float origin[3], float yaw, int ignore = -1, int type = VEHICLE_HUMVEE) {
	float heights[4];
	if (!PlacementGround(origin, yaw, heights, ignore, type))
		return false;
	for (int wheel = 0; wheel < 4; wheel++) {
		float gap = origin[2] - 1.0 - heights[wheel];
		if (gap < -0.1 || gap > g_Types[type].Suspension + 0.1) {
			strcopy(g_PlacementReason, sizeof(g_PlacementReason), "move the vehicle onto supported ground before saving");
			return false;
		}
	}
	if (type == VEHICLE_ATV)
		return ATVPlacementBody(origin, yaw, ignore, heights);
	// Raised underbody, hood and cabin volumes leave the real ground clearance open.
	float centers[6][3] = {{0.0, -7.0, 53.0}, {0.0, 75.0, 42.5}, {0.0, -80.0, 48.5},
		{0.0, 0.0, 25.0}, {0.0, -108.0, 22.0}, {0.0, 108.0, 22.0}};
	float halves[6][3] = {{48.0, 47.0, 32.0}, {45.5, 39.0, 18.5}, {46.5, 30.0, 24.5},
		{43.0, 102.0, 4.0}, {48.0, 8.0, 7.0}, {48.0, 8.0, 7.0}};
	for (int section = 0; section < 6; section++) {
		if (!PlacementCell(origin, yaw, centers[section], halves[section], ignore))
			return false;
	}
	float tireHalf[3][3] = {{10.0, 5.0, 2.0}, {11.0, 17.0, 6.0}, {11.0, 20.0, 11.0}};
	float tireHeight[3] = {5.0, 12.0, 29.0};
	for (int wheel = 0; wheel < 4; wheel++) {
		float center[3];
		center[0] = wheel % 2 ? 40.79 : -41.74;
		center[1] = wheel < 2 ? 76.93 : -71.84;
		for (int layer = 0; layer < 3; layer++) {
			center[2] = tireHeight[layer] - (origin[2] - 1.0 - heights[wheel]);
			if (!PlacementCell(origin, yaw, center, tireHalf[layer], ignore))
				return false;
		}
	}
	return true;
}

bool ATVPlacementBody(const float origin[3], float yaw, int ignore, const float heights[4]) {
	float centers[7][3] = {{0.0, 0.0, 22.0}, {0.0, 28.0, 30.0}, {0.0, -28.0, 30.0},
		{0.0, -3.0, 15.0}, {0.0, 8.0, 44.0}, {0.0, 46.0, 23.0}, {0.0, -46.0, 27.0}};
	float halves[7][3] = {{12.5, 34.0, 10.5}, {29.0, 14.0, 5.0}, {29.0, 14.0, 5.0},
		{24.0, 12.0, 1.5}, {18.0, 8.0, 4.0}, {20.0, 2.0, 3.0}, {19.0, 2.0, 3.0}};
	for (int section = 0; section < 7; section++) {
		if (!PlacementCell(origin, yaw, centers[section], halves[section], ignore))
			return false;
	}
	float tireHalf[3][3] = {{4.0, 5.0, 1.5}, {5.0, 10.0, 4.0}, {5.5, 12.5, 7.5}};
	float tireHeight[3] = {3.0, 8.0, 18.0};
	for (int wheel = 0; wheel < 4; wheel++) {
		float center[3];
		WheelLocal(VEHICLE_ATV, wheel, center);
		for (int layer = 0; layer < 3; layer++) {
			center[2] = tireHeight[layer] - (origin[2] - 1.0 - heights[wheel]);
			if (!PlacementCell(origin, yaw, center, tireHalf[layer], ignore))
				return false;
		}
	}
	return true;
}

void SetPlacementWheels(int entity, const float origin[3], float yaw, int type = VEHICLE_HUMVEE) {
	float heights[4];
	if (!PlacementGround(origin, yaw, heights, entity, type))
		return;
	for (int wheel = 0; wheel < 4; wheel++)
		SetEntPropFloat(entity, Prop_Send, "m_flPoseParameter", ClampFloat((origin[2] - 1.0 - heights[wheel]) / g_Types[type].WheelTravel, 0.0, 1.0), wheel * 2);
}
bool IsVehicleAdmin(int client) {
	return client > 0 && IsClientInGame(client) && CheckCommandAccess(client, "sm_vehicles", ADMFLAG_RCON);
}

public Action Command_AdminVehicles(int client, int args) {
	if (IsVehicleAdmin(client))
		ShowAdminMenu(client);
	return Plugin_Handled;
}

void ShowAdminMenu(int client) {
	CacheSecuritySpawns();
	Menu menu = new Menu(AdminMenuHandler);
	menu.SetTitle("Vehicle admin | %d/%d live | %d saved", g_Count, MAX_VEHICLES, g_SavedCount);
	menu.AddItem("spawn", "Spawn vehicle now (temporary)");
	menu.AddItem("place", "Place vehicle and save for this map", g_ConfigReady ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("near", "Manage nearest vehicle");
	menu.AddItem("live", "Browse live vehicles");
	menu.AddItem("saved", "Saved map placements");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int AdminMenuHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[24];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "spawn") || StrEqual(info, "place")) {
			ShowVehicleTypeMenu(client, StrEqual(info, "place"));
			return 0;
		} else if (StrEqual(info, "near")) {
			int v = NearestVehicle(client);
			if (v != -1) {
				ShowLiveMenu(client, v);
				return 0;
			}
			PrintToChat(client, "[Vehicles] No vehicle within 300 units.");
		} else if (StrEqual(info, "live")) {
			ShowLiveList(client);
			return 0;
		} else if (StrEqual(info, "saved")) {
			ShowSavedList(client);
			return 0;

		}
		ShowAdminMenu(client);
	}
	return 0;
}

int NearestVehicle(int client) {
	float eye[3], origin[3], best = 90000.0;
	GetClientEyePosition(client, eye);
	int found = -1;
	for (int v = 0; v < MAX_VEHICLES; v++) {
		int entity = Vehicle(v);
		if (entity == -1)
			continue;
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
		float distance = GetVectorDistance(eye, origin, true);
		if (distance < best) {
			best = distance;
			found = v;
		}
	}
	return found;
}

void ShowLiveList(int client) {
	Menu menu = new Menu(LiveListHandler);
	menu.SetTitle("Live vehicles");
	for (int v = 0; v < MAX_VEHICLES; v++) {
		int entity = Vehicle(v);
		if (entity == -1)
			continue;
		char info[64], label[96];
		Format(info, sizeof(info), "%d %d", g_MapSerial, g_V[v].VehicleRef);
		Format(label, sizeof(label), "%s #%d | HP %.0f | %s%s", g_TypeNames[g_V[v].Type], v + 1, g_V[v].Health,
			g_V[v].SavedId > 0 ? "saved" : "temporary", g_V[v].Health <= 0.0 ? " | destroyed" : (Occupied(v) ? " | occupied" : ""));
		menu.AddItem(info, label);
	}
	if (menu.ItemCount == 0)
		menu.AddItem("", "None. Back > Spawn vehicle now", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int LiveListHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && IsVehicleAdmin(client))
		ShowAdminMenu(client);
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[64], parts[2][24];
		menu.GetItem(item, info, sizeof(info));
		ExplodeString(info, " ", parts, 2, 24);
		int v = VehicleByRef(StringToInt(parts[1]));
		if (StringToInt(parts[0]) == g_MapSerial && Vehicle(v) != -1)
			ShowLiveMenu(client, v);
		else
			ShowLiveList(client);
	}
	return 0;
}

void AddLiveItem(Menu menu, int v, const char[] action, const char[] text, bool enabled = true) {
	char info[80];
	Format(info, sizeof(info), "%d %d %s", g_MapSerial, g_V[v].VehicleRef, action);
	menu.AddItem(info, text, enabled ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
}

void ShowLiveMenu(int client, int v) {
	if (Vehicle(v) == -1) {
		ShowLiveList(client);
		return;
	}
	Menu menu = new Menu(LiveMenuHandler);
	bool destroyed = g_V[v].Health <= 0.0;
	menu.SetTitle("%s #%d | HP %.0f/%.0f | %s", g_TypeNames[g_V[v].Type], v + 1, g_V[v].Health, g_Types[g_V[v].Type].Health,
		destroyed ? (g_V[v].WreckHidden ? "wreck cleared" : "destroyed") : (Occupied(v) ? "occupied" : "empty"));
	AddLiveItem(menu, v, "move", "Move to open space ahead", !Occupied(v) && !destroyed);
	AddLiveItem(menu, v, "left", "Rotate left 15 degrees", !Occupied(v) && !destroyed);
	AddLiveItem(menu, v, "right", "Rotate right 15 degrees", !Occupied(v) && !destroyed);
	AddLiveItem(menu, v, "save", g_V[v].SavedId > 0 ? "Save current position as its home" : "Save this vehicle for this map", g_ConfigReady && !Occupied(v) && !destroyed);
	AddLiveItem(menu, v, destroyed ? "respawn" : "repair", destroyed ? "Respawn vehicle here (checks clearance)" : "Repair to full health");
	AddLiveItem(menu, v, "remove", "Remove live vehicle (saved home kept)");
	AddLiveItem(menu, v, "status", "Print vehicle status to console");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int LiveMenuHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && IsVehicleAdmin(client))
		ShowAdminMenu(client);
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[80], parts[3][24];
		menu.GetItem(item, info, sizeof(info));
		ExplodeString(info, " ", parts, 3, 24);
		int v = VehicleByRef(StringToInt(parts[1]));
		int entity = Vehicle(v);
		if (StringToInt(parts[0]) != g_MapSerial || entity == -1) {
			PrintToChat(client, "[Vehicles] That vehicle is no longer available.");
			ShowAdminMenu(client);
			return 0;
		}
		if (StrEqual(parts[2], "remove")) {
			Menu confirm = new Menu(ConfirmRemoveHandler);
			confirm.SetTitle("Remove %s #%d? Occupants will be safely ejected.", g_TypeNames[g_V[v].Type], v + 1);
			confirm.AddItem(info, "Yes, remove live vehicle");
			confirm.AddItem("cancel", "Cancel");
			confirm.Display(client, MENU_TIME_FOREVER);
			return 0;
		}
		if (StrEqual(parts[2], "respawn")) {
			if (g_V[v].Health > 0.0)
				PrintToChat(client, "[Vehicles] This vehicle is already working.");
			else if (RespawnVehicle(v, client))
				PrintToChat(client, "[Vehicles] Vehicle respawned. Saved home unchanged.");
			else
				PrintToChat(client, "[Vehicles] Cannot respawn: %s.", g_PlacementReason);
		} else if (StrEqual(parts[2], "repair") && g_V[v].Health > 0.0) {
			g_V[v].Health = g_Types[g_V[v].Type].Health;
			UpdateVehicleSkin(v, entity);
			UpdateVehicleDamageEffects(v, entity);
			PrintToChat(client, "[Vehicles] Vehicle repaired.");
		} else if (StrEqual(parts[2], "status")) {
			PrintToConsole(client, "[Vehicles] v%s %s #%d entity=%d saved=%d HP=%.0f speed=%.1f steer=%.2f input=%d", PLUGIN_VERSION,
				g_TypeNames[g_V[v].Type], v + 1, entity, g_V[v].SavedId, g_V[v].Health, g_V[v].Speed, g_V[v].Steering, g_V[v].DriveButtons);
			PrintToConsole(client, "[Vehicles] blocked=%d ground=%d hull=%d reason='%s' curb steps=%d", g_V[v].BlockedMoves,
				g_V[v].GroundBlocks, g_V[v].HullBlocks, g_V[v].LastBlockReason, g_V[v].CurbSteps);
			PrintToConsole(client, "[Vehicles] swept player contacts=%d applied pushes=%d external push steps=%d", g_V[v].ImpactContacts, g_V[v].ImpactPushes, g_V[v].PushSteps);
			PrintToConsole(client, "[Vehicles] destroyed=%d wreck cleared=%d | loose debris=%d/%d server-wide", g_V[v].Destroyed, g_V[v].WreckHidden, CountVehicleDebris(), VEHICLE_DEBRIS_LIMIT);
			if (g_V[v].Destroyed) {
				PrintToConsole(client, "[Vehicles] wreck original physics=%d removed=%d", g_V[v].WreckHadPhysics, g_V[v].WreckPhysicsRemoved);
				PrintToConsole(client, "[Vehicles] scripted debris spawned=%d blocked=%d failed=%d launched=%d moved=%d stopped by obstruction=%d max travel=%.1f",
					g_V[v].DebrisSpawned, g_V[v].DebrisBlocked, g_V[v].DebrisFailed, g_V[v].DebrisLaunched,
					g_V[v].DebrisMoved, g_V[v].DebrisFlightBlocked, g_V[v].DebrisTravel);
			}
			float tilt[3];
			GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", tilt);
			PrintToConsole(client, "[Vehicles] airborne=%d wheel contacts=%d vertical speed=%.1f jumps=%d landings=%d ramp recoveries=%d", g_V[v].Airborne, g_V[v].SupportCount, g_V[v].FlightVelocity[2], g_V[v].Jumps, g_V[v].Landings, g_V[v].RampRecoveries);
			PrintToConsole(client, "[Vehicles] pitch=%.1f roll=%.1f body traces last move=%d | Security spawns cached=%d", tilt[0], tilt[2], g_V[v].BodyTraces, g_SecuritySpawns == null ? -1 : g_SecuritySpawns.Length);
			for (int s = 0; s < VehicleSeats(v); s++)
				PrintToConsole(client, "[Vehicles] seat %s: userid=%d", IsATV(v) && s == 1 ? "Armed rear passenger" : g_SeatNames[s], g_V[v].Occupants[s]);
			PrintToChat(client, "[Vehicles] Status printed to your console.");
		} else if (g_V[v].Health <= 0.0)
			PrintToChat(client, "[Vehicles] This vehicle is destroyed. Use Respawn vehicle to restore it when the area is clear.");
		else if (Occupied(v))
			PrintToChat(client, "[Vehicles] Everyone must exit before moving, rotating or saving the vehicle.");
		else if (StrEqual(parts[2], "save")) {
			if (SaveLivePlacement(v, client))
				PrintToChat(client, "[Vehicles] Home position saved for this map.");
			else
				PrintToChat(client, "[Vehicles] Save failed. Previous placements kept; check server errors.");
		} else {
			float origin[3], angles[3];
			GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
			GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", angles);
			bool ok;
			if (StrEqual(parts[2], "move"))
				ok = AdminPlacement(client, origin, angles[1], entity, g_V[v].Type);
			else {
				angles[1] = NormalizeYaw(angles[1] + (StrEqual(parts[2], "left") ? 15.0 : -15.0));
				ok = SettlePlacement(origin, angles[1], entity, g_V[v].Type) && PlacementClear(origin, angles[1], entity, g_V[v].Type) && SecuritySpawnClear(origin, angles[1], client, g_V[v].Type);
			}
			if (ok) {
				angles[0] = angles[2] = 0.0;
				StopEngine(v);
				TeleportEntity(entity, origin, angles, NULL_VECTOR);
				SetPlacementWheels(entity, origin, angles[1], g_V[v].Type);
				PrintToChat(client, "[Vehicles] Position changed. Use Save current position to update its saved home.");
			} else
				PrintToChat(client, "[Vehicles] Vehicle kept in place: %s.", g_PlacementReason);
		}
		ShowLiveMenu(client, v);
	}
	return 0;
}

public int ConfirmRemoveHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[80], parts[3][24];
		menu.GetItem(item, info, sizeof(info));
		if (!StrEqual(info, "cancel")) {
			ExplodeString(info, " ", parts, 3, 24);
			int v = VehicleByRef(StringToInt(parts[1]));
			if (StringToInt(parts[0]) == g_MapSerial && v != -1)
				RemoveVehicle(v);
		}
		ShowAdminMenu(client);
	}
	return 0;
}

int SavedIndex(int id) {
	for (int i = 0; i < g_SavedCount; i++) {
		if (g_Saved[i].Id == id)
			return i;
	}
	return -1;
}

int LiveForSaved(int id) {
	for (int v = 0; v < MAX_VEHICLES; v++) {
		if (Vehicle(v) != -1 && g_V[v].SavedId == id)
			return v;
	}
	return -1;
}

void SpawnSavedPlacements() {
	if (g_EndingMap || !g_ConfigReady)
		return;
	for (int i = 0; i < g_SavedCount; i++) {
		if (LiveForSaved(g_Saved[i].Id) != -1)
			continue;
		if (SpawnVehicle(g_Saved[i].Origin, g_Saved[i].Yaw, g_Saved[i].Id, -1, g_Saved[i].Type) == -1)
			LogMessage("Saved vehicle %d skipped: blocked position, unsupported ground or entity limit.", g_Saved[i].Id);
	}
}

void LoadPlacements() {
	g_SavedCount = 0;
	g_NextSavedId = 1;
	g_ConfigReady = false;
	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	for (int i = 0; map[i]; i++) {
		if (!IsCharAlpha(map[i]) && !IsCharNumeric(map[i]) && map[i] != '-' && map[i] != '_')
			map[i] = '_';
	}
	BuildPath(Path_SM, path, sizeof(path), "configs/bm_vehicles");
	if (!DirExists(path) && !CreateDirectory(path, 511)) {
		LogError("Cannot create vehicle configuration directory: %s", path);
		return;
	}
	Format(g_ConfigPath, sizeof(g_ConfigPath), "%s/%s.cfg", path, map);
	if (!FileExists(g_ConfigPath)) {
		char backup[PLATFORM_MAX_PATH];
		Format(backup, sizeof(backup), "%s.bak", g_ConfigPath);
		if (FileExists(backup)) {
			if (!RenameFile(g_ConfigPath, backup)) {
				LogError("Saved vehicle file missing; cannot restore backup %s. Saving disabled.", backup);
				return;
			}
			LogMessage("Recovered saved vehicles from %s", backup);
		} else {
			g_ConfigReady = true;
			return;
		}
	}
	KeyValues kv = new KeyValues("BMVehicles");
	bool ok = kv.ImportFromFile(g_ConfigPath);
	int count = kv.GetNum("count", -1);
	if (!ok || (kv.GetNum("version", 0) != 1 && kv.GetNum("version", 0) != 2) || count < 0 || count > MAX_VEHICLES) {
		delete kv;
		LogError("Invalid vehicle configuration, saving disabled to protect it: %s", g_ConfigPath);
		return;
	}
	for (int i = 0; i < count; i++) {
		char key[12];
		IntToString(i, key, sizeof(key));
		if (!kv.JumpToKey(key)) {
			ok = false;
			break;
		}
		char typeKey[32];
		kv.GetString("type", typeKey, sizeof(typeKey), "humvee");
		int type = -1;
		for (int t = 0; t < VEHICLE_TYPES; t++) {
			if (StrEqual(typeKey, g_TypeKeys[t]))
				type = t;
		}
		int id = kv.GetNum("id", 0);
		float origin[3], yaw;
		float missing[3] = {99999.0, 99999.0, 99999.0};
		kv.GetVector("origin", origin, missing);
		yaw = kv.GetFloat("yaw", 99999.0);
		if (type == -1 || id <= 0 || id > 1000000 || SavedIndex(id) != -1 || !ValidPosition(origin, yaw)) {
			ok = false;
			break;
		}
		g_Saved[i].Type = type;
		g_Saved[i].Id = id;
		g_Saved[i].Origin = origin;
		g_Saved[i].Yaw = yaw;
		g_SavedCount++;
		if (id >= g_NextSavedId)
			g_NextSavedId = id + 1;
		kv.GoBack();
	}
	delete kv;
	if (!ok) {
		g_SavedCount = 0;
		LogError("Invalid placement record; saving disabled: %s", g_ConfigPath);
		return;
	}
	g_ConfigReady = true;
}

bool ValidPosition(const float origin[3], float yaw) {
	for (int i = 0; i < 3; i++) {
		if (!(origin[i] >= -32768.0 && origin[i] <= 32768.0))
			return false;
	}
	return yaw >= -360.0 && yaw <= 360.0;
}

bool WritePlacements() {
	if (!g_ConfigReady)
		return false;
	KeyValues kv = new KeyValues("BMVehicles");
	kv.SetNum("version", 2);
	kv.SetNum("count", g_SavedCount);
	for (int i = 0; i < g_SavedCount; i++) {
		char key[12];
		IntToString(i, key, sizeof(key));
		kv.JumpToKey(key, true);
		kv.SetNum("id", g_Saved[i].Id);
		kv.SetString("type", g_TypeKeys[g_Saved[i].Type]);
		kv.SetVector("origin", g_Saved[i].Origin);
		kv.SetFloat("yaw", g_Saved[i].Yaw);
		kv.GoBack();
	}
	char temp[PLATFORM_MAX_PATH], backup[PLATFORM_MAX_PATH];
	Format(temp, sizeof(temp), "%s.tmp", g_ConfigPath);
	Format(backup, sizeof(backup), "%s.bak", g_ConfigPath);
	bool ok = kv.ExportToFile(temp);
	delete kv;
	if (!ok) {
		LogError("Cannot write vehicle placements: %s", temp);
		return false;
	}
	kv = new KeyValues("BMVehicles");
	ok = kv.ImportFromFile(temp) && kv.GetNum("count", -1) == g_SavedCount;
	delete kv;
	if (!ok)
		return false;
	bool hadOriginal = FileExists(g_ConfigPath);
	if (hadOriginal) {
		if (FileExists(backup) && !DeleteFile(backup))
			return false;
		if (!RenameFile(backup, g_ConfigPath))
			return false;
	}
	if (!RenameFile(g_ConfigPath, temp)) {
		if (hadOriginal && !RenameFile(g_ConfigPath, backup)) {
			LogError("Restore failed; original vehicle configuration retained at %s", backup);
			g_ConfigReady = false;
		}
		LogError("Cannot commit vehicle placements: %s", g_ConfigPath);
		return false;
	}
	return true;
}

bool SaveLivePlacement(int v, int client) {
	if (!g_ConfigReady || Occupied(v) || Vehicle(v) == -1)
		return false;
	float current[3], rotation[3];
	GetEntPropVector(Vehicle(v), Prop_Data, "m_vecAbsOrigin", current);
	GetEntPropVector(Vehicle(v), Prop_Data, "m_angAbsRotation", rotation);
	if (!PlacementClear(current, rotation[1], Vehicle(v), g_V[v].Type)) {
		PrintToChat(client, "[Vehicles] Cannot save here: %s.", g_PlacementReason);
		return false;
	}
	if (!SecuritySpawnClear(current, rotation[1], client, g_V[v].Type))
		return false;
	int index = SavedIndex(g_V[v].SavedId);
	bool adding = index == -1;
	if (adding && g_SavedCount == MAX_VEHICLES)
		return false;
	if (adding)
		index = g_SavedCount++;
	Placement old;
	old = g_Saved[index];
	float angles[3];
	GetEntPropVector(Vehicle(v), Prop_Data, "m_vecAbsOrigin", g_Saved[index].Origin);
	GetEntPropVector(Vehicle(v), Prop_Data, "m_angAbsRotation", angles);
	g_Saved[index].Yaw = NormalizeYaw(angles[1]);
	g_Saved[index].Type = g_V[v].Type;
	g_Saved[index].Id = adding ? g_NextSavedId : g_V[v].SavedId;
	if (!WritePlacements()) {
		g_Saved[index] = old;
		if (adding)
			g_SavedCount--;
		return false;
	}
	g_V[v].SavedId = g_Saved[index].Id;
	if (adding)
		g_NextSavedId++;
	return true;
}

void ShowSavedList(int client) {
	Menu menu = new Menu(SavedListHandler);
	menu.SetTitle("Saved placements for this map");
	for (int i = 0; i < g_SavedCount; i++) {
		char info[64], label[96];
		Format(info, sizeof(info), "%d %d", g_MapSerial, g_Saved[i].Id);
		Format(label, sizeof(label), "%s home #%d | %.0f %.0f %.0f | %s", g_TypeNames[g_Saved[i].Type], g_Saved[i].Id, g_Saved[i].Origin[0],
			g_Saved[i].Origin[1], g_Saved[i].Origin[2], LiveForSaved(g_Saved[i].Id) == -1 ? "not spawned" : "spawned");
		menu.AddItem(info, label);
	}
	if (menu.ItemCount == 0)
		menu.AddItem("", "None. Back > Place vehicle and save", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SavedListHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && IsVehicleAdmin(client))
		ShowAdminMenu(client);
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[64], parts[2][24];
		menu.GetItem(item, info, sizeof(info));
		ExplodeString(info, " ", parts, 2, 24);
		int id = StringToInt(parts[1]);
		if (StringToInt(parts[0]) != g_MapSerial || SavedIndex(id) == -1) {
			ShowSavedList(client);
			return 0;
		}
		Menu actions = new Menu(SavedActionHandler);
		actions.SetTitle("Saved home #%d", id);
		char key[80];
		Format(key, sizeof(key), "%s spawn", info);
		actions.AddItem(key, "Spawn at saved home if absent", LiveForSaved(id) == -1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		Format(key, sizeof(key), "%s manage", info);
		actions.AddItem(key, "Manage its live vehicle", LiveForSaved(id) != -1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		Format(key, sizeof(key), "%s delete", info);
		actions.AddItem(key, "Delete saved home (live vehicle stays)");
		actions.ExitBackButton = true;
		actions.Display(client, MENU_TIME_FOREVER);
	}
	return 0;
}

public int SavedActionHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && IsVehicleAdmin(client))
		ShowSavedList(client);
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[80], parts[3][24];
		menu.GetItem(item, info, sizeof(info));
		ExplodeString(info, " ", parts, 3, 24);
		int id = StringToInt(parts[1]);
		int index = SavedIndex(id);
		if (StringToInt(parts[0]) != g_MapSerial || index == -1) {
			ShowSavedList(client);
			return 0;
		}
		int v = LiveForSaved(id);
		if (StrEqual(parts[2], "manage") && v != -1) {
			ShowLiveMenu(client, v);
			return 0;
		}
		if (StrEqual(parts[2], "spawn") && v == -1) {
			if (SpawnVehicle(g_Saved[index].Origin, g_Saved[index].Yaw, id, -1, g_Saved[index].Type) == -1)
				PrintToChat(client, "[Vehicles] Home is blocked, assets unavailable or vehicle/entity limit reached.");
		} else if (StrEqual(parts[2], "delete")) {
			Menu confirm = new Menu(ConfirmSavedHandler);
			confirm.SetTitle("Delete saved home #%d? It will no longer spawn each round.", id);
			confirm.AddItem(info, "Yes, delete saved home; keep live vehicle");
			confirm.AddItem("cancel", "Cancel");
			confirm.Display(client, MENU_TIME_FOREVER);
			return 0;
		}
		ShowSavedList(client);
	}
	return 0;
}

public int ConfirmSavedHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[80], parts[3][24];
		menu.GetItem(item, info, sizeof(info));
		if (!StrEqual(info, "cancel")) {
			ExplodeString(info, " ", parts, 3, 24);
			int id = StringToInt(parts[1]);
			int index = SavedIndex(id);
			if (StringToInt(parts[0]) == g_MapSerial && index != -1 && g_ConfigReady) {
				Placement removed;
				removed = g_Saved[index];
				for (int i = index; i < g_SavedCount - 1; i++)
					g_Saved[i] = g_Saved[i + 1];
				g_SavedCount--;
				if (!WritePlacements()) {
					for (int i = g_SavedCount; i > index; i--)
						g_Saved[i] = g_Saved[i - 1];
					g_Saved[index] = removed;
					g_SavedCount++;
					PrintToChat(client, "[Vehicles] Delete failed; saved home retained.");
				} else {
					int v = LiveForSaved(id);
					if (v != -1)
						g_V[v].SavedId = 0;
					PrintToChat(client, "[Vehicles] Saved home deleted. Its live vehicle is now temporary.");
				}
			}
		}
		ShowSavedList(client);
	}
	return 0;
}

void ShowVehicleTypeMenu(int client, bool save) {
	Menu menu = new Menu(VehicleTypeHandler);
	menu.SetTitle(save ? "Place and save: choose vehicle" : "Spawn temporarily: choose vehicle");
	for (int type = 0; type < VEHICLE_TYPES; type++) {
		char info[48], label[96];
		Format(info, sizeof(info), "%d %d %d", g_MapSerial, save, type);
		Format(label, sizeof(label), "%s | %d seat%s | %s", g_TypeNames[type], g_Types[type].Seats,
			g_Types[type].Seats == 1 ? "" : "s", type == VEHICLE_ATV ? "armed rear passenger" : "armored cabin");
		menu.AddItem(info, label, g_Types[type].Ready && (type != VEHICLE_ATV || g_ATVRiderReady) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int VehicleTypeHandler(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && IsVehicleAdmin(client))
		ShowAdminMenu(client);
	else if (action == MenuAction_Select && IsVehicleAdmin(client)) {
		char info[48], parts[3][16];
		menu.GetItem(item, info, sizeof(info));
		if (ExplodeString(info, " ", parts, 3, 16) != 3)
			return 0;
		int type = StringToInt(parts[2]);
		bool save = StringToInt(parts[1]) != 0;
		if (StringToInt(parts[0]) != g_MapSerial || type < 0 || type >= VEHICLE_TYPES || (save && !g_ConfigReady)) {
			ShowAdminMenu(client);
			return 0;
		}
		float origin[3], yaw;
		if (AdminPlacement(client, origin, yaw, -1, type)) {
			int v = SpawnVehicle(origin, yaw, 0, -1, type);
			if (v == -1)
				PrintToChat(client, "[Vehicles] Spawn failed: check clearance, installed assets and entity/vehicle limits.");
			else if (save && !SaveLivePlacement(v, client)) {
				RemoveVehicle(v);
				PrintToChat(client, "[Vehicles] Could not save; new placement cancelled. Check server errors.");
			} else {
				PrintToChat(client, "[Vehicles] %s spawned%s.", g_TypeNames[type], save ? " and saved for this map" : " temporarily until the next round or map change");
				ShowLiveMenu(client, v);
				return 0;
			}
		}
		ShowVehicleTypeMenu(client, save);
	}
	return 0;
}

void PreparePassengerDisplay() {
	GameData config = new GameData("insurgency-bm.games");
	if (config == null) {
		LogError("Missing insurgency-bm.games.txt; rear passenger display disabled.");
		return;
	}
	g_PassengerOverlayOffset = config.GetOffset("CBaseAnimatingOverlay::AnimationOverlayVector");
	StartPrepSDKCall(SDKCall_Entity);
	if (PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseAnimatingOverlay::SetNumAnimOverlays")) {
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		g_PassengerSetLayers = EndPrepSDKCall();
	}
	StartPrepSDKCall(SDKCall_Player);
	if (PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CINSPlayer::GetMuzzle")) {
		PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
		PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
		g_PassengerGetMuzzle = EndPrepSDKCall();
	}
	delete config;
	if (g_PassengerSetLayers == null || g_PassengerOverlayOffset <= 0)
		LogError("Rear passenger animation setup unavailable; check passenger gamedata.");
}

bool CreatePassengerDisplay(int client, int vehicle, int modelVariant) {
	if (g_PassengerSetLayers == null || g_PassengerOverlayOffset <= 0
		|| FindDataMapInfo(client, "m_AnimOverlay") != g_PassengerOverlayOffset)
		return false;
	// Plain CBaseFlex retains animation overlays without the cycler facial-flex test.
	int display = CreateEntityByName("funCBaseFlex");
	if (display == -1)
		return false;
	g_R[client].DisplayRef = EntIndexToEntRef(display);
	DispatchKeyValue(display, "model", g_ATVPassengerModels[modelVariant]);
	if (!DispatchSpawn(display) || FindDataMapInfo(display, "m_AnimOverlay") != g_PassengerOverlayOffset)
		return false;
	SetEntityModel(display, g_ATVPassengerModels[modelVariant]);
	SetEntProp(display, Prop_Send, "m_nSolidType", 0);
	SetEntProp(display, Prop_Data, "m_takedamage", 0);
	SetEntityMoveType(display, MOVETYPE_NONE);
	SetEntPropEnt(display, Prop_Send, "m_hOwnerEntity", client);
	SetEntProp(display, Prop_Send, "m_bClientSideAnimation", 0);
	SetEntPropFloat(display, Prop_Send, "m_flPlaybackRate", 0.0);
	if (!SDKHookEx(display, SDKHook_SetTransmit, Hook_PassengerDisplayTransmit))
		return false;
	SDKCall(g_PassengerSetLayers, display, 15);
	g_R[client].DriverAnimTimeOffset = FindDataMapInfo(display, "m_flAnimTime");
	if (g_R[client].DriverAnimTimeOffset <= 0)
		return false;
	float local[3];
	SeatLocal(g_R[client].Vehicle, g_R[client].Seat, local, 1);
	ParentAtLocal(display, vehicle, local, -90.0);
	SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") | EF_NODRAW);
	return UpdatePassengerDisplay(client);
}

public Action Hook_PassengerDisplayTransmit(int entity, int viewer) {
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (owner <= 0 || owner > MaxClients || !IsClientInGame(viewer))
		return Plugin_Continue;
	bool firstPerson = viewer == owner;
	if (firstPerson && GetFeatureStatus(FeatureType_Native, "ThirdPerson_IsClientActive") == FeatureStatus_Available)
		firstPerson = !ThirdPerson_IsClientActive(viewer);
	if (viewer != owner && GetEntProp(viewer, Prop_Send, "m_iObserverMode") == 4)
		firstPerson = GetEntPropEnt(viewer, Prop_Send, "m_hObserverTarget") == owner;
	return firstPerson ? Plugin_Handled : Plugin_Continue;
}

bool CopyPassengerLayers(int client, int display) {
	int count = GetEntData(client, g_PassengerOverlayOffset + 12);
	if (count < 0 || count > 15 || GetEntData(display, g_PassengerOverlayOffset + 12) != 15)
		return false;
	Address source = view_as<Address>(GetEntData(client, g_PassengerOverlayOffset));
	Address dest = view_as<Address>(GetEntData(display, g_PassengerOverlayOffset));
	if ((count > 0 && source == Address_Null) || dest == Address_Null)
		return false;
	// Verified 32-bit CAnimationLayer layout. Never copy its owner pointer.
	int fields[] = {8, 12, 16, 20, 60};
	bool changed;
	for (int layer = 0; layer < 15; layer++) {
		for (int f = 0; f < sizeof(fields); f++) {
			int offset = layer * 76 + fields[f];
			int value = layer < count ? LoadFromAddress(source + view_as<Address>(offset), NumberType_Int32) : (fields[f] == 60 ? 15 : 0);
			Address target = dest + view_as<Address>(offset);
			if (LoadFromAddress(target, NumberType_Int32) != value) {
				StoreToAddress(target, value, NumberType_Int32);
				changed = true;
			}
		}
	}
	if (changed)
		ChangeEdictState(display);
	return true;
}

void RestorePassengerWeapon(int client) {
	int weapon = EntRefToEntIndex(g_R[client].PassengerWeaponRef);
	if (weapon > MaxClients && IsValidEntity(weapon))
		SetEntProp(weapon, Prop_Send, "m_fEffects", (GetEntProp(weapon, Prop_Send, "m_fEffects") & ~EF_NODRAW) | g_R[client].PassengerWeaponNoDraw);
	g_R[client].PassengerWeaponRef = INVALID_ENT_REFERENCE;
}

bool UpdatePassengerWeapon(int client, int display) {
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int previous = EntRefToEntIndex(g_R[client].PassengerWeaponRef);
	int prop = EntRefToEntIndex(g_R[client].DriverRigRef);
	if (weapon != previous) {
		RestorePassengerWeapon(client);
		if (prop > MaxClients && IsValidEntity(prop))
			RemoveEntity(prop);
		g_R[client].DriverRigRef = INVALID_ENT_REFERENCE;
		prop = -1;
	}
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return true;
	if (prop == -1) {
		int model = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
		int table = FindStringTable("modelprecache");
		char path[PLATFORM_MAX_PATH];
		if (model <= 0 || table == INVALID_STRING_TABLE || model >= GetStringTableNumStrings(table))
			return false;
		ReadStringTable(table, model, path, sizeof(path));
		prop = CreateEntityByName("prop_dynamic_override");
		if (prop == -1)
			return false;
		g_R[client].DriverRigRef = EntIndexToEntRef(prop);
		DispatchKeyValue(prop, "model", path);
		DispatchKeyValue(prop, "solid", "0");
		DispatchKeyValue(prop, "DisableBoneFollowers", "1");
		if (!DispatchSpawn(prop) || !SDKHookEx(prop, SDKHook_SetTransmit, Hook_PassengerDisplayTransmit))
			return false;
		SetEntityMoveType(prop, MOVETYPE_NONE);
		SetEntPropEnt(prop, Prop_Send, "m_hOwnerEntity", client);
		float local[3];
		ParentAtLocal(prop, display, local, 0.0);
		SetEntProp(prop, Prop_Send, "m_fEffects", GetEntProp(prop, Prop_Send, "m_fEffects") | DRIVER_BONEMERGE_EFFECTS);
		g_R[client].PassengerWeaponRef = EntIndexToEntRef(weapon);
		g_R[client].PassengerWeaponNoDraw = GetEntProp(weapon, Prop_Send, "m_fEffects") & EF_NODRAW;
	}
	SetEntProp(prop, Prop_Send, "m_nSkin", GetEntProp(weapon, Prop_Send, "m_nSkin"));
	SetEntProp(prop, Prop_Send, "m_nBody", GetEntProp(weapon, Prop_Send, "m_nBody"));
	int effects = GetEntProp(weapon, Prop_Send, "m_fEffects");
	SetEntProp(weapon, Prop_Send, "m_fEffects", effects | EF_NODRAW);
	return true;
}

bool UpdatePassengerDisplay(int client) {
	int display = EntRefToEntIndex(g_R[client].DisplayRef);
	if (display <= MaxClients || !IsValidEntity(display) || !CopyPassengerLayers(client, display))
		return false;
	SetEntProp(display, Prop_Send, "m_nSequence", GetEntProp(client, Prop_Send, "m_nSequence"));
	SetEntPropFloat(display, Prop_Send, "m_flCycle", GetEntPropFloat(client, Prop_Send, "m_flCycle"));
	SetEntProp(display, Prop_Send, "m_nNewSequenceParity", GetEntProp(client, Prop_Send, "m_nNewSequenceParity"));
	SetEntProp(display, Prop_Send, "m_nSkin", GetEntProp(client, Prop_Send, "m_nSkin"));
	SetEntProp(display, Prop_Send, "m_nBody", GetEntProp(client, Prop_Send, "m_nBody"));
	SetEntDataFloat(display, g_R[client].DriverAnimTimeOffset, GetGameTime(), true);
	for (int i = 0; i < 5; i++)
		SetEntPropFloat(display, Prop_Send, "m_flPoseParameter", GetEntPropFloat(client, Prop_Send, "m_flPoseParameter", i), i);
	// v2 libraries: body_pitch, body_yaw, body_height, move_y, move_x.
	SetEntPropFloat(display, Prop_Send, "m_flPoseParameter", (80.0 - g_R[client].LookYaw) / 160.0, 1);
	return UpdatePassengerWeapon(client, display);
}

public bool FilterPassengerGround(int entity, int contentsMask, any client) {
	return entity != client;
}

public bool FilterPassengerOwnedGround(int entity, int contentsMask, any client) {
	if (entity == client)
		return false;
	if (entity <= 0 || !IsValidEntity(entity))
		return true;
	// Match PassServerEntityFilter's ownership exclusions, not just the plugin's vehicle list.
	return GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") != client
		&& GetEntPropEnt(client, Prop_Send, "m_hOwnerEntity") != entity;
}

public Action Command_PassengerStatus(int client, int args) {
	for (int rider = 1; rider <= MaxClients; rider++) {
		if (!HumanAlive(rider) || (rider != client && !ArmedATVPassenger(rider)))
			continue;
		bool seated = ArmedATVPassenger(rider);
		float velocity[3], eye[3], muzzle[3], muzzleAngles[3], parentAngles[3];
		GetEntPropVector(rider, Prop_Data, "m_vecAbsVelocity", velocity);
		GetClientEyeAngles(rider, eye);
		int parent = GetEntPropEnt(rider, Prop_Data, "m_hMoveParent");
		if (parent > MaxClients && IsValidEntity(parent))
			GetEntPropVector(parent, Prop_Data, "m_angAbsRotation", parentAngles);
		int display = EntRefToEntIndex(g_R[rider].DisplayRef);
		ReplyToCommand(client, "[Vehicles] v%s %N: seated=%d, abs speed=%.2f, grounded=%d, jumping=%d, stance=%d, display=%d",
			PLUGIN_VERSION, rider, seated, GetVectorLength(velocity), (GetEntityFlags(rider) & FL_ONGROUND) != 0,
			GetEntProp(rider, Prop_Send, "m_bJumping"), GetEntProp(rider, Prop_Send, "m_iCurrentStance"), display);
		ReplyToCommand(client, "[Vehicles] eye pitch/yaw=%.2f/%.2f, parent=%d, parent pitch/yaw/roll=%.2f/%.2f/%.2f, player sequence=%d, display sequence=%d",
			eye[0], eye[1], parent, parentAngles[0], parentAngles[1], parentAngles[2], GetEntProp(rider, Prop_Send, "m_nSequence"),
			display > MaxClients ? GetEntProp(display, Prop_Send, "m_nSequence") : -1);
		if (seated) {
			int support = EntRefToEntIndex(g_R[rider].PassengerSupportRef);
			float origin[3], below[3], mins[3], maxs[3], normal[3];
			GetClientAbsOrigin(rider, origin);
			GetClientMins(rider, mins);
			GetClientMaxs(rider, maxs);
			below = origin;
			below[2] -= 2.0;
			Handle trace = TR_TraceHullFilterEx(origin, below, mins, maxs, MASK_PLAYERSOLID, FilterPassengerGround, rider);
			bool hit = TR_DidHit(trace);
			if (hit)
				TR_GetPlaneNormal(trace, normal);
			int blocker = hit ? TR_GetEntityIndex(trace) : -1;
			char classname[64] = "none";
			if (blocker >= 0 && IsValidEntity(blocker))
				GetEntityClassname(blocker, classname, sizeof(classname));
			int vehicle = Vehicle(g_R[rider].Vehicle);
			ReplyToCommand(client, "[Vehicles] vehicle=%d owner=%d support=%d, raw ground trace hit=%d entity=%d (%s) startsolid=%d normal Z=%.2f",
				vehicle, vehicle > MaxClients ? GetEntPropEnt(vehicle, Prop_Send, "m_hOwnerEntity") : -1,
				support, hit, blocker, classname, TR_StartSolid(trace), normal[2]);
			delete trace;
			trace = TR_TraceHullFilterEx(origin, below, mins, maxs, MASK_PLAYERSOLID, FilterPassengerOwnedGround, rider);
			normal[2] = 0.0;
			hit = TR_DidHit(trace);
			if (hit)
				TR_GetPlaneNormal(trace, normal);
			ReplyToCommand(client, "[Vehicles] owner-filtered ground trace hit=%d entity=%d startsolid=%d normal Z=%.2f",
				hit, hit ? TR_GetEntityIndex(trace) : -1, TR_StartSolid(trace), normal[2]);
			delete trace;
			if (support > MaxClients) {
				trace = TR_ClipRayHullToEntityEx(origin, below, mins, maxs, MASK_PLAYERSOLID, support);
				ReplyToCommand(client, "[Vehicles] support-only trace hit=%d startsolid=%d fraction=%.2f",
					TR_DidHit(trace), TR_StartSolid(trace), TR_GetFraction(trace));
				delete trace;
			}
		}
		int activeWeapon = GetEntPropEnt(rider, Prop_Send, "m_hActiveWeapon");
		if (activeWeapon > MaxClients && IsValidEntity(activeWeapon) && HasEntProp(activeWeapon, Prop_Send, "m_bWeaponBlocked"))
			ReplyToCommand(client, "[Vehicles] weapon blocked=%d", GetEntProp(activeWeapon, Prop_Send, "m_bWeaponBlocked"));
		if (g_PassengerGetMuzzle != null) {
			SDKCall(g_PassengerGetMuzzle, rider, muzzle, muzzleAngles);
			ReplyToCommand(client, "[Vehicles] muzzle pitch/yaw=%.2f/%.2f, muzzle-eye delta=%.2f/%.2f",
				muzzleAngles[0], muzzleAngles[1], NormalizeYaw(muzzleAngles[0] - eye[0]), NormalizeYaw(muzzleAngles[1] - eye[1]));
		}
	}
	return Plugin_Handled;
}

bool PassengerAimTestNoDisplay(int client) {
	return g_R[client].AimTestStep == 3 || g_R[client].AimTestStep == 4;
}

bool ApplyPassengerAimTest(int client) {
	int vehicle = Vehicle(g_R[client].Vehicle);
	if (vehicle == -1)
		return false;
	if (g_R[client].AimTestStep == 1 && !StandingClear(client, g_R[client].AimTestOutside))
		return false;
	int modelIndex = ATVPassengerVariant(g_R[client].SavedModel);
	if (modelIndex == -1)
		return false;
	char model[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	bool nativeVisuals = g_R[client].AimTestStep == 4;
	if (!StrEqual(model, nativeVisuals ? g_R[client].SavedModel : g_ATVPassengerModels[modelIndex], false)) {
		int skin = GetEntProp(client, Prop_Send, "m_nSkin");
		int body = GetEntProp(client, Prop_Send, "m_nBody");
		SetEntityModel(client, nativeVisuals ? g_R[client].SavedModel : g_ATVPassengerModels[modelIndex]);
		SetEntProp(client, Prop_Send, "m_nSkin", skin);
		SetEntProp(client, Prop_Send, "m_nBody", body);
	}
	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	SetEntProp(client, Prop_Send, "m_fEffects", nativeVisuals ? ((effects & ~EF_NODRAW) | g_R[client].SavedNoDraw) : (effects | EF_NODRAW));
	if (nativeVisuals)
		RestorePassengerWeapon(client);
	if (PassengerAimTestNoDisplay(client)) {
		int prop = EntRefToEntIndex(g_R[client].DriverRigRef);
		g_R[client].DriverRigRef = INVALID_ENT_REFERENCE;
		if (prop > MaxClients && IsValidEntity(prop))
			RemoveEntity(prop);
		int display = EntRefToEntIndex(g_R[client].DisplayRef);
		g_R[client].DisplayRef = INVALID_ENT_REFERENCE;
		if (display > MaxClients && IsValidEntity(display))
			RemoveEntity(display);
	} else if (EntRefToEntIndex(g_R[client].DisplayRef) == INVALID_ENT_REFERENCE) {
		// Restore before recreation so its saved visibility remains the original value.
		RestorePassengerWeapon(client);
		if (!CreatePassengerDisplay(client, vehicle, modelIndex))
			return false;
	}
	FollowPassengerSeat(client);
	HoldPassengerMotion(client);
	return true;
}

void LogPassengerAimSample(int client, const char[] label) {
	float eye[3], muzzle[3], muzzleAngles[3], velocity[3], aimPunch[3], viewPunch[3], viewOffset[3];
	GetClientEyeAngles(client, eye);
	SDKCall(g_PassengerGetMuzzle, client, muzzle, muzzleAngles);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	GetEntPropVector(client, Prop_Data, "m_vecViewOffset", viewOffset);
	bool hasAimPunch = HasEntProp(client, Prop_Send, "m_aimPunchAngle");
	bool hasViewPunch = HasEntProp(client, Prop_Send, "m_viewPunchAngle");
	if (hasAimPunch)
		GetEntPropVector(client, Prop_Send, "m_aimPunchAngle", aimPunch);
	if (hasViewPunch)
		GetEntPropVector(client, Prop_Send, "m_viewPunchAngle", viewPunch);
	char line[512];
	Format(line, sizeof(line), "[ATV ADS test] v%s %s: ADS=%d, pitch delta=%.3f, yaw delta=%.3f, speed=%.2f, ground=%d, flags=%d, movetype=%d",
		PLUGIN_VERSION, label, GetEntProp(client, Prop_Send, "m_iPlayerFlags") & 1,
		NormalizeYaw(muzzleAngles[0] - eye[0]), NormalizeYaw(muzzleAngles[1] - eye[1]), GetVectorLength(velocity),
		GetEntPropEnt(client, Prop_Send, "m_hGroundEntity"), GetEntityFlags(client), GetEntityMoveType(client));
	PrintToConsole(client, "%s", line);
	LogMessage("%N %s", client, line);
	Format(line, sizeof(line), "[ATV ADS test] %s: eye pitch=%.3f, muzzle pitch=%.3f, aim punch=%d/%.3f, view punch=%d/%.3f, view height=%.2f",
		label, eye[0], NormalizeYaw(muzzleAngles[0]), hasAimPunch, aimPunch[0], hasViewPunch, viewPunch[0], viewOffset[2]);
	PrintToConsole(client, "%s", line);
	LogMessage("%N %s", client, line);
	float origin[3];
	GetClientAbsOrigin(client, origin);
	Format(line, sizeof(line), "[ATV ADS test] %s: origin=%.1f/%.1f/%.1f, view=%d, display=%d, display weapon=%d",
		label, origin[0], origin[1], origin[2], GetEntPropEnt(client, Prop_Send, "m_hViewEntity"),
		EntRefToEntIndex(g_R[client].DisplayRef), EntRefToEntIndex(g_R[client].DriverRigRef));
	PrintToConsole(client, "%s", line);
	LogMessage("%N %s", client, line);
}

void StopPassengerAimTest(int client) {
	delete g_R[client].AimTestTimer;
	if (g_R[client].AimTestStep == -1)
		return;
	g_R[client].AimTestStep = -1;
	// ExitRider has already chosen and applied an exit position when Changing is set.
	if (HumanAlive(client) && ArmedATVPassenger(client) && g_R[client].PassengerMotionApplied && !g_R[client].Changing
		&& !ApplyPassengerAimTest(client)) {
		LogError("Could not restore passenger display after ADS comparison; exiting client %d.", client);
		ExitRider(client, true);
	}
}

public Action Command_PassengerAimTest(int client, int args) {
	if (!HumanAlive(client) || !ArmedATVPassenger(client)) {
		ReplyToCommand(client, "[Vehicles] Run this from the rear passenger's game console.");
		return Plugin_Handled;
	}
	if (g_R[client].AimTestStep != -1) {
		StopPassengerAimTest(client);
		ReplyToCommand(client, "[Vehicles] ADS comparison cancelled.");
		return Plugin_Handled;
	}
	StopPassengerDrive(client);
	int v = g_R[client].Vehicle;
	int vehicle = Vehicle(v);
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (vehicle == -1 || FloatAbs(g_V[v].Speed) > 0.1 || g_V[v].Airborne || weapon <= MaxClients || g_PassengerGetMuzzle == null) {
		ReplyToCommand(client, "[Vehicles] Stop the ATV and equip a firearm first; muzzle gamedata must be available.");
		return Plugin_Handled;
	}
	float exitPoint[3];
	if (!FindExit(client, exitPoint)) {
		ReplyToCommand(client, "[Vehicles] Park with clear space beside the ATV first; the position comparison needs a safe point outside it.");
		return Plugin_Handled;
	}
	g_R[client].AimTestOutside = exitPoint;
	g_R[client].AimTestStep = 0;
	g_R[client].AimTestWeaponRef = EntIndexToEntRef(weapon);
	GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", g_R[client].AimTestOrigin);
	g_R[client].AimTestTimer = CreateTimer(4.0, Timer_PassengerAimTest, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	ReplyToCommand(client, "[Vehicles] Hold first-person ADS without firing or moving for 28 seconds. The test temporarily moves your viewpoint beside the ATV and removes the display, then restores the seat.");
	return Plugin_Handled;
}

public Action Timer_PassengerAimTest(Handle timer, any userid) {
	int client = GetClientOfUserId(userid);
	if (client == 0 || g_R[client].AimTestTimer != timer)
		return Plugin_Stop;
	int v = g_R[client].Vehicle;
	int vehicle = Vehicle(v);
	bool ready = !g_EndingMap && HumanAlive(client) && ArmedATVPassenger(client) && vehicle != -1;
	if (ready) {
		float origin[3];
		GetEntPropVector(vehicle, Prop_Data, "m_vecAbsOrigin", origin);
		ready = FloatAbs(g_V[v].Speed) <= 0.1 && !g_V[v].Airborne
			&& GetVectorDistance(origin, g_R[client].AimTestOrigin, true) < 1.0
			&& GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == EntRefToEntIndex(g_R[client].AimTestWeaponRef);
	}
	if (!ready) {
		g_R[client].AimTestTimer = null;
		StopPassengerAimTest(client);
		if (IsClientInGame(client))
			PrintToChat(client, "[Vehicles] ADS comparison stopped because the rider, weapon or ATV changed; seated state restored.");
		return Plugin_Stop;
	}
	char labels[][] = {"seated baseline", "outside position only", "seat position restored", "display entities removed", "native visuals without display entities", "display entities restored", "native view refreshed"};
	int step = g_R[client].AimTestStep;
	LogPassengerAimSample(client, labels[step]);
	if (step == 6) {
		g_R[client].AimTestTimer = null;
		StopPassengerAimTest(client);
		PrintToChat(client, "[Vehicles] ADS comparison complete. Copy all [ATV ADS test] lines; seated state restored.");
		return Plugin_Stop;
	}
	g_R[client].AimTestStep++;
	if (!ApplyPassengerAimTest(client)) {
		g_R[client].AimTestTimer = null;
		StopPassengerAimTest(client);
		PrintToChat(client, "[Vehicles] ADS comparison stopped: test position blocked or display setup failed.");
		return Plugin_Stop;
	}
	if (g_R[client].AimTestStep == 6) {
		SetEntPropEnt(client, Prop_Send, "m_hViewEntity", -1);
		SetClientViewEntity(client, client);
	}
	return Plugin_Continue;
}

bool AimControlLiftClear(int client) {
	float raised[3], mins[3], maxs[3];
	raised = g_AimControlOrigin[client];
	raised[2] += 16.0;
	GetClientMins(client, mins);
	GetClientMaxs(client, maxs);
	Handle trace = TR_TraceHullFilterEx(g_AimControlOrigin[client], raised, mins, maxs, MASK_PLAYERSOLID, FilterPlacement, client);
	bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
	delete trace;
	return clear;
}

void StopAimControl(int client) {
	delete g_AimControlTimer[client];
	if (g_AimControlHeld[client] && HumanAlive(client) && g_R[client].Vehicle == -1
		&& GetEntityMoveType(client) == MOVETYPE_NONE) {
		float origin[3], raised[3], zero[3];
		GetClientAbsOrigin(client, origin);
		raised = g_AimControlOrigin[client];
		raised[2] += 16.0;
		if (g_AimControlLifted[client] && GetVectorDistance(origin, raised, true) <= 4.0
			&& StandingClear(client, g_AimControlOrigin[client]))
			TeleportEntity(client, g_AimControlOrigin[client], NULL_VECTOR, zero);
		SetEntityMoveType(client, MOVETYPE_WALK);
	}
	g_AimControlHeld[client] = false;
	g_AimControlLifted[client] = false;
}

public Action Command_AimControl(int client, int args) {
	if (client > 0 && g_AimControlTimer[client] != null) {
		StopAimControl(client);
		ReplyToCommand(client, "[Vehicles] On-foot ADS control cancelled; movement restored.");
		return Plugin_Handled;
	}
	if (!HumanAlive(client) || g_R[client].Vehicle != -1 || GetEntityMoveType(client) != MOVETYPE_WALK
		|| GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != 0
		|| (GetEntityFlags(client) & FL_ONGROUND) == 0 || GetEntProp(client, Prop_Send, "m_iCurrentStance") != 0) {
		ReplyToCommand(client, "[Vehicles] Run this while standing normally on the map floor outside the ATV.");
		return Plugin_Handled;
	}
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	if (weapon <= MaxClients || g_PassengerGetMuzzle == null || GetVectorLength(velocity) > 0.1) {
		ReplyToCommand(client, "[Vehicles] Stop moving and equip a firearm first; muzzle gamedata must be available.");
		return Plugin_Handled;
	}
	GetClientAbsOrigin(client, g_AimControlOrigin[client]);
	if (!AimControlLiftClear(client)) {
		ReplyToCommand(client, "[Vehicles] Move to an open area; the ground-contact control needs clearance above you.");
		return Plugin_Handled;
	}
	g_AimControlStep[client] = 0;
	g_AimControlHeld[client] = true;
	g_AimControlLifted[client] = false;
	g_AimControlWeapon[client] = EntIndexToEntRef(weapon);
	SetEntityMoveType(client, MOVETYPE_NONE);
	g_AimControlTimer[client] = CreateTimer(4.0, Timer_AimControl, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	ReplyToCommand(client, "[Vehicles] Hold first-person ADS without firing or moving for 12 seconds: supported, lifted 16 units, supported again. MOVETYPE_NONE stays the same; walking restores automatically.");
	return Plugin_Handled;
}

public Action Timer_AimControl(Handle timer, any userid) {
	int client = GetClientOfUserId(userid);
	if (client == 0 || g_AimControlTimer[client] != timer)
		return Plugin_Stop;
	bool ready = !g_EndingMap && HumanAlive(client) && g_R[client].Vehicle == -1;
	if (ready) {
		float origin[3], expected[3];
		GetClientAbsOrigin(client, origin);
		expected = g_AimControlOrigin[client];
		if (g_AimControlLifted[client])
			expected[2] += 16.0;
		ready = GetVectorDistance(origin, expected, true) <= 4.0
			&& GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == EntRefToEntIndex(g_AimControlWeapon[client])
			&& GetEntityMoveType(client) == MOVETYPE_NONE;
	}
	if (!ready) {
		g_AimControlTimer[client] = null;
		StopAimControl(client);
		PrintToChat(client, "[Vehicles] On-foot ADS control cancelled: player state, weapon or position changed.");
		return Plugin_Stop;
	}
	char labels[][] = {"supported MOVETYPE_NONE", "lifted MOVETYPE_NONE", "supported again MOVETYPE_NONE"};
	int step = g_AimControlStep[client];
	LogPassengerAimSample(client, labels[step]);
	if (step == 2) {
		g_AimControlTimer[client] = null;
		StopAimControl(client);
		PrintToChat(client, "[Vehicles] Ground-contact ADS control complete; walking restored. Copy all [ATV ADS test] lines.");
		return Plugin_Stop;
	}
	if ((step == 0 && !AimControlLiftClear(client)) || !StandingClear(client, g_AimControlOrigin[client])) {
		g_AimControlTimer[client] = null;
		StopAimControl(client);
		PrintToChat(client, "[Vehicles] Ground-contact ADS control cancelled: return position or lift path blocked; walking restored.");
		return Plugin_Stop;
	}
	float point[3], zero[3];
	point = g_AimControlOrigin[client];
	g_AimControlLifted[client] = step == 0;
	if (g_AimControlLifted[client])
		point[2] += 16.0;
	// Leave flags and ground entity to native collision prediction throughout this control.
	TeleportEntity(client, point, NULL_VECTOR, zero);
	g_AimControlStep[client]++;
	return Plugin_Continue;
}
