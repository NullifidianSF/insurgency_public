#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
	name		= "[INS] cache_remove_dupe",
	author		= "GPT-5",
	description	= "Removes every obj_weapon_cache that lacks m_iszControlPoint (single scan on round_start)",
	version		= "1.0",
	url			= ""
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Defer one frame so any round_start-spawned caches are fully created.
	RequestFrame(Frame_SweepOnce);
	return Plugin_Continue;
}

void Frame_SweepOnce(any data)
{
	SweepAndCullUnlinkedCaches();
}

static void SweepAndCullUnlinkedCaches()
{
	int e = -1;
	while ((e = FindEntityByClassname(e, "obj_weapon_cache")) != -1)
	{
		if (!IsValidEntity(e)) continue;

		if (!CacheHasCPLink(e))
		{
			SafeKillIdx(e);
		}
	}
}

static bool CacheHasCPLink(int ent)
{
	char buf[64]; buf[0] = '\0';

	if (HasEntProp(ent, Prop_Data, "m_iszControlPoint"))
		GetEntPropString(ent, Prop_Data, "m_iszControlPoint", buf, sizeof buf);
	else if (HasEntProp(ent, Prop_Send, "m_iszControlPoint"))
		GetEntPropString(ent, Prop_Send, "m_iszControlPoint", buf, sizeof buf);

	return (buf[0] != '\0');
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
