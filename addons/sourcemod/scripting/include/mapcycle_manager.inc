#if defined __mapcycle_manager_inc
	#endinput
#endif
#define __mapcycle_manager_inc

enum MCM_ChangeFrom
{
	MCM_ChangedInitial,
	MCM_ChangedPlayerCount
};

forward void MCM_MapcycleChanged(ArrayList maps, MCM_ChangeFrom from);

public SharedPlugin __pl_mapcycle_manager =
{
	name = "mapcycle_manager",
	file = "mapcycle_manager.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_mapcycle_manager_SetNTVOptional()
{
	
}
#endif