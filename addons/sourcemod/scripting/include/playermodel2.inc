#if defined __playermodel2_inc
	#endinput
#endif
#define __playermodel2_inc

forward void pm2_model_changed(int client);

native void pm2_get_model(int client, char[] model, int len);

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
public __pl_playermodel2_SetNTVOptional()
{
	MarkNativeAsOptional("pm2_get_model");
}
#endif