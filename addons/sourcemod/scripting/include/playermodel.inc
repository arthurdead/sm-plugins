#if defined _playermodel_included_
	#endinput
#endif
#define _playermodel_included_

#if defined GAME_TF2
	#include <tf2>
	#include <tf2_stocks>
#endif

#if defined GAME_TF2
	#define BODYGROUP_SCOUT_HAT (1 << 0)
	#define BODYGROUP_SCOUT_HEADPHONES (1 << 1)
	#define BODYGROUP_SCOUT_SHOESSOCKS (1 << 2)
	#define BODYGROUP_SCOUT_DOGTAGS (1 << 3)
	#define BODYGROUP_SOLDIER_ROCKET (1 << 0)
	#define BODYGROUP_SOLDIER_HELMET (1 << 1)
	#define BODYGROUP_SOLDIER_MEDAL (1 << 2)
	#define BODYGROUP_SOLDIER_GRENADES (1 << 3)
	#define BODYGROUP_PYRO_HEAD (1 << 0)
	#define BODYGROUP_PYRO_GRENADES (1 << 1)
	#define BODYGROUP_DEMO_SMILE (1 << 0)
	#define BODYGROUP_DEMO_SHOES (1 << 1)
	#define BODYGROUP_HEAVY_HANDS (1 << 0)
	#define BODYGROUP_ENGINEER_HELMET (1 << 0)
	#define BODYGROUP_ENGINEER_ARM (1 << 1)
	#define BODYGROUP_MEDIC_BACKPACK (1 << 0)
	#define BODYGROUP_SNIPER_ARROWS (1 << 0)
	#define BODYGROUP_SNIPER_HAT (1 << 1)
	#define BODYGROUP_SNIPER_BULLETS (1 << 2)
	#define BODYGROUP_SPY_MASK (1 << 0)
	#define BODYGROUP_MERASMUS_BOOK (1 << 1)
	#define BODYGROUP_MERASMUS_STAFF (1 << 3)
#endif

enum PlayerModelType
{
	PlayerModelDefault,
	PlayerModelCustomModel,
	PlayerModelProp,
	PlayerModelBonemerge,
};

forward void Playermodel_OnApplied(int client);
//0 == disconnect, 1 == death, 2 == native
forward void Playermodel_OnCleared(int client, int type);

native void Playermodel_Clear(int client, bool def=false, bool reapply=false);
//returns entref
native int Playermodel_Reapply(int client);
native void Playermodel_SetModel(int client, const char[] model, bool def=false);
native void Playermodel_GetModel(int client, char[] model, int length, bool def=false);
native void Playermodel_GetAnimation(int client, char[] model, int length, bool def=false);
//returns entref
native int Playermodel_GetEntity(int client);
//returns entref
native int Playermodel_GetLink(int client);
//returns entref
native int Playermodel_CreateLink(int client);
//returns entref
native int Playermodel_GetAnimEnt(int client);
native int Playermodel_SetAnimation(int client, const char[] model, bool def=false);
native PlayerModelType Playermodel_GetType(int client, bool def=false);
//returns entref
native int PlayerModel_SetType(int client, const char[] model, PlayerModelType type, bool def=false);

native int Playermodel_GetSkin(int client, bool def=false);
//(TF2) if the type is bonemerge this actually sets the team number
native void Playermodel_SetSkin(int client, int skin, bool def=false);

native int Playermodel_GetBodygroup(int client, bool def=false);
native void Playermodel_SetBodygroup(int client, int body, bool def=false);

stock bool Playermodel_IsSet(int client, bool def=false)
{
	return (Playermodel_GetType(client, def) != PlayerModelDefault);
}

#if defined GAME_TF2
stock void GetModelForPlayerClass(int client, char[] model, int length)
{
	TFClassType class = TF2_GetPlayerClass(client);
	GetModelForClass(class, model, length);
}

stock void GetModelForClass(TFClassType class, char[] model, int length)
{
	switch(class)
	{
		case TFClass_Unknown: { strcopy(model, length, "models/error.mdl"); }
		case TFClass_Engineer: { strcopy(model, length, "models/player/engineer.mdl"); }
		case TFClass_Scout: { strcopy(model, length, "models/player/scout.mdl"); }
		case TFClass_Medic: { strcopy(model, length, "models/player/medic.mdl"); }
		case TFClass_Soldier: { strcopy(model, length, "models/player/soldier.mdl"); }
		case TFClass_Heavy: { strcopy(model, length, "models/player/heavy.mdl"); }
		case TFClass_DemoMan: { strcopy(model, length, "models/player/demo.mdl"); }
		case TFClass_Spy: { strcopy(model, length, "models/player/spy.mdl"); }
		case TFClass_Sniper: { strcopy(model, length, "models/player/sniper.mdl"); }
		case TFClass_Pyro: { strcopy(model, length, "models/player/pyro.mdl"); }
	}
}

stock void GetArmModelForClass(TFClassType class, char[] model, int length)
{
	switch(class)
	{
		case TFClass_Unknown: { strcopy(model, length, "models/error.mdl"); }
		case TFClass_Engineer: { strcopy(model, length, "models/weapons/c_models/c_engineer_arms.mdl"); }
		case TFClass_Scout: { strcopy(model, length, "models/weapons/c_models/c_scout_arms.mdl"); }
		case TFClass_Medic: { strcopy(model, length, "models/weapons/c_models/c_medic_arms.mdl"); }
		case TFClass_Soldier: { strcopy(model, length, "models/weapons/c_models/c_soldier_arms.mdl"); }
		case TFClass_Heavy: { strcopy(model, length, "models/weapons/c_models/c_heavy_arms.mdl"); }
		case TFClass_DemoMan: { strcopy(model, length, "models/weapons/c_models/c_demo_arms.mdl"); }
		case TFClass_Spy: { strcopy(model, length, "models/weapons/c_models/c_spy_arms.mdl"); }
		case TFClass_Sniper: { strcopy(model, length, "models/weapons/c_models/c_sniper_arms.mdl"); }
		case TFClass_Pyro: { strcopy(model, length, "models/weapons/c_models/c_pyro_arms.mdl"); }
	}
}
#endif

public SharedPlugin __pl_playermodel = 
{
	name = "playermodel",
	file = "playermodel.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_playermodel_SetNTVOptional()
{
	MarkNativeAsOptional("Playermodel_Clear");
	MarkNativeAsOptional("Playermodel_GetModel");
	MarkNativeAsOptional("Playermodel_GetAnimation");
	MarkNativeAsOptional("Playermodel_GetEntity");
	MarkNativeAsOptional("Playermodel_SetAnimation");
	MarkNativeAsOptional("Playermodel_GetType");
	MarkNativeAsOptional("PlayerModel_SetType");
	MarkNativeAsOptional("Playermodel_GetSkin");
	MarkNativeAsOptional("Playermodel_SetSkin");
}
#endif