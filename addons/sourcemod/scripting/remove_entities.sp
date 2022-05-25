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
	ins_prison_2020_new
};

public Plugin myinfo = {
	name = "remove_entities",
	author = "Nullifidian",
	description = "remove map entities",
	version = "1.8"
};

public void OnPluginStart() {
	RegAdminCmd("sm_totalent", cmd_totalent, ADMFLAG_BAN, "Print total entities");
}

public void OnMapStart() {
	g_iMapId = -1;

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	if (strcmp(sMapName, "embassy_coop", false) == 0) {
		g_iMapId = embassy_coop;
	}
	else if (strcmp(sMapName, "congress_coop", false) == 0) {
		g_iMapId = congress_coop;
	}
	else if (strcmp(sMapName, "frequency_open_coop", false) == 0) {
		g_iMapId = frequency_open_coop;
	}
	else if (strcmp(sMapName, "prospect_coop_b6", false) == 0) {
		g_iMapId = prospect_coop_b6;
	}
	else if (strcmp(sMapName, "congress_open_coop", false) == 0) {
		g_iMapId = congress_open_coop;
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
	else if (strcmp(sMapName, "ins_prison_2020_new", false) == 0) {
		g_iMapId = ins_prison_2020_new;
	} else {
		if (g_bEventHooked) {
			HookFreezeRoundEnd(false);
		}
		return;
	}

	if (!g_bEventHooked) {
		HookFreezeRoundEnd();
	}

	switch (g_iMapId) {
		case embassy_coop, congress_coop, frequency_open_coop, prospect_coop_b6, congress_open_coop: {
			RemoveEntities("env_sprite");
		}
	}
}

public Action Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
	int		iEnt = MaxClients + 1;
	char	sName[64];

	switch (g_iMapId) {
		case embassy_coop, congress_coop, congress_open_coop: {
			RemoveEntities("prop_sprinkler");
		}
		case frequency_open_coop: {
			RemoveEntities("prop_sprinkler");
			RemoveEntities("func_dustmotes");
		}
		case sinjar_coop: {
			while ((iEnt = FindEntityByClassname(iEnt, "func_breakable")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
				if (strcmp(sName, "Breakable_CP5", false) == 0) {
					RemoveEntity(iEnt);
				}
			}
		}
		case jail_break_coop_ws: {
			while ((iEnt = FindEntityByClassname(iEnt, "func_door")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
				if (/*strcmp(sName, "prison_door4a", false) == 0
				|| strcmp(sName, "prison_door4b", false) == 0
				|| */strcmp(sName, "prison_door2", false) == 0
				|| strcmp(sName, "prison_door3", false) == 0
				|| strcmp(sName, "road_gate", false) == 0
				|| strcmp(sName, "final_door2", false) == 0
				|| strcmp(sName, "final_door1", false) == 0) {
					RemoveEntity(iEnt);
				}
			}
			iEnt = MaxClients + 1;
			while ((iEnt = FindEntityByClassname(iEnt, "func_breakable")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
				if (strcmp(sName, "breakout_wall", false) == 0) {
					RemoveEntity(iEnt);
				}
			}
		}
		case crash_course: {
			while ((iEnt = FindEntityByClassname(iEnt, "func_nav_blocker")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
				if (strcmp(sName, "bridge_navblocker", false) == 0) {
					RemoveEntity(iEnt);
				}
			}
			iEnt = MaxClients + 1;
			while ((iEnt = FindEntityByClassname(iEnt, "prop_dynamic")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
				if (strcmp(sName, "howitzer_door", false) == 0) {
					RemoveEntity(iEnt);
				}
			}
		}
		case ins_dog_red: {
			while ((iEnt = FindEntityByClassname(iEnt, "func_door")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
				if (strcmp(sName, "Bunker_Doors", false) == 0) {
					RemoveEntity(iEnt);
				}
			}
		}
		case arcate_aof: {
			while ((iEnt = FindEntityByClassname(iEnt, "func_door_rotating")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));
				if (strcmp(sName, "doorC", false) == 0) {
					RemoveEntity(iEnt);
				}
			}
		}
		case ins_prison_2020_new: {
			while ((iEnt = FindEntityByClassname(iEnt, "func_door")) != -1) {
				if (GetEntPropFloat(iEnt, Prop_Data, "m_flWait") != -1.0) {
					SetEntPropFloat(iEnt, Prop_Data, "m_flWait", -1.0);
				}
			}
			iEnt = MaxClients + 1;
			while ((iEnt = FindEntityByClassname(iEnt, "func_door_rotating")) != -1) {
				if (GetEntPropFloat(iEnt, Prop_Data, "m_flWait") != -1.0) {
					SetEntPropFloat(iEnt, Prop_Data, "m_flWait", -1.0);
				}
			}
		}
	}
}

void RemoveEntities(char[] sEnt) {
	int	iCount = 0,
		iEnt = MaxClients + 1;

	while ((iEnt = FindEntityByClassname(iEnt, sEnt)) != -1) {
		RemoveEntity(iEnt);
		iCount++;
	}
	PrintToServer("!!! REMOVED %i %s !!!", iCount, sEnt);
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