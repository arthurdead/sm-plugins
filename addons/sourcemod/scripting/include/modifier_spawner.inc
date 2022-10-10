#if defined __modifier_spawner_inc
	#endinput
#endif
#define __modifier_spawner_inc

#if !defined REQUIRE_PLUGIN
	#define __MOD_POP_PL_OPTIONAL
#endif

#if !defined REQUIRE_EXTENSIONS
	#define __MOD_POP_EXT_OPTIONAL
#endif

#if defined __MOD_POP_OPTIONAL
	#undef REQUIRE_EXTENSIONS
	#undef REQUIRE_PLUGIN
#endif

#include <popspawner>

#if defined __MOD_POP_OPTIONAL
	#if !defined __MOD_POP_EXT_OPTIONAL
		#define REQUIRE_EXTENSIONS
	#endif
	#define REQUIRE_PLUGIN
#endif

#define MAX_MODIFIER_NAME 64

enum default_modifiers
{
	modifier_none,
	modifier_lighting,
	modifier_vampiric,
};

native bool modifier_spawner_parse(CustomPopulationSpawner spawner, KeyValues data);
native bool modifier_spawner_spawn(CustomPopulationSpawner spawner, const float pos[3], ArrayList result);

public SharedPlugin __pl_modifier_spawner =
{
	name = "modifier_spawner",
	file = "modifier_spawner.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_modifier_spawner_SetNTVOptional()
{
	MarkNativeAsOptional("modifier_spawner_parse");
	MarkNativeAsOptional("modifier_spawner_spawn");
}
#endif