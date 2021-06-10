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

	void __InternalDeleteEntity(bool prop)
	{
		int entity = EntRefToEntIndex(this.entity);

		if(prop) {
			if(IsValidEntity(entity)) {
			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					TF2_RemoveWearable(this.owner, entity);
				} else
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
		this.body_default = -1;
	}

	void ClearDeath()
	{
		this.DeleteEntity();

		this.link = INVALID_ENT_REFERENCE;
		this.entity = INVALID_ENT_REFERENCE;
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
	}

	void __InternalClearAllVars()
	{
		this.ClearDefault();
		this.ClearDeath();
	}

	void ClearDisconnect()
	{
		this.__InternalClearAllVars();
		this.owner = INVALID_ENT_REFERENCE;
	}

	void Init(int client)
	{
		this.__InternalClearAllVars();
		this.owner = client;
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

	void SetBody()
	{
		this.__InternalSetBody(this.IsProp());
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
			#if defined GAME_TF2
				if(this.type == PlayerModelBonemerge) {
					SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(this.owner));
				} else
			#endif
				{
					SetEntProp(entity, Prop_Send, "m_nSkin", 0);
				}
			} else {
				this.SetCustomSkin(-1);
			}
		}
	}

	void __InternalSetBody(bool prop)
	{
		this.CheckForDefault();

		int entity = EntRefToEntIndex(this.entity);

		if(this.body != -1) {
			SetEntProp(entity, Prop_Send, "m_nBody", this.body);
		} else {
			SetEntProp(entity, Prop_Send, "m_nBody", 0);
		}
	}

	void DeleteLink()
	{
	#if defined GAME_TF2
		int entity = EntRefToEntIndex(this.link);
		if(entity != this.owner && IsValidEntity(entity)) {
			RemoveEntity(entity);
		}
	#endif
		this.link = INVALID_ENT_REFERENCE;
	}

	int CreateLink()
	{
	#if defined GAME_TF2
		if(this.type == PlayerModelProp) {
			this.DeleteLink();

			int entity = CreateEntityByName("prop_dynamic_override");

			char tmp[PLATFORM_MAX_PATH];
			TFClassType class = TF2_GetPlayerClass(this.owner);
			GetModelForClass(class, tmp, sizeof(tmp));

			DispatchKeyValue(entity, "model", tmp);
			DispatchSpawn(entity);

			SetEntityModel(entity, tmp);

			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", this.owner);

			int flags = EF_NOSHADOW|EF_NORECEIVESHADOW|EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES;
			SetEntProp(entity, Prop_Send, "m_fEffects", flags);

			this.link = EntIndexToEntRef(entity);
		} else
	#endif
		{
			this.link = EntIndexToEntRef(this.owner);
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
			GetEntPropString(client, Prop_Data, "m_ModelName", currmodel, sizeof(currmodel));
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
				this.entity = EntIndexToEntRef(this.owner);

				if(this.type == PlayerModelCustomModel) {
					this.SetCustomModel(this.model);
				}

				SetEntityRenderMode(client, RENDER_NORMAL);
			}
			case PlayerModelProp, PlayerModelBonemerge:
			{
				int entity = EntRefToEntIndex(this.entity);

				if((entity != client) && IsValidEntity(entity)) {
					SetEntityModel(entity, this.model);
				} else {
				#if defined GAME_TF2
					if(this.type == PlayerModelBonemerge) {
						entity = TF2Items_GiveNamedItem(client, hDummyItemView);
					} else
				#endif
					{
					#if defined GAME_L4D2
						entity = CreateEntityByName("commentary_dummy");
					#else
						entity = CreateEntityByName("funCBaseFlex");
					#endif
					}

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
					if(this.type == PlayerModelBonemerge) {
						effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL;
					}
					effects |= EF_PARENT_ANIMATES;
					effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
					SetEntProp(entity, Prop_Send, "m_fEffects", effects);

					this.CreateLink();

					int link = EntRefToEntIndex(this.link);

					SetVariantString("!activator");
					AcceptEntityInput(entity, "SetParent", link);

					SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
					SetEntityRenderColor(entity, 255, 255, 255, 255);

				#if defined GAME_TF2
					if(this.type != PlayerModelBonemerge) {
						this.SetCustomModel(this.model);
					}
				#endif

				#if defined GAME_TF2
					if(this.type == PlayerModelBonemerge) {
						SDKCall(hEquipWearable, client, entity);
					} else
				#endif
					{
						SetEntProp(entity, Prop_Send, "m_bClientSideAnimation", 0);
						SetEntProp(entity, Prop_Send, "m_bClientSideFrameReset", 0);
					}

				#if defined GAME_TF2
					if(this.type == PlayerModelBonemerge) {
						SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
					}
				#endif

					SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);

					if(this.type == PlayerModelProp) {
						//SDKHook(entity, SDKHook_SetTransmit, OnPropTransmit);
					}

					SetEntityModel(entity, this.model);

					this.entity = EntIndexToEntRef(entity);
				}
			}
		}

		this.__InternalSetSkin(prop);
		this.__InternalSetBody(prop);

		Call_StartForward(OnApplied);
		Call_PushCell(client);
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
	CreateNative("Playermodel_GetModel", Native_GetModel);
	CreateNative("Playermodel_GetAnimation", Native_GetAnimation);
	CreateNative("Playermodel_GetEntity", Native_GetEntity);
	CreateNative("Playermodel_GetLink", Native_GetLink);
	CreateNative("Playermodel_SetAnimation", Native_SetAnimation);
	CreateNative("Playermodel_GetType", Native_GetType);
	CreateNative("PlayerModel_SetType", Native_SetType);
	CreateNative("Playermodel_GetSkin", Native_GetSkin);
	CreateNative("Playermodel_SetSkin", Native_SetSkin);
	CreateNative("Playermodel_GetBodygroup", Native_GetBodygroup);
	CreateNative("Playermodel_SetBodygroup", Native_SetBodygroup);
	OnApplied = new GlobalForward("Playermodel_OnApplied", ET_Ignore, Param_Cell);
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

	bool def = GetNativeCell(4);

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

#if defined GAME_TF2
int m_flInvisibilityOffset = -1;
int iLastSpyAlpha[33] = {255, ...};
#endif

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

void OnPlayerPostThink(int client)
{
	if(g_PlayersModelInfo[client].type == PlayerModelProp ||
		g_PlayersModelInfo[client].type == PlayerModelBonemerge) {

		int entity = EntRefToEntIndex(g_PlayersModelInfo[client].entity);
		if(!IsValidEntity(entity)) {
			return;
		}

		int r = 255;
		int g = 255;
		int b = 255;
		int a = 255;
		GetEntityRenderColor(client, r, g, b, a);

	#if defined GAME_TF2
		int mod = CalcSpyAlpha(client);
		if(mod != -1 && mod < a) {
			a = mod;
		}
	#endif

		SetEntityRenderMode(client, RENDER_NONE);
		SetEntityRenderColor(entity, r, g, b, a);
	}
#if defined GAME_TF2
	else if(g_PlayersModelInfo[client].type == PlayerModelCustomModel) {
		int r = 255;
		int g = 255;
		int b = 255;
		int a = 255;
		GetEntityRenderColor(client, r, g, b, a);

		int mod = CalcSpyAlpha(client);
		if(mod != -1) {
			int limit = a;

			if(iLastSpyAlpha[client] != -1) {
				limit = iLastSpyAlpha[client];
			}
			
			if(mod < limit) {
				a = mod;
			}
		} else {
			iLastSpyAlpha[client] = -1;
		}

		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, r, g, b, a);
	}
#endif
}

#if defined GAME_TF2
public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if(condition == TFCond_Cloaked) {
		if(g_PlayersModelInfo[client].type != PlayerModelDefault) {
			iLastSpyAlpha[client] = GetEntityAlpha(client)+1;
		}
	}

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
	g_PlayersModelInfo[client].Apply(client);
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
	g_PlayersModelInfo[client].Init(client);
	SDKHook(client, SDKHook_PostThink, OnPlayerPostThink);
}

public void OnClientDisconnect(int client)
{
	g_PlayersModelInfo[client].ClearDisconnect();
#if defined GAME_TF2
	iLastSpyAlpha[client] = -1;
#endif
}