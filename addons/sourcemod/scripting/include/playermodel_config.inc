#if defined _playermodel_config_included_
	#endinput
#endif
#define _playermodel_config_included_

enum
{
	playermodel_noflags = 0,
	playermodel_hidehats = (1 << 1),
	playermodel_hideweapons = (1 << 3),
};

native int Playermodel_GetFlags(int client);

public SharedPlugin __pl_playermodel_config = 
{
	name = "playermodel_config",
	file = "playermodel_config.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_playermodel_config_SetNTVOptional()
{
	MarkNativeAsOptional("Playermodel_GetFlags");
}
#endif