#if defined _moreinfected_inc_
	#endinput
#endif
#define _moreinfected_inc_

#tryinclude <datamaps>

enum infected_directive
{
	directive_wanderer,
	directive_ambient,
	directive_attack,
};

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
	char data[MAX_DATA_LENGTH];
}

typeset moreinfected_functions
{
	//precache
	function void (moreinfected_data data);

	//spawn common
	function int (int entity, Address area, float pos[3], infected_directive directive, moreinfected_data data);

	//spawn special
	function int (int entity, Address area, float pos[3], float ang[3], ZombieClassType type, moreinfected_data data);
};

#if defined datamaps_included
stock CustomSendtable sendtable_from_infected_factory(CustomEntityFactory factory)
{
	return CustomSendtable.from_factory(factory, "Infected");
}

stock CustomEntityFactory register_infected_factory(const char[] classname)
{
#if 0
	CustomEntityFactory factory = EntityFactoryDictionary.register_based_name(classname, "infected");
	CustomSendtable sendtable = sendtable_from_infected_factory(factory);
	sendtable.override_with("NextBotCombatCharacter");
#else
	CustomEntityFactory factory = register_nextbot_factory(classname);
#endif
	return factory;
}
#endif

public SharedPlugin __pl_moreinfected =
{
	name = "moreinfected",
	file = "moreinfected.smx",
	required = 0,
};