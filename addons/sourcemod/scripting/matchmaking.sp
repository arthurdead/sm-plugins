#include <sourcemod>
#include <sdktools>

#define k_nMatchGroup_MvM_Practice 0
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
	int logic = FindEntityByClassname(-1, "tf_logic_mann_vs_machine");

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, PLATFORM_MAX_PATH);

	bool map_is_mvm = (logic != -1 || GameRules_GetProp("m_bPlayingMannVsMachine") || StrContains(map, "mvm_") == 0);

	if(map_is_mvm) {
		GameRules_SetProp("m_nMatchGroupType", k_nMatchGroup_MvM_Practice);
	} else {
		GameRules_SetProp("m_nMatchGroupType", k_nMatchGroup_Casual_12v12);
	}
}