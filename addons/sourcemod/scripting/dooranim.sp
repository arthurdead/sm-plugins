#include <sourcemod>
#include <sdktools>
#include <proxysend>

#define TF2_MAXPLAYERS 33

static Handle player_door_timer[TF2_MAXPLAYERS+1];

public void OnPluginStart()
{
	RegAdminCmd("sm_dooranim", sm_dooranim, ADMFLAG_ROOT);
}

public void OnClientDisconnect(int client)
{
	if(player_door_timer[client] != null) {
		KillTimer(player_door_timer[client]);
		player_door_timer[client] = null;
	}
}

static Action timer_door_time(Handle timer, DataPack data)
{
	data.Reset();

	int client = GetClientOfUserId(data.ReadCell());
	if(client == 0) {
		return Plugin_Stop;
	}

	int time = data.ReadCell();

	Event event = CreateEvent("restart_timer_time");
	event.SetInt("time", time--);
	event.FireToClient(client);
	event.Cancel();

	if(time == 0) {
		player_door_timer[client] = null;
		return Plugin_Stop;
	}

	--data.Position;

	data.WriteCell(time);

	return Plugin_Continue;
}

static Action sm_dooranim(int client, int args)
{
	if(args != 1) {
		ReplyToCommand(client, "[SM] Usage: sm_dooranim <filter>");
		return Plugin_Handled;
	}

	char filter[64];
	GetCmdArg(1, filter, sizeof(filter));

	char name[MAX_TARGET_LENGTH];
	bool isml = false;
	int targets[MAXPLAYERS];
	int count = ProcessTargetString(filter, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE, name, sizeof(name), isml);
	if(count == 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	GameRules_SetProp("m_nRoundsPlayed", 0);

	for(int i = 0; i < count; ++i) {
		int target = targets[i];

		if(player_door_timer[target] != null) {
			KillTimer(player_door_timer[target]);
		}

		DataPack data;
		player_door_timer[target] = CreateDataTimer(1.0, timer_door_time, data, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		data.WriteCell(GetClientUserId(target));
		data.WriteCell(10);

		TriggerTimer(player_door_timer[client], true);
	}

	return Plugin_Handled;
}