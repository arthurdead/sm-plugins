#include <sourcemod>
#include <sdktools>
#include <sendproxy>
#include <tf2_stocks>
#include <trainingmsg>

bool msg_enabled[MAXPLAYERS+1] = {false, ...};

TrainingMsgFlags msg_flags[MAXPLAYERS+1] = {TMSG_NOFLAGS, ...};

#define MsgHasContinue(%1) (!!(msg_flags[%1] & TMSG_HAS_CONTINUE))

bool has_continued[MAXPLAYERS+1] = {false, ...};
int num_enabled = 0;
bool gamerules_hooked = false;
bool g_bLateLoaded = false;
int player_wants_vgui[MAXPLAYERS+1] = {0, ...};
Handle player_vgui_timer[MAXPLAYERS+1] = {null, ...};
int current_player_menu[MAXPLAYERS+1] = {-1, ...};

UserMsg TrainingObjective = INVALID_MESSAGE_ID;
UserMsg TrainingMsg = INVALID_MESSAGE_ID;

int tf_gamerules = -1;
int m_bIsInTrainingOffset = -1;
int m_bIsTrainingHUDVisibleOffset = -1;
int m_bIsWaitingForTrainingContinueOffset = -1;

ConVar tf_training_client_message = null;
ConVar sm_trainingmsg_setprop = null;

ArrayList TraningMsgMenus = null;
ArrayList TraningMsgMenusFunctions = null;

GlobalForward hOnContinued = null;

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

TraningMsgMenuFunction tmpmenufunc;
TraningMsgMenuInfo tmpmenuinfo;

ConVar sm_rsay_time = null;

public void OnPluginStart()
{
	TraningMsgMenus = new ArrayList(sizeof(TraningMsgMenuInfo));
	TraningMsgMenusFunctions = new ArrayList(sizeof(TraningMsgMenuFunction));

	TrainingObjective = GetUserMessageId("TrainingObjective");
	TrainingMsg = GetUserMessageId("TrainingMsg");

	m_bIsInTrainingOffset = FindSendPropInfo("CTFGameRulesProxy", "m_bIsInTraining");
	m_bIsTrainingHUDVisibleOffset = FindSendPropInfo("CTFGameRulesProxy", "m_bIsTrainingHUDVisible");
	m_bIsWaitingForTrainingContinueOffset = FindSendPropInfo("CTFGameRulesProxy", "m_bIsWaitingForTrainingContinue");

	AddCommandListener(command_menu, "menuopen");
	AddCommandListener(command_menu, "menuclosed");
	AddCommandListener(command_continue, "training_continue");

	tf_training_client_message = FindConVar("tf_training_client_message");

	sm_trainingmsg_setprop = CreateConVar("sm_trainingmsg_setprop", "0");

	HookEvent("player_spawn", player_spawn);
	HookEvent("teamplay_round_start", teamplay_round_start);

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
	GetCmdArg(1, title, sizeof(title));

	ArrayList result = new ArrayList();

	TrainingMsgMenu menu = TrainingMsgMenu(VoteHandler, result);
	menu.SetTitle(title);

	for(int i = 0; i < TRAINING_MSG_MAX_HEIGHT; ++i) {
		int idx = i+2;
		if(args >= idx) {
			GetCmdArg(idx, title, sizeof(title));
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
	GetCmdArgString(msg, sizeof(msg));

	CleanTrainingMessageText(msg, sizeof(msg));

	char msg_newline[TRAINING_MSG_MAX_LEN];
	int len = strlen(msg);
	WarpTrainingMessageText(msg_newline, msg, len);

	char title[TRAINING_MSG_MAX_WIDTH];
	Format(title, sizeof(title), "%N", client);

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

bool CancelTrainingMsgMenu(int client, int reason = TrainingMsgMenuCancel_Interrupted)
{
	int index = current_player_menu[client];
	current_player_menu[client] = -1;
	if(index != -1) {
		TraningMsgMenusFunctions.GetArray(index, tmpmenufunc, sizeof(TraningMsgMenuFunction));

		Call_StartFunction(tmpmenufunc.plugin, tmpmenufunc.func);
		Call_PushCell(TrainingMsgMenuAction_Cancel);
		Call_PushCell(client);
		Call_PushCell(reason);
		Call_PushCell(tmpmenufunc.data);
		Call_PushCell(0);
		Call_Finish();

		TraningMsgMenusFunctions.Erase(index);
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
				TraningMsgMenusFunctions.GetArray(index, tmpmenufunc, sizeof(TraningMsgMenuFunction));

				Call_StartFunction(tmpmenufunc.plugin, tmpmenufunc.func);
				Call_PushCell(TrainingMsgMenuAction_Select);
				Call_PushCell(param1);
				Call_PushCell(param2);
				Call_PushCell(tmpmenufunc.data);
				Call_PushCell(0);
				Call_Finish();

				TraningMsgMenusFunctions.Erase(index);
			}
		}
		case MenuAction_Cancel: {
			int index = current_player_menu[param1];
			current_player_menu[param1] = -1;
			DisableClient(param1, _, false);

			if(index != -1) {
				TraningMsgMenusFunctions.GetArray(index, tmpmenufunc, sizeof(TraningMsgMenuFunction));

				Call_StartFunction(tmpmenufunc.plugin, tmpmenufunc.func);
				Call_PushCell(TrainingMsgMenuAction_Cancel);
				Call_PushCell(param1);

				switch(param2) {
					case MenuCancel_Disconnected: { Call_PushCell(TrainingMsgMenuCancel_Disconnected); }
					case MenuCancel_Interrupted: { Call_PushCell(TrainingMsgMenuCancel_Interrupted); }
					case MenuCancel_Exit: { Call_PushCell(TrainingMsgMenuCancel_Exit); }
					case MenuCancel_Timeout: { Call_PushCell(TrainingMsgMenuCancel_Timeout); }
					default: { Call_PushCell(-1); }
				}

				Call_PushCell(tmpmenufunc.data);
				Call_PushCell(0);
				Call_Finish();

				TraningMsgMenusFunctions.Erase(index);
			}
		}
	}
	return 0;
}

int TrainingMsgMenuCtor(Handle plugin, int params)
{
	tmpmenuinfo.title[0] = '\0';
	tmpmenuinfo.keys |= (1 << 9);
	tmpmenuinfo.pan = new Panel();
	tmpmenuinfo.pan.DrawText("");
	tmpmenuinfo.pan.SetKeys(tmpmenuinfo.keys);
	tmpmenuinfo.items = new ArrayList(ByteCountToCells(TRAINING_MSG_MAX_WIDTH));
	tmpmenuinfo.flags = TMSG_NOFLAGS;
	tmpmenuinfo.curritem = 0;

	tmpmenufunc.func = GetNativeFunction(1);
	tmpmenufunc.plugin = plugin;
	tmpmenufunc.data = GetNativeCell(2);

	TraningMsgMenusFunctions.PushArray(tmpmenufunc, sizeof(TraningMsgMenuFunction));

	return TraningMsgMenus.PushArray(tmpmenuinfo, sizeof(TraningMsgMenuInfo));
}

void AddItemToString(ArrayList items, int keys, int i, int maxlen, char[] msg, int len, bool newline, bool pipe)
{
	char[] item = new char[maxlen];
	items.GetString(i, item, maxlen);

	if(keys & (1 << i)) {
		char num[2];
		IntToString(i+1, num, sizeof(num));
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

	TraningMsgMenus.GetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	bool ret = tmpmenuinfo.pan.Send(client, GlobalTrainingMsgMenuHandler, time);
	if(ret) {
		CancelTrainingMsgMenu(client);
		EnableClient(client);
		msg_flags[client] = tmpmenuinfo.flags;

		current_player_menu[client] = index;

		int clients[1];
		clients[0] = client;

		int block = tmpmenuinfo.items.BlockSize;
		int itemnum = tmpmenuinfo.items.Length;
		int len = (itemnum * block) + (3 * TRAINING_MSG_MAX_WIDTH);
		char[] msg = new char[len];

		if(itemnum > TRAINING_MSG_MAX_HEIGHT) {
			itemnum = TRAINING_MSG_MAX_HEIGHT;
		}

		for(int i = 0; i < itemnum; ++i) {
			AddItemToString(tmpmenuinfo.items, tmpmenuinfo.keys, i, TRAINING_MSG_MAX_WIDTH, msg, len, true, false);
		}

		SendToClientsHelper(clients, sizeof(clients), tmpmenuinfo.title, msg);
	}

	delete tmpmenuinfo.pan;
	delete tmpmenuinfo.items;

	TraningMsgMenus.Erase(index);

	return ret;
}

int TrainingMsgMenuExitButton(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenus.GetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	if(GetNativeCell(2)) {
		tmpmenuinfo.keys |= (1 << 9);
	} else {
		tmpmenuinfo.keys &= ~(1 << 9);
	}
	tmpmenuinfo.pan.SetKeys(tmpmenuinfo.keys);

	TraningMsgMenus.SetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	return 0;
}

int TrainingMsgMenuFlags(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenus.GetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	tmpmenuinfo.flags = GetNativeCell(2);

	TraningMsgMenus.SetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	return 0;
}

int TrainingMsgMenuAddItem(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenus.GetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	if(tmpmenuinfo.curritem == TRAINING_MSG_MAX_HEIGHT) {
		return 0;
	}

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] title = new char[length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	tmpmenuinfo.keys |= (1 << tmpmenuinfo.curritem);
	tmpmenuinfo.pan.SetKeys(tmpmenuinfo.keys);
	++tmpmenuinfo.curritem;

	tmpmenuinfo.items.PushString(title);

	TraningMsgMenus.SetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	any data = GetNativeCell(3);

	return 1;
}

int TrainingMsgMenuDrawItem(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenus.GetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	if(tmpmenuinfo.curritem == TRAINING_MSG_MAX_HEIGHT) {
		return 0;
	}

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] title = new char[length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	++tmpmenuinfo.curritem;
	tmpmenuinfo.items.PushString(title);

	TraningMsgMenus.SetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	return 1;
}

int TrainingMsgMenuSetTitle(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenus.GetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] title = new char[length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	strcopy(tmpmenuinfo.title, sizeof(tmpmenuinfo.title), title);

	TraningMsgMenus.SetArray(index, tmpmenuinfo, sizeof(TraningMsgMenuInfo));

	return 0;
}

bool CheckPluginHandle(Handle hPlugin)
{
	return !(hPlugin == null || !IsValidHandle(hPlugin));
}

public void OnGameFrame()
{
	bool any_enabled = false;

	if(sm_trainingmsg_setprop.BoolValue) {
		any_enabled = ((num_enabled > 0) && (num_enabled != MaxClients));
	} else {
		any_enabled = (num_enabled > 0);
	}

	if(any_enabled)
	{
		ChangeGameRulesState();

		//TODO!!! refactor this using OnNotifyPluginUnloaded
		/*for(int i = 0; i < TraningMsgMenusFunctions.Length; ++i) {
			Handle plugin[1];
			TraningMsgMenusFunctions.GetArray(i, plugin, 1);

			if(!CheckPluginHandle(plugin[0]) || GetPluginStatus(plugin[0]) != Plugin_Running) {
				for(int j = 1; j <= MaxClients; ++j) {
					if(current_player_menu[j] == i) {
						DisableClient(j, _, false);
						current_player_menu[j] = -1;
					}
				}

				TraningMsgMenusFunctions.Erase(i);
				--i;
			}
		}*/
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
		tf_gamerules = entity;
	}
}

public void OnEntityDestroyed(int entity)
{
	if(entity == tf_gamerules) {
		tf_gamerules = -1;
	}
}

void ChangeGameRulesState()
{
	if(tf_gamerules != -1) {
		ChangeEdictState(tf_gamerules, m_bIsInTrainingOffset);
		ChangeEdictState(tf_gamerules, m_bIsTrainingHUDVisibleOffset);
		ChangeEdictState(tf_gamerules, m_bIsWaitingForTrainingContinueOffset);
	} else {
		ThrowError("tf_gamerules was not found");
	}
}

Action Timer_ResetWantsVgui(Handle timer, int client)
{
	client = GetClientOfUserId(client);
	if(client != -1) {
		player_vgui_timer[client] = null;
		player_wants_vgui[client] = 0;
		ChangeGameRulesState();
	}
}

Action command_continue(int client, const char[] command, int args)
{
	if(msg_enabled[client] && MsgHasContinue(client)) {
		if(!!(msg_flags[client] & TMSG_REMOVE_ON_CONTINUE)) {
			int ret = DisableClient(client, _, true, TrainingMsgMenuCancel_Exit);
			if(ret == 1) {
				ChangeGameRulesState();
			}
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
					ChangeGameRulesState();
				}
			} else {
				if(player_wants_vgui[client]++ == 0) {
					ChangeGameRulesState();
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

Action HookIsTraining(const char[] cPropName, int &iValue, const int iElement, const int iClient)
{
	if(msg_enabled[iClient]) {
		if(player_wants_vgui[iClient] != 0) {
			iValue = 0;
		} else {
			iValue = 1;
		}
	} else {
		iValue = 0;
	}
	return Plugin_Changed;
}

Action HookIsContinue(const char[] cPropName, int &iValue, const int iElement, const int iClient)
{
	if(msg_enabled[iClient] && MsgHasContinue(iClient)) {
		iValue = 1;
	} else {
		iValue = 0;
	}
	return Plugin_Changed;
}

void Unhook(bool value, bool has_continue)
{
	if(gamerules_hooked) {
		SendProxy_UnhookGameRules("m_bIsInTraining", HookIsTraining);
		SendProxy_UnhookGameRules("m_bIsTrainingHUDVisible", HookIsTraining);
		SendProxy_UnhookGameRules("m_bIsWaitingForTrainingContinue", HookIsContinue);
		gamerules_hooked = false;
	}

	if(sm_trainingmsg_setprop.BoolValue) {
		GameRules_SetProp("m_bIsInTraining", value);
		GameRules_SetProp("m_bIsTrainingHUDVisible", value);
		GameRules_SetProp("m_bIsWaitingForTrainingContinue", has_continue);
	} else {
		if(!value) {
			GameRules_SetProp("m_bIsInTraining", 0);
			GameRules_SetProp("m_bIsTrainingHUDVisible", 0);
			GameRules_SetProp("m_bIsWaitingForTrainingContinue", 0);
		}
	}

	ChangeGameRulesState();
}

void Hook()
{
	if(!gamerules_hooked) {
		SendProxy_HookGameRules("m_bIsInTraining", Prop_Int, HookIsTraining, true);
		SendProxy_HookGameRules("m_bIsTrainingHUDVisible", Prop_Int, HookIsTraining, true);
		SendProxy_HookGameRules("m_bIsWaitingForTrainingContinue", Prop_Int, HookIsContinue, true);
		gamerules_hooked = true;
	}

	ChangeGameRulesState();
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

	int ret = DisableClient(client);
	if(ret == 1) {
		ChangeGameRulesState();
	}

	return Plugin_Continue;
}

Action teamplay_round_start(Event event, const char[] name, bool dontBroadcast)
{
	DisableAll();

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
}

void SendToClientsHelper(int[] clients, int numClients, const char[] title, const char[] msg)
{
	Hook();
	SendUsrMsgHelper(clients, numClients, title, msg);
}

void SendToAllHelper(int[] clients, int numClients, const char[] title, const char[] msg, bool has_continue)
{
	if(!sm_trainingmsg_setprop.BoolValue) {
		Hook();
	} else {
		Unhook(true, has_continue);
	}
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
	length++;

	char[] title = new char[length];
	GetNativeString(1, title, length);

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingObjective, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
}

int ChangeTextAll(Handle plugin, int params)
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
				//TODO!!! change title
			}
		}
	}

	int length = 0;
	GetNativeStringLength(1, length);
	length++;

	char[] title = new char[length];
	GetNativeString(1, title, length);

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingMsg, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
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
	length++;

	char[] title = new char[length];
	GetNativeString(3, title, length);

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingObjective, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
}

int ChangeText(Handle plugin, int params)
{
	int numClients = GetNativeCell(2);

	int[] clients = new int[numClients];
	GetNativeArray(1, clients, numClients);

	for(int i = 0; i < numClients; ++i) {
		int client = clients[i];
		if(CancelTrainingMsgMenu(client)) {
			//TODO!!! change title
		}
	}

	int length = 0;
	GetNativeStringLength(3, length);
	length++;

	char[] title = new char[length];
	GetNativeString(3, title, length);

	BfWrite usrmsg = view_as<BfWrite>(StartMessageEx(TrainingMsg, clients, numClients));
	usrmsg.WriteString(title);
	EndMessage();
}

bool IsClientValid(int client)
{
	if(!IsClientInGame(client) ||
		IsFakeClient(client) ||
		IsClientSourceTV(client) ||
		IsClientReplay(client)) {
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
	length++;

	char[] title = new char[length];
	GetNativeString(3, title, length);

	length = 0;
	GetNativeStringLength(4, length);
	length++;

	char[] msg = new char[length];
	GetNativeString(4, msg, length);

	TrainingMsgFlags flags = GetNativeCell(5);

	if(sm_trainingmsg_setprop.BoolValue && numClients == MaxClients) {
		for(int i = 0; i < numClients; ++i) {
			HandleAllLoop(i, flags);
		}

		bool has_continue = !!(flags & TMSG_HAS_CONTINUE);

		SendToAllHelper(clients, numClients, title, msg, has_continue);
	} else {
		for(int i = 0; i < numClients; ++i) {
			int client = clients[i];
			if(!HandleClientLoop(client, flags)) {
				continue;
			}
		}

		SendToClientsHelper(clients, numClients, title, msg);
	}

	return 0;
}

bool HandleAllLoop(int i, TrainingMsgFlags flags)
{
	if(sm_trainingmsg_setprop.BoolValue) {
		DisableClient(i);
	}
	if(!IsClientValid(i)) {
		return false;
	}
	CancelTrainingMsgMenu(i);
	if(!sm_trainingmsg_setprop.BoolValue) {
		EnableClient(i);
		msg_flags[i] = flags;
	}
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
	length++;

	char[] title = new char[length];
	GetNativeString(1, title, length);

	length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] msg = new char[length];
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
	length++;

	char[] title = new char[length];
	GetNativeString(2, title, length);

	length = 0;
	GetNativeStringLength(3, length);
	length++;

	char[] msg = new char[length];
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

	ChangeGameRulesState();

	return 0;
}

public void OnClientDisconnect(int client)
{
	if(DisableClient(client, _, false) == 1) {
		ChangeGameRulesState();
	}
}