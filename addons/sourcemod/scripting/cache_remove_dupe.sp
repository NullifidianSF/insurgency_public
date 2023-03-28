#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = {
	name = "cache_remove_dupe",
	author = "Nullifidian",
	description = "It removes duplicate caches from a map.",
	version = "1.2"
};

public void OnPluginStart() {
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
}

public Action Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
	FindRemoveCache();
}

void FindRemoveCache() {
	int		iEnt = MaxClients + 1,
			iEnt2 = MaxClients + 1;

	bool	bRemoved = false;
		
	float	vEnt[3],
			vEnt2[3];

	while ((iEnt = FindEntityByClassname(iEnt, "obj_weapon_cache")) != -1) {
		GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vEnt);
		while ((iEnt2 = FindEntityByClassname(iEnt2, "obj_weapon_cache")) != -1) {
			if (iEnt == iEnt2) {
				continue;
			}

			GetEntPropVector(iEnt2, Prop_Data, "m_vecAbsOrigin", vEnt2);
			if (GetVectorDistance(vEnt, vEnt2) > 40.0) {
				continue;
			}
			
			RemoveEntity(iEnt);
			TeleportEntity(iEnt2, vEnt, NULL_VECTOR, NULL_VECTOR);
			bRemoved = true;
			break;
		}

		if (bRemoved) {
			RequestFrame(FindRemoveCache);
			break;
		}
	}
}