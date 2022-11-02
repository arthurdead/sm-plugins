#if defined __matproxy_inc
	#endinput
#endif
#define __matproxy_inc

native void set_material_var(int entity, const char[] material, const char[] variable, const char[] value);

public SharedPlugin __pl_matproxy =
{
	name = "matproxy",
	file = "matproxy.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_matproxy_SetNTVOptional()
{
	
}
#endif