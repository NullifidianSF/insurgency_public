#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

bool g_bLateLoad;

public Plugin myinfo = {
	name		= "molotov",
	author		= "Nullifidian & Jared Ballou",
	description	= "Molotov that lay on the ground can explode from damage",
	version		= "1.3",
	url			= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	if (g_bLateLoad) {
		for (int i = MaxClients + 1; i <= 2048; i++) {
			if (!IsValidEntity(i)) {
				continue;
			}
			char classname[32];
			GetEdictClassname(i, classname, sizeof(classname));
			if (strcmp(classname, "weapon_molotov") == 0) {
				SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
			}
		}
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i)) {
				SDKHook(i, SDKHook_WeaponEquip, Hook_WeaponEquip);
			}
		}
	}
}

public void OnClientPostAdminCheck(int client) {
	if (client > 0 && !IsFakeClient(client)) {
		SDKHook(client, SDKHook_WeaponEquip, Hook_WeaponEquip);
	}
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (strcmp(classname, "weapon_molotov") == 0) {
		SDKHook(entity, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup) {
	if (attacker > MaxClients || damage <= 0.0) {
		return Plugin_Continue;
	}

	SDKUnhook(victim, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	
	const float fTime = 2.0;
	DataPack hDatapack;
	CreateDataTimer(fTime, Timer_Boom, hDatapack);
	hDatapack.WriteCell(EntIndexToEntRef(victim));
	hDatapack.WriteCell(EntIndexToEntRef(attacker));
	IgniteEntity(victim, fTime);

	return Plugin_Continue;
}

//seen in "Suicide Bombers" plugin by Jared Ballou https://github.com/jaredballou/insurgency-sourcemod/blob/master/scripting/disabled/bsuicide_bomb_redux.sp
Action Timer_Boom(Handle timer, DataPack hDatapack) {
	hDatapack.Reset();
	int	victim = EntRefToEntIndex(hDatapack.ReadCell()),
		attacker = EntRefToEntIndex(hDatapack.ReadCell());

	if (victim == INVALID_ENT_REFERENCE || !IsValidEntity(victim)) {
		return Plugin_Stop;
	}

	GoBoom(victim, attacker);

	return Plugin_Stop;
}

public Action Hook_WeaponEquip(int client, int weapon) {
	char classname[32];
	GetEdictClassname(weapon, classname, sizeof(classname));
	if (strcmp(classname, "weapon_molotov") == 0) {
		int ent = GetEntPropEnt(weapon, Prop_Data, "m_hEffectEntity");
		if (IsValidEntity(ent)) {
			//maybe need to check for IsValidEntity(weapon) here
			GoBoom(weapon, client);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

void GoBoom(int victim, int attacker) {
	float vecOrigin[3];
	GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += 1.0;

	int iGrenade = CreateEntityByName("grenade_molotov");
	if (IsValidEntity(iGrenade)) {
		RemoveEntity(victim);
		SetEntPropEnt(iGrenade, Prop_Data, "m_hOwnerEntity", (attacker != INVALID_ENT_REFERENCE && IsValidEntity(attacker) && attacker > 0) ? attacker : -1);
		//SetEntProp(iGrenade, Prop_Data, "m_nNextThinkTick", 1); //for smoke
		SetEntProp(iGrenade, Prop_Data, "m_takedamage", 2);
		SetEntProp(iGrenade, Prop_Data, "m_iHealth", 1);
		SetEntProp(iGrenade, Prop_Data, "m_usSolidFlags", 0);
		SetEntProp(iGrenade, Prop_Data, "m_nSolidType", 0);
		TeleportEntity(iGrenade, vecOrigin, NULL_VECTOR, NULL_VECTOR);

		if (DispatchSpawn(iGrenade)) {
			char sBuffer[32];
			int iPointHurt = CreateEntityByName("point_hurt");
			if (IsValidEntity(iPointHurt)) {
				DispatchKeyValue(iGrenade, "targetname", "hurtme");
				DispatchKeyValue(iPointHurt, "DamageTarget", "hurtme");

				IntToString(100, sBuffer, sizeof(sBuffer));
				DispatchKeyValue(iPointHurt, "Damage", sBuffer);

				IntToString(DMG_BLAST, sBuffer, sizeof(sBuffer));
				DispatchKeyValue(iPointHurt, "DamageType", sBuffer);

				DispatchKeyValue(iPointHurt, "classname", "weapon_molotov");
				DispatchSpawn(iPointHurt);

				AcceptEntityInput(iPointHurt, "Hurt", (attacker != INVALID_ENT_REFERENCE && IsValidEntity(attacker) && attacker > 0) ? attacker : -1);
				DispatchKeyValue(iPointHurt, "classname", "point_hurt");
				DispatchKeyValue(iGrenade, "targetname", "donthurtme");
				RemoveEntity(iPointHurt);
			}
		}
	}
}