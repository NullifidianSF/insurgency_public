#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.2"
#define GAMEDATA_FILE "insurgency-bm.games"

Handle g_hResupply = null;
int g_iLastResupplyTimeOffset = -1;
int g_iResupplyPenaltyTimeOffset = -1;
int g_iResupplyCountOffset = -1;

public Plugin myinfo =
{
	name = "BM Admin Resupply",
	author = "OpenAI Codex",
	description = "Admin command to rearm a living player without consuming normal resupply cooldown",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	if (GetEngineVersion() != Engine_Insurgency)
	{
		SetFailState("This plugin supports Insurgency 2014 only.");
	}

	GameData config = LoadGameConfigFile(GAMEDATA_FILE);
	if (config == null)
	{
		SetFailState("Missing gamedata: addons/sourcemod/gamedata/%s.txt", GAMEDATA_FILE);
	}

	g_iLastResupplyTimeOffset = config.GetOffset("CINSPlayer::LastResupplyTime");
	g_iResupplyPenaltyTimeOffset = config.GetOffset("CINSPlayer::ResupplyPenaltyTime");
	g_iResupplyCountOffset = config.GetOffset("CINSPlayer::ResupplyCount");
	if (g_iLastResupplyTimeOffset == -1
		|| g_iResupplyPenaltyTimeOffset == -1
		|| g_iResupplyCountOffset == -1)
	{
		delete config;
		SetFailState("Missing one or more CINSPlayer resupply offsets in %s.", GAMEDATA_FILE);
	}

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CINSPlayer::Resupply"))
	{
		delete config;
		SetFailState("Missing CINSPlayer::Resupply signature in %s.", GAMEDATA_FILE);
	}

	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_hResupply = EndPrepSDKCall();
	delete config;

	if (g_hResupply == null)
	{
		SetFailState("CINSPlayer::Resupply could not be prepared for this server build.");
	}

	RegAdminCmd("sm_resupply", Command_Resupply, ADMFLAG_BAN,
		"sm_resupply <target> - rearm living players without consuming normal resupply cooldown");
}

public void OnPluginEnd()
{
	delete g_hResupply;
}

public Action Command_Resupply(int client, int args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "Usage: sm_resupply <target>  (@all and @humans supported)");
		return Plugin_Handled;
	}

	char targetArgument[MAX_TARGET_LENGTH];
	GetCmdArg(1, targetArgument, sizeof(targetArgument));

	int targets[MAXPLAYERS];
	char targetName[MAX_TARGET_LENGTH];
	bool targetNameIsML;
	int targetCount = ProcessTargetString(targetArgument, client, targets, sizeof(targets),
		COMMAND_FILTER_CONNECTED | COMMAND_FILTER_ALIVE,
		targetName, sizeof(targetName), targetNameIsML);
	if (targetCount <= 0)
	{
		ReplyToTargetError(client, targetCount);
		return Plugin_Handled;
	}

	int resuppliedCount = 0;
	for (int i = 0; i < targetCount; i++)
	{
		int target = targets[i];
		if (!ResupplyPlayerPreservingCooldown(target))
		{
			LogError("Unable to resupply %N.", target);
			continue;
		}

		resuppliedCount++;
		PrintToChat(target, "\x04[Admin]\x01 You have been resupplied.");
		LogAction(client, target, "resupplied \"%L\"", target);
	}

	ReplyToCommand(client, "Resupplied %d of %d living target%s.",
		resuppliedCount, targetCount, targetCount == 1 ? "" : "s");
	return Plugin_Handled;
}

bool ResupplyPlayerPreservingCooldown(int client)
{
	float lastResupplyTime = GetEntDataFloat(client, g_iLastResupplyTimeOffset);
	float penaltyTime = GetEntDataFloat(client, g_iResupplyPenaltyTimeOffset);
	int resupplyCount = GetEntData(client, g_iResupplyCountOffset, 4);

	bool resupplied = view_as<bool>(SDKCall(g_hResupply, client, true));

	// Resupply(true) bypasses the engine gate but records a new resupply.
	// Restore every field used by normal resupply cooldown and penalty calculations.
	SetEntDataFloat(client, g_iLastResupplyTimeOffset, lastResupplyTime, false);
	SetEntDataFloat(client, g_iResupplyPenaltyTimeOffset, penaltyTime, false);
	SetEntData(client, g_iResupplyCountOffset, resupplyCount, 4, false);

	return resupplied;
}
