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
		if(fwd_player_closed_vgui.FunctionCount > 0) {
			Call_StartForward(fwd_player_closed_vgui);
			Call_PushCell(client);
			Call_PushCell(player_vgui[client]);
			Call_Finish();
		}
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

	AddCommandListener(command_class, "changeclass");
	AddCommandListener(command_class, "joinclass");
	AddCommandListener(command_class, "join_class");

	AddCommandListener(command_team, "changeteam");
	AddCommandListener(command_team, "jointeam");
	AddCommandListener(command_team, "jointeam_nomenus");
	AddCommandListener(command_team, "join_team");

	HookUserMessage(GetUserMessageId("VGUIMenu"), VGUIMenu);

	//TODO!!!! CTFPlayer::m_bIsClassMenuOpen
}

#define PANEL_CLASS_BLUE "class_blue"
#define PANEL_CLASS_RED "class_red"
#define PANEL_CLASS "class"
#define PANEL_TEAM "team"

static Action VGUIMenu(UserMsg msg_id, Handle msg, const int[] players, int playersNum, bool reliable, bool init)
{
	BfRead read = view_as<BfRead>(msg);

	char name[32];
	read.ReadString(name, sizeof(name));

	bool show = read.ReadByte() != 0;

#if defined DEBUG
	PrintToServer("VGUIMenu %s %i", name, show);
#endif

	if(StrEqual(name, PANEL_TEAM)) {
		for(int i = 0; i < playersNum; ++i) {
			int client = players[i];

			if(show) {
				
			} else {
				
			}
		}
	} else if(StrEqual(name, PANEL_CLASS_BLUE) ||
				StrEqual(name, PANEL_CLASS_RED) ||
				StrEqual(name, PANEL_CLASS)) {
		for(int i = 0; i < playersNum; ++i) {
			int client = players[i];

			if(show) {
				
			} else {
				
			}
		}
	}

	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	player_menu_open_num[client] = 0;
	player_menu_close_num[client] = 0;
	player_vgui[client] = player_vgui_none;
}

static Action command_class(int client, const char[] command, int args)
{
#if defined DEBUG
	PrintToServer("command_class %s", command);
#endif

	return Plugin_Continue;
}

static Action command_team(int client, const char[] command, int args)
{
#if defined DEBUG
	PrintToServer("command_team %s", command);
#endif

	if(player_vgui[client] == player_vgui_team) {
		player_menu_open_num[client] = 0;
		player_menu_close_num[client] = 0;
		player_vgui[client] = player_vgui_none;
		if(fwd_player_closed_vgui.FunctionCount > 0) {
			Call_StartForward(fwd_player_closed_vgui);
			Call_PushCell(client);
			Call_PushCell(player_vgui_team);
			Call_Finish();
		}
	}

	return Plugin_Continue;
}

static Action command_menu(int client, const char[] command, int args)
{
#if defined DEBUG
	PrintToServer("command_menu %s", command);
#endif

	if(StrEqual(command, "menuclosed")) {
		++player_menu_close_num[client];
		if(player_menu_close_num[client] == 2 && player_menu_open_num[client] == 0) {
			player_menu_open_num[client] = 0;
			player_menu_close_num[client] = 0;
			if(player_vgui[client] == player_vgui_class) {
				player_vgui[client] = player_vgui_none;
				if(fwd_player_closed_vgui.FunctionCount > 0) {
					Call_StartForward(fwd_player_closed_vgui);
					Call_PushCell(client);
					Call_PushCell(player_vgui_class);
					Call_Finish();
				}
			} else {
				player_vgui[client] = player_vgui_team;
				if(fwd_player_opened_vgui.FunctionCount > 0) {
					Call_StartForward(fwd_player_opened_vgui);
					Call_PushCell(client);
					Call_PushCell(player_vgui_team);
					Call_Finish();
				}
			}
		} else if(player_menu_close_num[client] == 1 && player_menu_open_num[client] == 0) {
			if(player_vgui[client] == player_vgui_none) {
				if(fwd_player_opening_vgui.FunctionCount > 0) {
					Call_StartForward(fwd_player_opening_vgui);
					Call_PushCell(client);
					Call_Finish();
				}
			} else if(player_vgui[client] == player_vgui_class) {
				if(fwd_player_closing_class_vgui.FunctionCount > 0) {
					Call_StartForward(fwd_player_closing_class_vgui);
					Call_PushCell(client);
					Call_Finish();
				}
			}
		}
	} else if(StrEqual(command, "menuopen")) {
		++player_menu_open_num[client];
		if(player_menu_open_num[client] == 1 && player_menu_close_num[client] == 1) {
			player_vgui[client] = player_vgui_class;
			player_menu_open_num[client] = 0;
			player_menu_close_num[client] = 0;
			if(fwd_player_opened_vgui.FunctionCount > 0) {
				Call_StartForward(fwd_player_opened_vgui);
				Call_PushCell(client);
				Call_PushCell(player_vgui_class);
				Call_Finish();
			}
		}
	}

	return Plugin_Continue;
}