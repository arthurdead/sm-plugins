#if defined __savenames_inc
	#endinput
#endif
#define __savenames_inc

native bool sn_get(int accid, char[] name, int len);

public SharedPlugin __pl_savenames =
{
	name = "savenames",
	file = "savenames.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_savenames_SetNTVOptional()
{
	MarkNativeAsOptional("sn_get");
}
#endif