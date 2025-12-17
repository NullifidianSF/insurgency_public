// (C) 2014 Jared Ballou <sourcemod@jballou.com>
// Released under GPLv3

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION		"0.0.16"
#define PLUGIN_DESCRIPTION	"Plugin for pulling prop_ragdoll bodies"

#define MAXENTITIES 2048

#define MAX_BUTTONS         30			// we use up to bit 29
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
#define BTN_SPRINT          (1 << 15)		// hold sprint
#define BTN_WALK            (1 << 16)
#define BTN_SPECIAL1        (1 << 17)
#define BTN_AIM             (1 << 18)
#define BTN_SCOREBOARD      (1 << 19)
#define BTN_FLASHLIGHT      (1 << 22)
#define BTN_DUCK_TOGGLE     (1 << 24)		// crouch toggle
#define BTN_SPRINT_TOGGLE   (1 << 26)		// sprint toggle
#define BTN_AIM_TOGGLE      (1 << 27)
#define BTN_ACCESSORY       (1 << 28)
#define BTN_STANCE_TOGGLE   (1 << 29)		// change-stance key

// ----------------------
// compile-time switches (lite but safe preset)
// ----------------------
#define DRAG_USE_TRACE_RATED	1	// keep the ~20Hz downward ground trace while dragging (prone/downward only)
#define DRAG_USE_SAFETY_TIMER	1	// one post-release clamp 0.02s later

// ----------------------
// tuning
// ----------------------
#define DRAG_ACQUIRE_DIST_MAX	90.0	// Max distance (HU) from player to rag to START dragging (aim/cone/near checks).
										// ↑ Raise to grab from farther away (more forgiving).
										// ↓ Lower to require being closer (reduces wrong-body grabs).

#define DRAG_KEEP_DIST_MAX		160.0	// Max leash distance (HU) while dragging; beyond this we auto-drop.
										// ↑ Raise to move farther without dropping (can feel snappier/teleporty).
										// ↓ Lower to drop sooner if you run off.

#define DRAG_TARGET_AHEAD		38.0	// Forward offset (HU) from player feet for the target drag point.
										// ↑ Puts the rag further ahead (may snag on steps/ledges).
										// ↓ Keeps rag closer to you (safer when prone).

#define DRAG_Z_LIFT				10.0	// Extra vertical lift added on top of stance-based lift (prone/crouch).
										// ↑ Reduces ground scraping/sinking (can look floaty).
										// ↓ Tighter to ground (risk minor clipping on slopes).

#define DRAG_LERP				0.65	// Smoothing factor (0..1) toward target each tick.
										// ↑ Closer to 1 = snappier, reacts faster but can jitter.
										// ↓ Closer to 0 = smoother/laggier follow.

#define RAG_NEAR_SCAN_RADIUS	110.0	// Radius (HU) for fallback “cone” scan when foliage blocks aim traces.
										// ↑ Easier to acquire through bushes; may pick side rags unintentionally.
										// ↓ More precise but harder to grab in clutter.

#define FRONT_COS_THRESHOLD		0.35	// Dot-product threshold for “in front” cone (1=dead ahead, 0=90°, -1=behind).
										// ↑ Narrows cone (stricter front requirement).
										// ↓ Widens cone (easier to pick, less precise).

#define CLAMP_CLEARANCE_Z		15.0	// How far ABOVE the traced ground (HU) to place the rag when clamping.
										// ↑ Safer against sinks on uneven/displacement terrain.
										// ↓ Closer to ground; may scrape on bumps.

#define TRACE_RATE_SEC			0.05	// Minimum time between ground traces per dragging client (seconds).
										// ↓ More frequent traces (smoother over bumps; more CPU).
										// ↑ Fewer traces (lighter; less responsive on rough ground).

#define CLAMP_OFFSET			12.0	// Offset for multi-sample clamping (center + 4 points) if you enable that preset.
										// Kept for completeness; not used in the current single-point clamp.

#define DRAG_IGNORE_MAX_SEC 	2.0		// Hard cap on “ignore this rag” cooldown (protects against cross-map time drift).
										// If ignore exceeds this, it’s cleared immediately.

// ----------------------
// state
// ----------------------
int		ga_iDragRagRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
bool	ga_bDragging[MAXPLAYERS + 1] = { false, ... };
bool	ga_bDragViaCmd[MAXPLAYERS + 1] = { false, ... };
int		ga_iLastButtons[MAXPLAYERS + 1] = { 0, ... };
float	ga_fNextTraceTime[MAXPLAYERS + 1] = { 0.0, ... };
int		ga_iLastStance[MAXPLAYERS + 1] = { 0, ... };	// 0 stand, 1 crouch, 2 prone

float	g_fIgnoreUntil[MAXENTITIES + 1] = { 0.0, ... };
int		g_iActiveDrags = 0;

// Cached datamap offset (ragdoll teleport safety)
int		g_iOffsPhysicsObject = -1;

// --- NEW: ultra-light randomized tip pump (only when humans present) ---
Handle	g_hTipTimer = null;

// -------------------------------------------------------------

public Plugin myinfo = {
	name		= "dragragdoll",
	author		= "Daimyo, Nullifidian & ChatGPT",
	description	= PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url			= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Drag_IsEntityDragged", Native_IsEntityDragged);
	CreateNative("Drag_ForceDrop",       Native_ForceDrop);
	return APLRes_Success;
}

public any Native_IsEntityDragged(Handle plugin, int numParams)
{
	int ent = GetNativeCell(1);
	if (ent <= MaxClients || !IsValidEntity(ent)) return false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (ga_bDragging[i] && EntRefToEntIndex(ga_iDragRagRef[i]) == ent)
			return true;
	}
	return false;
}

public any Native_ForceDrop(Handle plugin, int numParams)
{
	int ent = GetNativeCell(1);
	if (ent > MaxClients && IsValidEntity(ent))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (ga_bDragging[i] && EntRefToEntIndex(ga_iDragRagRef[i]) == ent)
			{
				StopDragging(i);
				if (ent > 0 && ent < MAXENTITIES)
					g_fIgnoreUntil[ent] = GetGameTime() + 1.0;
				break;
			}
		}
	}
	return 0;
}

public void OnPluginStart()
{
	RegPluginLibrary("drag");
	RegConsoleCmd("drag", cmd_drag, "Toggle dragging a dead body (manual)");
	RegAdminCmd("sm_dragtip",  cmd_drag_tip, ADMFLAG_GENERIC, "Broadcast the dragging how-to tip.");
	RegAdminCmd("sm_dragdump",        cmd_drag_dump, ADMFLAG_RCON, "Dump info about the ragdoll you're aiming at.");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_end",    Event_RoundEnd,    EventHookMode_PostNoCopy);
	HookEvent("round_start",  Event_RoundStart,  EventHookMode_PostNoCopy);

	// Try to start the tip pump if humans are already around on late load
	EnsureTipTimer();
}

public void OnMapStart()
{
	for (int i = 0; i < MAXENTITIES; i++)
		g_fIgnoreUntil[i] = 0.0;
}

public void OnClientDisconnect(int client)
{
	if (ga_bDragging[client])
		StopDragging(client);

	ga_bDragViaCmd[client] = false;
	ga_iDragRagRef[client] = INVALID_ENT_REFERENCE;
	ga_iLastButtons[client] = 0;
	ga_iLastStance[client] = 0;
	ga_fNextTraceTime[client] = 0.0;

	// If the server is now empty, kill the tip pump so it does nothing while empty
	if (!HasAnyHumans())
		KillTipTimer();
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && ga_bDragging[client])
		StopDragging(client);
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	DropAllDrags();
	// Don't kill the tip pump on round end; it'll pause itself if empty
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	DropAllDrags();
	// Restart (or ensure) the tip pump on a new round if humans exist
	EnsureTipTimer();
	return Plugin_Continue;
}

public void OnMapEnd()
{
	DropAllDrags();
	KillTipTimer(); // clean end-of-map
}

static void DropAllDrags()
{
	for (int i = 1; i <= MaxClients; i++)
		if (ga_bDragging[i])
			StopDragging(i);
}

// ----------------------
// Tip pump helpers
// ----------------------

static bool HasAnyHumans()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			return true;
	return false;
}

static void EnsureTipTimer()
{
	if (g_hTipTimer != null) return;
	if (!HasAnyHumans()) return;

	// Schedule a single fire in 10–15 minutes; the callback will reschedule if still needed
	float delay = GetRandomFloat(600.0, 900.0);
	g_hTipTimer = CreateTimer(delay, Timer_DragTip, _, TIMER_FLAG_NO_MAPCHANGE);
}

static void KillTipTimer()
{
	if (g_hTipTimer != null)
	{
		CloseHandle(g_hTipTimer);
		g_hTipTimer = null;
	}
}

public Action Timer_DragTip(Handle timer, any data)
{
	// This is a one-shot: clear handle first
	g_hTipTimer = null;

	if (HasAnyHumans())
	{
		BroadcastDragTip();
		// Chain another random one-shot
		EnsureTipTimer();
	}
	// If empty, do nothing; the next EnsureTipTimer() happens on join/round start
	return Plugin_Stop;
}

static void BroadcastDragTip()
{
	PrintToChatAll("\x04Dragging:\x01 crouched/prone + (Sprint hold/toggle + Duck) or Stance Toggle. \nTo bind: bind <key> drag.");
}

// ----------------------
// drag core
// ----------------------

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	int last    = ga_iLastButtons[client];
	int pressed = (buttons ^ last) & buttons;

	// Sprint “active” if either hold or toggle bit is set
	bool sprintActive = (buttons & (BTN_SPRINT | BTN_SPRINT_TOGGLE)) != 0;

	bool stanceKnown = false;
	int  stance = 0;

	// ---- Toggle gesture (supports hold/toggle sprint & duck, stance key) ----
	// Start/stop when sprint is active AND (duck just pressed OR stance key pressed OR stance became not-standing
	// OR sprint was just pressed while already not-standing), and not firing.
	if (!ga_bDragViaCmd[client] && sprintActive && !(buttons & BTN_ATTACK1))
	{
		bool duckPressed       = (pressed & (BTN_DUCK | BTN_DUCK_TOGGLE)) != 0;
		bool stanceKeyPressed  = (pressed & BTN_STANCE_TOGGLE) != 0;
		bool sprintJustPressed = (pressed & (BTN_SPRINT | BTN_SPRINT_TOGGLE)) != 0;

		if (!stanceKnown)
		{
			stance = GetEntProp(client, Prop_Send, "m_iCurrentStance"); // 0 stand, 1 crouch, 2 prone
			stanceKnown = true;
		}
		bool becameNotStanding = (ga_iLastStance[client] == 0 && stance != 0);

		// allow sprint edge while already crouched/prone to (re)start dragging
		bool sprintEdgeWhileNotStanding = sprintJustPressed && (stance != 0);

		if (duckPressed || stanceKeyPressed || becameNotStanding || sprintEdgeWhileNotStanding)
		{
			if (ga_bDragging[client])	StopDragging(client);
			else						StartDragging(client, false);
		}
	}

	// ---- Maintain active drag (require not-standing; allow toggles) ----
	if (ga_bDragging[client])
	{
		if (!stanceKnown)
		{
			stance = GetEntProp(client, Prop_Send, "m_iCurrentStance");
			stanceKnown = true;
		}

		if (stance == 0)
		{
			StopDragging(client);
		}
		else
		{
			if (buttons & BTN_ATTACK1)
			{
				StopDragging(client);
			}
			else
			{
				int rag = EntRefToEntIndex(ga_iDragRagRef[client]);
				if (rag == INVALID_ENT_REFERENCE || !IsValidEntity(rag))
				{
					StopDragging(client);
				}
				else
				{
					PullRagdollTowardPlayer(client, rag);
				}
			}
		}
	}

	ga_iLastButtons[client] = buttons;

	// keep stance history updated with minimal reads
	if (stanceKnown)
		ga_iLastStance[client] = stance;
	else if (sprintActive || ga_bDragging[client])
		ga_iLastStance[client] = GetEntProp(client, Prop_Send, "m_iCurrentStance");

	return Plugin_Continue;
}

public Action cmd_drag(int client, int args)
{
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return Plugin_Handled;

	if (ga_bDragging[client])	StopDragging(client);
	else						StartDragging(client, true);

	return Plugin_Handled;
}

// ----------------------
// helpers
// ----------------------

static int FindClosestRagdollNearPoint(const float p[3], float radius, float now)
{
	int best = -1;
	float bestDistSqr = radius * radius;

	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "prop_ragdoll")) != -1)
	{
		if (!IsValidEntity(ent)) continue;

		// Skip recently forced-dropped rags (compatible with your native)
		if (ent > 0 && ent < MAXENTITIES && g_fIgnoreUntil[ent] > now)
			continue;

		if (IsRagAlreadyDragged(ent)) continue;

		float pos[3];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);

		float dx = pos[0] - p[0];
		float dy = pos[1] - p[1];
		float dz = pos[2] - p[2];
		float d2 = dx*dx + dy*dy + dz*dz;

		if (d2 <= bestDistSqr)
		{
			bestDistSqr = d2;
			best = ent;
		}
	}
	return best;
}

static void StartDragging(int client, bool viaCmd)
{
	int rag = AcquireRagdoll(client);
	if (rag == -1)
		return;

	int cg = GetEntProp(rag, Prop_Data, "m_CollisionGroup", 1);
	if (cg == 17)
		SetEntProp(rag, Prop_Data, "m_CollisionGroup", 1);

	// Freeze physics so it can't sink while we steer it
	SetEntityMoveType(rag, MOVETYPE_NONE);

	ga_iDragRagRef[client] = EntIndexToEntRef(rag);
	ga_bDragging[client] = true;
	g_iActiveDrags++;
	ga_bDragViaCmd[client] = viaCmd;
	ga_fNextTraceTime[client] = 0.0;
}

static void StopDragging(int client)
{
	int rag = EntRefToEntIndex(ga_iDragRagRef[client]);
	if (rag != INVALID_ENT_REFERENCE && IsValidEntity(rag))
	{
		// Clamp to ground while still frozen
		ClampRagToGround(rag, client);

		// Restore physics + wake
		SetEntityMoveType(rag, MOVETYPE_VPHYSICS);
		AcceptEntityInput(rag, "Wake");

		#if DRAG_USE_SAFETY_TIMER
		// Safety clamp shortly after release in case solver nudges down
		CreateTimer(0.02, Timer_SettleClamp, EntIndexToEntRef(rag), TIMER_FLAG_NO_MAPCHANGE);
		#endif
	}

	if (ga_bDragging[client] && g_iActiveDrags > 0) g_iActiveDrags--;

	ga_bDragging[client] = false;
	ga_bDragViaCmd[client] = false;
	ga_iDragRagRef[client] = INVALID_ENT_REFERENCE;
	ga_fNextTraceTime[client] = 0.0;
}

static bool IsRagdoll(int ent)
{
	if (ent <= MaxClients || !IsValidEntity(ent))
		return false;

	char cls[32];
	GetEntityClassname(ent, cls, sizeof cls);
	return (cls[0] == 'p' && StrEqual(cls, "prop_ragdoll", false));
}

static bool EntHasPhysicsObject(int ent) {
	if (ent <= MaxClients || !IsValidEntity(ent))
		return false;

	if (g_iOffsPhysicsObject == -1) {
		g_iOffsPhysicsObject = FindDataMapInfo(ent, "m_pPhysicsObject");
		if (g_iOffsPhysicsObject == -1)
			g_iOffsPhysicsObject = -2;
	}

	if (g_iOffsPhysicsObject == -2)
		return true;

	return (GetEntData(ent, g_iOffsPhysicsObject) != 0);
}

static int AcquireRagdoll(int client)
{
	float now = GetGameTime();

	// -------- Pass A: direct aim first
	int aimed = GetClientAimTarget(client, false);
	if (aimed != -1 && IsRagdoll(aimed))
	{
		if (aimed > 0 && aimed < MAXENTITIES && g_fIgnoreUntil[aimed] > now) {
			if (g_fIgnoreUntil[aimed] - now > DRAG_IGNORE_MAX_SEC)
				g_fIgnoreUntil[aimed] = 0.0;
			else
				return -1;
		}

		if (IsRagAlreadyDragged(aimed))
			return -1;

		if (IsCloseEnough(client, aimed, DRAG_ACQUIRE_DIST_MAX))
			return aimed;
	}

	// -------- Precompute eye/fwd once
	float eye[3], ang[3], fwd[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

	// A point ahead of the player (slightly further than DRAG_TARGET_AHEAD to clear the player bbox)
	float aimPoint[3];
	aimPoint[0] = eye[0] + fwd[0] * 60.0;
	aimPoint[1] = eye[1] + fwd[1] * 60.0;
	aimPoint[2] = eye[2] + fwd[2] * 10.0;

	// -------- Pass B: nearest rag to aim point (handles foliage / tiny props)
	{
		int nearAim = FindClosestRagdollNearPoint(aimPoint, 56.0, now);
		if (nearAim != -1)
		{
			// Slightly relaxed distance for this pass
			if (IsCloseEnough(client, nearAim, DRAG_ACQUIRE_DIST_MAX + 20.0))
				return nearAim;
		}
	}

	// -------- Pass C: your original front-cone scan (kept, small tweaks)
	int best = -1;
	float bestDist = 999999.0;

	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "prop_ragdoll")) != -1)
	{
		if (!IsValidEntity(ent)) continue;

		if (ent > 0 && ent < MAXENTITIES && g_fIgnoreUntil[ent] > now) {
			if (g_fIgnoreUntil[ent] - now > DRAG_IGNORE_MAX_SEC)
				g_fIgnoreUntil[ent] = 0.0;
			else
				continue;
		}

		if (IsRagAlreadyDragged(ent)) continue;

		float pos[3];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);

		float to[3];
		MakeVectorFromPoints(eye, pos, to);
		float dist = GetVectorLength(to);
		if (dist > RAG_NEAR_SCAN_RADIUS) continue;

		NormalizeVector(to, to);
		float dot = GetVectorDotProduct(fwd, to);
		if (dot < FRONT_COS_THRESHOLD) continue;

		if (dist < bestDist)
		{
			bestDist = dist;
			best = ent;
		}
	}
	if (best != -1 && IsCloseEnough(client, best, DRAG_ACQUIRE_DIST_MAX))
		return best;

	// -------- Pass D: last-resort small "feet bubble" when you're basically on top of it
	float feet[3];
	GetClientAbsOrigin(client, feet);
	int nearFeet = FindClosestRagdollNearPoint(feet, 64.0, now);
	if (nearFeet != -1)
		return nearFeet;

	return -1;
}

static bool IsCloseEnough(int client, int ent, float maxd)
{
	float a[3], b[3];
	GetClientAbsOrigin(client, a);
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", b);
	return (GetVectorDistance(a, b) <= maxd);
}

public bool TraceFilter_IgnorePlayersAndEnt(int entity, int contentsMask, any data)
{
	return (entity > MaxClients && entity != data);
}

// Returns ground Z under XY, or guessZ if nothing hit
static float GroundZAt(float x, float y, float guessZ, int ignoreEnt)
{
	float start[3];
	start[0] = x;
	start[1] = y;
	start[2] = guessZ + 64.0;

	float end[3];
	end[0] = x;
	end[1] = y;
	end[2] = guessZ - 1024.0;

	Handle tr = TR_TraceRayFilterEx(start, end, MASK_SOLID, RayType_EndPoint, TraceFilter_IgnorePlayersAndEnt, ignoreEnt);
	float z = guessZ;
	if (TR_DidHit(tr))
	{
		float hit[3];
		TR_GetEndPosition(hit, tr);
		z = hit[2];
	}
	CloseHandle(tr);
	return z;
}

// Clamp to ground at current XY (single point); if trace misses and client valid, don't go below client feet
static void ClampRagToGround(int rag, int client)
{
	float pos[3];
	GetEntPropVector(rag, Prop_Send, "m_vecOrigin", pos);

	float gz = GroundZAt(pos[0], pos[1], pos[2], rag);
	if (gz != pos[2])
	{
		pos[2] = gz + CLAMP_CLEARANCE_Z;
	}
	else if (client > 0 && IsClientInGame(client))
	{
		float feet[3];
		GetClientAbsOrigin(client, feet);
		float minZ = feet[2] + 2.0;
		if (pos[2] < minZ)
			pos[2] = minZ;
	}

	if (!EntHasPhysicsObject(rag))
		return;

	static const float VEC_ZERO[3] = { 0.0, 0.0, 0.0 };
	TeleportEntity(rag, pos, NULL_VECTOR, VEC_ZERO);
}

#if DRAG_USE_SAFETY_TIMER
public Action Timer_SettleClamp(Handle timer, any ragRef)
{
	int rag = EntRefToEntIndex(ragRef);
	if (rag <= MaxClients || !IsValidEntity(rag))
		return Plugin_Stop;

	float pos[3];
	GetEntPropVector(rag, Prop_Send, "m_vecOrigin", pos);

	float gz = GroundZAt(pos[0], pos[1], pos[2], rag);
	if (gz != pos[2])
	{
		float wantZ = gz + CLAMP_CLEARANCE_Z;
		if (pos[2] < wantZ)
		{
			pos[2] = wantZ;
			if (EntHasPhysicsObject(rag)) {
				static const float VEC_ZERO[3] = { 0.0, 0.0, 0.0 };
				TeleportEntity(rag, pos, NULL_VECTOR, VEC_ZERO);
				AcceptEntityInput(rag, "Wake");
			}
		}
	}

	return Plugin_Stop;
}
#endif

static void PullRagdollTowardPlayer(int client, int rag)
{
	if (!IsValidEntity(rag) || !IsRagdoll(rag))
	{
		StopDragging(client);
		return;
	}

	if (!IsCloseEnough(client, rag, DRAG_KEEP_DIST_MAX))
	{
		StopDragging(client);
		return;
	}

	float feet[3], ang[3], fwd[3], target[3], curr[3];
	GetClientAbsOrigin(client, feet);
	GetClientEyeAngles(client, ang);
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

	int stance = GetEntProp(client, Prop_Send, "m_iCurrentStance"); // 0 stand, 1 crouch, 2 prone
	float baseLift = (stance >= 2) ? 4.0 : 8.0;					// adjust to 3.0/6.0 if you like
	float ahead    = (stance >= 2) ? 30.0 : DRAG_TARGET_AHEAD;	// shorter reach when prone

	float zFeetTarget = feet[2] + baseLift + DRAG_Z_LIFT;

	target[0] = feet[0] + fwd[0] * ahead;
	target[1] = feet[1] + fwd[1] * ahead;
	target[2] = zFeetTarget;

	GetEntPropVector(rag, Prop_Send, "m_vecOrigin", curr);

	bool needClamp = (stance >= 2) || (target[2] < curr[2]);

	#if DRAG_USE_TRACE_RATED
	if (needClamp)
	{
		float now = GetGameTime();
		if (now >= ga_fNextTraceTime[client])
		{
			float start[3];
			start[0] = target[0];
			start[1] = target[1];
			start[2] = target[2] + 48.0;

			float end[3];
			end[0] = target[0];
			end[1] = target[1];
			end[2] = target[2] - 256.0;

			Handle tr = TR_TraceRayFilterEx(start, end, MASK_SOLID_BRUSHONLY, RayType_EndPoint, TraceFilter_IgnorePlayersAndEnt, rag);
			if (TR_DidHit(tr))
			{
				float hit[3];
				TR_GetEndPosition(hit, tr);
				float gz = hit[2] + CLAMP_CLEARANCE_Z;
				if (target[2] < gz)
					target[2] = gz;
			}
			CloseHandle(tr);

			ga_fNextTraceTime[client] = now + TRACE_RATE_SEC;
		}
		else
		{
			float minZ = feet[2] + 2.0;
			if (target[2] < minZ)
				target[2] = minZ;
		}
	}
	#else
	if (needClamp)
	{
		float minZ = feet[2] + 2.0;
		if (target[2] < minZ)
			target[2] = minZ;
	}
	#endif

	float dest[3];
	dest[0] = curr[0] + (target[0] - curr[0]) * DRAG_LERP;
	dest[1] = curr[1] + (target[1] - curr[1]) * DRAG_LERP;
	dest[2] = curr[2] + (target[2] - curr[2]) * DRAG_LERP;

	if (!EntHasPhysicsObject(rag))
		return;

	static const float VEC_ZERO[3] = { 0.0, 0.0, 0.0 };
	TeleportEntity(rag, dest, NULL_VECTOR, VEC_ZERO);
}

public void OnEntityDestroyed(int ent)
{
	if (g_iActiveDrags == 0) return;
	if (ent <= MaxClients) return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!ga_bDragging[i]) continue;

		int rag = EntRefToEntIndex(ga_iDragRagRef[i]);
		if (rag == ent)
		{
			ga_iDragRagRef[i] = INVALID_ENT_REFERENCE;
			ga_bDragging[i] = false;
			ga_bDragViaCmd[i] = false;
			if (g_iActiveDrags > 0) g_iActiveDrags--;
		}
	}
}

static bool IsRagAlreadyDragged(int ent)
{
	for (int i = 1; i <= MaxClients; i++)
		if (ga_bDragging[i] && EntRefToEntIndex(ga_iDragRagRef[i]) == ent)
			return true;
	return false;
}

public Action cmd_drag_tip(int client, int args)
{
	if (client == 0)
	{
		BroadcastDragTip();
		PrintToServer("[PullRag] Tip broadcasted.");
		return Plugin_Handled;
	}

	if (!IsClientInGame(client))
		return Plugin_Handled;

	if (!HasAnyHumans())
	{
		ReplyToCommand(client, "[PullRag] No human players online; not broadcasting.");
		return Plugin_Handled;
	}

	BroadcastDragTip();
	ReplyToCommand(client, "[PullRag] Tip sent to all players.");
	return Plugin_Handled;
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (ga_bDragging[i])
			StopDragging(i);
	}
	KillTipTimer();
}

static int GetAimRagdoll(int client)
{
	int ent = GetClientAimTarget(client, false);
	return (ent != -1 && IsRagdoll(ent)) ? ent : -1;
}

public Action cmd_drag_dump(int client, int args)
{
	int ent = (client == 0) ? -1 : GetAimRagdoll(client);
	if (client != 0 && ent == -1) { ReplyToCommand(client, "[PullRag] Aim at a ragdoll."); return Plugin_Handled; }

	if (client == 0)
	{
		// server console: dump first valid rag near crosshair is not available; list all briefly
		int count = 0, e = -1;
		while ((e = FindEntityByClassname(e, "prop_ragdoll")) != -1 && count < 12)
		{
			DumpRagState(0, e);
			count++;
		}
		if (count == 0) PrintToServer("[PullRag] No ragdolls on map.");
		return Plugin_Handled;
	}

	DumpRagState(client, ent);
	return Plugin_Handled;
}

static void DumpRagState(int client, int ent)
{
	if (ent <= MaxClients || !IsValidEntity(ent))
	{
		if (client == 0) PrintToServer("[PullRag] Invalid ent %d", ent);
		else ReplyToCommand(client, "[PullRag] Invalid ent %d", ent);
		return;
	}

	// BEFORE: int mt = GetEntityMoveType(ent);
	MoveType mt = GetEntityMoveType(ent);  // <-- fix tag
	int cg = GetEntProp(ent, Prop_Data, "m_CollisionGroup", 1);
	int st = GetEntProp(ent, Prop_Send, "m_nSolidType", 1);
	int owner = GetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity");
	bool healthy = IsCandidateHealthy(ent);

	float now = GetGameTime();
	float ignoreLeft = 0.0;
	if (ent > 0 && ent < MAXENTITIES && g_fIgnoreUntil[ent] > now)
		ignoreLeft = g_fIgnoreUntil[ent] - now;

	char cls[32]; GetEntityClassname(ent, cls, sizeof cls);

	// Cast MoveType to int for %d
	int mt_i = view_as<int>(mt);

	if (client == 0)
	{
		PrintToServer("[PullRag] ent=%d (%s) mt=%d cg=%d st=%d owner=%d healthy=%d ignore=%.2f",
			ent, cls, mt_i, cg, st, owner, healthy ? 1 : 0, ignoreLeft);
	}
	else
	{
		ReplyToCommand(client, "[PullRag] ent=%d (%s) mt=%d cg=%d st=%d owner=%d healthy=%d ignore=%.2f",
			ent, cls, mt_i, cg, st, owner, healthy ? 1 : 0, ignoreLeft);
	}
}

static bool IsCandidateHealthy(int ent)
{
	// BEFORE: int mt = GetEntityMoveType(ent);
	MoveType mt = GetEntityMoveType(ent);  // <-- fix tag

	if (mt != MOVETYPE_VPHYSICS && mt != MOVETYPE_NONE)
		return false;

	int cg = GetEntProp(ent, Prop_Data, "m_CollisionGroup", 1);
	if (cg == 17)
		return false;

	int solidType = GetEntProp(ent, Prop_Send, "m_nSolidType", 1);
	if (solidType != 6) // SOLID_VPHYSICS
		return false;

	return true;
}