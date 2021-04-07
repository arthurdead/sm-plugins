#if defined _moreinfected_inc_
	#endinput
#endif
#define _moreinfected_inc_

enum CommonInfectedSpawnDirective
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
	ZombieClassType_Smoker = 1,
	ZombieClassType_Boomer,
	ZombieClassType_Hunter,
	ZombieClassType_Spitter,
	ZombieClassType_Jockey,
	ZombieClassType_Charger,
	ZombieClassType_Witch,
	ZombieClassType_Tank,
}

#define MAX_DATA_LENGTH 64

enum struct moreinfected_data
{
	infected_class_flags class_flags;
	infected_directive_flags directive_flags;
	char data[MAX_DATA_LENGTH];
}

typeset moreinfected_functions
{
	//precache
	function void (moreinfected_data data);

	//spawn common
	function int (int entity, Address area, float pos[3], CommonInfectedSpawnDirective directive, moreinfected_data data);

	//spawn special
	function int (int entity, Address area, float pos[3], float ang[3], ZombieClassType type, moreinfected_data data);
};

public SharedPlugin __pl_moreinfected =
{
	name = "moreinfected",
	file = "moreinfected.smx",
	required = 0,
};