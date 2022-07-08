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

public void econ_cache_item(const char[] classname, int item_idx, StringMap settings)
{
	char value_str[10];
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

			TF2Attrib_SetByDefIndex(client, 1005, player_footprint[client]);
		}
		case econ_item_apply: {
			TF2Attrib_SetByDefIndex(client, 1005, player_footprint[client]);
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
		delete footprint_value_map;
		footprint_value_map = new StringMap();
	}
}