#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <nextbot>
#include <damagerules>

#define COLLISION_GROUP_NONE 0
#define COLLISION_GROUP_NPC 9
#define COLLISION_GROUP_PLAYER 5

#define CLASS_NONE 0
#define CLASS_PLAYER 1
#define CLASS_PLAYER_ALLY 2
#define NUM_AI_CLASSES 3

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

#define EFL_DONTWALKON (1 << 26)

DynamicHook IsNPCDetour = null;
DynamicHook GetSolidMaskDetour = null;
DynamicHook GetCollisionGroupDetour = null;
DynamicHook PhysicsSolidMaskForEntityDetour = null;
DynamicHook ClassifyDetour = null;
DynamicHook HasHumanGibsDetour = null;
DynamicHook HasAlienGibsDetour = null;
DynamicHook BloodColorDetour = null;
DynamicHook InitDefaultAIRelationshipsDetour = null;
DynamicHook AIClassTextDetour = null;
Handle SetDefaultRelationship = null;
Handle AllocateDefaultRelationships = null;
Handle GetBossType = null;
Handle GetWeaponID = null;

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
	GetCollisionGroupDetour = DynamicHook.FromConf(gamedata, "IBody::GetCollisionGroup");

	InitDefaultAIRelationshipsDetour = DynamicHook.FromConf(gamedata, "CGameRules::InitDefaultAIRelationships");
	AIClassTextDetour = DynamicHook.FromConf(gamedata, "CGameRules::AIClassText");

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseCombatCharacter::SetDefaultRelationship");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	SetDefaultRelationship = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBaseCombatCharacter::GetBossType");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	GetBossType = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTFWeaponBase::GetWeaponID");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	GetWeaponID = EndPrepSDKCall();

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
			SDKCall(SetDefaultRelationship, i, j, D_NU, 0);
		}
	}

	SDKCall(SetDefaultRelationship, CLASS_PLAYER, CLASS_PLAYER_ALLY, D_NU, 0);
	SDKCall(SetDefaultRelationship, CLASS_PLAYER_ALLY, CLASS_PLAYER, D_NU, 0);

	return MRES_Supercede;
}

MRESReturn AIClassText(DHookReturn hReturn, DHookParam hParams)
{
	int classType = hParams.Get(1);
	switch(classType) {
		case CLASS_NONE: { hReturn.SetString("CLASS_NONE"); }
		case CLASS_PLAYER: { hReturn.SetString("CLASS_PLAYER"); }
		case CLASS_PLAYER_ALLY: { hReturn.SetString("CLASS_PLAYER_ALLY"); }
		default: { hReturn.SetString("MISSING CLASS in ClassifyText()"); }
	}
	return MRES_Supercede;
}

MRESReturn GetCollisionGroup(int pThis, DHookReturn hReturn)
{
	hReturn.Value = COLLISION_GROUP_NPC;
	return MRES_Supercede;
}

MRESReturn Classify(int pThis, DHookReturn hReturn)
{
	hReturn.Value = CLASS_PLAYER_ALLY;
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

	flags = GetEntProp(entity, Prop_Data, "m_iEFlags");
	flags |= EFL_DONTWALKON;
	SetEntProp(entity, Prop_Data, "m_iEFlags", flags);

	SetEntProp(entity, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_NPC);

	TFTeam team = view_as<TFTeam>(GetEntProp(entity, Prop_Send, "m_iTeamNum"));
	if(team == TFTeam_Red) {
		PhysicsSolidMaskForEntityDetour.HookEntity(Hook_Pre, entity, PhysicsSolidMaskForEntityRed);

		if(GameRules_GetProp("m_bPlayingMannVsMachine")) {
			ClassifyDetour.HookEntity(Hook_Pre, entity, Classify);
		}
	} else if(team == TFTeam_Blue) {
		PhysicsSolidMaskForEntityDetour.HookEntity(Hook_Pre, entity, PhysicsSolidMaskForEntityBlue);
	} else {
		PhysicsSolidMaskForEntityDetour.HookEntity(Hook_Pre, entity, PhysicsSolidMaskForEntity);
	}
}

void OnNextBotSpawnPost(int entity)
{
	OnNPCSpawnPost(entity);

	INextBot bot = INextBot(entity);
	IBody body = bot.BodyInterface;

	GetCollisionGroupDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetCollisionGroup);

	TFTeam team = view_as<TFTeam>(GetEntProp(entity, Prop_Send, "m_iTeamNum"));
	if(team == TFTeam_Red) {
		GetSolidMaskDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetSolidMaskRed);
	} else if(team == TFTeam_Blue) {
		GetSolidMaskDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetSolidMaskBlue);
	} else {
		GetSolidMaskDetour.HookRaw(Hook_Pre, view_as<Address>(body), GetSolidMask);
	}
}

int ParticleEffectNames = INVALID_STRING_TABLE;

int bot_impact_light = INVALID_STRING_INDEX;
int bot_impact_heavy = INVALID_STRING_INDEX;
int spell_skeleton_goop_green = INVALID_STRING_INDEX;
int spell_pumpkin_mirv_goop_red = INVALID_STRING_INDEX;
int spell_pumpkin_mirv_goop_blue = INVALID_STRING_INDEX;
int merasmus_blood = INVALID_STRING_INDEX;
int merasmus_blood_bits = INVALID_STRING_INDEX;
int halloween_boss_injured = INVALID_STRING_INDEX;

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

	bot_impact_light = PrecacheParticle("bot_impact_light");
	bot_impact_heavy = PrecacheParticle("bot_impact_heavy");
	spell_skeleton_goop_green = PrecacheParticle("spell_skeleton_goop_green");
	spell_pumpkin_mirv_goop_red = PrecacheParticle("spell_pumpkin_mirv_goop_red");
	spell_pumpkin_mirv_goop_blue = PrecacheParticle("spell_pumpkin_mirv_goop_blue");
	merasmus_blood = PrecacheParticle("merasmus_blood");
	merasmus_blood_bits = PrecacheParticle("merasmus_blood_bits");
	halloween_boss_injured = PrecacheParticle("merasmus_blood_bits");
}

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
}

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
	TFTeam team = view_as<TFTeam>(GetEntProp(entity, Prop_Send, "m_iTeamNum"));
	switch(team) {
		case TFTeam_Red: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
		case TFTeam_Blue: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_YELLOW); }
		default: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_GREEN); }
	}

	SetEntityOnTakeDamage(entity, baseline_ontakedamage);
	SetEntityOnTakeDamageAlive(entity, DamageRules_OnZombieTakeDamageAlive);

	OnNextBotSpawnPost(entity);
}

void OnMonoculosSpawnPost(int entity)
{
	TFTeam team = view_as<TFTeam>(GetEntProp(entity, Prop_Send, "m_iTeamNum"));
	switch(team) {
		case TFTeam_Red: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
		case TFTeam_Blue: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_YELLOW); }
		default: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
	}

	OnNextBotSpawnPost(entity);
}

void OnHatmanSpawnPost(int entity)
{
	TFTeam team = view_as<TFTeam>(GetEntProp(entity, Prop_Send, "m_iTeamNum"));
	switch(team) {
		case TFTeam_Red: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_RED); }
		case TFTeam_Blue: { SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_YELLOW); }
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

void OnPlayerSpawnPost(int entity)
{
	TFTeam team = view_as<TFTeam>(GetClientTeam(entity));
	if(team == TFTeam_Blue) {
		if(GameRules_GetProp("m_bPlayingMannVsMachine")) {
			SetEntProp(entity, Prop_Data, "m_bloodColor", BLOOD_COLOR_MECH);
			SDKHook(entity, SDKHook_OnTakeDamageAlivePost, OnMechTakeDamageAlivePost);
		}
	}
}

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

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "obj_") != -1) {
		SDKHook(entity, SDKHook_SpawnPost, OnBuildingSpawnPost);
	}

	INextBot bot = INextBot(entity);
	if(bot != INextBot_Null) {
		bool is_player = (StrEqual(classname, "player") || StrEqual(classname, "tf_bot"));
		bool is_tank = StrEqual(classname, "tank_boss");
		bool is_zombie = StrEqual(classname, "tf_zombie");
		bool is_merasmus = StrEqual(classname, "merasmus");
		bool is_hatman = StrEqual(classname, "headless_hatman");
		bool is_monoculos = StrEqual(classname, "eyeball_boss");

		if(is_player) {
			SDKHook(entity, SDKHook_SpawnPost, OnPlayerSpawnPost);
		} else {
			IsNPCDetour.HookEntity(Hook_Pre, entity, IsNPC);

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
			} else {
				SDKHook(entity, SDKHook_SpawnPost, OnUnknownNextBotSpawnPost);
			}
		}
	}
}