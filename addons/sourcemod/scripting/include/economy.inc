#if defined __economy_inc
	#endinput
#endif
#define __economy_inc

#define ECON_MAX_ITEM_CATEGORY_NAME 64

#define ECON_MAX_ITEM_NAME 64
#define ECON_MAX_ITEM_DESCRIPTION 64

#define ECON_MAX_ITEM_CLASSNAME 64

#define ECON_MAX_ITEM_SETTING_NAME 64
#define ECON_MAX_ITEM_SETTING_VALUE 64

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

forward void econ_loaded();

native StringMap econ_item_settings(int idx);
native void econ_register_item_class(const char[] classname, bool equipable);

native int econ_find_category(const char[] name);

typedef econ_category_registered = function void (int idx);
native void econ_register_category(const char[] name, econ_category_registered registered);

native int econ_find_item(int category, const char[] name);
native void econ_register_item(int category, const char[] name, const char[] description, const char[] classname, int price, StringMap settings);

native void econ_set_item_price(int idx, int price);
native void econ_set_item_description(int idx, const char[] description);
native void econ_set_item_setting(int idx, const char[] name, const char[] value);

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
public __pl_economy_SetNTVOptional()
{
	MarkNativeAsOptional("econ_item_settings");
	MarkNativeAsOptional("econ_register_item_class");
	MarkNativeAsOptional("econ_find_category");
	MarkNativeAsOptional("econ_register_category");
	MarkNativeAsOptional("econ_find_item");
	MarkNativeAsOptional("econ_register_item");
	MarkNativeAsOptional("econ_set_item_price");
	MarkNativeAsOptional("econ_set_item_description");
	MarkNativeAsOptional("econ_set_item_setting");
	MarkNativeAsOptional("econ_menu_add_item");
}
#endif