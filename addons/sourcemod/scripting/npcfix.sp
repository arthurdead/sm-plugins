#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <nextbot>
#if defined GAME_TF2
#include <tf2_stocks>
#include <damagerules>
#endif

#define COLLISION_GROUP_NONE 0
#define COLLISION_GROUP_NPC 9
#define COLLISION_GROUP_PLAYER 5

#define CLASS_NONE 0
#define CLASS_PLAYER 1
#define CLASS_PLAYER_ALLY 2
#if defined GAME_L4D2
#define CLASS_UNKNOWN1 3
#define CLASS_INFECTED 4
#define NUM_AI_CLASSES 5
#elseif defined GAME_TF2
#define NUM_AI_CLASSES 3
#endif

#define DONT_BLEED -1
#define BLOOD_COLOR_RED 0
#define BLOOD_COLOR_YELLOW 1
#define BLOOD_COLOR_GREEN 2
#define BLOOD_COLOR_MECH 3

#define D_ER 0
#define D_HT 1
#define D_FR 2
#define D_LI 3
#define D_NU 4

#define CONTENTS_REDTEAM CONTENTS_TEAM1
#define CONTENTS_BLUETEAM CONTENTS_TEAM2

#define EFL_DIRTY_SURROUNDING_COLLISION_BOUNDS (1 << 14)
#define EFL_DIRTY_SPATIAL_PARTITION (1 << 15)
#define EFL_DONTWALKON (1 << 26)

#define FSOLID_NOT_STANDABLE 0x0010

#define	DAMAGE_YES 2

#define USE_OBB_COLLISION_BOUNDS 0
#define USE_ROTATION_EXPANDED_BOUNDS 5
#if defined GAME_L4D2
#define USE_ROTATION_EXPANDED_SEQUENCE_BOUNDS 7
#endif

#define SOLID_VPHYSICS 6
#define SOLID_BBOX 2
#define SOLID_CUSTOM 5

#define LIFE_ALIVE 0

DynamicHook IsNPCDetour = null;
DynamicHook GetSolidMaskDetour = null;
#if defined GAME_TF2
DynamicHook GetCollisionGroupDetour = null;
#endif
DynamicHook PhysicsSolidMaskForEntityDetour = null;
DynamicHook ClassifyDetour = null;
DynamicHook HasHumanGibsDetour = null;
DynamicHook HasAlienGibsDetour = null;
DynamicHook BloodColorDetour = null;
DynamicHook InitDefaultAIRelationshipsDetour = null;
DynamicHook AIClassTextDetour = null;
Handle SetDefaultRelationship = null;
Handle AllocateDefaultRelationships = null;
#if defined GAME_TF2
Handle GetBossType = null;
Handle GetWeaponID = null;
#endif

public void OnPluginStart()
{
	GameData gamedata = new GameData("npcfix");

	IsNPCDetour = DynamicHook.FromConf(gamedata, "CBaseEntity::IsNPC");
	DynamicDetour MyNPCPointerDetour = DynamicDetour.FromConf(gamedata, "CBaseEntity::MyNPCPointer");
	PhysicsSolidMaskForEntityDetour = DynamicHook.FromConf(gamedata, "CBaseEntity::PhysicsSolidMaskForEntity");
	ClassifyDetour = DynamicHook.FromConf(gamedata, "CBaseEntity::Classify");
	HasHumanGibsDetour = DynamicHook.FromConf(gamedata, "CBaseCombatCharacter::HasHumanGibs");
	HasAlienGibsDetour = DynamicHook.FromConf(gamedata, "CBaseCombatCharacter::HasAlienGibs");
	BloodColorDetour = DynamicHook.FromConf(gamedata, "CBaseEntity::BloodColor");

	GetSolidMaskDetour = DynamicHook.FromConf(gamedata, "IBody::GetSolidMask");
#if defined GAME_TF2
	GetCollisionGroupDetour = DynamicHook.FromConf(gamedata, "IBody::GetCollisionGroup");
#endif

	InitDefaultAIRelationshipsDetour = DynamicHook.FromConf(gamedata, "CGameRules::InitDefaultAIRelationships");
	AIClassTextDetour = DynamicHook.FromConf(gamedata, "CGameRules::AIClassText");

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseCombatCharacter::SetDefaultRelationship");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	SetDefaultRelationship = EndPrepSDKCall();

#if defined GAME_TF2
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBaseCombatCharacter::GetBossType");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	GetBossType = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTFWeaponBase::GetWeaponID");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	GetWeaponID = EndPrepSDKCall();
#endif

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseCombatCharacter::AllocateDefaultRelationships");
	AllocateDefaultRelationships = EndPrepSDKCall();

	delete gamedata;

	MyNPCPointerDetour.Enable(Hook_Pre, MyNPCPointer);
}

public void OnConfigsExecuted()
{
	ConVar tmp = FindConVar("npc_vphysics");
	tmp.BoolValue = true;
}

MRESReturn InitDefaultAIRelationships(int pThis)
{
	SDKCall(AllocateDefaultRelationships);

	for(int i = 0; i < NUM_AI_CLASSES; ++i) {
		for(int j = 0; j < NUM_AI_CLASSES; ++j) {
			SDKCall(SetDefaultRelationship, i, j, i == j ? D_LI : D_NU, 0);
		}
	}

	SDKCall(SetDefaultRelationship, CLASS_PLAYER, CLASS_PLAYER_ALLY, D_LI, 0);
#if defined GAME_L4D2
	SDKCall(SetDefaultRelationship, CLASS_PLAYER, CLASS_INFECTED, D_HT, 0);
#endif

	SDKCall(SetDefaultRelationship, CLASS_PLAYER_ALLY, CLASS_PLAYER, D_LI, 0);
#if defined GAME_L4D2
	SDKCall(SetDefaultRelationship, CLASS_PLAYER_ALLY, CLASS_INFECTED, D_HT, 0);
#endif

#if defined GAME_L4D2
	SDKCall(SetDefaultRelationship, CLASS_INFECTED, CLASS_PLAYER, D_HT, 0);
	SDKCall(SetDefaultRelationship, CLASS_INFECTED, CLASS_PLAYER_ALLY, D_HT, 0);
#endif

	return MRES_Supercede;
}

MRESReturn AIClassText(DHookReturn hReturn, DHookParam hParams)
{
	int classType = hParams.Get(1);
	switch(classType) {
		case CLASS_NONE: { hReturn.SetString("CLASS_NONE"); }
		case CLASS_PLAYER: { hReturn.SetString("CLASS_PLAYER"); }
		case CLASS_PLAYER_ALLY: { hReturn.SetString("CLASS_PLAYER_ALLY"); }
	#if defined GAME_L4D2
		case CLASS_UNKNOWN1: { hReturn.SetString("CLASS_UNKNOWN1"); }
		case CLASS_INFECTED: { hReturn.SetString("CLASS_INFECTED"); }
	#endif
		default: { hReturn.SetString("MISSING CLASS in ClassifyText()"); }
	}
	return MRES_Supercede;
}

#if defined GAME_TF2
MRESReturn GetCollisionGroup(int pThis, DHookReturn hReturn)
{
	hReturn.Value = COLLISION_GROUP_NPC;
	return MRES_Supercede;
}
#endif

MRESReturn ClassifyAlly(int pThis, DHookReturn hReturn)
{
	hReturn.Value = CLASS_PLAYER_ALLY;
	return MRES_Supercede;
}

#if defined GAME_L4D2
MRESReturn ClassifyInfected(int pThis, DHookReturn hReturn)
{
	hReturn.Value = CLASS_INFECTED;
	return MRES_Supercede;
}
#endif

MRESReturn GetSolidMask(Address pThis, DHookReturn hReturn)
{
	hReturn.Value = MASK_NPCSOLID;
	return MRES_Supercede;
}

MRESReturn PhysicsSolidMaskForEntity(int pThis, DHookReturn hReturn)
{
	hReturn.Value = MASK_NPCSOLID;
	return MRES_Supercede;
}

MRESReturn GetSolidMaskRed(Address pThis, DHookReturn hReturn)
{
	hReturn.Value = MASK_NPCSOLID|CONTENTS_BLUETEAM;
	return MRES_Supercede;
}

MRESReturn GetSolidMaskBlue(Address pThis, DHookReturn hReturn)
{
	hReturn.Value = MASK_NPCSOLID|CONTENTS_REDTEAM;
	return MRES_Supercede;
}

MRESReturn PhysicsSolidMaskForEntityBlue(int pThis, DHookReturn hReturn)
{
	hReturn.Value = MASK_NPCSOLID|CONTENTS_REDTEAM;
	return MRES_Supercede;
}

MRESReturn PhysicsSolidMaskForEntityRed(int pThis, DHookReturn hReturn)
{
	hReturn.Value = MASK_NPCSOLID|CONTENTS_BLUETEAM;
	return MRES_Supercede;
}

MRESReturn MyNPCPointer(int pThis, DHookReturn hReturn)
{
	INextBot bot = INextBot(pThis);
	if(bot != INextBot_Null) {
		hReturn.Value = 0;
		return MRES_Supercede;
	} else {
		return MRES_Ignored;
	}
}

MRESReturn HasHumanGibs(int pThis, DHookReturn hReturn)
{
	hReturn.Value = 1;
	return MRES_Supercede;
}

MRESReturn HasAlienGibs(int pThis, DHookReturn hReturn)
{
	hReturn.Value = 1;
	return MRES_Supercede;
}

MRESReturn IsNPC(int pThis, DHookReturn hReturn)
{
	hReturn.Value = 1;
	return MRES_Supercede;
}

void OnNPCSpawnPost(int entity)
{
	int flags = GetEntityFlags(entity);
	flags |= FL_NPC;
	SetEntityFlags(entity, FL_NPC);

	SetEntProp(entity, Prop_Data, "m_lifeState", LIFE_ALIVE);
	SetEntProp(entity, Prop_Data, "m_takedamage", DAMAGE_YES);

	SetEntProp(entity, Prop_Send, "m_nSolidType", SOLID_BBOX);

	SetEntProp(entity, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_NPC);

	flags = GetEdictFlags(entity);
	flags |= FL_EDICT_DIRTY_PVS_INFORMATION;
	SetEdictFlags(entity, flags);

	flags = GetEntProp(entity, Prop_Data, "m_iEFlags");
	flags |= EFL_DIRTY_SURROUNDING_COLLISION_BOUNDS|EFL_DIRTY_SPATIAL_PARTITION|EFL_DONTWALKON;
	SetEntProp(entity, Prop_Data, "m_iEFlags", flags);

	flags = GetEntProp(entity, Prop_Send, "m_usSolidFlags");
	flags |= FSOLID_NOT_STANDABLE;
	SetEntProp(entity, Prop_Send, "m_usSolidFlags", flags);

	SetEntityMoveType(entity, MOVETYPE_CUSTOM);

	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	if(team == 2) {
		PhysicsSolidMaskForEntityDetour.HookEntity(Hook_Pre, entity, PhysicsSolidMaskForEntityRed);

	#if defined GAME_TF2
		if(GameRules_GetProp("m_bPlayingMannVsMachine")) {
			ClassifyDetour.HookEntity(Hook_Pre, entity, ClassifyAlly);
		}
	#elseif GAME_L4D2
		ClassifyDetour.HookEntity(Hook_Pre, entity, ClassifyAlly);
	#endif
	} else if(team == 3) {
		PhysicsSolidMaskForEntityDetour.HookEntity(Hook_Pre, entity, PhysicsSolidMaskForEntityBlue);
	#if defined GAME_L4D2
		ClassifyDetour.HookEntity(Hook_Pre, entity, ClassifyInfected);
	#endif
	} else {
		PhysicsSolidMaskForEntityDetour.HookEntity(Hook_Pre, entity, PhysicsSolidMaskForEntity);
	}
}

void OnNextBotSpawnPost(int entity)
{
	OnNPCSpawnPost(entity);

	INextBot bot = INextBot(entity);
	IBody body = bot.BodyInterface;

#if defined GAME_TF2
	GetCollisionGroupDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetCollisionGroup);
#endif

	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	if(team == 2) {
		GetSolidMaskDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetSolidMaskRed);
	} else if(team == 3) {
		GetSolidMaskDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetSolidMaskBlue);
	} else {
		GetSolidMaskDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetSolidMask);
	}
}

int ParticleEffectNames = INVALID_STRING_TABLE;

#if defined GAME_TF2
int bot_impact_light = INVALID_STRING_INDEX;
int bot_impact_heavy = INVALID_STRING_INDEX;
int spell_skeleton_goop_green = INVALID_STRING_INDEX;
int spell_pumpkin_mirv_goop_red = INVALID_STRING_INDEX;
int spell_pumpkin_mirv_goop_blue = INVALID_STRING_INDEX;
int merasmus_blood = INVALID_STRING_INDEX;
int merasmus_blood_bits = INVALID_STRING_INDEX;
int halloween_boss_injured = INVALID_STRING_INDEX;
#endif

int PrecacheParticle(const char[] name)
{
	int index = FindStringIndex(ParticleEffectNames, name);
	if(index == INVALID_STRING_INDEX) {
		AddToStringTable(ParticleEffectNames, name);
		index = FindStringIndex(ParticleEffectNames, name);
	}
	return index;
}

public void OnMapStart()
{
	InitDefaultAIRelationshipsDetour.HookGamerules(Hook_Pre, InitDefaultAIRelationships);
	AIClassTextDetour.HookGamerules(Hook_Pre, AIClassText);

	ParticleEffectNames = FindStringTable("ParticleEffectNames");

#if defined GAME_TF2
	bot_impact_light = PrecacheParticle("bot_impact_light");
	bot_impact_heavy = PrecacheParticle("bot_impact_heavy");
	spell_skeleton_goop_green = PrecacheParticle("spell_skeleton_goop_green");
	spell_pumpkin_mirv_goop_red = PrecacheParticle("spell_pumpkin_mirv_goop_red");
	spell_pumpkin_mirv_goop_blue = PrecacheParticle("spell_pumpkin_mirv_goop_blue");
	merasmus_blood = PrecacheParticle("merasmus_blood");
	merasmus_blood_bits = PrecacheParticle("merasmus_blood_bits");
	halloween_boss_injured = PrecacheParticle("merasmus_blood_bits");
#endif
}

#if defined GAME_TF2
void DoNPCHurt(int victim, float damage, int weapon, int attacker, bool crit, int boss)
{
	Event npc_hurt = CreateEvent("npc_hurt");
	npc_hurt.SetInt("entindex", victim);
	int m_iHealth = GetEntProp(victim, Prop_Data, "m_iHealth");
	if(m_iHealth < 0) {
		m_iHealth = 0;
	}
	npc_hurt.SetInt("health", m_iHealth);
	int damageamount = RoundToFloor(damage);
	npc_hurt.SetInt("damageamount", damageamount);
	npc_hurt.SetBool("crit", crit);
	npc_hurt.SetInt("boss", boss);
	if(attacker >= 1 && attacker <= MaxClients) {
		npc_hurt.SetInt("attacker_player", GetClientUserId(attacker));
		int weaponid = 0;
		if(IsValidEntity(weapon)) {
			weaponid = SDKCall(GetWeaponID, weapon);
		}
		npc_hurt.SetInt("weaponid", weaponid);
	} else {
		npc_hurt.SetInt("attacker_player", 0);
		npc_hurt.SetInt("weaponid", 0);
	}
	npc_hurt.Fire();
}

int DamageRules_OnUnknownNextBotTakeDamageAlive(int entity, CTakeDamageInfo info, any data)
{
	int dmg = baseline_ontakedamagealive(entity, info, 0);

	if(dmg > 0) {
		int attacker = info.m_hAttacker;
		if(attacker != -1) {
			INextBot bot = INextBot(entity);
			IVision vision = bot.VisionInterface;
			vision.AddKnownEntity(attacker);
		}

		DoNPCHurt(entity, info.m_flDamage, info.m_hWeapon, attacker, info.m_eCritType != CRIT_NONE, 0);

		if(data == -2) {
			DoMechDamageParticle(entity, info.m_vecDamagePosition);
		} else if(data != -1) {
			DoParticleEffect(entity, info.m_vecDamagePosition, data);
		}
	}

	return dmg;
}
#elseif defined GAME_L4D2
void DoInfectedHurt(int victim, float damage, int attacker, int hitgroup, int type)
{
	Event infected_hurt = CreateEvent("infected_hurt");
	if(attacker >= 1 && attacker <= MaxClients) {
		npc_hurt.SetInt("attacker", GetClientUserId(attacker));
	} else {
		npc_hurt.SetInt("attacker", 0);
	}
	infected_hurt.SetInt("entityid", victim);
	infected_hurt.SetInt("hitgroup", hitgroup);
	int amount = RoundToFloor(damage);
	infected_hurt.SetInt("amount", amount);
	infected_hurt.SetInt("type", type);
	infected_hurt.Fire();
}
#endif

void OnUnknownNextBotSpawnPost(int entity)
{
	OnNextBotSpawnPost(entity);

	int m_bloodColor = GetEntProp(entity, Prop_Data, "m_bloodColor");
	switch(m_bloodColor) {
		case BLOOD_COLOR_RED:
		{ HasHumanGibsDetour.HookEntity(Hook_Pre, entity, HasHumanGibs); }
		case BLOOD_COLOR_GREEN, BLOOD_COLOR_YELLOW:
		{ HasAlienGibsDetour.HookEntity(Hook_Pre, entity, HasAlienGibs); }
	}

#if defined GAME_TF2
	SetEntityOnTakeDamage(entity, baseline_ontakedamage);

	if(m_bloodColor == BLOOD_COLOR_MECH) {
		SetEntityOnTakeDamageAlive(entity, DamageRules_OnUnknownNextBotTakeDamageAlive, -2);
	} else {
		int index = -1;

		switch(m_bloodColor) {
			case BLOOD_COLOR_RED: { index = spell_pumpkin_mirv_goop_red; }
			case BLOOD_COLOR_GREEN: { index = merasmus_blood; }
			case BLOOD_COLOR_YELLOW: { index = halloween_boss_injured; }
		}

		SetEntityOnTakeDamageAlive(entity, DamageRules_OnUnknownNextBotTakeDamageAlive, index);
	}
#endif
}

#if defined GAME_TF2
void OnTankSpawnPost(int entity)
{
	SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_MECH);

	OnNextBotSpawnPost(entity);
}

int DamageRules_OnZombieTakeDamageAlive(int entity, CTakeDamageInfo info, any data)
{
	int dmg = baseline_ontakedamagealive(entity, info, 0);

	if(dmg > 0) {
		DoNPCHurt(entity, info.m_flDamage, info.m_hWeapon, info.m_hAttacker, info.m_eCritType != CRIT_NONE, 0);
	}

	return dmg;
}

void OnZombieSpawnPost(int entity)
{
	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	switch(team) {
		case 2: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
		case 3: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_YELLOW); }
		default: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_GREEN); }
	}

	SetEntityOnTakeDamage(entity, baseline_ontakedamage);
	SetEntityOnTakeDamageAlive(entity, DamageRules_OnZombieTakeDamageAlive);

	OnNextBotSpawnPost(entity);
}

void OnMonoculosSpawnPost(int entity)
{
	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	switch(team) {
		case 2: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
		case 3: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_YELLOW); }
		default: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
	}

	OnNextBotSpawnPost(entity);
}

void OnHatmanSpawnPost(int entity)
{
	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	switch(team) {
		case 2: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
		case 3: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_YELLOW); }
		default: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_YELLOW); }
	}

	OnNextBotSpawnPost(entity);
}

void OnMerasmusSpawnPost(int entity)
{
	SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_GREEN);

	OnNextBotSpawnPost(entity);
}

void OnBuildingSpawnPost(int entity)
{
	SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_MECH);

	SDKHook(entity, SDKHook_OnTakeDamagePost, OnMechTakeDamagePost);
}
#elseif defined GAME_L4D2
void OnInfectedSpawnPost(int entity)
{
	SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED);

	OnNextBotSpawnPost(entity);
}
#endif

void OnPlayerSpawnPost(int entity)
{
	int team = GetClientTeam(entity);
	if(team == 3) {
	#if defined GAME_TF2
		if(GameRules_GetProp("m_bPlayingMannVsMachine")) {
			SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_MECH);
			SDKHook(entity, SDKHook_OnTakeDamageAlivePost, OnMechTakeDamageAlivePost);
		}
	#endif
	}
}

#if defined GAME_TF2
void DoParticleEffect(int victim, const float damagePosition[3], int index)
{
	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", damagePosition[0]);
	TE_WriteFloat("m_vecOrigin[1]", damagePosition[1]);
	TE_WriteFloat("m_vecOrigin[2]", damagePosition[2]);
	TE_WriteFloat("m_vecStart[0]", damagePosition[0]);
	TE_WriteFloat("m_vecStart[1]", damagePosition[1]);
	TE_WriteFloat("m_vecStart[2]", damagePosition[2]);
	float m_vecAngles[3];
	TE_WriteVector("m_vecAngles", m_vecAngles);
	TE_WriteNum("m_iParticleSystemIndex", index);
	TE_WriteNum("entindex", victim);
	TE_WriteNum("m_iAttachType", 2);
	TE_WriteNum("m_iAttachmentPointIndex", 0);
	TE_WriteNum("m_bResetParticles", 0);
	TE_SendToAll();
}

void DoMechDamageParticle(int victim, const float damagePosition[3])
{
	int m_iHealth = GetEntProp(victim, Prop_Data, "m_iHealth");
	int m_iMaxHealth = GetEntProp(victim, Prop_Data, "m_iMaxHealth");

	if((float(m_iHealth) / m_iMaxHealth) > 0.3) {
		DoParticleEffect(victim, damagePosition, bot_impact_light);
	} else {
		DoParticleEffect(victim, damagePosition, bot_impact_heavy);
	}
}

void OnMechTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom)
{
	DoMechDamageParticle(victim, damagePosition);
}

void OnMechTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom)
{
	DoMechDamageParticle(victim, damagePosition);
}
#endif

public void OnEntityCreated(int entity, const char[] classname)
{
#if defined GAME_TF2
	if(StrContains(classname, "obj_") != -1) {
		SDKHook(entity, SDKHook_SpawnPost, OnBuildingSpawnPost);
	}
#endif

	INextBot bot = INextBot(entity);
	if(bot != INextBot_Null) {
	#if defined GAME_TF2
		bool is_player = (StrEqual(classname, "player") || StrEqual(classname, "tf_bot"));
	#elseif defined GAME_L4D2
		bool is_player = (StrEqual(classname, "player"));
	#endif

	#if defined GAME_TF2
		bool is_tank = StrEqual(classname, "tank_boss");
		bool is_zombie = StrEqual(classname, "tf_zombie");
		bool is_merasmus = StrEqual(classname, "merasmus");
		bool is_hatman = StrEqual(classname, "headless_hatman");
		bool is_monoculos = StrEqual(classname, "eyeball_boss");
	#elseif defined GAME_L4D2
		bool is_infected = StrEqual(classname, "infected");
	#endif

		if(is_player) {
			SDKHook(entity, SDKHook_SpawnPost, OnPlayerSpawnPost);
		} else {
			IsNPCDetour.HookEntity(Hook_Pre, entity, IsNPC);

		#if defined GAME_TF2
			if(is_zombie) {
				HasHumanGibsDetour.HookEntity(Hook_Pre, entity, HasHumanGibs);
				SDKHook(entity, SDKHook_SpawnPost, OnZombieSpawnPost);
			} else if(is_merasmus) {
				HasHumanGibsDetour.HookEntity(Hook_Pre, entity, HasHumanGibs);
				SDKHook(entity, SDKHook_SpawnPost, OnMerasmusSpawnPost);
			} else if(is_monoculos) {
				HasHumanGibsDetour.HookEntity(Hook_Pre, entity, HasHumanGibs);
				SDKHook(entity, SDKHook_SpawnPost, OnMonoculosSpawnPost);
			} else if(is_tank) {
				SDKHook(entity, SDKHook_SpawnPost, OnTankSpawnPost);
			} else if(is_hatman) {
				HasHumanGibsDetour.HookEntity(Hook_Pre, entity, HasHumanGibs);
				SDKHook(entity, SDKHook_SpawnPost, OnHatmanSpawnPost);
			}
		#elseif defined GAME_L4D2
			if(is_infected) {
				HasHumanGibsDetour.HookEntity(Hook_Pre, entity, HasHumanGibs);
				SDKHook(entity, SDKHook_SpawnPost, OnInfectedSpawnPost);
			}
		#endif
			else {
				SDKHook(entity, SDKHook_SpawnPost, OnUnknownNextBotSpawnPost);
			}
		}
	}
}