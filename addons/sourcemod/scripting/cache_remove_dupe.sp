#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = {
	name = "cache_remove_dupe",
	author = "Nullifidian",
	description = "It removes duplicate caches from a map.",
	version = "1.0"
};

public void OnPluginStart() {
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
}

public Action Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
	int		iEnt = MaxClients + 1,
			iEnt2;
		
	float	vEnt[3],
			vEnt2[3];

	while ((iEnt = FindEntityByClassname(iEnt, "obj_weapon_cache")) != -1) {
		GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vEnt);
		iEnt2 = iEnt + 1;
		while ((iEnt2 = FindEntityByClassname(iEnt2, "obj_weapon_cache")) != -1) {
			if (iEnt == iEnt2) {
				continue;
			}
			
			GetEntPropVector(iEnt2, Prop_Data, "m_vecAbsOrigin", vEnt2);

			if (GetVectorDistance(vEnt, vEnt2) <= 40.0) {
				RemoveEntity(iEnt);
				TeleportEntity(iEnt2, vEnt, NULL_VECTOR, NULL_VECTOR);
				break;
			}
		}
	}
}