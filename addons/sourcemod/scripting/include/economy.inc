#if defined __economy_inc
	#endinput
#endif
#define __economy_inc

enum econ_item_action
{
	econ_item_equip,
	econ_item_unequip,
	econ_item_remove,
	econ_item_apply
};

forward void econ_cache_item(const char[] classname, int item_idx, StringMap settings);
forward Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx);
forward void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action);

native StringMap econ_item_settings(int idx);
native void econ_register_item_class(const char[] classname, bool equipable);

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
}
#endif