#if defined __gamemode_manager_inc
	#endinput
#endif
#define __gamemode_manager_inc

enum gmm_gamemode_action
{
	gmm_gamemode_start,
	gmm_gamemode_end
}

forward void gmm_handle_gamemode(const char[] name, gmm_gamemode_action action);

forward Action gmm_map_valid_for_gamemode(const char[] name, const char[] map);

public SharedPlugin __pl_gamemode_manager =
{
	name = "gamemode_manager",
	file = "gamemode_manager.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_gamemode_manager_SetNTVOptional()
{
	
}
#endif