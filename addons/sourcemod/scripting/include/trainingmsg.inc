#if defined trainingmsg_inc
	#endinput
#endif
#define trainingmsg_inc

#define TRAINING_MSG_MAX_WIDTH 56
#define TRAINING_MSG_MAX_HEIGHT 4
#define TRAINING_MSG_MAX_LEN (TRAINING_MSG_MAX_WIDTH * TRAINING_MSG_MAX_HEIGHT)

enum TrainingMsgMenuAction
{
	TrainingMsgMenuAction_Select,
	TrainingMsgMenuAction_Cancel,
};

enum
{
	TrainingMsgMenuCancel_Disconnected,
	TrainingMsgMenuCancel_Interrupted,
	TrainingMsgMenuCancel_Exit,
	TrainingMsgMenuCancel_Timeout,
	TrainingMsgMenuCancel_ExitBack
};

typedef TrainingMsgMenuHandler = function void (TrainingMsgMenuAction action, int client, int param1, any menu_data);

#define TRAININGMSGMENU_TIME_FOREVER 0

enum TrainingMsgFlags
{
	TMSG_NOFLAGS = 0,
	TMSG_HAS_CONTINUE = (1 << 0),
	TMSG_REMOVE_ON_CONTINUE = (1 << 2),
};

#define TMSG_CONTINUE_AUTOREMOVE (TMSG_HAS_CONTINUE|TMSG_REMOVE_ON_CONTINUE)

methodmap TrainingMsgMenu
{
	public native TrainingMsgMenu(TrainingMsgMenuHandler handler, any data = 0);

	public native void SetTitle(const char[] str);

	public native bool DrawItem(const char[] str);
	public native bool AddItem(const char[] str, bool disabled = false);

	property bool ExitButton {
		public native set(bool value);
	}

	property bool ExitBackButton {
		public native set(bool value);
	}

	property TrainingMsgFlags Flags {
		public native set(TrainingMsgFlags value);
	}

	public native bool SendToClient(int client, int time);
	//public native void SendToAll(int time);
	//public native void SendToClients(const int[] clients, int numClients, int time);
};

forward void OnPlayerContinuedTrainingMessage(int client);

native bool IsTrainingMessageVisibleToClient(int client);
native bool IsTrainingMessageVisibleToAll();

native bool HasPlayerContinuedTrainingMessage(int client);
native bool TrainingMessageHasContinue(int client);

native void RemoveContinueFromTrainingMessage(int client);
native void RemoveContinueFromClient(int client);

/*
if you want text to be hinted use \x2 before the text and \x1 after like this
Format(mytext, sizeof(mytext), "\x2this text is hinted \x1now this text isnt");
*/

native void SendTrainingMessageToClients(const int[] clients, int numClients, const char[] title, const char[] msg, TrainingMsgFlags flags = TMSG_NOFLAGS);
native void SendTrainingMessageToAll(const char[] title, const char[] msg, TrainingMsgFlags flags = TMSG_NOFLAGS);
native void SendTrainingMessageToClient(int client, const char[] title, const char[] msg, TrainingMsgFlags flags = TMSG_NOFLAGS);

native void RemoveTrainingMessageFromAll();
native void RemoveTrainingMessageFromClients(const int[] clients, int numClients);

native void ChangeTrainingMessageTitleClients(const int[] clients, int numClients, const char[] title);
native void ChangeTrainingMessageTextClients(const int[] clients, int numClients, const char[] title);

native void ChangeTrainingMessageTitleAll(const char[] title);
native void ChangeTrainingMessageTextAll(const char[] title);

stock void CleanTrainingMessageText(char[] msg, int len)
{
	ReplaceString(msg, len, "{yellow}", "\x2");
	ReplaceString(msg, len, "{gold}", "\x2");

	ReplaceString(msg, len, "{default}", "\x1");
	ReplaceString(msg, len, "{white}", "\x1");

	ReplaceString(msg, len, "\\x2", "\x2");
	ReplaceString(msg, len, "\\x1", "\x1");

	ReplaceString(msg, len, "\\n", "\n");
	ReplaceString(msg, len, "\\t", "\t");
}

stock void RemoveTrainingMessageFromClient(int client)
{
	int clients[1];
	clients[0] = client;

	RemoveTrainingMessageFromClients(clients, sizeof(clients));
}

stock void ChangeTrainingMessageTitleClient(int client, const char[] title)
{
	int clients[1];
	clients[0] = client;

	ChangeTrainingMessageTitleClients(clients, sizeof(clients), title);
}

stock void ChangeTrainingMessageTextClient(int client, const char[] title)
{
	int clients[1];
	clients[0] = client;

	ChangeTrainingMessageTextClients(clients, sizeof(clients), title);
}

public SharedPlugin __pl_trainingmsg =
{
	name = "trainingmsg",
	file = "trainingmsg.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_trainingmsg_SetNTVOptional()
{
	
}
#endif