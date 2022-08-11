#include <sourcemod>
#include <sdktools>
#include <popspawner>

//#define DEBUG

#define SKELETON_NORMAL 0
#define SKELETON_KING 1
#define SKELETON_MINI 2

#define TF_TEAM_HALLOWEEN 4

static ConVar tf_halloween_bot_health_base;
static ConVar tf_halloween_bot_min_player_count;
static ConVar tf_halloween_bot_health_per_player;

public void OnPluginStart()
{
	tf_halloween_bot_health_base = FindConVar("tf_halloween_bot_health_base");
	tf_halloween_bot_min_player_count = FindConVar("tf_halloween_bot_min_player_count");
	tf_halloween_bot_health_per_player = FindConVar("tf_halloween_bot_health_per_player");

	CustomPopulationSpawner spawner = register_popspawner("Zombie");
	spawner.Parse = zombie_pop_parse;
	spawner.Spawn = zombie_pop_spawn;
	spawner.GetClass = zombie_pop_class;
	spawner.GetHealth = zombie_pop_health;
	spawner.HasAttribute = zombie_pop_attribute;

	spawner = register_popspawner("HeadlessHatmann");
	spawner.Parse = hhh_pop_parse;
	spawner.Spawn = hhh_pop_spawn;
	spawner.GetClass = hhh_pop_class;
	spawner.GetHealth = hhh_pop_health;
	spawner.HasAttribute = hhh_pop_attribute;
}

public void OnMapStart()
{
	PrecacheModel("models/bots/skeleton_sniper_boss/skeleton_sniper_boss.mdl");
	PrecacheModel("models/player/items/demo/crown.mdl");
}

static bool zombie_pop_parse(CustomPopulationSpawner spawner, KeyValues data)
{
	char value[10];
	data.GetString("type", value, sizeof(value));

	if(value[0] == '\0' || StrEqual(value, "Normal")) {
		spawner.set_data("type", SKELETON_NORMAL);
	} else if(StrEqual(value, "King")) {
		spawner.set_data("type", SKELETON_KING);
	} else if(StrEqual(value, "Mini")) {
		spawner.set_data("type", SKELETON_MINI);
	} else {
		return false;
	}

	return true;
}

static bool zombie_pop_spawn(CustomPopulationSpawner spawner, float pos[3], ArrayList result)
{
	int entity = CreateEntityByName("tf_zombie");
	TeleportEntity(entity, pos);
	SetEntProp(entity, Prop_Send, "m_iTeamNum", TF_TEAM_HALLOWEEN);
	DispatchSpawn(entity);

	switch(spawner.get_data("type")) {
		case SKELETON_KING: {
			SetEntityModel(entity, "models/bots/skeleton_sniper_boss/skeleton_sniper_boss.mdl");
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 2.0);
			SetEntProp(entity, Prop_Data, "m_iHealth", 1000);
			SetEntProp(entity, Prop_Data, "m_iMaxHealth", 1000);
		}
		case SKELETON_MINI: {
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 0.5);
		}
	}

#if defined DEBUG
	PrintToServer("zombie_pop_spawn [%f, %f, %f]", pos[0], pos[1], pos[2]);
#endif

	if(result) {
		result.Push(entity);
	}

	return true;
}

static TFClassType zombie_pop_class(CustomPopulationSpawner spawner, int num)
{
	return TFClass_Sniper;
}

static int zombie_pop_health(CustomPopulationSpawner spawner, int num)
{
	switch(spawner.get_data("type")) {
		case SKELETON_KING: return 1000;
	}

	return 50;
}

static bool zombie_pop_attribute(CustomPopulationSpawner spawner, AttributeType attr, int num)
{
	AttributeType flags = NPC_POP_FLAGS;
	if(spawner.get_data("type") == SKELETON_KING) {
		flags = BOSS_NPC_POP_FLAGS;
	}

	return !!(attr & flags);
}

static bool hhh_pop_parse(CustomPopulationSpawner spawner, KeyValues data)
{
	return true;
}

static bool hhh_pop_spawn(CustomPopulationSpawner spawner, float pos[3], ArrayList result)
{
	int entity = CreateEntityByName("headless_hatman");
	TeleportEntity(entity, pos);
	SetEntProp(entity, Prop_Send, "m_iTeamNum", TF_TEAM_HALLOWEEN);
	DispatchSpawn(entity);

	if(result) {
		result.Push(entity);
	}

	return true;
}

static TFClassType hhh_pop_class(CustomPopulationSpawner spawner, int num)
{
	return TFClass_DemoMan;
}

static int hhh_pop_health(CustomPopulationSpawner spawner, int num)
{
	int health = tf_halloween_bot_health_base.IntValue;

	int num_players = 0;
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			GetClientTeam(i) < 2) {
			continue;
		}
		++num_players;
	}

	int min_players = tf_halloween_bot_min_player_count.IntValue;
	if(num_players > min_players) {
		health += ((num_players - min_players) * tf_halloween_bot_health_per_player.IntValue);
	}

	return health;
}

static bool hhh_pop_attribute(CustomPopulationSpawner spawner, AttributeType attr, int num)
{
	return !!(attr & BOSS_NPC_POP_FLAGS);
}