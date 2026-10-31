#if defined _bm_supply_included
 #endinput
#endif
#define _bm_supply_included

#include <sourcemod>

native int BMProps_GetInvestedSupply(int client);
native void BMProps_SetTotalSupply(int client, int total);

public SharedPlugin __pl_bm_supply = {
	name = "bm_props",
	file = "props.smx",
	required = 0
};

public void __pl_bm_supply_SetNTVOptional() {
	MarkNativeAsOptional("BMProps_GetInvestedSupply");
	MarkNativeAsOptional("BMProps_SetTotalSupply");
}

stock bool BMSupply_HasProps() {
	bool available = GetFeatureStatus(FeatureType_Native, "BMProps_GetInvestedSupply") == FeatureStatus_Available
		&& GetFeatureStatus(FeatureType_Native, "BMProps_SetTotalSupply") == FeatureStatus_Available;
	if (!available && LibraryExists("bm_props"))
		ThrowError("Supply accounting requires props v3.82.8 or newer with supply natives available.");
	return available;
}

// Received supply is the inventory budget; invested supply remains owned by the player.
stock int BMSupply_GetTotal(int client) {
	int invested = BMSupply_HasProps() ? BMProps_GetInvestedSupply(client) : 0;
	return GetEntProp(client, Prop_Send, "m_nRecievedTokens") + invested;
}

// Absolute totals include invested supply. Keep available supply in sync without selling equipment.
stock void BMSupply_SetTotal(int client, int total) {
	if (total < 0)
		total = 0;
	if (BMSupply_HasProps()) {
		BMProps_SetTotalSupply(client, total);
		return;
	}
	int available = GetEntProp(client, Prop_Send, "m_nAvailableTokens")
		+ total - GetEntProp(client, Prop_Send, "m_nRecievedTokens");
	if (available < 0)
		available = 0;
	if (available > total)
		available = total;
	SetEntProp(client, Prop_Send, "m_nRecievedTokens", total);
	SetEntProp(client, Prop_Send, "m_nAvailableTokens", available);
}
