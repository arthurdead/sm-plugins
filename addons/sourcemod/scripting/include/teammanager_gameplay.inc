#if defined _teammanager_gameplay_inc_
	#endinput
#endif
#define _teammanager_gameplay_inc_

#define INVALID_GAMEPLAY_GROUP -1

enum GameplayGroupType
{
	Gameplay_Friendly,
	Gameplay_Normal,
	Gameplay_FriendlyFire,
};

native int TeamManager_NewGameplayGroup(GameplayGroupType type);

native void TeamManager_AddPlayerToGameplayGroup(int client, int group);
native void TeamManager_RemovePlayerFromGameplayGroup(int client, int group);

native void TeamManager_RemoveGameplayGroup(int group);

public SharedPlugin __pl_teammanager_gameplay =
{
	name = "teammanager_gameplay",
	file = "teammanager_gameplay.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_teammanager_gameplay_SetNTVOptional()
{
	MarkNativeAsOptional("TeamManager_NewGameplayGroup");
	MarkNativeAsOptional("TeamManager_AddPlayerToGameplayGroup");
	MarkNativeAsOptional("TeamManager_RemovePlayerFromGameplayGroup");
	MarkNativeAsOptional("TeamManager_RemoveGameplayGroup");
}
#endif