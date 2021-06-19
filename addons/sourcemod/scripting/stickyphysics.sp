#include <sourcemod>
#include <vphysics>
#include <sdkhooks>
#include <sdktools>

ConVar stickyphysics_parent = null;

public void OnPluginStart()
{
	stickyphysics_parent = CreateConVar("stickyphysics_parent", "0");

	HookEvent("player_death", player_death);
	HookEvent("player_team", player_team);
	HookEvent("player_changeclass", player_changeclass);
	HookEvent("object_destroyed", object_destroyed);
}

void LoopChildren_r(int entity, Function func)
{
	char classname[64];
	while(IsValidEntity(entity)) {
		GetEntityClassname(entity, classname, sizeof(classname));
		Call_StartFunction(GetMyHandle(), func);
		Call_PushCell(entity);
		Call_PushString(classname);
		Call_Finish();
		int child = GetEntPropEnt(entity, Prop_Data, "m_hMoveChild");
		LoopChildren_r(child, func);
		entity = GetEntPropEnt(entity, Prop_Data, "m_hMovePeer");
	}
}

void LoopChildren(int entity, Function func)
{
	int child = GetEntPropEnt(entity, Prop_Data, "m_hMoveChild");
	LoopChildren_r(child, func);
}

void ClearSticky(int entity, const char[] classname)
{
	if(!StrEqual(classname, "tf_projectile_pipe_remote")) {
		return;
	}

	AcceptEntityInput(entity, "ClearParent");
	SetEntityMoveType(entity, MOVETYPE_VPHYSICS);
	SetEntProp(entity, Prop_Send, "m_bTouched", 0);
	Phys_EnableMotion(entity, true);
	SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 1.0);
	SetEntityModel(entity, "models/weapons/w_models/w_stickybomb.mdl");
}

void RemoveStickies(int target)
{
	LoopChildren(target, ClearSticky);
}

Action player_team(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	RemoveStickies(client);
	return Plugin_Continue;
}

Action player_changeclass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	RemoveStickies(client);
	return Plugin_Continue;
}

Action player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	RemoveStickies(client);
	return Plugin_Continue;
}

Action object_destroyed(Event event, const char[] name, bool dontBroadcast)
{
	int entity = event.GetInt("index");
	RemoveStickies(entity);
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_projectile_pipe_remote")) {
		SDKHook(entity, SDKHook_Use, OnPipeUse);
		SDKHook(entity, SDKHook_Touch, OnPipeTouch);
	}
}

Action OnPipeUse(int entity, int activator, int caller, UseType type, float value)
{
	if(type == Use_Toggle) {
		Phys_EnableMotion(entity, true);
	}
	return Plugin_Continue;
}

public void OnMapStart()
{
	PrecacheModel("models/props_lakeside_event/bomb_temp_hat.mdl");
}

void OnPipeTouch(int entity, int other)
{
	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	int other_team = GetEntProp(other, Prop_Send, "m_iTeamNum");
	if(team == other_team) {
		return;
	}

	bool player = (other >= 1 && other <= MaxClients);

	if(player) {
		int weapon = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
		if(IsValidEntity(weapon)) {
			int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
			if(IsValidEntity(owner)) {
				if(owner == other) {
					return;
				}
			}
		}
	}

	if(stickyphysics_parent.BoolValue) {
		SetEntProp(entity, Prop_Send, "m_bTouched", 1);
		Phys_EnableMotion(entity, false);
		SetEntityMoveType(entity, MOVETYPE_NONE);

		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", other);

		if(player) {
			SetEntityModel(entity, "models/props_lakeside_event/bomb_temp_hat.mdl");
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 0.5);
		}
	}
}