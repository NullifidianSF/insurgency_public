#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <insurgencydy>

public Plugin myinfo = {
	name = "ca_countdown",
	author = "Nullifidian",
	description = "Print how long left until counterattack.",
	version = "1.2",
	url = "https://steamcommunity.com/id/Nullifidian/"
};

ConVar	g_cvDelay,
		g_cvDelayFinale;

int		g_iDelay,
		g_iDelayFinale;

char	g_sSound1[] = "hq/outpost/outpost_nextwave8.ogg",
		g_sSound2[] = "hq/outpost/outpost_nextwave5.ogg";

public void OnPluginStart() {
	HookEvent("controlpoint_captured", Event_ControlPointCaptured);
	HookEvent("object_destroyed", Event_ObjectDestroyed);

	//How long (in seconds) until the enemy counter-attack wave spawns.
	g_cvDelay = FindConVar("mp_checkpoint_counterattack_delay");
	if (!g_cvDelay) {
		SetFailState("mp_checkpoint_counterattack_delay not found!");
	}
	g_iDelay = g_cvDelay.IntValue;
	g_cvDelay.AddChangeHook(OnConVarChanged);

	//How long (in seconds) until the enemy counter-attack wave spawns (finale).
	g_cvDelayFinale = FindConVar("mp_checkpoint_counterattack_delay_finale");
	if (!g_cvDelayFinale) {
		SetFailState("mp_checkpoint_counterattack_delay_finale not found!");
	}
	g_iDelayFinale = g_cvDelayFinale.IntValue;
	g_cvDelayFinale.AddChangeHook(OnConVarChanged);
}

public void OnMapStart() {
	PrecacheSound(g_sSound1, true);
	PrecacheSound(g_sSound2, true);
}

public Action Event_ControlPointCaptured(Event event, const char[] name, bool dontBroadcast) {
	if (event.GetInt ("team") == 2) {
		CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast) {
	if (event.GetInt ("attackerteam") == 2) {
		CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

Action Timer_Countdown(Handle timer) {
	if (!Ins_InCounterAttack()) {
		return Plugin_Stop;
	}

	static int	iTimeDone = 0,
				ncp,
				acp;

	if (iTimeDone == 0) {
		ncp = Ins_ObjectiveResource_GetProp("m_iNumControlPoints");
		acp = Ins_ObjectiveResource_GetProp("m_nActivePushPointIndex");
	}

	int iTimeLeft;

	//last point (from bot respawn by daimyo)
	if ((acp+1) == ncp) {
		if (iTimeDone >= g_iDelayFinale) {
			iTimeDone = 0;
			return Plugin_Stop;
		}

		iTimeDone++;
		iTimeLeft = g_iDelayFinale - iTimeDone;

		if (iTimeLeft <= 0) {
			iTimeDone = 0;
			PlaySound();
			return Plugin_Stop;
		}
	} else {
		if (iTimeDone >= g_iDelay) {
			iTimeDone = 0;
			return Plugin_Stop;
		}

		iTimeDone++;
		iTimeLeft = g_iDelay - iTimeDone;

		if (iTimeLeft <= 0) {
			iTimeDone = 0;
			PlaySound();
			return Plugin_Stop;
		}
	}
	PrintCenterTextAll("Insurgents counter-attacking in %d", iTimeLeft);
	return Plugin_Continue;
}

void PlaySound() {
	switch (GetRandomInt(0, 1)) {
		case 0: EmitSoundToAll(g_sSound1);
		case 1: EmitSoundToAll(g_sSound2);
	}
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvDelay) {
		g_iDelay = g_cvDelay.IntValue;
	}
	else if (convar == g_cvDelayFinale) {
		g_iDelayFinale = g_cvDelayFinale.IntValue;
	}
}