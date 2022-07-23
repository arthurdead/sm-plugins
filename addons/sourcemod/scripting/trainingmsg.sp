#include <sourcemod>
#include <sdktools>
#include <proxysend>
#include <tf2_stocks>
#include <trainingmsg>

#define INT_STR_MAX 4

bool msg_enabled[MAXPLAYERS+1];

TrainingMsgFlags msg_flags[MAXPLAYERS+1] = {TMSG_NOFLAGS, ...};

#define MsgHasContinue(%1) (!!(msg_flags[%1] & TMSG_HAS_CONTINUE))

bool has_continued[MAXPLAYERS+1];
int num_enabled;
bool gamerules_hooked;
bool g_bLateLoaded;
int player_wants_vgui[MAXPLAYERS+1];
Handle player_vgui_timer[MAXPLAYERS+1];
int current_player_menu[MAXPLAYERS+1] = {-1, ...};

char player_last_msg[MAXPLAYERS+1][TRAINING_MSG_MAX_LEN];

UserMsg TrainingObjective = INVALID_MESSAGE_ID;
UserMsg TrainingMsg = INVALID_MESSAGE_ID;

int tf_gamerules = -1;
int m_bIsInTrainingOffset = -1;
int m_bIsTrainingHUDVisibleOffset = -1;
int m_bIsWaitingForTrainingContinueOffset = -1;

//ConVar tf_training_client_message;

ConVar sv_stressbots;

ArrayList TraningMsgMenus;
ArrayList TraningMsgMenusFunctions;
ArrayList TraningMsgPluginMap;

GlobalForward hOnContinued;

enum struct TraningMsgMenuFunction
{
	Handle plugin;
	Function func;
	any data;
}

enum struct TraningMsgMenuInfo
{
	Panel pan;
	ArrayList items;
	char title[TRAINING_MSG_MAX_WIDTH];
	int curritem;
	int keys;
	TrainingMsgFlags flags;
}

ConVar sm_rsay_time = null;

public void OnPluginStart()
{
	TraningMsgMenus = new ArrayList(sizeof(TraningMsgMenuInfo));
	TraningMsgMenusFunctions = new ArrayList(sizeof(TraningMsgMenuFunction));
	TraningMsgPluginMap = new ArrayList(2);

	TrainingObjective = GetUserMessageId("TrainingObjective");
	TrainingMsg = GetUserMessageId("TrainingMsg");

	m_bIsInTrainingOffset = FindSendPropInfo("CTFGameRulesProxy", "m_bIsInTraining");
	m_bIsTrainingHUDVisibleOffset = FindSendPropInfo("CTFGameRulesProxy", "m_bIsTrainingHUDVisible");
	m_bIsWaitingForTrainingContinueOffset = FindSendPropInfo("CTFGameRulesProxy", "m_bIsWaitingForTrainingContinue");

	AddCommandListener(command_menu, "menuopen");
	AddCommandListener(command_menu, "menuclosed");
	AddCommandListener(command_continue, "training_continue");

	//tf_training_client_message = FindConVar("tf_training_client_message");

	sv_stressbots = FindConVar("sv_stressbots");

	HookEvent("player_spawn", player_spawn);

	sm_rsay_time = CreateConVar("sm_rsay_time", "10.0");

	RegAdminCmd("sm_rsay", sm_rsay, ADMFLAG_GENERIC);
	RegAdminCmd("sm_rsay2", sm_rsay2, ADMFLAG_GENERIC);
	RegAdminCmd("sm_rbug", sm_rbug, ADMFLAG_GENERIC);
	//RegAdminCmd("sm_rvote", sm_rvote, ADMFLAG_GENERIC);
}

/*void VoteHandler(TrainingMsgMenuAction action, int client, int param1, any menu_data, any item_data)
{
	if(action == TrainingMsgMenuAction_Select) {
		ArrayList result = view_as<ArrayList>(menu_data);
		int idx = param1-1;
		int curr = result.Get(idx);
		++curr;
		result.Set(idx, curr);
	}
}

Action Timer_ShowVoteResult(Handle timer, any data)
{
	ArrayList result = view_as<ArrayList>(data);
	for(int i = 0, len = result.Length; i < len; ++i) {

	}
	delete result;
	return Plugin_Handled;
}

Action sm_rvote(int client, int args)
{
	if(args < 2) {
		ReplyToCommand(client, "[SM] sm_rvote <title> <option1> <option2> etc...");
		return Plugin_Handled;
	}

	if(args >= (TRAINING_MSG_MAX_HEIGHT+2)) {
		ReplyToCommand(client, "[SM] only %i options allowed", TRAINING_MSG_MAX_HEIGHT);
		return Plugin_Handled;
	}

	char title[TRAINING_MSG_MAX_WIDTH];
	GetCmdArg(1, title, TRAINING_MSG_MAX_WIDTH);

	ArrayList result = new ArrayList();

	TrainingMsgMenu menu = TrainingMsgMenu(VoteHandler, result);
	menu.SetTitle(title);

	for(int i = 0; i < TRAINING_MSG_MAX_HEIGHT; ++i) {
		int idx = i+2;
		if(args >= idx) {
			GetCmdArg(idx, title, TRAINING_MSG_MAX_WIDTH);
			menu.AddItem(title);
			//result.Set(i, 0);
		} else {
			break;
		}
	}

	//menu.Flags = TMSG_CONTINUE_AUTOREMOVE;

	menu.SendToClient(client, TRAININGMSGMENU_TIME_FOREVER);

	//CreateTimer(2.0, Timer_ShowVoteResult, result);

	return Plugin_Handled;
}*/

Handle rsay_timer = null;

Action sm_rbug(int client, int args)
{
	if(rsay_timer != null) {
		KillTimer(rsay_timer);
	}
	rsay_timer = null;

	DisableAll();

	return Plugin_Handled;
}

void DoRSay(int client, int args, bool has_continue)
{
	if(args < 1) {
		ReplyToCommand(client, "[SM] sm_rsay <msg>");
		return;
	}

	char msg[TRAINING_MSG_MAX_LEN];
	GetCmdArgString(msg, TRAINING_MSG_MAX_LEN);

	CleanTrainingMessageText(msg, TRAINING_MSG_MAX_LEN);

	char msg_newline[TRAINING_MSG_MAX_LEN];
	int len = strlen(msg);
	WarpTrainingMessageText(msg_newline, msg, len);

	char title[TRAINING_MSG_MAX_WIDTH];
	Format(title, TRAINING_MSG_MAX_WIDTH, "%N", client);

	TrainingMsgFlags flags = has_continue ? TMSG_CONTINUE_AUTOREMOVE : TMSG_NOFLAGS;

	int numClients = 0;
	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(!HandleAllLoop(i, flags)) {
			continue;
		}
		clients[numClients++] = i;
	}

	SendToAllHelper(clients, numClients, title, msg_newline, has_continue);

	if(!has_continue) {
		if(rsay_timer != null) {
			KillTimer(rsay_timer);
		}
		rsay_timer = CreateTimer(sm_rsay_time.FloatValue, Timer_RemoveRsay, 0, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action sm_rsay2(int client, int args)
{
	DoRSay(client, args, true);
	return Plugin_Handled;
}

Action sm_rsay(int client, int args)
{
	DoRSay(client, args, false);
	return Plugin_Handled;
}

Action Timer_RemoveRsay(Handle timer, any data)
{
	DisableAll();
	rsay_timer = null;

	return Plugin_Continue;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("IsTrainingMessageVisibleToClient", IsVisibleClient);
	CreateNative("IsTrainingMessageVisibleToAll", IsVisibleAll);

	CreateNative("HasPlayerContinuedTrainingMessage", HasContinued);
	CreateNative("TrainingMessageHasContinue", HasContinue);

	CreateNative("RemoveContinueFromTrainingMessage", RemoveContinueMsg);
	CreateNative("RemoveContinueFromClient", RemoveContinueClient);

	CreateNative("SendTrainingMessageToClients", SendToClients);
	CreateNative("SendTrainingMessageToAll", SendToAll);
	CreateNative("SendTrainingMessageToClient", SendToClient);

	CreateNative("RemoveTrainingMessageFromAll", RemoveFromAll);
	CreateNative("RemoveTrainingMessageFromClients", RemoveFromClients);

	CreateNative("ChangeTrainingMessageTitleClients", ChangeTitle);
	CreateNative("ChangeTrainingMessageTextClients", ChangeText);

	CreateNative("ChangeTrainingMessageTitleAll", ChangeTitleAll);
	CreateNative("ChangeTrainingMessageTextAll", ChangeTextAll);

	CreateNative("TrainingMsgMenu.TrainingMsgMenu", TrainingMsgMenuCtor);
	CreateNative("TrainingMsgMenu.SetTitle", TrainingMsgMenuSetTitle);
	CreateNative("TrainingMsgMenu.DrawItem", TrainingMsgMenuDrawItem);
	CreateNative("TrainingMsgMenu.AddItem", TrainingMsgMenuAddItem);
	CreateNative("TrainingMsgMenu.ExitButton.set", TrainingMsgMenuExitButton);
	CreateNative("TrainingMsgMenu.Flags.set", TrainingMsgMenuFlags);
	CreateNative("TrainingMsgMenu.SendToClient", TrainingMsgMenuSendToClient);

	hOnContinued = new GlobalForward("OnPlayerContinuedTrainingMessage", ET_Ignore, Param_Cell);

	RegPluginLibrary("trainingmsg");

	g_bLateLoaded = late;
	return APLRes_Success;
}

void RemoveTrainingMsgMenuFuncs(int index, Handle plugin)
{
	int idx = TraningMsgPluginMap.FindValue(plugin);
	if(idx != -1) {
		TraningMsgPluginMap.Erase(idx);
	}

	TraningMsgMenusFunctions.Erase(index);
}

bool CancelTrainingMsgMenu(int client, int reason = TrainingMsgMenuCancel_Interrupted)
{
	int index = current_player_menu[client];
	current_player_menu[client] = -1;
	if(index != -1) {
		TraningMsgMenuFunction menufunc;
		TraningMsgMenusFunctions.GetArray(index, menufunc, sizeof(TraningMsgMenuFunction));

		Call_StartFunction(menufunc.plugin, menufunc.func);
		Call_PushCell(TrainingMsgMenuAction_Cancel);
		Call_PushCell(client);
		Call_PushCell(reason);
		Call_PushCell(menufunc.data);
		Call_PushCell(0);
		Call_Finish();

		RemoveTrainingMsgMenuFuncs(index, menufunc.plugin);
		return true;
	}
	return false;
}

int GlobalTrainingMsgMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select && param2 == 10) {
		action = MenuAction_Cancel;
		param2 = MenuCancel_Exit;
	}

	switch(action) {
		case MenuAction_Select: {
			int index = current_player_menu[param1];
			current_player_menu[param1] = -1;
			DisableClient(param1, _, false);

			if(index != -1) {
				TraningMsgMenuFunction menufunc;
				TraningMsgMenusFunctions.GetArray(index, menufunc, sizeof(TraningMsgMenuFunction));

				Call_StartFunction(menufunc.plugin, menufunc.func);
				Call_PushCell(TrainingMsgMenuAction_Select);
				Call_PushCell(param1);
				Call_PushCell(param2);
				Call_PushCell(menufunc.data);
				Call_PushCell(0);
				Call_Finish();

				RemoveTrainingMsgMenuFuncs(index, menufunc.plugin);
			}
		}
		case MenuAction_Cancel: {
			int index = current_player_menu[param1];
			current_player_menu[param1] = -1;
			DisableClient(param1, _, false);

			if(index != -1) {
				TraningMsgMenuFunction menufunc;
				TraningMsgMenusFunctions.GetArray(index, menufunc, sizeof(TraningMsgMenuFunction));

				Call_StartFunction(menufunc.plugin, menufunc.func);
				Call_PushCell(TrainingMsgMenuAction_Cancel);
				Call_PushCell(param1);

				switch(param2) {
					case MenuCancel_Disconnected: { Call_PushCell(TrainingMsgMenuCancel_Disconnected); }
					case MenuCancel_Interrupted: { Call_PushCell(TrainingMsgMenuCancel_Interrupted); }
					case MenuCancel_Exit: { Call_PushCell(TrainingMsgMenuCancel_Exit); }
					case MenuCancel_Timeout: { Call_PushCell(TrainingMsgMenuCancel_Timeout); }
					default: { Call_PushCell(-1); }
				}

				Call_PushCell(menufunc.data);
				Call_PushCell(0);
				Call_Finish();

				RemoveTrainingMsgMenuFuncs(index, menufunc.plugin);
			}
		}
		case MenuAction_End: {
			//????
		}
	}
	return 0;
}

int TrainingMsgMenuCtor(Handle plugin, int params)
{
	TraningMsgMenuInfo menuinfo;
	menuinfo.title[0] = '\0';
	menuinfo.keys |= (1 << 9);
	menuinfo.pan = new Panel();
	menuinfo.pan.DrawText("");
	menuinfo.pan.SetKeys(menuinfo.keys);
	menuinfo.items = new ArrayList(ByteCountToCells(TRAINING_MSG_MAX_WIDTH));
	menuinfo.flags = TMSG_NOFLAGS;
	menuinfo.curritem = 0;

	TraningMsgMenuFunction menufunc;
	menufunc.func = GetNativeFunction(1);
	menufunc.plugin = plugin;
	menufunc.data = GetNativeCell(2);

	int idx = TraningMsgMenusFunctions.PushArray(menufunc, sizeof(TraningMsgMenuFunction));
	idx = TraningMsgPluginMap.Push(idx);
	TraningMsgPluginMap.Set(idx, menufunc.plugin);

	return TraningMsgMenus.PushArray(menuinfo, sizeof(TraningMsgMenuInfo));
}

void AddItemToString(ArrayList items, int keys, int i, int maxlen, char[] msg, int len, bool newline, bool pipe)
{
	char[] item = new char[maxlen];
	items.GetString(i, item, maxlen);

	if(keys & (1 << i)) {
		char num[INT_STR_MAX];
		IntToString(i+1, num, INT_STR_MAX);
		StrCat(msg, len, num);
		StrCat(msg, len, ". ");
	}

	StrCat(msg, len, item);

	if(pipe) {
		StrCat(msg, len, " | ");
	}

	if(newline) {
		StrCat(msg, len, "\n");
	}
}

int TrainingMsgMenuSendToClient(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	int client = GetNativeCell(2);

	if(!IsClientValid(client)) {
		return 0;
	}

	int time = GetNativeCell(3);

	TraningMsgMenuInfo menuinfo;
	TraningMsgMenus.GetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	bool ret = menuinfo.pan.Send(client, GlobalTrainingMsgMenuHandler, time);
	if(ret) {
		CancelTrainingMsgMenu(client);
		EnableClient(client);
		msg_flags[client] = menuinfo.flags;

		current_player_menu[client] = index;

		int clients[1];
		clients[0] = client;

		int block = menuinfo.items.BlockSize;
		int itemnum = menuinfo.items.Length;
		int len = (itemnum * block) + (3 * TRAINING_MSG_MAX_WIDTH);
		char[] msg = new char[len];

		if(itemnum > TRAINING_MSG_MAX_HEIGHT) {
			itemnum = TRAINING_MSG_MAX_HEIGHT;
		}

		for(int i = 0; i < itemnum; ++i) {
			AddItemToString(menuinfo.items, menuinfo.keys, i, TRAINING_MSG_MAX_WIDTH, msg, len, true, false);
		}

		SendToClientsHelper(clients, sizeof(clients), menuinfo.title, msg);
	}

	delete menuinfo.pan;
	delete menuinfo.items;

	TraningMsgMenus.Erase(index);

	return ret;
}

int TrainingMsgMenuExitButton(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo menuinfo;
	TraningMsgMenus.GetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	if(GetNativeCell(2)) {
		menuinfo.keys |= (1 << 9);
	} else {
		menuinfo.keys &= ~(1 << 9);
	}
	menuinfo.pan.SetKeys(menuinfo.keys);

	TraningMsgMenus.SetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	return 0;
}

int TrainingMsgMenuFlags(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo menuinfo;
	TraningMsgMenus.GetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	menuinfo.flags = GetNativeCell(2);

	TraningMsgMenus.SetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	return 0;
}

int TrainingMsgMenuAddItem(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo menuinfo;
	TraningMsgMenus.GetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	if(menuinfo.curritem == TRAINING_MSG_MAX_HEIGHT) {
		return 0;
	}

	int length = 0;
	GetNativeStringLength(2, length);
	char[] title = new char[++length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	menuinfo.keys |= (1 << menuinfo.curritem);
	menuinfo.pan.SetKeys(menuinfo.keys);
	++menuinfo.curritem;

	menuinfo.items.PushString(title);

	TraningMsgMenus.SetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	//any data = GetNativeCell(3);

	return 1;
}

int TrainingMsgMenuDrawItem(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo menuinfo;
	TraningMsgMenus.GetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	if(menuinfo.curritem == TRAINING_MSG_MAX_HEIGHT) {
		return 0;
	}

	int length = 0;
	GetNativeStringLength(2, length);
	char[] title = new char[++length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	++menuinfo.curritem;
	menuinfo.items.PushString(title);

	TraningMsgMenus.SetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	return 1;
}

int TrainingMsgMenuSetTitle(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo menuinfo;
	TraningMsgMenus.GetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	int length = 0;
	GetNativeStringLength(2, length);
	char[] title = new char[++length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	strcopy(menuinfo.title, TRAINING_MSG_MAX_WIDTH, title);

	TraningMsgMenus.SetArray(index, menuinfo, sizeof(TraningMsgMenuInfo));

	return 0;
}

public void OnNotifyPluginUnloaded(Handle plugin)
{
	int idx = TraningMsgPluginMap.FindValue(plugin);
	if(idx != -1) {
		int index = TraningMsgPluginMap.Get(idx, 1);

		for(int j = 1; j <= MaxClients; ++j) {
			if(current_player_menu[j] == index) {
				DisableClient(j, _, false);
				current_player_menu[j] = -1;
			}
		}

		TraningMsgMenusFunctions.Erase(index);
	}
}

public void OnMapStart()
{
	if(g_bLateLoaded) {
		tf_gamerules = FindEntityByClassname(-1, "tf_gamerules");
		if(tf_gamerules == -1) {
			ThrowError("tf_gamerules was not found");
		}
	}
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		DisableClient(i);
	}
}

public void OnMapEnd()
{
	OnPluginEnd();

	tf_gamerules = -1;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_gamerules")) {
		if(tf_gamerules != -1) {
			ThrowError("multiple tf_gamerules");
		}

		tf_gamerules = entity;
	}
}

public void OnEntityDestroyed(int entity)
{
	if(entity == tf_gamerules) {
		tf_gamerules = -1;
	}
}

Action Timer_ResetWantsVgui(Handle timer, int client)
{
	client = GetClientOfUserId(client);
	if(client != -1) {
		player_vgui_timer[client] = null;
		player_wants_vgui[client] = 0;
	}
	return Plugin_Continue;
}

Action command_continue(int client, const char[] command, int args)
{
	if(msg_enabled[client] && MsgHasContinue(client)) {
		if(!!(msg_flags[client] & TMSG_REMOVE_ON_CONTINUE)) {
			DisableClient(client, _, true, TrainingMsgMenuCancel_Exit);
		} else {
			has_continued[client] = true;

			Call_StartForward(hOnContinued);
			Call_PushCell(client);
			Call_Finish();
		}
	}
	return Plugin_Continue;
}

Action command_menu(int client, const char[] command, int args)
{
	if(msg_enabled[client] || IsGloballyEnabled()) {
		if(StrEqual(command, "menuclosed")) {
			if(player_wants_vgui[client] >= 3) {
				--player_wants_vgui[client];
				if((player_wants_vgui[client]-3) == 1) {
					player_wants_vgui[client] = 0;
				}
			} else {
				if(player_wants_vgui[client]++ == 0) {
					player_vgui_timer[client] = CreateTimer(0.2, Timer_ResetWantsVgui, GetClientUserId(client));

					BfWrite usrmsg = view_as<BfWrite>(StartMessageOne("HudNotifyCustom", client));
					usrmsg.WriteString("You need to double-tap to change class.");
					usrmsg.WriteString("ico_notify_flag_moving");
					usrmsg.WriteByte(GetClientTeam(client));
					EndMessage();
				}
			}
		} else if(StrEqual(command, "menuopen")) {
			player_wants_vgui[client] *= 2;
		}
	}
	return Plugin_Continue;
}

Action HookIsTraining(int entity, const char[] prop, bool &value, int element, int client)
{
	if(msg_enabled[client]) {
		if(player_wants_vgui[client] != 0) {
			value = false;
		} else {
			value = true;
		}
	} else {
		value = false;
	}
	return Plugin_Changed;
}

Action HookIsContinue(int entity, const char[] prop, bool &value, int element, int client)
{
	if(msg_enabled[client] && MsgHasContinue(client)) {
		value = true;
	} else {
		value = false;
	}
	return Plugin_Changed;
}

void Unhook(bool value, bool has_continue)
{
	if(gamerules_hooked) {
		if(tf_gamerules == -1) {
			ThrowError("tf_gamerules was not found");
		}

		proxysend_unhook(tf_gamerules, "m_bIsInTraining", HookIsTraining);
		proxysend_unhook(tf_gamerules, "m_bIsTrainingHUDVisible", HookIsTraining);
		proxysend_unhook(tf_gamerules, "m_bIsWaitingForTrainingContinue", HookIsContinue);
		gamerules_hooked = false;
	}

	if(!value) {
		GameRules_SetProp("m_bIsInTraining", 0);
		GameRules_SetProp("m_bIsTrainingHUDVisible", 0);
		GameRules_SetProp("m_bIsWaitingForTrainingContinue", 0);
	}
}

void Hook()
{
	if(!gamerules_hooked) {
		if(tf_gamerules == -1) {
			ThrowError("tf_gamerules was not found");
		}

		proxysend_hook(tf_gamerules, "m_bIsInTraining", HookIsTraining, true);
		proxysend_hook(tf_gamerules, "m_bIsTrainingHUDVisible", HookIsTraining, true);
		proxysend_hook(tf_gamerules, "m_bIsWaitingForTrainingContinue", HookIsContinue, true);
		gamerules_hooked = true;
	}
}

void EnableClient(int client)
{
	player_wants_vgui[client] = 0;

	if(player_vgui_timer[client] != null) {
		KillTimer(player_vgui_timer[client]);
		player_vgui_timer[client] = null;
	}

	if(!msg_enabled[client]) {
		msg_enabled[client] = true;
		++num_enabled;
	}
}

int DisableClient(int client, bool send_empty = true, bool cancel_menu = true, int reason = TrainingMsgMenuCancel_Interrupted)
{
	player_wants_vgui[client] = 0;

	if(player_vgui_timer[client] != null) {
		KillTimer(player_vgui_timer[client]);
		player_vgui_timer[client] = null;
	}

	if(cancel_menu) {
		CancelTrainingMsgMenu(client, reason);
	}

	if(send_empty) {
		if(IsClientValid(client)) {
			int clients[1];
			clients[0] = client;
			SendUsrMsgHelper(clients, sizeof(clients), "", "");
		}
	}

	if(msg_enabled[client]) {
		msg_enabled[client] = false;
		msg_flags[client] = TMSG_NOFLAGS;
		has_continued[client] = false;
		player_last_msg[client][0] = '\0';
		--num_enabled;

		if(num_enabled == 0) {
			Unhook(false, false);
			return 2;
		}

		return 1;
	} else {
		return 0;
	}
}

void DisableAll()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(DisableClient(i) == 2) {
			break;
		}
	}
}

Action player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(msg_enabled[client]) {
		int clients[1];
		clients[0] = client;
		BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingMsg, clients, 1));
		usrmsg.WriteString(player_last_msg[client]);
		EndMessage();
	}

	return Plugin_Continue;
}

void SendUsrMsgHelper(int[] clients, int numClients, const char[] title, const char[] msg)
{
	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingObjective, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();

	usrmsg = view_as<BfWrite>(StartMessageEx(TrainingMsg, clients, numClients));
	usrmsg.WriteString(msg);
	EndMessage();

	for(int i = 0; i < numClients; ++i) {
		int client = clients[i];
		strcopy(player_last_msg[client], TRAINING_MSG_MAX_LEN, msg);
	}
}

void SendToClientsHelper(int[] clients, int numClients, const char[] title, const char[] msg)
{
	Hook();
	SendUsrMsgHelper(clients, numClients, title, msg);
}

void SendToAllHelper(int[] clients, int numClients, const char[] title, const char[] msg, bool has_continue)
{
	Hook();
	SendUsrMsgHelper(clients, numClients, title, msg);
}

bool IsGloballyEnabled()
{
	int m_bIsInTraining = GameRules_GetProp("m_bIsInTraining");
	int m_bIsTrainingHUDVisible = GameRules_GetProp("m_bIsTrainingHUDVisible");

	return (m_bIsInTraining && m_bIsTrainingHUDVisible);
}

int IsVisibleClient(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return (IsGloballyEnabled() || msg_enabled[client]);
}

int IsVisibleAll(Handle plugin, int params)
{
	return (IsGloballyEnabled() || num_enabled == MaxClients);
}

int HasContinued(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return has_continued[client];
}

int HasContinue(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return MsgHasContinue(client);
}

int RemoveContinueMsg(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	if(msg_enabled[client] && MsgHasContinue(client)) {
		msg_flags[client] &= ~(TMSG_HAS_CONTINUE|TMSG_REMOVE_ON_CONTINUE);
	}

	return 0;
}

int RemoveContinueClient(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	if(msg_enabled[client] && MsgHasContinue(client)) {
		has_continued[client] = false;
	}

	return 0;
}

int ChangeTitleAll(Handle plugin, int params)
{
	int numClients = 0;
	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientValid(i)) {
			continue;
		}
		if(IsGloballyEnabled() || msg_enabled[i]) {
			clients[numClients++] = i;
			if(CancelTrainingMsgMenu(i)) {
				//TODO!!! change msg
			}
		}
	}

	int length = 0;
	GetNativeStringLength(1, length);
	char[] title = new char[++length];
	GetNativeString(1, title, length);

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingObjective, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
	return 0;
}

int ChangeTextAll(Handle plugin, int params)
{
	int length = 0;
	GetNativeStringLength(1, length);
	char[] title = new char[++length];
	GetNativeString(1, title, length);

	int numClients = 0;
	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientValid(i)) {
			continue;
		}
		if(IsGloballyEnabled() || msg_enabled[i]) {
			clients[numClients++] = i;
			strcopy(player_last_msg[i], TRAINING_MSG_MAX_LEN, title);
			if(CancelTrainingMsgMenu(i)) {
				//TODO!!! change title
			}
		}
	}

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingMsg, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
	return 0;
}

int ChangeTitle(Handle plugin, int params)
{
	int numClients = GetNativeCell(2);

	int[] clients = new int[numClients];
	GetNativeArray(1, clients, numClients);

	for(int i = 0; i < numClients; ++i) {
		int client = clients[i];
		if(CancelTrainingMsgMenu(client)) {
			//TODO!!! change msg
		}
	}

	int length = 0;
	GetNativeStringLength(3, length);
	char[] title = new char[++length];
	GetNativeString(3, title, length);

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingObjective, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
	return 0;
}

int ChangeText(Handle plugin, int params)
{
	int numClients = GetNativeCell(2);

	int[] clients = new int[numClients];
	GetNativeArray(1, clients, numClients);

	int length = 0;
	GetNativeStringLength(3, length);
	char[] title = new char[++length];
	GetNativeString(3, title, length);

	for(int i = 0; i < numClients; ++i) {
		int client = clients[i];
		strcopy(player_last_msg[client], TRAINING_MSG_MAX_LEN, title);
		if(CancelTrainingMsgMenu(client)) {
			//TODO!!! change title
		}
	}

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingMsg, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
	return 0;
}

bool IsClientValid(int client)
{
	if(!IsClientInGame(client) ||
		(!sv_stressbots.BoolValue && (
		IsFakeClient(client) ||
		IsClientSourceTV(client) ||
		IsClientReplay(client)))) {
		return false;
	}

	return true;
}

int SendToClients(Handle plugin, int params)
{
	int numClients = GetNativeCell(2);

	int[] clients = new int[numClients];
	GetNativeArray(1, clients, numClients);

	int length = 0;
	GetNativeStringLength(3, length);
	char[] title = new char[++length];
	GetNativeString(3, title, length);

	length = 0;
	GetNativeStringLength(4, length);
	char[] msg = new char[++length];
	GetNativeString(4, msg, length);

	TrainingMsgFlags flags = GetNativeCell(5);

	for(int i = 0; i < numClients; ++i) {
		int client = clients[i];
		if(!HandleClientLoop(client, flags)) {
			continue;
		}
	}

	SendToClientsHelper(clients, numClients, title, msg);

	return 0;
}

bool HandleAllLoop(int i, TrainingMsgFlags flags)
{
	if(!IsClientValid(i)) {
		return false;
	}
	CancelTrainingMsgMenu(i);
	EnableClient(i);
	msg_flags[i] = flags;
	return true;
}

bool HandleClientLoop(int i, TrainingMsgFlags flags)
{
	if(!IsClientValid(i)) {
		return false;
	}
	CancelTrainingMsgMenu(i);
	EnableClient(i);
	msg_flags[i] = flags;
	return true;
}

int SendToAll(Handle plugin, int params)
{
	int length = 0;
	GetNativeStringLength(1, length);
	char[] title = new char[++length];
	GetNativeString(1, title, length);

	length = 0;
	GetNativeStringLength(2, length);
	char[] msg = new char[++length];
	GetNativeString(2, msg, length);

	TrainingMsgFlags flags = GetNativeCell(3);

	int numClients = 0;
	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(!HandleAllLoop(i, flags)) {
			continue;
		}
		clients[numClients++] = i;
	}

	bool has_continue = !!(flags & TMSG_HAS_CONTINUE);

	SendToAllHelper(clients, numClients, title, msg, has_continue);

	return 0;
}

int SendToClient(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	TrainingMsgFlags flags = GetNativeCell(4);

	if(!HandleClientLoop(client, flags)) {
		return 0;
	}

	int length = 0;
	GetNativeStringLength(2, length);
	char[] title = new char[++length];
	GetNativeString(2, title, length);

	length = 0;
	GetNativeStringLength(3, length);
	char[] msg = new char[++length];
	GetNativeString(3, msg, length);

	int clients[1];
	clients[0] = client;

	SendToClientsHelper(clients, sizeof(clients), title, msg);

	return 0;
}

int RemoveFromAll(Handle plugin, int params)
{
	DisableAll();

	return 0;
}

int RemoveFromClients(Handle plugin, int params)
{
	int numClients = GetNativeCell(2);

	int[] clients = new int[numClients];
	GetNativeArray(1, clients, numClients);

	for(int i = 0; i < numClients; ++i) {
		int client = clients[i];
		int ret = DisableClient(client);
		if(ret == 2) {
			return 0;
		}
	}

	return 0;
}

public void OnClientDisconnect(int client)
{
	DisableClient(client, _, false);
}