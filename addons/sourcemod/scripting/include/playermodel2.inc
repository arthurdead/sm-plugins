#if defined __playermodel_inc
	#endinput
#endif
#define __playermodel_inc

#if defined GAME_TF2
	#include <tf2>
	#include <tf2_stocks>
#endif

enum playermodelslot
{
	playermodelslot_animation,
	playermodelslot_model,
	playermodelslot_skin,
	playermodelslot_bodygroup,
};

enum playermodelflags
{
	playermodel_noflags = 0,
	playermodel_hidehats = (1 << 1),
	playermodel_hideweapons = (1 << 2),
	playermodel_nogameplay = (1 << 3),
	playermodel_noweapons = (1 << 4),
	playermodel_nohats = (1 << 5),
	playermodel_nevermerge = (1 << 6),
	playermodel_alwaysmerge = (1 << 7),
};

native playermodelflags pm2_getflags(int client);

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
	
}
#endif
