/*
Flags:
0 - Unregistered Users  -  10 MIN
1 - Registered users    -  30 MIN
2 - Subscribed Users    - Unlimited
3 - Premium  Users       - Unlimited*/
#include <sourcemod>
#include <cstrike>

#define PLUGIN_VERSION "1.6"
#define QUERY_LENGTH 150

static int TimeLeft[MAXPLAYERS + 1];
int RegisterStatus[MAXPLAYERS + 1];
int ActiveKickStatus[MAXPLAYERS + 1];
int IdOnRecord[MAXPLAYERS + 1];
Handle ClTimer[MAXPLAYERS + 1];

char clientbuffer[MAXPLAYERS + 1][32];

Handle DB = INVALID_HANDLE;
Handle Client_Check[MAXPLAYERS + 1];
Handle Client_New[MAXPLAYERS + 1];
Handle Welcome_Client[MAXPLAYERS + 1];
Handle ClientRegister[MAXPLAYERS + 1];
Handle Kick_Client[MAXPLAYERS + 1];
ConVar g_unregtime;
ConVar g_regtime;
Handle Unsubscribed_timer[MAXPLAYERS + 1];
//Handle UpdateExit[MAXPLAYERS + 1];
public Plugin myinfo = 
{
	name = "Playtonia Deathmatch Plugin", 
	author = "Sai \"ScouZa\" Anand", 
	description = "Manages clients based on Playtonia database, allows registration & 10 minutes of free play to unregistered users.", 
	version = PLUGIN_VERSION, 
	url = "http://beta.playtonia.com/"
};

public void OnPluginStart()
{
	RegAdminCmd("sm_registerplayer", Command_Register, ADMFLAG_GENERIC, "Opens Playtonia Registration page for target");
	RegConsoleCmd("sm_register", Player_Register, "Client command for register");
	g_unregtime = CreateConVar("pl_unregmaxtime", "10", "Maximum amount of minutes a unregistered player can play.");
	g_regtime = CreateConVar("pl_regmaxtime", "60", "Maximum amout of minutes a unsubscribed player can play.");
	char error[150];
	DB = SQL_Connect("Unreg", true, error, sizeof(error));
	if (DB == INVALID_HANDLE)
	{
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Cannot connect to MySQL Server: %s", error);
		CloseHandle(DB);
	}
	else
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "MySQL Connection Successful");
}

public void OnClientAuthorized(client)
{
	char name[32];
	GetClientName(client, name, sizeof(name));
	if (!IsFakeClient(client))
	{
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "%s is attempting to join server.", name);
		IsClientRegistered(client);
		Client_Check[client] = CreateTimer(5.0, ClientCheck, client);
	}
}

public void OnClientPutInServer(client)
{
	char name[32];
	char authid[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, authid, sizeof(authid));
	if (!IsFakeClient(client))
	{
		PrintToChatAll("[SM] \x04%s\x01 has joined the server.", name, authid);
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "%s (%s) has joined the server.", name, authid);
	}
}

public Action ClientCheck(Handle timer, any client)
{
	Client_Check[client] = INVALID_HANDLE;
	char name[32];
	GetClientName(client, name, sizeof(name));
	
	if (RegisterStatus[client] == 0 || RegisterStatus[client] == 1)
	{
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Checking if client %s is in unregistered players database...", name);
		ClientUnregistered(client);
		Client_New[client] = CreateTimer(5.0, ClientNew, client);
	}
}

public Action ClientNew(Handle timer, any client)
{
	Client_New[client] = INVALID_HANDLE;
	char name[32];
	if (IsClientConnected(client) && !IsFakeClient(client)) {
		GetClientName(client, name, sizeof(name)); }
	
	if (!IdOnRecord[client]) {
		ClientIsNew(client); }
}

public void OnClientPostAdminCheck(client)
{
	if (!IsFakeClient(client))
		Welcome_Client[client] = CreateTimer(5.0, WelcomeClient, client);
}

public Action WelcomeClient(Handle timer, any client)
{
	Welcome_Client[client] = INVALID_HANDLE;
	if (IsClientInGame(client))
	{
		PrintToChat(client, " \x09WELCOME TO THE \x04PLAYTONIA \x09PRACTICE SERVER!");
		
		if (RegisterStatus[client] == 0)
		{
			PrintToChat(client, " \x03Unregistered users get \x02ONLY %d MINUTES\x03 per day!", g_unregtime.IntValue);
			PrintToChat(client, " \x02You have %d minutes of practice left for today.", TimeLeft[client]);
			PrintToChat(client, " \x03Type \x04!register \x03on chat to register now.");
			PrintToChat(client, " \x09Reconnect after registration to enjoy unlimited practice.");
			PrintToChat(client, " \x03Can't see registration page? Set 'cl_disablehtmlmotd' to 0");
			PrintToChat(client, " \x03Signin via Steam @\x04beta.playtonia.com\x03 to register.");
		} else if (RegisterStatus[client] == 1) {
			PrintToChat(client, " \x03Unsubscribed users get \x02ONLY %d MINUTES\x03 per day!", g_regtime.IntValue);
			PrintToChat(client, "  \x09Subscribe in Playtonia Website. To play unlimited in PLAYTONIA Practice servers.");
		} else {
			
			return;
		}
	}
}


public void OnClientDisconnect(client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if (!ActiveKickStatus[client] && RegisterStatus[client] == 0 || RegisterStatus[client] == 1 && !IsFakeClient(client))
	{
		char FTime[30];
		FormatTime(FTime[0], sizeof(FTime), "%d%m%Y", GetTime());
		int timer;
		timer = TimeLeft[client];
		char query[150];
		Format(query, QUERY_LENGTH, "UPDATE unregister_player SET exit_time='%s', time_left='%d',subscribed='%d' WHERE steam_id='%s'", FTime[0], timer, RegisterStatus[client], steamid64);
		Format(clientbuffer[client], 32, "%s", name);
		SQL_TQuery(DB, UpdateDB, query, client);
	}
	
	if (RegisterStatus[client] && !IsFakeClient(client))
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Registered client %s left the server.", name);
	
	if (ClTimer[client] != null)
	{
		KillTimer(ClTimer[client]);
		ClTimer[client] = null;
	}
}

public void UpdateDB(Handle owner, Handle hndl, char[] error, any client)
{
	if (hndl != INVALID_HANDLE)
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Unregistered client %s left the server. Values updated on the unregistered database.", clientbuffer[client]);
	else
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Unregistered client %s left the server, but time values couldn't be updated on database. SQL Error: %s", clientbuffer[client], error);
}

public void IsClientRegistered(int client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	char query1[150];
	
	Format(query1, QUERY_LENGTH, "SELECT steam_id,subscribe_int FROM log_nd_reg_userprofile WHERE steam_id='%s'", steamid64);
	
	SQL_TQuery(DB, IsRegisteredDB, query1, client);
}

public void IsRegisteredDB(Handle owner, Handle hndl, char[] error, any client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if (hndl != INVALID_HANDLE)
	{
		if (SQL_FetchRow(hndl))
		{
			int reg_status;
			//SQL_FetchInt(hndl,1,reg_status);
			reg_status = SQL_FetchInt(hndl, 1);
			if (reg_status == 1) {
				ReplyToCommand(client, "Client %s is REGISTERED but not subscribed member", name);
				RegisterStatus[client] = 1;
				//@naa
				
				Unsubscribed_timer[client] = CreateTimer(15.0, AddUnsubscribed, client);
			} else if (reg_status >= 2) {
				ReplyToCommand(client, "Client %s is REGISTERED and a subscribed or premium member..", name);
				LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s is REGISTERED and a subscribed or premium member on the Playtonia Database.", name);
				char query2[150];
				Format(query2, QUERY_LENGTH, "SELECT steam_id FROM unregister_player WHERE steam_id='%s'", steamid64);
				SQL_TQuery(DB, RegisteredDB, query2, client);
			}
		}
		else
		{
			ReplyToCommand(client, "Client %s is NOT registered on the Playtonia Database.", name);
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s is NOT registered on the Playtonia Database.", name);
			RegisterStatus[client] = 0;
		}
	}
	else
	{
		ReplyToCommand(client, "Client %s will be treated as unregistered player. SQL Error: %s", name, error);
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s will be treated as unregistered player. SQL Error: %s", name, error);
		RegisterStatus[client] = 0;
	}
}

public void RegisteredDB(Handle owner, Handle hndl, char[] error, any client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if (hndl != INVALID_HANDLE && SQL_FetchRow(hndl))
	{
		char query3[150];
		Format(query3, QUERY_LENGTH, "DELETE FROM unregister_player WHERE steam_id='%s'", steamid64);
		SQL_TQuery(DB, DeleteDB, query3, client);
	}
	else
	{
		ReplyToCommand(client, "Either client %s is not in unregistered database or SQL Error. %s", name, error);
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Either client %s is not in unregistered database or SQL Error. %s", name, error);
	}
	RegisterStatus[client] = 2;
}

public void DeleteDB(Handle owner, Handle hndl, char[] error, any client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if (hndl != INVALID_HANDLE)
	{
		ReplyToCommand(client, "Client %s deleted from unregistered players database as they have registered themselves on the Playtonia database.", name);
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s deleted from unregistered players database as they have registered themselves on the Playtonia database.", name);
	}
	else
	{
		ReplyToCommand(client, "Unable to remove registered client %s from unregistered_players database. SQL Error: %s", name, error);
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Unable to remove registered client %s from unregistered_players database. SQL Error: %s", name, error);
	}
}

public void ClientUnregistered(int client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	char query[150];
	
	Format(query, QUERY_LENGTH, "SELECT * FROM unregister_player WHERE steam_id='%s'", steamid64);
	
	SQL_TQuery(DB, UnregisteredDB, query, client);
}

public void UnregisteredDB(Handle owner, Handle hndl, char[] error, any client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if (hndl != INVALID_HANDLE)
	{
		if (SQL_FetchRow(hndl))
		{
			ReplyToCommand(client, "Client %s is present in the unregistered users database.", name);
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s is present in the unregistered users database.", name);
			char exit_time[20], time_left[10];
			int subscribe;
			char currenttime[20];
			FormatTime(currenttime[0], sizeof(currenttime), "%d%m%Y", GetTime());
			SQL_FetchString(hndl, 1, exit_time, sizeof(exit_time));
			SQL_FetchString(hndl, 2, time_left, sizeof(time_left));
			//SQL_FetchInt(hndl,3, subscribe, sizeof(subscribe));
			subscribe = SQL_FetchInt(hndl, 3);
			int timer;
			timer = StringToInt(time_left);
			
			if (IsClientConnected(client) && !IsFakeClient(client))
			{
				if (StrEqual(exit_time, currenttime[0], true) && timer <= 0 && subscribe == 1 || subscribe == 0)
				{
					PrintToServer("exit_time is '%s',current time is '%s' and timer value is %d", exit_time, currenttime[0], timer);
					ActiveKickStatus[client] = 1;
					LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has already reached limit for the day. Player will be kicked.", name);
					if (RegisterStatus[client] == 1) {
						KickClient(client, "Time's up for the day. Subscribe in @ beta.playtonia.com to play"); } else {
						KickClient(client, "Time's up for the day. Register @ beta.playtonia.com to play");
					}
				}
				else if (StrEqual(exit_time, currenttime[0], false))
				{
					ActiveKickStatus[client] = 0;
					if (subscribe == 1) {
						TimeLeft[client] = g_regtime.IntValue;
						ClTimer[client] = CreateTimer(60.0, UNSUBSCRIBED, client, TIMER_REPEAT);
						PrintToChatAll("UNSUBSCRIBED timer running.");
					} else if (subscribe == 0) {
						TimeLeft[client] = g_unregtime.IntValue;
						LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has %d minutes left for the day. Player will be auto-kicked after reaching limit.", name, timer);
						ClTimer[client] = CreateTimer(60.0, TimerCallBack, client, TIMER_REPEAT); }
				}
				IdOnRecord[client] = 1;
			}
		}
		else
		{
			if (IsClientConnected(client) && !IsFakeClient(client))
			{
				ReplyToCommand(client, "Client %s is a new player.", name);
				LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s is a new player.", name);
				IdOnRecord[client] = 0;
			}
		}
	}
	else
	{
		ReplyToCommand(client, "Client %s will be treated as new player. SQL Error: %s", name, error);
		LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s will be treated as new player. SQL Error: %s", name, error);
		IdOnRecord[client] = 0;
	}
}

public void ClientIsNew(int client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	char query[150]
	Format(query, QUERY_LENGTH, "INSERT into unregister_player(steam_id) VALUES ('%s')", steamid64);
	
	SQL_TQuery(DB, InsertDB, query, client);
}

public void InsertDB(Handle owner, Handle hndl, char[] error, any client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if (hndl != INVALID_HANDLE)
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			ReplyToCommand(client, "Client %s added to unregistered players database.", name);
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s added to unregistered players database.", name);
			ActiveKickStatus[client] = 0;
			TimeLeft[client] = g_unregtime.IntValue;
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has %d minutes left for the day. Player will be auto-kicked after reaching limit.", name, g_unregtime.IntValue);
			ClTimer[client] = CreateTimer(60.0, TimerCallBack, client, TIMER_REPEAT);
		}
	}
	else
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			ReplyToCommand(client, "Client %s couldn't be added to unregistered players database, either they already exist or SQL Error: %s", name, error);
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s couldn't be added to unregistered players database, either they already exist or SQL Error: %s", name, error);
			ActiveKickStatus[client] = 0;
			TimeLeft[client] = g_unregtime.IntValue;
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has %d minutes left for the day. Player will be auto-kicked after reaching limit.", name, g_unregtime.IntValue);
			ClTimer[client] = CreateTimer(60.0, TimerCallBack, client, TIMER_REPEAT);
		}
	}
}

public Action Command_Register(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_registerplayer <player_fullname>");
		return Plugin_Handled;
	}
	char name[96], buffer[96];
	int targets[65];
	GetCmdArg(1, name, sizeof(name));
	char url[128] = "http://164.132.204.30/server/index.html";
	bool cs = false;
	int count = ProcessTargetString(name, client, targets, sizeof(targets), 0, buffer, sizeof(buffer), cs);
	if (count <= 0)
		ReplyToCommand(client, "Target not found in player list. [SM] Usage: sm_registerplayer <player_fullname>");
	else for (int i = 0; i < count; i++)
	{
		ShowMOTDPanel(targets[i], "Playtonia in MOTD", url, MOTDPANEL_TYPE_URL);
	}
	return Plugin_Handled;
}

public Action Player_Register(int client, int args)
{
	char url[128] = "https://beta.playtonia.com/";
	ShowMOTDPanel(client, "Playtonia in MOTD", url, MOTDPANEL_TYPE_URL);
	return Plugin_Handled;
}

public Action TimerCallBack(Handle timer, any client)
{
	if (IsClientConnected(client) && !IsFakeClient(client)) {
		CS_SetClientClanTag(client, "[UNREGISTERED]");
	}
	TimeLeft[client]--;
	PrintToChat(client, " \x02You have %d minute(s) left today.", TimeLeft[client]);
	PrintToChat(client, " \x03Type \x04!register \x03on chat to register now.");
	PrintToChat(client, " \x09Reconnect after registration to enjoy unlimited practice.");
	if (TimeLeft[client] <= 0)
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			ClientRegister[client] = CreateTimer(15.0, Client_Register, client);
			Kick_Client[client] = CreateTimer(45.0, KickTheClient, client);
			ClTimer[client] = INVALID_HANDLE;
		}
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action Client_Register(Handle timer, any client)
{
	ClientRegister[client] = INVALID_HANDLE;
	if (IsClientConnected(client) && !IsFakeClient(client))
	{
		char url[128] = "http://164.132.204.30/server/index.html";
		ShowMOTDPanel(client, "Playtonia in MOTD", url, MOTDPANEL_TYPE_URL);
	}
}

public Action KickTheClient(Handle timer, any client)
{
	Kick_Client[client] = INVALID_HANDLE;
	
	if (IsClientConnected(client) && !IsFakeClient(client)) {
		KickClient(client, "Time's up for the day. Register @ beta.playtonia.com to play");
		ClTimer[client] = INVALID_HANDLE; }
}

public Action UNSUBSCRIBED(Handle timer, any client)
{
	//PrintToChatAll("inside UNSUBSCRIBED timer.");
	if (IsClientConnected(client) && !IsFakeClient(client)) {
		CS_SetClientClanTag(client, "[UNSUBSCRIBED]");
	}
	TimeLeft[client]--;
	PrintToChat(client, " \x02You have %d minute(s) left today.", TimeLeft[client]);
	PrintToChat(client, " \x09Subscribe to enjoy unlimited practice.");
	if (TimeLeft[client] <= 0)
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			ClientRegister[client] = CreateTimer(15.0, Client_Register, client);
			Kick_Client[client] = CreateTimer(45.0, KickTheClient, client);
			ClTimer[client] = INVALID_HANDLE;
			
		}
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action AddUnsubscribed(Handle timer, any client) {
	Unsubscribed_timer[client] = INVALID_HANDLE;
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	char query[150];
	int sub = 1;
	Format(query, QUERY_LENGTH, "INSERT into unregister_player(steam_id,subscribed) VALUES ('%s','%d')", steamid64, sub);
	SQL_TQuery(DB, InsertDBUnsub, query, client);
}

public void InsertDBUnsub(Handle owner, Handle hndl, char[] error, any client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if (hndl != INVALID_HANDLE)
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			ReplyToCommand(client, "Client %s added to unregistered players database.", name);
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s added to unregistered players database.", name);
			ActiveKickStatus[client] = 0;
			TimeLeft[client] = g_regtime.IntValue;
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has %d minutes left for the day. Player will be auto-kicked after reaching limit.", name, g_regtime.IntValue);
			ClTimer[client] = CreateTimer(60.0, UNSUBSCRIBED, client, TIMER_REPEAT);
		}
	}
	else
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			ReplyToCommand(client, "Client %s couldn't be added to unregistered players database, either they already exist or SQL Error: %s", name, error);
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s couldn't be added to unregistered players database, either they already exist or SQL Error: %s", name, error);
			ActiveKickStatus[client] = 0;
			TimeLeft[client] = g_regtime.IntValue;
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has %d minutes left for the day. Player will be auto-kicked after reaching limit.", name, g_regtime.IntValue);
			ClTimer[client] = CreateTimer(60.0, UNSUBSCRIBED, client, TIMER_REPEAT);
		}
	}
}

/*public Action UPDATEEXIT(Handle timer, any client){
	Unsubscribed_timer[client] = INVALID_HANDLE;
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	char query[150];
	char exit_time[30];
	FormatTime(exit_time[0],sizeof(exit_time),"%d%m%Y",GetTime());
	Format(query, QUERY_LENGTH, "UPDATE into unregister_player (exit_time,time_left) VALUES ('%s','%d')", exit_time[30],TimeLeft[client]);
	SQL_TQuery(DB, UPDATEDBEXIT , query, client);	
}

public void UPDATEDBEXIT(Handle owner, Handle hndl, char[] error, any client)
{
	char steamid64[64], name[64];
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
	
	if(hndl != INVALID_HANDLE)
	{
		if(IsClientConnected(client) && !IsFakeClient(client))
		{
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s updated the timeleft unregistered players database.", name);
			ActiveKickStatus[client]=0;
			TimeLeft[client]=0;
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has %d minutes left for the day. Player will be auto-kicked after reaching limit.", name,g_regtime.IntValue);
			ClTimer[client] = CreateTimer(60.0, UNSUBSCRIBED, client, TIMER_REPEAT);
		}
	}
	else
	{
		if(IsClientConnected(client) && !IsFakeClient(client))
		{
			ReplyToCommand(client, "Client %s couldn't be added to unregistered players database, either they already exist or SQL Error: %s", name, error);
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s couldn't be added to unregistered players database, either they already exist or SQL Error: %s", name, error);
			ActiveKickStatus[client]=0;
			TimeLeft[client]=0;
			LogToFile("addons/sourcemod/logs/PlaytoniaClientLog.log", "Client %s has %d minutes left for the day. Player will be auto-kicked after reaching limit.", name,g_regtime.IntValue);
			ClTimer[client] = CreateTimer(60.0, UNSUBSCRIBED, client, TIMER_REPEAT);
		}
	}
} */


