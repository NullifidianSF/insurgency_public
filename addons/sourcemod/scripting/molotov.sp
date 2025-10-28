#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

bool g_bLateLoad;

public Plugin myinfo = {
	name		= "molotov",
	author		= "Nullifidian",
	description	= "Molotovs lying on the ground can explode from damage",
	version		= "1.5",
	url			= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	if (g_bLateLoad) {
		int maxEnts = GetMaxEntities();
		for (int i = MaxClients + 1; i < maxEnts; i++) {
			if (!IsValidEntity(i))
				continue;

			char classname[32];
			GetEntityClassname(i, classname, sizeof(classname));
			if (StrEqual(classname, "weapon_molotov", false))
				SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}

		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i))
				SDKHook(i, SDKHook_WeaponEquip, Hook_WeaponEquip);
		}
	}
}

public void OnClientPostAdminCheck(int client) {
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
		SDKHook(client, SDKHook_WeaponEquip, Hook_WeaponEquip);
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "weapon_molotov", false)) {
		SDKHook(entity, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

int ResolveAttacker(int attacker, int inflictor) {
	if (1 <= attacker && attacker <= MaxClients && IsClientInGame(attacker))
		return attacker;

	if (IsValidEntity(attacker)) {
		int own = GetEntPropEnt(attacker, Prop_Data, "m_hOwnerEntity");
		if (1 <= own && own <= MaxClients && IsClientInGame(own))
			return own;
	}

	if (IsValidEntity(inflictor)) {
		int own2 = GetEntPropEnt(inflictor, Prop_Data, "m_hOwnerEntity");
		if (1 <= own2 && own2 <= MaxClients && IsClientInGame(own2))
			return own2;
	}

	return -1;
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup) {
	if (damage <= 0.0)
		return Plugin_Continue;

	SDKUnhook(victim, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

	const float fTime = 2.0;

	DataPack pack;
	CreateDataTimer(fTime, Timer_Boom, pack);
	pack.WriteCell(EntIndexToEntRef(victim));

	int credited = ResolveAttacker(attacker, inflictor);
	pack.WriteCell( (credited > 0) ? EntIndexToEntRef(credited) : INVALID_ENT_REFERENCE );

	IgniteEntity(victim, fTime);

	return Plugin_Continue;
}

public Action Hook_WeaponEquip(int client, int weapon) {
	if (!IsValidEntity(weapon) || !IsClientInGame(client))
		return Plugin_Continue;

	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));
	if (!StrEqual(classname, "weapon_molotov", false))
		return Plugin_Continue;

	if (HasEntProp(weapon, Prop_Data, "m_hEffectEntity")) {
		int fx = GetEntPropEnt(weapon, Prop_Data, "m_hEffectEntity");
		if (IsValidEntity(fx)) {
			GoBoom(weapon, client);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action Timer_Boom(Handle timer, DataPack pack) {
	pack.Reset();
	int victimRef = pack.ReadCell();
	int attackerRef = pack.ReadCell();

	int victim = EntRefToEntIndex(victimRef);
	int attacker = EntRefToEntIndex(attackerRef);

	if (victim <= 0 || !IsValidEntity(victim))
		return Plugin_Stop;

	GoBoom(victim, attacker);
	return Plugin_Stop;
}

void GoBoom(int victim, int attacker) {
	if (!IsValidEntity(victim))
		return;

	float origin[3];
	GetEntPropVector(victim, Prop_Send, "m_vecOrigin", origin);
	origin[2] += 1.0;

	int owner = -1;
	if (1 <= attacker && attacker <= MaxClients && IsClientInGame(attacker))
		owner = attacker;
	else {
		int own = GetEntPropEnt(victim, Prop_Data, "m_hOwnerEntity");
		if (1 <= own && own <= MaxClients && IsClientInGame(own))
			owner = own;
	}

	int molly = CreateEntityByName("grenade_molotov");
	if (!IsValidEntity(molly))
		return;

	SafeKillIdx(victim);

	SetEntPropEnt(molly, Prop_Data, "m_hOwnerEntity", (owner > 0) ? owner : -1);
	SetEntProp(molly,   Prop_Data, "m_takedamage", 2);
	SetEntProp(molly,   Prop_Data, "m_iHealth", 1);
	SetEntProp(molly,   Prop_Data, "m_usSolidFlags", 0);
	SetEntProp(molly,   Prop_Data, "m_nSolidType", 0);
	TeleportEntity(molly, origin, NULL_VECTOR, NULL_VECTOR);

	if (!DispatchSpawn(molly)) {
		SafeKillIdx(molly);
		return;
	}

	ActivateEntity(molly);

	int hurt = CreateEntityByName("point_hurt");
	if (!IsValidEntity(hurt))
		return;

	DispatchKeyValue(molly, "targetname", "hurtme");
	DispatchKeyValue(hurt, "DamageTarget", "hurtme");
	DispatchKeyValue(hurt, "Damage", "100");
	DispatchKeyValue(hurt, "DamageType", "64"); // DMG_BLAST

	DispatchSpawn(hurt);

	AcceptEntityInput(hurt, "Hurt", (owner > 0) ? owner : -1);

	DispatchKeyValue(molly, "targetname", "donthurtme");
	SafeKillIdx(hurt);
}

stock void SafeKillIdx(int ent) {
	if (ent <= MaxClients) return;
	int ref = EntIndexToEntRef(ent);
	if (ref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, ref);
}

stock void SafeKillRef(int entref) {
	if (entref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, entref);
}

stock void NF_KillEntity(any entref) {
	int ent = EntRefToEntIndex(entref);
	if (ent <= MaxClients || !IsValidEntity(ent)) return;

	if (!AcceptEntityInput(ent, "Kill"))
		RemoveEntity(ent);
}
