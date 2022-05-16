#include <sourcemod>
#include <proxysend>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <sdkhooks>

#define TF_STATE_DYING 3

static int m_iIDEntIndex[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};

static void toggle_target_id(int client, bool value)
{
	if(value) {
		TF2Attrib_SetByDefIndex(client, 269, 1.0);
		SDKHook(client, SDKHook_PostThinkPost, player_think_post);
	} else {
		TF2Attrib_RemoveByDefIndex(client, 269);
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_post);
	}
}

static void VectorAddRotatedOffset(const float angle[3], float buffer[3], const float offset[3])
{
	float vecForward[3];
	float vecLeft[3];
	float vecUp[3];
	GetAngleVectors(angle, vecForward, vecLeft, vecUp);

	ScaleVector(vecForward, offset[0]);
	ScaleVector(vecLeft, offset[1]);
	ScaleVector(vecUp, offset[2]);

	float vecAdd[3];
	AddVectors(vecAdd, vecForward, vecAdd);
	AddVectors(vecAdd, vecLeft, vecAdd);
	AddVectors(vecAdd, vecUp, vecAdd);

	AddVectors(buffer, vecAdd, buffer);
}

static bool trace_filter_players(int entity, int contentsMask, any data)
{
	if(entity != data && entity >= 1 && entity <= MaxClients) {
		return true;
	}
	return false;
}

static void player_think_post(int client)
{
	float ang[3];
	GetClientEyeAngles(client, ang);

	float start[3];
	GetClientEyePosition(client, start);
	VectorAddRotatedOffset(ang, start, view_as<float>({10.0, 0.0, 0.0}));

	float end[3];
	end[0] = start[0];
	end[1] = start[1];
	end[2] = start[2];
	VectorAddRotatedOffset(ang, end, view_as<float>({8192.0, 0.0, 0.0}));

	TR_TraceRayFilter(start, end, MASK_SOLID, RayType_EndPoint, trace_filter_players, client);

	int ent = TR_GetEntityIndex();
	if(ent >= 1 && ent <= MaxClients) {
		m_iIDEntIndex[client] = EntIndexToEntRef(ent);
		proxysend_hook(client, "m_nPlayerState", player_proxysend_state, false);
	} else {
		m_iIDEntIndex[client] = INVALID_ENT_REFERENCE;
		proxysend_unhook(client, "m_nPlayerState", player_proxysend_state);
	}
}

static Action player_proxysend_state(int entity, const char[] prop, int &value, int element, int client)
{
	if(m_iIDEntIndex[entity] != INVALID_ENT_REFERENCE) {
		value = TF_STATE_DYING;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	m_iIDEntIndex[client] = INVALID_ENT_REFERENCE;
}

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

		toggle_target_id(i, true);
	}
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			toggle_target_id(i, false);
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

	toggle_target_id(client, true);
}

static void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(IsFakeClient(client)) {
		return;
	}

	toggle_target_id(client, true);
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER)) {
		toggle_target_id(client, false);
	}
}