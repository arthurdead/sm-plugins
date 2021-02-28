#if defined trainingmsg_inc
	#endinput
#endif
#define trainingmsg_inc

native bool IsTrainingMessageVisibleToClient(int client);
native bool IsTrainingMessageVisibleToAll();

native void SendTrainingMessageToClients(const int[] clients, int numClients, const char[] title, const char[] msg);
native void SendTrainingMessageToAll(const char[] title, const char[] msg);
native void SendTrainingMessageToClient(int client, const char[] title, const char[] msg);

native void RemoveTrainingMessageFromAll();
native void RemoveTrainingMessageFromClients(const int[] clients, int numClients);

native void ChangeTrainingMessageTitleClients(const int[] clients, int numClients, const char[] title);
native void ChangeTrainingMessageTextClients(const int[] clients, int numClients, const char[] title);

native void ChangeTrainingMessageTitleAll(const char[] title);
native void ChangeTrainingMessageTextAll(const char[] title);

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
public __pl_trainingmsg_SetNTVOptional()
{
	
}
#endif