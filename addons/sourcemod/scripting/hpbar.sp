#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

native bool Medic_IsClientMedic(int client);

public Plugin myinfo =
{
	name		= "HPbar2 (Medic Healthkit Team Bars)",
	author		= "Pericles (updated by ChatGPT)",
	description	= "Shows health bars over injured teammates (Security only), visible only to medics while holding the healthkit.",
	version		= "1.0",
	url			= "https://forums.alliedmods.net/showthread.php?t=312223"
};

static const int	TEAM_SECURITY	= 2;
static const int	HP_FULL			= 100;	// Insurgency players are effectively 100hp in normal play
static const float	BAR_Z_OFF		= 10.0;
static const float	UPDATERATE		= 0.50;	// Update interval (seconds) for teammate HP bars.

Handle	g_hUpdateTimer = INVALID_HANDLE;

int		g_iBarSpriteRef[MAXPLAYERS + 1];
int		g_iBarMmcRef[MAXPLAYERS + 1];
bool	g_bTargetInjured[MAXPLAYERS + 1];
int		g_iLastFrame[MAXPLAYERS + 1];

bool	g_bHasMedicNative = false;

float	g_fViewerNextCheck[MAXPLAYERS + 1];
bool	g_bViewerHoldingKit[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Medic_IsClientMedic");
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	g_bHasMedicNative = (LibraryExists("bm_medic")
		&& GetFeatureStatus(FeatureType_Native, "Medic_IsClientMedic") == FeatureStatus_Available);
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "bm_medic") == 0)
		g_bHasMedicNative = (GetFeatureStatus(FeatureType_Native, "Medic_IsClientMedic") == FeatureStatus_Available);
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "bm_medic") == 0)
		g_bHasMedicNative = false;
}

public void OnPluginStart()
{
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_PostNoCopy);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_PostNoCopy);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_iBarSpriteRef[i] = INVALID_ENT_REFERENCE;
		g_iBarMmcRef[i] = INVALID_ENT_REFERENCE;
		g_bTargetInjured[i] = false;
		g_iLastFrame[i] = 0;

		ResetViewerCache(i);
	}
}

public void OnPluginEnd()
{
	StopUpdateTimer();
	KillAllBars();
}

public void OnMapStart()
{
	// https://steamcommunity.com/sharedfiles/filedetails/?id=3630807362
	PrecacheModel("materials/animated/hpbar5s.vmt", true);
	StartUpdateTimer();
}

public void OnMapEnd()
{
	StopUpdateTimer();
	KillAllBars();
}

public void OnClientPutInServer(int client)
{
	g_iBarSpriteRef[client] = INVALID_ENT_REFERENCE;
	g_iBarMmcRef[client] = INVALID_ENT_REFERENCE;
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;

	ResetViewerCache(client);
}

public void OnClientDisconnect(int client)
{
	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;

	ResetViewerCache(client);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;

	ResetViewerCache(client);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	// PvE optimization: we only ever care about Security players.
	if (GetClientTeam(client) != TEAM_SECURITY)
		return;

	UpdateTargetBar(client);
}

static void StartUpdateTimer()
{
	StopUpdateTimer();
	g_hUpdateTimer = CreateTimer(UPDATERATE, Timer_UpdateAll, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

static void StopUpdateTimer()
{
	if (g_hUpdateTimer == INVALID_HANDLE)
		return;

	KillTimer(g_hUpdateTimer);
	g_hUpdateTimer = INVALID_HANDLE;
}

public Action Timer_UpdateAll(Handle timer, any data)
{
	// If no medic is actively holding a healthkit, remove all bars so SetTransmit doesn't cost anything.
	if (!AnyMedicHoldingHealthkit())
	{
		KillAllBars();
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		// PvE optimization: only attach/update bars for Security players.
		if (GetClientTeam(i) != TEAM_SECURITY)
		{
			if (EntRefToEntIndex(g_iBarSpriteRef[i]) != -1 || EntRefToEntIndex(g_iBarMmcRef[i]) != -1)
				KillBar(i);

			g_bTargetInjured[i] = false;
			g_iLastFrame[i] = 0;
			continue;
		}

		UpdateTargetBar(i);
	}

	return Plugin_Continue;
}

public Action Bar_SetTransmit(int entity, int client)
{
	if (GetEdictFlags(entity) & FL_EDICT_ALWAYS)
		SetEdictFlags(entity, GetEdictFlags(entity) ^ FL_EDICT_ALWAYS);

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Stop;

	int target = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (target < 1 || target > MaxClients || !IsClientInGame(target))
		return Plugin_Stop;

	// Security-only (PvE optimization)
	if (GetClientTeam(target) != TEAM_SECURITY || GetClientTeam(client) != TEAM_SECURITY)
		return Plugin_Stop;

	// Must be injured (otherwise no point sending it)
	if (!g_bTargetInjured[target])
		return Plugin_Stop;

	// Only medics, only while holding healthkit
	if (!IsClientMedic(client) || !ViewerHoldingHealthkit(client))
		return Plugin_Stop;

	// Same team only, and not for self
	if (client == target || GetClientTeam(client) != GetClientTeam(target))
		return Plugin_Stop;

	return Plugin_Continue;
}

// ----------------------------------------------------------------------
// Viewer checks
// ----------------------------------------------------------------------

static void ResetViewerCache(int client)
{
	g_fViewerNextCheck[client] = 0.0;
	g_bViewerHoldingKit[client] = false;
}

static bool IsClientMedic(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;

	if (GetClientTeam(client) != TEAM_SECURITY)
		return false;

	if (g_bHasMedicNative)
		return Medic_IsClientMedic(client);

	// Strict mode: if bm_medic isn't running, treat as non-medic.
	return false;
}

static bool ViewerHoldingHealthkit(int client)
{
	float now = GetGameTime();
	if (now < g_fViewerNextCheck[client])
		return g_bViewerHoldingKit[client];

	g_fViewerNextCheck[client] = now + 0.10;

	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		g_bViewerHoldingKit[client] = false;
		return false;
	}

	int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (wep <= MaxClients || !IsValidEntity(wep))
	{
		g_bViewerHoldingKit[client] = false;
		return false;
	}

	char cls[64];
	GetEdictClassname(wep, cls, sizeof(cls));
	g_bViewerHoldingKit[client] = (StrContains(cls, "weapon_healthkit", false) != -1);

	return g_bViewerHoldingKit[client];
}

static bool AnyMedicHoldingHealthkit()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		if (!IsClientMedic(i))
			continue;

		if (ViewerHoldingHealthkit(i))
			return true;
	}

	return false;
}

// ----------------------------------------------------------------------
// Bars
// ----------------------------------------------------------------------

static void KillAllBars()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		KillBar(i);
		g_bTargetInjured[i] = false;
		g_iLastFrame[i] = 0;
	}
}

static void KillBar(int target)
{
	int spr = EntRefToEntIndex(g_iBarSpriteRef[target]);
	if (spr != -1)
	{
		SDKUnhook(spr, SDKHook_SetTransmit, Bar_SetTransmit);
		AcceptEntityInput(spr, "KillHierarchy");
	}

	g_iBarSpriteRef[target] = INVALID_ENT_REFERENCE;
	g_iBarMmcRef[target] = INVALID_ENT_REFERENCE;
	g_iLastFrame[target] = 0;
}

static void EnsureBar(int target)
{
	if (target < 1 || target > MaxClients || !IsClientInGame(target))
		return;

	int spr = EntRefToEntIndex(g_iBarSpriteRef[target]);
	if (spr != -1)
		return;

	char tname[32];
	FormatEx(tname, sizeof(tname), "hpbar_t_%d", target);

	spr = CreateEntityByName("env_sprite");
	if (spr == -1)
		return;

	g_iBarSpriteRef[target] = EntIndexToEntRef(spr);

	DispatchKeyValue(spr, "targetname", tname);
	DispatchKeyValue(spr, "model", "animated/hpbar5s.vmt");
	DispatchKeyValue(spr, "scale", "0.2");
	DispatchKeyValue(spr, "rendermode", "7");
	DispatchKeyValue(spr, "rendercolor", "255 255 255");
	DispatchKeyValue(spr, "renderfx", "0");
	DispatchKeyValue(spr, "disableshadows", "1");
	DispatchKeyValue(spr, "disableshadowdepth", "1");

	DispatchSpawn(spr);
	ActivateEntity(spr);
	AcceptEntityInput(spr, "DisableShadow");

	SetEntPropEnt(spr, Prop_Send, "m_hOwnerEntity", target);

	// Parent to a stance-following attachment.
	// Use "eyes" (usually centered). "head" can be offset on some Ins models.
	SetVariantString("!activator");
	AcceptEntityInput(spr, "SetParent", target, spr, 0);

	SetVariantString("eyes");
	if (!AcceptEntityInput(spr, "SetParentAttachment", target, spr, 0))
	{
		SetVariantString("head");
		AcceptEntityInput(spr, "SetParentAttachment", target, spr, 0);
	}

	// Local offset from the attachment. BAR_Z_OFF
	char local[32];
	FormatEx(local, sizeof(local), "-5.0 0 %.1f", BAR_Z_OFF);
	SetVariantString(local);
	AcceptEntityInput(spr, "SetLocalOrigin");

	AcceptEntityInput(spr, "HideSprite");

	SDKHook(spr, SDKHook_SetTransmit, Bar_SetTransmit);

	// MMC (frame control)
	int mmc = CreateEntityByName("material_modify_control");
	if (mmc == -1)
	{
		KillBar(target);
		return;
	}

	g_iBarMmcRef[target] = EntIndexToEntRef(mmc);

	DispatchKeyValue(mmc, "materialName", "animated/hpbar5s.vmt");
	DispatchKeyValue(mmc, "materialVar", "$frame");

	DispatchSpawn(mmc);
	ActivateEntity(mmc);

	SetVariantString("!activator");
	AcceptEntityInput(mmc, "SetParent", spr, mmc, 0);
}

static int GetBarFrameFromHP(int hp)
{
	if (hp < 1)
		hp = 1;
	else if (hp > HP_FULL)
		hp = HP_FULL;

	// 20 frames total; use floor so only exactly 100hp is truly "full frame".
	float frac = float(hp) / float(HP_FULL);
	int frame = RoundToFloor(frac * 20.0);
	if (frame < 1)
		frame = 1;
	else if (frame > 20)
		frame = 20;

	return frame;
}

static void SetBarFrame(int target, int frame)
{
	if (g_iLastFrame[target] == frame)
		return;

	int mmc = EntRefToEntIndex(g_iBarMmcRef[target]);
	if (mmc == -1)
		return;

	g_iLastFrame[target] = frame;

	char strFrame[4];
	IntToString(frame, strFrame, sizeof(strFrame));

	char vstring[32];
	FormatEx(vstring, sizeof(vstring), "%s -1 0 0", strFrame);

	SetVariantString(vstring);
	AcceptEntityInput(mmc, "StartAnimSequence");
}

static void UpdateTargetBar(int target)
{
	if (target < 1 || target > MaxClients || !IsClientInGame(target))
		return;

	// PvE optimization: only Security teammates get bars.
	if (GetClientTeam(target) != TEAM_SECURITY)
	{
		if (EntRefToEntIndex(g_iBarSpriteRef[target]) != -1 || EntRefToEntIndex(g_iBarMmcRef[target]) != -1)
			KillBar(target);

		g_bTargetInjured[target] = false;
		return;
	}

	if (!IsPlayerAlive(target))
	{
		if (EntRefToEntIndex(g_iBarSpriteRef[target]) != -1 || EntRefToEntIndex(g_iBarMmcRef[target]) != -1)
			KillBar(target);

		g_bTargetInjured[target] = false;
		return;
	}

	int hp = GetClientHealth(target);

	// Only show bars for teammates who are NOT full HP
	if (hp >= HP_FULL)
	{
		if (EntRefToEntIndex(g_iBarSpriteRef[target]) != -1 || EntRefToEntIndex(g_iBarMmcRef[target]) != -1)
			KillBar(target);

		g_bTargetInjured[target] = false;
		return;
	}

	g_bTargetInjured[target] = true;

	EnsureBar(target);

	int spr = EntRefToEntIndex(g_iBarSpriteRef[target]);
	if (spr == -1)
		return;

	AcceptEntityInput(spr, "ShowSprite");
	SetBarFrame(target, GetBarFrameFromHP(hp));
}
