#include <sourcemod>
#include <damagerules>
#include <datamaps>
#include <popspawner>

static ArrayList last_killed_data;

public void OnPluginStart()
{
	last_killed_data = new ArrayList(3);
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
			int target = -1;

			int attacker_userid = last_killed_data.Get(idx, 1);
			if(attacker_userid != -1) {
				int attacker = GetClientOfUserId(attacker_userid);
				if(attacker != 0) {
					target = attacker;
				}
			}

			if(target == -1) {
				int inflictor_userid = last_killed_data.Get(idx, 1);
				if(inflictor_userid != -1) {
					int inflictor = GetClientOfUserId(inflictor_userid);
					if(inflictor != 0) {
						target = inflictor;
					}
				}
			}

			if(target != -1) {
			#if 1
				claim_currency_pack(target, entity, 1.0);
			#else
				float pos[3];
				GetClientAbsOrigin(target, pos);
				TeleportEntity(entity, pos);
			#endif
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
	int attacker_userid = -1;
	int attacker = info.m_hAttacker;
	if(attacker >= 1 && attacker <= MaxClients) {
		attacker_userid = GetClientUserId(attacker);
	}

	int inflictor_userid = -1;
	int inflictor = info.m_hInflictor;
	if(inflictor >= 1 && inflictor <= MaxClients) {
		inflictor_userid = GetClientUserId(inflictor);
	}

	int ref = EntIndexToEntRef(entity);
	int idx = last_killed_data.FindValue(ref);
	if(idx == -1) {
		idx = last_killed_data.Push(ref);
	}

	last_killed_data.Set(idx, attacker_userid, 1);
	last_killed_data.Set(idx, inflictor_userid, 2);

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