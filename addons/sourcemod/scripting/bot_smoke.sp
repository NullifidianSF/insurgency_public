#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#define PL_VERSION "1.1.6"
#define GAMEDATA_FILE "insurgency-bm.games"
#define MAX_PLAYER_CHECK_DEPTH 32
#define GUNFIRE_CHECK_INTERVAL 0.5

enum struct SmokeCloud {
	int entityRef;
	float origin[3];
	float expires;
	float revealedUntil;
}

ArrayList g_hSmokeClouds;
GameData g_hGameData;
DynamicDetour g_hSightDetour;
DynamicDetour g_hFireDetour;
DynamicDetour g_hPlayerSightDetour;
DynamicDetour g_hBlockerDetour;
ConVar g_cvEnabled;
ConVar g_cvDistance;
ConVar g_cvSmokeWindow;
ConVar g_cvRevealTime;
ConVar g_cvSmokeRadius;
ConVar g_cvRequireGunfire;
Handle g_hSmokeWindowTimer;
bool g_bHooksEnabled;
bool g_bWindowUpdateQueued;
bool g_bWeaponFireHooked;
bool g_bResetVisionHooks;
float g_fSmokeWindowEnd;
bool g_bEnabled;
bool g_bRequireGunfire;
float g_fDistanceSquared;
float g_fSmokeRadiusSquared;
float g_fNextGunfireCheckAt[MAXPLAYERS + 1];
int g_iBotCheckDepth;
int g_iPlayerCheckDepth;
int g_iPlayerBotDepth;
bool g_bPlayerCheckIsBot[MAX_PLAYER_CHECK_DEPTH];
int g_iSightCalls;
int g_iFireCalls;
int g_iPlayerSightCalls;
int g_iSightPassed;
int g_iFirePassed;
int g_iPlayerSightPassed;
int g_iPlayerBypassed;
int g_iScopedBlockerCalls;
int g_iBlockedCalls;
int g_iBypassedCalls;
float g_fLastBlockedDistance = -1.0;

public Plugin myinfo = {
	name = "Bot Smoke Range",
	author = "Nullifidian, OpenAI",
	description = "Lets nearby bots see through smoke after human gunfire, or throughout its configured lifetime. Walls still block sight",
	version = PL_VERSION,
	url = ""
};

public void OnPluginStart() {
	if (GetFeatureStatus(FeatureType_Native, "DynamicDetour.DynamicDetour") != FeatureStatus_Available)
		SetFailState("[Bot Smoke] DHooks with DynamicDetour support is required.");

	g_cvEnabled = CreateConVar("sm_botsmoke_enable", "1",
		"Enable the bot-only close-range visual-blocker exception. 0 restores native behavior.", _, true, 0.0, true, 1.0);
	g_cvDistance = CreateConVar("sm_botsmoke_distance", "512",
		"Maximum bot-to-checked-point distance in game units for ignoring smoke/shared explosion-cloud blockers. Walls remain checked. Native close-range threshold is 64.", _, true, 64.0, true, 512.0);
	g_cvSmokeWindow = CreateConVar("sm_botsmoke_window", "25",
		"Seconds each smoke cloud is tracked after detonation, including fading. Not automatic theater detection. Changes affect future detonations.", _, true, 0.1, true, 300.0);
	g_cvRevealTime = CreateConVar("sm_botsmoke_reveal_time", "5",
		"Seconds human weapon fire near or aimed through a smoke cloud exposes it to nearby bots. More shots refresh that cloud only; exposure never outlasts its tracked lifetime.", _, true, 0.1, true, 60.0);
	g_cvSmokeRadius = CreateConVar("sm_botsmoke_radius", "290",
		"Approximate cloud radius in units for nearby gunfire, shot-path and sight-line checks. Not the exact native blocker or particle boundary.", _, true, 1.0, true, 1024.0);
	g_cvRequireGunfire = CreateConVar("sm_botsmoke_require_gunfire", "1",
		"1 = human gunfire exposes individual clouds. 0 = full sm_botsmoke_window after detonation, without gunfire hooks or cloud tracking. Switching modes clears the active window and waits for new smoke.", _, true, 0.0, true, 1.0);
	g_hSmokeClouds = new ArrayList(sizeof(SmokeCloud));
	g_cvEnabled.AddChangeHook(OnSettingsChanged);
	g_cvDistance.AddChangeHook(OnSettingsChanged);
	g_cvSmokeRadius.AddChangeHook(OnSettingsChanged);
	g_cvRequireGunfire.AddChangeHook(OnSettingsChanged);
	CacheSettings();

	RegAdminCmd("sm_botsmoke", Command_Status, ADMFLAG_ROOT,
		"Show current/last smoke-window counters and settings. Optional argument: reset.");

	g_hGameData = LoadGameConfigFile(GAMEDATA_FILE);
	if (g_hGameData == null)
		SetFailState("[Bot Smoke] Missing gamedata: %s.txt", GAMEDATA_FILE);

	g_hSightDetour = CreateDetour("CINSBotVision::IsLineOfSightClear");
	g_hSightDetour.AddParam(HookParamType_VectorPtr);

	g_hFireDetour = CreateDetour("CINSBotVision::IsLineOfFireClear");
	g_hFireDetour.AddParam(HookParamType_VectorPtr);
	// The second C++ argument is a by-value Vector, occupying three float stack slots
	// on these verified 32-bit builds. These values are never changed by this hook.
	for (int axis = 0; axis < 3; axis++)
		g_hFireDetour.AddParam(HookParamType_Float);

	// Bots also use the inherited player sight path, including its own smoke gate.
	// Pass the actual player entity so human callers never gain an exception.
	g_hPlayerSightDetour = CreateDetour("CINSPlayer::IsLineOfSightClearToPoint", ThisPointer_CBaseEntity);
	g_hPlayerSightDetour.AddParam(HookParamType_VectorPtr);
	g_hPlayerSightDetour.AddParam(HookParamType_Int);
	g_hPlayerSightDetour.AddParam(HookParamType_CBaseEntity);

	g_hBlockerDetour = CreateDetour("CVisibilityBlockers::DoesLineIntersectBlocker");
	g_hBlockerDetour.AddParam(HookParamType_VectorPtr);
	g_hBlockerDetour.AddParam(HookParamType_VectorPtr);

	HookEvent("grenade_detonate", Event_GrenadeDetonate, EventHookMode_Post);
	UpdateWeaponFireHook();
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	// Do not scan existing smoke on late load. Wait for the next detonation.
	AutoExecConfig(true, "bot_smoke");
	LogMessage("[Bot Smoke] Loaded v%s. Use sm_botsmoke for mode/settings/counters. Hooks remain idle until the selected smoke mode activates them.", PL_VERSION);
}

void EnableVisionHooks() {
	if (g_bHooksEnabled)
		return;

	// Start fresh only when leaving IDLE. Extending an active window keeps its stats.
	// Completed-window counters remain available until this point (or manual/map reset).
	ResetCounters();

	// Paired hooks limit the shared blocker override to a native bot sight/fire call.
	// All original world traces, recognition tests, and return values remain intact.
	if (!g_hSightDetour.Enable(Hook_Pre, Detour_Sight_Pre)
		|| !g_hSightDetour.Enable(Hook_Post, Detour_Sight_Post)
		|| !g_hFireDetour.Enable(Hook_Pre, Detour_Fire_Pre)
		|| !g_hFireDetour.Enable(Hook_Post, Detour_Fire_Post)
		|| !g_hPlayerSightDetour.Enable(Hook_Pre, Detour_PlayerSight_Pre)
		|| !g_hPlayerSightDetour.Enable(Hook_Post, Detour_PlayerSight_Post)
		|| !g_hBlockerDetour.Enable(Hook_Post, Detour_Blocker_Post))
		SetFailState("[Bot Smoke] Could not enable all required detours. Check that gamedata matches your server build.");

	g_bHooksEnabled = true;
}

void DisableVisionHooks() {
	if (!g_bHooksEnabled)
		return;

	// Attempt every removal even if an earlier one fails.
	bool removed = g_hBlockerDetour.Disable(Hook_Post, Detour_Blocker_Post);
	removed = g_hPlayerSightDetour.Disable(Hook_Pre, Detour_PlayerSight_Pre) && removed;
	removed = g_hPlayerSightDetour.Disable(Hook_Post, Detour_PlayerSight_Post) && removed;
	removed = g_hFireDetour.Disable(Hook_Pre, Detour_Fire_Pre) && removed;
	removed = g_hFireDetour.Disable(Hook_Post, Detour_Fire_Post) && removed;
	removed = g_hSightDetour.Disable(Hook_Pre, Detour_Sight_Pre) && removed;
	removed = g_hSightDetour.Disable(Hook_Post, Detour_Sight_Post) && removed;
	if (!removed)
		SetFailState("[Bot Smoke] Could not disable all vision detours.");
	g_bHooksEnabled = false;
}

public void Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bEnabled)
		return;

	int grenade = event.GetInt("entityid");
	if (grenade <= MaxClients || !IsValidEntity(grenade))
		return;

	char classname[64];
	if (!GetEntityClassname(grenade, classname, sizeof(classname)))
		return;
	if (StrContains(classname, "m18", false) == -1 && StrContains(classname, "smoke", false) == -1)
		return;

	float now = GetGameTime();
	if (!g_bRequireGunfire) {
		// Full-window mode needs only one deadline, not grenade refs or positions.
		float expires = now + g_cvSmokeWindow.FloatValue;
		if (expires > g_fSmokeWindowEnd)
			g_fSmokeWindowEnd = expires;
		QueueWindowUpdate();
		return;
	}

	PruneSmokeClouds(now);
	int entityRef = EntIndexToEntRef(grenade);
	SmokeCloud cloud;
	int count = g_hSmokeClouds.Length;
	for (int i = 0; i < count; i++) {
		g_hSmokeClouds.GetArray(i, cloud, sizeof(cloud));
		if (cloud.entityRef == entityRef)
			return;
	}

	cloud.entityRef = entityRef;
	GetEntPropVector(grenade, Prop_Send, "m_vecOrigin", cloud.origin);
	cloud.expires = now + g_cvSmokeWindow.FloatValue;
	cloud.revealedUntil = 0.0;
	g_hSmokeClouds.PushArray(cloud, sizeof(cloud));
	// Gunfire mode waits for a human shot near or aimed through the cloud.
}

void PruneSmokeClouds(float now) {
	SmokeCloud cloud;
	for (int i = g_hSmokeClouds.Length - 1; i >= 0; i--) {
		g_hSmokeClouds.GetArray(i, cloud, sizeof(cloud));
		if (cloud.expires <= now)
			g_hSmokeClouds.Erase(i);
	}
}

void GetSmokeOrigin(SmokeCloud cloud, float origin[3]) {
	int grenade = EntRefToEntIndex(cloud.entityRef);
	if (grenade > MaxClients && IsValidEntity(grenade))
		GetEntPropVector(grenade, Prop_Send, "m_vecOrigin", origin);
	else
		for (int axis = 0; axis < 3; axis++)
			origin[axis] = cloud.origin[axis];
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast) {
	if (!g_bEnabled || !g_bRequireGunfire || g_hSmokeClouds.Length == 0)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return;

	float now = GetGameTime();
	// Throttle every human weapon independently, before pruning, cloud scans or traces.
	if (now < g_fNextGunfireCheckAt[client])
		return;	
	g_fNextGunfireCheckAt[client] = now + GUNFIRE_CHECK_INTERVAL;
	PruneSmokeClouds(now);
	int count = g_hSmokeClouds.Length;
	if (count == 0)
		return;
	float eye[3], origin[3], shotEnd[3];
	GetClientEyePosition(client, eye);
	SmokeCloud cloud;
	bool changed, shotTraced, shotValid;
	float revealUntil = now + g_cvRevealTime.FloatValue;
	for (int i = 0; i < count; i++) {
		g_hSmokeClouds.GetArray(i, cloud, sizeof(cloud));
		GetSmokeOrigin(cloud, origin);
		if (GetVectorDistance(eye, origin, true) > g_fSmokeRadiusSquared) {
			// Nearby fire needs no trace. All other clouds share at most one trace per event.
			if (!shotTraced) {
				shotTraced = true;
				shotValid = GetHumanShotEnd(client, eye, shotEnd);
			}
			if (!shotValid || !LineIntersectsSmoke(eye, shotEnd, origin))
				continue;
		}

		float until = revealUntil;
		if (until > cloud.expires)
			until = cloud.expires;
		if (until > cloud.revealedUntil)
			cloud.revealedUntil = until;
		for (int axis = 0; axis < 3; axis++)
			cloud.origin[axis] = origin[axis];
		g_hSmokeClouds.SetArray(i, cloud, sizeof(cloud));
		changed = true;
	}
	if (changed)
		QueueWindowUpdate();
}

bool GetHumanShotEnd(int client, const float eye[3], float end[3]) {
	// weapon_fire provides no bullet trajectory. Approximate it with the current aim,
	// stopping at the first shot-solid hit. This does not simulate spread or penetration.
	float angles[3];
	GetClientEyeAngles(client, angles);
	Handle trace = TR_TraceRayFilterEx(eye, angles, MASK_SHOT, RayType_Infinite, TraceFilter_HumanShot, client);
	bool valid = !TR_StartSolid(trace) && !TR_AllSolid(trace);
	if (valid)
		TR_GetEndPosition(end, trace);
	delete trace;
	return valid;
}

public bool TraceFilter_HumanShot(int entity, int contentsMask, any client) {
	return entity != client;
}

public void OnClientDisconnect(int client) {
	g_fNextGunfireCheckAt[client] = 0.0;
}

void ResetGunfireCheckTimes() {
	for (int client = 1; client <= MaxClients; client++)
		g_fNextGunfireCheckAt[client] = 0.0;
}

float GetExposureEnd(float now) {
	float latest;
	SmokeCloud cloud;
	int count = g_hSmokeClouds.Length;
	for (int i = 0; i < count; i++) {
		g_hSmokeClouds.GetArray(i, cloud, sizeof(cloud));
		if (cloud.expires > now && cloud.revealedUntil > latest)
			latest = cloud.revealedUntil;
	}
	return latest;
}

bool LineIntersectsSmoke(const float start[3], const float end[3], const float center[3]) {
	float delta[3], toCenter[3], closest[3];
	SubtractVectors(end, start, delta);
	SubtractVectors(center, start, toCenter);
	float lengthSquared = GetVectorDotProduct(delta, delta);
	float fraction;
	if (lengthSquared > 0.0)
		fraction = GetVectorDotProduct(toCenter, delta) / lengthSquared;
	if (fraction < 0.0)
		fraction = 0.0;
	else if (fraction > 1.0)
		fraction = 1.0;
	for (int axis = 0; axis < 3; axis++)
		closest[axis] = start[axis] + delta[axis] * fraction;
	return GetVectorDistance(closest, center, true) <= g_fSmokeRadiusSquared;
}

bool CanBypassExposedSmoke(const float start[3], const float end[3]) {
	float now = GetGameTime();
	bool intersectsExposed;
	SmokeCloud cloud;
	float origin[3];
	int count = g_hSmokeClouds.Length;
	for (int i = 0; i < count; i++) {
		g_hSmokeClouds.GetArray(i, cloud, sizeof(cloud));
		if (cloud.expires <= now)
			continue;
		GetSmokeOrigin(cloud, origin);
		if (!LineIntersectsSmoke(start, end, origin))
			continue;
		// A quiet tracked cloud along the same line retains concealment, including overlaps.
		if (cloud.revealedUntil <= now)
			return false;
		intersectsExposed = true;
	}
	return intersectsExposed;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	g_hSmokeClouds.Clear();
	g_fSmokeWindowEnd = 0.0;
	ResetGunfireCheckTimes();
	QueueWindowUpdate();
}

void QueueWindowUpdate() {
	if (g_bWindowUpdateQueued)
		return;
	g_bWindowUpdateQueued = true;
	RequestFrame(Frame_UpdateSmokeWindow);
}

void UpdateWeaponFireHook() {
	bool needed = g_bEnabled && g_bRequireGunfire;
	if (needed == g_bWeaponFireHooked)
		return;
	if (needed)
		HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
	else
		UnhookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
	g_bWeaponFireHooked = needed;
}

public void Frame_UpdateSmokeWindow(any data) {
	g_bWindowUpdateQueued = false;
	// Never change a detour while one of its paired calls is in progress.
	if (g_iBotCheckDepth > 0 || g_iPlayerCheckDepth > 0) {
		QueueWindowUpdate();
		return;
	}

	UpdateWeaponFireHook();
	if (g_bResetVisionHooks) {
		DisableVisionHooks();
		g_bResetVisionHooks = false;
	}
	delete g_hSmokeWindowTimer;
	float now = GetGameTime();
	if (g_bRequireGunfire) {
		PruneSmokeClouds(now);
		g_fSmokeWindowEnd = GetExposureEnd(now);
	}
	float remaining = g_fSmokeWindowEnd - now;
	if (!g_bEnabled || remaining <= 0.0) {
		g_fSmokeWindowEnd = 0.0;
		DisableVisionHooks();
		return;
	}

	EnableVisionHooks();
	if (remaining < 0.1)
		remaining = 0.1;
	g_hSmokeWindowTimer = CreateTimer(remaining, Timer_SmokeWindowExpired, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SmokeWindowExpired(Handle timer) {
	g_hSmokeWindowTimer = null;
	QueueWindowUpdate();
	return Plugin_Stop;
}

DynamicDetour CreateDetour(const char[] name, ThisPointerType thisType = ThisPointer_Ignore) {
	DynamicDetour detour = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Bool, thisType);
	if (!detour.SetFromConf(g_hGameData, SDKConf_Signature, name)) {
		delete detour;
		SetFailState("[Bot Smoke] Could not resolve %s in %s.txt", name, GAMEDATA_FILE);
	}
	return detour;
}

public void OnPluginEnd() {
	delete g_hSmokeWindowTimer;
	delete g_hSmokeClouds;
	// Deleting DynamicDetour handles removes their hooks, including partial startup.
	delete g_hBlockerDetour;
	delete g_hPlayerSightDetour;
	delete g_hFireDetour;
	delete g_hSightDetour;
	delete g_hGameData;
}

public void OnMapStart() {
	g_hSmokeClouds.Clear();
	g_fSmokeWindowEnd = 0.0;
	ResetGunfireCheckTimes();
	DisableVisionHooks();
	g_bResetVisionHooks = false;
	g_iBotCheckDepth = 0;
	g_iPlayerCheckDepth = 0;
	g_iPlayerBotDepth = 0;
	ResetCounters();
}

public void OnMapEnd() {
	delete g_hSmokeWindowTimer;
	g_hSmokeClouds.Clear();
	g_fSmokeWindowEnd = 0.0;
	DisableVisionHooks();
}

public void OnSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	CacheSettings();
	if (convar == g_cvEnabled || convar == g_cvRequireGunfire) {
		// No reconstruction of clouds when switching modes or re-enabling.
		g_hSmokeClouds.Clear();
		g_fSmokeWindowEnd = 0.0;
		ResetGunfireCheckTimes();
		g_bResetVisionHooks = true;
		QueueWindowUpdate();
	}
}

void CacheSettings() {
	g_bEnabled = g_cvEnabled.BoolValue;
	g_bRequireGunfire = g_cvRequireGunfire.BoolValue;
	float distance = g_cvDistance.FloatValue;
	g_fDistanceSquared = distance * distance;
	float radius = g_cvSmokeRadius.FloatValue;
	g_fSmokeRadiusSquared = radius * radius;
}

void ResetCounters() {
	g_iSightCalls = 0;
	g_iFireCalls = 0;
	g_iPlayerSightCalls = 0;
	g_iSightPassed = 0;
	g_iFirePassed = 0;
	g_iPlayerSightPassed = 0;
	g_iPlayerBypassed = 0;
	g_iScopedBlockerCalls = 0;
	g_iBlockedCalls = 0;
	g_iBypassedCalls = 0;
	g_fLastBlockedDistance = -1.0;
}

public MRESReturn Detour_Sight_Pre(DHookReturn hReturn, DHookParam hParams) {
	g_iSightCalls++;
	g_iBotCheckDepth++;
	return MRES_Ignored;
}

public MRESReturn Detour_Fire_Pre(DHookReturn hReturn, DHookParam hParams) {
	g_iFireCalls++;
	g_iBotCheckDepth++;
	return MRES_Ignored;
}

public MRESReturn Detour_Sight_Post(DHookReturn hReturn, DHookParam hParams) {
	if (hReturn.Value)
		g_iSightPassed++;
	if (g_iBotCheckDepth > 0)
		g_iBotCheckDepth--;
	return MRES_Ignored;
}

public MRESReturn Detour_Fire_Post(DHookReturn hReturn, DHookParam hParams) {
	if (hReturn.Value)
		g_iFirePassed++;
	if (g_iBotCheckDepth > 0)
		g_iBotCheckDepth--;
	return MRES_Ignored;
}

public MRESReturn Detour_PlayerSight_Pre(int client, DHookReturn hReturn, DHookParam hParams) {
	int depth = g_iPlayerCheckDepth++;
	if (depth >= MAX_PLAYER_CHECK_DEPTH)
		return MRES_Ignored;

	// Record each call's classification, rather than rechecking a possibly changed
	// client in Post. Nested human calls are also recorded, but never counted as bots.
	g_bPlayerCheckIsBot[depth] = client >= 1 && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client);
	if (g_bPlayerCheckIsBot[depth]) {
		g_iPlayerSightCalls++;
		g_iPlayerBotDepth++;
		g_iBotCheckDepth++;
	}
	return MRES_Ignored;
}

public MRESReturn Detour_PlayerSight_Post(int client, DHookReturn hReturn, DHookParam hParams) {
	if (g_iPlayerCheckDepth <= 0)
		return MRES_Ignored;

	int depth = --g_iPlayerCheckDepth;
	if (depth >= MAX_PLAYER_CHECK_DEPTH || !g_bPlayerCheckIsBot[depth])
		return MRES_Ignored;

	g_bPlayerCheckIsBot[depth] = false;
	if (hReturn.Value)
		g_iPlayerSightPassed++;
	g_iPlayerBotDepth--;
	g_iBotCheckDepth--;
	return MRES_Ignored;
}

public MRESReturn Detour_Blocker_Post(DHookReturn hReturn, DHookParam hParams) {
	if (g_iBotCheckDepth <= 0 || g_bResetVisionHooks)
		return MRES_Ignored;

	// Fail closed on excessive recursion or a human player check nested inside a
	// bot callback. The original shared blocker result must remain unchanged there.
	if (g_iPlayerCheckDepth > MAX_PLAYER_CHECK_DEPTH)
		return MRES_Ignored;
	if (g_iPlayerCheckDepth > 0 && !g_bPlayerCheckIsBot[g_iPlayerCheckDepth - 1])
		return MRES_Ignored;

	g_iScopedBlockerCalls++;
	if (!hReturn.Value)
		return MRES_Ignored;

	g_iBlockedCalls++;
	float start[3], end[3];
	hParams.GetVector(1, start);
	hParams.GetVector(2, end);
	float distanceSquared = GetVectorDistance(start, end, true);
	g_fLastBlockedDistance = SquareRoot(distanceSquared);
	if (!g_bEnabled || !(distanceSquared <= g_fDistanceSquared))
		return MRES_Ignored;
	if (g_bRequireGunfire && !CanBypassExposedSmoke(start, end))
		return MRES_Ignored;

	// Only negate this shared visual-blocker result, never the outer bot sight/fire
	// result. The native bool does not identify the blocking cloud. Our tracked spheres
	// are approximate; shared explosion blockers on an eligible line can also be bypassed.
	hReturn.Value = false;
	g_iBypassedCalls++;
	if (g_iPlayerBotDepth > 0)
		g_iPlayerBypassed++;
	return MRES_Override;
}

public Action Command_Status(int client, int args) {
	if (args > 0) {
		char option[16];
		GetCmdArg(1, option, sizeof(option));
		if (StrEqual(option, "reset", false))
			ResetCounters();
		else {
			ReplyToCommand(client, "[Bot Smoke] Usage: sm_botsmoke [reset]");
			return Plugin_Handled;
		}
	}

	ReplyToCommand(client, "[Bot Smoke] v%s | %s | distance %.0f units | native bot-vision threshold 64.", PL_VERSION, g_bEnabled ? "ENABLED" : "DISABLED", g_cvDistance.FloatValue);
	ReplyToCommand(client, "[Bot Smoke] Mode: %s.", g_bRequireGunfire ? "human gunfire near or aimed through smoke exposes individual clouds" : "full smoke window; gunfire and cloud-radius checks skipped");
	float remaining = g_fSmokeWindowEnd - GetGameTime();
	if (remaining < 0.0)
		remaining = 0.0;
	ReplyToCommand(client, "[Bot Smoke] Vision hooks: %s | exposure remaining: %.1fs | reveal per shot: %.1fs | smoke lifetime: %.1fs | radius: %.0f units.", g_bHooksEnabled ? "ACTIVE" : "IDLE", remaining, g_cvRevealTime.FloatValue, g_cvSmokeWindow.FloatValue, g_cvSmokeRadius.FloatValue);
	if (g_bRequireGunfire) {
		int activeClouds, exposedClouds;
		float now = GetGameTime();
		SmokeCloud cloud;
		int count = g_hSmokeClouds.Length;
		for (int i = 0; i < count; i++) {
			g_hSmokeClouds.GetArray(i, cloud, sizeof(cloud));
			if (cloud.expires <= now)
				continue;
			activeClouds++;
			if (g_bEnabled && cloud.revealedUntil > now)
				exposedClouds++;
		}
		ReplyToCommand(client, "[Bot Smoke] Tracked live clouds: %d | exposed clouds: %d.", activeClouds, exposedClouds);
		ReplyToCommand(client, "[Bot Smoke] Gunfire checks: at most once every %.1fs per human player, for all weapons.", GUNFIRE_CHECK_INTERVAL);
	}
	else
		ReplyToCommand(client, "[Bot Smoke] Per-cloud tracking is OFF; only the latest smoke expiry is stored.");
	ReplyToCommand(client, "[Bot Smoke] Weapon-fire event hook: %s.", g_bWeaponFireHooked ? "ON" : "OFF");
	ReplyToCommand(client, "[Bot Smoke] Counters reset on a new window, not extensions. Completed stats remain while idle; sm_botsmoke reset clears them manually.");
	ReplyToCommand(client, "[Bot Smoke] Sight passed/calls: %d/%d | firing passed/checks: %d/%d.", g_iSightPassed, g_iSightCalls, g_iFirePassed, g_iFireCalls);
	ReplyToCommand(client, "[Bot Smoke] Bot player-sight passed/calls: %d/%d | bypasses within player-sight: %d | scoped blocker calls: %d.", g_iPlayerSightPassed, g_iPlayerSightCalls, g_iPlayerBypassed, g_iScopedBlockerCalls);
	ReplyToCommand(client, "[Bot Smoke] Native blocked: %d | bypassed: %d | last blocked distance: %.1f (-1 = none) | context depth: %d.", g_iBlockedCalls, g_iBypassedCalls, g_fLastBlockedDistance, g_iBotCheckDepth);
	ReplyToCommand(client, "[Bot Smoke] Walls unchanged. Exception covers shared smoke/explosion clouds; counters are checks, not unique bots or players.");
	return Plugin_Handled;
}
