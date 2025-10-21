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
			AcceptEntityInput(e, "Kill");	// preferred, lets map I/O clean up
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
