#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

int		ga_iVictims[MAXPLAYERS + 1][2];

Handle	ga_hGrenadeTimer[MAXPLAYERS + 1],
		ga_hArtiTimer[MAXPLAYERS + 1];

float	g_fShells,
		ga_fFireSupportTime[MAXPLAYERS + 1];

bool	g_bFireSupportPlugin = false;

ConVar	g_cvShells;

char ga_sWeapon[][] = {
	"rocket_at4",
	"rocket_rpg7",
	"grenade_f1",
	"grenade_m67",
	"grenade_m26a2",
	"grenade_c4",
	"grenade_ied",
	"grenade_ied_gunshot",
	"grenade_m203_he",
	"grenade_gp25_he",
	//"grenade_m79",
	"grenade_ied_fire",
	"grenade_ied_radius",
	"grenade_c4_radius",
	"prop_dynamic"
};

public Plugin myinfo = {
	name = "explosive_total_kills",
	author = "Nullifidian",
	description = "Print in chat how many kills with one explosive.",
	version = "1.0.4",
	url = "https://steamcommunity.com/id/Nullifidian/"
};

public void OnPluginStart() {
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
}

public void OnLibraryRemoved(const char[] name) {
	if (strcmp(name, "FireSupport", false) == 0) {
		g_bFireSupportPlugin = false;
		UnhookEvent("grenade_detonate", Event_GrenadeDetonate);
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i)) {
				delete ga_hArtiTimer[i];
				ga_iVictims[i][1] = 0;
			}
		}
		if (g_cvShells) {
			g_cvShells.RemoveChangeHook(OnConVarChanged);
		}
	}
}

public void OnLibraryAdded(const char[] name) {
	if (strcmp(name, "FireSupport", false) == 0) {
		g_bFireSupportPlugin = true;
		g_cvShells = FindConVar("sm_firesupport_shell_num");
		if (g_cvShells) {
			g_fShells = g_cvShells.FloatValue;
			g_cvShells.AddChangeHook(OnConVarChanged);
		}
		HookEvent("grenade_detonate", Event_GrenadeDetonate);
	}
}

public void OnClientDisconnect(int iAttacker) {
	delete ga_hGrenadeTimer[iAttacker];
	delete ga_hArtiTimer[iAttacker];
	for (int i = 0; i <= 1; i++) {
		ga_iVictims[iAttacker][i] = 0;
	}
}

public Action Event_GrenadeDetonate(Event event, char[] name, bool dontBroadcast) {
	if (event.GetInt("id") == 25) {
		ga_fFireSupportTime[GetClientOfUserId(event.GetInt("userid"))] = GetTickedTime();
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int	iAttacker = GetClientOfUserId(event.GetInt("attacker")),
		iVictim = GetClientOfUserId(event.GetInt("userid"));

	if (!IsValidClient(iAttacker) || iAttacker == iVictim || IsFakeClient(iAttacker)) {
		return Plugin_Continue;
	}

	char sWeapon[32];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	//PrintToChatAll("sWeapon: %s",sWeapon);

	for (int count=0; count<sizeof(ga_sWeapon); count++) {
		if (strcmp(sWeapon, ga_sWeapon[count], false) == 0) {
			ga_iVictims[iAttacker][0]++;
			if (ga_hGrenadeTimer[iAttacker] == null) {
				DataPack Dpack;
				ga_hGrenadeTimer[iAttacker] = CreateDataTimer(0.1, Timer_GrenadeTotalKilled, Dpack);
				Dpack.WriteCell(iAttacker);
				Dpack.WriteString(sWeapon);
				return Plugin_Continue;
			}
			return Plugin_Continue;
		}
	}

	if (g_bFireSupportPlugin && strcmp(sWeapon, "rocket_firesupport", false) == 0) {
		ga_iVictims[iAttacker][1]++;
		if (ga_hArtiTimer[iAttacker] == null) {
			ga_hArtiTimer[iAttacker] = CreateTimer(g_cvShells ? ((1.2 * g_fShells) - (GetTickedTime() - ga_fFireSupportTime[iAttacker])) : (24.0 - (GetTickedTime() - ga_fFireSupportTime[iAttacker])), Timer_ArtiTotalKilled, iAttacker);
		}
	}
	return Plugin_Continue;
}

Action Timer_GrenadeTotalKilled(Handle timer, DataPack Dpack) {
	Dpack.Reset();
	int iAttacker = Dpack.ReadCell();

	if (ga_iVictims[iAttacker][0] > 5) {
		char	sWeapon[32],
				sRename[32];

		Dpack.ReadString(sWeapon, sizeof(sWeapon));

		if (strcmp(sWeapon, "rocket_at4", false) == 0) {
			sRename = "AT4";
		}
		else if (strcmp(sWeapon, "rocket_rpg7", false) == 0) {
			sRename = "RPG-7";
		}
		else if (strcmp(sWeapon, "grenade_f1", false) == 0) {
			sRename = "F1";
		}
		else if (strcmp(sWeapon, "grenade_m67", false) == 0) {
			sRename = "M67";
		}
		else if (strcmp(sWeapon, "grenade_m26a2", false) == 0) {
			sRename = "M26A2 Frag";
		}
		else if (strcmp(sWeapon, "grenade_c4", false) == 0) {
			sRename = "C4";
		}
		else if (strcmp(sWeapon, "grenade_ied", false) == 0) {
			sRename = "IED";
		}
		else if (strcmp(sWeapon, "grenade_ied_gunshot", false) == 0) {
			sRename = "IED-G";
		}
		else if (strcmp(sWeapon, "grenade_m203_he", false) == 0) {
			sRename = "M203 HE";
		}
		else if (strcmp(sWeapon, "grenade_gp25_he", false) == 0) {
			sRename = "GP-25 HE";
		}
		else if (strcmp(sWeapon, "grenade_ied_fire", false) == 0) {
			sRename = "IED-F";
		}
		else if (strcmp(sWeapon, "grenade_ied_radius", false) == 0) {
			sRename = "IED-R";
		}
		else if (strcmp(sWeapon, "grenade_c4_radius", false) == 0) {
			sRename = "C4-R";
		}
		else if (strcmp(sWeapon, "prop_dynamic", false) == 0) {
			sRename = "TRIP MINE";
		}
		PrintToChatAll("\x07859715%N  \x07ffffff[%s] x \x07ad3e24%d", iAttacker, sRename, ga_iVictims[iAttacker][0]);
	}
	ga_iVictims[iAttacker][0] = 0;
	ga_hGrenadeTimer[iAttacker] = null;
	return Plugin_Stop;
}

Action Timer_ArtiTotalKilled(Handle timer, int iAttacker) {
	if (ga_iVictims[iAttacker][1] > 5) {
		PrintToChatAll("\x07859715%N  \x07ffffff[Artillery] x \x07ad3e24%d", iAttacker, ga_iVictims[iAttacker][1]);
	}
	ga_iVictims[iAttacker][1] = 0;
	ga_hArtiTimer[iAttacker] = null;
	return Plugin_Stop;
}

bool IsValidClient(int client) {
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client)) {
		return false;
	}
	return true;
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_fShells = g_cvShells.FloatValue;
}