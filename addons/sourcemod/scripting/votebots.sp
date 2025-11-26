#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = {
    name = "votebots",
    author = "Nullifidian",
    description = "vote menu to change bot count",
    version = "2.4"
};

const int g_iVoteOptions = 3;

int ga_iVotedFor[MAXPLAYERS + 1] = {0, ...},
    ga_iTotalVotes[g_iVoteOptions + 1] = {0, ...},
    g_iLivesMultiNow,
    g_iLivesMultiDef,
    g_iNeedVotes,
    g_iSecPlayers;

float g_fVotePercent;

bool g_bRoundStarted = false,
     ga_bPlayerVoted[MAXPLAYERS + 1] = {false, ...},
     g_bLateLoad;

ConVar g_cvVotePercent = null,
       g_cvBotLives = null;

char VoteSound[] = "ui/vote_success.wav";

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    g_bLateLoad = late;
    return APLRes_Success;
}

public void OnPluginStart() {
    CreateTimer(2.0, Timer_FindConVar);

    g_cvVotePercent = CreateConVar("sm_votebots_percent", "0.60", "% of players in-game need to vote for X option for change to take effect");
    g_fVotePercent = g_cvVotePercent.FloatValue;
    g_cvVotePercent.AddChangeHook(OnConVarChanged);

    if (g_bLateLoad) {
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

public void OnMapStart() {
    PrecacheSound(VoteSound, true);
    for (int i = 1; i <= g_iVoteOptions; i++) {
        ga_iTotalVotes[i] = 0;
    }
}

public void OnMapEnd() {
    g_bRoundStarted = false;
}

public void OnClientPostAdminCheck(int client) {
    if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client)) {
        ResetPlayerVote(client, false);
        ga_bPlayerVoted[client] = false;
    }
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bRoundStarted) {
        return Plugin_Continue;
    }
    if (event.GetInt("bot")) {
        return Plugin_Continue;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (ga_bPlayerVoted[client]) {
        ResetPlayerVote(client, true);
    }
    CountVotes();
    return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    if (event.GetInt("isbot")) {
        return Plugin_Continue;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (ga_bPlayerVoted[client] && event.GetInt("team") != 2) {
        ResetPlayerVote(client, true);
        ga_bPlayerVoted[client] = false;
    }
    CreateTimer(0.1, Timer_CountVotes);
    return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    CreateTimer(GetRandomFloat(1.0, 60.0), Timer_AdAll, _, TIMER_FLAG_NO_MAPCHANGE);
    g_bRoundStarted = true;
    return Plugin_Continue;
}

Action Timer_AdAll(Handle timer) {
    PrintToChatAll("\x070088cc[!vb]\x01 Type \x07ffff00!vb\x01 to vote for more/fewer bots.");
    return Plugin_Stop;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    g_bRoundStarted = false;
    return Plugin_Continue;
}

public Action cmd_votebots(int client, int args) {
    if (!client) {
        return Plugin_Handled;
    }
    if (!g_bRoundStarted) {
        PrintToChat(client, "\x070088cc[!vb]\x01 You can't use this command before the game round starts!");
        return Plugin_Handled;
    }
    if (GetClientTeam(client) != 2) {
        PrintToChat(client, "\x070088cc[!vb]\x01 You must join the security team before using this command!");
        return Plugin_Handled;
    }

    char sArg[3];
    int iArg;
    if (args == 1) {
        GetCmdArg(1, sArg, sizeof(sArg));
        iArg = StringToInt(sArg);

        int iBots = 0;
        for (int i = 1; i <= g_iVoteOptions; i++) {
            iBots += 5;
            if (iBots == g_iLivesMultiNow) {
                iBots += 5;
            }
            if (iArg == g_iLivesMultiNow) {
                PrintToChat(client, "\x070088cc[!vb]\x01 It already set to \x070088cc%i", iArg);
                return Plugin_Handled;
            }
            if (iArg == iBots) {
                if (ga_bPlayerVoted[client]) {
                    ResetPlayerVote(client, true);
                } else {
                    ga_bPlayerVoted[client] = true;
                }

                ga_iVotedFor[client] = i;
                ga_iTotalVotes[i]++;
                g_iNeedVotes = RoundToFloor(SecPlayersInGame() * g_fVotePercent);

                if (g_iNeedVotes < 1) {
                    g_iNeedVotes = 1;
                }

                if (ga_iTotalVotes[i] > 0 && ga_iTotalVotes[i] >= g_iNeedVotes) {
                    VoteWon(iBots, ga_iTotalVotes[i]);
                } else {
                    PrintToChat(client, "\x070088cc[!vb]\x01 You voted for \x070088cc%i \x01(vote \x070088cc%i\x01/\x070088cc%i\x01)", iBots, ga_iTotalVotes[i], g_iNeedVotes);
                }
                return Plugin_Handled;
            }
        }
        PrintToChat(client, "\x070088cc[!vb]\x01 Invalid number!");
    }

    VoteMenuSetup(client);
    return Plugin_Handled;
}

void VoteMenuSetup(int client) {
    Menu menu = new Menu(Handle_VoteMenu);
    menu.SetTitle("Number of bots per player\ncurrent: %i | default: %i", g_iLivesMultiNow, g_iLivesMultiDef);
    int iBots = 0;
    char sBots[6],
         sBuffer[32];
    bool bDefVoteSet = false;
    g_iNeedVotes = RoundToFloor(SecPlayersInGame() * g_fVotePercent);
    if (g_iNeedVotes < 1) {
        g_iNeedVotes = 1;
    }

    for (int i = 1; i <= g_iVoteOptions; i++) {
        iBots += 5;
        if (iBots == g_iLivesMultiNow) {
            iBots += 5;
        }
        if (!bDefVoteSet && g_iLivesMultiDef != g_iLivesMultiNow && (g_iLivesMultiDef <= iBots || i == g_iVoteOptions)) {
            IntToString(g_iLivesMultiDef, sBots, sizeof(sBots));
            Format(sBuffer, sizeof(sBuffer), "%s (votes %i/%i)", sBots, ga_iTotalVotes[i], g_iNeedVotes);
            menu.AddItem(sBots, sBuffer, (i == ga_iVotedFor[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
            bDefVoteSet = true;
            continue;
        }

        IntToString(iBots, sBots, sizeof(sBots));
        Format(sBuffer, sizeof(sBuffer), "%s (votes %i/%i)", sBots, ga_iTotalVotes[i], g_iNeedVotes);
        menu.AddItem(sBots, sBuffer, (i == ga_iVotedFor[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    }
    menu.Display(client, 15);
}

public int Handle_VoteMenu(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_Select: {
            if (GetClientTeam(param1) != 2) {
                PrintToChat(param1, "\x070088cc[!vb]\x01 You must join the security team before using this command!");
                return 0;
            }
            if (ga_bPlayerVoted[param1]) {
                ResetPlayerVote(param1, true);
            } else {
                ga_bPlayerVoted[param1] = true;
            }
            int iVoteOption = param2 + 1;
            ga_iVotedFor[param1] = iVoteOption;
            ga_iTotalVotes[iVoteOption]++;
            g_iNeedVotes = RoundToFloor(SecPlayersInGame() * g_fVotePercent);
            if (g_iNeedVotes < 1) {
                g_iNeedVotes = 1;
            }
            char item[6];
            menu.GetItem(param2, item, sizeof(item));
            if (ga_iTotalVotes[iVoteOption] > 0 && ga_iTotalVotes[iVoteOption] >= g_iNeedVotes) {
                VoteWon(StringToInt(item), ga_iTotalVotes[iVoteOption]);
            } else {
                PrintToChat(param1, "\x070088cc[!vb]\x01 You voted for \x070088cc%s \x01(vote \x070088cc%i\x01/\x070088cc%i\x01)", item, ga_iTotalVotes[iVoteOption], g_iNeedVotes);
            }
        }
        case MenuAction_End: {
            delete menu;
        }
    }
    return 0;
}

void ResetPlayerVote(int client, bool total) {
    if (total && ga_iTotalVotes[ga_iVotedFor[client]] > 0) {
        ga_iTotalVotes[ga_iVotedFor[client]]--;
    }
    ga_iVotedFor[client] = 0;
}

int SecPlayersInGame() {
    int clients = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2) {
            clients++;
        }
    }
    return clients;
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (convar == g_cvBotLives) {
        if (g_bRoundStarted) {
            g_iLivesMultiNow = g_cvBotLives.IntValue;
        } else {
            g_iLivesMultiNow = g_iLivesMultiDef = g_cvBotLives.IntValue;
        }
    } else if (convar == g_cvVotePercent) {
        g_fVotePercent = g_cvVotePercent.FloatValue;
    }
}

void CountVotes() {
    g_iSecPlayers = SecPlayersInGame();
    if (g_iSecPlayers < 2 && g_iLivesMultiDef != g_iLivesMultiNow) {
        ServerCommand("sm_botlives %i", g_iLivesMultiDef);
        return;
    }
    g_iNeedVotes = RoundToFloor(g_iSecPlayers * g_fVotePercent);
    int iHighestVotes = 0;
    int iWinningOption = -1;

    for (int i = 1; i <= g_iVoteOptions; i++) {
        if (ga_iTotalVotes[i] > iHighestVotes) {
            iHighestVotes = ga_iTotalVotes[i];
            iWinningOption = i;
        }
    }

    if (iWinningOption != -1 && iHighestVotes >= g_iNeedVotes) {
        int iBots = 5 + (iWinningOption - 1) * 5;
        if (iBots == g_iLivesMultiNow) {
            iBots += 5;
        }
        VoteWon(iBots, iHighestVotes);
    }
}

Action Timer_CountVotes(Handle timer) {
    CountVotes();
    return Plugin_Stop;
}

void VoteWon(int bots, int vote) {
    ServerCommand("sm_botlives %i", bots);
    EmitSoundToAll(VoteSound, _, SNDCHAN_AUTO, _, _, 0.70);
    PrintToChatAll("\x070088cc[!vb]\x01 Votes \x070088cc%i\x01/\x070088cc%i\x01 : Changed bot count to \x070088cc%i\x01 per player.", vote, g_iNeedVotes, bots);
    PrintHintTextToAll("[!vb] Votes %i/%i : Changed bot count to %i per player.", vote, g_iNeedVotes, bots);
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i) && ga_bPlayerVoted[i]) {
            ResetPlayerVote(i, true);
            ga_bPlayerVoted[i] = false;
        }
    }
}

public Action cmdListener(int client, const char[] cmd, int argc) {
    if (argc < 1 || client < 1 || !IsClientInGame(client)) {
        return Plugin_Continue;
    }
    char sArg1[16];
    GetCmdArg(1, sArg1, sizeof(sArg1));
    if (strcmp(sArg1, "BotCount", false) == 0) {
        cmd_votebots(client, 0);
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

Action Timer_FindConVar(Handle timer) {
    if ((g_cvBotLives = FindConVar("sm_botlives")) == null) {
        SetFailState("Fatal Error: Unable to FindConVar \"sm_botlives\" !");
    } else {
        g_iLivesMultiNow = g_iLivesMultiDef = g_cvBotLives.IntValue;
        g_cvBotLives.AddChangeHook(OnConVarChanged);
    }
    return Plugin_Stop;
}
