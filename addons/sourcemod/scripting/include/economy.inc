#if defined __economy_inc
	#endinput
#endif
#define __economy_inc

#include <tf2>
#include <tf2_stocks>

#define ECON_MAX_ITEM_CATEGORY_NAME 64

#define ECON_MAX_ITEM_NAME 64
#define ECON_MAX_ITEM_DESCRIPTION 64

#define ECON_MAX_ITEM_CLASSNAME 64

#define ECON_MAX_ITEM_SETTING_NAME 64
#define ECON_MAX_ITEM_SETTING_VALUE 64

#define ECON_INVALID_ITEM -1
#define ECON_INVALID_CATEGORY -1

enum econ_item_action
{
	econ_item_equip,
	econ_item_unequip,
	econ_item_remove,
	econ_item_apply
};

forward void econ_cache_item(const char[] classname, int item_idx, StringMap settings);

native void econ_menu_add_item(const char[] display);
forward void econ_modify_menu(const char[] classname, int item_idx);

forward Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx);
forward void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action);

//forward void econ_item_preview(int client, const char[] classname, int item_idx, bool start);

forward void econ_loaded();

native StringMap econ_item_settings(int idx);
native void econ_get_item_name(int idx, char[] str, int len);

forward void econ_register_item_classes();
native void econ_register_item_class(const char[] classname, bool equipable);

native int econ_find_category(int parent, const char[] name);

typedef econ_category_registered = function void (int idx, any data);
native void econ_register_category(const char[] name, int parent, econ_category_registered registered, any data);

native int econ_find_item(int category, const char[] name);

typedef econ_item_registered = function void (int idx, any data);
native void econ_register_item(KeyValues item_kv, econ_item_registered registered, any data);

native void econ_set_item_price(int idx, int price);
native void econ_set_item_description(int idx, const char[] description);
native void econ_set_item_setting(int idx, const char[] name, const char[] value);
native void econ_set_item_settings(int idx, StringMap settings);
native void econ_update_item(int idx, KeyValues item_kv);
native void econ_add_item_to_category(int item_idx, int cat_idx);

native void econ_get_or_register_item(int category, KeyValues item_kv, econ_item_registered registered, any data);

native void econ_get_or_register_category(const char[] name, int parent, econ_category_registered registered, any data);

stock bool econ_player_state_valid(int client)
{
	if(!IsClientInGame(client) ||
		!IsPlayerAlive(client) ||
		GetClientTeam(client) < 2 ||
		TF2_GetPlayerClass(client) == TFClass_Unknown) {
		return false;
	}

	return true;
}

public SharedPlugin __pl_economy =
{
	name = "economy",
	file = "economy.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_economy_SetNTVOptional()
{
	MarkNativeAsOptional("econ_menu_add_item");
	MarkNativeAsOptional("econ_item_settings");
	MarkNativeAsOptional("econ_get_item_name");
	MarkNativeAsOptional("econ_register_item_class");
	MarkNativeAsOptional("econ_find_category");
	MarkNativeAsOptional("econ_register_category");
	MarkNativeAsOptional("econ_find_item");
	MarkNativeAsOptional("econ_register_item");
	MarkNativeAsOptional("econ_set_item_price");
	MarkNativeAsOptional("econ_set_item_description");
	MarkNativeAsOptional("econ_set_item_setting");
	MarkNativeAsOptional("econ_set_item_settings");
	MarkNativeAsOptional("econ_update_item");
	MarkNativeAsOptional("econ_add_item_to_category");
	MarkNativeAsOptional("econ_get_or_register_item");
	MarkNativeAsOptional("econ_get_or_register_category");
}
#endif