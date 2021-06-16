#include <sourcemod>
#include <vphysics>
#include <sdkhooks>
#include <sdktools>

ConVar stickyphysics_parent = null;

public void OnPluginStart()
{
	stickyphysics_parent = CreateConVar("stickyphysics_parent", "0");

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
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

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PostThink, OnPlayerPostThink);
}

void OnPlayerPostThink(int client)
{
	float rot[3];
	GetClientAbsAngles(client, rot);

	int entity = GetEntPropEnt(client, Prop_Data, "m_hMoveChild");
	while(IsValidEntity(entity)) {
		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));
		if(StrEqual(classname, "tf_projectile_pipe_remote")) {

		}
		entity = GetEntPropEnt(entity, Prop_Data, "m_hMovePeer");
	}
}

void OnPipeTouch(int entity, int other)
{
	if(other >= 1 && other <= MaxClients) {
		int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
		int other_team = GetEntProp(other, Prop_Send, "m_iTeamNum");
		if(team == other_team) {
			return;
		}

		int weapon = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
		if(IsValidEntity(weapon)) {
			int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
			if(IsValidEntity(owner)) {
				if(owner == other) {
					return;
				}
			}
		}

		if(stickyphysics_parent.BoolValue) {
			SetEntProp(entity, Prop_Send, "m_bTouched", 1);
			Phys_EnableMotion(entity, false);

			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", other);
			SetEntityMoveType(entity, MOVETYPE_NONE);

			SetEntityModel(entity, "models/props_lakeside_event/bomb_temp_hat.mdl");

			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 0.5);
		}
	}
}