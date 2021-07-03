#if defined achivmissions_included
	#endinput
#endif
#define achivmissions_included

#define MAX_ACHIEVEMENT_NAME 64
#define MAX_ACHIEVEMENT_DESCRIPTION 64

#define ACHIEVEMENT_ANNOUNCEMENT_MIN_TIME 10.0

#define Achievement_Null view_as<Achievement>(-1)

forward void OnAchievementDataLoaded(int client);
forward void OnAchievementsLoaded();

methodmap Achievement
{
	property int Length
	{
		public native get();
	}

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
	public native void RemoveProgress(int client, int value);
	public native void Award(int client);
	public native void Remove(int client);

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

#define MissionEntry_Null view_as<MissionEntry>(-1)
#define PlayerMission_Null view_as<PlayerMission>(-1)

forward void OnMissionDataLoaded(int client);
forward void OnMissionsLoaded();

methodmap MissionEntry
{
	property int Length
	{
		public native get();
	}

	//public static native MissionEntry Get(int idx);

	public static native MissionEntry FindByName(const char[] name);
	public static native MissionEntry FindByID(int id);

	public native void GetName(char[] name, int len);
	public native void GetDescription(char[] desc, int len);

	property int ID
	{
		public native get();
	}

	property int Max
	{
		public native get();
	}

	public native PlayerMission GiveToPlayer(int client);
};

methodmap PlayerMission
{
	//public static native int Count(int client);

	//public static native PlayerMission Get(int client, int idx);

	public static native PlayerMission Find(int client, MissionEntry missi);
	public static native PlayerMission FindByName(int client, const char[] name);
	public static native PlayerMission FindByID(int client, int id);

	public static native PlayerMission GiveByName(int client, const char[] name);
	public static native PlayerMission GiveByID(int client, int id);

	property MissionEntry Entry
	{
		public native get();
	}

	public native bool AwardProgress(int value);
	public native void RemoveProgress(int value);
	public native void Complete();
	public native void Cancel();
	public native void TurnIn();

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
};

forward void OnMissionProgressChanged(int client, int oldprogress, int newprogress, PlayerMission missi);

enum MissionStatus
{
	MISSION_COMPLETED,
	MISSION_CANCELED,
	MISSION_TURNEDIN,
};

forward void OnMissionStatusChanged(int client, MissionStatus status, PlayerMission missi);

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