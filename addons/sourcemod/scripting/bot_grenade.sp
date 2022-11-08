#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

ConVar	g_cMin,
		g_cMax;

float	g_fMin,
		g_fMax;

public Plugin myinfo = {
	name = "bot_grenade",
	author = "Nullifidian",
	description = "Make bots less accurate with grenades by changing grenade velocity",
	version = "1.7",
	url = ""
};

public void OnPluginStart() {
	g_cMin = CreateConVar("sm_botgrenade_min", "0.7", "Min RNG value for grenade velocity multiplier");
	g_fMin = g_cMin.FloatValue;
	g_cMin.AddChangeHook(OnConVarChanged);

	g_cMax = CreateConVar("sm_botgrenade_max", "1.3", "Max RNG value for grenade velocity multiplier");
	g_fMax = g_cMax.FloatValue;
	g_cMax.AddChangeHook(OnConVarChanged);

	HookEvent("grenade_thrown", Event_GrenadeThrown);

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public Action Event_GrenadeThrown(Event event, char[] name, bool dontBroadcast) {
	int	client = GetClientOfUserId(GetEventInt(event, "userid")),
		ent = GetEventInt(event, "entityid");

	if (ent == -1 || client < 1 || !IsClientInGame(client) || !IsFakeClient(client)) {
		return Plugin_Continue;
	}

	RequestFrame(Frame_SetGrenadeVel, EntIndexToEntRef(ent));
	return Plugin_Continue;
}

void Frame_SetGrenadeVel(int entRef) {
	int ent = EntRefToEntIndex(entRef);
	if (ent == INVALID_ENT_REFERENCE || !IsValidEdict(ent)) {
		return;
	}

	float fVelocity[3];
	GetEntPropVector(ent, Prop_Send, "m_vecVelocity", fVelocity);

	float fRandom = GetRandomFloat(g_fMin, g_fMax);

	fVelocity[0] *= fRandom;
	fVelocity[1] *= fRandom;
	fVelocity[2] *= fRandom;

	TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, fVelocity);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cMin) {
		g_fMin = g_cMin.FloatValue;
	}
	else if (convar == g_cMax) {
		g_fMax = g_cMax.FloatValue;
	}
}