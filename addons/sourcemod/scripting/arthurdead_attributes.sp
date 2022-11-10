#include <sourcemod>
#include <nextbot>
#include <damagerules>
#include <teammanager>
#include <sdktools>
#include <animhelpers>
#include <sm_npcs>
#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>
#include <wpnhack>
#include <datamaps>

#define PATTACH_CUSTOMORIGIN 2
#define PATTACH_WORLDORIGIN 5

static bool late_loaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	late_loaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CustomEntityFactory vortex_factory = EntityFactoryDictionary.register_based("attribute_teleport_vortex", "hightower_teleport_vortex");
	CustomDatamap vortex_datamap = CustomDatamap.from_factory(vortex_factory);
	vortex_datamap.add_prop("m_flLifetime", custom_prop_time);
	vortex_datamap.add_prop("m_hWeapon", custom_prop_ehandle);

	if(late_loaded) {
		ArrayList bots = new ArrayList();
		CollectAllBots(bots);
		int len = bots.Length;
		for(int i = 0; i < len; ++i) {
			INextBot bot = bots.Get(i);
			int entity = bot.Entity;
			OnNextbotSpawned(bot, entity);
		}
		delete bots;

		for(int i = 1; i <= MaxClients; ++i) {
			if(IsClientInGame(i)) {
				OnClientPutInServer(i);
			}
		}
	}
}

enum struct CoilshotgunEnumInfo
{
	int entity_hit_ref;
	ArrayList entities;
	int attacker_team;
	int limit;
	int num_hit;
}

static CoilshotgunEnumInfo coilshotgun_info;

static bool coilshotgun_enum_func(int entity, any data)
{
	if(coilshotgun_info.num_hit >= coilshotgun_info.limit) {
		return false;
	}

	int ref = EntIndexToEntRef(entity);
	if(ref == coilshotgun_info.entity_hit_ref) {
		return true;
	}

	if(!EntityIsCombatCharacter(entity)) {
		return true;
	}

	int entity_team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	if(TeamManager_AreTeamsFriends(entity_team, coilshotgun_info.attacker_team)) {
		return true;
	}

	if(GetEntProp(entity, Prop_Data, "m_takedamage") == DAMAGE_NO ||
		GetEntProp(entity, Prop_Data, "m_lifeState") != LIFE_ALIVE ||
		GetEntProp(entity, Prop_Data, "m_iEFlags") & EFL_KILLME ||
		GetEntityFlags(entity) & FL_NOTARGET) {
		return true;
	}

	coilshotgun_info.entities.Push(ref);
	++coilshotgun_info.num_hit;
	return true;
}

static int ParticleEffectNames = INVALID_STRING_TABLE;

static int spell_lightningball_hit_blue = INVALID_STRING_INDEX;
static int spell_lightningball_hit_red = INVALID_STRING_INDEX;

public void OnMapStart()
{
	ParticleEffectNames = FindStringTable("ParticleEffectNames");

	spell_lightningball_hit_blue = FindStringIndex(ParticleEffectNames, "spell_lightningball_hit_blue");
	spell_lightningball_hit_red = FindStringIndex(ParticleEffectNames, "spell_lightningball_hit_red");

	PrecacheScriptSound("Halloween.spell_lightning_cast");
	PrecacheScriptSound("Halloween.spell_lightning_impact");
}

static void setup_particle(int entity, int particle, float start[3], float end[3], float dir[3])
{
	TE_Start("TFParticleEffect");
	TE_WriteNum("entindex", entity);
	TE_WriteNum("m_iParticleSystemIndex", particle);

	TE_WriteNum("m_iAttachType", PATTACH_CUSTOMORIGIN);
	TE_WriteFloat("m_vecOrigin[0]", start[0]);
	TE_WriteFloat("m_vecOrigin[1]", start[1]);
	TE_WriteFloat("m_vecOrigin[2]", start[2]);

	TE_WriteVector("m_vecAngles", dir);

	TE_WriteNum("m_bControlPoint1", 1);
	TE_WriteNum("m_ControlPoint1.m_eParticleAttachment", PATTACH_WORLDORIGIN);
	TE_WriteFloat("m_ControlPoint1.m_vecOffset[0]", end[0]);
	TE_WriteFloat("m_ControlPoint1.m_vecOffset[1]", end[1]);
	TE_WriteFloat("m_ControlPoint1.m_vecOffset[2]", end[2]);
}

#define VORTEXSTATE_INACTIVE 0
#define VORTEXSTATE_ACTIVE_EYEBALL_MOVED 1
#define VORTEXSTATE_ACTIVE_EYEBALL_DIED 2

static Action vortex_touch(int entity, int other)
{
	return Plugin_Handled;
}

static Action vortex_think(int entity)
{
	int weapon = GetEntPropEnt(entity, Prop_Data, "m_hWeapon");
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");

	if((GetGameTime() >= GetEntPropFloat(entity, Prop_Data, "m_flLifetime")) ||
		weapon == -1 ||
		owner == -1) {
		RemoveEntity(entity);
		SetEntityNextThink(entity, TIME_NEVER_THINK);
		return Plugin_Stop;
	}

	float my_pos[3];
	EntityWorldSpaceCenter(entity, my_pos);

	ArrayList entities = new ArrayList();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsClientReplay(i) ||
			IsClientSourceTV(i)) {
			continue;
		}

		if(TeamManager_AreTeamsFriends(GetClientTeam(i), GetEntProp(entity, Prop_Send, "m_iTeamNum"))) {
			continue;
		}

		float plr_pos[3];
		EntityWorldSpaceCenter(i, plr_pos);

		if(GetVectorDistance(my_pos, plr_pos) > 350.0) {
			continue;
		}

		if(!entity_is_damageable(i, true)) {
			continue;
		}

		entities.Push(i);
	}

	ArrayList bots = new ArrayList();
	CollectAllBots(bots);
	int len = bots.Length;
	for(int i = 0; i < len; ++i) {
		INextBot bot = bots.Get(i);
		int j = bot.Entity;

		if(TeamManager_AreTeamsFriends(GetEntProp(j, Prop_Send, "m_iTeamNum"), GetEntProp(entity, Prop_Send, "m_iTeamNum"))) {
			continue;
		}

		float plr_pos[3];
		EntityWorldSpaceCenter(j, plr_pos);

		if(GetVectorDistance(my_pos, plr_pos) > 350.0) {
			continue;
		}

		if(!entity_is_damageable(j, true)) {
			continue;
		}

		entities.Push(j);
	}
	delete bots;

	len = entities.Length;
	for(int i = 0; i < len; ++i) {
		int j = entities.Get(i);

		float plr_pos[3];
		EntityWorldSpaceCenter(j, plr_pos);

		float dir[3];
		SubtractVectors(my_pos, plr_pos, dir);
		NormalizeVector(dir, dir);
		ScaleVector(dir, 300.0);

		INextBot bot = INextBot(j);
		if(bot != INextBot_Null) {
			AnyLocomotion locomotion = view_as<AnyLocomotion>(bot.LocomotionInterface);
			locomotion.SetVelocity(dir);
		} else {
			ApplyAbsVelocityImpulse(j, dir);
		}

		float scale = GetEntPropFloat(j, Prop_Send, "m_flModelScale");
		scale -= 0.1;
		SetEntityModelScale(j, scale);

		CTakeDamageInfo info;
		info.Init(weapon, owner, 1.0, DMG_CRUSH, 0);
		CalculateExplosiveDamageForce(info, dir, my_pos, 1.0);

		if(scale <= 0.2) {
			info.m_bitsDamageType |= DMG_DISSOLVE;
			info.m_flDamage = float(GetEntProp(j, Prop_Data, "m_iMaxHealth"));
		}

		EntityTakeDamage(j, info);
	}
	delete entities;

	SetEntityNextThink(entity, GetGameTime() + 0.1);
	return Plugin_Handled;
}

public Action entity_impact_effect(int entity, ImpactEffectTraceInfo info, int nDamageType)
{
	char attrstr[64];
	if(TF2CustAttr_GetString(entity, "vortex_impact", attrstr, sizeof(attrstr)) > 0) {
		float duration = ReadFloatVar(attrstr, "duration", 5.0);

		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwner");
		int team = GetEntProp(owner, Prop_Send, "m_iTeamNum");

		int vortex = CreateEntityByName("attribute_teleport_vortex");
		SDKHook(vortex, SDKHook_Touch, vortex_touch);
		TeleportEntity(vortex, info.endpos);
		SetEntProp(vortex, Prop_Data, "m_iInitialTeamNum", team);
		SetEntityOwner(vortex, owner);
		SetEntPropEnt(vortex, Prop_Data, "m_hWeapon", entity);
		SetEntProp(vortex, Prop_Send, "m_iState", VORTEXSTATE_ACTIVE_EYEBALL_MOVED);
		SetEntPropFloat(vortex, Prop_Data, "m_flDuration", duration);
		SetEntPropFloat(vortex, Prop_Data, "m_flLifetime", GetGameTime() + duration);
		DispatchSpawn(vortex);
		HookEntityThink(vortex, vortex_think);
		ActivateEntity(vortex);
		TeamManager_SetEntityTeam(vortex, team, false);
		SetEntityMoveType(vortex, MOVETYPE_NONE);
		SetEntProp(vortex, Prop_Send, "m_nSolidType", SOLID_NONE);
		SetEntityCollisionGroup(vortex, COLLISION_GROUP_NONE);
		int solidflags = GetEntProp(vortex, Prop_Send, "m_usSolidFlags");
		solidflags |= FSOLID_NOT_SOLID;
		SetEntProp(vortex, Prop_Send, "m_usSolidFlags", solidflags);
	}

	return Plugin_Continue;
}

static Action anything_takedamage_pre(int entity, CTakeDamageInfo info, int &result)
{
	int attacker = info.m_hAttacker;
	if(attacker >= 1 && attacker <= MaxClients) {
		int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
		if(weapon != -1) {
			char attrstr[64];
			if(TF2CustAttr_GetString(weapon, "radius_shock", attrstr, sizeof(attrstr)) > 0) {
				info.m_bitsDamageType |= DMG_SHOCK;
				return Plugin_Changed;
			}
		}
	}

	return Plugin_Continue;
}

static Action anything_takedamage_post(int entity, CTakeDamageInfo info, int &result)
{
	int attacker = info.m_hAttacker;
	if(attacker >= 1 && attacker <= MaxClients) {
		int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
		if(weapon != -1) {
			char attrstr[64];
			if(TF2CustAttr_GetString(weapon, "radius_shock", attrstr, sizeof(attrstr)) > 0 && info.m_iAmmoType != TF_AMMO_COUNT) {
				info.m_iAmmoType = TF_AMMO_COUNT;

				float radius = ReadFloatVar(attrstr, "radius", 500.0);
				int limit = ReadIntVar(attrstr, "limit", 999);

				EmitGameSoundToAll("Halloween.spell_lightning_impact", entity);

				coilshotgun_info.entities = new ArrayList();
				coilshotgun_info.entity_hit_ref = EntIndexToEntRef(entity);
				coilshotgun_info.attacker_team = GetClientTeam(attacker);
				coilshotgun_info.limit = limit;
				coilshotgun_info.num_hit = 0;
				TR_EnumerateEntitiesSphere(info.m_vecDamagePosition, radius, PARTITION_NON_STATIC_EDICTS, coilshotgun_enum_func, 0);
				int len = coilshotgun_info.entities.Length;
				for(int i = 0; i < len; ++i) {
					int enum_entity = EntRefToEntIndex(coilshotgun_info.entities.Get(i));
					if(enum_entity == -1) {
						continue;
					}

					float end_pos[3];
					EntityWorldSpaceCenter(enum_entity, end_pos);

					float dir[3];
					SubtractVectors(info.m_vecDamagePosition, end_pos, dir);
					GetVectorAngles(dir, dir);

					int particle = (coilshotgun_info.attacker_team == TF_TEAM_RED ? spell_lightningball_hit_red : spell_lightningball_hit_blue);
					setup_particle(enum_entity, particle, info.m_vecDamagePosition, end_pos, dir);
					TE_SendToAll();

					EmitGameSoundToAll("Halloween.spell_lightning_cast", enum_entity);

					EntityTakeDamage(enum_entity, info);
				}
				delete coilshotgun_info.entities;
			}
		}
	}

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	HookEntityOnTakeDamage(client, anything_takedamage_pre, false);
	HookEntityOnTakeDamageAlive(client, anything_takedamage_post, true);
}

public void OnNextbotSpawned(INextBot bot, int entity)
{
	HookEntityOnTakeDamage(entity, anything_takedamage_pre, false);
	HookEntityOnTakeDamageAlive(entity, anything_takedamage_post, true);
}