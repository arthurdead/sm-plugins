#include <sourcemod>
#include <datamaps>
#include <sourcescramble>
#include <sdktools>
#include <wpnhack>

static int CTFThrowable_size = -1;
static Handle CTFThrowable_ctor;

static Address throwable_allocate(int size_modifier, any data)
{
	MemoryBlock block = new MemoryBlock(CTFThrowable_size + size_modifier);
	Address mem = block.Address;
	block.Disown();
	delete block;
	SDKCall(CTFThrowable_ctor, mem);
	return mem;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("throwable_enable");

	IEntityFactory spellbook_factory = EntityFactoryDictionary.find("tf_weapon_spellbook");
	CTFThrowable_size = spellbook_factory.Size;

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFThrowable::CTFThrowable");
	CTFThrowable_ctor = EndPrepSDKCall();

	delete gamedata;

	CustomEntityFactory factory = EntityFactoryDictionary.register_function("tf_weapon_throwable", throwable_allocate, CTFThrowable_size);
	CustomSendtable table = CustomSendtable.from_factory(factory);
	table.set_shared_name("TFThrowable");
	table.set_client_class_id("CTFThrowable");

	factory = EntityFactoryDictionary.register_function("tf_weapon_throwable_primary", throwable_allocate, CTFThrowable_size);
	table = CustomSendtable.from_factory(factory);
	table.set_shared_name("TFThrowablePrimary");
	table.set_client_class_id("CTFThrowable");

	factory = EntityFactoryDictionary.register_function("tf_weapon_throwable_secondary", throwable_allocate, CTFThrowable_size);
	table = CustomSendtable.from_factory(factory);
	table.set_shared_name("TFThrowableSecondary");
	table.set_client_class_id("CTFThrowable");

	factory = EntityFactoryDictionary.register_function("tf_weapon_throwable_melee", throwable_allocate, CTFThrowable_size);
	table = CustomSendtable.from_factory(factory);
	table.set_shared_name("TFThrowableMelee");
	table.set_client_class_id("CTFThrowable");

	factory = EntityFactoryDictionary.register_function("tf_weapon_throwable_utility", throwable_allocate, CTFThrowable_size);
	table = CustomSendtable.from_factory(factory);
	table.set_shared_name("TFThrowableUtility");
	table.set_client_class_id("CTFThrowable");

	precache_weapon_file("tf_weapon_throwable.txt", true);
	precache_weapon_file("tf_weapon_throwable_primary.txt", true);
	precache_weapon_file("tf_weapon_throwable_secondary.txt", true);
	precache_weapon_file("tf_weapon_throwable_melee.txt", true);
	precache_weapon_file("tf_weapon_throwable_utility.txt", true);
}

public void OnMapStart()
{
	PrecacheModel("models/weapons/c_models/c_balloon_default.mdl");
}
