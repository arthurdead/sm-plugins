#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf2items>
#include <tf2utils>
#include <bit>
#include <economy>
#include <playermodel2>

//#define DEBUG

#define TF2_MAXPLAYERS 33

#define EF_BONEMERGE 0x001
#define EF_BONEMERGE_FASTCULL 0x080
#define EF_PARENT_ANIMATES 0x200
#define EF_NODRAW 0x020
#define EF_NOSHADOW 0x010
#define EF_NORECEIVESHADOW 0x040

#define MAX_ATTACH_NAME 64

enum struct PosInfo
{
	char attachment[MAX_ATTACH_NAME];
	float pos[3];
	float ang[3];
}

static Handle dummy_item_view;

static int player_wearable_weapons[TF2_MAXPLAYERS+1][8];
static bool player_has_back_weapons[TF2_MAXPLAYERS+1];

static int modelprecache = INVALID_STRING_TABLE;

static StringMap pos_map;

public void OnPluginStart()
{
	for(int i = 0; i < sizeof(player_wearable_weapons); ++i) {
		for(int j = 0; j < sizeof(player_wearable_weapons[]); ++j) {
			player_wearable_weapons[i][j] = INVALID_ENT_REFERENCE;
		}
	}

	HookEvent("player_death", player_death);

	HookEvent("player_spawn", player_spawn);
	HookEvent("post_inventory_application", post_inventory_application);

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	pos_map = new StringMap();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "configs/back_weapons.txt");
	if(FileExists(path)) {
		KeyValues kv = new KeyValues("back_weapons");
		kv.ImportFromFile(path);

		char classname[64];
		PosInfo info;

		if(kv.GotoFirstSubKey()) {
			do {
				if(kv.GotoFirstSubKey()) {
					do {
						kv.GetString("attachment", info.attachment, MAX_ATTACH_NAME);
						kv.GetVector("pos", info.pos);
						kv.GetVector("ang", info.ang);

						if(kv.JumpToKey("item_index")) {
							if(kv.GotoFirstSubKey(false)) {
								do {
									int idx = kv.GetNum(NULL_STRING);

									char str[5];
									pack_int_in_str(idx, str);

									pos_map.SetArray(str, info, sizeof(PosInfo));
								} while(kv.GotoNextKey(false));
								kv.GoBack();
							}
							kv.GoBack();
						}

						if(kv.JumpToKey("classname")) {
							if(kv.GotoFirstSubKey(false)) {
								do {
									kv.GetString(NULL_STRING, classname, 64);

									pos_map.SetArray(classname, info, sizeof(PosInfo));
								} while(kv.GotoNextKey(false));
								kv.GoBack();
							}
							kv.GoBack();
						}
					} while(kv.GotoNextKey());
					kv.GoBack();
				}
			} while(kv.GotoNextKey());
			kv.GoBack();
		}

		delete kv;
	}

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);

			if(GetClientTeam(i) > 1 &&
				TF2_GetPlayerClass(i) != TFClass_Unknown &&
				IsPlayerAlive(i)) {
				int weapon = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");
				player_weapon_switch(i, weapon);
			}
		}
	}
}

static void misc_cat_registered(int idx)
{
	econ_get_or_register_item(idx, "Back Weapons", "", "back_weapons", 1200, null);
}

public void econ_loaded()
{
	econ_get_or_register_category("Misc", ECON_INVALID_CATEGORY, misc_cat_registered);
}

public Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx)
{
	return StrEqual(classname1, classname2) ? Plugin_Handled : Plugin_Continue;
}

public void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action)
{
	switch(action) {
		case econ_item_equip: {
			player_has_back_weapons[client] = true;

			if(econ_player_state_valid(client)) {
				int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
				player_weapon_switch(client, weapon);
			}
		}
		case econ_item_unequip: {
			player_has_back_weapons[client] = false;
			delete_player_weapon_entities(client);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "economy")) {
		econ_register_item_class("back_weapons", true);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "economy")) {
		
	}
}

static int get_player_weapon_entity(int client, int which)
{
	int entity = -1;
	if(player_wearable_weapons[client][which] != INVALID_ENT_REFERENCE) {
		entity = EntRefToEntIndex(player_wearable_weapons[client][which]);
		if(!IsValidEntity(entity)) {
			player_wearable_weapons[client][which] = INVALID_ENT_REFERENCE;
			entity = -1;
		}
	}

	return entity;
}

static void delete_player_weapon_entity(int client, int which)
{
	int entity = get_player_weapon_entity(client, which);
	if(entity != -1) {
		AcceptEntityInput(entity, "ClearParent");
		TF2_RemoveWearable(client, entity);
		RemoveEntity(entity);
		player_wearable_weapons[client][which] = INVALID_ENT_REFERENCE;
	}
}

static void delete_player_weapon_entities(int client)
{
	delete_player_weapon_entity(client, TFWeaponSlot_Primary);
	delete_player_weapon_entity(client, TFWeaponSlot_Secondary);
	delete_player_weapon_entity(client, TFWeaponSlot_Melee);
}

static int get_or_create_player_weapon_entity(int client, int which)
{
	int entity = get_player_weapon_entity(client, which);

	if(entity == -1) {
		entity = TF2Items_GiveNamedItem(client, dummy_item_view);
		float pos[3];
		GetClientAbsOrigin(client, pos);
		DispatchKeyValueVector(entity, "origin", pos);
		DispatchKeyValue(entity, "model", "models/error.mdl");
		TF2Util_EquipPlayerWearable(client, entity);
		TF2Util_SetWearableAlwaysValid(entity, true);
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
		SetEntPropString(entity, Prop_Data, "m_iClassname", "weapon_wearable");
		SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
		SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));
		player_wearable_weapons[client][which] = EntIndexToEntRef(entity);
	}

	return entity;
}

public void OnClientDisconnect(int client)
{
	delete_player_weapon_entities(client);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, player_weapon_switch);
}

public void OnMapStart()
{
	PrecacheModel("models/error.mdl");

	modelprecache = FindStringTable("modelprecache");
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientDisconnect(i);
		}
	}
}

static int get_model_index(const char[] model)
{
	if(modelprecache == INVALID_STRING_TABLE) {
		modelprecache = FindStringTable("modelprecache");
		if(modelprecache == INVALID_STRING_TABLE) {
			return INVALID_STRING_INDEX;
		}
	}

	int idx = FindStringIndex(modelprecache, model);
	if(idx == INVALID_STRING_INDEX) {
		idx = PrecacheModel(model);
	}
	return idx;
}

static void get_model_index_path(int idx, char[] model, int len)
{
	if(modelprecache == INVALID_STRING_TABLE) {
		modelprecache = FindStringTable("modelprecache");
		if(modelprecache == INVALID_STRING_TABLE) {
			strcopy(model, len, "models/error.mdl");
		}
	}

	ReadStringTable(modelprecache, idx, model, len);
}

static void copy_weapon(int client, int slot)
{
	int weapon = GetPlayerWeaponSlot(client, slot);
	if(weapon == -1) {
		delete_player_weapon_entity(client, slot);
		return;
	}

	int idx = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
	if(idx == -1) {
		delete_player_weapon_entity(client, slot);
		return;
	}

	int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	char str[5];
	pack_int_in_str(m_iItemDefinitionIndex, str);

	PosInfo info;
	if(!pos_map.GetArray(str, info, sizeof(PosInfo))) {
		char classname[64];
		GetEntityClassname(weapon, classname, sizeof(classname));

		if(!pos_map.GetArray(classname, info, sizeof(PosInfo))) {
			delete_player_weapon_entity(client, slot);
			return;
		}
	}

	int entity = get_or_create_player_weapon_entity(client, slot);

	char model[PLATFORM_MAX_PATH];
	get_model_index_path(idx, model, PLATFORM_MAX_PATH);

	SetEntityModel(entity, model);
	SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);

	int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
	effects &= ~(EF_BONEMERGE|EF_BONEMERGE_FASTCULL);
	effects |= EF_PARENT_ANIMATES;
	SetEntProp(entity, Prop_Send, "m_fEffects", effects);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);

	SetVariantString(info.attachment);
	AcceptEntityInput(entity, "SetParentAttachment");

	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", info.pos);
	SetEntPropVector(entity, Prop_Send, "m_angRotation", info.ang);
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	int death_flags = event.GetInt("death_flags");
	if(!(death_flags & TF_DEATHFLAG_DEADRINGER)) {
		delete_player_weapon_entities(client);
	}
}

static void frame_post_inventory_application(int userid)
{
	int client = GetClientOfUserId(userid);
	if(client == 0) {
		return;
	}

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	player_weapon_switch(client, weapon);
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");

	RequestFrame(frame_post_inventory_application, userid);
}

static void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");

	RequestFrame(frame_post_inventory_application, userid);
}

public void pm2_model_changed(int client)
{
	delete_player_weapon_entities(client);

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	player_weapon_switch(client, weapon);
}

static void player_weapon_switch(int client, int weapon)
{
#if defined DEBUG
	int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));

	PrintToServer("%i - %s", m_iItemDefinitionIndex, classname);
#endif

#if !defined DEBUG
	if(!player_has_back_weapons[client]) {
		delete_player_weapon_entities(client);
		return;
	}
#endif

	if(weapon == -1) {
		delete_player_weapon_entities(client);
		return;
	}

	int slot = TF2Util_GetWeaponSlot(weapon);

	delete_player_weapon_entity(client, slot);

	switch(slot) {
		case TFWeaponSlot_Primary: {
			copy_weapon(client, TFWeaponSlot_Secondary);
		}
		case TFWeaponSlot_Secondary: {
			copy_weapon(client, TFWeaponSlot_Primary);
		}
		case TFWeaponSlot_Melee: {
			copy_weapon(client, TFWeaponSlot_Secondary);
			copy_weapon(client, TFWeaponSlot_Primary);
		}
		default: {
			delete_player_weapon_entities(client);
		}
	}
}