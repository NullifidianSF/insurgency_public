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
	game_day_coop_ws,
	hard_rain,
	facilityb2_coop_v1_1,
	cs_workout_v1,
	ins_mountain_escape_v1_3
};

public Plugin myinfo = {
	name = "map_entities",
	author = "Nullifidian",
	description = "remove or modify entities for some maps",
	version = "2.2"
};

public void OnPluginStart() {
	RegAdminCmd("sm_totalent", cmd_totalent, ADMFLAG_RCON, "Print total entities");
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
	else if (strcmp(sMapName, "game_day_coop_ws", false) == 0) {
		g_iMapId = game_day_coop_ws;
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
	else if (g_bEventHooked) {
		HookFreezeRoundEnd(false);
		return;
	}

	if (!g_bEventHooked) {
		HookFreezeRoundEnd();
	}
}

public Action Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
	switch (g_iMapId) {
		case embassy_coop, congress_coop, congress_open_coop: {
			RemoveEntities("prop_sprinkler");
		}
		case frequency_open_coop: {
			RemoveEntities("prop_sprinkler");
			RemoveEntities("func_dustmotes");
		}
		case prospect_coop_b6: {
			int iEnt = MaxClients + 1;
			while ((iEnt = FindEntityByClassname(iEnt, "env_fog_controller")) != -1) {
				AcceptEntityInput(iEnt, "TurnOff");	//turn off fog
				//turn on FarZ to improve FPS
				SetVariantString("8500");
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
		case game_day_coop_ws: {
			RemoveEntities("func_door");
		}
		case facilityb2_coop_v1_1: {
			int iEnt = MaxClients + 1;
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
			int iEnt = MaxClients + 1;
			while ((iEnt = FindEntityByClassname(iEnt, "prop_dynamic")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
				if (StrContains(sModelName, "door_handle_01", false) > -1) {
					RemoveEntity(iEnt);
				}
			}
		}
	}
}

void RemoveEntities(char[] sClass, char[] sName = "") {
	int	iCount = 0,
		iEnt = MaxClients + 1;

	if (strlen(sName) > 0) {
		char sTempName[64];
		while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1) {
			GetEntPropString(iEnt, Prop_Data, "m_iName", sTempName, sizeof(sTempName));
			if (strcmp(sTempName, sName, false) == 0) {
				RemoveEntity(iEnt);
				iCount++;
			}
		}
	} else {
		while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1) {
			RemoveEntity(iEnt);
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
	for (int i = 0; i <= 2048; i++) {
		if (!IsValidEntity(i))
			continue;
		iCount++;
	}
	return iCount;
}

void HookFreezeRoundEnd(bool hook = true) {
	if (hook) {
		HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
		g_bEventHooked = true;
	} else {
		UnhookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
		g_bEventHooked = false;
	}
}