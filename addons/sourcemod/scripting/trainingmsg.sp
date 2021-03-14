#include <sourcemod>
#include <sdktools>
#include <sendproxy>
#include <tf2_stocks>
#include <trainingmsg>

bool msg_enabled[MAXPLAYERS+1] = {false, ...};
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

ConVar tf_training_client_message = null;
ConVar sm_trainingmsg_setprop = null;

ArrayList TraningMsgMenus = null;
ArrayList TraningMsgMenusFunctions = null;

enum struct TraningMsgMenuFunction
{
	Handle plugin;
	Function func;
}

enum struct TraningMsgMenuInfo
{
	Panel pan;
	ArrayList items;
	char title[TRAINING_MSG_MAX_WIDTH];
	int curritem;
	int keys;
}

public void OnPluginStart()
{
	TraningMsgMenus = new ArrayList(sizeof(TraningMsgMenuInfo));
	TraningMsgMenusFunctions = new ArrayList(sizeof(TraningMsgMenuFunction));

	TrainingObjective = GetUserMessageId("TrainingObjective");
	TrainingMsg = GetUserMessageId("TrainingMsg");

	m_bIsInTrainingOffset = FindSendPropInfo("CTFGameRules", "m_bIsInTraining");
	m_bIsTrainingHUDVisibleOffset = FindSendPropInfo("CTFGameRules", "m_bIsTrainingHUDVisible");

	AddCommandListener(command_menu, "menuopen");
	AddCommandListener(command_menu, "menuclosed");

	tf_training_client_message = FindConVar("tf_training_client_message");

	sm_trainingmsg_setprop = CreateConVar("sm_trainingmsg_setprop", "0");

	HookEvent("player_spawn", player_spawn);
	HookEvent("teamplay_round_start", teamplay_round_start);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("IsTrainingMessageVisibleToClient", IsVisibleClient);
	CreateNative("IsTrainingMessageVisibleToAll", IsVisibleAll);

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
	CreateNative("TrainingMsgMenu.SendToClient", TrainingMsgMenuSendToClient);

	RegPluginLibrary("trainingmsg");

	g_bLateLoaded = late;
	return APLRes_Success;
}

bool CancelTrainingMsgMenu(int client)
{
	int index = current_player_menu[client];
	current_player_menu[client] = -1;
	if(index != -1) {
		TraningMsgMenuFunction func;
		TraningMsgMenusFunctions.GetArray(index, func, sizeof(TraningMsgMenuFunction));

		Call_StartFunction(func.plugin, func.func);
		Call_PushCell(TrainingMsgMenuAction_Cancel);
		Call_PushCell(client);
		Call_PushCell(TrainingMsgMenuCancel_Interrupted);
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

			TraningMsgMenuFunction func;
			TraningMsgMenusFunctions.GetArray(index, func, sizeof(TraningMsgMenuFunction));

			Call_StartFunction(func.plugin, func.func);
			Call_PushCell(TrainingMsgMenuAction_Select);
			Call_PushCell(param1);
			Call_PushCell(param2);
			Call_PushCell(0);
			Call_Finish();

			TraningMsgMenusFunctions.Erase(index);
		}
		case MenuAction_Cancel: {
			int index = current_player_menu[param1];
			current_player_menu[param1] = -1;
			DisableClient(param1, _, false);

			TraningMsgMenuFunction func;
			TraningMsgMenusFunctions.GetArray(index, func, sizeof(TraningMsgMenuFunction));

			Call_StartFunction(func.plugin, func.func);
			Call_PushCell(TrainingMsgMenuAction_Cancel);
			Call_PushCell(param1);

			switch(param2) {
				case MenuCancel_Disconnected: { Call_PushCell(TrainingMsgMenuCancel_Disconnected); }
				case MenuCancel_Interrupted: { Call_PushCell(TrainingMsgMenuCancel_Interrupted); }
				case MenuCancel_Exit: { Call_PushCell(TrainingMsgMenuCancel_Exit); }
				case MenuCancel_Timeout: { Call_PushCell(TrainingMsgMenuCancel_Timeout); }
				default: { Call_PushCell(-1); }
			}

			Call_PushCell(0);
			Call_Finish();

			TraningMsgMenusFunctions.Erase(index);
		}
	}
	return 0;
}

int TrainingMsgMenuCtor(Handle plugin, int params)
{
	TraningMsgMenuInfo info;

	info.keys |= (1 << 9);
	info.pan = new Panel();
	info.pan.SetKeys(info.keys);
	info.items = new ArrayList(TRAINING_MSG_MAX_WIDTH);

	TraningMsgMenuFunction func;
	func.func = GetNativeFunction(1);
	func.plugin = plugin;

	TraningMsgMenusFunctions.PushArray(func, sizeof(TraningMsgMenuFunction));

	return TraningMsgMenus.PushArray(info, sizeof(TraningMsgMenuInfo));
}

void AddItemToString(ArrayList items, int keys, int i, int block, char[] msg, int len, bool newline, bool pipe)
{
	char[] item = new char[block];
	items.GetString(i, item, block);

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

	if(!IsClientInGame(client) ||
		IsFakeClient(client) ||
		IsClientSourceTV(client) ||
		IsClientReplay(client)) {
		return 0;
	}

	int time = GetNativeCell(3);

	TraningMsgMenuInfo info;
	TraningMsgMenus.GetArray(index, info, sizeof(TraningMsgMenuInfo));

	bool ret = info.pan.Send(client, GlobalTrainingMsgMenuHandler, time);
	if(ret) {
		CancelTrainingMsgMenu(client);
		EnableClient(client);

		current_player_menu[client] = index;

		int clients[1];
		clients[0] = client;

		int block = info.items.BlockSize;
		int itemnum = info.items.Length;
		int len = (itemnum * block) + (3 * TRAINING_MSG_MAX_WIDTH);
		char[] msg = new char[len];

		if(itemnum > TRAINING_MSG_MAX_HEIGHT) {
			itemnum = TRAINING_MSG_MAX_HEIGHT;
		}

		for(int i = 0; i < itemnum; ++i) {
			AddItemToString(info.items, info.keys, i, block, msg, len, true, false);
		}

		SendToClientsHelper(clients, sizeof(clients), info.title, msg);
	}

	delete info.pan;
	delete info.items;

	TraningMsgMenus.Erase(index);

	return ret;
}

int TrainingMsgMenuExitButton(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo info;
	TraningMsgMenus.GetArray(index, info, sizeof(TraningMsgMenuInfo));

	if(GetNativeCell(2)) {
		info.keys |= (1 << 9);
	} else {
		info.keys &= ~(1 << 9);
	}
	info.pan.SetKeys(info.keys);

	TraningMsgMenus.SetArray(index, info, sizeof(TraningMsgMenuInfo));

	return 0;
}

int TrainingMsgMenuAddItem(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo info;
	TraningMsgMenus.GetArray(index, info, sizeof(TraningMsgMenuInfo));

	if(info.curritem == TRAINING_MSG_MAX_HEIGHT) {
		return 0;
	}

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] title = new char[length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	info.keys |= (1 << info.curritem);
	info.pan.SetKeys(info.keys);
	++info.curritem;

	info.items.PushString(title);

	TraningMsgMenus.SetArray(index, info, sizeof(TraningMsgMenuInfo));

	any data = GetNativeCell(3);

	return 1;
}

int TrainingMsgMenuDrawItem(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo info;
	TraningMsgMenus.GetArray(index, info, sizeof(TraningMsgMenuInfo));

	if(info.curritem == TRAINING_MSG_MAX_HEIGHT) {
		return 0;
	}

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] title = new char[length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	++info.curritem;
	info.items.PushString(title);

	TraningMsgMenus.SetArray(index, info, sizeof(TraningMsgMenuInfo));

	return 1;
}

int TrainingMsgMenuSetTitle(Handle plugin, int params)
{
	int index = GetNativeCell(1);

	if(index < 0 || index > TraningMsgMenus.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid menu");
	}

	TraningMsgMenuInfo info;
	TraningMsgMenus.GetArray(index, info, sizeof(TraningMsgMenuInfo));

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] title = new char[length];
	GetNativeString(2, title, length);

	ReplaceString(title, length, "\n", "");

	strcopy(info.title, sizeof(info.title), title);

	TraningMsgMenus.SetArray(index, info, sizeof(TraningMsgMenuInfo));

	return 0;
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

		/*for(int i = 0; i < TraningMsgMenusFunctions.Length; ++i) {
			Handle plugin[1];
			TraningMsgMenusFunctions.GetArray(i, plugin, 1);

			if(GetPluginStatus(plugin[0]) != Plugin_Running) {
				for(int j = 1; j <= MaxClients; ++j) {
					if(current_player_menu[j] == i) {
						DisableClient(j, _, false);
						current_player_menu[j] = -1;
					}
				}

				TraningMsgMenusFunctions.Erase(i);
				++i;
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

public void OnMapEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		DisableClient(i);
	}
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

Action command_menu(int client, const char[] command, int args)
{
	if(msg_enabled[client]) {
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
		return Plugin_Changed;
	} else {
		iValue = 0;
		return Plugin_Changed;
	}
}

void Unhook(bool value)
{
	if(gamerules_hooked) {
		SendProxy_UnhookGameRules("m_bIsInTraining", HookIsTraining);
		SendProxy_UnhookGameRules("m_bIsTrainingHUDVisible", HookIsTraining);
		gamerules_hooked = false;
	}

	if(sm_trainingmsg_setprop.BoolValue) {
		GameRules_SetProp("m_bIsInTraining", value);
		GameRules_SetProp("m_bIsTrainingHUDVisible", value);
		ChangeGameRulesState();
	} else {
		if(!value) {
			GameRules_SetProp("m_bIsInTraining", 0);
			GameRules_SetProp("m_bIsTrainingHUDVisible", 0);
			ChangeGameRulesState();
		} else {
			ChangeGameRulesState();
		}
	}
}

void Hook()
{
	if(!gamerules_hooked) {
		SendProxy_HookGameRules("m_bIsInTraining", Prop_Int, HookIsTraining, true);
		SendProxy_HookGameRules("m_bIsTrainingHUDVisible", Prop_Int, HookIsTraining, true);
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

int DisableClient(int client, bool send_empty = true, bool cancel_menu = true)
{
	player_wants_vgui[client] = 0;

	if(player_vgui_timer[client] != null) {
		KillTimer(player_vgui_timer[client]);
		player_vgui_timer[client] = null;
	}

	if(cancel_menu) {
		CancelTrainingMsgMenu(client);
	}

	if(send_empty) {
		if(!IsClientInGame(client) ||
			IsFakeClient(client) ||
			IsClientSourceTV(client) ||
			IsClientReplay(client)) {
		} else {
			int clients[1];
			clients[0] = client;
			SendUsrMsgHelper(clients, sizeof(clients), "", "");
		}
	}

	if(msg_enabled[client]) {
		msg_enabled[client] = false;
		--num_enabled;

		if(num_enabled == 0) {
			Unhook(false);
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

void SendToAllHelper(int[] clients, int numClients, const char[] title, const char[] msg)
{
	if(sm_trainingmsg_setprop.BoolValue) {
		Hook();
	} else {
		Unhook(true);
	}
	SendUsrMsgHelper(clients, numClients, title, msg);
}

int IsVisibleClient(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int m_bIsInTraining = GameRules_GetProp("m_bIsInTraining");
	int m_bIsTrainingHUDVisible = GameRules_GetProp("m_bIsTrainingHUDVisible");

	return ((m_bIsInTraining && m_bIsTrainingHUDVisible) || msg_enabled[client]);
}

int IsVisibleAll(Handle plugin, int params)
{
	int m_bIsInTraining = GameRules_GetProp("m_bIsInTraining");
	int m_bIsTrainingHUDVisible = GameRules_GetProp("m_bIsTrainingHUDVisible");

	return ((m_bIsInTraining && m_bIsTrainingHUDVisible) || num_enabled == MaxClients);
}

int ChangeTitleAll(Handle plugin, int params)
{
	int m_bIsInTraining = GameRules_GetProp("m_bIsInTraining");
	int m_bIsTrainingHUDVisible = GameRules_GetProp("m_bIsTrainingHUDVisible");

	int numClients = 0;
	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsFakeClient(i) ||
			IsClientSourceTV(i) ||
			IsClientReplay(i)) {
			continue;
		}
		if((m_bIsInTraining && m_bIsTrainingHUDVisible) || msg_enabled[i]) {
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
	int m_bIsInTraining = GameRules_GetProp("m_bIsInTraining");
	int m_bIsTrainingHUDVisible = GameRules_GetProp("m_bIsTrainingHUDVisible");

	int numClients = 0;
	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsFakeClient(i) ||
			IsClientSourceTV(i) ||
			IsClientReplay(i)) {
			continue;
		}
		if((m_bIsInTraining && m_bIsTrainingHUDVisible) || msg_enabled[i]) {
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

	if(sm_trainingmsg_setprop.BoolValue && numClients == MaxClients) {
		for(int i = 0; i < numClients; ++i) {
			int client = clients[i];
			if(DisableClient(client, false) == 2) {
				break;
			}
			CancelTrainingMsgMenu(client);
		}

		SendToAllHelper(clients, numClients, title, msg);
	} else {
		for(int i = 0; i < numClients; ++i) {
			int client = clients[i];
			if(!IsClientInGame(client) ||
				IsFakeClient(client) ||
				IsClientSourceTV(client) ||
				IsClientReplay(client)) {
				continue;
			}
			CancelTrainingMsgMenu(client);
			EnableClient(client);
		}

		SendToClientsHelper(clients, numClients, title, msg);
	}

	return 0;
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

	int numClients = 0;
	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(sm_trainingmsg_setprop.BoolValue) {
			DisableClient(i);
		}
		if(!IsClientInGame(i) ||
			IsFakeClient(i) ||
			IsClientSourceTV(i) ||
			IsClientReplay(i)) {
			continue;
		}
		clients[numClients++] = i;
		CancelTrainingMsgMenu(i);
		if(!sm_trainingmsg_setprop.BoolValue) {
			EnableClient(i);
		}
	}

	SendToAllHelper(clients, numClients, title, msg);

	return 0;
}

int SendToClient(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	if(!IsClientInGame(client) ||
		IsFakeClient(client) ||
		IsClientSourceTV(client) ||
		IsClientReplay(client)) {
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

	CancelTrainingMsgMenu(client);
	EnableClient(client);

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

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		DisableClient(i);
	}
}