#if defined achivmissions_included
	#endinput
#endif
#define achivmissions_included

#define MAX_ACHIEVEMENT_NAME 64
#define MAX_ACHIEVEMENT_DESCRIPTION 64

#define ACHIEVEMENT_ANNOUNCEMENT_MIN_TIME 10.0

native void DoAchievementEffects(int client);

#define Achievement_Null view_as<Achievement>(-1)

forward void OnAchievementDataLoaded(int client);
forward void OnAchievementsLoaded();

methodmap Achievement
{
	public static native int Count();

	public static native Achievement Get(int idx);

	public static native Achievement FindByName(const char[] name);
	public static native Achievement FindByID(int id);

	public native void GetName(char[] name, int len);
	public native void GetDescription(char[] desc, int len);

	property int ID
	{
		public native get();
	}

	public native bool AwardProgress(int client, int value);
	public native bool RemoveProgress(int client, int value);
	public native bool Award(int client);
	public native bool Remove(int client);

	public native any GetPluginData(int client);
	public native void SetPluginData(int client, any data);

	public native int GetProgress(int client);

	property int Max
	{
		public native get();
	}

	public native bool HasAchieved(int client);
};

forward void OnAchievementProgressChanged(int client, int oldprogress, int newprogress, Achievement achiv);
forward void OnAchievementStatusChanged(int client, bool achieved, Achievement achiv);

#define MAX_MISSION_NAME 64
#define MAX_MISSION_DESCRIPTION 64
#define MAX_MISSION_PARAMS 4

#define MissionEntry_Null view_as<MissionEntry>(-1)
#define MissionInstance_Null view_as<MissionInstance>(-1)

forward void OnMissionDataLoaded(int client);
forward void OnMissionsLoaded();

enum MissionParamType
{
	MPARAM_INVALID,
	MPARAM_INT,
	MPARAM_CLASS,
};

enum struct MissionParamInfo
{
	MissionParamType type;
	int min;
	int max;
}

#define MissionParamInfoVar any[]

methodmap MissionEntry
{
	public static native int Count();

	public static native MissionEntry Get(int idx);

	public static native MissionEntry FindByName(const char[] name);
	public static native MissionEntry FindByID(int id);

	public native void GetName(char[] name, int len);
	public native void GetDescription(char[] desc, int len);

	property int ID
	{
		public native get();
	}

	//public native void GetParamInfo(int idx, MissionParamInfoVar info);

	public native MissionInstance Give(int client);
	public native MissionInstance GiveEx(int client, int param_values[MAX_MISSION_PARAMS]);

	public native ArrayList GetInstanceCache(int client);

	public void Execute(int client, Function func, any data=0)
	{
		ArrayList instances = this.GetInstanceCache(client);
		if(instances == null) {
			return;
		}

		int len = instances.Length;
		for(int i = 0; i < len; ++i) {
			MissionInstance inst = instances.Get(i);
			if(inst.Completed) {
				continue;
			}

			Call_StartFunction(null, func);
			Call_PushCell(client);
			Call_PushCell(inst);
			Call_PushCell(data);
			Call_Finish();
		}
	}

	public void ExecuteAll(Function func, any data=0)
	{
		for(int i = 1; i <= MaxClients; ++i) {
			if(!IsClientInGame(i)) {
				continue;
			}

			this.Execute(i, func, data);
		}
	}
};

methodmap MissionInstance
{
	public static native int Count(int client);

	public static native MissionInstance Get(int client, int idx);

	property MissionEntry Entry
	{
		public native get();
	}

	property int ID
	{
		public native get();
	}

	public native void AwardProgress(int value);
	public native bool RemoveProgress(int value);
	public native bool Complete();
	public native void Cancel();
	public native bool TurnIn();

	public native void SetParamValue(int param, int value);
	public native int GetParamValue(int param);

	property any PluginData
	{
		public native get();
		public native set(any value);
	}

	property int Progress
	{
		public native get();
	}

	property bool Completed
	{
		public native get();
	}

	property int Owner
	{
		public native get();
	}
};

forward void OnMissionProgressChanged(int client, int oldprogress, int newprogress, MissionInstance inst);

enum MissionStatus
{
	MISSION_UNCOMPLETED,
	MISSION_COMPLETED,
	MISSION_CANCELED,
	MISSION_TURNEDIN,
};

forward void OnMissionStatusChanged(int client, MissionStatus status, MissionInstance inst);

public SharedPlugin __pl_achivmissions =
{
	name = "achivmissions",
	file = "achivmissions.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_achivmissions_SetNTVOptional()
{
	
}
#endif