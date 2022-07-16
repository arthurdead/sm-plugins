#include <sourcemod>
#include <economy>
#include <tf2attributes>
#include <bit>

#define TF2_MAXPLAYERS 33

static StringMap footprint_value_map;

static float player_footprint[TF2_MAXPLAYERS+1];

public void OnPluginStart()
{
	footprint_value_map = new StringMap();
}

public void OnClientDisconnect(int client)
{
	player_footprint[client] = 0.0;
}

static void register_footprint(int cat_idx, const char[] name, int price, float value)
{
	econ_get_or_register_item(cat_idx, name, "", "footprint", price, econ_single_setting_float("value", value));
}

static void on_econ_cat_registered(int cat_idx)
{
	register_footprint(cat_idx, "Team Based", 200, 1.0);
	register_footprint(cat_idx, "Blue", 200, 7777.0);
	register_footprint(cat_idx, "Light Blue", 200, 933333.0);
	register_footprint(cat_idx, "Yellow", 200, 8421376.0);
	register_footprint(cat_idx, "Corrupted Green", 200, 4552221.0);
	register_footprint(cat_idx, "Dark Green", 200, 3100495.0);
	register_footprint(cat_idx, "Lime", 200, 51234123.0);
	register_footprint(cat_idx, "Brown", 200, 5322826.0);
	register_footprint(cat_idx, "Oak Tree Brown", 200, 8355220.0);
	register_footprint(cat_idx, "Flames", 200, 13595446.0);
	register_footprint(cat_idx, "Cream", 200, 8208497.0);
	register_footprint(cat_idx, "Pink", 200, 41234123.0);
	register_footprint(cat_idx, "Satan's Blue", 290, 300000.0);
	register_footprint(cat_idx, "Purple", 200, 2.0);
	register_footprint(cat_idx, "4 8 15 16 23 42", 290, 3.0);
	register_footprint(cat_idx, "Ghost In The Machine", 200, 83552.0);
	register_footprint(cat_idx, "Holy Flame", 290, 9335510.0);
}

public void econ_loaded()
{
	econ_get_or_register_category("Footprints", ECON_INVALID_CATEGORY, on_econ_cat_registered);
}

public void econ_cache_item(const char[] classname, int item_idx, StringMap settings)
{
	char value_str[ECON_MAX_ITEM_SETTING_VALUE];
	settings.GetString("value", value_str, sizeof(value_str));

	float value = StringToFloat(value_str);

	char str[5];
	pack_int_in_str(item_idx, str);
	footprint_value_map.SetValue(str, value);
}

public Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx)
{
	return StrEqual(classname2, "footprint") ? Plugin_Handled : Plugin_Continue;
}

public void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action)
{
	switch(action) {
		case econ_item_equip: {
			char str[5];
			pack_int_in_str(item_idx, str);

			footprint_value_map.GetValue(str, player_footprint[client]);

			if(IsClientInGame(client)) {
				TF2Attrib_SetByDefIndex(client, 1005, player_footprint[client]);
			}
		}
		case econ_item_apply: {
			if(player_footprint[client] != 0.0) {
				TF2Attrib_SetByDefIndex(client, 1005, player_footprint[client]);
			} else {
				TF2Attrib_RemoveByDefIndex(client, 1005);
			}
		}
		case econ_item_unequip: {
			player_footprint[client] = 0.0;
			TF2Attrib_RemoveByDefIndex(client, 1005);
		}
		case econ_item_remove: {
			TF2Attrib_RemoveByDefIndex(client, 1005);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "economy")) {
		econ_register_item_class("footprint", true);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "economy")) {
		footprint_value_map.Clear();
	}
}