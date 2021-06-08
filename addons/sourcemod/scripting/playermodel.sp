#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <sdkhooks>

#include <playermodel>

#if defined GAME_TF2
	#include <tf2>
	#include <tf2_stocks>
	#include <tf2items>
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
	int entity;
	int owner;
	int link;
	PlayerModelType type;
	PlayerModelType type_default;
	char model[PLAYERMODELINFO_MODEL_LENGTH];
	char model_default[PLAYERMODELINFO_MODEL_LENGTH];
	char animation[PLAYERMODELINFO_MODEL_LENGTH];
	char animation_default[PLAYERMODELINFO_MODEL_LENGTH];
	int skin;
	int skin_default;

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

	void __InternalDeleteEntity(bool prop)
	{
		if(prop) {
			if(IsValidEntity(this.entity)) {
			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					TF2_RemoveWearable(this.owner, this.entity);
				} else
			#endif
				{
					RemoveEntity(this.entity);
				}
			}
			this.DeleteLink();
			SetEntityRenderMode(this.owner, RENDER_TRANSCOLOR);
			SetEntityRenderColor(this.owner, 255, 255, 255, 255);
		#if defined GAME_TF2
			if(this.type != PlayerModelBonemerge) {
				this.SetCustomModel("");
			}
		#endif
		} else if(this.type == PlayerModelCustomModel) {
			this.SetCustomModel("");
		}
		if(!StrEqual(this.animation, "")) {
			this.SetCustomModel("");
		}
		this.entity = INVALID_ENT_REFERENCE;
	}

	void ClearDefault()
	{
		this.SetModel("", true);
		this.SetAnimation("", true);
		this.type_default = PlayerModelDefault;
		this.skin_default = -1;
	}

	void ClearDeath()
	{
		this.DeleteEntity();

		this.owner = INVALID_ENT_REFERENCE;
		this.link = INVALID_ENT_REFERENCE;
		this.entity = INVALID_ENT_REFERENCE;
		this.SetModel("");
		this.SetAnimation("");
		this.skin = -1;
		this.type = PlayerModelDefault;

		this.tmp_type = PlayerModelInvalid;

	#if !defined GAME_TF2
		strcopy(this.model_backup, PLAYERMODELINFO_MODEL_LENGTH, "");
		this.skin_backup = 0;
	#endif
	}

	void ClearDisconnect()
	{
		this.ClearDefault();
		this.ClearDeath();
	}

	void DeleteEntity()
	{
		this.__InternalDeleteEntity(this.IsProp());
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

	void __InternalSetSkin(bool prop)
	{
		this.CheckForDefault();

		if(this.skin != -1) {
			if(prop) {
			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					SetEntProp(this.entity, Prop_Send, "m_nSkin", this.skin);
				} else
			#endif
				{
					SetEntProp(this.entity, Prop_Send, "m_nSkin", this.skin);
				}
			} else {
				this.SetCustomSkin(this.skin);
			}
		} else {
			if(prop) {
				SetEntProp(this.entity, Prop_Send, "m_nSkin", 0);
			} else {
				this.SetCustomSkin(-1);
			}
		}
	}

	void DeleteLink()
	{
	#if defined GAME_TF2
		if(this.link != this.owner && IsValidEntity(this.link)) {
			RemoveEntity(this.link);
		}
	#endif
		this.link = INVALID_ENT_REFERENCE;
	}

	int CreateLink()
	{
	#if defined GAME_TF2
		if(this.type == PlayerModelProp) {
			this.DeleteLink();

			this.link = CreateEntityByName("prop_dynamic_override");

			char tmp[PLATFORM_MAX_PATH];
			TFClassType class = TF2_GetPlayerClass(this.owner);
			GetModelForClass(class, tmp, sizeof(tmp));

			DispatchKeyValue(this.link, "model", tmp);
			DispatchSpawn(this.link);

			SetEntityModel(this.link, tmp);

			SetVariantString("!activator");
			AcceptEntityInput(this.link, "SetParent", this.owner);

			//|EF_NOSHADOW|EF_NORECEIVESHADOW
			SetEntProp(this.link, Prop_Send, "m_fEffects", EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
		} else
	#endif
		{
			this.link = this.owner;
		}
		return this.link;
	}

	void Apply(int client)
	{
		this.CheckForDefault();
		this.owner = client;

		if(!StrEqual(this.animation, "")) {
			char currmodel[PLATFORM_MAX_PATH];
		#if defined GAME_TF2
			GetEntPropString(client, Prop_Send, "m_iszCustomModel", currmodel, sizeof(currmodel));
			if(StrEqual(currmodel, "")) {
				GetModelForClass(TF2_GetPlayerClass(client), currmodel, sizeof(currmodel));
			}
		#else
			GetEntPropString(entity, Prop_Data, "m_ModelName", currmodel, sizeof(currmodel));
		#endif

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
		}

		bool prop = this.IsProp();

		switch(this.type)
		{
			case PlayerModelCustomModel, PlayerModelDefault:
			{
				this.entity = this.owner;

				if(this.type == PlayerModelCustomModel) {
					this.SetCustomModel(this.model);

					SetEntityRenderMode(this.owner, RENDER_TRANSCOLOR);
					SetEntityRenderColor(this.owner, 255, 255, 255, 255);
				}
			}
			case PlayerModelProp, PlayerModelBonemerge:
			{
				if((this.entity != this.owner) && IsValidEntity(this.entity)) {
					SetEntityModel(this.entity, this.model);
				} else {
				#if defined GAME_TF2
					if(this.type == PlayerModelBonemerge) {
						this.entity = TF2Items_GiveNamedItem(this.owner, hDummyItemView);
					} else
				#endif
					{
					#if defined GAME_L4D2
						this.entity = CreateEntityByName("commentary_dummy");
					#else
						this.entity = CreateEntityByName("prop_dynamic_override");
					#endif
					}

					DispatchKeyValue(this.entity, "model", this.model);
				#if defined GAME_TF2
					if(this.type != PlayerModelBonemerge)
				#endif
					{
						DispatchSpawn(this.entity);
					}

					SetEntPropFloat(this.entity, Prop_Send, "m_flPlaybackRate", 1.0);

					int effects = GetEntProp(this.entity, Prop_Send, "m_fEffects");
					if(this.type == PlayerModelBonemerge) {
						effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL;
					}
					effects |= EF_PARENT_ANIMATES;
					effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
					SetEntProp(this.entity, Prop_Send, "m_fEffects", effects);

					this.CreateLink();

					SetVariantString("!activator");
					AcceptEntityInput(this.entity, "SetParent", this.link);

					SetEntityRenderMode(this.owner, RENDER_TRANSCOLOR);
					SetEntityRenderColor(this.owner, 255, 255, 255, 0);

					SetEntityRenderMode(this.entity, RENDER_TRANSCOLOR);
					SetEntityRenderColor(this.entity, 255, 255, 255, 255);

				#if defined GAME_TF2
					if(this.type != PlayerModelBonemerge) {
						this.SetCustomModel(this.model);
					}
				#endif

				#if defined GAME_TF2
					if(this.type == PlayerModelBonemerge) {
						SDKCall(hEquipWearable, this.owner, this.entity);
					} else
				#endif
					{
						SetEntProp(this.entity, Prop_Send, "m_bClientSideAnimation", 0);
						SetEntProp(this.entity, Prop_Send, "m_bClientSideFrameReset", 0);
					}

				#if defined GAME_TF2
					if(this.type == PlayerModelBonemerge) {
						SetEntProp(this.entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
					}
				#endif

					SetEntPropEnt(this.entity, Prop_Send, "m_hOwnerEntity", this.owner);

					if(this.type == PlayerModelProp) {
						//SDKHook(this.entity, SDKHook_SetTransmit, OnPropTransmit);
					}

					SetEntityModel(this.entity, this.model);
				}
			}
		}

		this.__InternalSetSkin(prop);

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
			return GetEntProp(this.entity, Prop_Send, "m_nSkin");
		} else {
			if(def) {
				return this.skin_default;
			} else {
				return this.skin;
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
	CreateNative("Playermodel_GetModel", Native_GetModel);
	CreateNative("Playermodel_GetAnimation", Native_GetAnimation);
	CreateNative("Playermodel_GetEntity", Native_GetEntity);
	CreateNative("Playermodel_SetAnimation", Native_SetAnimation);
	CreateNative("Playermodel_GetType", Native_GetType);
	CreateNative("PlayerModel_SetType", Native_SetType);
	CreateNative("Playermodel_GetSkin", Native_GetSkin);
	CreateNative("Playermodel_SetSkin", Native_SetSkin);
	OnApplied = new GlobalForward("Playermodel_OnApplied", ET_Ignore, Param_Cell);
	return APLRes_Success;
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

	g_PlayersModelInfo[client].Apply(client);

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

	bool def = GetNativeCell(3);

	if(def) {
		g_PlayersModelInfo[client].type_default = type;
		g_PlayersModelInfo[client].SetModel(model, true);
	} else {
		g_PlayersModelInfo[client].type = type;
		g_PlayersModelInfo[client].SetModel(model);
	}

	g_PlayersModelInfo[client].Apply(client);

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

	if(def) {
		g_PlayersModelInfo[client].ClearDefault();
	} else {
		g_PlayersModelInfo[client].ClearDeath();
	}

	return 0;
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientDisconnect(i);
		}
	}
}

int m_flInvisibilityOffset = -1;

public void OnPluginStart()
{
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
#endif
	
	delete hGameConf;

#if defined GAME_TF2
	hDummyItemView = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(hDummyItemView, "tf_wearable");
	TF2Items_SetItemIndex(hDummyItemView, 116);
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

	m_flInvisibilityOffset = FindSendPropInfo("CTFPlayer", "m_flInvisChangeCompleteTime");
	m_flInvisibilityOffset -= 8;
}

void OnPlayerPostThink(int client)
{
	if(g_PlayersModelInfo[client].type == PlayerModelDefault) {
		return;
	}

	if(g_PlayersModelInfo[client].entity == -1) {
		return;
	}

#if defined GAME_TF2
	if(!TF2_IsPlayerInCondition(client, TFCond_Disguised)) {
		float invis = GetEntDataFloat(client, m_flInvisibilityOffset);
		invis = 1.0 - invis;
		int alpha = RoundToFloor(255 * invis);
		if(alpha < 0) {
			alpha = 0;
		}
		if(alpha > 255) {
			alpha = 255;
		}
		SetEntityRenderColor(g_PlayersModelInfo[client].entity, 255, 255, 255, alpha);
	}
#endif
}

#if defined GAME_TF2
public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if(g_PlayersModelInfo[client].type == PlayerModelCustomModel) {
		if(condition == TFCond_Disguised) {
			g_PlayersModelInfo[client].SetCustomModel("");
			SetEntityRenderColor(client, 255, 255, 255, 255);
		}
	} else if(g_PlayersModelInfo[client].type == PlayerModelBonemerge) {
		if(condition == TFCond_Disguised) {
			SetEntityRenderColor(client, 255, 255, 255, 255);
		}
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(g_PlayersModelInfo[client].type == PlayerModelCustomModel) {
		if(condition == TFCond_Disguised) {
			g_PlayersModelInfo[client].SetCustomModel(g_PlayersModelInfo[client].model);
		}
	} else if(g_PlayersModelInfo[client].type == PlayerModelBonemerge) {
		if(condition == TFCond_Disguised) {
			SetEntityRenderColor(client, 255, 255, 255, 0);
		}
	}
}

void FrameInventory(int client)
{
	g_PlayersModelInfo[client].Apply(client);
}

void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(g_PlayersModelInfo[client].type == PlayerModelBonemerge) {
		g_PlayersModelInfo[client].entity = -1;
		RequestFrame(FrameInventory, client);
	}
}
#endif

void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	g_PlayersModelInfo[client].Apply(client);
}

void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
#if defined GAME_TF2
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER))
#endif
	{
		g_PlayersModelInfo[client].ClearDeath();
	}
}

public void OnClientPutInServer(int client)
{
	g_PlayersModelInfo[client].ClearDisconnect();
	SDKHook(client, SDKHook_PostThink, OnPlayerPostThink);
}

public void OnClientDisconnect(int client)
{
	g_PlayersModelInfo[client].ClearDisconnect();
}