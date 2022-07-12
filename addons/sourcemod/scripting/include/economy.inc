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

forward void econ_loaded();

native StringMap econ_item_settings(int idx);
native void econ_get_item_name(int idx, char[] str, int len);

native void econ_register_item_class(const char[] classname, bool equipable);

native int econ_find_category(int parent, const char[] name);

typedef econ_category_registered = function void (int idx);
native void econ_register_category(const char[] name, int parent, econ_category_registered registered);

native int econ_find_item(int category, const char[] name);
native void econ_register_item(int category, const char[] name, const char[] description, const char[] classname, int price, StringMap settings);

native void econ_set_item_price(int idx, int price);
native void econ_set_item_description(int idx, const char[] description);
native void econ_set_item_setting(int idx, const char[] name, const char[] value);
native void econ_set_item_settings(int idx, StringMap settings);

stock StringMap econ_single_setting_str(const char[] name, const char[] value)
{
	StringMap settings = new StringMap();
	settings.SetString(name, value);
	return settings;
}

stock StringMap econ_single_setting_int(const char[] name, int value)
{
	StringMap settings = new StringMap();

	int len = 20;
	char[] str = new char[len];
	IntToString(value, str, len);

	settings.SetString(name, str);
	return settings;
}

stock StringMap econ_single_setting_float(const char[] name, float value)
{
	StringMap settings = new StringMap();

	int len = 20;
	char[] str = new char[len];
	FloatToString(value, str, len);

	settings.SetString(name, str);
	return settings;
}

stock void econ_get_or_register_item(int category, const char[] name, const char[] description, const char[] classname, int price, StringMap settings)
{
	int idx = econ_find_item(category, name);
	if(idx == ECON_INVALID_ITEM) {
		econ_register_item(category, name, description, classname, price, settings);
	} else {
		econ_set_item_price(idx, price);

		if(settings != null) {
			econ_set_item_settings(idx, settings);
		} else {
			delete settings;
		}
	}
}

stock void econ_get_or_register_category(const char[] name, int parent, econ_category_registered registered)
{
	int idx = econ_find_category(parent, name);
	if(idx == ECON_INVALID_CATEGORY) {
		econ_register_category(name, parent, registered);
	} else {
		if(registered != INVALID_FUNCTION) {
			Call_StartFunction(null, registered);
			Call_PushCell(idx);
			Call_Finish();
		}
	}
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