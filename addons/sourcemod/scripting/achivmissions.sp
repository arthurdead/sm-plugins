#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <stocksoup/tf/tempents_stocks.inc>
#include <achivmissions>

#define DEBUG

//TODO!!! use prepared statements

void OnErrorTransaction(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	#pragma unused db,data,numQueries,failIndex,queryData

	LogError("%s", error);
}

void OnErrorQuery(Database db, DBResultSet results, const char[] error, any data)
{
	#pragma unused db,results,data

	if(!results) {
		LogError("%s", error);
	}
}

char tmpquery[1024];

#include "achivmissions/achiv_globals.sp"
#include "achivmissions/achiv_methodmaps.sp"
#include "achivmissions/achiv_helpers.sp"
#include "achivmissions/achiv_sql.sp"
#include "achivmissions/achiv_natives.sp"
#include "achivmissions/achiv_cmds.sp"

#include "achivmissions/missi_globals.sp"
#include "achivmissions/missi_methodmaps.sp"
#include "achivmissions/missi_helpers.sp"
#include "achivmissions/missi_sql.sp"
#include "achivmissions/missi_natives.sp"

public void OnPluginStart()
{
	if(SQL_CheckConfig("achievements")) {
		Database.Connect(OnAchivDatabaseConnect, "achievements");
	}

	if(SQL_CheckConfig("missions")) {
		Database.Connect(OnMissiDatabaseConnect, "missions");
	}

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

	HookEvent("achievement_earned", achievement_earned);

	RegConsoleCmd("sm_achievements", sm_achievements);
	RegConsoleCmd("sm_achivs", sm_achievements);

	RegAdminCmd("sm_achivgiv", sm_achivgiv, ADMFLAG_GENERIC);
	RegAdminCmd("sm_achivprog", sm_achivprog, ADMFLAG_GENERIC);
	RegAdminCmd("sm_achivrem", sm_achivrem, ADMFLAG_GENERIC);
	RegAdminCmd("sm_achivremprog", sm_achivremprog, ADMFLAG_GENERIC);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

void achievement_earned(Event event, const char[] name, bool dontBroadcast)
{
	int player = event.GetInt("player");

	m_flNextAchievementAnnounceTime[player] = GetGameTime() + ACHIEVEMENT_ANNOUNCEMENT_MIN_TIME;
}

public void OnClientPutInServer(int client)
{
	if(dbAchiv != null) {
		QueryPlayerAchivData(dbAchiv, client);
	}

	if(dbMissi != null) {
		QueryPlayerMissiData(dbMissi, client);
	}
}

public void OnClientDisconnect(int client)
{
	delete PlayerAchivCache[client];
	bAchivCacheLoaded[client] = false;

	delete PlayerMissiCache[client];
	bMissiCacheLoaded[client] = false;

	m_flNextAchievementAnnounceTime[client] = 0.0;
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int len)
{
	CreateNative("Achievement.FindByName", NativeAchiv_FindByName);
	CreateNative("Achievement.FindByID", NativeAchiv_FindByID);
	CreateNative("Achievement.Award", NativeAchiv_AwardAchievement);
	CreateNative("Achievement.AwardProgress", NativeAchiv_AwardProgress);
	CreateNative("Achievement.GetProgress", NativeAchiv_GetProgress);
	CreateNative("Achievement.Max.get", NativeAchiv_GetMax);
	CreateNative("Achievement.HasAchieved", NativeAchiv_HasAchieved);
	CreateNative("Achievement.ID.get", NativeAchiv_GetID);
	CreateNative("Achievement.GetName", NativeAchiv_GetName);
	CreateNative("Achievement.GetDescription", NativeAchiv_GetDesc);
	CreateNative("Achievement.RemoveProgress", NativeAchiv_RemoveProgress);
	CreateNative("Achievement.Remove", NativeAchiv_Remove);
	CreateNative("Achievement.Length.get", NativeAchiv_GetCount);
	CreateNative("Achievement.GetPluginData", NativeAchiv_GetPluginData);
	CreateNative("Achievement.SetPluginData", NativeAchiv_SetPluginData);

	hOnAchievementDataLoaded = new GlobalForward("OnAchievementDataLoaded", ET_Ignore, Param_Cell);
	hOnAchievementsLoaded = new GlobalForward("OnAchievementsLoaded", ET_Ignore);

	hOnAchievementProgressChanged = new GlobalForward("OnAchievementProgressChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	hOnAchievementStatusChanged = new GlobalForward("OnAchievementStatusChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

	CreateNative("MissionEntry.Length.get", NativeMissi_GetCount);
	CreateNative("MissionEntry.FindByName", NativeMissi_FindByName);
	CreateNative("MissionEntry.FindByID", NativeMissi_FindByID);
	CreateNative("MissionEntry.GetName", NativeMissi_GetName);
	CreateNative("MissionEntry.GetDescription", NativeMissi_GetDesc);
	CreateNative("MissionEntry.ID.get", NativeMissi_GetID);
	CreateNative("MissionEntry.Max.get", NativeMissi_GetMax);
	CreateNative("MissionEntry.GiveToPlayer", NativeMissi_GiveToPlayer);

	CreateNative("PlayerMission.Find", NativeMissi_Find);
	CreateNative("PlayerMission.FindByName", NativeMissi_FindByName2);
	CreateNative("PlayerMission.FindByID", NativeMissi_FindByID2);
	CreateNative("PlayerMission.GiveByName", NativeMissi_GiveByName);
	CreateNative("PlayerMission.GiveByID", NativeMissi_GiveByID);

	hOnMissionDataLoaded = new GlobalForward("OnMissionDataLoaded", ET_Ignore, Param_Cell);
	hOnMissionsLoaded = new GlobalForward("OnMissionsLoaded", ET_Ignore);

	hOnMissionProgressChanged = new GlobalForward("OnMissionProgressChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	hOnMissionStatusChanged = new GlobalForward("OnMissionStatusChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

	RegPluginLibrary("achivmissions");
	return APLRes_Success;
}