#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <tfdb>
#include <multicolors>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
    name        = "[TFDB] Versus Mode",
    author      = "keybangz",
    description = "A plugin to automatically enable god mode in certain 1v1 conditions.",
    version     = "1.0.0",
    url         = "https://github.com/keybangz/TFDBVersusMode"
};

float  g_fStartPosition[MAXPLAYERS + 1][3];
int g_iRoundTime = 600;
int g_iRemainingTime;
int    g_iLastRocket;
int g_iScore[MAXPLAYERS+1]		 = { 0, ... };
bool   g_bVersusMode 			 = false;
Handle g_hRoundHUD 		 		 = INVALID_HANDLE;
Handle g_hRoundTimer     		 = INVALID_HANDLE;
Handle g_hPlayer1HUD 		     = INVALID_HANDLE;
Handle g_hPlayer2HUD 			 = INVALID_HANDLE;
int Player1,Player2 			 = -1;

public void OnPluginStart()
{
    if (!TFDB_IsDodgeballEnabled())
        return;

    // HookEvent("player_hurt", OnPlayerHurt);
    HookEvent("teamplay_round_active", OnRoundStart);
    HookEvent("arena_round_start", OnRoundStart);
    HookEvent("teamplay_round_win", OnRoundEnd, EventHookMode_Post);

	g_hRoundHUD = CreateHudSynchronizer();
	g_hPlayer1HUD = CreateHudSynchronizer();
	g_hPlayer2HUD = CreateHudSynchronizer();

	RegAdminCmd("sm_versus", Command_VersusToggle, ADMFLAG_GENERIC, "Toggles versus mode.");

	if (TFDB_GetRoundStarted())
		g_iLastRocket = FindLastRocket();
}

public void OnMapStart() {
	DisableVersus();
}

public void EnableVersus()
{
	if(g_bVersusMode)
		return;

    g_bVersusMode = true;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && IsPlayerAlive(i))
        {
            GetClientAbsOrigin(i, g_fStartPosition[i]);
            SetEntProp(i, Prop_Data, "m_takedamage", 1, 1);

			// this may or may not work
			if(GetClientTeam(i) == 2)
				Player1 = i;
			else if(GetClientTeam(i) == 3)
				Player2 = i;

			SetHudTextParams(0.10, 0.125, float(g_iRoundTime), 255, 255, 255, 255);
			ShowSyncHudText(i, g_hPlayer1HUD, "%N: %d", Player1, g_iScore[Player1]);
			SetHudTextParams(0.10, 0.15, float(g_iRoundTime), 255, 255, 255, 255);
			ShowSyncHudText(i, g_hPlayer2HUD, "%N: %d", Player2, g_iScore[Player2]);
        }
    }

    int triggerEnt = FindEntityByClassname(-1, "trigger_hurt");

    if (IsValidEntity(triggerEnt))
        SDKHook(triggerEnt, SDKHook_Touch, OnTriggerHurt);

	// HUD Round Timer
	g_iRemainingTime = g_iRoundTime;
	g_hRoundTimer = CreateTimer(1.0, Timer_VersusRound, _, TIMER_REPEAT);

	TFDB_DestroyRockets();

	if (TFDB_GetRoundStarted())
		g_iLastRocket = FindLastRocket();

	CPrintToChatAll("\x05Versus\x01 mode enabled.");
}

public void DisableVersus()
{
	if(!g_bVersusMode)
		return;

    g_bVersusMode = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && GetClientTeam(i) >> 1)
        {
            SetEntProp(i, Prop_Data, "m_takedamage", 2, 1);
			g_iScore[i] = 0;
			ShowSyncHudText(i, g_hPlayer1HUD, "", Player1, g_iScore[Player1]);
			ShowSyncHudText(i, g_hPlayer2HUD, "", Player2, g_iScore[Player2]);
        }
    }

	// Covers players disconnecting.
	g_iScore[Player1] = 0;
	g_iScore[Player2] = 0;

	int triggerEnt = FindEntityByClassname(-1, "trigger_hurt");
	if(IsValidEntity(triggerEnt)) {
		SDKUnhook(triggerEnt, SDKHook_Touch, OnTriggerHurt);
	}

	CPrintToChatAll("\x05Versus\x01 mode disabled.");

	TFDB_DestroyRockets();

	delete g_hRoundTimer;
}

public Action Command_VersusToggle(int client, int args) {
	if(g_bVersusMode)
		DisableVersus();
	else if(!g_bVersusMode)
		EnableVersus();

	return Plugin_Handled;
}

public Action Timer_VersusRound(Handle timer) {
	g_iRemainingTime--;

	if(g_hRoundHUD != INVALID_HANDLE && g_bVersusMode) {
		SetHudTextParams(-1.0, 0.15, 5.0, 255, 255, 255, 255);
		for(int i = 1; i <= MaxClients; i++) {
			if(IsValidClient(i) && !IsFakeClient(i)) {
				ShowSyncHudText(i, g_hRoundHUD, "Versus Mode Enabled\n%02d:%02d", g_iRemainingTime / 60, g_iRemainingTime % 60);
			}
		}
	}

	// Force the round to end here.
	if(g_iRemainingTime <= 0) {
		DisableVersus();
		ForceEndRound();
	}

	return Plugin_Continue;
}

public void ForceEndRound() {
	int iEnt = -1;
	iEnt = FindEntityByClassname(iEnt, "game_round_win");
	
	if (iEnt < 1)
	{
		iEnt = CreateEntityByName("game_round_win");
		if (IsValidEntity(iEnt))
			DispatchSpawn(iEnt);
	}
		
	SetVariantInt(0);
	AcceptEntityInput(iEnt, "SetTeam");
	AcceptEntityInput(iEnt, "RoundWin");
}

public void OnClientPutInServer(int client) {
	int realClients = GetRealClientCount();

    if (realClients >> 2)
        DisableVersus();
}

public void OnClientDisconnect(int client) {
	int realClients = GetRealClientCount();
    int fakeClients = GetFakeClientCount();

    if (realClients == 1 && fakeClients == 1 || realClients == 2)
        EnableVersus();

	if (realClients == 0)
		DisableVersus();
}

public Action OnRoundStart(Event event, char[] name, bool dontBroadcast)
{
    int realClients = GetRealClientCount();
    int fakeClients = GetFakeClientCount();

    // PVB Bot Mode or players 1v1ing
    if (realClients == 1 && fakeClients == 1 || realClients == 2)
        EnableVersus();

    return Plugin_Continue;
}

public Action OnRoundEnd(Event event, char[] name, bool dontBroadcast)
{
    DisableVersus();

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!StrEqual(classname, "tf_projectile_rocket", false))
        return;

	if(!IsValidEntity(entity))
		return;

    SDKHook(entity, SDKHook_Touch, OnRocketTouch);
}

public Action OnRocketTouch(int entity, int other)
{
    if (entity != INVALID_ENT_REFERENCE && IsValidClient(other) && g_bVersusMode) {
        CPrintToChatAll("\x05%N\x01 was hit by a rocket travelling \x05%.0f\x01 mph with \x05%i\x01 deflections!", other, TFDB_GetRocketMphSpeed(g_iLastRocket), TFDB_GetRocketDeflections(g_iLastRocket));

		if(GetClientTeam(other) == 2)
			g_iScore[Player2]++;
		else if(GetClientTeam(other) == 3)
			g_iScore[Player1]++;

		for(int i = 1; i <= MaxClients; i++) {
			if(IsValidClient(i) && !IsFakeClient(i)) {
				SetHudTextParams(0.10, 0.125, float(g_iRemainingTime), 255, 255, 255, 255);
				ShowSyncHudText(i, g_hPlayer1HUD, "%N: %d", Player1, g_iScore[Player1]);
				SetHudTextParams(0.10, 0.15, float(g_iRemainingTime), 255, 255, 255, 255);
				ShowSyncHudText(i, g_hPlayer2HUD, "%N: %d", Player2, g_iScore[Player2]);
			}
		}
	}

    return Plugin_Continue;
}

public Action TFDB_OnRocketDeflectPre(int iIndex)
{
	g_iLastRocket = iIndex;
	
	return Plugin_Continue;
}

public void TFDB_OnRocketCreated(int iIndex)
{
	g_iLastRocket = iIndex;
}

public Action OnTriggerHurt(int entity, int player)
{
    if (IsValidClient(player) && IsPlayerAlive(player))
        TeleportEntity(player, g_fStartPosition[player], NULL_VECTOR, NULL_VECTOR);

    return Plugin_Continue;
}

int FindLastRocket()
{
	float fDeflectionTime;
	float fSpawnTime;
	int   iDeflectionIndex;
	int   iSpawnIndex;
	
	for (int iIndex = 0; iIndex < MAX_ROCKETS; iIndex++)
	{
		if (!TFDB_IsValidRocket(iIndex)) continue;
		
		if (TFDB_GetRocketLastDeflectionTime(iIndex) > fDeflectionTime)
		{
			iDeflectionIndex = iIndex;
			fDeflectionTime  = TFDB_GetRocketLastDeflectionTime(iIndex);
		}
		
		if (TFDB_GetLastSpawnTime(iIndex) > fSpawnTime)
		{
			iSpawnIndex = iIndex;
			fSpawnTime  = TFDB_GetLastSpawnTime(iIndex);
		}
	}
	
	return fDeflectionTime < fSpawnTime ? iSpawnIndex : iDeflectionIndex;
}

// Client Functions
bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

int GetRealClientCount(bool inGameOnly = true)
{
    int clients = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && !IsFakeClient(i) && !IsClientReplay(i) && !IsClientSourceTV(i))
        {
            clients++;
        }
    }
    return clients;
}

int GetFakeClientCount(bool inGameOnly = true)
{
    int clients = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && IsFakeClient(i) && !IsClientReplay(i) && !IsClientSourceTV(i))
        {
            clients++;
        }
    }
    return clients;
}