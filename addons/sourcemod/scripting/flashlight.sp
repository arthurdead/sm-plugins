#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

#define EF_DIMLIGHT 0x004

bool bFlashlightEnabled[MAXPLAYERS+1] = {false, ...};
bool bFlashlightSupported[MAXPLAYERS+1] = {false, ...};

public void OnPluginStart()
{
	HookEvent("player_spawn", player_spawn);
	HookEvent("player_death", player_death);

	RegConsoleCmd("sm_fl", ConCommand_Flashlight);
	RegConsoleCmd("sm_flashlight", ConCommand_Flashlight);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnConfigsExecuted()
{
	FindConVar("mp_flashlight").BoolValue = true;
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientDisconnected(i);
		}
	}
}

void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	SetEntProp(client, Prop_Send, "m_bWearingSuit", 1);
}

void RemoveFlashlight(int client)
{
	bFlashlightEnabled[client] = false;

	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	effects &= ~EF_DIMLIGHT;
	SetEntProp(client, Prop_Send, "m_fEffects", effects);
}

void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER))
	{
		RemoveFlashlight(client);
	}
}

public void OnClientPutInServer(int client)
{
	QueryClientConVar(client, "mat_supportflashlight", mat_supportflashlight);
}

public void OnClientDisconnect(int client)
{
	RemoveFlashlight(client);

	bFlashlightSupported[client] = false;
}

void mat_supportflashlight(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any data)
{
	if(result == ConVarQuery_Okay && StrEqual(cvarValue, "1")) {
		QueryClientConVar(client, "r_flashlightrender", r_flashlightrender);
	}
}

void r_flashlightrender(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any data)
{
	if(result == ConVarQuery_Okay && StrEqual(cvarValue, "1")) {
		bFlashlightSupported[client] = true;
	}
}

Action ConCommand_Flashlight(int client, int args)
{
	bFlashlightEnabled[client] = !bFlashlightEnabled[client];

	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	effects ^= EF_DIMLIGHT;
	SetEntProp(client, Prop_Send, "m_fEffects", effects);

	return Plugin_Handled;
}