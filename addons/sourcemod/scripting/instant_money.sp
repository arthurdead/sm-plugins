#include <sourcemod>
#include <damagerules>
#include <datamaps>
#include <popspawner>
#include <teammanager>

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
				if(GetClientTeam(target) != TF_TEAM_PVE_DEFENDERS) {
					target = -1;
				}
			}

			if(target == -1) {
				float my_pos[3];
				GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", my_pos);

				int closest_player = -1;
				float last_distance = 99999999.0;

				for(int i = 1; i <= MaxClients; ++i) {
					if(!IsClientInGame(i) ||
						IsClientSourceTV(i) ||
						IsClientReplay(i)) {
						continue;
					}

					if(GetClientTeam(i) != TF_TEAM_PVE_DEFENDERS ||
						!IsPlayerAlive(i)) {
						continue;
					}

					float plr_pos[3];
					GetClientAbsOrigin(i, plr_pos);

					float distance = GetVectorDistance(my_pos, plr_pos);
					if(distance < last_distance) {
						closest_player = i;
						last_distance = distance;
					}
				}

				if(closest_player != -1) {
					target = closest_player;
				}
			}

			if(target != -1) {
				claim_currency_pack(target, entity, 1.0);
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

	//^^^ TODO!!! call CTFGameRules::GetDeathScorer / CTFGameRules::GetAssister

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
	if(StrContains(classname, "item_currencypack") != -1) {
		SDKHook(entity, SDKHook_SpawnPost, currency_spawn);
	}
}