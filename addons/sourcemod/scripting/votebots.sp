#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
	name = "votebots",
	author = "Nullifidian + ChatGPT",
	description = "vote menu to change bot count",
	version = "2.12.1"
};

#define VB_PREFIX "\x070088cc[!vb]\x01"

const int g_iVoteOptions = 5;

int		ga_iVotedFor[MAXPLAYERS + 1] = {0, ...};
int		ga_iTotalVotes[g_iVoteOptions + 1] = {0, ...};
int		g_iLivesMultiNow;
int		g_iLivesMultiDef;
int		g_iNeedVotes;
int		g_iSecPlayers;

float	g_fVotePercent;

bool	g_bRoundStarted = false;
bool	g_bLateLoad = false;
bool	ga_bPlayerVoted[MAXPLAYERS + 1] = {false, ...};
bool	g_bShownTeamHint[MAXPLAYERS + 1] = {false, ...};

ConVar	g_cvVotePercent = null;
ConVar	g_cvBotLives = null;

char	g_sVoteSound[] = "ui/vote_success.wav";

Handle	g_hCountVotesTimer = null;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	// Load translations
	LoadTranslations("votebots.phrases");

	CreateTimer(2.0, Timer_FindConVar);

	g_cvVotePercent = CreateConVar("sm_votebots_percent", "0.60", "% of players in-game need to vote for X option for change to take effect");
	g_fVotePercent = g_cvVotePercent.FloatValue;
	g_cvVotePercent.AddChangeHook(OnConVarChanged);

	if (g_bLateLoad)
	{
		g_bRoundStarted = true;
	}

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_disconnect", Event_PlayerDisconnect);

	RegConsoleCmd("votebots", cmd_votebots);
	RegConsoleCmd("vb", cmd_votebots);

	AddCommandListener(cmdListener, "callvote");

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart()
{
	PrecacheSound(g_sVoteSound, true);

	for (int i = 1; i <= g_iVoteOptions; i++)
	{
		ga_iTotalVotes[i] = 0;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		ga_bPlayerVoted[i] = false;
		ga_iVotedFor[i] = 0;
		g_bShownTeamHint[i] = false;
	}
}

public void OnMapEnd()
{
	g_bRoundStarted = false;

	if (g_hCountVotesTimer != null)
	{
		CloseHandle(g_hCountVotesTimer);
		g_hCountVotesTimer = null;
	}
}

// Simple integer abs helper
int IntAbs(int value)
{
	return (value < 0) ? -value : value;
}

/**
 * Compute the bot-count value associated with a given vote option index (1..g_iVoteOptions),
 * using the same logic as the original menu (skip current value, inject default in order).
 */
int GetBotsForOption(int optionIndex)
{
	int iBots = 0;
	bool bDefVoteSet = false;

	for (int i = 1; i <= g_iVoteOptions; i++)
	{
		iBots += 5;

		// Never offer the current value as a vote option
		if (iBots == g_iLivesMultiNow)
		{
			iBots += 5;
		}

		// Inject default value once, in sorted order
		if (!bDefVoteSet && g_iLivesMultiDef != g_iLivesMultiNow && (g_iLivesMultiDef <= iBots || i == g_iVoteOptions))
		{
			if (optionIndex == i)
			{
				// This option is the "default" value
				return g_iLivesMultiDef;
			}

			bDefVoteSet = true;
			continue;
		}

		if (optionIndex == i)
		{
			return iBots;
		}
	}

	// Fallback: should never happen, but return current so we don't change anything
	return g_iLivesMultiNow;
}

public void OnClientPostAdminCheck(int client)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
	{
		ResetPlayerVote(client, false);
		ga_bPlayerVoted[client] = false;
		g_bShownTeamHint[client] = false;
	}
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bRoundStarted)
	{
		return Plugin_Continue;
	}

	if (event.GetInt("bot"))
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients)
	{
		return Plugin_Continue;
	}

	if (ga_bPlayerVoted[client])
	{
		ResetPlayerVote(client, true);
	}

	// Debounced recount
	ScheduleCountVotes();
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetInt("isbot"))
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients)
	{
		return Plugin_Continue;
	}

	int newTeam = event.GetInt("team");

	// Drop vote if they leave Security
	if (ga_bPlayerVoted[client] && newTeam != 2)
	{
		ResetPlayerVote(client, true);
		ga_bPlayerVoted[client] = false;
	}

	// Show a one-time hint when they actually join Security (per map)
	if (newTeam == 2 && !g_bShownTeamHint[client] && IsClientInGame(client) && !IsFakeClient(client))
	{
		g_bShownTeamHint[client] = true;

		PrintToChat(client, "%s %T", VB_PREFIX, "VB_JoinHint_Chat", client);
		PrintHintText(client, "%T", "VB_JoinHint_Hint", client);
	}

	// Debounced recount
	ScheduleCountVotes();
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundStarted = true;
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundStarted = false;
	return Plugin_Continue;
}

public Action cmd_votebots(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}

	if (!g_bRoundStarted)
	{
		PrintToChat(client, "%s %T", VB_PREFIX, "VB_Cmd_NotStarted", client);
		return Plugin_Handled;
	}

	if (GetClientTeam(client) != 2)
	{
		PrintToChat(client, "%s %T", VB_PREFIX, "VB_Cmd_NotSecurity", client);
		return Plugin_Handled;
	}

	// Allow numeric usage: !vb 10, !vb 15, etc.
	if (args == 1)
	{
		char sArg[8];
		GetCmdArg(1, sArg, sizeof(sArg));
		int iArg = StringToInt(sArg);

		// If they request the current value, tell them and bail
		if (iArg == g_iLivesMultiNow)
		{
			PrintToChat(client, "%s %T", VB_PREFIX, "VB_Cmd_AlreadySet", client, iArg);
			return Plugin_Handled;
		}

		// Find which option index corresponds to this bot value
		int iOptionIndex = -1;
		for (int i = 1; i <= g_iVoteOptions; i++)
		{
			int iBots = GetBotsForOption(i);
			if (iArg == iBots)
			{
				iOptionIndex = i;
				break;
			}
		}

		if (iOptionIndex == -1)
		{
			PrintToChat(client, "%s %T", VB_PREFIX, "VB_Cmd_InvalidNumber", client);
			VoteMenuSetup(client);
			return Plugin_Handled;
		}

		int iBotsValue = GetBotsForOption(iOptionIndex);

		if (ga_bPlayerVoted[client])
		{
			ResetPlayerVote(client, true);
		}
		else
		{
			ga_bPlayerVoted[client] = true;
		}

		ga_iVotedFor[client] = iOptionIndex;
		ga_iTotalVotes[iOptionIndex]++;

		g_iNeedVotes = RoundToFloor(SecPlayersInGame() * g_fVotePercent);
		if (g_iNeedVotes < 1)
		{
			g_iNeedVotes = 1;
		}

		if (ga_iTotalVotes[iOptionIndex] > 0 && ga_iTotalVotes[iOptionIndex] >= g_iNeedVotes)
		{
			VoteWon(iBotsValue, ga_iTotalVotes[iOptionIndex]);
		}
		else
		{
			// Feedback to the voter
			PrintToChat(client, "%s %T", VB_PREFIX, "VB_Cmd_YouVoted", client, iBotsValue, ga_iTotalVotes[iOptionIndex], g_iNeedVotes);

			// Broadcast when a new option gets its first vote
			if (ga_iTotalVotes[iOptionIndex] == 1)
			{
				for (int i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i) && !IsFakeClient(i))
					{
						PrintToChat(i, "%s %T", VB_PREFIX, "VB_Vote_Started_Chat", i, client, iBotsValue, ga_iTotalVotes[iOptionIndex], g_iNeedVotes);
						PrintHintText(i, "%T", "VB_Vote_Started_Hint", i, iBotsValue, ga_iTotalVotes[iOptionIndex], g_iNeedVotes);
					}
				}
			}

			// Fallback if enough players voted overall but votes are split
			CheckAllVotedFallback();
		}

		return Plugin_Handled;
	}

	// No / invalid args: open menu
	VoteMenuSetup(client);
	return Plugin_Handled;
}

void VoteMenuSetup(int client)
{
	Menu menu = new Menu(Handle_VoteMenu);

	char sTitle[128];
	Format(sTitle, sizeof(sTitle), "%T", "VB_Menu_Title", client, g_iLivesMultiNow, g_iLivesMultiDef);
	menu.SetTitle(sTitle);

	g_iNeedVotes = RoundToFloor(SecPlayersInGame() * g_fVotePercent);
	if (g_iNeedVotes < 1)
	{
		g_iNeedVotes = 1;
	}

	char sBots[8];
	char sBuffer[64];

	for (int i = 1; i <= g_iVoteOptions; i++)
	{
		int iBots = GetBotsForOption(i);

		IntToString(iBots, sBots, sizeof(sBots));
		Format(sBuffer, sizeof(sBuffer), "%T", "VB_Menu_Item", client, sBots, ga_iTotalVotes[i], g_iNeedVotes);

		menu.AddItem(sBots, sBuffer, (i == ga_iVotedFor[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	menu.Display(client, 15);
}

public int Handle_VoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (GetClientTeam(param1) != 2)
			{
				PrintToChat(param1, "%s %T", VB_PREFIX, "VB_Cmd_NotSecurity", param1);
				return 0;
			}

			if (ga_bPlayerVoted[param1])
			{
				ResetPlayerVote(param1, true);
			}
			else
			{
				ga_bPlayerVoted[param1] = true;
			}

			int iVoteOption = param2 + 1;
			int iBotsValue = GetBotsForOption(iVoteOption);

			ga_iVotedFor[param1] = iVoteOption;
			ga_iTotalVotes[iVoteOption]++;

			g_iNeedVotes = RoundToFloor(SecPlayersInGame() * g_fVotePercent);
			if (g_iNeedVotes < 1)
			{
				g_iNeedVotes = 1;
			}

			if (ga_iTotalVotes[iVoteOption] > 0 && ga_iTotalVotes[iVoteOption] >= g_iNeedVotes)
			{
				VoteWon(iBotsValue, ga_iTotalVotes[iVoteOption]);
			}
			else
			{
				// Feedback to the voter
				PrintToChat(param1, "%s %T", VB_PREFIX, "VB_Cmd_YouVoted", param1, iBotsValue, ga_iTotalVotes[iVoteOption], g_iNeedVotes);

				// Broadcast when a new option gets its first vote
				if (ga_iTotalVotes[iVoteOption] == 1)
				{
					for (int i = 1; i <= MaxClients; i++)
					{
						if (IsClientInGame(i) && !IsFakeClient(i))
						{
							PrintToChat(i, "%s %T", VB_PREFIX, "VB_Vote_Started_Chat", i, param1, iBotsValue, ga_iTotalVotes[iVoteOption], g_iNeedVotes);
							PrintHintText(i, "%T", "VB_Vote_Started_Hint", i, iBotsValue, ga_iTotalVotes[iVoteOption], g_iNeedVotes);
						}
					}
				}

				// Fallback if enough players voted overall but votes are split
				CheckAllVotedFallback();
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}

	return 0;
}

void ResetPlayerVote(int client, bool total)
{
	if (total && ga_iVotedFor[client] > 0)
	{
		int index = ga_iVotedFor[client];
		if (index >= 1 && index <= g_iVoteOptions && ga_iTotalVotes[index] > 0)
		{
			ga_iTotalVotes[index]--;
		}
	}

	ga_iVotedFor[client] = 0;
}

int SecPlayersInGame()
{
	int clients = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2)
		{
			clients++;
		}
	}

	return clients;
}

/**
 * Fallback:
 * If at least the required percent of Security players have voted (voters >= g_iNeedVotes)
 * but no single option meets the normal % threshold (no option >= g_iNeedVotes),
 * pick the best option (most votes; tie -> closest to default; tie -> fewer bots).
 */
void CheckAllVotedFallback()
{
	g_iSecPlayers = SecPlayersInGame();

	// Only interesting if we have at least 2 Security players
	if (g_iSecPlayers <= 1)
	{
		return;
	}

	int voters = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2 && ga_bPlayerVoted[i])
		{
			voters++;
		}
	}

	if (voters == 0)
	{
		return;
	}

	// Normal required votes for a win (same as everywhere else)
	g_iNeedVotes = RoundToFloor(g_iSecPlayers * g_fVotePercent);
	if (g_iNeedVotes < 1)
	{
		g_iNeedVotes = 1;
	}

	// Fallback only kicks in if enough players have *participated* overall
	if (voters < g_iNeedVotes)
	{
		return;
	}

	// Find the highest vote count for any single option
	int iHighestVotes = 0;
	for (int i = 1; i <= g_iVoteOptions; i++)
	{
		if (ga_iTotalVotes[i] > iHighestVotes)
		{
			iHighestVotes = ga_iTotalVotes[i];
		}
	}

	if (iHighestVotes <= 0)
	{
		return;
	}

	// If some option already meets the normal threshold, don't override it
	if (iHighestVotes >= g_iNeedVotes)
	{
		return;
	}

	// Collect options that share the highest vote count
	int iCandidates[g_iVoteOptions];
	int iNumCandidates = 0;

	for (int i = 1; i <= g_iVoteOptions; i++)
	{
		if (ga_iTotalVotes[i] == iHighestVotes)
		{
			iCandidates[iNumCandidates++] = i;
		}
	}

	if (iNumCandidates == 0)
	{
		return;
	}

	int iChosenOption = iCandidates[0];
	int iChosenBots = GetBotsForOption(iChosenOption);

	// Tie-break: closest to default; if still tie, smaller bot value wins
	for (int j = 1; j < iNumCandidates; j++)
	{
		int opt = iCandidates[j];
		int bots = GetBotsForOption(opt);

		int diffCurrent = IntAbs(iChosenBots - g_iLivesMultiDef);
		int diffNew = IntAbs(bots - g_iLivesMultiDef);

		if (diffNew < diffCurrent || (diffNew == diffCurrent && bots < iChosenBots))
		{
			iChosenOption = opt;
			iChosenBots = bots;
		}
	}

	VoteWonSplit(iChosenBots, iHighestVotes, voters, g_iSecPlayers, g_iNeedVotes);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_cvBotLives)
	{
		if (g_bRoundStarted)
		{
			g_iLivesMultiNow = g_cvBotLives.IntValue;
		}
		else
		{
			g_iLivesMultiNow = g_iLivesMultiDef = g_cvBotLives.IntValue;
		}
	}
	else if (convar == g_cvVotePercent)
	{
		g_fVotePercent = g_cvVotePercent.FloatValue;
	}
}

void CountVotes()
{
	g_iSecPlayers = SecPlayersInGame();

	// If only one Security player and value isn't default, reset back to default
	if (g_iSecPlayers < 2 && g_iLivesMultiDef != g_iLivesMultiNow)
	{
		ServerCommand("sm_botlives %i", g_iLivesMultiDef);
		return;
	}

	g_iNeedVotes = RoundToFloor(g_iSecPlayers * g_fVotePercent);
	if (g_iNeedVotes < 1)
	{
		g_iNeedVotes = 1;
	}

	int iHighestVotes = 0;
	int iWinningOption = -1;

	for (int i = 1; i <= g_iVoteOptions; i++)
	{
		if (ga_iTotalVotes[i] > iHighestVotes)
		{
			iHighestVotes = ga_iTotalVotes[i];
			iWinningOption = i;
		}
	}

	if (iWinningOption != -1 && iHighestVotes >= g_iNeedVotes)
	{
		int iBots = GetBotsForOption(iWinningOption);

		if (iBots != g_iLivesMultiNow)
		{
			VoteWon(iBots, iHighestVotes);
		}
	}
}

void ScheduleCountVotes()
{
	if (g_hCountVotesTimer == null)
	{
		g_hCountVotesTimer = CreateTimer(0.1, Timer_CountVotes, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_CountVotes(Handle timer)
{
	g_hCountVotesTimer = null;
	CountVotes();
	return Plugin_Stop;
}

void ApplyBotLives(int bots)
{
	ServerCommand("sm_botlives %i", bots);
	EmitSoundToAll(g_sVoteSound, _, SNDCHAN_AUTO, _, _, 0.70);
}

void ClearAllVotes()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && ga_bPlayerVoted[i])
		{
			ResetPlayerVote(i, true);
			ga_bPlayerVoted[i] = false;
		}
	}
}

void VoteWon(int bots, int vote)
{
	ApplyBotLives(bots);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			PrintToChat(i, "%s %T", VB_PREFIX, "VB_VoteWon_Chat", i, vote, g_iNeedVotes, bots);
			PrintHintText(i, "%T", "VB_VoteWon_Hint", i, vote, g_iNeedVotes, bots);
		}
	}

	ClearAllVotes();
}

void VoteWonSplit(int bots, int topVotes, int voters, int secPlayers, int needWin)
{
	ApplyBotLives(bots);

	int pct = RoundToNearest(g_fVotePercent * 100.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			PrintToChat(i, "%s %T", VB_PREFIX, "VB_VoteWonSplit_Chat", i, voters, secPlayers, needWin, pct, bots, topVotes);
			PrintHintText(i, "%T", "VB_VoteWonSplit_Hint", i, voters, secPlayers, needWin, pct, bots, topVotes);
		}
	}

	ClearAllVotes();
}



public Action cmdListener(int client, const char[] cmd, int argc)
{
	if (argc < 1 || client < 1 || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	char sArg1[16];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	if (strcmp(sArg1, "BotCount", false) == 0)
	{
		cmd_votebots(client, 0);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

Action Timer_FindConVar(Handle timer)
{
	if ((g_cvBotLives = FindConVar("sm_botlives")) == null)
	{
		SetFailState("Fatal Error: Unable to FindConVar \"sm_botlives\" !");
	}
	else
	{
		g_iLivesMultiNow = g_iLivesMultiDef = g_cvBotLives.IntValue;
		g_cvBotLives.AddChangeHook(OnConVarChanged);
	}

	return Plugin_Stop;
}
