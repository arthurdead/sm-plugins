#include <sourcemod>
#include <animhelpers>

//#define DEBUG

#define MATERIAL_MODIFY_STRING_SIZE 255

#define MATERIAL_MODIFY_MODE_NONE 0
#define MATERIAL_MODIFY_MODE_SETVAR 1

enum struct MatVarInfo
{
	int control;

	char value[MATERIAL_MODIFY_STRING_SIZE];

	float time;
}

enum struct EntityMatVarInfo
{
	int ref;

	StringMap variables;
}

static StringMap mat_ent_map;

static any native_set_material_var(Handle plugin, int params)
{
	char material[MATERIAL_MODIFY_STRING_SIZE];
	GetNativeString(2, material, MATERIAL_MODIFY_STRING_SIZE);

	ArrayList infos;
	if(!mat_ent_map.GetValue(material, infos)) {
		infos = new ArrayList(sizeof(EntityMatVarInfo));
		mat_ent_map.SetValue(material, infos);
	}

	int entity = GetNativeCell(1);
	int ref = EntIndexToEntRef(entity);

	EntityMatVarInfo info;

	int idx = infos.FindValue(ref, EntityMatVarInfo::ref);
	if(idx == -1) {
		info.ref = ref;
		info.variables = new StringMap();
		idx = infos.PushArray(info, sizeof(EntityMatVarInfo));
	} else {
		infos.GetArray(idx, info, sizeof(EntityMatVarInfo));
	}

	char variable[MATERIAL_MODIFY_STRING_SIZE];
	GetNativeString(3, variable, MATERIAL_MODIFY_STRING_SIZE);

	char value[MATERIAL_MODIFY_STRING_SIZE];
	GetNativeString(4, value, MATERIAL_MODIFY_STRING_SIZE);


	MatVarInfo var_info;

	if(!info.variables.GetArray(variable, var_info, sizeof(MatVarInfo))) {
		var_info.control = INVALID_ENT_REFERENCE;
	}

	strcopy(var_info.value, MATERIAL_MODIFY_STRING_SIZE, value);
	var_info.time = GetGameTime();

	info.variables.SetArray(variable, var_info, sizeof(MatVarInfo));

	return 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	RegPluginLibrary("matproxy");

	CreateNative("set_material_var", native_set_material_var);

	return APLRes_Success;
}

public void OnPluginStart()
{
	mat_ent_map = new StringMap();
}

static void maintain_controls(bool remove_all)
{
	StringMapSnapshot snap = mat_ent_map.Snapshot();

	char material[MATERIAL_MODIFY_STRING_SIZE];
	char variable[MATERIAL_MODIFY_STRING_SIZE];
	char value[MATERIAL_MODIFY_STRING_SIZE];

	EntityMatVarInfo info;
	MatVarInfo var_info;

	int len = snap.Length;
	for(int j = 0; j < len; ++j) {
		snap.GetKey(j, material, MATERIAL_MODIFY_STRING_SIZE);

		ArrayList infos;
		if(mat_ent_map.GetValue(material, infos)) {
			int len2 = infos.Length;
			for(int i = 0; i < len2; ++i) {
				infos.GetArray(i, info, sizeof(EntityMatVarInfo));

				int target = EntRefToEntIndex(info.ref);

				StringMapSnapshot snap2 = info.variables.Snapshot();

				int len3 = snap2.Length;
				int len3_copy = len3;
				for(int k = 0; k < len3; ++k) {
					snap2.GetKey(k, variable, MATERIAL_MODIFY_STRING_SIZE);

					if(info.variables.GetArray(variable, var_info, sizeof(MatVarInfo))) {
						int control = EntRefToEntIndex(var_info.control);

						if(target == -1 || remove_all) {
						#if defined DEBUG
							PrintToServer("removing %s %i %s target was deleted", material, i, variable);
						#endif
							if(control != -1) {
								RemoveEntity(control);
							}
							info.variables.Remove(variable);
							continue;
						}

						if(control == -1) {
						#if defined DEBUG
							PrintToServer("created control entity for %s %i %s", material, i, variable);
						#endif

							control = CreateEntityByName("material_modify_control");
							DispatchKeyValue(control, "materialName", material);
							DispatchKeyValue(control, "materialVar", variable);
							DispatchSpawn(control);

							SetVariantString("!activator");
							AcceptEntityInput(control, "SetParent", target);

							SetVariantString(var_info.value);
							AcceptEntityInput(control, "SetMaterialVar");

							var_info.control = EntIndexToEntRef(control);

							info.variables.SetArray(variable, var_info, sizeof(MatVarInfo));
						} else {
							GetEntPropString(control, Prop_Send, "m_szMaterialVarValue", value, MATERIAL_MODIFY_STRING_SIZE);
							if(!StrEqual(value, var_info.value)) {
								SetVariantString(var_info.value);
								AcceptEntityInput(control, "SetMaterialVar");
							}
						}

						float life = (GetGameTime() - var_info.time);
						if(life >= 0.3 || remove_all) {
						#if defined DEBUG
							PrintToServer("removing %s %i %s time was expired", material, i, variable);
						#endif
							--len3_copy;
							if(control != -1) {
								RemoveEntity(control);
							}
							info.variables.Remove(variable);
							continue;
						}
					}
				}

				delete snap2;

				if(target == -1 ||
					len3_copy == 0 ||
					remove_all) {
				#if defined DEBUG
					PrintToServer("removing %s %i no variables left", material, i);
				#endif
					--len2;
					infos.Erase(i);
					continue;
				}
			}
			if(len2 == 0 ||
				remove_all) {
			#if defined DEBUG
				PrintToServer("removing %s no entites left", material);
			#endif
				delete infos;
				mat_ent_map.Remove(material);
			}
		}
	}

	delete snap;
}

static Action timer_maintain_controls(Handle timer, any data)
{
	maintain_controls(false);

	return Plugin_Continue;
}

public void OnMapStart()
{
	CreateTimer(0.1, timer_maintain_controls, 0, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public void OnPluginEnd()
{
	maintain_controls(true);
}

public void OnMapEnd()
{
	maintain_controls(true);
}