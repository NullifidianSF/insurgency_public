#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#define GAMEDATA_FILE "insurgency-bm.games"
GameData g_hGameData = null;
DynamicDetour g_hDrawSpeedDetour = null;
DynamicDetour g_hHolsterSpeedDetour = null;
Handle g_hGetDrawSpeedModifier = null;
Handle g_hGetHolsterSpeedModifier = null;
ConVar g_cvEnabled = null;
ConVar g_cvMaximumModifier = null;

bool g_bDiagnosticBypass = false;
bool g_bDiagnosticNoCount = false;
int g_iBlockedDrawModifiers = 0;
int g_iBlockedHolsterModifiers = 0;

public Plugin myinfo = {
	name = "Weapon Switch Speed Fix",
	author = "Nullifidian & Codex",
	description = "Caps stacked draw and holster speed modifiers across a weapon switch",
	version = "1.4.1",
	url = ""
};

public void OnPluginStart() {
	if (GetFeatureStatus(FeatureType_Native, "DynamicDetour.DynamicDetour") != FeatureStatus_Available
		|| GetFeatureStatus(FeatureType_Native, "DHookSetup.SetFromConf") != FeatureStatus_Available
		|| GetFeatureStatus(FeatureType_Native, "DHookSetup.AddParam") != FeatureStatus_Available)
		SetFailState("[Weapon Switch Speed Fix] DHooks with DynamicDetour support is required.");

	g_hGameData = LoadGameConfigFile(GAMEDATA_FILE);
	if (g_hGameData == null)
		SetFailState("[Weapon Switch Speed Fix] Missing gamedata: addons/sourcemod/gamedata/%s.txt", GAMEDATA_FILE);

	g_hGetDrawSpeedModifier = CreateWeaponPairSDKCall("CINSWeapon::GetDrawSpeedModifier");
	g_hGetHolsterSpeedModifier = CreateWeaponPairSDKCall("CINSWeapon::GetHolsterSpeedModifier");

	g_cvEnabled = CreateConVar("sm_weapon_switch_speed_fix", "1",
		"Cap stacked draw and holster speed modifiers across a weapon switch. 0 = disabled, 1 = enabled.",
		_, true, 0.0, true, 1.0);
	g_cvMaximumModifier = CreateConVar("sm_weapon_switch_speed_max_modifier", "1.5",
		"Highest permitted native draw or holster speed multiplier. 1.50 keeps one theater speed upgrade and blocks x2.25 stacking.",
		_, true, 1.0, true, 10.0);
	RegAdminCmd("sm_weapon_switch_speed_info", Command_WeaponSwitchSpeedInfo, ADMFLAG_ROOT,
		"Display duplicate weapon switch-speed modifiers and fix status");
	RegAdminCmd("sm_weapon_switch_speed_values", Command_WeaponSwitchSpeedValues, ADMFLAG_ROOT,
		"Display native draw and holster speed multipliers for every carried weapon pair");
	AutoExecConfig(true, "weapon_switch_speed_fix");
	CreateModifierDetours();
}

public void OnPluginEnd() {
	if (g_hDrawSpeedDetour != null)
		g_hDrawSpeedDetour.Disable(Hook_Post, Detour_DrawSpeedModifier_Post);
	if (g_hHolsterSpeedDetour != null)
		g_hHolsterSpeedDetour.Disable(Hook_Post, Detour_HolsterSpeedModifier_Post);

	delete g_hDrawSpeedDetour;
	delete g_hHolsterSpeedDetour;
	delete g_hGetDrawSpeedModifier;
	delete g_hGetHolsterSpeedModifier;
	delete g_hGameData;
}

void CreateModifierDetours() {
	g_hDrawSpeedDetour = CreateWeaponPairDetour("CINSWeapon::GetDrawSpeedModifier");
	if (!g_hDrawSpeedDetour.Enable(Hook_Post, Detour_DrawSpeedModifier_Post))
		SetFailState("[Weapon Switch Speed Fix] Could not enable GetDrawSpeedModifier detour.");

	g_hHolsterSpeedDetour = CreateWeaponPairDetour("CINSWeapon::GetHolsterSpeedModifier");
	if (!g_hHolsterSpeedDetour.Enable(Hook_Post, Detour_HolsterSpeedModifier_Post))
		SetFailState("[Weapon Switch Speed Fix] Could not enable GetHolsterSpeedModifier detour.");
}

DynamicDetour CreateWeaponPairDetour(const char[] signature) {
	DynamicDetour detour = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Float, ThisPointer_Address);
	if (detour == null)
		SetFailState("[Weapon Switch Speed Fix] Could not create %s detour.", signature);

	detour.AddParam(HookParamType_CBaseEntity);
	if (!detour.SetFromConf(g_hGameData, SDKConf_Signature, signature)) {
		delete detour;
		SetFailState("[Weapon Switch Speed Fix] Missing %s signature.", signature);
	}

	return detour;
}

Handle CreateWeaponPairSDKCall(const char[] signature) {
	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(g_hGameData, SDKConf_Signature, signature))
		SetFailState("[Weapon Switch Speed Fix] Missing %s signature.", signature);

	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);

	Handle call = EndPrepSDKCall();
	if (call == null)
		SetFailState("[Weapon Switch Speed Fix] Could not prepare %s SDKCall.", signature);

	return call;
}

public MRESReturn Detour_DrawSpeedModifier_Post(Address pThis, DHookReturn hReturn, DHookParam hParams) {
	if (!g_cvEnabled.BoolValue || g_bDiagnosticBypass || !IsStackedModifier(hReturn.Value))
		return MRES_Ignored;

	hReturn.Value = g_cvMaximumModifier.FloatValue;
	if (!g_bDiagnosticNoCount)
		g_iBlockedDrawModifiers++;
	return MRES_Override;
}

public MRESReturn Detour_HolsterSpeedModifier_Post(Address pThis, DHookReturn hReturn, DHookParam hParams) {
	if (!g_cvEnabled.BoolValue || g_bDiagnosticBypass || !IsStackedModifier(hReturn.Value))
		return MRES_Ignored;

	hReturn.Value = g_cvMaximumModifier.FloatValue;
	if (!g_bDiagnosticNoCount)
		g_iBlockedHolsterModifiers++;
	return MRES_Override;
}

bool IsStackedModifier(float modifier) {
	return modifier > g_cvMaximumModifier.FloatValue + 0.001;
}

public Action Command_WeaponSwitchSpeedInfo(int client, int args) {
	if (client < 1 || !IsClientInGame(client)) {
		ReplyToCommand(client, "[Weapon Switch Speed Fix] This command must be used in game.");
		return Plugin_Handled;
	}

	int weapons[64];
	int weaponCount = CollectWeapons(client, weapons, sizeof weapons);
	ReplyToCommand(client, "[Weapon Switch Speed Fix] %s | blocked draw: %d | blocked holster: %d",
		g_cvEnabled.BoolValue ? "enabled" : "disabled", g_iBlockedDrawModifiers, g_iBlockedHolsterModifiers);
	ReplyToCommand(client, "[Weapon Switch Speed Fix] Carried native weapons: %d", weaponCount);

	char weaponClassname[64];
	for (int index = 0; index < weaponCount; index++) {
		GetEntityClassname(weapons[index], weaponClassname, sizeof weaponClassname);
		ReplyToCommand(client, "  [%d] %s (entity %d)", index, weaponClassname, weapons[index]);
	}

	bool foundStackingPair = false;
	char firstClassname[64];
	char secondClassname[64];
	for (int first = 0; first < weaponCount; first++) {
		GetEntityClassname(weapons[first], firstClassname, sizeof firstClassname);

		for (int second = 0; second < weaponCount; second++) {
			if (first == second)
				continue;

			GetEntityClassname(weapons[second], secondClassname, sizeof secondClassname);
			float rawDrawModifier = GetRawPairModifier(g_hGetDrawSpeedModifier, weapons[first], weapons[second]);
			float rawHolsterModifier = GetRawPairModifier(g_hGetHolsterSpeedModifier, weapons[first], weapons[second]);
			float appliedDrawModifier = GetProtectedPairModifier(g_hGetDrawSpeedModifier, weapons[first], weapons[second]);
			float appliedHolsterModifier = GetProtectedPairModifier(g_hGetHolsterSpeedModifier, weapons[first], weapons[second]);
			bool drawBlocked = IsStackedModifier(rawDrawModifier);
			bool holsterBlocked = IsStackedModifier(rawHolsterModifier);

			ReplyToCommand(client, "  %s %d -> %s %d: raw draw x%.3f, holster x%.3f | applied draw x%.3f, holster x%.3f | %s",
				firstClassname, weapons[first], secondClassname, weapons[second], rawDrawModifier,
				rawHolsterModifier, appliedDrawModifier, appliedHolsterModifier,
				drawBlocked || holsterBlocked ? (g_cvEnabled.BoolValue ? "blocked" : "stacking, fix disabled") : "no stack");
			if (drawBlocked || holsterBlocked)
				foundStackingPair = true;
		}
	}

	if (!foundStackingPair)
		ReplyToCommand(client, "[Weapon Switch Speed Fix] No carried weapon pair has a multiplying draw or holster modifier.");

	return Plugin_Handled;
}

public Action Command_WeaponSwitchSpeedValues(int client, int args) {
	if (client < 1 || !IsClientInGame(client)) {
		ReplyToCommand(client, "[Weapon Switch Speed Fix] This command must be used in game.");
		return Plugin_Handled;
	}

	int weapons[64];
	int weaponCount = CollectWeapons(client, weapons, sizeof weapons);
	ReplyToCommand(client, "[Weapon Switch Speed Fix] Native switch-speed values for %d carried weapons:", weaponCount);

	if (weaponCount < 2) {
		ReplyToCommand(client, "[Weapon Switch Speed Fix] Carry at least two weapons to measure a switch pair.");
		return Plugin_Handled;
	}

	char firstClassname[64];
	char secondClassname[64];
	for (int first = 0; first < weaponCount; first++) {
		GetEntityClassname(weapons[first], firstClassname, sizeof firstClassname);

		for (int second = 0; second < weaponCount; second++) {
			if (first == second)
				continue;

			GetEntityClassname(weapons[second], secondClassname, sizeof secondClassname);
			float rawDrawModifier = GetRawPairModifier(g_hGetDrawSpeedModifier, weapons[first], weapons[second]);
			float rawHolsterModifier = GetRawPairModifier(g_hGetHolsterSpeedModifier, weapons[first], weapons[second]);
			float appliedDrawModifier = GetProtectedPairModifier(g_hGetDrawSpeedModifier, weapons[first], weapons[second]);
			float appliedHolsterModifier = GetProtectedPairModifier(g_hGetHolsterSpeedModifier, weapons[first], weapons[second]);

			ReplyToCommand(client, "  %s %d -> %s %d: native draw x%.3f, holster x%.3f | applied draw x%.3f, holster x%.3f",
				firstClassname, weapons[first], secondClassname, weapons[second], rawDrawModifier,
				rawHolsterModifier, appliedDrawModifier, appliedHolsterModifier);
		}
	}

	return Plugin_Handled;
}

float GetRawPairModifier(Handle call, int firstWeapon, int secondWeapon) {
	g_bDiagnosticBypass = true;
	float modifier = SDKCall(call, firstWeapon, secondWeapon);
	g_bDiagnosticBypass = false;
	return modifier;
}

float GetProtectedPairModifier(Handle call, int firstWeapon, int secondWeapon) {
	g_bDiagnosticNoCount = true;
	float modifier = SDKCall(call, firstWeapon, secondWeapon);
	g_bDiagnosticNoCount = false;
	return modifier;
}

int CollectWeapons(int client, int[] weapons, int maxWeapons) {
	int weaponCount = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	int found = 0;

	for (int index = 0; index < weaponCount && found < maxWeapons; index++) {
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", index);
		if (!IsINSWeapon(weapon) || IsWeaponAlreadyListed(weapons, found, weapon))
			continue;

		weapons[found++] = weapon;
	}

	return found;
}

bool IsINSWeapon(int entity) {
	if (entity <= MaxClients || !IsValidEntity(entity))
		return false;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof classname);
	return StrContains(classname, "weapon_") == 0;
}

bool IsWeaponAlreadyListed(const int[] weapons, int weaponCount, int weapon) {
	for (int index = 0; index < weaponCount; index++)
		if (weapons[index] == weapon)
			return true;

	return false;
}
