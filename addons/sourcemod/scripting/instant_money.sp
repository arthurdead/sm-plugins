#include <sourcemod>
#include <damagerules>
#include <datamaps>
#include <popspawner>

static ArrayList last_killed_data;

public void OnPluginStart()
{
	last_killed_data = new ArrayList(2);
}

static void frame_currency_spawn(int entity)
{
	entity = EntRefToEntIndex(entity);
	if(entity == -1) {
		return;
	}

	SetEntityNextThink(entity, TIME_NEVER_THINK, "PowerupRemoveThink");

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(owner != -1) {
		int idx = last_killed_data.FindValue(EntIndexToEntRef(owner));
		if(idx != -1) {
			int attacker = GetClientOfUserId(last_killed_data.Get(idx, 1));
			if(attacker != 0) {
				float pos[3];
				GetClientAbsOrigin(attacker, pos);
				TeleportEntity(entity, pos);
			}
		}
	}
}

static void currency_spawn(int entity)
{
	RequestFrame(frame_currency_spawn, EntIndexToEntRef(entity));
}

static Action pop_entity_killed(int entity, CTakeDamageInfo info)
{
	int attacker = info.m_hAttacker;
	if(attacker < 1 || attacker > MaxClients) {
		int inflictor = info.m_hInflictor;
		if(inflictor >= 1 && inflictor <= MaxClients) {
			attacker = inflictor;
		} else {
			return Plugin_Continue;
		}
	}

	int userid = GetClientUserId(attacker);

	int ref = EntIndexToEntRef(entity);
	int idx = last_killed_data.FindValue(ref);
	if(idx == -1) {
		idx = last_killed_data.Push(ref);
	}

	last_killed_data.Set(idx, userid, 1);

	return Plugin_Continue;
}

public void pop_entity_spawned(IPopulator populator, IPopulationSpawner spawner, SpawnLocation location, int entity)
{
	HookEntityKilled(entity, pop_entity_killed, true);
}

public void OnEntityDestroyed(int entity)
{
	if(entity == -1) {
		return;
	}

	if(entity & (1 << 31)) {
		entity = EntRefToEntIndex(entity);
	}

	int idx = last_killed_data.FindValue(EntIndexToEntRef(entity));
	if(idx != -1) {
		last_killed_data.Erase(idx);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "item_currencypack_large") ||
		StrEqual(classname, "item_currencypack_medium") ||
		StrEqual(classname, "item_currencypack_small") ||
		StrEqual(classname, "item_currencypack_custom")) {
		SDKHook(entity, SDKHook_SpawnPost, currency_spawn);
	}
}