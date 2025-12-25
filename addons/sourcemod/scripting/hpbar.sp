#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

native bool Medic_IsClientMedic(int client);

public Plugin myinfo =
{
	name		= "hpbar",
	author		= "Pericles (updated by ChatGPT)",
	description	= "Shows health bars over injured teammates (Security only), visible only to medics while holding the healthkit or defib.",
	version		= "1.0.2",
	url			= "https://forums.alliedmods.net/showthread.php?t=312223"
};

static const int	TEAM_SECURITY	= 2;
static const int	HP_FULL			= 100;	// Insurgency players are effectively 100hp in normal play.

// Attachment-local offsets (parented to "eyes").
// Tip: to push the bar back so it's not in front of the eyes, set BAR_X_OFF to a small negative (e.g. -6.0).
static const float	BAR_X_OFF		= -5.0;	// negative = further back
static const float	BAR_Y_OFF		= 0.0;	// left/right
static const float	BAR_Z_OFF		= 10.0;	// up/down

static const float	UPDATERATE		= 0.50;	// seconds

Handle	g_hUpdateTimer = INVALID_HANDLE;

int		g_iBarSpriteRef[MAXPLAYERS + 1];
int		g_iBarMmcRef[MAXPLAYERS + 1];
bool	g_bTargetInjured[MAXPLAYERS + 1];
int		g_iLastFrame[MAXPLAYERS + 1];

bool	g_bHasMedicNative;
bool	g_bViewerHoldingKit[MAXPLAYERS + 1];

bool	g_bLateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
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

static void RefreshMedicNative()
{
	g_bHasMedicNative = (GetFeatureStatus(FeatureType_Native, "Medic_IsClientMedic") == FeatureStatus_Available);
}

public void OnPluginStart()
{
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_PostNoCopy);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_PostNoCopy);
	HookEvent("weapon_deploy", Event_WeaponDeploy, EventHookMode_Post);

	RefreshMedicNative();

	for (int i = 1; i <= MaxClients; i++)
	{
		g_iBarSpriteRef[i] = INVALID_ENT_REFERENCE;
		g_iBarMmcRef[i] = INVALID_ENT_REFERENCE;
		g_bTargetInjured[i] = false;
		g_iLastFrame[i] = 0;
		g_bViewerHoldingKit[i] = false;
	}

	if (g_bLateLoad)
		RequestFrame(Frame_LateLoadSync);
}

public void OnPluginEnd()
{
	StopUpdateTimer();
	KillAllBars();
}

public void OnMapStart()
{
	PrecacheModel("materials/animated/hpbar5s.vmt", true);
	StartUpdateTimer();
}

public void OnMapEnd()
{
	StopUpdateTimer();
	KillAllBars();
}

public void OnClientDisconnect(int client)
{
	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;
	g_bViewerHoldingKit[client] = false;
}

public void Frame_LateLoadSync(any data)
{
	RefreshMedicNative();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		UpdateViewerHoldingKitNow(i);

		if (IsPlayerAlive(i) && GetClientTeam(i) == TEAM_SECURITY && GetClientHealth(i) < 100)
			g_bTargetInjured[i] = true;
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;
	g_bViewerHoldingKit[client] = false;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;
	g_bViewerHoldingKit[client] = false;

	if (!IsFakeClient(client))
		RequestFrame(Frame_SpawnSync, event.GetInt("userid"));
}

public void Frame_SpawnSync(any userid)
{
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	UpdateViewerHoldingKitNow(client);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	KillBar(client);
	g_bTargetInjured[client] = false;
	g_iLastFrame[client] = 0;
	g_bViewerHoldingKit[client] = false;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	if (GetClientTeam(client) != TEAM_SECURITY)
		return;

	UpdateTargetBar(client);
}

public void Event_WeaponDeploy(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	UpdateViewerHoldingKitNow(client);
}

static void UpdateViewerHoldingKitNow(int client)
{
	g_bViewerHoldingKit[client] = false;

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return;

	if (!IsClientMedic(client))
		return;

	int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (wep <= MaxClients || !IsValidEntity(wep))
		return;

	char cls[64];
	GetEdictClassname(wep, cls, sizeof(cls));

	if (StrContains(cls, "weapon_healthkit", false) != -1 || StrContains(cls, "weapon_defib", false) != -1)
		g_bViewerHoldingKit[client] = true;
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
	if (!AnyMedicHoldingKit())
	{
		KillAllBars();
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (GetClientTeam(i) != TEAM_SECURITY)
		{
			if (EntRefToEntIndex(g_iBarSpriteRef[i]) != -1)
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

	if (GetClientTeam(target) != TEAM_SECURITY || GetClientTeam(client) != TEAM_SECURITY)
		return Plugin_Stop;

	if (!g_bTargetInjured[target])
		return Plugin_Stop;

	if (!IsClientMedic(client) || !g_bViewerHoldingKit[client])
		return Plugin_Stop;

	if (client == target)
		return Plugin_Stop;

	return Plugin_Continue;
}

// ----------------------------------------------------------------------
// Viewer checks
// ----------------------------------------------------------------------

static bool IsClientMedic(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;

	if (GetClientTeam(client) != TEAM_SECURITY)
		return false;

	if (g_bHasMedicNative)
		return Medic_IsClientMedic(client);

	return false;
}

static bool AnyMedicHoldingKit()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		if (GetClientTeam(i) != TEAM_SECURITY)
			continue;

		if (!IsClientMedic(i))
			continue;

		if (g_bViewerHoldingKit[i])
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
	SetVariantString("!activator");
	AcceptEntityInput(spr, "SetParent", target, spr, 0);

	SetVariantString("eyes");
	if (!AcceptEntityInput(spr, "SetParentAttachment", target, spr, 0))
	{
		SetVariantString("head");
		AcceptEntityInput(spr, "SetParentAttachment", target, spr, 0);
	}

	char local[48];
	FormatEx(local, sizeof(local), "%.1f %.1f %.1f", BAR_X_OFF, BAR_Y_OFF, BAR_Z_OFF);
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

	if (GetClientTeam(target) != TEAM_SECURITY || !IsPlayerAlive(target))
	{
		if (EntRefToEntIndex(g_iBarSpriteRef[target]) != -1)
			KillBar(target);

		g_bTargetInjured[target] = false;
		return;
	}

	int hp = GetClientHealth(target);
	if (hp >= HP_FULL)
	{
		if (EntRefToEntIndex(g_iBarSpriteRef[target]) != -1)
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
