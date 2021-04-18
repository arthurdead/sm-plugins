#if defined _moreinfected_inc_
	#endinput
#endif
#define _moreinfected_inc_

#define MI_MAX_NAME_LEN 64
#define MI_MAX_FUNC_LEN (MI_MAX_NAME_LEN+14)
#define MI_MAX_PLACE_LEN 64
#define MI_MAX_PLUGIN_LEN 64
#define MI_MAX_DATA_LEN 1024

#define MI_MAX_CLASS_LEN 97
#define MI_MAX_DIRECTIVE_LEN 42
#define MI_MAX_GENDER_LEN 15

#define MI_MAX_MODEL_LEN 64

enum InfectedSpawnDirective
{
	SpawnDirective_Wanderer,
	SpawnDirective_Ambient,
	SpawnDirective_Attack,
};

enum infected_directive_flags
{
	directive_flags_invalid = 0,
	directive_flags_wanderer = (1 << 0),
	directive_flags_ambient = (1 << 1),
	directive_flags_attack = (1 << 2),
}

enum infected_class_flags
{
	class_flags_invalid = 0,
	class_flags_common = (1 << 0),
	class_flags_tank = (1 << 1),
	class_flags_smoker = (1 << 2),
	class_flags_charger = (1 << 3),
	class_flags_boomer = (1 << 4),
	class_flags_hunter = (1 << 5),
	class_flags_jockey = (1 << 6),
	class_flags_spitter = (1 << 7),
	class_flags_witch = (1 << 8),
	class_flags_witch_bride = (1 << 9),
}

enum ZombieClassType
{
	ZombieClass_Common,
	ZombieClass_Smoker,
	ZombieClass_Boomer,
	ZombieClass_Hunter,
	ZombieClass_Spitter,
	ZombieClass_Jockey,
	ZombieClass_Charger,
	ZombieClass_Witch,
	ZombieClass_Tank,
	ZombieClass_Invalid,
}

enum struct moreinfected_data
{
	char name[MI_MAX_NAME_LEN];
	infected_class_flags class_flags;
	infected_directive_flags directive_flags;
	KeyValues data;
}

typeset moreinfected_functions
{
	//precache
	function void (moreinfected_data data);

	//spawn common
	function int (int entity, Address area, float pos[3], InfectedSpawnDirective directive, moreinfected_data data);

	//spawn special
	function int (int entity, Address area, float pos[3], float ang[3], ZombieClassType type, moreinfected_data data);
};

public SharedPlugin __pl_moreinfected =
{
	name = "moreinfected",
	file = "moreinfected.smx",
	required = 0,
};