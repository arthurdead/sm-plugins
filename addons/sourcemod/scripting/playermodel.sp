#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <sdkhooks>
#include <playermodel>
#include <sendproxy>
#include <animhelpers>

#if defined GAME_TF2
	#include <tf2>
	#include <tf2_stocks>
	#include <tf2items>
	#include <tf2attributes>
#endif

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "playermodels",
	author = "Arthurdead",
	description = "",
	version = "",
	url = ""
};

#if defined GAME_TF2
Handle hDummyItemView = null;
Handle hEquipWearable = null;
Handle hRecalculatePlayerBodygroups = null;
int m_SharedOffset = -1;
#endif

#define EF_BONEMERGE 0x001
#define EF_BONEMERGE_FASTCULL 0x080
#define EF_PARENT_ANIMATES 0x200
#define EF_NODRAW 0x020
#define EF_NOSHADOW 0x010
#define EF_NORECEIVESHADOW 0x040

#define PLAYERMODELINFO_MODEL_LENGTH PLATFORM_MAX_PATH

#define PlayerModelInvalid (view_as<PlayerModelType>(-1))

GlobalForward OnApplied = null;
GlobalForward OnCleared = null;

#if defined GAME_TF2
	#define OBS_MODE_IN_EYE 4
#else
	#error
#endif

Action OnPropTransmit(int entity, int client)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(client == owner) {
	#if defined GAME_TF2
		bool thirdperson = (
			TF2_IsPlayerInCondition(client, TFCond_Taunting) ||
			GetEntProp(owner, Prop_Send, "m_nForceTauntCam") == 1
		);
	#else
		#error
	#endif
		if(!thirdperson) {
			return Plugin_Handled;
		}
	} else {
		bool firstperson = (
			(GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") == owner &&
			GetEntProp(client, Prop_Send, "m_iObserverMode") == OBS_MODE_IN_EYE)
		);
		if(firstperson) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

enum struct PlayerModelInfo
{
	int owner;
	int entity;
	int link;
	int anim;
	PlayerModelType type;
	PlayerModelType type_default;
	char model[PLAYERMODELINFO_MODEL_LENGTH];
	char model_default[PLAYERMODELINFO_MODEL_LENGTH];
	char animation[PLAYERMODELINFO_MODEL_LENGTH];
	char animation_default[PLAYERMODELINFO_MODEL_LENGTH];
	int skin;
	int skin_default;
	int body;
	int body_default;

	PlayerModelType tmp_type;

#if !defined GAME_TF2
	char model_backup[PLAYERMODELINFO_MODEL_LENGTH];
	int skin_backup;
#endif

	void SetCustomModel(const char[] path)
	{
	#if defined GAME_TF2
		SetVariantString(path);
		AcceptEntityInput(this.owner, "SetCustomModel");
		SetEntProp(this.owner, Prop_Send, "m_bUseClassAnimations", 1);
	#else
		if(StrEqual(path, "")) {
			if(!StrEqual(this.model_backup, "")) {
				SetEntityModel(this.owner, this.model_backup);
			}
		} else {
			GetEntPropString(this.owner, Prop_Data, "m_ModelName", this.model_backup, PLAYERMODELINFO_MODEL_LENGTH);
			SetEntityModel(this.owner, path);
		}
	#endif
	}

	void SetCustomSkin(int skin)
	{
	#if defined GAME_TF2
		if(skin == -1) {
			SetEntProp(this.owner, Prop_Send, "m_bForcedSkin", false);
			SetEntProp(this.owner, Prop_Send, "m_nForcedSkin", 0);
		} else {
			SetEntProp(this.owner, Prop_Send, "m_bForcedSkin", true);
			SetEntProp(this.owner, Prop_Send, "m_nForcedSkin", skin);
		}
	#else
		if(skin == -1) {
			skin = this.skin_backup;
		} else {
			this.skin_backup = GetEntProp(this.owner, Prop_Send, "m_nSkin");
		}
		SetEntProp(this.owner, Prop_Send, "m_nSkin", skin);
	#endif
	}

	void GetStandardModel(char[] model, int len)
	{
	#if defined GAME_TF2
		GetModelForPlayerClass(this.owner, model, len);
	#else
		strcopy(model, len, this.model_backup);
	#endif
	}

	void RecalculateBodygroup()
	{
		if(IsValidEntity(this.owner)) {
		#if defined GAME_TF2
			Address pEntity = GetEntityAddress(this.owner);
			if(pEntity != Address_Null) {
				Address m_Shared = (pEntity + view_as<Address>(m_SharedOffset));
				SDKCall(hRecalculatePlayerBodygroups, m_Shared);
			}
		#else
			SetEntProp(this.owner, Prop_Send, "m_nBody", 0);
		#endif
		}

	#if defined GAME_TF2
		Event event = CreateEvent("post_inventory_application");
		event.SetInt("userid", GetClientUserId(this.owner));
		event.FireToClient(this.owner);
		delete event;
	#endif
	}

	void DeleteAnim()
	{
		if(this.type != PlayerModelProp) {
			if(!StrEqual(this.animation, "")) {
				this.SetCustomModel("");
			}
		} else {
			int entity = EntRefToEntIndex(this.anim);
			if(IsValidEntity(entity) && entity != this.owner) {
				AcceptEntityInput(entity, "ClearParent");
				RemoveEntity(entity);
			}
		}
		this.anim = EntIndexToEntRef(this.owner);
	}

	void ClearDefault()
	{
		this.SetModel("", true);
		this.SetAnimation("", true);
		this.type_default = PlayerModelDefault;
		this.skin_default = -1;
		this.body_default = -1;
	}

	void ClearDeath(bool callfwd, int val)
	{
		this.DeleteEntity();

		int ref = EntIndexToEntRef(this.owner);
		this.link = ref;
		this.entity = ref;
		this.anim = ref;
		this.SetModel("");
		this.SetAnimation("");
		this.skin = -1;
		this.body = -1;
		this.type = PlayerModelDefault;

		this.tmp_type = PlayerModelInvalid;

	#if !defined GAME_TF2
		strcopy(this.model_backup, PLAYERMODELINFO_MODEL_LENGTH, "");
		this.skin_backup = 0;
	#endif

		if(callfwd) {
			Call_StartForward(OnCleared);
			Call_PushCell(this.owner);
			Call_PushCell(val);
			Call_Finish();
		}
	}

	void __InternalClearAllVars(bool callfwd, int val)
	{
		this.ClearDefault();
		this.ClearDeath(callfwd, val);
	}

	void ClearDisconnect()
	{
		this.__InternalClearAllVars(true, 0);
		this.link = INVALID_ENT_REFERENCE;
		this.entity = INVALID_ENT_REFERENCE;
		this.anim = INVALID_ENT_REFERENCE;
	}

	void Init()
	{
		int ref = EntIndexToEntRef(this.owner);
		this.link = ref;
		this.entity = ref;
		this.anim = ref;
		this.__InternalClearAllVars(false, 0);
	}

	void DeleteEntity()
	{
		SendProxy_Unhook(this.owner, "m_clrRender", SendProxyRenderCLR);
		SendProxy_Unhook(this.owner, "m_nRenderMode", SendProxyRenderMode);

		this.RecalculateBodygroup();

		this.DeleteAnim();

		int entity = EntRefToEntIndex(this.entity);

		if(this.IsProp()) {
			if(IsValidEntity(entity)) {
				AcceptEntityInput(entity, "ClearParent");
			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					TF2_RemoveWearable(this.owner, entity);
				}
			#endif
				{
					RemoveEntity(entity);
				}
			}
			this.DeleteLink();
			SetEntityRenderMode(this.owner, RENDER_NORMAL);
		#if defined GAME_TF2
			if(this.type != PlayerModelBonemerge) {
				this.SetCustomModel("");
			}
		#endif
		} else if(this.type == PlayerModelCustomModel) {
			this.SetCustomModel("");
		}
		this.entity = EntIndexToEntRef(this.owner);
	}

	bool IsProp(bool def=false)
	{
		if(def) {
			return (this.type_default == PlayerModelProp || this.type_default == PlayerModelBonemerge);
		} else {
			return (this.type == PlayerModelProp || this.type == PlayerModelBonemerge);
		}
	}

	void SetModel(const char[] path, bool def=false)
	{
		if(def) {
			strcopy(this.model_default, PLAYERMODELINFO_MODEL_LENGTH, path);
		} else {
			strcopy(this.model, PLAYERMODELINFO_MODEL_LENGTH, path);
		}
	}

	void SetAnimation(const char[] path, bool def=false)
	{
		if(def) {
			strcopy(this.animation_default, PLAYERMODELINFO_MODEL_LENGTH, path);
		} else {
			strcopy(this.animation, PLAYERMODELINFO_MODEL_LENGTH, path);
		}
	}

	void SetSkin()
	{
		this.__InternalSetSkin(this.IsProp());
	}

	void SetBody()
	{
		this.CheckForDefault();

		int entity = EntRefToEntIndex(this.entity);

		if(this.body != -1) {
			SetEntProp(entity, Prop_Send, "m_nBody", this.body);
		} else {
			if(this.type == PlayerModelBonemerge) {
				int body = GetEntProp(this.owner, Prop_Send, "m_nBody");
				SetEntProp(entity, Prop_Send, "m_nBody", body);
			} else if(this.type == PlayerModelDefault) {
				this.RecalculateBodygroup();
			} else if(this.type == PlayerModelCustomModel) {
				SetEntProp(entity, Prop_Send, "m_nBody", 0);
			} else {
				SetEntProp(entity, Prop_Send, "m_nBody", 0);
			}
		}
	}

	void __InternalSetSkin(bool prop)
	{
		this.CheckForDefault();

		int entity = EntRefToEntIndex(this.entity);

		if(this.skin != -1) {
			if(prop) {
			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					SetEntProp(entity, Prop_Send, "m_iTeamNum", this.skin);
				} else
			#endif
				{
					SetEntProp(entity, Prop_Send, "m_nSkin", this.skin);
				}
			} else {
				this.SetCustomSkin(this.skin);
			}
		} else {
			if(prop) {
				if(this.type == PlayerModelBonemerge) {
				#if defined GAME_TF2
					SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(this.owner));
				#else
					int skin = GetEntProp(this.owner, Prop_Send, "m_nSkin");
					SetEntProp(entity, Prop_Send, "m_nSkin", skin);
				#endif
				} else {
					SetEntProp(entity, Prop_Send, "m_nSkin", 0);
				}
			} else {
				this.SetCustomSkin(-1);
			}
		}
	}

	void DeleteLink()
	{
	#if defined GAME_TF2
		int entity = EntRefToEntIndex(this.link);
		if(IsValidEntity(entity) && entity != this.owner) {
			AcceptEntityInput(entity, "ClearParent");
			RemoveEntity(entity);
		}
	#endif
		this.link = EntIndexToEntRef(this.owner);
	}

	void GetCurrentModel(char[] model, int len)
	{
	#if defined GAME_TF2
		GetEntPropString(this.owner, Prop_Send, "m_iszCustomModel", model, len);
		if(StrEqual(model, "")) {
			TFClassType class = TF2_GetPlayerClass(this.owner);
			GetModelForClass(class, model, len);
		}
	#else
		GetEntPropString(this.owner, Prop_Data, "m_ModelName", model, len);
	#endif
	}

	bool CreateAnim()
	{
		if(!StrEqual(this.animation, "")) {
			if(this.type != PlayerModelProp) {
				this.anim = EntIndexToEntRef(this.owner);

				char currmodel[PLATFORM_MAX_PATH];
				this.GetCurrentModel(currmodel, sizeof(currmodel));

				if(!StrEqual(this.animation, currmodel)) {
					this.SetCustomModel(this.animation);

					if(this.type == PlayerModelCustomModel || this.type == PlayerModelDefault) {
						if(this.type == PlayerModelDefault) {
							this.GetStandardModel(this.model, PLAYERMODELINFO_MODEL_LENGTH);
						}
						this.tmp_type = this.type;
						this.type = PlayerModelBonemerge;
					}
				}
			} else {
				this.DeleteAnim();

				this.CreateLink();

				int entity = CreateEntityByName("funCBaseFlex");

				float pos[3];
				GetClientAbsOrigin(this.owner, pos);

				DispatchKeyValue(entity, "model", this.animation);
				DispatchKeyValueVector(entity, "origin", pos);
				DispatchSpawn(entity);

				SetEntityModel(entity, this.animation);

				int link = EntRefToEntIndex(this.link);

				SetVariantString("!activator");
				AcceptEntityInput(entity, "SetParent", link);

				SetEntProp(entity, Prop_Send, "m_bClientSideAnimation", 0);
				SetEntProp(entity, Prop_Send, "m_bClientSideFrameReset", 0);
				SetEntPropFloat(entity, Prop_Send, "m_flPlaybackRate", 1.0);

				int flags = GetEntProp(entity, Prop_Send, "m_fEffects");
				flags |= EF_PARENT_ANIMATES|EF_NODRAW|EF_NOSHADOW|EF_NORECEIVESHADOW;
				SetEntProp(entity, Prop_Send, "m_fEffects", flags);

				SetEntityRenderMode(entity, RENDER_NONE);

				SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", this.owner);

				this.anim = EntIndexToEntRef(entity);

				return true;
			}
		}

		return false;
	}

	int CreateLink(bool force=false)
	{
	#if defined GAME_TF2
		if(force || this.type == PlayerModelProp) {
			this.DeleteLink();

			int entity = CreateEntityByName("prop_dynamic_override");

			float pos[3];
			GetClientAbsOrigin(this.owner, pos);

			char currmodel[PLATFORM_MAX_PATH];
			this.GetCurrentModel(currmodel, sizeof(currmodel));

			DispatchKeyValue(entity, "model", currmodel);
			DispatchKeyValueVector(entity, "origin", pos);
			DispatchSpawn(entity);

			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", this.owner);

			int flags = EF_BONEMERGE|
			EF_BONEMERGE_FASTCULL|EF_NOSHADOW|
			EF_NORECEIVESHADOW|EF_PARENT_ANIMATES;
			SetEntProp(entity, Prop_Send, "m_fEffects", flags);

			SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", this.owner);

			this.link = EntIndexToEntRef(entity);
		} else
	#endif
		{
			this.link = EntIndexToEntRef(this.owner);
		}
		return this.link;
	}

	void Apply()
	{
		this.CheckForDefault();

		bool created_anim_ent = this.CreateAnim();

		bool prop = this.IsProp();

		switch(this.type)
		{
			case PlayerModelCustomModel, PlayerModelDefault:
			{
				this.entity = EntIndexToEntRef(this.owner);

				if(this.type == PlayerModelCustomModel) {
					this.SetCustomModel(this.model);
				}

				SetEntityRenderMode(this.owner, RENDER_NORMAL);
			}
			case PlayerModelProp, PlayerModelBonemerge:
			{
				int entity = EntRefToEntIndex(this.entity);

				if(IsValidEntity(entity) && entity != this.owner) {
					AcceptEntityInput(entity, "ClearParent");
					RemoveEntity(entity);
				}

			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					entity = TF2Items_GiveNamedItem(this.owner, hDummyItemView);
				} else
			#endif
				{
				#if defined GAME_L4D2
					entity = CreateEntityByName("commentary_dummy");
				#else
					if(!created_anim_ent) {
						entity = CreateEntityByName("funCBaseFlex");
					} else {
						//entity = CreateEntityByName("prop_dynamic_override");
						entity = CreateEntityByName("funCBaseFlex");
					}
				#endif
				}

				float pos[3];
				GetClientAbsOrigin(this.owner, pos);

				DispatchKeyValueVector(entity, "origin", pos);
				DispatchKeyValue(entity, "model", this.model);
			#if defined GAME_TF2
				if(this.type != PlayerModelBonemerge)
			#endif
				{
					DispatchSpawn(entity);
				}

			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					SetEntPropString(entity, Prop_Data, "m_iClassname", "playermodel_wearable");
				}
			#endif

				SetEntPropFloat(entity, Prop_Send, "m_flPlaybackRate", 1.0);

				int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
				if(created_anim_ent || this.type == PlayerModelBonemerge) {
					effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL;
				}
				effects |= EF_PARENT_ANIMATES;
				effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
				SetEntProp(entity, Prop_Send, "m_fEffects", effects);

				if(!created_anim_ent) {
					this.CreateLink();
				}

				int link = EntRefToEntIndex(created_anim_ent ? this.anim : this.link);

				SetVariantString("!activator");
				AcceptEntityInput(entity, "SetParent", link);

				SetEntityRenderMode(this.owner, RENDER_NONE);

				SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
				SetEntityRenderColor(entity, 255, 255, 255, 255);

			#if defined GAME_TF2
				if(this.type != PlayerModelBonemerge) {
					this.SetCustomModel(this.model);
				}
			#endif

				if(!created_anim_ent && this.type == PlayerModelProp) {
					SetEntProp(entity, Prop_Send, "m_bClientSideAnimation", 0);
					SetEntProp(entity, Prop_Send, "m_bClientSideFrameReset", 0);
				}

				if(this.type == PlayerModelBonemerge) {
					//SendProxy_Hook(this.owner, "m_clrRender", Prop_Int, SendProxyRenderCLR, true);
					//SendProxy_Hook(this.owner, "m_nRenderMode", Prop_Int, SendProxyRenderMode, true);
				}

			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					SDKCall(hEquipWearable, this.owner, entity);
					SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
				}
			#endif

				SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", this.owner);

				if(this.type == PlayerModelProp) {
					//SDKHook(entity, SDKHook_SetTransmit, OnPropTransmit);
				}

				SetEntityModel(entity, this.model);

				this.entity = EntIndexToEntRef(entity);

				if(!created_anim_ent && this.type == PlayerModelProp) {
					this.anim = this.entity;
				}
			}
		}

		this.__InternalSetSkin(prop);
		this.SetBody();

		Call_StartForward(OnApplied);
		Call_PushCell(this.owner);
		Call_Finish();
	}

	void CheckForDefault()
	{
		if(this.type == PlayerModelDefault && this.type_default != PlayerModelDefault) {
			this.type = this.type_default;
		}

		if(this.skin == -1 && this.skin_default != -1) {
			this.skin = this.skin_default;
		}

		if(this.body == -1 && this.body_default != -1) {
			this.body = this.body_default;
		}

		if(StrEqual(this.model, "") && !StrEqual(this.model_default, "")) {
			this.SetModel(this.model_default);
		}

		if(StrEqual(this.animation, "") && !StrEqual(this.animation_default, "")) {
			this.SetAnimation(this.animation_default);
		}
	}

	int GetSkin(bool def=false)
	{
		if(!def && this.skin == -1) {
			int entity = EntRefToEntIndex(this.entity);
			return GetEntProp(entity, Prop_Send, "m_nSkin");
		} else {
			if(def) {
				return this.skin_default;
			} else {
				return this.skin;
			}
		}
	}

	int GetBody(bool def=false)
	{
		if(!def && this.body == -1) {
			int entity = EntRefToEntIndex(this.entity);
			return GetEntProp(entity, Prop_Send, "m_nBody");
		} else {
			if(def) {
				return this.body_default;
			} else {
				return this.body;
			}
		}
	}

	void GetModel(char[] path, int length, bool def=false)
	{
		if((!def && this.type == PlayerModelDefault) || (def && this.type_default == PlayerModelDefault)) {
			this.GetStandardModel(path, length);
		} else {
			if(def) {
				strcopy(path, length, this.model_default);
			} else {
				strcopy(path, length, this.model);
			}
		}
	}

	void GetAnimation(char[] path, int length, bool def=false)
	{
		if((!def && StrEqual(this.animation, "")) || (def && StrEqual(this.animation_default, ""))) {
			this.GetStandardModel(path, length);
		} else {
			if(def) {
				strcopy(path, length, this.animation_default);
			} else {
				strcopy(path, length, this.animation);
			}
		}
	}
}

PlayerModelInfo g_PlayersModelInfo[33];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("playermodel");
	CreateNative("Playermodel_Clear", Native_Clear);
	CreateNative("Playermodel_Reapply", Native_Reapply);
	CreateNative("Playermodel_GetModel", Native_GetModel);
	CreateNative("Playermodel_GetAnimation", Native_GetAnimation);
	CreateNative("Playermodel_GetEntity", Native_GetEntity);
	CreateNative("Playermodel_GetLink", Native_GetLink);
	CreateNative("Playermodel_CreateLink", Native_CreateLink);
	CreateNative("Playermodel_GetAnimEnt", Native_GetAnimEnt);
	CreateNative("Playermodel_SetModel", Native_SetModel);
	CreateNative("Playermodel_SetAnimation", Native_SetAnimation);
	CreateNative("Playermodel_GetType", Native_GetType);
	CreateNative("PlayerModel_SetType", Native_SetType);
	CreateNative("Playermodel_GetSkin", Native_GetSkin);
	CreateNative("Playermodel_SetSkin", Native_SetSkin);
	CreateNative("Playermodel_GetBodygroup", Native_GetBodygroup);
	CreateNative("Playermodel_SetBodygroup", Native_SetBodygroup);
	OnApplied = new GlobalForward("Playermodel_OnApplied", ET_Ignore, Param_Cell);
	OnCleared = new GlobalForward("Playermodel_OnCleared", ET_Ignore, Param_Cell, Param_Cell);
	return APLRes_Success;
}

int Native_GetBodygroup(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	bool def = GetNativeCell(2);

	return g_PlayersModelInfo[client].GetBody(def);
}

int Native_SetBodygroup(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	int body = GetNativeCell(2);
	bool def = GetNativeCell(3);

	if(def) {
		g_PlayersModelInfo[client].body_default = body;
	} else {
		g_PlayersModelInfo[client].body = body;
	}
	g_PlayersModelInfo[client].SetBody();

	return 0;
}

int Native_GetSkin(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	bool def = GetNativeCell(2);

	return g_PlayersModelInfo[client].GetSkin(def);
}

int Native_SetSkin(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	int skin = GetNativeCell(2);
	bool def = GetNativeCell(3);

	if(def) {
		g_PlayersModelInfo[client].skin_default = skin;
	} else {
		g_PlayersModelInfo[client].skin = skin;
	}
	g_PlayersModelInfo[client].SetSkin();

	return 0;
}

int Native_GetEntity(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return g_PlayersModelInfo[client].entity;
}

int Native_GetLink(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return g_PlayersModelInfo[client].link;
}

int Native_CreateLink(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int link = EntRefToEntIndex(g_PlayersModelInfo[client].link);
	if(link == client || !IsValidEntity(link)) {
		g_PlayersModelInfo[client].CreateLink(true);
	}

	return g_PlayersModelInfo[client].link;
}

int Native_GetAnimEnt(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return g_PlayersModelInfo[client].anim;
}

int Native_GetAnimation(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	int length = GetNativeCell(3);
	bool def = GetNativeCell(4);

	char[] tmp = new char[length];
	g_PlayersModelInfo[client].GetAnimation(tmp, length, def);

	SetNativeString(2, tmp, length);

	return 0;
}

int Native_GetModel(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	int length = GetNativeCell(3);
	bool def = GetNativeCell(4);

	char[] tmp = new char[length];
	g_PlayersModelInfo[client].GetModel(tmp, length, def);

	SetNativeString(2, tmp, length);

	return 0;
}

int Native_SetModel(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] model = new char[length];
	GetNativeString(2, model, length);

	bool def = GetNativeCell(3);

	g_PlayersModelInfo[client].DeleteEntity();

	g_PlayersModelInfo[client].SetModel(model, def);

	if(g_PlayersModelInfo[client].type == PlayerModelDefault) {
		g_PlayersModelInfo[client].type = PlayerModelCustomModel;
	}

	g_PlayersModelInfo[client].Apply();

	return g_PlayersModelInfo[client].entity;
}

int Native_SetAnimation(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] model = new char[length];
	GetNativeString(2, model, length);

	bool def = GetNativeCell(3);

	g_PlayersModelInfo[client].DeleteEntity();

	g_PlayersModelInfo[client].SetAnimation(model, def);

	if(StrEqual(model, "")) {
		if(g_PlayersModelInfo[client].tmp_type != PlayerModelInvalid) {
			g_PlayersModelInfo[client].type = g_PlayersModelInfo[client].tmp_type;
			if(g_PlayersModelInfo[client].type == PlayerModelDefault) {
				g_PlayersModelInfo[client].SetModel("");
			}
		}
	}

	g_PlayersModelInfo[client].Apply();

	return g_PlayersModelInfo[client].entity;
}

int Native_SetType(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	PlayerModelType type = view_as<PlayerModelType>(GetNativeCell(3));

	int length = 0;
	GetNativeStringLength(2, length);
	length++;

	char[] model = new char[length];
	GetNativeString(2, model, length);

	bool def = GetNativeCell(4);

	if(def) {
		g_PlayersModelInfo[client].type_default = type;
		g_PlayersModelInfo[client].SetModel(model, true);
	} else {
		g_PlayersModelInfo[client].type = type;
		g_PlayersModelInfo[client].SetModel(model);
	}

	g_PlayersModelInfo[client].Apply();

	return g_PlayersModelInfo[client].entity;
}

int Native_GetType(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	bool def = GetNativeCell(2);

	if(def) {
		return view_as<int>(g_PlayersModelInfo[client].type_default);
	} else {
		return view_as<int>(g_PlayersModelInfo[client].type);
	}
}

int Native_Clear(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	bool def = GetNativeCell(2);
	bool reapply = GetNativeCell(3);

	if(def) {
		g_PlayersModelInfo[client].ClearDefault();
	} else {
		g_PlayersModelInfo[client].ClearDeath(true, 2);
	}

	if(reapply) {
		g_PlayersModelInfo[client].Apply();
	}

	return 0;
}

int Native_Reapply(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	g_PlayersModelInfo[client].Apply();

	return g_PlayersModelInfo[client].entity;
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientDisconnect(i);
		}
	}
}

#if defined GAME_TF2
int m_flInvisibilityOffset = -1;
#endif

public void OnPluginStart()
{
	for(int i = 0; i < sizeof(g_PlayersModelInfo); ++i) {
		g_PlayersModelInfo[i].owner = i;
	}

	GameData hGameConf = new GameData("playermodel");
	if(hGameConf == null) {
		SetFailState("Gamedata not found.");
		return;
	}
	
#if defined GAME_TF2
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBasePlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	hEquipWearable = EndPrepSDKCall();
	if(hEquipWearable == null) {
		SetFailState("Failed to create SDKCall for CBasePlayer::EquipWearable.");
		delete hGameConf;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFPlayerShared::RecalculatePlayerBodygroups");
	hRecalculatePlayerBodygroups = EndPrepSDKCall();
	if(hRecalculatePlayerBodygroups == null) {
		SetFailState("Failed to create SDKCall for CTFPlayerShared::RecalculatePlayerBodygroups.");
		delete hGameConf;
		return;
	}

	m_SharedOffset = FindSendPropInfo("CTFPlayer", "m_Shared");
#endif
	
	delete hGameConf;

#if defined GAME_TF2
	hDummyItemView = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(hDummyItemView, "tf_wearable");
	TF2Items_SetItemIndex(hDummyItemView, -1);
	TF2Items_SetQuality(hDummyItemView, 0);
	TF2Items_SetLevel(hDummyItemView, 0);
	TF2Items_SetNumAttributes(hDummyItemView, 0);
#endif

	HookEvent("player_death", player_death);
	HookEvent("player_spawn", player_spawn);
#if defined GAME_TF2
	HookEvent("post_inventory_application", post_inventory_application);
#endif

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

#if defined GAME_TF2
	m_flInvisibilityOffset = FindSendPropInfo("CTFPlayer", "m_flInvisChangeCompleteTime");
	m_flInvisibilityOffset -= 8;
#endif
}

#if defined GAME_TF2
int CalcSpyAlpha(int client)
{
	if(!TF2_IsPlayerInCondition(client, TFCond_Disguised)) {
		float invis = GetEntDataFloat(client, m_flInvisibilityOffset);
		if(invis > 0.0) {
			invis = 1.0 - invis;
			int a = RoundToCeil(255 * invis);
			if(a < 0) {
				a = 0;
			}
			if(a > 255) {
				a = 255;
			}
			return a;
		}
	}
	return -1;
}
#endif

int GetEntityAlpha(int entity)
{
	int r = 255;
	int g = 255;
	int b = 255;
	int a = 255;
	GetEntityRenderColor(entity, r, g, b, a);
	return a;
}

void SetEntityAlpha(int entity, int a)
{
	int r = 255;
	int g = 255;
	int b = 255;
	int __a = 255;
	GetEntityRenderColor(entity, r, g, b, __a);
	__a = a;
	SetEntityRenderColor(entity, r, g, b, a);
}

void OnPlayerPostThink(int client)
{
	PlayerModelType type = g_PlayersModelInfo[client].type;
	if(type == PlayerModelProp || type == PlayerModelBonemerge) {
		int entity = EntRefToEntIndex(g_PlayersModelInfo[client].entity);
		if(!IsValidEntity(entity)) {
			return;
		}

		if(type == PlayerModelProp) {
			int anim = EntRefToEntIndex(g_PlayersModelInfo[client].anim);
			if(IsValidEntity(anim)) {
				if(anim != entity) {
					float pos[3];
					GetClientAbsOrigin(client, pos);

					float ang[3];
					GetClientAbsAngles(client, ang);
					ang[0] = 0.0;

					TeleportEntity(anim, pos, ang);
				}

				view_as<BaseAnimating>(anim).StudioFrameAdvance();
			}

			int link = EntRefToEntIndex(g_PlayersModelInfo[client].link);
			if(IsValidEntity(link)) {
				int flags = GetEntProp(link, Prop_Send, "m_fEffects");
				if(flags & EF_BONEMERGE_FASTCULL) {
					int buttons = GetEntProp(client, Prop_Data, "m_nButtons");
					bool m_bDucked = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked"));
					bool m_bDucking = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucking")) || (buttons & IN_DUCK);

					float localorigin[3];
					if(m_bDucked || m_bDucking) {
						localorigin[2] = -30.0;
					} else {
						localorigin[2] = -40.0;
					}

					SetEntPropVector(entity, Prop_Send, "m_vecOrigin", localorigin);
				}
			}
		}

		int r = 255;
		int g = 255;
		int b = 255;
		int a = 255;
		GetEntityRenderColor(client, r, g, b, a);

	#if defined GAME_TF2
		if(TF2_GetPlayerClass(client) == TFClass_Spy) {
			int mod = CalcSpyAlpha(client);
			if(mod != -1 && mod < a) {
				a = mod;
			}
		}
	#endif

		SetEntityRenderMode(client, RENDER_NONE);
		SetEntityRenderColor(entity, r, g, b, a);
	}
}

#if defined GAME_TF2
public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if(g_PlayersModelInfo[client].type == PlayerModelCustomModel) {
		if(condition == TFCond_Disguised) {
			g_PlayersModelInfo[client].SetCustomModel("");
		}
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(g_PlayersModelInfo[client].type == PlayerModelCustomModel) {
		if(condition == TFCond_Disguised) {
			g_PlayersModelInfo[client].SetCustomModel(g_PlayersModelInfo[client].model);
		}
	}
}

void FrameInventory(int client)
{
	g_PlayersModelInfo[client].Apply();
}

void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(g_PlayersModelInfo[client].type == PlayerModelBonemerge) {
		RequestFrame(FrameInventory, client);
	}
}
#endif

void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	g_PlayersModelInfo[client].Apply();
}

void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
#if defined GAME_TF2
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER))
#endif
	{
		g_PlayersModelInfo[client].ClearDeath(true, 1);
	}
}

Action SendProxyRenderCLR(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(iClient == iEntity) {
		if(g_PlayersModelInfo[iEntity].type == PlayerModelBonemerge &&
			!TF2_IsPlayerInCondition(iEntity, TFCond_Disguised)) {
			iValue = 0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

Action SendProxyRenderMode(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(iClient == iEntity) {
		if(g_PlayersModelInfo[iEntity].type == PlayerModelBonemerge) {
			iValue = view_as<int>(RENDER_TRANSCOLOR);
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	g_PlayersModelInfo[client].Init();
	SDKHook(client, SDKHook_PostThink, OnPlayerPostThink);
}

public void OnClientDisconnect(int client)
{
	g_PlayersModelInfo[client].ClearDisconnect();
}