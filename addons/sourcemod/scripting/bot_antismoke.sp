#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

int			ga_iThrowCount[2048] = {0, ...},
			g_iMAX;

bool		ga_bPlayerInSmoke[MAXPLAYERS + 1][2048];

float		ga_fEyeAngles[MAXPLAYERS + 1][3],
			g_fRNG,
			g_fDIST;

ConVar		g_cvRNG,
			g_cvMAX,
			g_cvDIST;

ArrayList	ga_hExplosives;

public Plugin myinfo = {
	name		= "bot_antismoke",
	author		= "Nullifidian",
	description	= "A bot will throw a grenade at a human player if the human player is in a cloud of smoke",
	version		= "1.5",
	url			= ""
};

public void OnPluginStart() {
	ga_hExplosives = CreateArray();
	
	HookEvent("grenade_detonate", Event_GrenadeDetonate);

	g_cvRNG = CreateConVar("sm_botantismokerng", "1.0", "Chance for a bot to throw grenade at a smoke", FCVAR_NONE, true, 0.0, true, 1.0);
	g_fRNG = g_cvRNG.FloatValue;
	g_cvRNG.AddChangeHook(OnConVarChanged);

	g_cvMAX = CreateConVar("sm_botantismokemax", "2.0", "Max times bots can throw grenades at the same smoke [0.0 = no limit]", FCVAR_NONE, true, 0.0);
	g_iMAX = g_cvMAX.IntValue;
	g_cvMAX.AddChangeHook(OnConVarChanged);

	g_cvDIST = CreateConVar("sm_botantismokedistance", "1700.0", "Max distance between a bot and a smoke target [0.0 = no limit]", FCVAR_NONE, true, 0.0);
	g_fDIST = g_cvDIST.FloatValue;
	g_cvDIST.AddChangeHook(OnConVarChanged);

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart() {
	CreateTimer(2.0, TimerR_SmokeCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	ClearArray(ga_hExplosives);
	return Plugin_Continue;
}

public Action Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || (IsClientInGame(client) && IsFakeClient(client))) {
		return Plugin_Continue;
	}

	int iEnt = event.GetInt("entityid");
	if (!IsValidEntity(iEnt)) {
		return Plugin_Continue;
	}

	char sEnt[32];
	if (!GetEntityClassname(iEnt, sEnt, sizeof(sEnt)) || (StrContains(sEnt, "m18", false) == -1 && StrContains(sEnt, "smoke", false) == -1)) {
		return Plugin_Continue;
	}

	ga_iThrowCount[iEnt] = 0;
	PushArrayCell(ga_hExplosives, EntIndexToEntRef(iEnt));

	return Plugin_Continue;
}

Action TimerR_SmokeCheck(Handle timer) {
	if (g_fRNG == 0.0) {
		return Plugin_Continue;
	} 

	int iArraySize = ga_hExplosives.Length;

	if (iArraySize < 1) {
		return Plugin_Continue;
	}

	int		iEnt;

	float	fEntPos[3],
			fPlayerPos[3];
	
	for (int i = 1; i < MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) {
			continue;
		}

		iArraySize = ga_hExplosives.Length;
		if (iArraySize < 1) {
			break;
		}

		if (!IsFakeClient(i)) {
			for (int j = (iArraySize - 1); j >= 0; j--) {
				iEnt = EntRefToEntIndex(ga_hExplosives.Get(j));

				if (iEnt == INVALID_ENT_REFERENCE || !IsValidEntity(iEnt)) {
					RemoveFromArray(ga_hExplosives, j);
					continue;
				}

				GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fEntPos);
				GetClientAbsOrigin(i, fPlayerPos);
				//PrintToChatAll("dist from smoke: %f", GetVectorDistance(fEntPos, fPlayerPos));
				if (GetVectorDistance(fEntPos, fPlayerPos) <= 280) {
					ga_bPlayerInSmoke[i][iEnt] = true;
				} else {
					ga_bPlayerInSmoke[i][iEnt] = false;
				}
			}
			continue;
		}

		for (int j = (iArraySize - 1); j >= 0; j--) {
			iEnt = EntRefToEntIndex(ga_hExplosives.Get(j));
			if (iEnt == INVALID_ENT_REFERENCE || !IsValidEntity(iEnt)) {
				RemoveFromArray(ga_hExplosives, j);
				continue;
			}

			for (int k = 1; k <=  MaxClients; k++) {
				if (ga_bPlayerInSmoke[k][iEnt]
				&& IsClientInGame(k)
				&& IsPlayerAlive(k)
				&& IsTargetInSightRange(i, k, 90.0, g_fDIST)
				&& GetRandomFloat(0.0, 1.0) <= g_fRNG
				&& GiveNadeAndThrow(i)) {
					if (g_iMAX == 0) {
						return Plugin_Continue;
					}
					ga_iThrowCount[iEnt]++;
					if (g_iMAX >= ga_iThrowCount[iEnt]) {
						RemoveFromArray(ga_hExplosives, j);
					}
					return Plugin_Continue;
				}
			}
		}
	}
	return Plugin_Continue;
}

//based on https://forums.alliedmods.net/showthread.php?t=210080
bool IsTargetInSightRange(int client, int target, float angle = 90.0, float distance = 0.0, bool heightcheck = true, bool negativeangle = false) {
	if (angle > 360.0) {
		angle = 360.0;
	}
	if (angle < 0.0) {
		return false;
	}

	float	clientpos[3],
			targetpos[3],
			anglevector[3],
			targetvector[3],
			resultangle,
			resultdistance;
			
	GetClientEyeAngles(client, anglevector);
	GetAngleVectors(anglevector, anglevector, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(anglevector, anglevector);

	if (negativeangle) {
		NegateVector(anglevector);
	}

	GetClientAbsOrigin(client, clientpos);
	GetClientAbsOrigin(target, targetpos);
	targetpos[2] += 50.0;

	if (heightcheck && distance > 0) {
		resultdistance = GetVectorDistance(clientpos, targetpos);
	}

	MakeVectorFromPoints(clientpos, targetpos, targetvector);
	NormalizeVector(targetvector, targetvector);

	resultangle = RadToDeg(ArcCosine(GetVectorDotProduct(targetvector, anglevector)));
	
	if (resultangle <= angle / 2) {
		Handle hTrace = TR_TraceRayFilterEx(clientpos, targetpos, MASK_SOLID_BRUSHONLY, RayType_EndPoint, TraceFilter);
		if (TR_DidHit(hTrace)) {
			delete hTrace;
			return false;
		}
		delete hTrace;

		GetVectorAngles(targetvector, ga_fEyeAngles[client]);

		if (distance > 0) {
			if (!heightcheck) {
				resultdistance = GetVectorDistance(clientpos, targetpos);
			}
			if (distance >= resultdistance) {
				return true;
			} else {
				return false;
			}
		} else {
			return true;
		}
	}
	return false;
}

bool TraceFilter(int entity, int contentsMask, any data) {
	return (entity == data);
}

bool GiveNadeAndThrow(int client) {
	int iWeapon = GetPlayerWeaponSlot(client, 3);

	if (iWeapon != -1 && IsValidEntity(iWeapon)) {
		char sName[32];
		if (GetEntityClassname(iWeapon, sName, sizeof(sName))
		&& (strcmp(sName, "weapon_f1", false) == 0
		|| strcmp(sName, "weapon_m67", false) == 0
		|| strcmp(sName, "weapon_molotov", false) == 0
		|| strcmp(sName, "weapon_anm14", false) == 0
		|| strcmp(sName, "weapon_m84", false) == 0)) {
			if (HasEntProp(iWeapon, Prop_Send, "m_bPinPulled")) {
				TeleportEntity(client, NULL_VECTOR, ga_fEyeAngles[client], NULL_VECTOR);
				SetEntProp(iWeapon, Prop_Send, "m_bPinPulled", true);
				SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", iWeapon);
				return true;
			}
		}
		return false;
	}

	switch (GetRandomInt(0, 4)) {
		case 0: iWeapon = GivePlayerItem(client, "weapon_f1");
		case 1: iWeapon = GivePlayerItem(client, "weapon_m67");
		case 2: iWeapon = GivePlayerItem(client, "weapon_molotov");
		case 3: iWeapon = GivePlayerItem(client, "weapon_anm14");
		case 4: iWeapon = GivePlayerItem(client, "weapon_m84");
	}

	if (iWeapon > 0 && IsValidEntity(iWeapon)) {
		SetEntProp(client, Prop_Send, "m_iAmmo", 1, _, GetEntProp(iWeapon, Prop_Data, "m_iPrimaryAmmoType"));
		if (HasEntProp(iWeapon, Prop_Send, "m_bPinPulled")) {
			TeleportEntity(client, NULL_VECTOR, ga_fEyeAngles[client], NULL_VECTOR);
			SetEntProp(iWeapon, Prop_Send, "m_bPinPulled", true);
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", iWeapon);
			return true;
		}
	}
	return false;
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvRNG) {
		g_fRNG = g_cvRNG.FloatValue;
	}
	else if (g_cvMAX) {
		g_iMAX = g_cvMAX.IntValue;
	}
	else if (g_cvDIST) {
		g_fDIST = g_cvDIST.FloatValue;
	}
}