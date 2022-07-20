#if defined __mapcycle_manager_inc
	#endinput
#endif
#define __mapcycle_manager_inc

enum mcm_changed_from
{
	mcm_changed_initial,
	mcm_changed_player_count
};

forward void mcm_changed(ArrayList maps, mcm_changed_from from);

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