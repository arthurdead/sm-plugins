#include <sourcemod>
#include <vgui_watcher>

//#define DEBUG

#define TF2_MAXPLAYERS 33

static int player_menu_open_num[TF2_MAXPLAYERS+1];
static int player_menu_close_num[TF2_MAXPLAYERS+1];
static player_vgui_state player_vgui[TF2_MAXPLAYERS+1];

static GlobalForward fwd_player_opened_vgui;
static GlobalForward fwd_player_closed_vgui;
static GlobalForward fwd_player_closing_class_vgui;
static GlobalForward fwd_player_opening_vgui;

static int native_player_current_vgui(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return player_vgui[client]
}

static int native_player_is_opening_vgui(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return (player_vgui[client] == player_vgui_none && player_menu_close_num[client] == 1 && player_menu_open_num[client] == 0);
}

static int native_player_is_closing_class_vgui(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return (player_vgui[client] == player_vgui_class && player_menu_close_num[client] == 1 && player_menu_open_num[client] == 0);
}

static int native_reset_player_vgui(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	if(player_vgui[client] != player_vgui_none) {
		Call_StartForward(fwd_player_closed_vgui);
		Call_PushCell(client);
		Call_PushCell(player_vgui[client]);
		Call_Finish();
	}

	player_menu_open_num[client] = 0;
	player_menu_close_num[client] = 0;
	player_vgui[client] = player_vgui_none;

	return 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	RegPluginLibrary("vgui_watcher");

	CreateNative("player_current_vgui", native_player_current_vgui);
	CreateNative("player_is_opening_vgui", native_player_is_opening_vgui);
	CreateNative("player_is_closing_class_vgui", native_player_is_closing_class_vgui);

	CreateNative("reset_player_vgui", native_reset_player_vgui);

	fwd_player_opened_vgui = new GlobalForward("player_opened_vgui", ET_Ignore, Param_Cell, Param_Cell);
	fwd_player_closed_vgui = new GlobalForward("player_closed_vgui", ET_Ignore, Param_Cell, Param_Cell);
	fwd_player_closing_class_vgui = new GlobalForward("player_closing_class_vgui", ET_Ignore, Param_Cell);
	fwd_player_opening_vgui = new GlobalForward("player_opening_vgui", ET_Ignore, Param_Cell);

	return APLRes_Success;
}

public void OnPluginStart()
{
	AddCommandListener(command_menu, "menuopen");
	AddCommandListener(command_menu, "menuclosed");

	AddCommandListener(command_team, "changeteam");
	AddCommandListener(command_team, "jointeam");
	AddCommandListener(command_team, "jointeam_nomenus");
	AddCommandListener(command_team, "join_team");
}

public void OnClientDisconnect(int client)
{
	player_menu_open_num[client] = 0;
	player_menu_close_num[client] = 0;
	player_vgui[client] = player_vgui_none;
}

static Action command_team(int client, const char[] command, int args)
{
	if(player_vgui[client] == player_vgui_team) {
		player_menu_open_num[client] = 0;
		player_menu_close_num[client] = 0;
		player_vgui[client] = player_vgui_none;
		Call_StartForward(fwd_player_closed_vgui);
		Call_PushCell(client);
		Call_PushCell(player_vgui_team);
		Call_Finish();
	#if defined DEBUG
		PrintToServer("closed team menu");
	#endif
	}
	return Plugin_Continue;
}

static Action command_menu(int client, const char[] command, int args)
{
#if defined DEBUG
	PrintToServer("%s", command);
#endif

	if(StrEqual(command, "menuclosed")) {
		++player_menu_close_num[client];
		if(player_menu_close_num[client] == 2 && player_menu_open_num[client] == 0) {
			player_menu_open_num[client] = 0;
			player_menu_close_num[client] = 0;
			if(player_vgui[client] == player_vgui_class) {
				player_vgui[client] = player_vgui_none;
				Call_StartForward(fwd_player_closed_vgui);
				Call_PushCell(client);
				Call_PushCell(player_vgui_class);
				Call_Finish();
			#if defined DEBUG
				PrintToServer("closed class menu");
			#endif
			} else {
				player_vgui[client] = player_vgui_team;
				Call_StartForward(fwd_player_opened_vgui);
				Call_PushCell(client);
				Call_PushCell(player_vgui_team);
				Call_Finish();
			#if defined DEBUG
				PrintToServer("opened team menu");
			#endif
			}
		} else if(player_menu_close_num[client] == 1 && player_menu_open_num[client] == 0) {
			if(player_vgui[client] == player_vgui_none) {
				Call_StartForward(fwd_player_opening_vgui);
				Call_PushCell(client);
				Call_Finish();
			#if defined DEBUG
				PrintToServer("opening menu");
			#endif
			} else if(player_vgui[client] == player_vgui_class) {
				Call_StartForward(fwd_player_closing_class_vgui);
				Call_PushCell(client);
				Call_Finish();
			#if defined DEBUG
				PrintToServer("closing class menu");
			#endif
			}
		}
	} else if(StrEqual(command, "menuopen")) {
		++player_menu_open_num[client];
		if(player_menu_open_num[client] == 1 && player_menu_close_num[client] == 1) {
			player_vgui[client] = player_vgui_class;
			player_menu_open_num[client] = 0;
			player_menu_close_num[client] = 0;
			Call_StartForward(fwd_player_opened_vgui);
			Call_PushCell(client);
			Call_PushCell(player_vgui_class);
			Call_Finish();
		#if defined DEBUG
			PrintToServer("opened class menu");
		#endif
		}
	}

	return Plugin_Continue;
}