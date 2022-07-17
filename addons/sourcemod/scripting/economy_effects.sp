#include <sourcemod>
#include <economy>
#include <bit>
#include <tf2attributes>
#include <sdktools>
#include <tf2utils>
#include <animhelpers>

#define TF2_MAXPLAYERS 33

#define PATTACH_CUSTOMORIGIN 2
#define PATTACH_WORLDORIGIN 5

enum tracer_type
{
	tracer_none,
	tracer_machina,
	tracer_merasmus
};

static StringMap tracer_map;

static tracer_type player_tracer[TF2_MAXPLAYERS+1];

static int ParticleEffectNames = INVALID_STRING_TABLE;
static int modelprecache = INVALID_STRING_TABLE;

static int merasmus_zap = INVALID_STRING_INDEX;

public void OnPluginStart()
{
	tracer_map = new StringMap();

	AddTempEntHook("Fire Bullets", FireBullets);
}

public void OnMapStart()
{
	PrecacheModel("models/error.mdl");

	ParticleEffectNames = FindStringTable("ParticleEffectNames");
	modelprecache = FindStringTable("modelprecache");

	merasmus_zap = FindStringIndex(ParticleEffectNames, "merasmus_zap");
}

static int find_particle(const char[] name)
{
	if(ParticleEffectNames == INVALID_STRING_TABLE) {
		ParticleEffectNames = FindStringTable("ParticleEffectNames");
	}
	return FindStringIndex(ParticleEffectNames, name);
}

static bool tracefilter_ignore_weapon(int entity, int mask, int weapon)
{
	if(entity == weapon || entity == GetEntPropEnt(weapon, Prop_Send, "m_hOwner")) {
		return false;
	}
	return true;
}

static void get_model_index_path(int idx, char[] model, int len)
{
	if(modelprecache == INVALID_STRING_TABLE) {
		modelprecache = FindStringTable("modelprecache");
		if(modelprecache == INVALID_STRING_TABLE) {
			strcopy(model, len, "models/error.mdl");
			return;
		}
	}

	ReadStringTable(modelprecache, idx, model, len);
}

static void setup_tracer(int weapon, int particle, float start[3], float ang[3], float end[3])
{
	TE_Start("TFParticleEffect");
	TE_WriteNum("entindex", weapon);
	TE_WriteNum("m_iParticleSystemIndex", particle);

	TE_WriteNum("m_iAttachType", PATTACH_CUSTOMORIGIN);
	TE_WriteFloat("m_vecOrigin[0]", start[0]);
	TE_WriteFloat("m_vecOrigin[1]", start[1]);
	TE_WriteFloat("m_vecOrigin[2]", start[2]);

	TE_WriteVector("m_vecAngles", ang);

	TE_WriteNum("m_bControlPoint1", 1);
	TE_WriteNum("m_ControlPoint1.m_eParticleAttachment", PATTACH_WORLDORIGIN);
	TE_WriteFloat("m_ControlPoint1.m_vecOffset[0]", end[0]);
	TE_WriteFloat("m_ControlPoint1.m_vecOffset[1]", end[1]);
	TE_WriteFloat("m_ControlPoint1.m_vecOffset[2]", end[2]);
}

static Action FireBullets(const char[] te_name, const int[] players, int numClients, float delay)
{
	if(merasmus_zap == INVALID_STRING_INDEX) {
		merasmus_zap = find_particle("merasmus_zap");
		if(merasmus_zap == INVALID_STRING_INDEX) {
			return Plugin_Continue;
		}
	}

	int m_iPlayer = TE_ReadNum("m_iPlayer");
	int client = m_iPlayer+1;

	if(player_tracer[client] != tracer_merasmus) {
		return Plugin_Continue;
	}

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(weapon == -1) {
		return Plugin_Continue;
	}

	int m_iWeaponID = TE_ReadNum("m_iWeaponID");
	if(m_iWeaponID != TF2Util_GetWeaponID(weapon)) {
		return Plugin_Continue;
	}

	int m_iWorldModelIndex = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
	if(m_iWorldModelIndex == -1) {
		return Plugin_Continue;
	}

	char old_model[PLATFORM_MAX_PATH];
	GetEntPropString(weapon, Prop_Data, "m_ModelName", old_model, PLATFORM_MAX_PATH);

	char new_model[PLATFORM_MAX_PATH];
	get_model_index_path(m_iWorldModelIndex, new_model, PLATFORM_MAX_PATH);

	SetEntityModel(weapon, new_model);

	int muzzle = view_as<BaseAnimating>(weapon).LookupAttachment("muzzle");
	if(muzzle == 0) {
		SetEntityModel(weapon, old_model);
		return Plugin_Continue;
	}

	float attach_ang[3];
	float start[3];
	view_as<BaseAnimating>(weapon).GetAttachment(muzzle, start, attach_ang);

	SetEntityModel(weapon, old_model);

	float ang[3];
	GetClientEyeAngles(client, ang);

	Handle trace = TR_TraceRayFilterEx(start, ang, MASK_SOLID, RayType_Infinite, tracefilter_ignore_weapon, weapon);

	float end[3];
	TR_GetEndPosition(end, trace);

	delete trace;

	setup_tracer(weapon, merasmus_zap, start, ang, end);

	int[] new_players = new int[MaxClients];
	for(int i = 0; i < numClients; ++i) {
		new_players[i] = players[i];
	}

	new_players[numClients++] = client;
	TE_Send(new_players, numClients, delay);

	return Plugin_Continue;
}

public void econ_cache_item(const char[] classname, int item_idx, StringMap settings)
{
	char value_str[ECON_MAX_ITEM_SETTING_VALUE];
	settings.GetString("type", value_str, ECON_MAX_ITEM_SETTING_VALUE);

	int value = StringToInt(value_str);

	char str[5];
	pack_int_in_str(item_idx, str);

	tracer_map.SetValue(str, value);
}

public void OnClientDisconnect(int client)
{
	player_tracer[client] = tracer_none;
}

public Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx)
{
	return StrEqual(classname1, classname2) ? Plugin_Handled : Plugin_Continue;
}

public void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action)
{
	switch(action) {
		case econ_item_apply: {
			if(player_tracer[client] == tracer_machina) {
				TF2Attrib_SetByDefIndex(client, 305, 1.0);
			}
		}
		case econ_item_remove: {
			if(player_tracer[client] == tracer_machina) {
				TF2Attrib_RemoveByDefIndex(client, 305);
			}
		}
		case econ_item_equip: {
			char str[5];
			pack_int_in_str(item_idx, str);
			tracer_map.GetValue(str, player_tracer[client]);

			if(player_tracer[client] == tracer_machina) {
				if(IsClientInGame(client)) {
					TF2Attrib_SetByDefIndex(client, 305, 1.0);
				}
			}
		}
		case econ_item_unequip: {
			if(player_tracer[client] == tracer_machina) {
				TF2Attrib_RemoveByDefIndex(client, 305);
			}
			player_tracer[client] = tracer_none;
		}
	}
}

static void tracer_cat_registered(int idx)
{
	econ_get_or_register_item(idx, "Machina", "", "weapon_tracer", 1200, econ_single_setting_int("type", tracer_machina));
	econ_get_or_register_item(idx, "Merasmus", "", "weapon_tracer", 1200, econ_single_setting_int("type", tracer_merasmus));
}

static void misc_cat_registered(int idx)
{
	econ_get_or_register_category("Weapon Tracer", idx, tracer_cat_registered);
}

public void econ_loaded()
{
	econ_get_or_register_category("Misc", ECON_INVALID_CATEGORY, misc_cat_registered);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "economy")) {
		econ_register_item_class("weapon_tracer", true);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "economy")) {
		tracer_map.Clear();
	}
}
