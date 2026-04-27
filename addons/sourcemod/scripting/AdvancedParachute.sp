#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#define PLUGIN_NAME		"Advanced Parachute"
#define PLUGIN_VERSION	"1.9"
#define PLUGIN_AUTHOR	"ESK0"

#define	BTN_USE			(1 << 6)

public Plugin myinfo =
{
	name	= PLUGIN_NAME,
	version	= PLUGIN_VERSION,
	author	= PLUGIN_AUTHOR,
	url		= ""
};

// ------------------------------------------------------------
// Config / assets
// ------------------------------------------------------------
char sFilePath[PLATFORM_MAX_PATH];

char sAllowedMaps[][] =
{
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
Handle		g_hTimerAd[MAXPLAYERS + 1];

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
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_hOnParachute = CreateGlobalForward("OnParachuteOpen", ET_Event, Param_Cell);
	RegPluginLibrary("AdvancedParachute");
	return APLRes_Success;
}

// ------------------------------------------------------------
// Plugin lifecycle
// ------------------------------------------------------------
public void OnPluginStart()
{
	RegConsoleCmd("sm_parachute", Command_Parachute);

	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/AdvancedParachute.cfg");

	arParachuteList = new ArrayList(256);
	smParachutes = new StringMap();

	HookEvent("player_death", Event_OnPlayerDeath);

	g_hParachute = RegClientCookie("advanced_parachute_test", "Parachute clientprefs", CookieAccess_Private);
}

public void OnMapStart()
{
	g_bAllowedMap = false;
	g_iOpenChuteCount = 0;

	char sMapname[64];
	GetCurrentMap(sMapname, sizeof(sMapname));

	for (int i = 0; i < sizeof(sAllowedMaps); i++)
	{
		if (strcmp(sMapname, sAllowedMaps[i], false) == 0)
		{
			g_bAllowedMap = true;
			break;
		}
	}

	if (!g_bAllowedMap)
	{
		CreateTimer(1.0, Timer_UnloadSelf, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	PrecacheModels();

	g_iDefaultPar = -1;
	arParachuteList.Clear();
	smParachutes.Clear();

	KeyValues kv = new KeyValues("AdvancedParachute");
	if (!FileExists(sFilePath))
	{
		SetFailState("[AdvancedParachute] Missing config: %s", sFilePath);
		return;
	}
	kv.ImportFromFile(sFilePath);
	if (kv.GotoFirstSubKey())
	{
		AdvP_AddParachute(kv);
		while (kv.GotoNextKey())
		{
			AdvP_AddParachute(kv);
		}
	}
	delete kv;

	if (g_iDefaultPar == -1)
	{
		SetFailState("[AdvancedParachute] Default parachute not found in config");
	}
}

public Action Timer_UnloadSelf(Handle timer)
{
	char fn[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, fn, sizeof fn);
	ServerCommand("sm plugins unload %s", fn);
	return Plugin_Stop;
}

// ------------------------------------------------------------
// Client lifecycle
// ------------------------------------------------------------
public void OnClientPostAdminCheck(int client)
{
	if (!g_bAllowedMap || !IsValidClient(client) || IsFakeClient(client))
		return;

	if (g_iDefaultPar < 0 || arParachuteList.Length == 0)
		return;

	if (g_hTimerAd[client] == null)
		g_hTimerAd[client] = CreateTimer(90.0, Timer_PrintMsg, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	// Ensure cookie is a valid choice (or set default)
	char sDefault[64];
	arParachuteList.GetString(g_iDefaultPar, sDefault, sizeof sDefault);

	char sCookie[64];
	GetClientCookie(client, g_hParachute, sCookie, sizeof sCookie);

	bool validCookie = false;
	if (sCookie[0] != '\0' && arParachuteList.FindString(sCookie) != -1)
	{
		char conf[512], parts[2][512];
		if (smParachutes.GetString(sCookie, conf, sizeof conf))
		{
			ExplodeString(conf, ";", parts, sizeof parts, sizeof parts[]);
			int flags = ReadFlagString(parts[1]);
			if (strlen(parts[1]) == 0 || CheckCommandAccess(client, "", flags, true))
				validCookie = true;
		}
	}

	if (!validCookie)
		SetClientCookie(client, g_hParachute, sDefault);

	// Reset runtime state
	g_LastButtons[client] = 0;
	g_bChuteOpen[client] = false;
	g_iParachuteRef[client] = INVALID_ENT_REFERENCE;
}

public void OnClientDisconnect_Post(int client)
{
	g_LastButtons[client] = 0;

	if (g_bChuteOpen[client])
		RemoveParachute(client);

	if (g_hTimerAd[client] != null)
	{
		delete g_hTimerAd[client];
		g_hTimerAd[client] = null;
	}

	g_bChuteOpen[client] = false;
	g_iParachuteRef[client] = INVALID_ENT_REFERENCE;
}

// ------------------------------------------------------------
// Gameplay
// ------------------------------------------------------------
public void OnGameFrame()
{
	if (!g_bAllowedMap || g_iOpenChuteCount == 0)
		return;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsValidClient(client, true))
			continue;

		if (!g_bChuteOpen[client])
			continue;

		float vel[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vel);

		if (vel[2] < 0.0)
		{
			const float clampDown = -100.0;
			if (vel[2] < clampDown)
			{
				vel[2] += 50.0;
				if (vel[2] > clampDown)
					vel[2] = clampDown;
			}
			else
			{
				vel[2] = clampDown;
			}

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!g_bAllowedMap)
		return Plugin_Continue;

	if (!IsValidClient(client, true))
		return Plugin_Continue;

	int flags = GetEntityFlags(client);

	// Auto-close when hitting ground
	if (g_bChuteOpen[client] && (flags & FL_ONGROUND))
		RemoveParachute(client);

	bool usePressed = (buttons & BTN_USE) && !(g_LastButtons[client] & BTN_USE);
	bool useReleased = !(buttons & BTN_USE) && (g_LastButtons[client] & BTN_USE);

	if (!IsFakeClient(client))
	{
		// Open on +use if mid-air and no chute
		if (usePressed && !g_bChuteOpen[client] && !(flags & FL_ONGROUND))
			AttachParachute(client);

		// Close on -use
		if (useReleased && g_bChuteOpen[client])
			RemoveParachute(client);
	}
	else
	{
		// Simple bot behavior: always open mid-air if not open
		if (!g_bChuteOpen[client] && !(flags & FL_ONGROUND))
			AttachParachute(client);
	}

	g_LastButtons[client] = buttons;
	return Plugin_Continue;
}

public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidClient(client) && g_bChuteOpen[client])
		RemoveParachute(client);
	return Plugin_Continue;
}

// ------------------------------------------------------------
// Commands / Menus
// ------------------------------------------------------------
public Action Command_Parachute(int client, int args)
{
	if (!g_bAllowedMap || !IsValidClient(client) || arParachuteList.Length == 0)
		return Plugin_Handled;

	Menu menu = new Menu(h_parachutemenu);
	menu.SetTitle("Advanced Parachute");

	char sCurrent[64];
	GetClientCookie(client, g_hParachute, sCurrent, sizeof sCurrent);

	for (int i = 0; i < arParachuteList.Length; i++)
	{
		char sName[64];
		char sConf[512];
		char parts[2][512];

		arParachuteList.GetString(i, sName, sizeof sName);
		smParachutes.GetString(sName, sConf, sizeof sConf);
		ExplodeString(sConf, ";", parts, sizeof parts, sizeof parts[]);

		int flags = ReadFlagString(parts[1]);

		bool allowed = (strlen(parts[1]) == 0) ? true : CheckCommandAccess(client, "", flags, true);
		int draw = allowed && !StrEqual(sName, sCurrent, false) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
		menu.AddItem(sName, sName, draw);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int h_parachutemenu(Menu menu, MenuAction action, int client, int item)
{
	if (!IsValidClient(client))
	{
		if (action == MenuAction_End)
			delete menu;
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char chosen[64];
		menu.GetItem(item, chosen, sizeof chosen);
		SetClientCookie(client, g_hParachute, chosen);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

// ------------------------------------------------------------
// Parachute attach/remove
// ------------------------------------------------------------
stock void ChuteClearState(int client)
{
	if (g_bChuteOpen[client] && g_iOpenChuteCount > 0)
		g_iOpenChuteCount--;

	g_bChuteOpen[client] = false;
	g_iParachuteRef[client] = INVALID_ENT_REFERENCE;
}

stock int ChuteEntIndex(int client)
{
	int ref = g_iParachuteRef[client];
	if (ref == INVALID_ENT_REFERENCE)
		return -1;

	int ent = EntRefToEntIndex(ref);
	if (ent == INVALID_ENT_REFERENCE || ent <= MaxClients || !IsValidEntity(ent))
		return -1;

	return ent;
}

void AttachParachute(int client)
{
	if (!g_bAllowedMap || !IsValidClient(client, true) || g_bChuteOpen[client])
		return;

	Action result = Plugin_Continue;
	Call_StartForward(g_hOnParachute);
	Call_PushCell(client);
	Call_Finish(result);
	if (result == Plugin_Stop || result == Plugin_Handled)
		return;

	int ent = CreateEntityByName("prop_dynamic_override");
	if (ent == -1 || !IsValidEntity(ent))
		return;

	char modelStr[PLATFORM_MAX_PATH];
	modelStr[0] = '\0';

	if (!IsFakeClient(client))
	{
		char sCookie[64];
		GetClientCookie(client, g_hParachute, sCookie, sizeof sCookie);

		char sConf[512];
		if (smParachutes.GetString(sCookie, sConf, sizeof sConf))
		{
			char parts[2][512];
			ExplodeString(sConf, ";", parts, sizeof parts, sizeof parts[]);
			strcopy(modelStr, sizeof modelStr, parts[0]);
		}
		else
		{
			// fallback to default section
			char defName[64];
			arParachuteList.GetString(g_iDefaultPar, defName, sizeof defName);
			if (smParachutes.GetString(defName, sConf, sizeof sConf))
			{
				char dparts[2][512];
				ExplodeString(sConf, ";", dparts, sizeof dparts, sizeof dparts[]);
				strcopy(modelStr, sizeof modelStr, dparts[0]);
			}
		}
	}
	else
	{
		static const char g_BotModels[][] =
		{
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
		int idx = GetRandomInt(0, sizeof(g_BotModels) - 1);
		strcopy(modelStr, sizeof modelStr, g_BotModels[idx]);
	}

	if (modelStr[0] != '\0')
		DispatchKeyValue(ent, "model", modelStr);

	SetEntProp(ent, Prop_Send, "m_usSolidFlags", 12);
	SetEntProp(ent, Prop_Data, "m_nSolidType", 6);
	SetEntProp(ent, Prop_Send, "m_CollisionGroup", 1);

	if (!DispatchSpawn(ent))
	{
		if (!AcceptEntityInput(ent, "Kill"))
			RemoveEntity(ent);
		return;
	}

	float origin[3];
	float ang[3];
	float attachAng[3];

	GetClientAbsOrigin(client, origin);
	GetClientAbsAngles(client, ang);
	attachAng[0] = 0.0;
	attachAng[1] = ang[1];
	attachAng[2] = 0.0;

	TeleportEntity(ent, origin, attachAng, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(ent, "SetParent", client);

	if (StrContains(modelStr, "gargoyle", false) != -1)
	{
		SetVariantString("idle");
		AcceptEntityInput(ent, "SetAnimation");
	}

	g_iParachuteRef[client] = EntIndexToEntRef(ent);
	g_bChuteOpen[client] = true;
	g_iOpenChuteCount++;
}

void RemoveParachute(int client)
{
	if (!g_bChuteOpen[client] && g_iParachuteRef[client] == INVALID_ENT_REFERENCE)
		return;

	int ref = g_iParachuteRef[client];

	// Clear state first, then kill next frame (avoids same-frame parent/owner issues)
	ChuteClearState(client);

	if (ref != INVALID_ENT_REFERENCE)
		RequestFrame(DeferredKillRef, ref);
}

public void DeferredKillRef(any ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent > MaxClients && ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "ClearParent");
		if (!AcceptEntityInput(ent, "Kill"))
			RemoveEntity(ent);
	}
}

// ------------------------------------------------------------
// Chat nudges (optional)
// ------------------------------------------------------------
public Action Timer_PrintMsg(Handle timer, int client)
{
	if (!IsClientInGame(client))
	{
		g_hTimerAd[client] = null;
		return Plugin_Stop;
	}

	if (!g_bAllowedMap)
		return Plugin_Continue;

	if (GetClientTeam(client) == 2)
	{
		PrintToChat(client, "\x070088cc[BM]\x01 Hello \x07ffff00%N\x01, you can use a parachute on this map.", client);
		PrintToChat(client, "\x070088cc[BM]\x01 Hold \x07ffff00USE (F)\x01 to open. Type \x07ffff00!parachute\x01 for skins.");
	}
	return Plugin_Continue;
}

// ------------------------------------------------------------
// Config loading helpers
// ------------------------------------------------------------
void AdvP_AddParachute(KeyValues kv)
{
	char sName[64];
	char sModel[PLATFORM_MAX_PATH];
	char sFlag[32];
	char sPack[512];

	kv.GetSectionName(sName, sizeof sName);
	arParachuteList.PushString(sName);

	kv.GetString("model", sModel, sizeof sModel);
	kv.GetString("flag", sFlag, sizeof sFlag, "");

	if (g_iDefaultPar == -1)
	{
		if (kv.GetNum("default", 0) == 1)
			g_iDefaultPar = arParachuteList.Length - 1;
	}

	Format(sPack, sizeof sPack, "%s;%s", sModel, sFlag);
	smParachutes.SetString(sName, sPack);
}

// ------------------------------------------------------------
// Precaching
// ------------------------------------------------------------
void PrecacheModels()
{
	// Models
	PrecacheModel("models/parachute/gargoyle.mdl", true);
	PrecacheModel("models/parachute/parachute_ark.mdl", true);
	PrecacheModel("models/parachute/parachute_bf2.mdl", true);
	PrecacheModel("models/parachute/parachute_bf2002.mdl", true);
	PrecacheModel("models/parachute/parachute_bf2142.mdl", true);
	PrecacheModel("models/parachute/parachute_blue.mdl", true);
	PrecacheModel("models/parachute/parachute_carbon.mdl", true);
	PrecacheModel("models/parachute/parachute_green_v2.mdl", true);
	PrecacheModel("models/parachute/parachute_ice_v2.mdl", true);
	PrecacheModel("models/parachute/parachute_rainbow.mdl", true);
	PrecacheModel("models/parachute/parachute_spongebob.mdl", true);
	PrecacheModel("models/parachute/parachute_star_fox_guard.mdl", true);
	PrecacheModel("models/parachute/umbrella_big2.mdl", true);

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

// ------------------------------------------------------------
// Utils
// ------------------------------------------------------------
bool IsValidClient(int client, bool alive = false)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		if (!alive || IsPlayerAlive(client))
			return true;
	}
	return false;
}
