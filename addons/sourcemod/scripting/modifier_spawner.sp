#include <sourcemod>
#include <popspawner>
#include <sdktools>
#include <sdkhooks>
#include <modifier_spawner>
#include <nextbot>
#include <damagerules>
#include <animhelpers>

#define DEBUG

static bool late_load;

#define SOLID_NONE 0
#define FSOLID_NOT_SOLID 0x0004
#define COLLISION_GROUP_NONE 0

Action entity_disable_touch(int entity, int other)
{
	return Plugin_Handled;
}

stock int create_dummy_projectile(const char[] classname, int entity)
{
	float pos[3];
	EntityWorldSpaceCenter(entity, pos);

	float ang[3];
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);

	int proj = CreateEntityByName(classname);
	SDKHook(proj, SDKHook_Touch, entity_disable_touch);
	SDKHook(proj, SDKHook_StartTouch, entity_disable_touch);
	TeleportEntity(proj, pos, ang);
	SetEntProp(proj, Prop_Data, "m_iInitialTeamNum", GetEntProp(entity, Prop_Data, "m_iInitialTeamNum"));
	SetEntityOwner(proj, entity);
	DispatchSpawn(proj);
	SetEntityMoveType(proj, MOVETYPE_NONE);
	SetEntProp(proj, Prop_Send, "m_nSolidType", SOLID_NONE);
	SetEntityCollisionGroup(proj, COLLISION_GROUP_NONE);
	int solidflags = GetEntProp(proj, Prop_Send, "m_usSolidFlags");
	solidflags |= FSOLID_NOT_SOLID;
	SetEntProp(proj, Prop_Send, "m_usSolidFlags", solidflags);
	ActivateEntity(proj);
	SetEntProp(proj, Prop_Send, "m_iTeamNum", GetEntProp(entity, Prop_Send, "m_iTeamNum"));

	SetVariantString("!activator");
	AcceptEntityInput(proj, "SetParent", entity);

	return proj;
}

#include "modifier_spawner/lightning.sp"
#undef ModifierInfo

#include "modifier_spawner/vampiric.sp"
#undef ModifierInfo

static void modifiers_plugin_init()
{
	lightning_plugin_init();
	vampiric_plugin_init();
}

static int get_modifier_idx(const char[] name)
{
	if(StrEqual(name, "None")) {
		return modifier_none;
	} else if(StrEqual(name, "Lightning")) {
		return modifier_lighting;
	} else if(StrEqual(name, "Vampiric")) {
		return modifier_vampiric;
	}

	return -1;
}

static bool modifier_parse(int idx, CustomPopulationSpawner spawner, KeyValues data)
{
	switch(idx) {
		case modifier_none:
		return true;
		case modifier_lighting:
		return lightning_parse(spawner, data);
		case modifier_vampiric:
		return vampiric_parse(spawner, data);
	}

	return false;
}

static bool modifier_entity_init(int idx, int entity)
{
	switch(idx) {
		case modifier_none:
		return true;
		case modifier_lighting:
		return lighting_entity_init(entity);
		case modifier_vampiric:
		return vampiric_entity_init(entity);
	}

	return false;
}

public void modifier_entity_destroyed(int entity)
{
	lightning_entity_destroyed(entity);
	vampiric_entity_destroyed(entity);
}

public void modifier_entity_created(int entity, const char[] classname)
{
	lighting_entity_created(entity, classname);
	vampiric_entity_created(entity, classname);
}

static void modifier_check_late_load(int entity, const char[] classname)
{
	lightning_check_late_load(entity, classname);
	vampiric_check_late_load(entity, classname);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	late_load = late;
	RegPluginLibrary("modifier_spawner");
	CreateNative("modifier_spawner_parse", native_modifier_spawner_parse);
	CreateNative("modifier_spawner_spawn", native_modifier_spawner_spawn);
	return APLRes_Success;
}

static Action sm_mspawn(int client, int args)
{
	if(args < 2) {
		return Plugin_Handled;
	}

	char classname[64];
	GetCmdArg(1, classname, sizeof(classname));

	char modifier_name[MAX_MODIFIER_NAME];
	GetCmdArg(2, modifier_name, MAX_MODIFIER_NAME);

	int idx = get_modifier_idx(modifier_name);

	float pos[3];
	GetClientAbsOrigin(client, pos);

	int entity = CreateEntityByName(classname);
	TeleportEntity(entity, pos);
	DispatchSpawn(entity);
	ActivateEntity(entity);

	modifier_entity_init(idx, entity);

	return Plugin_Handled;
}

public void OnPluginStart()
{
	modifiers_plugin_init();

	RegAdminCmd("sm_mspawn", sm_mspawn, ADMFLAG_ROOT);

	if(late_load) {
		int entity = -1;
		char classname[64];
		while((entity = FindEntityByClassname(entity, "*")) != -1) {
			GetEntityClassname(entity, classname, sizeof(classname));
			OnEntityCreated(entity, classname);

			entity_check_late_load(entity, classname);
		}
	}
}

static int native_modifier_spawner_parse(Handle plugin, int params)
{
	CustomPopulationSpawner spawner = GetNativeCell(1);
	KeyValues data = GetNativeCell(2);

	ArrayList modifiers = new ArrayList(2);

	bool valid = true;
	bool section_valid = false;

	if(data.JumpToKey("Modifiers")) {
		section_valid = true;

		if(data.GotoFirstSubKey()) {
			char modifier_name[MAX_MODIFIER_NAME];

			do {
				data.GetSectionName(modifier_name, MAX_MODIFIER_NAME);

				int sym = -1;
				if(!data.GetSectionSymbol(sym)) {
					valid = false;
					break;
				}

				int idx = get_modifier_idx(modifier_name);
				if(idx == -1) {
					valid = false;
					break;
				}

				idx = modifiers.Push(idx);
				modifiers.Set(idx, sym, 1);
			} while(data.GotoNextKey());
			data.GoBack();
		}
		data.GoBack();
	}

	if(!valid) {
		delete modifiers;
		return 0;
	}

	int len = modifiers.Length;
	if(len == 0) {
		delete modifiers;
		return section_valid ? 0 : 1;
	}

	int idx = (GetURandomInt() % len);
	int modifier = modifiers.Get(idx);
	int sym = modifiers.Get(idx, 1);

	if(!data.JumpToKey("Modifiers")) {
		data.GoBack();
		delete modifiers;
		return 0;
	}

	if(!data.JumpToKeySymbol(sym)) {
		data.GoBack();
		delete modifiers;
		return 0;
	}

	if(!modifier_parse(modifier, spawner, data)) {
		data.GoBack();
		delete modifiers;
		return 0;
	}

	data.GoBack();
	data.GoBack();

	delete modifiers;

	spawner.set_data("modifier", modifier);

	return 1;
}

public void OnEntityDestroyed(int entity)
{
	if(entity == -1) {
		return;
	}

	if(entity & (1 << 31)) {
		entity = EntRefToEntIndex(entity);
	}

	modifier_entity_destroyed(entity);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	modifier_entity_created(entity, classname);
}

static void entity_check_late_load(int entity, const char[] classname)
{
	modifier_check_late_load(entity, classname);
}

static int native_modifier_spawner_spawn(Handle plugin, int params)
{
	ArrayList result = GetNativeCell(3);
	if(!result) {
		return 1;
	}

	CustomPopulationSpawner spawner = GetNativeCell(1);

	if(!spawner.has_data("modifier")) {
		return 1;
	}

	float pos[3];
	GetNativeArray(2, pos, 3);

	int modifier = spawner.get_data("modifier");

	int len = result.Length;
	for(int i = 0; i < len; ++i) {
		int entity = result.Get(i);

		if(!modifier_entity_init(modifier, entity)) {
			return 0;
		}
	}

	return 1;
}