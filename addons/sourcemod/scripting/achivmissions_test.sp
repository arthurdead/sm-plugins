#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <achivmissions>
#include <trainingmsg>

Achievement test_achiv = Achievement_Null;
MissionEntry test_missi = MissionEntry_Null;

public void OnPluginStart()
{
	HookEvent("player_spawn", player_spawn);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

	OnAchievementsLoaded();

	RegConsoleCmd("sm_missitest", sm_missitest);

	HookEvent("player_death", player_death);
	OnMissionsLoaded();
}

void trmenuhndl(TrainingMsgMenuAction action, int client, int param1, any menu_data, any item_data)
{
	if(action == TrainingMsgMenuAction_Select) {
		
	}
}

Action sm_missitest(int client, int args)
{
	TrainingMsgMenu menu = TrainingMsgMenu(trmenuhndl);

	menu.SetTitle("test");

	//menu.AddItem("yes");
	//menu.AddItem("no");

	char display[(6)*TRAINING_MSG_MAX_HEIGHT];

	for(int i = 0; i < TRAINING_MSG_MAX_HEIGHT; ++i) {
		Format(display, sizeof(display), "test%i", i);
		menu.AddItem(display);
	}

	menu.SendToClient(client, TRAININGMSGMENU_TIME_FOREVER);

	return Plugin_Handled;
}

void handle_die(int client, MissionInstance inst, any data)
{
	int times = inst.GetParamValue(0);
	int class = inst.GetParamValue(1);

	if(TF2_GetPlayerClass(client) == class) {
		inst.AwardProgress(1);

		if(inst.Progress >= times) {
			inst.Complete();
		}
	}
}

void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	test_missi.ExecuteAll(handle_die);
}

public void OnMissionsLoaded()
{
	test_missi = MissionEntry.FindByName("die");
}

public void OnClientPutInServer(int client)
{
	
}

void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(test_achiv != Achievement_Null) {
		test_achiv.Award(client);
	}
}

public void OnMissionStatusChanged(int client, MissionStatus status, MissionInstance inst)
{
	PrintToServer("OnMissionStatusChanged %i %i %i", client, status, inst.ID);
}

public void OnMissionProgressChanged(int client, int oldprogress, int newprogress, MissionInstance inst)
{
	PrintToServer("OnMissionProgressChanged %i %i %i %i", client, oldprogress, newprogress, inst.ID);
}

public void OnAchievementsLoaded()
{
	test_achiv = Achievement.FindByName("spawn");
}