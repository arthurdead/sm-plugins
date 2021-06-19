#include <sourcemod>
#include <sdkhooks>

#define SF_DOOR_PUSE 256
#define SF_DOOR_PTOUCH 1024
#define	SF_DOOR_USE_CLOSES 8192
#define SF_DOOR_IGNORE_USE 32768
#define SF_DOOR_NEW_USE_RULES 65536

#define SF_BUTTON_TOUCH_ACTIVATES 256
#define SF_BUTTON_DAMAGE_ACTIVATES 512
#define SF_BUTTON_USE_ACTIVATES 1024
#define	SF_BUTTON_SPARK_IF_OFF 4096
#define	SF_BUTTON_JIGGLE_ON_USE_LOCKED 8192

Handle PlayerUseTimer[MAXPLAYERS+1] = {null, ...};
bool bPlayerInUse[MAXPLAYERS+1] = {false, ...};

public void OnPluginStart()
{
	RegConsoleCmd("sm_use", sm_use);

	AddCommandListener(command_hook, "voicemenu");
}

public void OnConfigsExecuted()
{
	FindConVar("tf_allow_player_use").BoolValue = true;
}

public void OnClientDisconnect(int client)
{
	if(PlayerUseTimer[client] != null) {
		KillTimer(PlayerUseTimer[client]);
	}
	PlayerUseTimer[client] = null;
	bPlayerInUse[client] = false;
}

Action Timer_ResetUse(Handle timer, int client)
{
	client = GetClientOfUserId(client);
	if(client != 0) {
		DeactivateUse(client);
		PlayerUseTimer[client] = null;
	}
	return Plugin_Continue;
}

public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	char command[64];
	kv.GetSectionName(command, sizeof(command));

	if(StrEqual(command, "+inspect_server")) {
		ActivateUse(client);
	} else if(StrEqual(command, "-inspect_server")) {
		DeactivateUse(client);
	}

	return Plugin_Continue;
}

void ActivateUse(int client)
{
	int buttons = GetEntProp(client, Prop_Data, "m_afButtonPressed");
	buttons |= IN_USE;
	SetEntProp(client, Prop_Data, "m_afButtonPressed", buttons);
	bPlayerInUse[client] = true;
}

void DeactivateUse(int client)
{
	int buttons = GetEntProp(client, Prop_Data, "m_afButtonPressed");
	buttons &= ~IN_USE;
	SetEntProp(client, Prop_Data, "m_afButtonPressed", buttons);
	bPlayerInUse[client] = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(bPlayerInUse[client]) {
		buttons |= IN_USE;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

Action command_hook(int client, const char[] command, int args)
{
	if(StrEqual(command, "voicemenu")) {
		if(args == 2) {
			char arg1[2];
			GetCmdArg(1, arg1, sizeof(arg1));

			char arg2[2];
			GetCmdArg(2, arg2, sizeof(arg2));

			if(arg1[0] == '0' && arg2[0] == '0') {
				if(PlayerUseTimer[client] != null) {
					KillTimer(PlayerUseTimer[client]);
				}

				ActivateUse(client);
				PlayerUseTimer[client] = CreateTimer(0.2, Timer_ResetUse, GetClientUserId(client));
			}
		}
	}
	return Plugin_Continue;
}

Action sm_use(int client, int args)
{
	if(PlayerUseTimer[client] != null) {
		KillTimer(PlayerUseTimer[client]);
	}

	ActivateUse(client);
	PlayerUseTimer[client] = CreateTimer(0.2, Timer_ResetUse, GetClientUserId(client));

	return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "func_door") ||
		StrEqual(classname, "func_water") ||
		StrEqual(classname, "func_door_rotating")) {
		SDKHook(entity, SDKHook_SpawnPost, OnDoorSpawnPost);
	} else if(StrEqual(classname, "func_button") ||
			StrEqual(classname, "func_rot_button") ||
			StrEqual(classname, "momentary_rot_button")) {
		SDKHook(entity, SDKHook_SpawnPost, OnButtonSpawnPost);
	}
}

void OnDoorSpawnPost(int entity)
{
	int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");
	SetEntProp(entity, Prop_Data, "m_spawnflags", flags);
}

void OnButtonSpawnPost(int entity)
{
	int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");
	flags |= SF_BUTTON_USE_ACTIVATES;
	SetEntProp(entity, Prop_Data, "m_spawnflags", flags);
}