#include <sourcemod>
#include <sdktools>
#include <sendproxy>
#include <tf2_stocks>

//#define SET_PROP

bool msg_enabled[MAXPLAYERS+1] = {false, ...};
int num_enabled = 0;
bool gamerules_hooked = false;
bool g_bLateLoaded = false;
int player_wants_vgui[MAXPLAYERS+1] = {0, ...};
Handle player_vgui_timer[MAXPLAYERS+1] = {null, ...};

UserMsg TrainingObjective = INVALID_MESSAGE_ID;
UserMsg TrainingMsg = INVALID_MESSAGE_ID;

int tf_gamerules = -1;
int m_bIsInTrainingOffset = -1;
int m_bIsTrainingHUDVisibleOffset = -1;

public void OnPluginStart()
{
	TrainingObjective = GetUserMessageId("TrainingObjective");
	TrainingMsg = GetUserMessageId("TrainingMsg");

	m_bIsInTrainingOffset = FindSendPropInfo("CTFGameRules", "m_bIsInTraining");
	m_bIsTrainingHUDVisibleOffset = FindSendPropInfo("CTFGameRules", "m_bIsTrainingHUDVisible");

	AddCommandListener(command_menu, "menuopen");
	AddCommandListener(command_menu, "menuclosed");

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

	RegPluginLibrary("trainingmsg");

	g_bLateLoaded = late;
	return APLRes_Success;
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

public void OnGameFrame()
{
	if(num_enabled > 0) {
		ChangeGameRulesState();
	}
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

#if defined SET_PROP
	GameRules_SetProp("m_bIsInTraining", value);
	GameRules_SetProp("m_bIsTrainingHUDVisible", value);
#else
	if(!value) {
		GameRules_SetProp("m_bIsInTraining", 0);
		GameRules_SetProp("m_bIsTrainingHUDVisible", 0);
	} else {
		ChangeGameRulesState();
	}
#endif
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

int DisableClient(int client, bool send_empty)
{
	player_wants_vgui[client] = 0;

	if(player_vgui_timer[client] != null) {
		KillTimer(player_vgui_timer[client]);
		player_vgui_timer[client] = null;
	}

	if(send_empty && IsClientInGame(client)) {
		int clients[1];
		clients[0] = client;

		SendUsrMsgHelper(clients, sizeof(clients), "", "");
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
		if(DisableClient(i, true) == 2) {
			break;
		}
	}
}

Action player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	int ret = DisableClient(client, true);
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
#if !defined SET_PROP
	Hook();
#else
	Unhook(true);
#endif
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
		if(IsClientInGame(i)) {
			if((m_bIsInTraining && m_bIsTrainingHUDVisible) || msg_enabled[i]) {
				clients[numClients++] = i;
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
		if(IsClientInGame(i)) {
			if((m_bIsInTraining && m_bIsTrainingHUDVisible) || msg_enabled[i]) {
				clients[numClients++] = i;
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

#if defined SET_PROP
	if(numClients == MaxClients) {
		for(int i = 0; i < numClients; ++i) {
			int client = clients[i];
			if(DisableClient(client, false) == 2) {
				break;
			}
		}

		SendToAllHelper(clients, numClients, title, msg);
	} else
#endif
	{
		for(int i = 0; i < numClients; ++i) {
			int client = clients[i];
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
		if(IsClientInGame(i)) {
			clients[numClients++] = i;
		#if !defined SET_PROP
			EnableClient(i);
		#endif
		}
	#if defined SET_PROP
		DisableClient(i, true);
	#endif
	}

	SendToAllHelper(clients, numClients, title, msg);

	return 0;
}

int SendToClient(Handle plugin, int params)
{
	int client = GetNativeCell(1);

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
		int ret = DisableClient(client, true);
		if(ret == 2) {
			return 0;
		}
	}

	ChangeGameRulesState();

	return 0;
}

public void OnClientDisconnect(int client)
{
	DisableClient(client, true);
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		DisableClient(i, true);
	}
}