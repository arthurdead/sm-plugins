#include <sourcemod>
#include <vector>
#include <dhooks>

#define	MAX_OVERLAY_DIST_SQR 90000000.0

static ConVar localplayer_index = null;

public void OnPluginStart()
{
	GameData gamedata = new GameData("listen");

	DynamicDetour UTIL_GetLocalPlayerDetour = DynamicDetour.FromConf(gamedata, "UTIL_GetLocalPlayer");
	DynamicDetour UTIL_GetListenServerHostDetour = DynamicDetour.FromConf(gamedata, "UTIL_GetListenServerHost");
	DynamicDetour NDebugOverlayLineDetour = DynamicDetour.FromConf(gamedata, "NDebugOverlay::Line");
	DynamicDetour NDebugOverlayCircleDetour = DynamicDetour.FromConf(gamedata, "NDebugOverlay::Circle");
	DynamicDetour NDebugOverlayTriangleDetour = DynamicDetour.FromConf(gamedata, "NDebugOverlay::Triangle");

	delete gamedata;

	localplayer_index = CreateConVar("localplayer_index", "-1");

	UTIL_GetLocalPlayerDetour.Enable(Hook_Pre, UTIL_GetLocalPlayer);
	UTIL_GetListenServerHostDetour.Enable(Hook_Pre, UTIL_GetListenServerHost);
	NDebugOverlayLineDetour.Enable(Hook_Pre, NDebugOverlayLine);
	NDebugOverlayCircleDetour.Enable(Hook_Pre, NDebugOverlayCircle);
	NDebugOverlayTriangleDetour.Enable(Hook_Pre, NDebugOverlayTriangle);

	RegAdminCmd("sm_listen", sm_listen, ADMFLAG_ROOT);
}

public void OnConfigsExecuted()
{
	localplayer_index.IntValue = -1;
}

public void OnClientDisconnect(int client)
{
	if(client == localplayer_index.IntValue) {
		localplayer_index.IntValue = -1;
	}
}

static Action sm_listen(int client, int params)
{
	localplayer_index.IntValue = client;
	return Plugin_Handled;
}

static int get_local_player()
{
	int local = localplayer_index.IntValue;
	if(local <= 0 || local > MaxClients) {
		local = -1;
	}
	return local;
}

static int halo = -1;
static int laser = -1;
static int arrow = -1;

public void OnMapStart()
{
	switch(GetEngineVersion()) {
		case Engine_TF2: {
			halo = PrecacheModel("materials/sprites/halo01.vmt");
			laser = PrecacheModel("materials/sprites/laser.vmt");
			arrow = PrecacheModel("materials/sprites/obj_icons/capture_highlight.vmt");
		}
		case Engine_Left4Dead2: {
			halo = PrecacheModel("materials/sprites/glow01.vmt");
			laser = PrecacheModel("materials/sprites/laserbeam.vmt");
			arrow = PrecacheModel("materials/sprites/laserbeam.vmt");
		}
	}
}

static void DrawLine(float origin[3], float target[3], int r, int g, int b, bool noDepthTest, float duration)
{
	int num_clients = 0;

	int local = get_local_player();

	int[] clients = new int[MaxClients];
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsFakeClient(i)) {
			continue;
		}

		if((local != -1 && local == i) ||
			!!(GetUserFlagBits(i) & ADMFLAG_ROOT)) {
			clients[num_clients++] = i;
		}
	}

	if(num_clients == 0) {
		return;
	}

	if(duration < 0.1) {
		duration = 0.1;
	}

	if(duration > 25.6) {
		duration = 25.6;
	}

	int mdl = noDepthTest ? arrow : laser;
	int hal = halo;

	int color[4];
	color[0] = r;
	color[1] = g;
	color[2] = b;
	color[3] = 255;

	TE_SetupBeamPoints(origin, target, mdl, hal, 0, 0, duration, 1.0, 1.0, 1, 1.0, color, 0);
	TE_Send(clients, num_clients);
}

static void DrawTriangle(float p1[3], float p2[3], float p3[3], int r, int g, int b, int a, bool noDepthTest, float duration)
{
	
}

static MRESReturn UTIL_GetLocalPlayer(DHookReturn hReturn)
{
	int client = get_local_player();
	if(client != -1 && IsClientInGame(client)) {
		hReturn.Value = client;
	} else {
		hReturn.Value = -1;
	}
	return MRES_Supercede;
}

static MRESReturn UTIL_GetListenServerHost(DHookReturn hReturn)
{
	int client = get_local_player();
	if(client != -1 && IsClientInGame(client)) {
		hReturn.Value = client;
	} else {
		hReturn.Value = -1;
	}
	return MRES_Supercede;
}

static MRESReturn NDebugOverlayLine(DHookParam hParams)
{
	float origin[3];
	hParams.GetVector(1, origin);

	float target[3];
	hParams.GetVector(2, target);

	int r = hParams.Get(3);
	int g = hParams.Get(4);
	int b = hParams.Get(5);

	bool noDepthTest = hParams.Get(6);

	float duration = hParams.Get(7);

	DrawLine(origin, target, r, g, b, noDepthTest, duration);

	return MRES_Supercede;
}

static MRESReturn NDebugOverlayTriangle(DHookParam hParams)
{
	float p1[3];
	hParams.GetVector(1, p1);

	float p2[3];
	hParams.GetVector(2, p2);

	float p3[3];
	hParams.GetVector(3, p3);

	int r = hParams.Get(4);
	int g = hParams.Get(5);
	int b = hParams.Get(6);
	int a = hParams.Get(7);

	bool noDepthTest = hParams.Get(8);

	float duration = hParams.Get(9);

	DrawTriangle(p1, p2, p3, r, g, b, a, noDepthTest, duration);

	return MRES_Supercede;
}

static MRESReturn NDebugOverlayCircle(DHookParam hParams)
{
	float position[3];
	hParams.GetVector(1, position);

	float xAxis[3];
	hParams.GetVector(2, xAxis);

	float yAxis[3];
	hParams.GetVector(3, yAxis);

	float radius = hParams.Get(4);

	int r = hParams.Get(5);
	int g = hParams.Get(6);
	int b = hParams.Get(7);
	int a = hParams.Get(8);

	bool noDepthTest = hParams.Get(9);

	float duration = hParams.Get(10);

	int nSegments = 16;
	float flRadStep = (FLOAT_PI * 2.0) / float(nSegments);

	float vecLastPosition[3];
	float vecStart[3];
	AddVectors(position, xAxis, vecStart);
	ScaleVector(vecStart, radius);
	float vecPosition[3];
	vecPosition = vecStart;

	for(int i = 1; i <= nSegments; ++i)
	{
		vecLastPosition = vecPosition;

		float tmpfl = flRadStep * i;
		float flSin = Sine(tmpfl);
		float flCos = Cosine(tmpfl);

		vecPosition = position;

		float tmpvec[3];
		tmpvec = xAxis;
		ScaleVector(tmpvec, flCos * radius);
		AddVectors(vecPosition, tmpvec, vecPosition);

		tmpvec = yAxis;
		ScaleVector(tmpvec, flSin * radius);
		AddVectors(vecPosition, tmpvec, vecPosition);

		DrawLine(vecLastPosition, vecPosition, r, g, b, noDepthTest, duration);

		if(a && i > 1)
		{
			DrawTriangle(vecStart, vecLastPosition, vecPosition, r, g, b, a, noDepthTest, duration);
		}
	}

	return MRES_Supercede;
}