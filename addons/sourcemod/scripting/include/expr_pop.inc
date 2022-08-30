#if defined __expr_pop_inc
	#endinput
#endif
#define __expr_pop_inc

#include <popspawner>

enum entity_healthbar_t
{
	entity_healthbar_none,
	entity_healthbar_boss,
	entity_healthbar_last,
};

native bool expr_pop_parse(CustomPopulationSpawner spawner, KeyValues data);
native bool expr_pop_spawn(CustomPopulationSpawner spawner, const float pos[3], ArrayList result);

stock int expr_pop_health(CustomPopulationSpawner spawner, int num)
{
	if(spawner.has_data("health")) {
		return spawner.get_data("health");
	} else {
		return 0;
	}
}

stock bool expr_pop_attribute(CustomPopulationSpawner spawner, AttributeType attr, int num)
{
	entity_healthbar_t healthbar = entity_healthbar_none;
	if(spawner.has_data("healthbar")) {
		healthbar = spawner.get_data("healthbar");
	}

	if((healthbar == entity_healthbar_boss) && !!(attr & (MINIBOSS|USE_BOSS_HEALTH_BAR))) {
		return true;
	}

	return false;
}

public SharedPlugin __pl_expr_pop =
{
	name = "expr_pop",
	file = "expr_pop.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_expr_pop_SetNTVOptional()
{
	
}
#endif