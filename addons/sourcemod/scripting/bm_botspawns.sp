// [INS] Bot Spawn Marker & Saver
// - Manual spawn placement per-CP for Insurgency 2014
// - Visual indicators while editing
// - Save/Load KeyValues file format
// - No cvars; tweak constants below
//
// Usage: sm_botspawns  (main menu)
//        sm_botspawns_load, sm_botspawns_save, sm_botspawns_clearvis
//
// Access: ADMFLAG_RCON
//
// File: addons/sourcemod/data/bm_botspawns/<mapname>.txt
//
// © 2025 Nullifidian + ChatGPT collab. Public domain-like; do what you want.
//
// Build: requires <sdktools> and <sdktools_tempents>

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdktools_tempents>

#define MAX_CPS				32
#define MAX_CAPTURE_ZONES	64

#define TEAM_SPECTATOR		1
#define TEAM_SECURITY		2
#define TEAM_INSURGENT		3

#define BTN_JUMP			(1 << 1)
#define FL_ONGROUND			(1 << 0)
static int g_iPrevButtons[MAXPLAYERS + 1];

static const char ga_Letters[][] = {
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
	"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
	"?"
};

// ─────────────────────────────────────────────────────────────────────────────
// Constants / settings (no cvars)
// ─────────────────────────────────────────────────────────────────────────────

static const float	kZOffsetOnAdd		= 10.0;		// +Z so bots don’t stick in ground
static const float	kDuplicateMinDist	= 32.0;		// warn if closer than this
static const float	kVisTickInterval	= 0.75;		// seconds per redraw while menus open
static const char	kDirRel[]			= "addons/sourcemod/data/bm_botspawns";

// Visuals: colors (r,g,b,a)
static const int	kColor_CP[4]		= {  80, 180, 255, 200 };	// cyan/blue
static const int	kColor_CA[4]		= { 255, 140,  60, 200 };	// orange
static const int	kColor_Hi[4]		= { 255, 220,  60, 255 };	// highlight pulse

// Beam/Glow visuals
static const float	kBeamWidth			= 4.0;
static const float	kBeamLife			= 0.75;
//static const float	kGlowLife			= 0.75;
static const float	kPillarHeight		= 64.0;

// draw at most this many POINTS per tick (each = 2 temp ents)
static const int	kDrawPointBudget	= 64;

// My movement speed
static const float kMovementSpeed = 3.0;
// My jump speed
static const float kJumpSpeed = 1.5;

// ─────────────────────────────────────────────────────────────────────────────
// Globals
// ─────────────────────────────────────────────────────────────────────────────

enum EAddKind { Add_CP = 0, Add_CA = 1 };

ArrayList g_CPSpawns[MAX_CPS];	// per-CP list of float[3]
ArrayList g_CASpawns[MAX_CPS];	// per-CP list of float[3]

int		g_iNumCPs = 0;

// per-client UI state
int		g_iSelectedCP[MAXPLAYERS + 1] = { -1, ... };
bool	g_bAnyMenuOpen[MAXPLAYERS + 1] = { false, ... };
Handle	g_hVisTimer[MAXPLAYERS + 1] = { null, ... };
bool	g_bAddMenuOpen[MAXPLAYERS + 1] = { false, ... };

// per-client undo history: each entry = (cp << 1) | (isCA ? 1 : 0)
ArrayList g_UndoStack[MAXPLAYERS + 1] = { null, ... };
static int  BM_PackUndoCode(int cp, bool isCA) { return (cp << 1) | (isCA ? 1 : 0); }
static int  BM_CodeToCP(int code)             { return (code >> 1); }
static bool BM_CodeIsCA(int code)             { return (code & 1) != 0; }

// TempEnt sprite
int		g_iSpriteBeam = -1;

bool	g_bFlipDrawOrder[MAXPLAYERS + 1] = { false, ... };
int		g_iVisCurCP[MAXPLAYERS + 1] = { 0, ... };
int		g_iVisCurCA[MAXPLAYERS + 1] = { 0, ... };

// Cap-blocking while editing (now done by CZ spawnflags)
int		g_iCapBlockUsers = 0;

// Cached trigger_capture_zone brushes (for spawnflag toggle)
int		g_iCZCount = 0;
int		g_iCZEnt[MAX_CAPTURE_ZONES];			// entrefs
int		g_iCZSpawnflags[MAX_CAPTURE_ZONES];		// original flags

Handle ga_hSpeedTimer[MAXPLAYERS + 1];

bool g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public Plugin myinfo =
{
	name		= "bm_botspawns",
	author		= "Nullifidian + ChatGPT",
	description = "A tool for manually placing bot spawn locations per CP and CA for the bm_botrespawn plugin. Remember to remove this plugin after use.",
	version		= "1.1.0",
	url			= ""
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
	RegAdminCmd("sm_botspawns",			Cmd_Main,			ADMFLAG_RCON, "Open bot spawn editor menu");
	RegAdminCmd("sm_botspawns_save",	Cmd_SaveNow,		ADMFLAG_RCON, "Save spawns to file immediately");
	RegAdminCmd("sm_botspawns_load",	Cmd_LoadNow,		ADMFLAG_RCON, "Load spawns from file");
	RegAdminCmd("sm_botspawns_clearvis",Cmd_ClearVis,		ADMFLAG_RCON, "Clear/stop visuals for your client");

	HookEvent("player_spawn", Event_PlayerSpawn);

	for (int i = 0; i < MAX_CPS; i++)
	{
		if (g_CPSpawns[i] == null) g_CPSpawns[i] = new ArrayList(3);
		if (g_CASpawns[i] == null) g_CASpawns[i] = new ArrayList(3);
	}

	for (int c = 1; c <= MaxClients; c++)
	{
		if (g_UndoStack[c] == null)
			g_UndoStack[c] = new ArrayList();
	}
}

public void OnMapStart()
{
	// Determine #CPs
	g_iNumCPs = BM_GetNumControlPoints();

	// Precache beam
	g_iSpriteBeam = PrecacheModel("materials/sprites/laser.vmt", true);

	// Clear runtime state per client
	for (int c = 1; c <= MaxClients; c++)
	{
		g_iSelectedCP[c] = (g_iNumCPs > 0) ? 0 : -1;
		g_bAnyMenuOpen[c] = false;
		g_bAddMenuOpen[c] = false;
		KillVisTimer(c);
		KillSpeedTimer(c);
		if (g_UndoStack[c] != null) g_UndoStack[c].Clear();
	}

	if (g_bLateLoad)
		BM_CacheCaptureZones();

	// Load spawns for the map
	char map[64]; GetCurrentMap(map, sizeof map);
	int before = BM_TotalCountAll();
	bool ok = BM_LoadFromFile(map);
	int after = BM_TotalCountAll();
	PrintToServer("[BM] BotSpawns: loaded=%s, cp_count=%d, total=%d (was %d)", ok ? "yes" : "no", g_iNumCPs, after, before);

	// reset cap block
	g_iCapBlockUsers = 0;
}

public void OnMapEnd()
{
	// extra safety: restore flags on map end
	BM_CZAllowClients(true);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	RequestFrame(FR_BMCacheCaptureZones);
	return Plugin_Continue;
}

void FR_BMCacheCaptureZones() {
	BM_CacheCaptureZones();
}

public void OnClientDisconnect(int client)
{
	if (g_UndoStack[client] != null) g_UndoStack[client].Clear();

	if (g_bAnyMenuOpen[client])
	{
		if (g_bAddMenuOpen[client])
			BM_RemoveCapUser();

		g_bAnyMenuOpen[client] = false;
		g_bAddMenuOpen[client] = false;
		KillVisTimer(client);

		if (g_iCapBlockUsers > 0)
		{
			g_iCapBlockUsers--;
			if (g_iCapBlockUsers == 0)
				BM_CZAllowClients(true);
		}
	}

	g_iPrevButtons[client] = 0;

	KillSpeedTimer(client);

}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SECURITY)
		return Plugin_Continue;

	FakeClientCommandEx(client, "god");
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (client < 1 || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	bool pressed = (buttons & BTN_JUMP) && !(g_iPrevButtons[client] & BTN_JUMP);

	if (pressed && (GetEntityFlags(client) & FL_ONGROUND)) {
		if (HasEntProp(client, Prop_Send, "m_flLaggedMovementValue") && ga_hSpeedTimer[client] == null) {
			SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", kJumpSpeed);
			ga_hSpeedTimer[client] = CreateTimer(0.25, Timer_SetMoveSpeed, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}

		SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", {0.0, 0.0, 900.0});
	}

	g_iPrevButtons[client] = buttons;
	return Plugin_Continue;
}

Action Timer_SetMoveSpeed(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
		KillSpeedTimer(client);
		return Plugin_Stop;
	}

	if ((GetEntityFlags(client) & FL_ONGROUND) && HasEntProp(client, Prop_Send, "m_flLaggedMovementValue")) {
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", kMovementSpeed);
		KillSpeedTimer(client);
	}

	return Plugin_Continue;
}

static void KillSpeedTimer(int client) {
	if (ga_hSpeedTimer[client] != null) {
		KillTimer(ga_hSpeedTimer[client]);
		ga_hSpeedTimer[client] = null;
	}
}

public Action Cmd_Main(int client, int args)
{
	if (!BM_IsClientOK(client)) return Plugin_Handled;
	OpenMainMenu(client);
	return Plugin_Handled;
}

public Action Cmd_SaveNow(int client, int args)
{
	if (!BM_IsClientOK(client)) return Plugin_Handled;

	char map[64]; GetCurrentMap(map, sizeof map);
	bool ok = BM_SaveToFile(map);
	PrintToChat(client, "[BM] Save %s for map '%s'.", ok ? "OK" : "FAILED", map);
	return Plugin_Handled;
}

public Action Cmd_LoadNow(int client, int args)
{
	if (!BM_IsClientOK(client)) return Plugin_Handled;

	char map[64]; GetCurrentMap(map, sizeof map);
	bool ok = BM_LoadFromFile(map);
	PrintToChat(client, "[BM] Load %s for map '%s'.", ok ? "OK" : "FAILED/MISSING", map);
	return Plugin_Handled;
}

public Action Cmd_ClearVis(int client, int args)
{
	if (!BM_IsClientOK(client)) return Plugin_Handled;

	if (g_bAddMenuOpen[client])
		BM_RemoveCapUser();

	g_bAnyMenuOpen[client] = false;
	g_bAddMenuOpen[client] = false;
	KillVisTimer(client);
	PrintToChat(client, "[BM] Visuals cleared.");

	return Plugin_Handled;
}

// ─────────────────────────────────────────────────────────────────────────────
// Menus
// ─────────────────────────────────────────────────────────────────────────────

static void OpenMainMenu(int client)
{
	char cpfmt[16];
	BM_CPFmt(g_iSelectedCP[client], cpfmt, sizeof cpfmt);

	int ltr = LetterIndex(g_iSelectedCP[client]);

	Menu m = new Menu(H_Main);
	m.SetTitle("Bot Spawns Editor\nSelected CP: %s (%s) - total: %d",
		(g_iSelectedCP[client] >= 0) ? cpfmt : "none", ga_Letters[ltr], g_iNumCPs);

	m.AddItem("1", "Select CP");
	m.AddItem("2", "Add spawns");
	m.AddItem("3", "Remove spawns");
	m.AddItem("4", "Save to file");

	m.ExitButton = true;
	m.Display(client, 0);

	// safe: only real players, in game
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
	{
		if (HasEntProp(client, Prop_Send, "m_flLaggedMovementValue"))
		{
			SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", kMovementSpeed);
		}

		if (HasEntProp(client, Prop_Send, "m_flStamina"))
		{
			SetEntPropFloat(client, Prop_Send, "m_flStamina", 99999.0);
		}

		if (HasEntProp(client, Prop_Send, "m_flStartStamina"))
		{
			SetEntPropFloat(client, Prop_Send, "m_flStartStamina", 99999.0);
		}
	}
}

public int H_Main(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char info[8]; m.GetItem(item, info, sizeof info);
		switch (info[0])
		{
			case '1': OpenSelectCPMenu(client);
			case '2': OpenAddMenu(client);
			case '3': OpenRemoveMenu(client);
			case '4': OpenSaveConfirm(client);
		}
	}
	return 0;
}

static void OpenSelectCPMenu(int client)
{
	char cpfmt[16];
	BM_CPFmt(g_iSelectedCP[client], cpfmt, sizeof cpfmt);

	int letSel = LetterIndex(g_iSelectedCP[client]);

	Menu m = new Menu(H_SelectCP);
	m.SetTitle("Select CP (selected: %s (%s) - total: %d)",
		(g_iSelectedCP[client] >= 0) ? cpfmt : "none", ga_Letters[letSel], g_iNumCPs);

	for (int cp = 0; cp < g_iNumCPs; cp++)
	{
		char key[8]; IntToString(cp, key, sizeof key);
		int ltr = LetterIndex(cp);
		char lbl[64]; Format(lbl, sizeof lbl, "CP#%d (%s) | Spawns: CP %d CA %d", cp, ga_Letters[ltr], g_CPSpawns[cp].Length, g_CASpawns[cp].Length);
		m.AddItem(key, lbl);
	}
	m.ExitBackButton = true;
	m.Display(client, 0);
}

public int H_SelectCP(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char key[8]; m.GetItem(item, key, sizeof key);
		int cp = StringToInt(key);
		if (cp >= 0 && cp < g_iNumCPs)
		{
			bool changed = (g_iSelectedCP[client] != cp);
			g_iSelectedCP[client] = cp;
			if (changed && g_bAnyMenuOpen[client])
			{
				StartVisTimer(client);
			}
		}
		OpenMainMenu(client);
	}
	else if (a == MenuAction_Cancel)
	{
		OpenMainMenu(client);
	}
	return 0;
}

static void OpenAddMenu(int client)
{
	if (!BM_EnsureSelectedCP(client)) { OpenMainMenu(client); return; }
	bool firstEnter = false;
	if (!g_bAddMenuOpen[client])
	{
		g_bAddMenuOpen[client] = true;
		firstEnter = true;
	}

	g_bAnyMenuOpen[client] = true;
	StartVisTimer(client);

	if (firstEnter)
		BM_AddCapUser();

	int cp = g_iSelectedCP[client];

	char cpfmt[16];
	BM_CPFmt(g_iSelectedCP[client], cpfmt, sizeof cpfmt);

	int ltr = LetterIndex(cp);

	Menu m = new Menu(H_Add);
	m.SetTitle("Add spawns for %s (%s)\nCP: %d CA: %d Total for All CPs: %d",
		cpfmt, ga_Letters[ltr], g_CPSpawns[cp].Length, g_CASpawns[cp].Length, BM_TotalCountAll());

	m.AddItem("a1", "Add spawn");
	m.AddItem("a2", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);
	m.AddItem("a3", "Add spawn for CA");
	m.AddItem("a4", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);
	m.AddItem("a5", "Undo (this CP)");

	m.ExitBackButton = true;
	m.Display(client, 0);
}

public int H_Add(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char info[8]; m.GetItem(item, info, sizeof info);
		int cp = g_iSelectedCP[client];
		if (cp < 0 || cp >= g_iNumCPs) { OpenMainMenu(client); return 0; }

		if (StrEqual(info, "a1"))
		{
			float v[3];
			GetClientAbsOrigin(client, v);
			v[2] += kZOffsetOnAdd;

			if (!BM_CanAddSpawn(client, cp, Add_CP, v))
			{
				StartVisTimer(client);
				OpenAddMenu(client);
				return 0;
			}

			g_CPSpawns[cp].PushArray(v, 3);
			BM_PushUndo(client, cp, Add_CP);
			BM_NotifyCounts(client, cp);
			StartVisTimer(client);
		}
		else if (StrEqual(info, "a3"))
		{
			float v[3];
			GetClientAbsOrigin(client, v);
			v[2] += kZOffsetOnAdd;

			if (!BM_CanAddSpawn(client, cp, Add_CA, v))
			{
				StartVisTimer(client);
				OpenAddMenu(client);
				return 0;
			}

			g_CASpawns[cp].PushArray(v, 3);
			BM_PushUndo(client, cp, Add_CA);
			BM_NotifyCounts(client, cp);
			StartVisTimer(client);
		}
		else if (StrEqual(info, "a5"))
		{
			if (!BM_DoUndoOneForSelectedCP(client))
				PrintToChat(client, "[BM] Nothing to undo for this CP.");
			BM_NotifyCounts(client, g_iSelectedCP[client]);
			StartVisTimer(client);
		}

		OpenAddMenu(client);
	}
	else if (a == MenuAction_Cancel)
	{
		if (g_bAddMenuOpen[client])
			BM_RemoveCapUser();

		g_bAnyMenuOpen[client] = false;
		g_bAddMenuOpen[client] = false;
		KillVisTimer(client);

		OpenMainMenu(client);
	}
	return 0;
}

static void OpenRemoveMenu(int client)
{
	if (!BM_EnsureSelectedCP(client)) { OpenMainMenu(client); return; }

	g_bAnyMenuOpen[client] = true;
	g_bAddMenuOpen[client] = false;
	StartVisTimer(client);

	int cp = g_iSelectedCP[client];

	char cpfmt[16];
	BM_CPFmt(g_iSelectedCP[client], cpfmt, sizeof cpfmt);

	int ltr = LetterIndex(cp);

	Menu m = new Menu(H_RemoveRoot);
	m.SetTitle("Remove spawns for %s (%s)\nCP: %d CA: %d Total for All CPs: %d",
		cpfmt, ga_Letters[ltr], g_CPSpawns[cp].Length, g_CASpawns[cp].Length, BM_TotalCountAll());

	m.AddItem("r1", "Remove");
	m.AddItem("r2", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);
	m.AddItem("r3", "Remove closest to you");
	m.AddItem("r4", " ", ITEMDRAW_DISABLED | ITEMDRAW_SPACER);
	m.AddItem("r5", "Remove all spawns");

	m.ExitBackButton = true;
	m.Display(client, 0);
}

public int H_RemoveRoot(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char info[8]; m.GetItem(item, info, sizeof info);
		int cp = g_iSelectedCP[client];
		if (cp < 0 || cp >= g_iNumCPs) { OpenMainMenu(client); return 0; }

		if (StrEqual(info, "r1"))
		{
			OpenRemoveListMenu(client);
			return 0;
		}
		else if (StrEqual(info, "r3"))
		{
			float me[3]; GetClientAbsOrigin(client, me);

			bool isCA; int idx; float pos[3]; float d2;
			if (!BM_FindClosestSpawn(cp, me, isCA, idx, pos, d2))
			{
				PrintToChat(client, "[BM] No spawns to remove on this CP.");
				OpenRemoveMenu(client);
				return 0;
			}

			BM_HighlightPoint(client, pos, isCA ? kColor_CA : kColor_CP, true);
			OpenRemoveOneConfirm(client, isCA, idx);
			return 0;
		}
		else if (StrEqual(info, "r5"))
		{
			OpenRemoveAllConfirm(client);
			return 0;
		}

		OpenRemoveMenu(client);
	}
	else if (a == MenuAction_Cancel)
	{
		g_bAnyMenuOpen[client] = false;
		g_bAddMenuOpen[client] = false;
		KillVisTimer(client);
		OpenMainMenu(client);
	}
	return 0;
}

static void OpenRemoveListMenu(int client)
{
	if (!BM_EnsureSelectedCP(client)) { OpenMainMenu(client); return; }
	int cp = g_iSelectedCP[client];

	char cpfmt[16];
	BM_CPFmt(g_iSelectedCP[client], cpfmt, sizeof cpfmt);

	Menu m = new Menu(H_RemoveList);
	m.SetTitle("Select spawn to remove for %s", cpfmt);

	int nCP = g_CPSpawns[cp].Length;
	for (int i = 0; i < nCP; i++)
	{
		float v[3]; g_CPSpawns[cp].GetArray(i, v, 3);

		char key[16]; Format(key, sizeof key, "C:%d", i);
		char lbl[128]; Format(lbl, sizeof lbl, "CP  %02d) %.0f, %.0f, %.2f", i, v[0], v[1], v[2]);
		m.AddItem(key, lbl);
	}

	int nCA = g_CASpawns[cp].Length;
	for (int i = 0; i < nCA; i++)
	{
		float v[3]; g_CASpawns[cp].GetArray(i, v, 3);

		char key[16]; Format(key, sizeof key, "A:%d", i);
		char lbl[128]; Format(lbl, sizeof lbl, "CA  %02d) %.0f, %.0f, %.2f", i, v[0], v[1], v[2]);
		m.AddItem(key, lbl);
	}

	if (nCP + nCA == 0)
	{
		m.AddItem("none", "(no spawns)", ITEMDRAW_DISABLED);
	}

	m.ExitBackButton = true;
	m.Display(client, 0);
}

public int H_RemoveList(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char key[16]; m.GetItem(item, key, sizeof key);

		if (StrEqual(key, "none"))
		{
			OpenRemoveMenu(client);
			return 0;
		}

		int cp = g_iSelectedCP[client];
		if (cp < 0 || cp >= g_iNumCPs) { OpenMainMenu(client); return 0; }

		bool isCA = (key[0] == 'A');
		int idx = StringToInt(key[2]);

		float v[3];
		if (isCA)
		{
			if (idx < 0 || idx >= g_CASpawns[cp].Length) { OpenRemoveListMenu(client); return 0; }
			g_CASpawns[cp].GetArray(idx, v, 3);
		}
		else
		{
			if (idx < 0 || idx >= g_CPSpawns[cp].Length) { OpenRemoveListMenu(client); return 0; }
			g_CPSpawns[cp].GetArray(idx, v, 3);
		}

		BM_HighlightPoint(client, v, isCA ? kColor_CA : kColor_CP, true);
		OpenRemoveOneConfirm(client, isCA, idx);
	}
	else if (a == MenuAction_Cancel)
	{
		OpenRemoveMenu(client);
	}
	return 0;
}

static void OpenRemoveOneConfirm(int client, bool isCA, int idx)
{
	Menu m = new Menu(H_RemoveOneConfirm);

	char cap[48]; strcopy(cap, sizeof cap, isCA ? "CA" : "CP");
	m.SetTitle("Remove this %s spawn?\nAre you sure?", cap);

	char key[16]; Format(key, sizeof key, "%c:%d", isCA ? 'A' : 'C', idx);
	m.AddItem(key, "YES");
	m.AddItem("no", "NO");

	m.ExitBackButton = true;
	m.Display(client, 0);
}

public int H_RemoveOneConfirm(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char key[16]; m.GetItem(item, key, sizeof key);
		if (StrEqual(key, "no"))
		{
			OpenRemoveMenu(client);
			return 0;
		}

		bool isCA = (key[0] == 'A');
		int idx = StringToInt(key[2]);
		int cp = g_iSelectedCP[client];
		if (cp < 0 || cp >= g_iNumCPs) { OpenMainMenu(client); return 0; }

		if (isCA)
		{
			if (idx >= 0 && idx < g_CASpawns[cp].Length)
				g_CASpawns[cp].Erase(idx);
		}
		else
		{
			if (idx >= 0 && idx < g_CPSpawns[cp].Length)
				g_CPSpawns[cp].Erase(idx);
		}

		BM_NotifyCounts(client, cp);
		StartVisTimer(client);
		OpenRemoveMenu(client);
	}
	else if (a == MenuAction_Cancel)
	{
		OpenRemoveMenu(client);
	}
	return 0;
}

static void OpenRemoveAllConfirm(int client)
{
	int cp = g_iSelectedCP[client];
	char cpfmt[16];
	BM_CPFmt(cp, cpfmt, sizeof cpfmt);

	int ltr = LetterIndex(cp);

	Menu m = new Menu(H_RemoveAllConfirm);
	m.SetTitle("Remove ALL spawns for %s (%s) (CP %d)?\nThis clears CP and CA.", cpfmt, ga_Letters[ltr], cp);
	m.AddItem("YES", "YES");
	m.AddItem("NO",  "NO");
	m.ExitBackButton = true;
	m.Display(client, 0);
}

public int H_RemoveAllConfirm(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char k[8]; m.GetItem(item, k, sizeof k);
		if (k[0] == 'Y')
		{
			int cp = g_iSelectedCP[client];
			if (cp >= 0 && cp < g_iNumCPs)
			{
				g_CPSpawns[cp].Clear();
				g_CASpawns[cp].Clear();
				BM_NotifyCounts(client, cp);
				StartVisTimer(client);
			}
		}
		OpenRemoveMenu(client);
	}
	else if (a == MenuAction_Cancel)
	{
		OpenRemoveMenu(client);
	}
	return 0;
}

static void OpenSaveConfirm(int client)
{
	Menu m = new Menu(H_SaveConfirm);
	m.SetTitle("Save all CP/CA spawns for this map to file?");
	m.AddItem("YES", "YES");
	m.AddItem("NO",  "NO");
	m.ExitBackButton = true;
	m.Display(client, 0);
}

public int H_SaveConfirm(Menu m, MenuAction a, int client, int item)
{
	if (a == MenuAction_End) { delete m; }
	else if (a == MenuAction_Select)
	{
		char k[8]; m.GetItem(item, k, sizeof k);
		if (k[0] == 'Y')
		{
			char map[64]; GetCurrentMap(map, sizeof map);
			bool ok = BM_SaveToFile(map);
			PrintToChat(client, "[BM] Save %s.", ok ? "OK" : "FAILED");
		}
		OpenMainMenu(client);
	}
	else if (a == MenuAction_Cancel)
	{
		OpenMainMenu(client);
	}
	return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Visuals
// ─────────────────────────────────────────────────────────────────────────────

static void StartVisTimer(int client)
{
	KillVisTimer(client);
	if (!g_bAnyMenuOpen[client]) return;

	g_bFlipDrawOrder[client] = false;
	g_iVisCurCP[client] = 0;
	g_iVisCurCA[client] = 0;

	g_hVisTimer[client] = CreateTimer(kVisTickInterval, T_DrawVis, GetClientUserId(client),
									TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

static void KillVisTimer(int client)
{
	if (g_hVisTimer[client] != null)
	{
		KillTimer(g_hVisTimer[client]);
		g_hVisTimer[client] = null;
	}
}

static void BM_DrawPointBudget(int client, const float pos[3], const int color[4], int &drawn, int budget)
{
	if (drawn < budget)
	{
		BM_DrawPoint(client, pos, color);
		drawn++;
	}
}

public Action T_DrawVis(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!BM_IsClientOK(client) || !g_bAnyMenuOpen[client]) return Plugin_Stop;

	int cp = g_iSelectedCP[client];
	if (cp < 0 || cp >= g_iNumCPs) return Plugin_Continue;

	int nCP = g_CPSpawns[cp].Length;
	int nCA = g_CASpawns[cp].Length;

	int drawn = 0;

	bool caFirst = g_bFlipDrawOrder[client];
	g_bFlipDrawOrder[client] = !g_bFlipDrawOrder[client];

	int i = (nCP > 0) ? (g_iVisCurCP[client] % nCP) : 0;
	int j = (nCA > 0) ? (g_iVisCurCA[client] % nCA) : 0;

	if (caFirst)
	{
		while (drawn < kDrawPointBudget && (nCP > 0 || nCA > 0))
		{
			if (nCA > 0)
			{
				float vA[3]; g_CASpawns[cp].GetArray(j, vA, 3);
				BM_DrawPointBudget(client, vA, kColor_CA, drawn, kDrawPointBudget);
				j = (j + 1) % nCA;
				if (drawn >= kDrawPointBudget) break;
			}
			if (nCP > 0)
			{
				float vC[3]; g_CPSpawns[cp].GetArray(i, vC, 3);
				BM_DrawPointBudget(client, vC, kColor_CP, drawn, kDrawPointBudget);
				i = (i + 1) % nCP;
			}
			if ((nCA == 0 || j == g_iVisCurCA[client] % (nCA == 0 ? 1 : nCA)) &&
				(nCP == 0 || i == g_iVisCurCP[client] % (nCP == 0 ? 1 : nCP)))
			{
				break;
			}
		}
	}
	else
	{
		while (drawn < kDrawPointBudget && (nCP > 0 || nCA > 0))
		{
			if (nCP > 0)
			{
				float vC[3]; g_CPSpawns[cp].GetArray(i, vC, 3);
				BM_DrawPointBudget(client, vC, kColor_CP, drawn, kDrawPointBudget);
				i = (i + 1) % nCP;
				if (drawn >= kDrawPointBudget) break;
			}
			if (nCA > 0)
			{
				float vA[3]; g_CASpawns[cp].GetArray(j, vA, 3);
				BM_DrawPointBudget(client, vA, kColor_CA, drawn, kDrawPointBudget);
				j = (j + 1) % nCA;
			}
			if ((nCA == 0 || j == g_iVisCurCA[client] % (nCA == 0 ? 1 : nCA)) &&
				(nCP == 0 || i == g_iVisCurCP[client] % (nCP == 0 ? 1 : nCP)))
			{
				break;
			}
		}
	}

	if (nCP > 0) g_iVisCurCP[client] = i;
	if (nCA > 0) g_iVisCurCA[client] = j;

	// only while Add menu is open
	if (g_bAddMenuOpen[client])
		BM_DrawClosestCPDebug(client, cp);

	return Plugin_Continue;
}

static void BM_DrawPoint(int client, const float pos[3], const int color[4])
{
	float top[3];
	top[0] = pos[0];
	top[1] = pos[1];
	top[2] = pos[2] + kPillarHeight;

	TE_SetupBeamPoints(pos, top, g_iSpriteBeam, 0, 0, 0,
					   kBeamLife, kBeamWidth, kBeamWidth, 0, 0.0, color, 0);
	TE_SendToClient(client);
}

static void BM_DrawClosestCPDebug(int client, int cp)
{
	if (cp < 0 || cp >= g_iNumCPs) return;

	int n = g_CPSpawns[cp].Length;
	if (n <= 0) return;

	float eye[3];
	GetClientEyePosition(client, eye);

	// lower so it doesn't blind you
	eye[2] -= 20.0;

	float best[3];
	float bestD2 = 0.0;
	bool found = false;

	for (int i = 0; i < n; i++)
	{
		float v[3];
		g_CPSpawns[cp].GetArray(i, v, 3);

		float d2 = GetVectorDistance(eye, v, true);
		if (!found || d2 < bestD2)
		{
			found = true;
			bestD2 = d2;
			best[0] = v[0];
			best[1] = v[1];
			best[2] = v[2];
		}
	}

	if (!found) return;

	// don’t let the line go below the spawn point
	if (eye[2] < best[2] + 8.0)
		eye[2] = best[2] + 8.0;

	TE_SetupBeamPoints(eye, best, g_iSpriteBeam, 0, 0, 0,
		kBeamLife, kBeamWidth, kBeamWidth, 0, 0.0, kColor_Hi, 0);
	TE_SendToClient(client);

	float dist = SquareRoot(bestD2);
	PrintHintText(client, "Closest CP spawn: %.0f u", dist);
}

static void BM_HighlightPoint(int client, const float pos[3], const int baseColor[4], bool strongerPulse)
{
	float w    = strongerPulse ? (kBeamWidth * 2.0) : kBeamWidth;
	float life = strongerPulse ? 1.00 : kBeamLife;

	float top[3];
	top[0] = pos[0];
	top[1] = pos[1];
	top[2] = pos[2] + (kPillarHeight * 1.25);

	int c[4];
	c[0] = (baseColor[0] + kColor_Hi[0]) / 2;
	c[1] = (baseColor[1] + kColor_Hi[1]) / 2;
	c[2] = (baseColor[2] + kColor_Hi[2]) / 2;
	c[3] = 255;

	TE_SetupBeamPoints(pos, top, g_iSpriteBeam, 0, 0, 0, life, w, w, 0, 0.0, c, 0);
	TE_SendToClient(client);
}

// ─────────────────────────────────────────────────────────────────────────────
// Save / Load
// ─────────────────────────────────────────────────────────────────────────────

static bool BM_SaveToFile(const char[] map)
{
	char dir[PLATFORM_MAX_PATH];
	strcopy(dir, sizeof dir, kDirRel);
	CreateDirectory(dir, 511);

	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof path, "%s/%s.txt", dir, map);

	File f = OpenFile(path, "w");
	if (f == null)
	{
		PrintToServer("[BM] Save FAILED: cannot open '%s' for write.", path);
		return false;
	}

	for (int cp = 0; cp < g_iNumCPs && cp < MAX_CPS; cp++)
	{
		f.WriteLine("\"CP%d\"", cp);
		f.WriteLine("{");

		int n = g_CPSpawns[cp].Length;
		for (int i = 0; i < n; i++)
		{
			float v[3]; g_CPSpawns[cp].GetArray(i, v, 3);
			char line[128];
			Format(line, sizeof line, "\t\"%.6f, %.6f, %.6f\"", v[0], v[1], v[2]);
			f.WriteLine(line);
		}

		f.WriteLine("\t\"CA\"");
		f.WriteLine("\t{");
		int m = g_CASpawns[cp].Length;
		for (int j = 0; j < m; j++)
		{
			float w[3]; g_CASpawns[cp].GetArray(j, w, 3);
			char line2[128];
			Format(line2, sizeof line2, "\t\t\"%.6f, %.6f, %.6f\"", w[0], w[1], w[2]);
			f.WriteLine(line2);
		}
		f.WriteLine("\t}");
		f.WriteLine("}");
		f.WriteLine("");
	}
	delete f;

	bool verified = BM_PostSaveVerify(map);
	PrintToServer("[BM] Save %s: '%s'  (verified=%s)",
				  verified ? "OK" : "WARN",
				  path, verified ? "yes" : "no");

	return true;
}

static bool BM_PostSaveVerify(const char[] map)
{
	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof path, "%s/%s.txt", kDirRel, map);

	File f = OpenFile(path, "r");
	if (f == null)
	{
		PrintToServer("[BM] Verify FAILED: cannot open '%s'.", path);
		return false;
	}

	int memCP[MAX_CPS], memCA[MAX_CPS];
	int memTotal = 0;
	for (int cp = 0; cp < g_iNumCPs && cp < MAX_CPS; cp++)
	{
		memCP[cp] = g_CPSpawns[cp].Length;
		memCA[cp] = g_CASpawns[cp].Length;
		memTotal += memCP[cp] + memCA[cp];
	}

	int diskCP[MAX_CPS];
	int diskCA[MAX_CPS];
	for (int i = 0; i < MAX_CPS; i++)
	{
		diskCP[i] = 0;
		diskCA[i] = 0;
	}
	int diskTotal = 0;

	int cp = -1;
	bool inCA = false;

	char line[256];
	while (!f.EndOfFile() && f.ReadLine(line, sizeof line))
	{
		TrimString(line);
		if (line[0] == '\0') continue;

		if (line[0] == '"' && line[1] == 'C' && line[2] == 'P')
		{
			int i = 3, n = 0, sign = 1;
			if (line[i] == '-') { sign = -1; i++; }
			while (line[i] >= '0' && line[i] <= '9') { n = (n*10) + (line[i]-'0'); i++; }
			n *= sign;

			if (n >= 0 && n < MAX_CPS) { cp = n; inCA = false; }
			else                       { cp = -1; inCA = false; }
			continue;
		}

		if (StrContains(line, "\"CA\"") == 0) { inCA = true; continue; }
		if (line[0] == '{') continue;
		if (line[0] == '}') { inCA = false; continue; }

		if (cp >= 0 && cp < MAX_CPS && line[0] == '"')
		{
			if (StrContains(line, ",") != -1)
			{
				if (inCA) { diskCA[cp]++; diskTotal++; }
				else      { diskCP[cp]++; diskTotal++; }
			}
		}
	}
	delete f;

	bool match = true;
	if (diskTotal != memTotal) match = false;

	for (int i = 0; i < g_iNumCPs && i < MAX_CPS; i++)
	{
		if (diskCP[i] != memCP[i] || diskCA[i] != memCA[i])
			match = false;
	}

	if (!match)
	{
		PrintToServer("[BM] Verify mismatch: memory=%d, disk=%d", memTotal, diskTotal);
		for (int i = 0; i < g_iNumCPs && i < MAX_CPS; i++)
		{
			if (diskCP[i] != memCP[i] || diskCA[i] != memCA[i])
			{
				PrintToServer("[BM]  CP#%d  CP:%d->%d  CA:%d->%d",
					i, memCP[i], diskCP[i], memCA[i], diskCA[i]);
			}
		}
	}
	else
	{
		PrintToServer("[BM] Verify OK: total=%d across %d CPs.", diskTotal, g_iNumCPs);
	}

	return match;
}

static bool BM_LoadFromFile(const char[] map)
{
	for (int cp = 0; cp < MAX_CPS; cp++)
	{
		if (g_CPSpawns[cp] != null) g_CPSpawns[cp].Clear();
		if (g_CASpawns[cp] != null) g_CASpawns[cp].Clear();
	}

	char path[PLATFORM_MAX_PATH];
	Format(path, sizeof path, "%s/%s.txt", kDirRel, map);

	File f = OpenFile(path, "r");
	if (f == null) return false;

	int cp = -1;
	bool inCA = false;

	char line[256];
	while (!f.EndOfFile() && f.ReadLine(line, sizeof line))
	{
		TrimString(line);
		if (line[0] == '\0') continue;

		if (line[0] == '"' && line[1] == 'C' && line[2] == 'P')
		{
			int i = 3, n = 0, sign = 1;
			if (line[i] == '-') { sign = -1; i++; }
			while (line[i] >= '0' && line[i] <= '9') { n = (n*10) + (line[i]-'0'); i++; }
			n *= sign;

			if (n >= 0 && n < MAX_CPS)
			{
				cp = n; inCA = false;
				if (g_CPSpawns[cp] == null) g_CPSpawns[cp] = new ArrayList(3);
				if (g_CASpawns[cp] == null) g_CASpawns[cp] = new ArrayList(3);
			}
			else { cp = -1; inCA = false; }
			continue;
		}

		if (StrContains(line, "\"CA\"") == 0) { inCA = true; continue; }

		if (line[0] == '{' || line[0] == '}') { if (line[0] == '}') inCA = false; continue; }

		if (cp >= 0 && cp < MAX_CPS && line[0] == '"')
		{
			int len = strlen(line);
			if (len >= 2 && line[len - 1] == '"')
				line[len - 1] = '\0';

			// copies from line+1
			char vec[256];
			strcopy(vec, sizeof vec, line[1]);
			TrimString(vec);

			float v[3];
			if (BM_ParseVec3(vec, v))
			{
				if (inCA)
					g_CASpawns[cp].PushArray(v, 3);
				else
					g_CPSpawns[cp].PushArray(v, 3);
			}
		}
	}

	delete f;
	return true;
}

static bool BM_ParseVec3(const char[] s, float out[3])
{
	char parts[3][32];
	int n = ExplodeString(s, ",", parts, 3, 32);
	if (n != 3) return false;

	TrimString(parts[0]);
	TrimString(parts[1]);
	TrimString(parts[2]);

	out[0] = StringToFloat(parts[0]);
	out[1] = StringToFloat(parts[1]);
	out[2] = StringToFloat(parts[2]);
	return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

static bool BM_IsClientOK(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientInGame(client));
}

static bool BM_EnsureSelectedCP(int client)
{
	if (g_iNumCPs <= 0)
	{
		PrintToChat(client, "[BM] No control points found on this map.");
		return false;
	}
	if (g_iSelectedCP[client] < 0 || g_iSelectedCP[client] >= g_iNumCPs)
		g_iSelectedCP[client] = 0;
	return true;
}

static void BM_CPFmt(int cp, char[] out, int maxlen)
{
	Format(out, maxlen, "CP#%d", cp);
}

static void BM_NotifyCounts(int client, int cp)
{
	char cpfmt[16];
	BM_CPFmt(cp, cpfmt, sizeof cpfmt);

	int cpc = g_CPSpawns[cp].Length + g_CASpawns[cp].Length;

	PrintToChat(client, "[BM] %s: CP=%d, CA=%d (CP total=%d) - Map total=%d",
		cpfmt,
		g_CPSpawns[cp].Length,
		g_CASpawns[cp].Length,
		cpc,
		BM_TotalCountAll());
}

static int BM_TotalCountAll()
{
	int total = 0;
	for (int i = 0; i < g_iNumCPs && i < MAX_CPS; i++)
		total += g_CPSpawns[i].Length + g_CASpawns[i].Length;
	return total;
}

static int BM_GetNumControlPoints()
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "ins_objective_resource")) != -1)
	{
		int n = GetEntProp(ent, Prop_Send, "m_iNumControlPoints");
		if (n > 0 && n <= MAX_CPS) return n;
	}
	return 0;
}

static bool BM_CanAddSpawn(int client, int cp, EAddKind kind, const float v[3])
{
	ArrayList arr = (kind == Add_CP) ? g_CPSpawns[cp] : g_CASpawns[cp];
	int n = arr.Length;
	float thresh2 = kDuplicateMinDist * kDuplicateMinDist;

	for (int i = 0; i < n; i++)
	{
		float w[3];
		arr.GetArray(i, w, 3);
		if (GetVectorDistance(v, w, true) < thresh2)
		{
			PrintToChat(client, "[BM] Too close to existing %s spawn #%d (min %.0f units) — not added.",
				(kind == Add_CP) ? "CP" : "CA", i, kDuplicateMinDist);
			return false;
		}
	}
	return true;
}

static bool BM_FindClosestSpawn(int cp, const float me[3], bool &outIsCA, int &outIdx, float outPos[3], float &outDist2)
{
	bool   found    = false;
	float  bestD2   = 0.0;
	int    bestIdx  = -1;
	bool   bestCA   = false;

	int nCP = g_CPSpawns[cp].Length;
	for (int i = 0; i < nCP; i++)
	{
		float v[3]; g_CPSpawns[cp].GetArray(i, v, 3);
		float d2 = GetVectorDistance(me, v, true);
		if (!found || d2 < bestD2)
		{
			found  = true;
			bestD2 = d2;
			bestIdx = i;
			bestCA = false;
			outPos[0] = v[0]; outPos[1] = v[1]; outPos[2] = v[2];
		}
	}

	int nCA = g_CASpawns[cp].Length;
	for (int j = 0; j < nCA; j++)
	{
		float v2[3]; g_CASpawns[cp].GetArray(j, v2, 3);
		float d2 = GetVectorDistance(me, v2, true);
		if (!found || d2 < bestD2)
		{
			found  = true;
			bestD2 = d2;
			bestIdx = j;
			bestCA = true;
			outPos[0] = v2[0]; outPos[1] = v2[1]; outPos[2] = v2[2];
		}
	}

	if (!found) return false;

	outIsCA  = bestCA;
	outIdx   = bestIdx;
	outDist2 = bestD2;
	return true;
}

static void BM_PushUndo(int client, int cp, EAddKind kind)
{
	if (g_UndoStack[client] == null) g_UndoStack[client] = new ArrayList();
	g_UndoStack[client].Push( BM_PackUndoCode(cp, (kind == Add_CA)) );
}

static bool BM_DoUndoOneForSelectedCP(int client)
{
	int cpSel = g_iSelectedCP[client];
	if (cpSel < 0 || cpSel >= g_iNumCPs) return false;
	if (g_UndoStack[client] == null || g_UndoStack[client].Length == 0) return false;

	for (int i = g_UndoStack[client].Length - 1; i >= 0; i--)
	{
		int code = g_UndoStack[client].Get(i);
		int cp   = BM_CodeToCP(code);
		bool isCA = BM_CodeIsCA(code);

		if (cp != cpSel) continue;

		ArrayList arr = isCA ? g_CASpawns[cp] : g_CPSpawns[cp];
		int n = arr.Length;
		if (n > 0)
		{
			float last[3]; arr.GetArray(n - 1, last, 3);
			arr.Erase(n - 1);
			g_UndoStack[client].Erase(i);

			PrintToChat(client, "[BM] Undo %s on CP#%d: (%.0f, %.0f, %.2f).",
				isCA ? "CA" : "CP", cp, last[0], last[1], last[2]);
			return true;
		}
		else
		{
			g_UndoStack[client].Erase(i);
		}
	}
	return false;
}

static void BM_CacheCaptureZones()
{
	g_iCZCount = 0;

	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "trigger_capture_zone")) != -1)
	{
		if (g_iCZCount >= MAX_CAPTURE_ZONES)
			break;

		g_iCZEnt[g_iCZCount] = EntIndexToEntRef(ent);
		g_iCZSpawnflags[g_iCZCount] = GetEntProp(ent, Prop_Data, "m_spawnflags");
		g_iCZCount++;
	}
	PrintToServer("[BM] BotSpawns: cached %d trigger_capture_zone.", g_iCZCount);
}

static void BM_CZAllowClients(bool allow)
{
	for (int i = 0; i < g_iCZCount; i++)
	{
		int ent = EntRefToEntIndex(g_iCZEnt[i]);
		if (ent == -1)
			continue;

		if (allow)
		{
			SetEntProp(ent, Prop_Data, "m_spawnflags", g_iCZSpawnflags[i]);
		}
		else
		{
			int flags = GetEntProp(ent, Prop_Data, "m_spawnflags");
			flags &= ~1; // clear "Clients" bit
			SetEntProp(ent, Prop_Data, "m_spawnflags", flags);
		}
	}
}

static void BM_AddCapUser()
{
	if (g_iCapBlockUsers == 0)
	{
		BM_CZAllowClients(false);
	}
	g_iCapBlockUsers++;
}

static void BM_RemoveCapUser()
{
	if (g_iCapBlockUsers > 0)
	{
		g_iCapBlockUsers--;
		if (g_iCapBlockUsers == 0)
		{
			BM_CZAllowClients(true);
		}
	}
}

// returns safe index for ga_Letters[]
int LetterIndex(int n)
{
	// 0..25 -> A..Z, everything else -> "?"
	if (n >= 0 && n < 26)
		return n;
	return 26;
}

public void OnPluginEnd()
{
	// Restore capture-zone flags if we were blocking
	BM_CZAllowClients(true);

	for (int c = 1; c <= MaxClients; c++)
	{
		g_bAnyMenuOpen[c] = false;
		g_bAddMenuOpen[c] = false;
		KillVisTimer(c);
		KillSpeedTimer(c);
		g_iSelectedCP[c] = -1;
		if (g_UndoStack[c] != null) { delete g_UndoStack[c]; g_UndoStack[c] = null; }
	}

	for (int i = 0; i < MAX_CPS; i++)
	{
		if (g_CPSpawns[i] != null) { delete g_CPSpawns[i]; g_CPSpawns[i] = null; }
		if (g_CASpawns[i] != null) { delete g_CASpawns[i]; g_CASpawns[i] = null; }
	}

	g_iSpriteBeam = -1;
	g_iNumCPs     = 0;
	BM_CZAllowClients(true);
	g_iCapBlockUsers = 0;
}
