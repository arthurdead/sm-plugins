#include <sourcemod>
#include <proxysend>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>

#define TF_STATE_DYING 3

public void OnPluginStart()
{
	HookEvent("player_death", player_death);
	HookEvent("player_spawn", player_spawn);
	HookEvent("post_inventory_application", post_inventory_application);

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			!IsPlayerAlive(i) ||
			GetClientTeam(i) < 2 ||
			TF2_GetPlayerClass(i) == TFClass_Unknown ||
			IsFakeClient(i) ||
			IsClientReplay(i) ||
			IsClientSourceTV(i)) {
			continue;
		}

		TF2Attrib_SetByDefIndex(i, 269, 1.0);
		proxysend_hook(i, "m_nPlayerState", player_proxysend_state, true);
	}
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			TF2Attrib_RemoveByDefIndex(i, 269);
		}
	}
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	TFClassType player_class = TF2_GetPlayerClass(client);
	if(player_class == TFClass_Unknown ||
		GetClientTeam(client) < 2 ||
		IsFakeClient(client) ||
		IsClientReplay(client) ||
		IsClientSourceTV(client)) {
		return;
	}

	TF2Attrib_SetByDefIndex(client, 269, 1.0);
	proxysend_hook(client, "m_nPlayerState", player_proxysend_state, true);
}

static void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client)) {
		return;
	}

	TF2Attrib_SetByDefIndex(client, 269, 1.0);
	proxysend_hook(client, "m_nPlayerState", player_proxysend_state, true);
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER)) {
		TF2Attrib_RemoveByDefIndex(client, 269);
		proxysend_unhook(client, "m_nPlayerState", player_proxysend_state);
	}
}

static Action player_proxysend_state(int entity, const char[] prop, int &value, int element, int client)
{
	if(client == entity) {
		//TODO!!! make a trace
		value = TF_STATE_DYING;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}