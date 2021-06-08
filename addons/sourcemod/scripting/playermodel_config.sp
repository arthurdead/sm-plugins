#include <sourcemod>
#include <sdkhooks>
#include <clientprefs>
#include <tf2>
#include <tf2_stocks>
#include <animhelpers>
#include <playermodel>

ArrayList arrModelInfos = null;
StringMap mapGroup = null;
StringMap mapInfoIds = null;

#define MODEL_NAME_MAX 64
#define OVERRIDE_MAX 64

#define M_PI 3.14159265358979323846
#define IN_ANYMOVEMENTKEY (IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT)

#define TFClass_Any (view_as<TFClassType>(-1))

enum AnimsetType
{
	animset_tf2,
	animset_hl2,
};

#define PLAYERMODEL_TRANSMIT_BUGGED

#define FLAG_NOWEAPONS (1 << 0)
#define FLAG_NOHATS (1 << 1)
#define FLAG_NODMG (1 << 2)
#if defined PLAYERMODEL_TRANSMIT_BUGGED
#define FLAG_HACKTHIRDPERSON (1 << 3)
#endif

enum struct ConfigModelInfo
{
	char name[MODEL_NAME_MAX];
	char model[PLATFORM_MAX_PATH];
	char anim[PLATFORM_MAX_PATH];
	char override[OVERRIDE_MAX];
	AnimsetType animset;
	TFClassType orig_class;
	TFClassType class;
	int flags;
	PlayerModelType type;
	StringMap sequences;
	StringMap poseparameters;
	int bodygroup;
}

#define ModelInfo ConfigModelInfo

enum struct AnimInfo
{
	int m_hOldGroundEntity;
	bool m_bDidJustJump;
	bool m_bDidJustLand;
	bool m_bWillHardLand;
	bool m_bWasDucked;
	bool m_bCanAnimate;
	int m_nOldButtons;

	void Init()
	{
		this.m_hOldGroundEntity = -1;
		this.m_bCanAnimate = true;
	}

	void Clear()
	{
		this.m_hOldGroundEntity = -1;
		this.m_bDidJustJump = false;
		this.m_bDidJustLand = false;
		this.m_bWillHardLand = false;
		this.m_bWasDucked = false;
		this.m_bCanAnimate = true;
		this.m_nOldButtons = 0;
	}
}

enum struct PlayerInfo
{
	StringMap seqmap;
	StringMap posemap;
	int flags;
	int id;
	AnimsetType animset;

	void Init()
	{
		this.id = -1;
	}

	void Clear()
	{
		this.seqmap = null;
		this.posemap = null;
		this.flags = 0;
		this.id = -1;
		this.animset = animset_tf2;
	}
}

AnimInfo playeranim[33];
PlayerInfo playerinfo[33];

ModelInfo tmpmodelinfo;
char tmpstr1[64];
char tmpstr2[PLATFORM_MAX_PATH];
ArrayList tmpclassarr[10] = {null, ...};

char tmpflagstrs[3][64];
int FlagStrToFlags(const char[] str)
{
	int num = ExplodeString(str, "|", tmpflagstrs, 3, 64);

	int flags = 0;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(tmpflagstrs[i], "nohats")) {
			flags |= FLAG_NOHATS;
		} else if(StrEqual(tmpflagstrs[i], "noweapons")) {
			flags |= FLAG_NOWEAPONS;
		} else if(StrEqual(tmpflagstrs[i], "nodmg")) {
			flags |= FLAG_NODMG;
		}
	}

	return flags;
}

Cookie ClassCookies[10] = {null, ...};

stock void ClassToClassname(TFClassType type, char[] name, int length)
{
	switch(type)
	{
		case TFClass_Unknown: { strcopy(name, length, "none"); }
		case TFClass_Scout: { strcopy(name, length, "scout"); }
		case TFClass_Soldier: { strcopy(name, length, "soldier"); }
		case TFClass_Sniper: { strcopy(name, length, "sniper"); }
		case TFClass_Spy: { strcopy(name, length, "spy"); }
		case TFClass_Medic: { strcopy(name, length, "medic"); }
		case TFClass_DemoMan: { strcopy(name, length, "demoman"); }
		case TFClass_Pyro: { strcopy(name, length, "pyro"); }
		case TFClass_Engineer: { strcopy(name, length, "engineer"); }
		case TFClass_Heavy: { strcopy(name, length, "heavy"); }
	}
}

void FrameInventoryWeapon(int client)
{
	TF2_RemoveAllWeapons(client);
}

void FrameInventoryHats(int client)
{
	TF2_RemoveAllWearables(client);
}

void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(playerinfo[client].flags & FLAG_NOWEAPONS) {
		RequestFrame(FrameInventoryWeapon, client);
	}

	if(playerinfo[client].flags & FLAG_NOHATS) {
		RequestFrame(FrameInventoryHats, client);
	}
}

void player_changeclass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	int class = event.GetInt("class");

	LoadCookies(client, view_as<TFClassType>(class));
}

public void OnPluginStart()
{
	RegAdminCmd("sm_pm", ConCommand_PM, ADMFLAG_GENERIC);

	HookEvent("post_inventory_application", post_inventory_application);

	HookEvent("player_changeclass", player_changeclass);

	mapInfoIds = new StringMap();

	mapGroup = new StringMap();

	arrModelInfos = new ArrayList(sizeof(ModelInfo));
	for(int i = 1; i <= 9; ++i) {
		ClassToClassname(view_as<TFClassType>(i), tmpstr1, sizeof(tmpstr1));
		Format(tmpstr1, sizeof(tmpstr1), "playermodel_%s", tmpstr1);
		ClassCookies[i] = RegClientCookie(tmpstr1, "", CookieAccess_Private);
	}

	BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels.txt");

	if(FileExists(tmpstr2)) {
		KeyValues kvModels = new KeyValues("Playermodels");
		kvModels.ImportFromFile(tmpstr2);

		if(kvModels.GotoFirstSubKey()) {
			do {
				kvModels.GetSectionName(tmpmodelinfo.name, MODEL_NAME_MAX);

				kvModels.GetString("class", tmpstr1, sizeof(tmpstr1), "all");
				if(StrEqual(tmpstr1, "all")) {
					tmpmodelinfo.class = TFClass_Any;
				} else {
					tmpmodelinfo.class = TF2_GetClass(tmpstr1);
					if(tmpmodelinfo.class == TFClass_Unknown) {
						continue;
					}
				}

				kvModels.GetString("animset", tmpstr1, sizeof(tmpstr1), "tf2");
				if(StrEqual(tmpstr1, "hl2")) {
					tmpmodelinfo.animset = animset_hl2;
				} else if(StrEqual(tmpstr1, "tf2")) {
					tmpmodelinfo.animset = animset_tf2;
				} else {
					continue;
				}

				kvModels.GetString("type", tmpstr1, sizeof(tmpstr1), "custom_model");
				if(StrEqual(tmpstr1, "bonemerge")) {
					tmpmodelinfo.type = PlayerModelBonemerge;
				} else if(StrEqual(tmpstr1, "prop")) {
					tmpmodelinfo.type = PlayerModelProp;
				} else if(StrEqual(tmpstr1, "custom_model")) {
					tmpmodelinfo.type = PlayerModelCustomModel;
				} else {
					continue;
				}

				kvModels.GetString("model", tmpmodelinfo.model, PLATFORM_MAX_PATH);
				kvModels.GetString("animation", tmpmodelinfo.anim, PLATFORM_MAX_PATH);
				kvModels.GetString("override", tmpmodelinfo.override, OVERRIDE_MAX);

				kvModels.GetString("flags", tmpstr1, sizeof(tmpstr1), "nodmg");
				tmpmodelinfo.flags = FlagStrToFlags(tmpstr1);

				if(tmpmodelinfo.type == PlayerModelProp ||
					tmpmodelinfo.animset != animset_tf2) {
					tmpmodelinfo.flags |= FLAG_NOHATS|FLAG_NOWEAPONS;
				#if defined PLAYERMODEL_TRANSMIT_BUGGED
					tmpmodelinfo.flags |= FLAG_HACKTHIRDPERSON;
				#endif
				}

				kvModels.GetString("bodygroup", tmpstr1, sizeof(tmpstr1), "0");
				tmpmodelinfo.bodygroup = StringToInt(tmpstr1);

				kvModels.GetString("original_class", tmpstr1, sizeof(tmpstr1), "unknown");
				tmpmodelinfo.orig_class = TF2_GetClass(tmpstr1);

				int idx = arrModelInfos.Length;

				tmpmodelinfo.sequences = new StringMap();
				tmpmodelinfo.poseparameters = new StringMap();

				arrModelInfos.PushArray(tmpmodelinfo, sizeof(tmpmodelinfo));

				mapInfoIds.SetValue(tmpmodelinfo.name, idx);

				kvModels.GetString("group", tmpstr1, sizeof(tmpstr1), "all");
				if(!mapGroup.GetArray(tmpstr1, tmpclassarr, sizeof(tmpclassarr))) {
					for(int i = 1; i <= 9; ++i) {
						tmpclassarr[i] = new ArrayList();
					}
					mapGroup.SetArray(tmpstr1, tmpclassarr, sizeof(tmpclassarr));
				}

				if(tmpmodelinfo.class == TFClass_Any) {
					for(int i = 1; i <= 9; ++i) {
						tmpclassarr[i].Push(idx);
					}
				} else {
					tmpclassarr[tmpmodelinfo.class].Push(idx);
				}
			} while(kvModels.GotoNextKey());

			kvModels.GoBack();
		}

		delete kvModels;
	}

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
		if(AreClientCookiesCached(i)) {
			OnClientCookiesCached(i);
		}
	}
}

void LoadCookies(int client, TFClassType class)
{
	ClassCookies[class].Get(client, tmpstr1, sizeof(tmpstr1));

	if(tmpstr1[0] == '\0' || StrEqual(tmpstr1, "none")) {
		ClearPlayerModel(client);
	} else {
		int idx = -1;

		bool valid = true;

		if(mapInfoIds.GetValue(tmpstr1, idx)) {
			arrModelInfos.GetArray(idx, tmpmodelinfo, sizeof(tmpmodelinfo));

			if(tmpmodelinfo.override[0] != '\0') {
				if(!CheckCommandAccess(client, tmpmodelinfo.override, ADMFLAG_GENERIC)) {
					valid = false;
				}
			}

			if(valid) {
				SetPlayerModel(client, class, tmpmodelinfo, idx);
			}
		}

		if(!valid) {
			ClearPlayerModel(client);

			ClassCookies[class].Set(client, "none");
		}
	}
}

public void OnClientCookiesCached(int client)
{
	if(IsClientInGame(client)) {
		TFClassType class = TF2_GetPlayerClass(client);

		if(class != TFClass_Unknown) {
			LoadCookies(client, class);
		}
	}
}

void CleanString(char[] str)
{
	int len = strlen(str);
	for(int i = 0; i < len; ++i) {
		switch(str[i]) {
			case '\r': { str[i] = ' '; }
			case '\n': { str[i] = ' '; }
			case '\t': { str[i] = ' '; }
		}
	}

	TrimString(str);
}

public void OnMapStart()
{
	for(int i = 0, len = arrModelInfos.Length; i < len; ++i) {
		arrModelInfos.GetArray(i, tmpmodelinfo, sizeof(tmpmodelinfo));

		PrecacheModel(tmpmodelinfo.model);

		if(tmpmodelinfo.anim[0] != '\0') {
			PrecacheModel(tmpmodelinfo.anim);
		}

		Format(tmpstr2, sizeof(tmpstr2), "%s.dep", tmpmodelinfo.model);
		if(FileExists(tmpstr2)) {
			File dlfile = OpenFile(tmpstr2, "r");

			while(!dlfile.EndOfFile()) {
				dlfile.ReadLine(tmpstr2, sizeof(tmpstr2));

				CleanString(tmpstr2);

				AddFileToDownloadsTable(tmpstr2);
			}

			delete dlfile;
		}
	}
}

public void OnClientPutInServer(int client)
{
	playeranim[client].Init();
	playerinfo[client].Init();
	SDKHook(client, SDKHook_PostThink, OnPlayerPostThink);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnPlayerTakeDamageAlive);
}

Action OnPlayerTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(victim != attacker && attacker >= 1 && attacker <= MaxClients) {
		if(playerinfo[attacker].flags & FLAG_NODMG) {
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	playeranim[client].Clear();
	playerinfo[client].Clear();
}

float GetVectorLength2D(float vec[3])
{
	float tmp[3];
	tmp[0] = vec[0];
	tmp[1] = vec[1];
	return GetVectorLength(tmp);
}

int LookupSequence(StringMap map, int entity, const char[] name)
{
	int sequence = -1;
	if(map.GetValue(name, sequence)) {
		return sequence;
	} else {
		sequence = view_as<BaseAnimating>(entity).LookupSequence(name);
		map.SetValue(name, sequence, true);
	}
	return sequence;
}

int LookupPoseParameter(StringMap map, int entity, const char[] name)
{
	int sequence = -1;
	if(map.GetValue(name, sequence)) {
		return sequence;
	} else {
		sequence = view_as<BaseAnimating>(entity).LookupPoseParameter(name);
		map.SetValue(name, sequence, true);
	}
	return sequence;
}

void do_hl2animset(int client, int entity, AnimInfo anim, StringMap seqmap, StringMap posemap)
{
	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vel);

	int buttons = GetEntProp(client, Prop_Data, "m_nButtons");
	bool m_bDucked = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked"));
	bool m_bDucking = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucking")) || (buttons & IN_DUCK);
	int GroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	bool m_bSequenceFinished = view_as<bool>(GetEntProp(entity, Prop_Data, "m_bSequenceFinished"));

	float localorigin[3];
	if(m_bDucked || m_bDucking) {
		localorigin[2] = -30.0;
	} else {
		localorigin[2] = -40.0;
	}
	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", localorigin);

	float eye[3];
	//GetEntPropVector(client, Prop_Data, "m_angAbsRotation", eye);
	GetClientEyeAngles(client, eye);

	float xaxis[3];
	float zaxis[3];
	GetAngleVectors(eye, xaxis, zaxis, NULL_VECTOR);

	float x = GetVectorDotProduct(xaxis, vel);
	float z = GetVectorDotProduct(zaxis, vel);

	float yaw = (ArcTangent2(-z, x) * 180.0 / M_PI);

	int move_yaw = LookupPoseParameter(posemap, entity, "move_yaw");
	view_as<BaseAnimating>(entity).SetPoseParameter(move_yaw, yaw);

	bool moving = (GetVectorLength2D(vel) > 3.0);

	if(GroundEntity != -1 && anim.m_hOldGroundEntity == GroundEntity) {
		if(!anim.m_bDidJustLand) {
			if(anim.m_bCanAnimate) {
				if((buttons & IN_ANYMOVEMENTKEY) && moving) {
					int sequence = LookupSequence(seqmap, entity, "run_all_panicked");
					if(m_bDucked) {
						sequence = LookupSequence(seqmap, entity, "Crouch_walk_all");
					}
					view_as<BaseAnimating>(entity).ResetSequence(sequence);
				} else {
					int sequence = LookupSequence(seqmap, entity, "idle_subtle");
					if(m_bDucked) {
						sequence = LookupSequence(seqmap, entity, "crouchidlehide");
					}
					view_as<BaseAnimating>(entity).ResetSequence(sequence);
				}
			}
		} else {
			if(anim.m_bWillHardLand) {
				anim.m_bCanAnimate = true;
				anim.m_bWillHardLand = false;
				anim.m_bDidJustLand = false;
			} else {
				anim.m_bDidJustLand = false;
			}
		}
	}

	if(GroundEntity == -1 && anim.m_hOldGroundEntity != -1) {
		bool m_bJumping = view_as<bool>(GetEntProp(client, Prop_Send, "m_bJumping"));
		if(m_bJumping) {
			anim.m_bDidJustJump = true;
		}
	}

	if(GroundEntity == -1) {
		if(anim.m_bDidJustJump) {
			int sequence = LookupSequence(seqmap, entity, "jump_holding_jump");
			view_as<BaseAnimating>(entity).ResetSequence(sequence);
			if(m_bSequenceFinished) {
				anim.m_bDidJustJump = false;
			}
		} else {
			int sequence = LookupSequence(seqmap, entity, "jump_holding_glide");
			view_as<BaseAnimating>(entity).ResetSequence(sequence);
		}
	}

	float m_flFallVelocity = GetEntPropFloat(client, Prop_Send, "m_flFallVelocity");
	if(m_flFallVelocity >= 500.0) {
		anim.m_bWillHardLand = true;
	}

	if(GroundEntity != -1 && anim.m_hOldGroundEntity == -1) {
		anim.m_bDidJustLand = true;
	}

	anim.m_hOldGroundEntity = GroundEntity;
	anim.m_nOldButtons = buttons;
	anim.m_bWasDucked = m_bDucked;

	float speed = 0.1;
	if(anim.m_bCanAnimate) {
		speed = GetEntPropFloat(entity, Prop_Data, "m_flGroundSpeed");
		if(speed <= 0.0) {
			/*int sequence = GetEntProp(entity, Prop_Send, "m_nSequence");
			speed = GetSpeedForSequence(sequence);
			*/
		}
		if(m_bDucked) {
			speed *= 3.00000003;
		}
	}
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", speed);

	SetEntProp(entity, Prop_Data, "m_bSequenceLoops", 1);
	view_as<BaseAnimating>(entity).StudioFrameAdvance();
}

void OnPlayerPostThink(int client)
{
	AnimsetType animset = playerinfo[client].animset;

	if(animset == animset_tf2) {
		return;
	}

	int entity = Playermodel_GetEntity(client);
	if(entity == -1) {
		return;
	}

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		SetEntProp(client, Prop_Send, "m_nForceTauntCam", 1);
	}
#endif

	if(animset == animset_hl2) {
		do_hl2animset(client, entity, playeranim[client], playerinfo[client].seqmap, playerinfo[client].posemap);
	}
}

void ClearPlayerModel(int client)
{
	bool hadnoweapons = !!(playerinfo[client].flags & FLAG_NOWEAPONS);

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		//SetEntProp(client, Prop_Send, "m_nForceTauntCam", 0);
	}
#endif

	OnClientDisconnect(client);

	Playermodel_Clear(client);
	Playermodel_Clear(client, true);

	if(hadnoweapons) {
		TF2_RespawnPlayer(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 1);
	}
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			ClearPlayerModel(i);
		}
	}
}

void TF2_RemoveAllWearables(int client)
{
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1)
	{
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner == client) {
			TF2_RemoveWearable(client, entity);
		}
	}
}

public void Playermodel_OnApplied(int client)
{
	if(playerinfo[client].flags & FLAG_NOWEAPONS) {
		TF2_RemoveAllWeapons(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 0);
	}

	if(playerinfo[client].flags & FLAG_NOHATS) {
		TF2_RemoveAllWearables(client);
	}

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		SetEntProp(client, Prop_Send, "m_nForceTauntCam", 1);
	}
#endif
}

void SetPlayerModel(int client, TFClassType class, ModelInfo info, int id)
{
	bool hadnoweapons = !!(playerinfo[client].flags & FLAG_NOWEAPONS);

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		//SetEntProp(client, Prop_Send, "m_nForceTauntCam", 0);
	}
#endif

	playerinfo[client].flags = info.flags;
	playerinfo[client].animset = info.animset;
	playerinfo[client].seqmap = info.sequences;
	playerinfo[client].posemap = info.poseparameters;
	playerinfo[client].id = id;

	if(hadnoweapons) {
		TF2_RespawnPlayer(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 1);
	}

	Playermodel_Clear(client);

	PlayerModelType type = info.type;
	if(type == PlayerModelBonemerge && class == info.orig_class) {
		type = PlayerModelCustomModel;
		PrintToServer("setcustommodel");
	}

	int entity = PlayerModel_SetType(client, info.model, type, true);

	SetEntProp(entity, Prop_Send, "m_nBody", info.bodygroup);

	if(info.anim[0] != '\0') {
		Playermodel_SetAnimation(client, info.anim, true);
	}
}

int MenuHandler_PlayerModel(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));

		int idx = StringToInt(tmpstr1);

		TFClassType class = TF2_GetPlayerClass(param1);
		if(class != TFClass_Unknown) {
			arrModelInfos.GetArray(idx, tmpmodelinfo, sizeof(tmpmodelinfo));

			SetPlayerModel(param1, class, tmpmodelinfo, idx);

			ClassCookies[class].Set(param1, tmpmodelinfo.name);

			menu.GetTitle(tmpstr1, sizeof(tmpstr1));

			if(mapGroup.GetArray(tmpstr1, tmpclassarr, sizeof(tmpclassarr))) {
				DisplayModelMenu(tmpstr1, tmpclassarr[class], class, param1, menu.Selection);
			}
		}
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayGroupMenu(param1);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

int MenuHandler_ModelGroup(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		if(param2 == 0) {
			ClearPlayerModel(param1);

			TFClassType class = TF2_GetPlayerClass(param1);
			if(class != TFClass_Unknown) {
				ClassCookies[class].Set(param1, "none");
			}

			DisplayGroupMenu(param1);
		} else {
			menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));

			if(mapGroup.GetArray(tmpstr1, tmpclassarr, sizeof(tmpclassarr))) {
				TFClassType class = TF2_GetPlayerClass(param1);
				if(class != TFClass_Unknown) {
					DisplayModelMenu(tmpstr1, tmpclassarr[class], class, param1);
				}
			} else {
				DisplayGroupMenu(param1);
			}
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DisplayModelMenu(const char[] group, ArrayList arr, TFClassType class, int client, int item = -1)
{
	Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_PlayerModel, MENU_ACTIONS_DEFAULT);
	menu.SetTitle(group);

	int drawstyle = ITEMDRAW_DEFAULT;
	if(playerinfo[client].id == -1) {
		drawstyle = ITEMDRAW_DISABLED;
	}

	menu.ExitBackButton = true;

	GetModelForClass(class, tmpstr2, sizeof(tmpstr2));

	for(int i, len = arr.Length; i < len; ++i) {
		int idx = arr.Get(i);

		arrModelInfos.GetArray(idx, tmpmodelinfo, sizeof(tmpmodelinfo));

		if(tmpmodelinfo.override[0] != '\0') {
			if(!CheckCommandAccess(client, tmpmodelinfo.override, ADMFLAG_GENERIC)) {
				continue;
			}
		}

		if(tmpmodelinfo.orig_class == class) {
			if(StrEqual(tmpstr2, tmpmodelinfo.model)) {
				continue;
			}
		}

		IntToString(idx, tmpstr1, sizeof(tmpstr1));

		drawstyle = ITEMDRAW_DEFAULT;
		if(playerinfo[client].id == idx) {
			drawstyle = ITEMDRAW_DISABLED;
		}

		menu.AddItem(tmpstr1, tmpmodelinfo.name, drawstyle);
	}

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

void DisplayGroupMenu(int client)
{
	TFClassType class = TF2_GetPlayerClass(client);
	if(class == TFClass_Unknown) {
		return;
	}

	Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_ModelGroup, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Playermodel");

	menu.AddItem("-1", "none");

	StringMapSnapshot snapshot = mapGroup.Snapshot();

	for(int i = 0, len = snapshot.Length; i < len; ++i) {
		snapshot.GetKey(i, tmpstr1, sizeof(tmpstr1));

		menu.AddItem(tmpstr1, tmpstr1);
	}

	delete snapshot;

	menu.Display(client, MENU_TIME_FOREVER);
}

Action ConCommand_PM(int client, int args)
{
	DisplayGroupMenu(client);

	return Plugin_Handled;
}