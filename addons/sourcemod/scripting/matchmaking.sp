#include <sourcemod>
#include <sdktools>

#define k_nMatchGroup_Casual_12v12 7

public void OnPluginStart()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientConnected(i)) {
			OnClientConnected(i);
		}
	}
}

public void OnClientConnected(int client)
{
	Event event = CreateEvent("client_beginconnect", true);
	event.SetString("source", "matchmaking");
	event.FireToClient(client);
	event.Cancel();
}

public void OnMapStart()
{
	GameRules_SetProp("m_nMatchGroupType", k_nMatchGroup_Casual_12v12);
}