#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#define PLUGIN_NAME		"Advanced Parachute"
#define PLUGIN_VERSION	"2.0.4"
#define PLUGIN_AUTHOR	"ESK0"

#define	BTN_USE			(1 << 6)
#define EDICT_RESERVE	64
#define BOT_RETRY_DELAY	0.5
#define BOT_MIN_DROP	128.0

public Plugin myinfo = {
	name	= PLUGIN_NAME,
	version	= PLUGIN_VERSION,
	author	= PLUGIN_AUTHOR,
	url		= ""
};

// ------------------------------------------------------------
// Config / assets
// ------------------------------------------------------------
char sFilePath[PLATFORM_MAX_PATH];

char sAllowedMaps[][] = {
	"ins_mountain_escape_v1_3",
	"frequency_open_coop",
	"chateau_tunnels_v3",
	"haditha_dam_coop_finale",
	"haditha_dam_2022",
	"ins_coastdawn_a3"
};

// ------------------------------------------------------------
// State
// ------------------------------------------------------------
int			g_LastButtons[MAXPLAYERS + 1] = {0, ...};
int			g_iParachuteRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};	// entref (safe)
bool		g_bChuteOpen[MAXPLAYERS + 1] = {false, ...};						// fast state bit
bool		g_bAttachQueued[MAXPLAYERS + 1] = {false, ...};
Handle		g_hTimerAd[MAXPLAYERS + 1];
float		g_fNextBotAttempt[MAXPLAYERS + 1];
bool		g_bBotAirborne[MAXPLAYERS + 1];
float		g_fBotPeakHeight[MAXPLAYERS + 1];
ArrayList	g_PendingKills;
ArrayList	g_BotModels;

int			g_iDefaultPar = -1;
ArrayList	arParachuteList;
StringMap	smParachutes;

Handle		g_hParachute;			// clientprefs cookie
Handle		g_hOnParachute;			// forward OnParachuteOpen(client)
bool		g_bAllowedMap = false;
int			g_iOpenChuteCount = 0;

// ------------------------------------------------------------
// Forwards / library
// ------------------------------------------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_hOnParachute = CreateGlobalForward("OnParachuteOpen", ET_Event, Param_Cell);
	RegPluginLibrary("AdvancedParachute");
	return APLRes_Success;
}

// ------------------------------------------------------------
// Plugin lifecycle
// ------------------------------------------------------------
public void OnPluginStart() {
	RegConsoleCmd("sm_parachute", Command_Parachute);

	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/AdvancedParachute.cfg");

	arParachuteList = new ArrayList(ByteCountToCells(64));
	smParachutes = new StringMap();
	g_PendingKills = new ArrayList();
	g_BotModels = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	HookEvent("player_death", Event_ResetParachute);
	HookEvent("player_spawn", Event_ResetParachute);

	g_hParachute = RegClientCookie("advanced_parachute_test", "Parachute clientprefs", CookieAccess_Private);
}

public void OnMapStart() {
	g_bAllowedMap = false;
	g_iOpenChuteCount = 0;
	for (int client = 1; client <= MaxClients; client++) {
		ChuteClearState(client);
		g_LastButtons[client] = 0;
		ResetBotFallTracking(client);
	}

	char sMapname[64];
	GetCurrentMap(sMapname, sizeof(sMapname));

	for (int i = 0; i < sizeof(sAllowedMaps); i++) {
		if (strcmp(sMapname, sAllowedMaps[i], false) == 0) {
			g_bAllowedMap = true;
			break;
		}
	}

	if (!g_bAllowedMap) {
		CreateTimer(1.0, Timer_UnloadSelf, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	PrecacheModels();

	g_iDefaultPar = -1;
	arParachuteList.Clear();
	smParachutes.Clear();

	if (!FileExists(sFilePath)) {
		SetFailState("[AdvancedParachute] Missing config: %s", sFilePath);
		return;
	}
	KeyValues kv = new KeyValues("AdvancedParachute");
	if (!kv.ImportFromFile(sFilePath)) {
		delete kv;
		SetFailState("[AdvancedParachute] Unable to parse config: %s", sFilePath);
		return;
	}
	if (kv.GotoFirstSubKey()) {
		AdvP_AddParachute(kv);
		while (kv.GotoNextKey())
			AdvP_AddParachute(kv);
	}
	delete kv;

	if (g_iDefaultPar == -1) {
		SetFailState("[AdvancedParachute] Default parachute not found in config");
		return;
	}

	for (int client = 1; client <= MaxClients; client++)
		if (IsValidClient(client) && IsClientAuthorized(client))
			OnClientPostAdminCheck(client);
}

public void OnMapEnd() {
	CleanupParachutes();
}

public void OnPluginEnd() {
	CleanupParachutes();
}

void CleanupParachutes() {
	g_bAllowedMap = false;
	for (int client = 1; client <= MaxClients; client++) {
		delete g_hTimerAd[client];
		int ent = ChuteEntIndex(client);
		ChuteClearState(client);
		if (ent != -1)
			RemoveEntity(ent);
		g_LastButtons[client] = 0;
		ResetBotFallTracking(client);
	}
	if (g_PendingKills != null) {
		for (int i = 0; i < g_PendingKills.Length; i++) {
			int ent = EntRefToEntIndex(g_PendingKills.Get(i));
			if (ent > MaxClients && IsValidEntity(ent))
				RemoveEntity(ent);
		}
		g_PendingKills.Clear();
	}
	g_iOpenChuteCount = 0;
}

public Action Timer_UnloadSelf(Handle timer) {
	char fn[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, fn, sizeof fn);
	ServerCommand("sm plugins unload \"%s\"", fn);
	return Plugin_Stop;
}

// ------------------------------------------------------------
// Client lifecycle
// ------------------------------------------------------------
public void OnClientPostAdminCheck(int client) {
	if (!g_bAllowedMap || !IsValidClient(client) || IsFakeClient(client))
		return;

	if (g_iDefaultPar < 0 || arParachuteList.Length == 0)
		return;

	if (g_hTimerAd[client] == null)
		g_hTimerAd[client] = CreateTimer(90.0, Timer_PrintMsg, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	ValidateClientCookie(client);
}

public void OnClientCookiesCached(int client) {
	if (IsValidClient(client) && IsClientAuthorized(client))
		ValidateClientCookie(client);
}

void ValidateClientCookie(int client) {
	if (!g_bAllowedMap || IsFakeClient(client) || !AreClientCookiesCached(client) || g_iDefaultPar < 0)
		return;

	// Ensure cookie is a valid choice (or set default)
	char sDefault[64];
	arParachuteList.GetString(g_iDefaultPar, sDefault, sizeof sDefault);

	char sCookie[64];
	GetClientCookie(client, g_hParachute, sCookie, sizeof sCookie);

	// Access is checked when selecting or opening, since admin loading may still be pending.
	if (sCookie[0] == '\0' || arParachuteList.FindString(sCookie) == -1)
		SetClientCookie(client, g_hParachute, sDefault);
}

public void OnClientPutInServer(int client) {
	RemoveParachute(client);
	g_LastButtons[client] = 0;
	ResetBotFallTracking(client);
}

public void OnClientDisconnect(int client) {
	g_LastButtons[client] = 0;
	RemoveParachute(client);
	delete g_hTimerAd[client];
	ResetBotFallTracking(client);
}

// ------------------------------------------------------------
// Gameplay
// ------------------------------------------------------------
public void OnGameFrame() {
	if (!g_bAllowedMap || g_iOpenChuteCount == 0)
		return;

	for (int client = 1; client <= MaxClients; client++) {
		if (!g_bChuteOpen[client])
			continue;

		int ent = ChuteEntIndex(client);
		if (!IsValidClient(client, true) || ent == -1 || (GetEntityFlags(client) & FL_ONGROUND)) {
			RemoveParachute(client);
			continue;
		}

		float chuteAngles[3];
		if (GetClientEyeAngles(client, chuteAngles)) {
			float parentAngles[3], currentAngles[3];
			GetClientAbsAngles(client, parentAngles);
			GetEntPropVector(ent, Prop_Data, "m_angRotation", currentAngles);
			// TeleportEntity applies local angles to a parented prop.
			chuteAngles[0] = 0.0;
			chuteAngles[1] -= parentAngles[1];
			if (chuteAngles[1] > 180.0)
				chuteAngles[1] -= 360.0;
			else if (chuteAngles[1] < -180.0)
				chuteAngles[1] += 360.0;
			chuteAngles[2] = 0.0;
			if (FloatAbs(chuteAngles[1] - currentAngles[1]) > 0.1 || currentAngles[0] != 0.0 || currentAngles[2] != 0.0)
				TeleportEntity(ent, NULL_VECTOR, chuteAngles, NULL_VECTOR);
		}

		float vel[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vel);

		if (vel[2] < 0.0) {
			const float clampDown = -100.0;
			if (vel[2] < clampDown) {
				vel[2] += 50.0;
				if (vel[2] > clampDown)
					vel[2] = clampDown;
			}
			else
				vel[2] = clampDown;

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!g_bAllowedMap)
		return Plugin_Continue;

	if (!IsValidClient(client, true))
		return Plugin_Continue;

	int flags = GetEntityFlags(client);
	if (flags & FL_ONGROUND)
		ResetBotFallTracking(client);

	// Auto-close when hitting ground
	if ((g_bChuteOpen[client] || g_bAttachQueued[client]) && (flags & FL_ONGROUND))
		RemoveParachute(client);

	bool usePressed = (buttons & BTN_USE) && !(g_LastButtons[client] & BTN_USE);
	bool useReleased = !(buttons & BTN_USE) && (g_LastButtons[client] & BTN_USE);

	if (!IsFakeClient(client)) {
		// Open on +use if mid-air and no chute
		if (usePressed && !g_bChuteOpen[client] && !(flags & FL_ONGROUND))
			QueueAttachParachute(client);

		// Close on -use
		if (useReleased) {
			g_bAttachQueued[client] = false;
			if (g_bChuteOpen[client])
				RemoveParachute(client);
		}
	}
	else {
		if (!IsBotFallMovement(client))
			ResetBotFallTracking(client);
		else if (!(flags & FL_ONGROUND) && !g_bChuteOpen[client]) {
			float origin[3];
			GetClientAbsOrigin(client, origin);
			if (!g_bBotAirborne[client] || origin[2] > g_fBotPeakHeight[client]) {
				g_fBotPeakHeight[client] = origin[2];
				g_bBotAirborne[client] = true;
			}

			QueueAttachParachute(client);
		}
	}

	g_LastButtons[client] = buttons;
	return Plugin_Continue;
}

public Action Event_ResetParachute(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0) {
		RemoveParachute(client);
		g_LastButtons[client] = 0;
		ResetBotFallTracking(client);
	}
	return Plugin_Continue;
}

// ------------------------------------------------------------
// Commands / Menus
// ------------------------------------------------------------
public Action Command_Parachute(int client, int args) {
	if (!g_bAllowedMap || !IsValidClient(client) || IsFakeClient(client) || arParachuteList.Length == 0)
		return Plugin_Handled;

	if (!AreClientCookiesCached(client)) {
		PrintToChat(client, "[Advanced Parachute] Your saved settings are still loading. Please try again shortly.");
		return Plugin_Handled;
	}

	Menu menu = new Menu(h_parachutemenu);
	menu.SetTitle("Advanced Parachute");

	char sCurrent[64];
	GetClientCookie(client, g_hParachute, sCurrent, sizeof sCurrent);

	for (int i = 0; i < arParachuteList.Length; i++) {
		char sName[64];
		char sConf[512];
		char parts[2][512];

		arParachuteList.GetString(i, sName, sizeof sName);
		smParachutes.GetString(sName, sConf, sizeof sConf);
		ExplodeString(sConf, ";", parts, sizeof parts, sizeof parts[]);

		int flags = ReadFlagString(parts[1]);

		bool allowed = (parts[1][0] == '\0') ? true : CheckCommandAccess(client, "", flags, true);
		int draw = allowed && !StrEqual(sName, sCurrent, false) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
		menu.AddItem(sName, sName, draw);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int h_parachutemenu(Menu menu, MenuAction action, int client, int item) {
	if (!IsValidClient(client)) {
		if (action == MenuAction_End)
			delete menu;
		return 0;
	}

	if (action == MenuAction_Select) {
		char chosen[64];
		menu.GetItem(item, chosen, sizeof chosen);
		char conf[512], parts[2][512];
		if (!g_bAllowedMap || !AreClientCookiesCached(client) || !smParachutes.GetString(chosen, conf, sizeof conf))
			return 0;
		ExplodeString(conf, ";", parts, sizeof parts, sizeof parts[]);
		if (parts[1][0] != '\0' && !CheckCommandAccess(client, "", ReadFlagString(parts[1]), true))
			return 0;
		SetClientCookie(client, g_hParachute, chosen);
	}
	else if (action == MenuAction_End)
		delete menu;
	return 0;
}

// ------------------------------------------------------------
// Parachute attach/remove
// ------------------------------------------------------------
stock void ChuteClearState(int client) {
	if (g_bChuteOpen[client] && g_iOpenChuteCount > 0)
		g_iOpenChuteCount--;

	g_bAttachQueued[client] = false;
	g_bChuteOpen[client] = false;
	g_iParachuteRef[client] = INVALID_ENT_REFERENCE;
}

stock int ChuteEntIndex(int client) {
	int ref = g_iParachuteRef[client];
	if (ref == INVALID_ENT_REFERENCE)
		return -1;

	int ent = EntRefToEntIndex(ref);
	if (ent == INVALID_ENT_REFERENCE || ent <= MaxClients || !IsValidEntity(ent))
		return -1;

	return ent;
}

void ResetBotFallTracking(int client) {
	g_bBotAirborne[client] = false;
	g_fBotPeakHeight[client] = 0.0;
	g_fNextBotAttempt[client] = 0.0;
}

bool IsBotFallMovement(int client) {
	MoveType moveType = GetEntityMoveType(client);
	// Bot locomotion is not restricted to the human player's MOVETYPE_WALK.
	return moveType != MOVETYPE_NONE && moveType != MOVETYPE_NOCLIP && moveType != MOVETYPE_OBSERVER && moveType != MOVETYPE_LADDER;
}

bool ShouldBotDeployParachute(int client) {
	if (!g_bBotAirborne[client] || !IsBotFallMovement(client) || (GetEntityFlags(client) & FL_ONGROUND))
		return false;

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	if (velocity[2] >= 0.0)
		return false;

	float origin[3];
	GetClientAbsOrigin(client, origin);
	// Track the apex so boosted bots can deploy before falling below their launch height.
	return g_fBotPeakHeight[client] - origin[2] >= BOT_MIN_DROP;
}

void QueueAttachParachute(int client) {
	if (!g_bAllowedMap || !IsValidClient(client, true) || g_bChuteOpen[client] || g_bAttachQueued[client])
		return;

	if (GetEntityFlags(client) & FL_ONGROUND)
		return;

	if (IsFakeClient(client)) {
		float now = GetGameTime();
		if (now < g_fNextBotAttempt[client] || !ShouldBotDeployParachute(client))
			return;
		g_fNextBotAttempt[client] = now + BOT_RETRY_DELAY;
	}

	g_bAttachQueued[client] = true;
	RequestFrame(DeferredAttachParachute, GetClientUserId(client));
}

public void DeferredAttachParachute(any userid) {
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients)
		return;

	if (!g_bAttachQueued[client])
		return;

	g_bAttachQueued[client] = false;

	if (!g_bAllowedMap || !IsValidClient(client, true) || g_bChuteOpen[client])
		return;

	if (GetEntityFlags(client) & FL_ONGROUND)
		return;

	if (IsFakeClient(client)) {
		if (!ShouldBotDeployParachute(client))
			return;
	}
	else if ((GetClientButtons(client) & BTN_USE) == 0)
		return;

	AttachParachute(client);
}

void AttachParachute(int client) {
	if (!g_bAllowedMap || !IsValidClient(client, true) || g_bChuteOpen[client])
		return;

	Action result = Plugin_Continue;
	Call_StartForward(g_hOnParachute);
	Call_PushCell(client);
	Call_Finish(result);
	if (result == Plugin_Stop || result == Plugin_Handled)
		return;

	// Forward listeners can disconnect, kill or move the client.
	if (!g_bAllowedMap || !IsValidClient(client, true) || g_bChuteOpen[client] || (GetEntityFlags(client) & FL_ONGROUND))
		return;
	if (IsFakeClient(client)) {
		if (!ShouldBotDeployParachute(client))
			return;
	}
	else if ((GetClientButtons(client) & BTN_USE) == 0)
		return;

	// Leave networked entity slots available for gameplay entities.
	if (GetEntityCount() >= GetMaxEntities() - EDICT_RESERVE)
		return;

	char modelStr[PLATFORM_MAX_PATH];
	modelStr[0] = '\0';

	if (!IsFakeClient(client)) {
		char sCookie[64];
		if (AreClientCookiesCached(client))
			GetClientCookie(client, g_hParachute, sCookie, sizeof sCookie);

		char sConf[512];
		if (smParachutes.GetString(sCookie, sConf, sizeof sConf)) {
			char parts[2][512];
			ExplodeString(sConf, ";", parts, sizeof parts, sizeof parts[]);
			if (parts[1][0] == '\0' || CheckCommandAccess(client, "", ReadFlagString(parts[1]), true))
				strcopy(modelStr, sizeof modelStr, parts[0]);
		}
		if (modelStr[0] == '\0') {
			// fallback to default section
			char defName[64];
			arParachuteList.GetString(g_iDefaultPar, defName, sizeof defName);
			if (smParachutes.GetString(defName, sConf, sizeof sConf)) {
				char dparts[2][512];
				ExplodeString(sConf, ";", dparts, sizeof dparts, sizeof dparts[]);
				strcopy(modelStr, sizeof modelStr, dparts[0]);
			}
		}
	}
	else {
		if (g_BotModels.Length == 0)
			return;
		g_BotModels.GetString(GetRandomInt(0, g_BotModels.Length - 1), modelStr, sizeof modelStr);
	}

	if (modelStr[0] == '\0' || !IsModelPrecached(modelStr))
		return;

	int ent = CreateEntityByName("prop_dynamic_override");
	if (ent == -1 || !IsValidEntity(ent))
		return;

	int ref = EntIndexToEntRef(ent);
	DispatchKeyValue(ent, "model", modelStr);
	// A cosmetic chute does not need a VPhysics collision body or trigger bounds.
	DispatchKeyValue(ent, "solid", "0");

	if (!DispatchSpawn(ent)) {
		KillParachuteRef(ref);
		return;
	}

	ent = EntRefToEntIndex(ref);
	if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent))
		return;
	if (!g_bAllowedMap || !IsValidClient(client, true) || (GetEntityFlags(client) & FL_ONGROUND)) {
		KillParachuteRef(ref);
		return;
	}

	SetEntProp(ent, Prop_Send, "m_usSolidFlags", 4);
	SetEntProp(ent, Prop_Data, "m_nSolidType", 0);
	SetEntProp(ent, Prop_Send, "m_CollisionGroup", 1);

	float origin[3];
	float attachAng[3];

	GetClientAbsOrigin(client, origin);
	if (!GetClientEyeAngles(client, attachAng))
		GetClientAbsAngles(client, attachAng);
	attachAng[0] = 0.0;
	attachAng[2] = 0.0;

	TeleportEntity(ent, origin, attachAng, NULL_VECTOR);
	SetVariantString("!activator");
	if (!AcceptEntityInput(ent, "SetParent", client)) {
		KillParachuteRef(ref);
		return;
	}

	ent = EntRefToEntIndex(ref);
	if (ent == INVALID_ENT_REFERENCE || !IsValidEntity(ent))
		return;

	if (StrContains(modelStr, "gargoyle", false) != -1) {
		SetVariantString("idle");
		AcceptEntityInput(ent, "SetAnimation");
	}

	if (EntRefToEntIndex(ref) == INVALID_ENT_REFERENCE)
		return;
	if (!g_bAllowedMap || !IsValidClient(client, true) || (GetEntityFlags(client) & FL_ONGROUND)) {
		KillParachuteRef(ref);
		return;
	}

	g_iParachuteRef[client] = ref;
	g_bChuteOpen[client] = true;
	g_iOpenChuteCount++;
}

void RemoveParachute(int client) {
	g_bAttachQueued[client] = false;
	if (!g_bChuteOpen[client] && g_iParachuteRef[client] == INVALID_ENT_REFERENCE)
		return;

	int ref = g_iParachuteRef[client];

	// Clear state first, then kill next frame (avoids same-frame parent/owner issues)
	ChuteClearState(client);

	if (ref != INVALID_ENT_REFERENCE) {
		g_PendingKills.Push(ref);
		RequestFrame(DeferredKillRef, ref);
	}
}

public void DeferredKillRef(any ref) {
	int index = g_PendingKills.FindValue(ref);
	if (index == -1)
		return;
	g_PendingKills.Erase(index);
	KillParachuteRef(ref);
}

void KillParachuteRef(int ref) {
	int ent = EntRefToEntIndex(ref);
	if (ent > MaxClients && ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
		RemoveEntity(ent);
}

// ------------------------------------------------------------
// Chat nudges (optional)
// ------------------------------------------------------------
public Action Timer_PrintMsg(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (client == 0 || g_hTimerAd[client] != timer)
		return Plugin_Stop;

	if (!IsClientInGame(client) || !g_bAllowedMap) {
		g_hTimerAd[client] = null;
		return Plugin_Stop;
	}

	if (GetClientTeam(client) == 2) {
		PrintToChat(client, "\x070088cc[BM]\x01 Hello \x07ffff00%N\x01, you can use a parachute on this map.", client);
		PrintToChat(client, "\x070088cc[BM]\x01 Hold \x07ffff00USE (F)\x01 to open. Type \x07ffff00!parachute\x01 for skins.");
	}
	return Plugin_Continue;
}

// ------------------------------------------------------------
// Config loading helpers
// ------------------------------------------------------------
void AdvP_AddParachute(KeyValues kv) {
	char sName[64];
	char sModel[PLATFORM_MAX_PATH];
	char sFlag[32];
	char sPack[512];

	kv.GetSectionName(sName, sizeof sName);

	kv.GetString("model", sModel, sizeof sModel);
	ReplaceString(sModel, sizeof sModel, "\\", "/");
	kv.GetString("flag", sFlag, sizeof sFlag, "");
	if (arParachuteList.FindString(sName) != -1) {
		LogError("[AdvancedParachute] Duplicate parachute: %s", sName);
		return;
	}
	if (StrContains(sModel, ";") != -1 || StrContains(sFlag, ";") != -1 || !PrecacheParachuteModel(sModel)) {
		LogError("[AdvancedParachute] Skipping invalid parachute: %s (%s)", sName, sModel);
		return;
	}
	arParachuteList.PushString(sName);

	if (g_iDefaultPar == -1 && kv.GetNum("default", 0) == 1)
		g_iDefaultPar = arParachuteList.Length - 1;

	Format(sPack, sizeof sPack, "%s;%s", sModel, sFlag);
	smParachutes.SetString(sName, sPack);
}

// ------------------------------------------------------------
// Precaching
// ------------------------------------------------------------
void PrecacheModels() {
	static const char models[][] = {
		"models/parachute/umbrella_big2.mdl",
		"models/parachute/parachute_ark.mdl",
		"models/parachute/parachute_bf2.mdl",
		"models/parachute/parachute_bf2002.mdl",
		"models/parachute/parachute_bf2142.mdl",
		"models/parachute/parachute_blue.mdl",
		"models/parachute/parachute_carbon.mdl",
		"models/parachute/parachute_green_v2.mdl",
		"models/parachute/parachute_ice_v2.mdl",
		"models/parachute/parachute_rainbow.mdl",
		"models/parachute/parachute_spongebob.mdl",
		"models/parachute/parachute_star_fox_guard.mdl"
	};
	g_BotModels.Clear();
	for (int i = 0; i < sizeof(models); i++)
		if (PrecacheParachuteModel(models[i]))
			g_BotModels.PushString(models[i]);
	if (g_BotModels.Length == 0)
		LogError("[AdvancedParachute] No bot parachute models are available on this map");

	// Materials (Generic precache to avoid late precache warnings)
	PrecacheGeneric("materials/models/parachute/body.vmt", true);
	PrecacheGeneric("materials/models/parachute/gargoyle.vmt", true);
	PrecacheGeneric("materials/models/parachute/pack.vmt", true);
	PrecacheGeneric("materials/models/parachute/pack_carbon.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute2002.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute2142.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_ark.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_ark_backpack.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_blue.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_c.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_carbon.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_green_v2.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_ice_v2.vmt", true);
	PrecacheGeneric("materials/models/parachute/parachute_rainbow.vmt", true);
	PrecacheGeneric("materials/models/parachute/patrick_flag.vmt", true);
	PrecacheGeneric("materials/models/props/de_dust/hr_dust/dust_patio_set/dust_patio_umbrella_color.vmt", true);
}

bool PrecacheParachuteModel(const char[] model) {
	int length = strlen(model);
	if (length < 5 || StrContains(model, "models/", false) != 0 || !StrEqual(model[length - 4], ".mdl", false) || !FileExists(model, true))
		return false;
	return IsModelPrecached(model) || PrecacheModel(model, true) > 0;
}

// ------------------------------------------------------------
// Utils
// ------------------------------------------------------------
bool IsValidClient(int client, bool alive = false) {
	if (client > 0 && client <= MaxClients && IsClientInGame(client)) {
		if (!alive || IsPlayerAlive(client))
			return true;
	}
	return false;
}
