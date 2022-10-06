#include <sourcemod>
#include <economy>
#include <bit>
#include <tf2attributes>
#include <sdktools>
#include <tf2utils>
#include <dhooks>

#define TF2_MAXPLAYERS 33

#define MAX_PARTICLE_NAME 64

#define PATTACH_CUSTOMORIGIN 2
#define PATTACH_WORLDORIGIN 5

static StringMap tracer_map;

static char player_tracer_name[TF2_MAXPLAYERS+1][MAX_PARTICLE_NAME];
static int player_tracer_particle[TF2_MAXPLAYERS+1] = {INVALID_STRING_INDEX, ...};

static int ParticleEffectNames = INVALID_STRING_TABLE;

public void OnPluginStart()
{
	GameData gamedata = new GameData("economy_effects");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

	DynamicDetour detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::MaybeDrawRailgunBeam");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayer_MaybeDrawRailgunBeam_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::MaybeDrawRailgunBeam");
		delete gamedata;
		return;
	}

	detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::GetHorriblyHackedRailgunPosition");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayer_GetHorriblyHackedRailgunPosition_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::GetHorriblyHackedRailgunPosition");
		delete gamedata;
		return;
	}

	delete gamedata;

	tracer_map = new StringMap();
}

public void OnMapStart()
{
	ParticleEffectNames = FindStringTable("ParticleEffectNames");
}

static int find_particle(const char[] name)
{
	if(ParticleEffectNames == INVALID_STRING_TABLE) {
		ParticleEffectNames = FindStringTable("ParticleEffectNames");
	}
	return FindStringIndex(ParticleEffectNames, name);
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

static MRESReturn CTFPlayer_MaybeDrawRailgunBeam_detour(int pThis, DHookParam hParams)
{
	if(player_tracer_particle[pThis] == INVALID_STRING_INDEX) {
		return MRES_Ignored;
	}

	int weapon = hParams.Get(2);

	float vStartPos[3];
	hParams.GetVector(3, vStartPos);

	float vEndPos[3];
	hParams.GetVector(4, vEndPos);

	float ang[3];
	GetClientEyeAngles(pThis, ang);

	setup_tracer(weapon, player_tracer_particle[pThis], vStartPos, ang, vEndPos);
	TE_SendToAll();

	return MRES_Ignored;
}

static MRESReturn CTFPlayer_GetHorriblyHackedRailgunPosition_detour(int pThis, DHookParam hParams)
{
	return MRES_Ignored;
}

public void econ_cache_item(const char[] classname, int item_idx, StringMap settings)
{
	char value_str[ECON_MAX_ITEM_SETTING_VALUE];
	settings.GetString("particle", value_str, ECON_MAX_ITEM_SETTING_VALUE);

	char str[5];
	pack_int_in_str(item_idx, str);

	tracer_map.SetString(str, value_str);
}

public void OnClientDisconnect(int client)
{
	player_tracer_name[client][0] = '\0';
	player_tracer_particle[client] = INVALID_STRING_INDEX;
}

public Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx)
{
	return StrEqual(classname1, classname2) ? Plugin_Handled : Plugin_Continue;
}

public void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action)
{
	switch(action) {
		case econ_item_apply: {
			if(StrEqual(player_tracer_name[client], "dxhr_sniper_rail")) {
				TF2Attrib_SetByDefIndex(client, 305, 1.0);
			}
		}
		case econ_item_remove: {
			if(StrEqual(player_tracer_name[client], "dxhr_sniper_rail")) {
				TF2Attrib_RemoveByDefIndex(client, 305);
			}
		}
		case econ_item_equip: {
			char str[5];
			pack_int_in_str(item_idx, str);
			if(!tracer_map.GetString(str, player_tracer_name[client], MAX_PARTICLE_NAME)) {
				player_tracer_name[client][0] = '\0';
				return;
			}

			if(StrEqual(player_tracer_name[client], "dxhr_sniper_rail")) {
				player_tracer_particle[client] = INVALID_STRING_INDEX;

				if(econ_player_state_valid(client)) {
					TF2Attrib_SetByDefIndex(client, 305, 1.0);
				}
			} else {
				player_tracer_particle[client] = find_particle(player_tracer_name[client]);
			}
		}
		case econ_item_unequip: {
			if(StrEqual(player_tracer_name[client], "dxhr_sniper_rail")) {
				if(IsClientInGame(client)) {
					TF2Attrib_RemoveByDefIndex(client, 305);
				}
			}
			player_tracer_name[client][0] = '\0';
			player_tracer_particle[client] = INVALID_STRING_INDEX;
		}
	}
}

static void tracer_cat_registered(int idx, any data)
{
	{
		KeyValues item_kv = new KeyValues("");
		item_kv.SetString("name", "Machina");
		item_kv.SetString("classname", "weapon_tracer");
		item_kv.SetNum("price", 1200);

		if(item_kv.JumpToKey("settings", true)) {
			item_kv.SetString("particle", "dxhr_sniper_rail");
			item_kv.GoBack();
		}

		econ_get_or_register_item(idx, item_kv, INVALID_FUNCTION, 0);

		delete item_kv;
	}

	{
		KeyValues item_kv = new KeyValues("");
		item_kv.SetString("name", "Merasmus");
		item_kv.SetString("classname", "weapon_tracer");
		item_kv.SetNum("price", 1200);

		if(item_kv.JumpToKey("settings", true)) {
			item_kv.SetString("particle", "merasmus_zap");
			item_kv.GoBack();
		}

		econ_get_or_register_item(idx, item_kv, INVALID_FUNCTION, 0);

		delete item_kv;
	}

	{
		KeyValues item_kv = new KeyValues("");
		item_kv.SetString("name", "Classic");
		item_kv.SetString("classname", "weapon_tracer");
		item_kv.SetNum("price", 1200);

		if(item_kv.JumpToKey("settings", true)) {
			item_kv.SetString("particle", "tfc_sniper_distortion_trail");
			item_kv.GoBack();
		}

		econ_get_or_register_item(idx, item_kv, INVALID_FUNCTION, 0);

		delete item_kv;
	}
}

static void misc_cat_registered(int idx, any data)
{
	econ_get_or_register_category("Weapon Tracer", idx, tracer_cat_registered, 0);
}

public void econ_loaded()
{
	econ_get_or_register_category("Misc", ECON_INVALID_CATEGORY, misc_cat_registered, 0);
}

public void econ_register_item_classes()
{
	econ_register_item_class("weapon_tracer", true);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "economy")) {
		
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "economy")) {
		tracer_map.Clear();
	}
}
