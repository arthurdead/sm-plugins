#include <sourcemod>
#include <playermodel>
#include <sdkhooks>
#include <tf_econ_data>

public void OnPluginStart()
{
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

TFClassType GetWeaponClass(int item)
{
	for(TFClassType i = TFClass_Scout; i < TFClass_Engineer; ++i) {
		if(TF2Econ_GetItemLoadoutSlot(item, i) != -1) {
			return i;
		}
	}
	return TFClass_Unknown;
}

void OnWeaponSwitch(int client, int weapon)
{
	if(HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex")) {
		int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		int slot = TF2Econ_GetItemLoadoutSlot(m_iItemDefinitionIndex, TF2_GetPlayerClass(client));
		if(slot == -1 || GetPlayerWeaponSlot(client, slot) != weapon) {
			TFClassType class = GetWeaponClass(m_iItemDefinitionIndex);
			if(class != TFClass_Unknown) {
				char anim[64];
				GetModelForClass(class, anim, sizeof(anim));
				Playermodel_SetAnimation(client, anim);
			} else {
				Playermodel_SetAnimation(client, "");
			}
		} else {
			Playermodel_SetAnimation(client, "");
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
}