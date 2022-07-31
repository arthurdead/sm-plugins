#if defined __vgui_watcher_inc
	#endinput
#endif
#define __vgui_watcher_inc

enum player_vgui_state
{
	player_vgui_none,
	player_vgui_team,
	player_vgui_class
};

native player_vgui_state player_current_vgui(int client);
native bool player_is_opening_vgui(int client);
native bool player_is_closing_class_vgui(int client);

forward void player_opened_vgui(int client, player_vgui_state which);
forward void player_closed_vgui(int client, player_vgui_state which);
forward void player_closing_class_vgui(int client);
forward void player_opening_vgui(int client);

public SharedPlugin __pl_vgui_watcher =
{
	name = "vgui_watcher",
	file = "vgui_watcher.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_vgui_watcher_SetNTVOptional()
{
	
}
#endif