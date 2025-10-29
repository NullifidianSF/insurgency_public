#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

bool	g_bEventHooked = false;
int		g_iMapId = -1;

enum {
	embassy_coop = 0,
	congress_coop,
	frequency_open_coop,
	prospect_coop_b6,
	congress_open_coop,
	sinjar_coop,
	jail_break_coop_ws,
	crash_course,
	ins_dog_red,
	arcate_aof,
	dedust1p2_aof,
	hard_rain,
	facilityb2_coop_v1_1,
	cs_workout_v1,
	ins_mountain_escape_v1_3,
	karkand_redux_p2,
	pipeline_coop,
	ins_coastdawn_a3
};

public Plugin myinfo = {
	name = "map_entities",
	author = "Nullifidian + ChatGPT",
	description = "remove or modify entities for some maps",
	version = "2.7"
};

public void OnPluginStart() {
	RegAdminCmd("sm_totalent", cmd_totalent, ADMFLAG_RCON, "Print total entities");
	RegAdminCmd("sm_entstats", cmd_entstats, ADMFLAG_RCON, "List entity counts by classname.");
	RegAdminCmd("sm_entdelete", cmd_entdelete, ADMFLAG_RCON, "Delete ents by classname with optional name/model filters");
}

public void OnMapStart() {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	g_iMapId = -1;

	if (strcmp(sMapName, "embassy_coop", false) == 0) {
		g_iMapId = embassy_coop;
		RemoveEntities("env_sprite");
	}
	else if (strcmp(sMapName, "congress_coop", false) == 0) {
		g_iMapId = congress_coop;
		RemoveEntities("env_sprite");
	}
	else if (strcmp(sMapName, "frequency_open_coop", false) == 0) {
		g_iMapId = frequency_open_coop;
		RemoveEntities("env_sprite");
	}
	else if (strcmp(sMapName, "prospect_coop_b6", false) == 0) {
		g_iMapId = prospect_coop_b6;
		RemoveEntities("env_sprite");
	}
	else if (strcmp(sMapName, "congress_open_coop", false) == 0) {
		g_iMapId = congress_open_coop;
		RemoveEntities("env_sprite");
	}
	else if (strcmp(sMapName, "sinjar_coop", false) == 0) {
		g_iMapId = sinjar_coop;
	}
	else if (strcmp(sMapName, "jail_break_coop_ws", false) == 0) {
		g_iMapId = jail_break_coop_ws;
	}
	else if (strcmp(sMapName, "crash_course", false) == 0) {
		g_iMapId = crash_course;
	}
	else if (strcmp(sMapName, "ins_dog_red", false) == 0) {
		g_iMapId = ins_dog_red;
	}
	else if (strcmp(sMapName, "arcate_aof", false) == 0) {
		g_iMapId = arcate_aof;
	}
	else if (strcmp(sMapName, "dedust1p2_aof", false) == 0) {
		g_iMapId = dedust1p2_aof;
		RemoveEntities("logic_relay", "logic_breakdoor");
	}
	else if (strcmp(sMapName, "hard_rain", false) == 0) {
		g_iMapId = hard_rain;
		RemoveEntities("env_fog_controller");
	}
	else if (strcmp(sMapName, "facilityb2_coop_v1_1", false) == 0) {
		g_iMapId = facilityb2_coop_v1_1;
	}
	else if (strcmp(sMapName, "cs_workout_v1", false) == 0) {
		g_iMapId = cs_workout_v1;
	}
	else if (strcmp(sMapName, "ins_mountain_escape_v1_3", false) == 0) {
		g_iMapId = ins_mountain_escape_v1_3;
		RemoveEntities("env_fog_controller");
	}
	else if (strcmp(sMapName, "karkand_redux_p2", false) == 0) {
		g_iMapId = karkand_redux_p2;
		RemoveEntities("env_fog_controller");
	}
	else if (strcmp(sMapName, "pipeline_coop", false) == 0) {
		g_iMapId = pipeline_coop;
	}
	else if (strcmp(sMapName, "ins_coastdawn_a3", false) == 0) {
		g_iMapId = ins_coastdawn_a3;
		RemoveEntities("env_sprite");
	}
	else if (g_bEventHooked) {
		HookRoundStartEvent(false);
		return;
	}

	if (!g_bEventHooked) {
		HookRoundStartEvent();
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	switch (g_iMapId) {
		case embassy_coop, congress_coop, congress_open_coop: {
			RemoveEntities("prop_sprinkler");
		}
		case frequency_open_coop: {
			RemoveEntities("prop_sprinkler");
			RemoveEntities("func_dustmotes");
		}
		case prospect_coop_b6: {
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "env_fog_controller")) != -1) {
				AcceptEntityInput(iEnt, "TurnOff");	//turn off fog
				//turn on FarZ to improve FPS
				SetVariantString("7000");
				AcceptEntityInput(iEnt, "SetFarZ");
			}
		}
		case sinjar_coop: {
			RemoveEntities("func_breakable", "Breakable_CP5");
		}
		case jail_break_coop_ws: {
			RemoveEntities("func_door", "prison_door2");
			RemoveEntities("func_door", "prison_door3");
			RemoveEntities("func_door", "road_gate");
			RemoveEntities("func_door", "final_door1");
			RemoveEntities("func_door", "final_door2");
			RemoveEntities("func_breakable", "breakout_wall");
		}
		case crash_course: {
			RemoveEntities("func_nav_blocker", "bridge_navblocker");
			RemoveEntities("prop_dynamic", "howitzer_door");
		}
		case ins_dog_red: {
			RemoveEntities("func_door", "Bunker_Doors");
		}
		case arcate_aof: {
			RemoveEntities("func_door_rotating", "doorC");
		}
		case dedust1p2_aof: {
			RemoveEntities("func_breakable", "breakdoor");
			RemoveEntities("prop_dynamic", "ied_model");
		}
		case facilityb2_coop_v1_1: {
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "func_breakable")) != -1) {
				//set hp on windows so we can break them
				SetVariantString("100");
				AcceptEntityInput(iEnt, "SetHealth");
			}
		}
		case cs_workout_v1: {
			RemoveEntities("func_door_rotating");	//remove doors
			//remove door handles
			char sModelName[64];
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "prop_dynamic")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
				if (StrContains(sModelName, "door_handle_01", false) > -1) {
					SafeKillIdx(iEnt);
				}
			}
		}
		case pipeline_coop: {
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "func_breakable")) != -1) {
				if (GetEntProp(iEnt, Prop_Data, "m_iHealth") != 500)
					SafeKillIdx(iEnt);
			}
			
			RemoveEntities("prop_door_rotating");
			RemoveEntities("func_brush");
		}
		case ins_coastdawn_a3: {
			RemoveEntities("func_breakable");
		}
	}
	return Plugin_Continue;
}

void RemoveEntities(char[] sClass, char[] sName = "") {
	int	iCount = 0,
		iEnt = -1;

	if (strlen(sName) > 0) {
		char sTempName[64];
		while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1) {
			GetEntPropString(iEnt, Prop_Data, "m_iName", sTempName, sizeof(sTempName));
			if (strcmp(sTempName, sName, false) == 0) {
				SafeKillIdx(iEnt);
				iCount++;
			}
		}
	} else {
		while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1) {
			SafeKillIdx(iEnt);
			iCount++;
		}
	}

	if (iCount > 0) {
		if (strlen(sName) > 0) {
			PrintToServer("[map_entities] Removed: \"%s\" named \"%s\" x %d", sClass, sName, iCount);
		} else {
			PrintToServer("[map_entities] Removed: \"%s\" x %d", sClass, iCount);
		}
	} else {
		if (strlen(sName) > 0) {
			PrintToServer("[map_entities] Didn't find: \"%s\" named \"%s\"", sClass, sName);
			LogError("Didn't find: \"%s\" named \"%s\"", sClass, sName);
		} else {
			PrintToServer("[map_entities] Didn't find: \"%s\"", sClass);
			LogError("Didn't find: \"%s\"", sClass);
		}
	}
}

public Action cmd_totalent(int client, int args) {
	ReplyToCommand(client, "Total entities: %i", CountEnt());
	return Plugin_Handled;
}

int CountEnt() {
	int iCount = 0;
	for (int i = 0; i < GetMaxEntities(); i++) {
		if (!IsValidEntity(i))
			continue;
		iCount++;
	}
	return iCount;
}

void HookRoundStartEvent(bool hook = true) {
	if (hook) {
		g_bEventHooked = true;
		HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	} else {
		UnhookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
		g_bEventHooked = false;
	}
}

public Action cmd_entstats(int client, int args) {
	StringMap counts = new StringMap();
	int used = 0;
	char cls[64];

	int maxe = GetMaxEntities();
	for (int i = 0; i < maxe; i++) {
		if (!IsValidEntity(i))
			continue;

		if (i >= 1 && i <= MaxClients)
			continue;

		GetEntityClassname(i, cls, sizeof(cls));
		if (!cls[0])
			continue;

		int c;
		if (counts.GetValue(cls, c))
			counts.SetValue(cls, c + 1);
		else
			counts.SetValue(cls, 1);

		used++;
	}

	StringMapSnapshot snap = counts.Snapshot();
	int n = snap.Length;

	int[] order = new int[n];
	for (int i = 0; i < n; i++)
		order[i] = i;

	for (int a = 0; a < n - 1; a++) {
		int best = a;
		int bestCount = EntClassCountBySnap(counts, snap, order[best]);

		for (int b = a + 1; b < n; b++) {
			int curCount = EntClassCountBySnap(counts, snap, order[b]);
			if (curCount > bestCount) {
				best = b;
				bestCount = curCount;
			}
		}

		if (best != a) {
			int tmp = order[a];
			order[a] = order[best];
			order[best] = tmp;
		}
	}

	bool toClient = (client > 0 && IsClientInGame(client));
	if (toClient) {
		PrintToConsole(client, "=== Entity class counts (excluding players) ===");
		PrintToConsole(client, "Used edicts: %d / %d (free: %d)", used, maxe, (maxe - used));
		PrintToConsole(client, "%-5s  %-40s  %s", "#", "classname", "count");
	}
	else {
		PrintToServer("=== Entity class counts (excluding players) ===");
		PrintToServer("Used edicts: %d / %d (free: %d)", used, maxe, (maxe - used));
		PrintToServer("%-5s  %-40s  %s", "#", "classname", "count");
	}

	char key[64];
	for (int i = 0; i < n; i++) {
		snap.GetKey(order[i], key, sizeof(key));
		int cnt = 0;
		counts.GetValue(key, cnt);

		if (toClient)
			PrintToConsole(client, "%-5d  %-40s  %d", i + 1, key, cnt);
		else
			PrintToServer("%-5d  %-40s  %d", i + 1, key, cnt);
	}

	if (toClient)
		ReplyToCommand(client, "Entity stats printed to your console.");

	delete snap;
	delete counts;
	return Plugin_Handled;
}

public Action cmd_entdelete(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "Usage: sm_entdelete <classname> [name|model:<substr>] [-contains]");
		return Plugin_Handled;
	}

	char cls[64];
	GetCmdArg(1, cls, sizeof(cls));

	char nameFilter[64]; nameFilter[0] = '\0';
	char modelFilter[PLATFORM_MAX_PATH]; modelFilter[0] = '\0';
	bool contains = false;

	if (args >= 2) {
		char arg2[PLATFORM_MAX_PATH];
		GetCmdArg(2, arg2, sizeof(arg2));

		if (StrContains(arg2, "model:", false) == 0) {
			strcopy(modelFilter, sizeof(modelFilter), arg2[6]);
		}
		else {
			strcopy(nameFilter, sizeof(nameFilter), arg2);
		}
	}

	if (args >= 3) {
		char arg3[32];
		GetCmdArg(3, arg3, sizeof(arg3));
		contains = (StrEqual(arg3, "-contains", false) || StrEqual(arg3, "-c", false));
	}

	int removed = RemoveEntitiesByCmd(cls, nameFilter, contains, modelFilter);

	if (removed > 0)
		ReplyToCommand(client, "[map_entities] Removed \"%s\" %s%s%s x %d",
			cls,
			modelFilter[0] ? "model~" : (nameFilter[0] ? "named " : ""),
			modelFilter[0] ? modelFilter : (nameFilter[0] ? nameFilter : ""),
			contains && nameFilter[0] ? " (contains)" : "",
			removed);
	else
		ReplyToCommand(client, "[map_entities] No matches for \"%s\" with given filters.", cls);

	return Plugin_Handled;
}

static int RemoveEntitiesByCmd(const char[] sClass, const char[] sNameFilter = "", bool contains = false, const char[] sModelFilter = "") {
	int count = 0;
	int ent = -1;

	char tempName[64];
	char tempModel[PLATFORM_MAX_PATH];

	while ((ent = FindEntityByClassname(ent, sClass)) != -1) {
		if (ent <= MaxClients || !IsValidEntity(ent))
			continue;

		bool match = true;

		if (sModelFilter[0]) {
			GetEntPropString(ent, Prop_Data, "m_ModelName", tempModel, sizeof(tempModel));
			if (!tempModel[0] || StrContains(tempModel, sModelFilter, false) == -1)
				match = false;
		}

		if (match && sNameFilter[0]) {
			GetEntPropString(ent, Prop_Data, "m_iName", tempName, sizeof(tempName));
			if (contains) {
				if (StrContains(tempName, sNameFilter, false) == -1)
					match = false;
			}
			else {
				if (strcmp(tempName, sNameFilter, false) != 0)
					match = false;
			}
		}

		if (!match)
			continue;

		SafeKillIdx(ent);
		count++;
	}

	return count;
}

static int EntClassCountBySnap(StringMap map, StringMapSnapshot snap, int snapIndex) {
	char k[64];
	snap.GetKey(snapIndex, k, sizeof(k));
	int c = 0;
	map.GetValue(k, c);
	return c;
}

stock void SafeKillIdx(int ent) {
	if (ent <= MaxClients) return;
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