#include <sourcemod>
#include <dhooks>

static ArrayList maps;
static int map_idx;

static int CNavMesh_m_generationState_offset = -1;
static int CNavMesh_m_generationMode_offset = -1;
static int CNavMesh_m_isAnalyzed_offset = -1;

#define SAVE_NAV_MESH 9

#define GENERATE_INCREMENTAL 2
#define GENERATE_ANALYSIS_ONLY 4
#define GENERATE_FULL 1

public void OnPluginStart()
{
	GameData gamedata = new GameData("ensurenav");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

	DynamicDetour tmp = DynamicDetour.FromConf(gamedata, "CNavMesh::UpdateGeneration");
	if(!tmp || !tmp.Enable(Hook_Pre, CNavMesh_UpdateGeneration_detour)) {
		SetFailState("Failed to enable pre detour for CNavMesh::UpdateGeneration");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, CNavMesh_UpdateGeneration_detour_post)) {
		SetFailState("Failed to enable pre detour for CNavMesh::UpdateGeneration");
		delete gamedata;
		return;
	}

	CNavMesh_m_generationState_offset = gamedata.GetOffset("CNavMesh::m_generationState");
	CNavMesh_m_generationMode_offset = gamedata.GetOffset("CNavMesh::m_generationMode");
	CNavMesh_m_isAnalyzed_offset = gamedata.GetOffset("CNavMesh::m_isAnalyzed");

	delete gamedata;

	RegAdminCmd("sm_ensurenav", sm_ensurenav, ADMFLAG_ROOT);
}

static MRESReturn CNavMesh_UpdateGeneration_detour(Address pThis, DHookReturn hReturn)
{
	int m_generationState = LoadFromAddress(pThis + view_as<Address>(CNavMesh_m_generationState_offset), NumberType_Int32);
	if(m_generationState == SAVE_NAV_MESH) {
		int m_generationMode = LoadFromAddress(pThis + view_as<Address>(CNavMesh_m_generationMode_offset), NumberType_Int32);
		if(m_generationMode == GENERATE_ANALYSIS_ONLY || m_generationMode == GENERATE_FULL) {
			StoreToAddress(pThis + view_as<Address>(CNavMesh_m_isAnalyzed_offset), 1, NumberType_Int8);
		}

		StoreToAddress(pThis + view_as<Address>(CNavMesh_m_generationMode_offset), GENERATE_INCREMENTAL, NumberType_Int32);
	}
	return MRES_Ignored;
}

static MRESReturn CNavMesh_UpdateGeneration_detour_post(Address pThis, DHookReturn hReturn)
{
	int m_generationState = LoadFromAddress(pThis + view_as<Address>(CNavMesh_m_generationState_offset), NumberType_Int32);
	if(m_generationState == SAVE_NAV_MESH) {
		nav_done();
	}
	return MRES_Ignored;
}

static Action sm_ensurenav(int client, int args)
{
	if(maps) {
		ReplyToCommand(client, "Already generating navs");
		return Plugin_Handled;
	}

	char nextmap[PLATFORM_MAX_PATH];

	maps = view_as<ArrayList>(ReadMapList(null, _, "default", MAPLIST_FLAG_MAPSFOLDER));
	for(int i = 0; i < maps.Length;) {
		maps.GetString(map_idx, nextmap, sizeof(nextmap));

		Format(nextmap, sizeof(nextmap), "maps/%s.nav", nextmap);

		if(FileExists(nextmap, true)) {
			maps.Erase(i);
			continue;
		}

		++i;
	}

	map_idx = 0;

	int len = maps.Length;
	if(len == 0) {
		delete maps;
	} else {
		ReplyToCommand(client, "Generating nav for %i maps", len);

		OnMapStart();
	}

	return Plugin_Handled;
}

static void nav_done()
{
	if(++map_idx == maps.Length) {
		delete maps;
		map_idx = 0;
	} else {
		char nextmap[PLATFORM_MAX_PATH];
		maps.GetString(map_idx, nextmap, sizeof(nextmap));
		SetNextMap(nextmap);
		ForceChangeLevel(nextmap, "ensurenav");
	}
}

public void OnMapStart()
{
	if(maps) {
		char currentmap[PLATFORM_MAX_PATH];
		GetCurrentMap(currentmap, sizeof(currentmap));

		char nextmap[PLATFORM_MAX_PATH];
		maps.GetString(map_idx, nextmap, sizeof(nextmap));

		if(!StrEqual(currentmap, nextmap)) {
			SetNextMap(nextmap);
			ForceChangeLevel(nextmap, "ensurenav");
			return;
		}

		Format(nextmap, sizeof(nextmap), "maps/%s.nav", nextmap);

		if(!FileExists(nextmap, true)) {
			SetCommandFlags("nav_generate", GetCommandFlags("nav_generate") & ~FCVAR_CHEAT);
			InsertServerCommand("nav_generate");
			ServerExecute();
			SetCommandFlags("nav_generate", GetCommandFlags("nav_generate") | FCVAR_CHEAT);
		} else {
			nav_done();
		}
	}
}