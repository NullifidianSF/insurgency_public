#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.2.2"
#define MAX_ZONES 64
#define MIN_ZONE_SIZE 32.0
#define COLLISION_SCAN_RANGE 512.0
#define GAP_CHECK_RANGE 128.0
#define SCANNERS_PER_TICK 2

enum struct KillZone {
	int id;
	char name[64];
	float mins[3];
	float maxs[3];
	bool enabled;
}

KillZone g_Zones[MAX_ZONES];
int g_NextID;
int g_Beam;
char g_Map[PLATFORM_MAX_PATH];
char g_Path[PLATFORM_MAX_PATH];
bool g_DataReady;
bool g_MapActive;
bool g_EditorHooks;
bool g_RuntimeUpdateQueued;
Handle g_CheckTimer;
Handle g_PreviewTimer;
ConVar g_Enabled;
ConVar g_Bots;
ConVar g_AdminProtection;
bool g_Editing[MAXPLAYERS + 1];
bool g_OwnNoclip[MAXPLAYERS + 1];
MoveType g_PreviousMove[MAXPLAYERS + 1];
int g_Selected[MAXPLAYERS + 1];
int g_Corners[MAXPLAYERS + 1];
float g_First[MAXPLAYERS + 1][3];
float g_Second[MAXPLAYERS + 1][3];
bool g_ShowCollision[MAXPLAYERS + 1];
int g_ScanCursor;

public Plugin myinfo = {
	name = "[INS] Kill Zones",
	author = "Nullifidian & Codex",
	description = "Per-map restricted areas with an admin box editor.",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart() {
	RegAdminCmd("sm_killzones", Command_Menu, ADMFLAG_RCON, "Enter the kill-zone editor.");
	RegAdminCmd("sm_killzones_end", Command_End, ADMFLAG_RCON, "Exit the editor and remove protection.");
	RegAdminCmd("sm_killzone_name", Command_Name, ADMFLAG_RCON, "sm_killzone_name <name> - rename the selected zone.");
	g_Enabled = CreateConVar("sm_killzones_enabled", "1", "Enable kill-zone enforcement.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Bots = CreateConVar("sm_killzones_bots", "0", "Also kill bots entering a zone.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_AdminProtection = CreateConVar("sm_killzones_admin_protection", "1", "Protect admins while editing kill zones. Set to 0 to test zone kills while editing.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Enabled.AddChangeHook(OnEnabledChanged);
	g_AdminProtection.AddChangeHook(OnProtectionChanged);
	AutoExecConfig(true, "bm_killzones");
}

public void OnMapStart() {
	g_MapActive = false;
	g_RuntimeUpdateQueued = false;
	UpdateRuntime();
	g_ScanCursor = 0;
	for (int client = 1; client <= MaxClients; client++)
		ResetEditor(client, false);
	g_Beam = PrecacheModel("materials/vgui/white.vmt", true);
	GetCurrentMap(g_Map, sizeof g_Map);
	char filename[PLATFORM_MAX_PATH];
	strcopy(filename, sizeof filename, g_Map);
	ReplaceString(filename, sizeof filename, "/", "_");
	ReplaceString(filename, sizeof filename, "\\", "_");
	BuildPath(Path_SM, g_Path, sizeof g_Path, "data/bm_killzones/%s.txt", filename);
	LoadZones();
	g_MapActive = true;
	UpdateRuntime();
}

public void OnMapEnd() {
	g_MapActive = false;
	g_DataReady = false;
	g_RuntimeUpdateQueued = false;
	UpdateRuntime();
	for (int client = 1; client <= MaxClients; client++)
		ResetEditor(client, true);
}

public void OnPluginEnd() {
	g_MapActive = false;
	UpdateRuntime();
	for (int client = 1; client <= MaxClients; client++)
		ResetEditor(client, true);
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	QueueRuntimeUpdate();
}

public void OnProtectionChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	for (int client = 1; client <= MaxClients; client++) {
		if (g_Editing[client] && IsClientInGame(client))
			PrintToChat(client, "[KillZones] Editor protection %s. %s", g_AdminProtection.BoolValue ? "ON" : "OFF",
				g_AdminProtection.BoolValue ? "Editors are protected from kill zones." : "Enabled kill zones now affect editors too.");
	}
}

void QueueRuntimeUpdate() {
	if (!g_MapActive || g_RuntimeUpdateQueued)
		return;
	g_RuntimeUpdateQueued = true;
	RequestFrame(Frame_UpdateRuntime);
}

public void Frame_UpdateRuntime(any data) {
	g_RuntimeUpdateQueued = false;
	UpdateRuntime();
}

void UpdateRuntime() {
	bool checkPlayers;
	bool editors;
	if (g_MapActive && g_DataReady) {
		if (g_Enabled.BoolValue) {
			for (int slot = 0; slot < MAX_ZONES; slot++) {
				if (g_Zones[slot].id && g_Zones[slot].enabled) {
					checkPlayers = true;
					break;
				}
			}
		}
		for (int client = 1; client <= MaxClients; client++) {
			if (g_Editing[client]) {
				editors = true;
				break;
			}
		}
	}
	if (checkPlayers) {
		if (g_CheckTimer == null)
			g_CheckTimer = CreateTimer(0.1, Timer_CheckPlayers, _, TIMER_REPEAT);
	} else
		delete g_CheckTimer;
	if (editors) {
		if (!g_EditorHooks) {
			HookEvent("player_death", Event_ResetEditor);
			HookEvent("player_spawn", Event_ResetEditor);
			HookEvent("player_team", Event_ResetEditor);
			g_EditorHooks = true;
		}
		if (g_PreviewTimer == null)
			g_PreviewTimer = CreateTimer(0.5, Timer_Preview, _, TIMER_REPEAT);
	} else {
		delete g_PreviewTimer;
		if (g_EditorHooks) {
			UnhookEvent("player_death", Event_ResetEditor);
			UnhookEvent("player_spawn", Event_ResetEditor);
			UnhookEvent("player_team", Event_ResetEditor);
			g_EditorHooks = false;
		}
	}
}

public void OnClientDisconnect(int client) {
	ResetEditor(client, false);
}

public void Event_ResetEditor(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
		ResetEditor(client, true);
}

void ResetEditor(int client, bool restore) {
	bool wasEditing = g_Editing[client];
	if (restore && g_OwnNoclip[client] && IsClientInGame(client) && IsPlayerAlive(client)
		&& GetEntityMoveType(client) == MOVETYPE_NOCLIP)
		SetEntityMoveType(client, g_PreviousMove[client]);
	g_Editing[client] = false;
	g_OwnNoclip[client] = false;
	g_Selected[client] = 0;
	g_Corners[client] = 0;
	g_ShowCollision[client] = false;
	if (wasEditing)
		QueueRuntimeUpdate();
}

bool HasAccess(int client) {
	return client > 0 && IsClientInGame(client) && !IsFakeClient(client)
		&& CheckCommandAccess(client, "sm_killzones", ADMFLAG_RCON);
}

bool CanEdit(int client) {
	return HasAccess(client) && IsPlayerAlive(client) && g_Editing[client] && g_DataReady;
}

public Action Command_Menu(int client, int args) {
	if (!HasAccess(client))
		return Plugin_Handled;
	if (!g_DataReady) {
		ReplyToCommand(client, "[KillZones] Map data failed to load. Check the SourceMod error log.");
		return Plugin_Handled;
	}
	if (!IsPlayerAlive(client)) {
		ReplyToCommand(client, "[KillZones] You must be alive to edit zones.");
		return Plugin_Handled;
	}
	if (!g_Editing[client]) {
		g_Editing[client] = true;
		UpdateRuntime();
		PrintToChat(client, "[KillZones] Editing ON. Editor protection: %s. Exit the menu or use !killzones_end to finish.",
			g_AdminProtection.BoolValue ? "ON" : "OFF - kill zones affect you");
	}
	ShowMain(client);
	return Plugin_Handled;
}

public Action Command_End(int client, int args) {
	if (client > 0 && IsClientInGame(client)) {
		ResetEditor(client, true);
		PrintToChat(client, "[KillZones] Editing OFF. Kill zones now affect you.");
	}
	return Plugin_Handled;
}

public Action Command_Name(int client, int args) {
	if (!CanEdit(client)) {
		ReplyToCommand(client, "[KillZones] Open !killzones and select a saved zone first.");
		return Plugin_Handled;
	}
	int slot = FindZone(g_Selected[client]);
	if (slot == -1 || args == 0) {
		ReplyToCommand(client, "[KillZones] Select a saved zone, then use: sm_killzone_name <name>");
		return Plugin_Handled;
	}
	char name[256], previous[64];
	GetCmdArgString(name, sizeof name);
	StripQuotes(name);
	TrimString(name);
	ReplaceString(name, sizeof name, "\n", " ");
	ReplaceString(name, sizeof name, "\r", " ");
	if (!name[0] || strlen(name) >= sizeof previous) {
		ReplyToCommand(client, "[KillZones] Use a name between 1 and 63 bytes long.");
		return Plugin_Handled;
	}
	strcopy(previous, sizeof previous, g_Zones[slot].name);
	strcopy(g_Zones[slot].name, sizeof g_Zones[].name, name);
	if (!SaveZones()) {
		strcopy(g_Zones[slot].name, sizeof g_Zones[].name, previous);
		SaveFailed(client);
	} else {
		LogAction(client, -1, "Renamed kill zone #%d on %s to %s", g_Zones[slot].id, g_Map, name);
		PrintToChat(client, "[KillZones] Saved name: %s", name);
	}
	ShowZone(client);
	return Plugin_Handled;
}

void ShowMain(int client) {
	Menu menu = new Menu(Menu_Main);
	menu.SetTitle("Kill Zones - EDITOR PROTECTION %s", g_AdminProtection.BoolValue ? "ON" : "OFF");
	menu.AddItem("create", "Create a zone");
	menu.AddItem("browse", "Browse saved zones");
	menu.AddItem("noclip", GetEntityMoveType(client) == MOVETYPE_NOCLIP ? "Noclip: ON (toggle)" : "Noclip: OFF (toggle)");
	AddCollisionItems(menu, client);
	menu.AddItem("finish", "Finish editing");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Main(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_Exit)
		Command_End(client, 0);
	else if (action == MenuAction_Select && CanEdit(client)) {
		char info[16];
		menu.GetItem(item, info, sizeof info);
		if (StrEqual(info, "create")) {
			g_Corners[client] = 0;
			g_Selected[client] = 0;
			ShowCreate(client);
		} else if (StrEqual(info, "browse")) {
			g_Corners[client] = 0;
			ShowBrowse(client);
		} else if (StrEqual(info, "noclip")) {
			ToggleNoclip(client);
			ShowMain(client);
		} else if (HandleCollisionItem(client, info)) {
			ShowMain(client);
		} else
			Command_End(client, 0);
	}
	return 0;
}

void ToggleNoclip(int client) {
	MoveType move = GetEntityMoveType(client);
	if (move == MOVETYPE_NOCLIP) {
		SetEntityMoveType(client, g_OwnNoclip[client] ? g_PreviousMove[client] : MOVETYPE_WALK);
		g_OwnNoclip[client] = false;
	} else {
		g_PreviousMove[client] = move;
		g_OwnNoclip[client] = true;
		SetEntityMoveType(client, MOVETYPE_NOCLIP);
	}
}

void ShowCreate(int client) {
	Menu menu = new Menu(Menu_Create);
	menu.SetTitle("New zone - corners at your feet\nMinimum 32 units on every axis");
	menu.AddItem("first", "Mark first corner here");
	menu.AddItem("second", "Mark opposite corner here", g_Corners[client] > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("save", "Save and ENABLE zone", g_Corners[client] == 2 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("noclip", GetEntityMoveType(client) == MOVETYPE_NOCLIP ? "Noclip: ON (toggle)" : "Noclip: OFF (toggle)");
	AddCollisionItems(menu, client);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Create(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel) {
		if (item == MenuCancel_ExitBack && CanEdit(client)) {
			g_Corners[client] = 0;
			ShowMain(client);
		} else if (item == MenuCancel_Exit)
			Command_End(client, 0);
	} else if (action == MenuAction_Select && CanEdit(client)) {
		char info[16];
		menu.GetItem(item, info, sizeof info);
		if (HandleCollisionItem(client, info)) {
			ShowCreate(client);
			return 0;
		}
		if (StrEqual(info, "first")) {
			GetClientAbsOrigin(client, g_First[client]);
			g_Corners[client] = 1;
			PrintToChat(client, "[KillZones] First corner marked. Move diagonally AND vertically to the opposite corner.");
		} else if (StrEqual(info, "second") && g_Corners[client] > 0) {
			GetClientAbsOrigin(client, g_Second[client]);
			g_Corners[client] = 2;
			PrintToChat(client, "[KillZones] Second corner marked. Yellow outline is the draft; save to activate it.");
		} else if (StrEqual(info, "noclip"))
			ToggleNoclip(client);
		else if (StrEqual(info, "save") && g_Corners[client] == 2 && CreateZone(client)) {
			ShowZone(client);
			return 0;
		}
		ShowCreate(client);
	}
	return 0;
}

bool CreateZone(int client) {
	int slot = -1;
	for (int i = 0; i < MAX_ZONES; i++) {
		if (!g_Zones[i].id) {
			slot = i;
			break;
		}
	}
	if (slot == -1) {
		PrintToChat(client, "[KillZones] This map already has the maximum of %d zones.", MAX_ZONES);
		return false;
	}
	MakeBounds(g_First[client], g_Second[client], g_Zones[slot].mins, g_Zones[slot].maxs);
	if (!ValidBounds(g_Zones[slot].mins, g_Zones[slot].maxs)) {
		PrintToChat(client, "[KillZones] Box must be at least 32 units wide, deep AND tall. Mark the corners again.");
		return false;
	}
	g_Zones[slot].id = g_NextID++;
	g_Zones[slot].enabled = true;
	Format(g_Zones[slot].name, sizeof g_Zones[].name, "Zone %d", g_Zones[slot].id);
	if (!SaveZones()) {
		g_Zones[slot].id = 0;
		SaveFailed(client);
		return false;
	}
	g_Selected[client] = g_Zones[slot].id;
	g_Corners[client] = 0;
	LogAction(client, -1, "Created kill zone #%d on %s", g_Zones[slot].id, g_Map);
	PrintToChat(client, "[KillZones] %s saved and enabled. %s", g_Zones[slot].name,
		g_AdminProtection.BoolValue ? "You remain protected until you finish editing." : "Protection is OFF: this zone can kill you too.");
	return true;
}

void ShowBrowse(int client) {
	Menu menu = new Menu(Menu_Browse);
	menu.SetTitle("Saved zones - select to preview");
	char info[16], label[96];
	for (int i = 0; i < MAX_ZONES; i++) {
		if (!g_Zones[i].id)
			continue;
		IntToString(g_Zones[i].id, info, sizeof info);
		Format(label, sizeof label, "%s [%s]", g_Zones[i].name, g_Zones[i].enabled ? "ON" : "OFF");
		menu.AddItem(info, label);
	}
	if (!menu.ItemCount)
		menu.AddItem("0", "No zones saved for this map", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Browse(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel) {
		if (item == MenuCancel_ExitBack && CanEdit(client))
			ShowMain(client);
		else if (item == MenuCancel_Exit)
			Command_End(client, 0);
	} else if (action == MenuAction_Select && CanEdit(client)) {
		char info[16];
		menu.GetItem(item, info, sizeof info);
		g_Selected[client] = StringToInt(info);
		ShowZone(client);
	}
	return 0;
}

void ShowZone(int client) {
	int slot = FindZone(g_Selected[client]);
	if (slot == -1) {
		PrintToChat(client, "[KillZones] That zone no longer exists.");
		ShowBrowse(client);
		return;
	}
	Menu menu = new Menu(Menu_Zone);
	menu.SetTitle("%s [%s]\nSize: %.0f x %.0f x %.0f\nPreview: %s", g_Zones[slot].name,
		g_Zones[slot].enabled ? "ON" : "OFF", g_Zones[slot].maxs[0] - g_Zones[slot].mins[0],
		g_Zones[slot].maxs[1] - g_Zones[slot].mins[1], g_Zones[slot].maxs[2] - g_Zones[slot].mins[2],
		g_Zones[slot].enabled ? "RED" : "BLUE");
	menu.AddItem("toggle", g_Zones[slot].enabled ? "Disable zone" : "Enable zone");
	menu.AddItem("teleport", "Teleport to center (enables noclip)");
	menu.AddItem("rename", "Rename zone (show command)");
	menu.AddItem("delete", "Delete zone...");
	AddCollisionItems(menu, client);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Zone(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel) {
		if (item == MenuCancel_ExitBack && CanEdit(client))
			ShowBrowse(client);
		else if (item == MenuCancel_Exit)
			Command_End(client, 0);
	} else if (action == MenuAction_Select && CanEdit(client)) {
		int slot = FindZone(g_Selected[client]);
		if (slot == -1) {
			ShowBrowse(client);
			return 0;
		}
		char info[16];
		menu.GetItem(item, info, sizeof info);
		if (HandleCollisionItem(client, info)) {
			ShowZone(client);
			return 0;
		}
		if (StrEqual(info, "toggle")) {
			g_Zones[slot].enabled = !g_Zones[slot].enabled;
			if (!SaveZones()) {
				g_Zones[slot].enabled = !g_Zones[slot].enabled;
				SaveFailed(client);
			} else {
				LogAction(client, -1, "Set kill zone #%d on %s enabled=%d", g_Zones[slot].id, g_Map, g_Zones[slot].enabled);
				PrintToChat(client, "[KillZones] %s %s and saved.", g_Zones[slot].name, g_Zones[slot].enabled ? "enabled" : "disabled");
			}
		} else if (StrEqual(info, "teleport")) {
			if (GetEntityMoveType(client) != MOVETYPE_NOCLIP)
				ToggleNoclip(client);
			float point[3], velocity[3];
			for (int axis = 0; axis < 3; axis++)
				point[axis] = (g_Zones[slot].mins[axis] + g_Zones[slot].maxs[axis]) * 0.5;
			TeleportEntity(client, point, NULL_VECTOR, velocity);
			PrintToChat(client, "[KillZones] Teleported with noclip ON. Move somewhere safe before finishing editing.");
		} else if (StrEqual(info, "rename"))
			PrintToChat(client, "[KillZones] Type !killzone_name Your zone name in chat, or sm_killzone_name in console.");
		else if (StrEqual(info, "delete")) {
			Menu confirm = new Menu(Menu_Delete);
			confirm.SetTitle("Delete %s permanently?", g_Zones[slot].name);
			IntToString(g_Zones[slot].id, info, sizeof info);
			confirm.AddItem("cancel", "Cancel");
			confirm.AddItem(info, "Delete and save");
			confirm.ExitBackButton = true;
			confirm.Display(client, MENU_TIME_FOREVER);
			return 0;
		}
		ShowZone(client);
	}
	return 0;
}

public int Menu_Delete(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel) {
		if (item == MenuCancel_ExitBack && CanEdit(client))
			ShowZone(client);
		else if (item == MenuCancel_Exit)
			Command_End(client, 0);
	} else if (action == MenuAction_Select && CanEdit(client)) {
		char info[16];
		menu.GetItem(item, info, sizeof info);
		if (StrEqual(info, "cancel")) {
			ShowZone(client);
			return 0;
		}
		int id = StringToInt(info);
		int slot = FindZone(id);
		if (slot != -1) {
			g_Zones[slot].id = 0;
			if (!SaveZones()) {
				g_Zones[slot].id = id;
				SaveFailed(client);
			} else {
				LogAction(client, -1, "Deleted kill zone #%d on %s", id, g_Map);
				PrintToChat(client, "[KillZones] Zone deleted and saved.");
			}
		}
		ShowBrowse(client);
	}
	return 0;
}

int FindZone(int id) {
	if (id > 0) {
		for (int i = 0; i < MAX_ZONES; i++) {
			if (g_Zones[i].id == id)
				return i;
		}
	}
	return -1;
}

void MakeBounds(const float first[3], const float second[3], float mins[3], float maxs[3]) {
	for (int axis = 0; axis < 3; axis++) {
		mins[axis] = first[axis] < second[axis] ? first[axis] : second[axis];
		maxs[axis] = first[axis] > second[axis] ? first[axis] : second[axis];
	}
}

bool ValidBounds(const float mins[3], const float maxs[3]) {
	for (int axis = 0; axis < 3; axis++) {
		if (!(mins[axis] >= -1000000.0 && maxs[axis] <= 1000000.0
			&& maxs[axis] - mins[axis] >= MIN_ZONE_SIZE))
			return false;
	}
	return true;
}

bool ContainsPoint(int slot, const float point[3]) {
	for (int axis = 0; axis < 3; axis++) {
		if (point[axis] < g_Zones[slot].mins[axis] || point[axis] > g_Zones[slot].maxs[axis])
			return false;
	}
	return true;
}

public Action Timer_CheckPlayers(Handle timer) {
	if (!g_DataReady || !g_Enabled.BoolValue)
		return Plugin_Continue;
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) <= 1)
			continue;
		if (g_Editing[client]) {
			if (!HasAccess(client))
				ResetEditor(client, true);
			else if (g_AdminProtection.BoolValue)
				continue;
		}
		if (IsFakeClient(client) && !g_Bots.BoolValue)
			continue;
		float point[3];
		GetClientAbsOrigin(client, point);
		for (int slot = 0; slot < MAX_ZONES; slot++) {
			if (!g_Zones[slot].id || !g_Zones[slot].enabled || !ContainsPoint(slot, point))
				continue;
			if (!IsFakeClient(client))
				PrintToChat(client, "[KillZones] You entered a restricted map area.");
			ForcePlayerSuicide(client);
			break;
		}
	}
	return Plugin_Continue;
}

public Action Timer_Preview(Handle timer) {
	if (!g_DataReady || g_Beam <= 0)
		return Plugin_Continue;
	for (int client = 1; client <= MaxClients; client++) {
		if (!g_Editing[client])
			continue;
		if (!CanEdit(client)) {
			ResetEditor(client, true);
			continue;
		}
		int color[4] = {255, 210, 40, 255};
		if (g_Corners[client] > 0) {
			float end[3], mins[3], maxs[3];
			if (g_Corners[client] == 1)
				GetClientAbsOrigin(client, end);
			else
				end = g_Second[client];
			MakeBounds(g_First[client], end, mins, maxs);
			DrawBox(client, mins, maxs, color);
		} else {
			int slot = FindZone(g_Selected[client]);
			if (slot == -1)
				continue;
			color[0] = g_Zones[slot].enabled ? 230 : 15;
			color[1] = g_Zones[slot].enabled ? 15 : 75;
			color[2] = g_Zones[slot].enabled ? 15 : 255;
			DrawBox(client, g_Zones[slot].mins, g_Zones[slot].maxs, color);
		}
	}
	UpdateCollisionScanners();
	return Plugin_Continue;
}

void AddCollisionItems(Menu menu, int client) {
	menu.AddItem("collision", g_ShowCollision[client] ? "Nearby collision: ON (toggle)" : "Nearby collision: OFF (toggle)");
	menu.AddItem("gap", "Check aimed gap (stand / crouch)", g_ShowCollision[client] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
}

bool HandleCollisionItem(int client, const char[] info) {
	if (StrEqual(info, "collision")) {
		g_ShowCollision[client] = !g_ShowCollision[client];
		if (g_ShowCollision[client])
			PrintToChat(client, "[KillZones] Collision scan ON: blue/black crosses = player clip, red/black = other solid. Look around to sample nearby walls.");
		else
			PrintToChat(client, "[KillZones] Collision scan OFF.");
		return true;
	}
	if (StrEqual(info, "gap")) {
		if (g_ShowCollision[client])
			CheckAimedGap(client);
		return true;
	}
	return false;
}

public bool Trace_CollisionGeometry(int entity, int contentsMask) {
	return entity < 1 || entity > MaxClients;
}

void UpdateCollisionScanners() {
	if (g_Beam <= 0)
		return;
	int scans;
	for (int visited = 0; visited < MaxClients && scans < SCANNERS_PER_TICK; visited++) {
		g_ScanCursor = (g_ScanCursor % MaxClients) + 1;
		if (!g_ShowCollision[g_ScanCursor] || !CanEdit(g_ScanCursor))
			continue;
		DrawCollisionScan(g_ScanCursor);
		scans++;
	}
}

void DrawCollisionScan(int client) {
	float eye[3], angles[3], look[3], right[3], up[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, look, right, up);
	for (int row = -2; row <= 2; row++) {
		for (int column = -2; column <= 2; column++) {
			float direction[3], end[3];
			for (int axis = 0; axis < 3; axis++)
				direction[axis] = look[axis] + right[axis] * float(column) * 0.2 + up[axis] * float(row) * 0.2;
			NormalizeVector(direction, direction);
			for (int axis = 0; axis < 3; axis++)
				end[axis] = eye[axis] + direction[axis] * COLLISION_SCAN_RANGE;
			Handle trace = TR_TraceRayFilterEx(eye, end, MASK_PLAYERSOLID, RayType_EndPoint, Trace_CollisionGeometry);
			if (!TR_DidHit(trace) || TR_StartSolid(trace) || TR_AllSolid(trace)) {
				delete trace;
				continue;
			}
			float hit[3], normal[3], fraction = TR_GetFraction(trace);
			TR_GetEndPosition(hit, trace);
			TR_GetPlaneNormal(trace, normal);
			delete trace;
			Handle clip = TR_TraceRayFilterEx(eye, end, CONTENTS_PLAYERCLIP, RayType_EndPoint, Trace_CollisionGeometry);
			bool playerClip = TR_DidHit(clip) && !TR_StartSolid(clip) && !TR_AllSolid(clip)
				&& FloatAbs(TR_GetFraction(clip) - fraction) * COLLISION_SCAN_RANGE <= 1.0;
			delete clip;
			int color[4] = {230, 15, 15, 255};
			if (playerClip) {
				color[0] = 15;
				color[1] = 75;
				color[2] = 255;
			}
			float center[3], strokeStart[3], strokeEnd[3];
			for (int axis = 0; axis < 3; axis++) {
				center[axis] = hit[axis] + normal[axis];
				strokeStart[axis] = center[axis] - right[axis] * 5.0;
				strokeEnd[axis] = center[axis] + right[axis] * 5.0;
			}
			int black[4] = {0, 0, 0, 255};
			TE_SetupBeamPoints(strokeStart, strokeEnd, g_Beam, 0, 0, 0, 1.1, 2.5, 2.5, 0, 0.0, black, 0);
			TE_SendToClient(client);
			for (int axis = 0; axis < 3; axis++) {
				strokeStart[axis] = center[axis] - up[axis] * 5.0;
				strokeEnd[axis] = center[axis] + up[axis] * 5.0;
			}
			TE_SetupBeamPoints(strokeStart, strokeEnd, g_Beam, 0, 0, 0, 1.1, 2.5, 2.5, 0, 0.0, color, 0);
			TE_SendToClient(client);
		}
	}
}

void CheckAimedGap(int client) {
	float start[3], end[3], angles[3], direction[3];
	GetClientAbsOrigin(client, start);
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	for (int axis = 0; axis < 3; axis++)
		end[axis] = start[axis] + direction[axis] * GAP_CHECK_RANGE;
	// Insurgency g_InsViewVectors: 34-wide hulls, standing 75 and crouching 49 units tall.
	CheckGapHull(client, "Standing", start, end, 75.0);
	CheckGapHull(client, "Crouching", start, end, 49.0);
	PrintToChat(client, "[KillZones] Tested %.0f units from your FEET in your look direction. Green = clear, red = blocked. Straight-path check only.", GAP_CHECK_RANGE);
}

void CheckGapHull(int client, const char[] stance, const float start[3], const float end[3], float height) {
	float mins[3] = {-17.0, -17.0, 0.0};
	float maxs[3] = {17.0, 17.0, 0.0};
	maxs[2] = height;
	Handle trace = TR_TraceHullFilterEx(start, end, mins, maxs, MASK_PLAYERSOLID, Trace_CollisionGeometry);
	bool inside = TR_StartSolid(trace) || TR_AllSolid(trace);
	bool blocked = inside || TR_DidHit(trace);
	float reached[3];
	if (inside)
		reached = start;
	else
		TR_GetEndPosition(reached, trace);
	delete trace;
	if (inside)
		PrintToChat(client, "[KillZones] %s: starts inside solid. Reposition before testing.", stance);
	else if (blocked)
		PrintToChat(client, "[KillZones] %s: BLOCKED after %.1f of %.0f units.", stance, GetVectorDistance(start, reached), GAP_CHECK_RANGE);
	else
		PrintToChat(client, "[KillZones] %s: CLEAR over the tested %.0f units.", stance, GAP_CHECK_RANGE);
	int color[4] = {70, 255, 90, 255};
	if (blocked) {
		color[0] = 255;
		color[1] = 70;
		color[2] = 70;
	}
	float boxMins[3], boxMaxs[3], lineStart[3], lineEnd[3];
	for (int axis = 0; axis < 3; axis++) {
		boxMins[axis] = reached[axis] + mins[axis];
		boxMaxs[axis] = reached[axis] + maxs[axis];
		lineStart[axis] = start[axis];
		lineEnd[axis] = reached[axis];
	}
	lineStart[2] += height * 0.5;
	lineEnd[2] += height * 0.5;
	DrawBox(client, boxMins, boxMaxs, color, 3.0);
	DrawContrastLine(client, lineStart, lineEnd, color, 3.0);
}

void DrawContrastLine(int client, const float start[3], const float end[3], const int color[4], float life) {
	if (GetVectorDistance(start, end, true) < 0.01)
		return;
	float points[4][3];
	points[0] = start;
	points[3] = end;
	for (int axis = 0; axis < 3; axis++) {
		points[1][axis] = start[axis] + (end[axis] - start[axis]) * 0.15;
		points[2][axis] = start[axis] + (end[axis] - start[axis]) * 0.85;
	}
	int black[4] = {0, 0, 0, 255};
	for (int segment = 0; segment < 3; segment++) {
		TE_SetupBeamPoints(points[segment], points[segment + 1], g_Beam, 0, 0, 0, life, 3.0, 3.0, 0, 0.0, segment == 1 ? color : black, 0);
		TE_SendToClient(client);
	}
}

void DrawBox(int client, const float mins[3], const float maxs[3], const int color[4], float life = 0.6) {
	float corners[8][3];
	for (int corner = 0; corner < 8; corner++) {
		for (int axis = 0; axis < 3; axis++)
			corners[corner][axis] = (corner & (1 << axis)) ? maxs[axis] : mins[axis];
	}
	for (int corner = 0; corner < 8; corner++) {
		for (int axis = 0; axis < 3; axis++) {
			if (corner & (1 << axis))
				continue;
			DrawContrastLine(client, corners[corner], corners[corner | (1 << axis)], color, life);
		}
	}
}

bool ReadVector(KeyValues kv, const char[] key, float vector[3]) {
	char value[192], parts[4][48];
	kv.GetString(key, value, sizeof value);
	if (ExplodeString(value, " ", parts, sizeof parts, sizeof parts[]) != 3)
		return false;
	for (int axis = 0; axis < 3; axis++) {
		int length = strlen(parts[axis]);
		if (!length || length >= sizeof parts[] - 1 || StringToFloatEx(parts[axis], vector[axis]) != length)
			return false;
	}
	return true;
}

bool ValidateData(KeyValues kv) {
	char root[32], map[PLATFORM_MAX_PATH];
	kv.Rewind();
	kv.GetSectionName(root, sizeof root);
	kv.GetString("map", map, sizeof map);
	if (!StrEqual(root, "BMKillZones") || kv.GetNum("version") != 1 || !StrEqual(map, g_Map) || !kv.JumpToKey("zones"))
		return false;
	int expectedCount = kv.GetNum("count", -1);
	if (expectedCount < -1 || expectedCount > MAX_ZONES)
		return false;
	int count;
	bool valid = true;
	if (kv.GotoFirstSubKey()) {
		do {
			float mins[3], maxs[3];
			char name[256], enabled[8];
			kv.GetString("name", name, sizeof name);
			kv.GetString("enabled", enabled, sizeof enabled);
			if (++count > MAX_ZONES || !name[0] || strlen(name) >= 64
				|| (!StrEqual(enabled, "0") && !StrEqual(enabled, "1"))
				|| !ReadVector(kv, "mins", mins) || !ReadVector(kv, "maxs", maxs) || !ValidBounds(mins, maxs)) {
				valid = false;
				break;
			}
		} while (kv.GotoNextKey());
	}
	kv.Rewind();
	return valid && (expectedCount == -1 || expectedCount == count);
}

void LoadZones() {
	g_DataReady = false;
	g_NextID = 1;
	for (int slot = 0; slot < MAX_ZONES; slot++)
		g_Zones[slot].id = 0;
	char backup[PLATFORM_MAX_PATH], source[PLATFORM_MAX_PATH];
	Format(backup, sizeof backup, "%s.bak", g_Path);
	if (!FileExists(g_Path) && !FileExists(backup)) {
		g_DataReady = true;
		return;
	}
	strcopy(source, sizeof source, FileExists(g_Path) ? g_Path : backup);
	KeyValues kv = new KeyValues("BMKillZones");
	kv.SetEscapeSequences(true);
	if (!kv.ImportFromFile(source) || !ValidateData(kv)) {
		LogError("Kill-zone data invalid or unreadable: %s. Enforcement and editing disabled; file retained. Repair the file and reload the plugin.", source);
		delete kv;
		return;
	}
	kv.JumpToKey("zones");
	int count;
	if (kv.GotoFirstSubKey()) {
		do {
			g_Zones[count].id = g_NextID++;
			kv.GetString("name", g_Zones[count].name, sizeof g_Zones[].name);
			ReadVector(kv, "mins", g_Zones[count].mins);
			ReadVector(kv, "maxs", g_Zones[count].maxs);
			g_Zones[count].enabled = kv.GetNum("enabled") != 0;
			count++;
		} while (kv.GotoNextKey());
	}
	delete kv;
	g_DataReady = true;
	LogMessage("Loaded %d kill zones for %s from %s", count, g_Map, source);
}

bool SaveZones() {
	if (!g_DataReady) {
		LogError("Kill-zone save blocked: map data is not ready (%s).", g_Path);
		return false;
	}
	char directory[PLATFORM_MAX_PATH], temp[PLATFORM_MAX_PATH], backup[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, directory, sizeof directory, "data/bm_killzones");
	if (!DirExists(directory) && !CreateDirectory(directory, 511)) {
		LogError("Kill-zone save failed: cannot create directory %s", directory);
		return false;
	}
	Format(temp, sizeof temp, "%s.tmp", g_Path);
	Format(backup, sizeof backup, "%s.bak", g_Path);
	KeyValues kv = new KeyValues("BMKillZones");
	kv.SetEscapeSequences(true);
	kv.SetNum("version", 1);
	kv.SetString("map", g_Map);
	kv.JumpToKey("zones", true);
	int count;
	for (int slot = 0; slot < MAX_ZONES; slot++) {
		if (!g_Zones[slot].id)
			continue;
		char key[16];
		IntToString(g_Zones[slot].id, key, sizeof key);
		kv.JumpToKey(key, true);
		kv.SetString("name", g_Zones[slot].name);
		kv.SetNum("enabled", g_Zones[slot].enabled ? 1 : 0);
		kv.SetVector("mins", g_Zones[slot].mins);
		kv.SetVector("maxs", g_Zones[slot].maxs);
		kv.GoBack();
		count++;
	}
	// Keep the section serializable even when the final zone is deleted.
	kv.SetNum("count", count);
	kv.Rewind();
	bool exported = kv.ExportToFile(temp);
	delete kv;
	if (!exported) {
		LogError("Kill-zone save failed: cannot write temporary file %s", temp);
		return false;
	}
	KeyValues verify = new KeyValues("BMKillZones");
	verify.SetEscapeSequences(true);
	bool imported = verify.ImportFromFile(temp);
	bool valid = imported && ValidateData(verify);
	delete verify;
	if (!valid) {
		LogError("Kill-zone save failed: temporary file %s (%s).", imported ? "failed validation" : "could not be read", temp);
		DeleteFile(temp);
		return false;
	}
	bool hadFile = FileExists(g_Path);
	if (hadFile && FileExists(backup) && !DeleteFile(backup)) {
		LogError("Kill-zone save failed: cannot remove previous backup %s", backup);
		DeleteFile(temp);
		return false;
	}
	if (hadFile && !RenameFile(backup, g_Path)) {
		LogError("Kill-zone save failed: cannot rename %s to backup %s", g_Path, backup);
		DeleteFile(temp);
		return false;
	}
	if (!RenameFile(g_Path, temp)) {
		LogError("Kill-zone save failed: cannot rename temporary file %s to %s", temp, g_Path);
		if (hadFile && !RenameFile(g_Path, backup))
			LogError("Could not restore kill-zone file; previous data remains at %s", backup);
		return false;
	}
	QueueRuntimeUpdate();
	return true;
}

void SaveFailed(int client) {
	PrintToChat(client, "[KillZones] SAVE FAILED: change cancelled. Check the server error log and file permissions.");
	LogError("Could not save kill zones to %s; requested change rolled back in memory.", g_Path);
}
