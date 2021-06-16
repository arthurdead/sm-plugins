#include <sourcemod>
#include <playermodel>
#include <sdkhooks>
#include <tf_econ_data>

ArrayList class_cache = null;

public void OnPluginStart()
{
	class_cache = new ArrayList();

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

//#define DISABLE_CACHE

TFClassType secondaryshotguns[] =
{
	TFClass_Soldier,
	TFClass_Heavy,
	TFClass_Pyro,
};

TFClassType secondarypistol[] =
{
	TFClass_Engineer,
	TFClass_Scout,
};

bool ClassShotgunIsSecondary(TFClassType class)
{
	for(int i = sizeof(secondaryshotguns)-1; i--;) {
		if(secondaryshotguns[i] == class) {
			return true;
		}
	}

	return false;
}

bool ClassPistolIsSecondary(TFClassType class)
{
	for(int i = sizeof(secondarypistol)-1; i--;) {
		if(secondarypistol[i] == class) {
			return true;
		}
	}

	return false;
}

bool IsPistolAndSecondary(const char[] classname)
{
	return (StrEqual(classname, "tf_weapon_handgun_scout_secondary") ||
			StrEqual(classname, "tf_weapon_pistol"))
}

bool IsShotgunAndSecondary(const char[] classname)
{
	if(StrEqual(classname, "tf_weapon_shotgun_primary") ||
		StrEqual(classname, "tf_weapon_shotgun_building_rescue")) {
		return false;
	} else {
		return (StrContains(classname, "tf_weapon_shotgun") != -1);
	}
}

TFClassType GetWeaponClass(int weapon, int item, TFClassType class)
{
#if !defined DISABLE_CACHE
	int idx = class_cache.FindValue(item);
	if(idx != -1) {
		ArrayList tmp = class_cache.Get(++idx);
		int len = tmp.Length;
		for(int i = len-1; i--;) {
			TFClassType it = tmp.Get(i);
			if(it == class) {
				return it;
			}
		}
		return tmp.Get(GetRandomInt(0, len-1));
	} else {
		class_cache.Push(item);
#endif

		ArrayList tmp = new ArrayList();

		TFClassType it = TFClass_Unknown;

		char classname[64];
		GetEntityClassname(weapon, classname, sizeof(classname));

		bool secondshot = IsShotgunAndSecondary(classname);
		if(secondshot) {
			for(int i = sizeof(secondaryshotguns)-1; i--;) {
				tmp.Push(secondaryshotguns[i]);
			}
		}

		bool secondpistol = IsPistolAndSecondary(classname);
		if(secondpistol) {
			for(int i = sizeof(secondarypistol)-1; i--;) {
				tmp.Push(secondarypistol[i]);
			}
		}

		for(TFClassType i = TFClass_Engineer; i--;) {
			if(secondshot && ClassShotgunIsSecondary(i) ||
				secondpistol && ClassPistolIsSecondary(i)) {
				if(i == class) {
					it = i;
				}
				continue;
			}

			int slot = TF2Econ_GetItemLoadoutSlot(item, i);
			if(slot != -1) {
				tmp.Push(i);
				if(i == class) {
					it = i;
				}
			}
		}

		int len = tmp.Length;

		if(!len) {
			tmp.Push(TFClass_Unknown);
			len = 1;
		}

#if !defined DISABLE_CACHE
		class_cache.Push(tmp);
#endif

#if defined DISABLE_CACHE
		TFClassType ret = TFClass_Unknown;

		if(it != TFClass_Unknown) {
			ret = it;
		} else {
			ret = tmp.Get(GetRandomInt(0, len-1));
		}

		delete tmp;
		return ret;
#else
		if(it != TFClass_Unknown) {
			return it;
		} else {
			return tmp.Get(GetRandomInt(0, len-1));
		}
	}
#endif
}

char tmpanim[PLATFORM_MAX_PATH];

void OnWeaponSwitch(int client, int weapon)
{
	if(TF2_IsPlayerInCondition(client, TFCond_Taunting)) {
		return;
	}

	TFClassType class = TFClass_Unknown;

	if(IsValidEntity(weapon)) {
		int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		TFClassType class = TF2_GetPlayerClass(client);
		int slot = TF2Econ_GetItemLoadoutSlot(m_iItemDefinitionIndex, class);
		int wepinslot = GetPlayerWeaponSlot(client, slot);

		if(slot == -1 || wepinslot != weapon) {
			class = GetWeaponClass(weapon, m_iItemDefinitionIndex, class);
		}
	}

	if(class != TFClass_Unknown && class != TF2_GetPlayerClass(client)) {
		GetModelForClass(class, tmpanim, sizeof(tmpanim));
		Playermodel_SetAnimation(client, tmpanim);
	} else {
		Playermodel_SetAnimation(client, "");
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
}