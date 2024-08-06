#pragma semicolon 1
#pragma newdecls required

#define INS_PL_BUYZONE (1 << 7)

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo = {
	name = "bot_dropsecondary",
	author = "Nullifidian",
	description = "Bots drop secondary weapon on death if it is not the weapon they are holding",
	version = "1.2"
};

public void OnPluginStart() {
	HookEvent("player_death", Event_PlayerDeath_Pre, EventHookMode_Pre);
}

public Action Event_PlayerDeath_Pre(Event event, const char[] name, bool dontBroadcast) {
	// Get the victim's client index
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	// Stop the code if the victim is not in the game or not a bot
	if (victim < 1 || !IsClientInGame(victim) || !IsFakeClient(victim)) {
		return Plugin_Continue;
	}

	// Stop the code if the victim at buy zone.
	if (GetEntProp(victim, Prop_Send, "m_iPlayerFlags") & INS_PL_BUYZONE) {
		return Plugin_Continue;
	}

	// Get the victim's active weapon entity index
	int activeWeapon = GetEntPropEnt(victim, Prop_Data, "m_hActiveWeapon");
	if (activeWeapon <= 0 || !IsValidEntity(activeWeapon)) {
		return Plugin_Continue;
	}

	// Get the victim's secondary weapon entity index
	int secondary = GetPlayerWeaponSlot(victim, 1);
	if (secondary <= 0 || !IsValidEntity(secondary)) {
		return Plugin_Continue;
	}

	// Stop the code if the active weapon is the secondary weapon
	if (activeWeapon == secondary) {
		return Plugin_Continue;
	}

	// Ensure the secondary weapon is still owned by the victim
	if (GetEntPropEnt(secondary, Prop_Data, "m_hOwnerEntity") != victim) {
		return Plugin_Continue;
	}

	// Drop the secondary weapon
	SDKHooks_DropWeapon(victim, secondary, NULL_VECTOR, NULL_VECTOR);

	// Prevent the physics model from sliding on the ground
	SetEntProp(secondary, Prop_Data, "m_MoveCollide", true);

	return Plugin_Continue;
}