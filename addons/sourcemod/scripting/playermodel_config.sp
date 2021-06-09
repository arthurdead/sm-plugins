#include <sourcemod>
#include <sdkhooks>
#include <clientprefs>
#include <tf2>
#include <tf2_stocks>
#include <animhelpers>
#include <playermodel>
#include <playermodel_config>

ArrayList arrModelInfos = null;
StringMap mapGroup = null;
StringMap mapInfoIds = null;

#define MODEL_NAME_MAX 64
#define OVERRIDE_MAX 64
#define STEAMID_MAX 64

#define M_PI 3.14159265358979323846
#define IN_ANYMOVEMENTKEY (IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT)

#define TFClass_Any (view_as<TFClassType>(-1))

//TODO!!!! make both of these kv files
enum AnimsetType
{
	animset_tf2,
	animset_hl2,
};

enum GestureType
{
	gestures_none,
	gestures_hl2rebel_male,
	gestures_hl2rebel_female,
	gestures_hl2gman,
	gestures_hl2breen,
};

#define PLAYERMODEL_TRANSMIT_BUGGED

#define FLAG_NOWEAPONS (1 << 0)
#define FLAG_NODMG (1 << 2)
#define FLAG_ALWAYSBONEMERGE (1 << 4)
#if defined PLAYERMODEL_TRANSMIT_BUGGED
#define FLAG_HACKTHIRDPERSON (1 << 5)
#endif

enum struct ConfigModelInfo
{
	char name[MODEL_NAME_MAX];
	char model[PLATFORM_MAX_PATH];
	char anim[PLATFORM_MAX_PATH];
	char override[OVERRIDE_MAX];
	char steamid[STEAMID_MAX];
	AnimsetType animset;
	GestureType gestures;
	TFClassType orig_class;
	TFClassType class;
	int flags;
	PlayerModelType type;
	StringMap sequences;
	StringMap poseparameters;
	int bodygroup;
	int skin;
}

#define ModelInfo ConfigModelInfo

enum struct GroupInfo
{
	char override[OVERRIDE_MAX];
	char steamid[STEAMID_MAX];
	ArrayList classarr[10];
}

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
	GestureType gestures;

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
		this.gestures = gestures_none;
	}
}

AnimInfo playeranim[33];
PlayerInfo playerinfo[33];

ModelInfo tmpmodelinfo;
GroupInfo tmpgroupinfo;
char tmpstr1[64];
char tmpstr2[PLATFORM_MAX_PATH];

char tmpflagstrs[3][64];
int FlagStrToFlags(const char[] str)
{
	int num = ExplodeString(str, "|", tmpflagstrs, 3, 64);

	int flags = 0;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(tmpflagstrs[i], "hidehats")) {
			flags |= playermodel_hidehats;
		} else if(StrEqual(tmpflagstrs[i], "noweapons")) {
			flags |= FLAG_NOWEAPONS;
		} else if(StrEqual(tmpflagstrs[i], "nodmg")) {
			flags |= FLAG_NODMG;
		} else if(StrEqual(tmpflagstrs[i], "hideweapons")) {
			flags |= playermodel_hideweapons;
		} else if(StrEqual(tmpflagstrs[i], "alwaysmerge")) {
			flags |= FLAG_ALWAYSBONEMERGE;
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

void FrameInventoryRemoveWeapon(int client)
{
	TF2_RemoveAllWeapons(client);
}

void FrameInventoryHideWeapon(int client)
{
	TF2_HideAllWeapons(client, true);
}

void FrameInventoryHats(int client)
{
	TF2_HideAllWearables(client, true);
}

void OnSpawnEndTouch(int entity, int other)
{
	if(other < 1 || other > MaxClients) {
		return;
	}

	if(playerinfo[other].flags & playermodel_hideweapons) {
		RequestFrame(FrameInventoryHideWeapon, other);
	}

	if(playerinfo[other].flags & playermodel_hidehats) {
		RequestFrame(FrameInventoryHats, other);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "func_respawnroom"))
	{
		SDKHook(entity, SDKHook_EndTouch, OnSpawnEndTouch);
	}
}

void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(playerinfo[client].flags & FLAG_NOWEAPONS) {
		RequestFrame(FrameInventoryRemoveWeapon, client);
	} else if(playerinfo[client].flags & playermodel_hideweapons) {
		RequestFrame(FrameInventoryHideWeapon, client);
	}

	if(playerinfo[client].flags & playermodel_hidehats) {
		RequestFrame(FrameInventoryHats, client);
	}
}

void player_changeclass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	int class = event.GetInt("class");

	LoadCookies(client, view_as<TFClassType>(class));
}

void GetGroupString(KeyValues kvGroups, const char[] group, const char[] name, char[] str, int len, const char[] def = "")
{
	if(kvGroups.JumpToKey(group)) {
		kvGroups.GetString(name, str, len, def);
		kvGroups.GoBack();
	} else {
		strcopy(str, len, def);
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("playermodel_config");
	CreateNative("Playermodel_GetFlags", Native_GetFlags);
	return APLRes_Success;
}

int Native_GetFlags(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return playerinfo[client].flags;
}

public void OnPluginStart()
{
	RegAdminCmd("sm_pm", ConCommand_PM, ADMFLAG_GENERIC);
	RegAdminCmd("sm_gt", ConCommand_GT, ADMFLAG_GENERIC);

	HookEvent("post_inventory_application", post_inventory_application);

	HookEvent("player_changeclass", player_changeclass);

	mapInfoIds = new StringMap();

	mapGroup = new StringMap();

	arrModelInfos = new ArrayList(sizeof(ModelInfo));
	char tmpclass[64];
	for(int i = 1; i <= 9; ++i) {
		ClassToClassname(view_as<TFClassType>(i), tmpclass, sizeof(tmpclass));
		Format(tmpstr1, sizeof(tmpstr1), "playermodel_v3_%s", tmpclass);
		ClassCookies[i] = RegClientCookie(tmpstr1, "", CookieAccess_Private);
	}

	BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/models.txt");

	if(FileExists(tmpstr2)) {
		KeyValues kvModels = new KeyValues("Playermodels");
		kvModels.ImportFromFile(tmpstr2);

		BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/groups.txt");
		KeyValues kvGroups = new KeyValues("Playermodels_groups");
		if(FileExists(tmpstr2)) {
			kvGroups.ImportFromFile(tmpstr2);
		}

		if(kvGroups.GotoFirstSubKey()) {
			do {
				kvGroups.GetSectionName(tmpstr1, sizeof(tmpstr1));

				kvGroups.GetString("override", tmpgroupinfo.override, OVERRIDE_MAX);
				kvGroups.GetString("steamid", tmpgroupinfo.steamid, STEAMID_MAX);

				for(int i = 1; i <= 9; ++i) {
					tmpgroupinfo.classarr[i] = new ArrayList();
				}

				mapGroup.SetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo));
			} while(kvGroups.GotoNextKey());

			kvGroups.GoBack();
		}

		if(kvModels.GotoFirstSubKey()) {
			char tmpgroup[64];

			do {
				kvModels.GetSectionName(tmpmodelinfo.name, MODEL_NAME_MAX);

				kvModels.GetString("group", tmpgroup, sizeof(tmpgroup), "all");

				kvModels.GetString("class", tmpstr1, sizeof(tmpstr1), "__unset");
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "class", tmpstr1, sizeof(tmpstr1), "all");
				}

				if(StrEqual(tmpstr1, "all")) {
					tmpmodelinfo.class = TFClass_Any;
				} else {
					tmpmodelinfo.class = TF2_GetClass(tmpstr1);
					if(tmpmodelinfo.class == TFClass_Unknown) {
						PrintToServer("model %s has unknown class: %s", tmpmodelinfo.name, tmpstr1);
						continue;
					}
				}

				kvModels.GetString("animset", tmpstr1, sizeof(tmpstr1), "__unset");
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "animset", tmpstr1, sizeof(tmpstr1), "tf2");
				}

				if(StrEqual(tmpstr1, "hl2")) {
					tmpmodelinfo.animset = animset_hl2;
				} else if(StrEqual(tmpstr1, "tf2")) {
					tmpmodelinfo.animset = animset_tf2;
				} else {
					PrintToServer("model %s has unknown animset: %s", tmpmodelinfo.name, tmpstr1);
					continue;
				}

				kvModels.GetString("gestures", tmpstr1, sizeof(tmpstr1), "__unset");
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "gestures", tmpstr1, sizeof(tmpstr1), "none");
				}

				if(StrEqual(tmpstr1, "hl2_gman")) {
					tmpmodelinfo.gestures = gestures_hl2gman;
				} else if(StrEqual(tmpstr1, "hl2_rebel_male")) {
					tmpmodelinfo.gestures = gestures_hl2rebel_male;
				} else if(StrEqual(tmpstr1, "hl2_rebel_female")) {
					tmpmodelinfo.gestures = gestures_hl2rebel_female;
				} else if(StrEqual(tmpstr1, "hl2_breen")) {
					tmpmodelinfo.gestures = gestures_hl2breen;
				} else if(StrEqual(tmpstr1, "none")) {
					tmpmodelinfo.gestures = gestures_none;
				} else {
					PrintToServer("model %s has unknown gestures: %s", tmpmodelinfo.name, tmpstr1);
					continue;
				}

				kvModels.GetString("type", tmpstr1, sizeof(tmpstr1), "__unset");
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "type", tmpstr1, sizeof(tmpstr1), "custom_model");
				}

				if(StrEqual(tmpstr1, "bonemerge")) {
					tmpmodelinfo.type = PlayerModelBonemerge;
				} else if(StrEqual(tmpstr1, "prop")) {
					tmpmodelinfo.type = PlayerModelProp;
				} else if(StrEqual(tmpstr1, "custom_model")) {
					tmpmodelinfo.type = PlayerModelCustomModel;
				} else {
					PrintToServer("model %s has unknown type: %s", tmpmodelinfo.name, tmpstr1);
					continue;
				}

				kvModels.GetString("model", tmpmodelinfo.model, PLATFORM_MAX_PATH);
				kvModels.GetString("animation", tmpmodelinfo.anim, PLATFORM_MAX_PATH);

				kvModels.GetString("override", tmpstr1, sizeof(tmpstr1));
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "override", tmpstr1, sizeof(tmpstr1));
				}

				strcopy(tmpmodelinfo.override, OVERRIDE_MAX, tmpstr1);

				kvModels.GetString("steamid", tmpstr1, sizeof(tmpstr1));
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "steamid", tmpstr1, sizeof(tmpstr1));
				}

				strcopy(tmpmodelinfo.steamid, STEAMID_MAX, tmpstr1);

				kvModels.GetString("flags", tmpstr1, sizeof(tmpstr1), "__unset");
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "flags", tmpstr1, sizeof(tmpstr1), "nodmg");
				}

				tmpmodelinfo.flags = FlagStrToFlags(tmpstr1);

				if(tmpmodelinfo.animset != animset_tf2) {
					tmpmodelinfo.type = PlayerModelProp;
				}

				if(tmpmodelinfo.type == PlayerModelProp ||
					tmpmodelinfo.animset != animset_tf2) {
					tmpmodelinfo.flags |= playermodel_hidehats|FLAG_NOWEAPONS;
				}

			#if defined PLAYERMODEL_TRANSMIT_BUGGED
				if(tmpmodelinfo.type == PlayerModelProp) {
					tmpmodelinfo.flags |= FLAG_HACKTHIRDPERSON;
				}
			#endif

				kvModels.GetString("bodygroup", tmpstr1, sizeof(tmpstr1), "__unset");
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "bodygroup", tmpstr1, sizeof(tmpstr1), "0");
				}

				tmpmodelinfo.bodygroup = StringToInt(tmpstr1);

				kvModels.GetString("skin", tmpstr1, sizeof(tmpstr1), "__unset");
				if(StrEqual(tmpstr1, "__unset")) {
					GetGroupString(kvGroups, tmpgroup, "skin", tmpstr1, sizeof(tmpstr1), "-1");
				}

				tmpmodelinfo.skin = StringToInt(tmpstr1);

				kvModels.GetString("original_class", tmpstr1, sizeof(tmpstr1), "unknown");
				tmpmodelinfo.orig_class = TF2_GetClass(tmpstr1);

				int idx = arrModelInfos.Length;

				tmpmodelinfo.sequences = new StringMap();
				tmpmodelinfo.poseparameters = new StringMap();

				arrModelInfos.PushArray(tmpmodelinfo, sizeof(tmpmodelinfo));

				mapInfoIds.SetValue(tmpmodelinfo.name, idx);

				if(!mapGroup.GetArray(tmpgroup, tmpgroupinfo, sizeof(tmpgroupinfo))) {
					for(int i = 1; i <= 9; ++i) {
						tmpgroupinfo.classarr[i] = new ArrayList();
					}
					mapGroup.SetArray(tmpgroup, tmpgroupinfo, sizeof(tmpgroupinfo));
				}

				if(tmpmodelinfo.class == TFClass_Any) {
					for(int i = 1; i <= 9; ++i) {
						tmpgroupinfo.classarr[i].Push(idx);
					}
				} else {
					tmpgroupinfo.classarr[tmpmodelinfo.class].Push(idx);
				}
			} while(kvModels.GotoNextKey());

			kvModels.GoBack();
		}

		delete kvModels;
		delete kvGroups;
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

			char tmpauth[STEAMID_MAX];
			if(tmpmodelinfo.steamid[0] != '\0') {
				if(GetClientAuthId(client, AuthId_SteamID64, tmpauth, sizeof(tmpauth))) {
					if(!StrEqual(tmpauth, tmpmodelinfo.steamid)) {
						valid = false;
					}
				} else {
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
					int sequence = LookupSequence(seqmap, entity, "run_all");
					if(buttons & IN_SPEED) {
						sequence = LookupSequence(seqmap, entity, "walk_all_Moderate");
					}
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

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			ClearPlayerModel(i);
		}
	}
}

void TF2_HideWeaponSlot(int client, int slot, bool hide)
{
	int entity = GetPlayerWeaponSlot(client, slot);
	if(entity != -1) {
		SetEntityRenderMode(entity, hide ? RENDER_TRANSCOLOR : RENDER_NORMAL);
		SetEntityRenderColor(entity, 255, 255, 255, hide ? 0 : 255);
	}
}

void TF2_HideAllWeapons(int client, bool hide)
{
	for(int i = 0; i <= 5; i++)
	{
		TF2_HideWeaponSlot(client, i, hide);
	}
}

void TF2_HideAllWearables(int client, bool hide)
{
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1)
	{
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner == client) {
			SetEntityRenderMode(entity, hide ? RENDER_TRANSCOLOR : RENDER_NORMAL);
			SetEntityRenderColor(entity, 255, 255, 255, hide ? 0 : 255);
		}
	}
}

public void Playermodel_OnApplied(int client)
{
	if(playerinfo[client].flags & FLAG_NOWEAPONS) {
		TF2_RemoveAllWeapons(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 0);
	} else if(playerinfo[client].flags & playermodel_hideweapons) {
		TF2_HideAllWeapons(client, true);
	}

	if(playerinfo[client].flags & playermodel_hidehats) {
		TF2_HideAllWearables(client, true);
	}

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		SetEntProp(client, Prop_Send, "m_nForceTauntCam", 1);
	}
#endif
}

void ClearPlayerModel(int client)
{
	bool hadnoweapons = !!(playerinfo[client].flags & FLAG_NOWEAPONS);
	bool hadhideweapons = !!(playerinfo[client].flags & playermodel_hideweapons);
	bool hadhidehats = !!(playerinfo[client].flags & playermodel_hidehats);

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
	} else if(hadhideweapons) {
		TF2_HideAllWeapons(client, false);
	}

	if(hadhidehats) {
		TF2_HideAllWearables(client, false);
	}
}

void SetPlayerModel(int client, TFClassType class, ModelInfo info, int id)
{
	bool hadnoweapons = !!(playerinfo[client].flags & FLAG_NOWEAPONS);
	bool hadhideweapons = !!(playerinfo[client].flags & playermodel_hideweapons);
	bool hadhidehats = !!(playerinfo[client].flags & playermodel_hidehats);

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		//SetEntProp(client, Prop_Send, "m_nForceTauntCam", 0);
	}
#endif

	playerinfo[client].flags = info.flags;
	playerinfo[client].animset = info.animset;
	playerinfo[client].gestures = info.gestures;
	playerinfo[client].seqmap = info.sequences;
	playerinfo[client].posemap = info.poseparameters;
	playerinfo[client].id = id;

	if(!(info.flags & FLAG_NOWEAPONS) && hadnoweapons) {
		TF2_RespawnPlayer(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 1);
	} else if(!(info.flags & playermodel_hideweapons) && hadhideweapons) {
		TF2_HideAllWeapons(client, false);
	}

	if(!(info.flags & playermodel_hidehats) && hadhidehats) {
		TF2_HideAllWearables(client, false);
	}

	Playermodel_Clear(client);

	PlayerModelType type = info.type;
	if(!(info.flags & FLAG_ALWAYSBONEMERGE)) {
		if(type == PlayerModelBonemerge && class == info.orig_class) {
			type = PlayerModelCustomModel;
		}
	}

	int entity = PlayerModel_SetType(client, info.model, type, true);

	Playermodel_SetSkin(client, info.skin, true);
	Playermodel_SetSkin(client, info.skin);

	Playermodel_SetBodygroup(client, info.bodygroup, true);
	Playermodel_SetBodygroup(client, info.bodygroup);

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

			if(mapGroup.GetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo))) {
				DisplayModelMenu(tmpstr1, tmpgroupinfo.classarr[class], class, param1, menu.Selection);
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

			if(mapGroup.GetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo))) {
				TFClassType class = TF2_GetPlayerClass(param1);
				if(class != TFClass_Unknown) {
					DisplayModelMenu(tmpstr1, tmpgroupinfo.classarr[class], class, param1);
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

	char tmpauth[STEAMID_MAX];

	for(int i, len = arr.Length; i < len; ++i) {
		int idx = arr.Get(i);

		arrModelInfos.GetArray(idx, tmpmodelinfo, sizeof(tmpmodelinfo));

		if(tmpmodelinfo.override[0] != '\0') {
			if(!CheckCommandAccess(client, tmpmodelinfo.override, ADMFLAG_GENERIC)) {
				continue;
			}
		}

		if(tmpmodelinfo.steamid[0] != '\0') {
			if(GetClientAuthId(client, AuthId_SteamID64, tmpauth, sizeof(tmpauth))) {
				if(!StrEqual(tmpauth, tmpmodelinfo.steamid)) {
					continue;
				}
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

void DisplayGroupMenu(int client, int item = -1)
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

	char tmpauth[STEAMID_MAX];

	for(int i = 0, len = snapshot.Length; i < len; ++i) {
		snapshot.GetKey(i, tmpstr1, sizeof(tmpstr1));

		mapGroup.GetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo));

		if(tmpgroupinfo.override[0] != '\0') {
			if(!CheckCommandAccess(client, tmpgroupinfo.override, ADMFLAG_GENERIC)) {
				continue;
			}
		}

		if(tmpgroupinfo.steamid[0] != '\0') {
			if(GetClientAuthId(client, AuthId_SteamID64, tmpauth, sizeof(tmpauth))) {
				if(!StrEqual(tmpauth, tmpgroupinfo.steamid)) {
					continue;
				}
			}
		}

		menu.AddItem(tmpstr1, tmpstr1);
	}

	delete snapshot;

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

int MenuHandler_ModelGestures(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		int entity = Playermodel_GetEntity(param1);

		menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));
		
		if(entity != -1 && IsValidEntity(entity)) {
			int sequence = LookupSequence(playerinfo[param1].seqmap, entity, tmpstr1);
			if(sequence != -1) {
				view_as<BaseAnimatingOverlay>(entity).AddGestureSequence1(sequence);
			}
		}

		DiplayGesturesMenu(param1, menu.Selection);
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DiplayGesturesMenu(int client, int item = -1)
{
	if(playerinfo[client].gestures == gestures_none) {
		return;
	}

	Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_ModelGestures, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Gestures");

	switch(playerinfo[client].gestures) {
		case gestures_hl2rebel_male: {
			menu.AddItem("g_clap", "Clap");
			menu.AddItem("g_wave", "Wave");
			menu.AddItem("g_salute", "Salute");
			menu.AddItem("g_shrug", "Shrug");
			menu.AddItem("g_thumbsup", "Thumbs Up");
			menu.AddItem("g_antman_stayback", "Stay back");
			menu.AddItem("g_frustrated_point", "Point");
			menu.AddItem("g_armsup", "Arms Up");
		}
		case gestures_hl2rebel_female: {
			menu.AddItem("g_wave", "Wave");
			menu.AddItem("G_puncuate", "Puncuate");
			menu.AddItem("g_arlene_postidle_headup", "Head Up");
			menu.AddItem("g_arrest_clench", "Clench");
			menu.AddItem("g_Clutch_Chainlink_HandtoChest", "Hand To Chest");
			menu.AddItem("g_display_left", "Display Left");
			menu.AddItem("g_left_openhand", "Open Hand Left");
			menu.AddItem("g_right_openhand", "Open Right Left");
			menu.AddItem("holdhands", "Hold Hands");
			menu.AddItem("urgenthandsweep", "Sweep Lower");
			menu.AddItem("urgenthandsweepcrouch", "Sweep Upper");
		}
		case gestures_hl2gman: {
			menu.AddItem("G_tiefidget", "Tie Fidget");
			menu.AddItem("G_lefthand_punct", "Puncuate");
		}
		case gestures_hl2breen: {
			menu.AddItem("B_g_waveoff", "Wave Off");
			menu.AddItem("B_g_wave", "Wave");
			menu.AddItem("B_g_upshrug", "Up Shrug");
			menu.AddItem("B_g_shrug", "Shrug");
			menu.AddItem("B_g_pray", "Pray");
			menu.AddItem("B_g_palmsout", "Palms Out");
			menu.AddItem("B_g_palmsup", "Palms Up");
			menu.AddItem("B_g_chopout", "Chop Out");
			menu.AddItem("B_g_rthd_chopdwn", "Chop Down");
			menu.AddItem("B_g_rthd_tohead", "To Head");
			menu.AddItem("B_g_sweepout", "Sweep Out");
			menu.AddItem("B_gesture01", "Hands Out");
			menu.AddItem("B_gesture02", "Palm Point");
		}
	}

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

Action ConCommand_GT(int client, int args)
{
	//DiplayGesturesMenu(client);

	return Plugin_Handled;
}

Action ConCommand_PM(int client, int args)
{
	DisplayGroupMenu(client);

	return Plugin_Handled;
}