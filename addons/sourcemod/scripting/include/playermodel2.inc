#if defined __playermodel2_inc
	#endinput
#endif
#define __playermodel2_inc

#include <tf2>

forward void pm2_model_changed(int client);

native bool pm2_is_thirdperson(int client);

native void pm2_get_model(int client, char[] model, int len);

native void pm2_set_player_loser(int client, bool value);
native void pm2_set_player_animation(int client, const char[] model, TFClassType class = TFClass_Unknown);

native void pm2_unequip_config(int client);
native void pm2_equip_config(int client, const char[] name);

native void pm2_remove_attach_link(int client);
native int pm2_get_attach_link(int client);

public SharedPlugin __pl_playermodel2 =
{
	name = "playermodel2",
	file = "playermodel2.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_playermodel2_SetNTVOptional()
{
	MarkNativeAsOptional("pm2_get_model");
	MarkNativeAsOptional("pm2_is_thirdperson");
}
#endif