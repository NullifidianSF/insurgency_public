#pragma semicolon 1
#pragma newdecls required

#define PF_BUYZONE	(1 << 7)

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo = {
	name		= "bot_dropsecondary",
	author		= "Nullifidian",
	description	= "Bots drop secondary weapon on death if it is not the weapon they are holding",
	version		= "1.3"
};

static const float VEC_ZERO[3] = { 0.0, 0.0, 0.0 };

public void OnPluginStart() {
	HookEvent("player_death", Event_PlayerDeath_Pre, EventHookMode_Pre);
}

public Action Event_PlayerDeath_Pre(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int victim = GetClientOfUserId(userid);
	if (victim < 1 || !IsClientInGame(victim) || !IsFakeClient(victim))
		return Plugin_Continue;

	int flags = GetEntProp(victim, Prop_Send, "m_iPlayerFlags");
	if ((flags & PF_BUYZONE) != 0)
		return Plugin_Continue;

	int activeWeapon = GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon");
	if (activeWeapon <= 0 || !IsValidEntity(activeWeapon))
		return Plugin_Continue;

	int secondary = GetPlayerWeaponSlot(victim, 1);
	if (secondary <= 0 || !IsValidEntity(secondary))
		return Plugin_Continue;

	if (activeWeapon == secondary)
		return Plugin_Continue;

	if (GetEntPropEnt(secondary, Prop_Send, "m_hOwnerEntity") != victim)
		return Plugin_Continue;

	if (!SDKHooks_DropWeapon(victim, secondary, NULL_VECTOR, NULL_VECTOR))
		return Plugin_Continue;

	int ref = EntIndexToEntRef(secondary);
	RequestFrame(FreezeDropped, ref);

	return Plugin_Continue;
}

public void FreezeDropped(int ref) {
	int ent = EntRefToEntIndex(ref);
	if (ent <= 0 || !IsValidEntity(ent))
		return;

	TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, VEC_ZERO);
	SetEntPropVector(ent, Prop_Data, "m_vecAngVelocity", VEC_ZERO);
}