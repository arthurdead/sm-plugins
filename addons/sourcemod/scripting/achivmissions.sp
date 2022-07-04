#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <stocksoup/tf/tempents_stocks.inc>
#include <achivmissions>
#include <bit>

//#define DEBUG

#define QUERY_STR_MAX 1024
#define INT_STR_MAX 4

//TODO!!! use prepared statements?

void OnErrorTransaction(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("%s", error);
}

void OnErrorQuery(Database db, DBResultSet results, const char[] error, any data)
{
	if(!results) {
		LogError("%s", error);
	}
}

char __ignorename[1];
bool __ignoreisml;

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
#include "achivmissions/missi_cmds.sp"

public void OnPluginStart()
{
	load_databases();

	HookEvent("achievement_earned", achievement_earned);

	RegConsoleCmd("sm_achievements", sm_achievements);
	RegConsoleCmd("sm_achivs", sm_achievements);

	RegConsoleCmd("sm_missions", sm_missions);
	RegConsoleCmd("sm_missis", sm_missions);

	RegAdminCmd("sm_achivgiv", sm_achivgiv, ADMFLAG_GENERIC);
	RegAdminCmd("sm_achivprog", sm_achivprog, ADMFLAG_GENERIC);
	RegAdminCmd("sm_achivrem", sm_achivrem, ADMFLAG_GENERIC);
	RegAdminCmd("sm_achivremprog", sm_achivremprog, ADMFLAG_GENERIC);

	RegAdminCmd("sm_missigiv", sm_missigiv, ADMFLAG_GENERIC);

	RegAdminCmd("sm_missiachiv_reload", sm_archiv_reload, ADMFLAG_ROOT);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

void unload_databases()
{
	delete dbAchiv;
	delete achiv_names;
	delete achiv_descs;
	delete mapAchivIds;

	delete dbMissi;
	delete mapMissiIds;
	delete missi_names;
	delete missi_descs;
}

void load_databases()
{
	if(SQL_CheckConfig("achievements")) {
		Database.Connect(OnAchivDatabaseConnect, "achievements");
	}

	if(SQL_CheckConfig("missions")) {
		Database.Connect(OnMissiDatabaseConnect, "missions");
	}
}

Action sm_archiv_reload(int client, int args)
{
	unload_databases();
	load_databases();

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientDisconnect(i);
			OnClientPutInServer(i);
		}
	}

	return Plugin_Handled;
}

void achievement_earned(Event event, const char[] name, bool dontBroadcast)
{
	int player = event.GetInt("player");

	m_flNextAchievementAnnounceTime[player] = GetGameTime() + ACHIEVEMENT_ANNOUNCEMENT_MIN_TIME;
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client)) {
		return;
	}

	if(dbAchiv != null) {
		QueryPlayerAchivData(dbAchiv, client);
	}

	if(dbMissi != null) {
		QueryPlayerMissiData(dbMissi, client);
	}
}

public void OnClientDisconnect(int client)
{
	if(missi_map != null) {
		missi_map.RemoveClient(client);
	}

	delete PlayerAchivCache[client];
	bAchivCacheLoaded[client] = false;

	delete PlayerMissiCache[client];
	bMissiCacheLoaded[client] = false;

	m_flNextAchievementAnnounceTime[client] = 0.0;
}

int Native_DoAchievementEffects(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	if(ShouldAnnounceAchievement(client)) {
		OnAchievementAchieved(client);
	}

	return 0;
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int len)
{
	CreateNative("DoAchievementEffects", Native_DoAchievementEffects);

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
	CreateNative("Achievement.Count", NativeAchiv_GetCount);
	CreateNative("Achievement.GetPluginData", NativeAchiv_GetPluginData);
	CreateNative("Achievement.SetPluginData", NativeAchiv_SetPluginData);
	CreateNative("Achievement.Get", NativeAchiv_Get);

	hOnAchievementDataLoaded = new GlobalForward("OnAchievementDataLoaded", ET_Ignore, Param_Cell);
	hOnAchievementsLoaded = new GlobalForward("OnAchievementsLoaded", ET_Ignore);

	hOnAchievementProgressChanged = new GlobalForward("OnAchievementProgressChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	hOnAchievementStatusChanged = new GlobalForward("OnAchievementStatusChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

	CreateNative("MissionEntry.Count", NativeMissi_GetCount);
	CreateNative("MissionEntry.FindByName", NativeMissi_FindByName);
	CreateNative("MissionEntry.FindByID", NativeMissi_FindByID);
	CreateNative("MissionEntry.GetName", NativeMissi_GetName);
	CreateNative("MissionEntry.GetDescription", NativeMissi_GetDesc);
	CreateNative("MissionEntry.ID.get", NativeMissi_GetID);
	CreateNative("MissionEntry.Give", NativeMissi_GiveToPlayer);
	CreateNative("MissionEntry.GiveEx", NativeMissi_GiveToPlayerEx);
	CreateNative("MissionEntry.Get", NativeMissi_Get);
	CreateNative("MissionEntry.GetInstanceCache", NativeMissi_GetInstanceCache);

	CreateNative("MissionInstance.Count", NativePlrMissi_Count);
	CreateNative("MissionInstance.Get", NativePlrMissi_Get);
	CreateNative("MissionInstance.Entry.get", NativePlrMissi_GetEntry);
	CreateNative("MissionInstance.AwardProgress", NativePlrMissi_AwardProgress);
	CreateNative("MissionInstance.RemoveProgress", NativePlrMissi_RemoveProgress);
	CreateNative("MissionInstance.Complete", NativePlrMissi_Complete);
	CreateNative("MissionInstance.Cancel", NativePlrMissi_Cancel);
	CreateNative("MissionInstance.TurnIn", NativePlrMissi_TurnIn);
	CreateNative("MissionInstance.SetParamValue", NativePlrMissi_SetParamValue);
	CreateNative("MissionInstance.GetParamValue", NativePlrMissi_GetParamValue);
	CreateNative("MissionInstance.PluginData.get", NativePlrMissi_GetPluginData);
	CreateNative("MissionInstance.Progress.get", NativePlrMissi_GetProgress);
	CreateNative("MissionInstance.Completed.get", NativePlrMissi_GetCompleted);
	CreateNative("MissionInstance.Owner.get", NativePlrMissi_GetOwner);
	CreateNative("MissionInstance.PluginData.set", NativePlrMissi_SetPluginData);
	CreateNative("MissionInstance.ID.get", NativePlrMissi_GetID);

	hOnMissionDataLoaded = new GlobalForward("OnMissionDataLoaded", ET_Ignore, Param_Cell);
	hOnMissionsLoaded = new GlobalForward("OnMissionsLoaded", ET_Ignore);

	hOnMissionProgressChanged = new GlobalForward("OnMissionProgressChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	hOnMissionStatusChanged = new GlobalForward("OnMissionStatusChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

	RegPluginLibrary("achivmissions");
	return APLRes_Success;
}