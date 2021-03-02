#include <sourcemod>
#include <vector>
#include <dhooks>

#define	MAX_OVERLAY_DIST_SQR 90000000.0

ConVar localplayer_index = null;

public void OnPluginStart()
{
	GameData gamedata = new GameData("listen");

	DynamicDetour UTIL_GetLocalPlayerDetour = DynamicDetour.FromConf(gamedata, "UTIL_GetLocalPlayer");
	DynamicDetour UTIL_GetListenServerHostDetour = DynamicDetour.FromConf(gamedata, "UTIL_GetListenServerHost");
	DynamicDetour NDebugOverlayLineDetour = DynamicDetour.FromConf(gamedata, "NDebugOverlay::Line");
	DynamicDetour NDebugOverlayCircleDetour = DynamicDetour.FromConf(gamedata, "NDebugOverlay::Circle");
	DynamicDetour NDebugOverlayTriangleDetour = DynamicDetour.FromConf(gamedata, "NDebugOverlay::Triangle");

	delete gamedata;

	localplayer_index = CreateConVar("localplayer_index", "1");

	UTIL_GetLocalPlayerDetour.Enable(Hook_Pre, UTIL_GetLocalPlayer);
	UTIL_GetListenServerHostDetour.Enable(Hook_Pre, UTIL_GetListenServerHost);
	NDebugOverlayLineDetour.Enable(Hook_Pre, NDebugOverlayLine);
	NDebugOverlayCircleDetour.Enable(Hook_Pre, NDebugOverlayCircle);
	NDebugOverlayTriangleDetour.Enable(Hook_Pre, NDebugOverlayTriangle);
}

int halo = -1;
int laser = -1;
int arrow = -1;

public void OnMapStart()
{
	halo = PrecacheModel("materials/sprites/halo01.vmt");
	laser = PrecacheModel("materials/sprites/laser.vmt");
	arrow = PrecacheModel("materials/sprites/obj_icons/capture_highlight.vmt");
}

void DrawLine(int client, float origin[3], float target[3], int r, int g, int b, bool noDepthTest, float duration)
{
	if(duration == 0.0) {
		duration = 0.1;
	}

	int mdl = noDepthTest ? arrow : laser;
	int hal = halo;

	int color[4];
	color[0] = r;
	color[1] = g;
	color[2] = b;
	color[3] = 255;

	TE_SetupBeamPoints(origin, target, mdl, hal, 0, 0, duration, 1.0, 1.0, 1, 1.0, color, 0);
	TE_SendToClient(client);
}

MRESReturn NDebugOverlayLine(DHookParam hParams)
{
	int client = localplayer_index.IntValue;
	if(!IsClientInGame(client)) {
		return MRES_Supercede;
	}

	float origin[3];
	hParams.GetVector(1, origin);

	float target[3];
	hParams.GetVector(2, target);

	int r = hParams.Get(3);
	int g = hParams.Get(4);
	int b = hParams.Get(5);

	bool noDepthTest = hParams.Get(6);

	float duration = hParams.Get(7);

	DrawLine(client, origin, target, r, g, b, noDepthTest, duration);

	return MRES_Supercede;
}

void DrawTriangle(int client, float p1[3], float p2[3], float p3[3], int r, int g, int b, int a, bool noDepthTest, float duration)
{
	
}

MRESReturn NDebugOverlayTriangle(DHookParam hParams)
{
	int client = localplayer_index.IntValue;
	if(!IsClientInGame(client)) {
		return MRES_Supercede;
	}

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

	DrawTriangle(client, p1, p2, p3, r, g, b, a, noDepthTest, duration);

	return MRES_Supercede;
}

MRESReturn NDebugOverlayCircle(DHookParam hParams)
{
	int client = localplayer_index.IntValue;
	if(!IsClientInGame(client)) {
		return MRES_Supercede;
	}

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

		DrawLine(client, vecLastPosition, vecPosition, r, g, b, noDepthTest, duration);

		if(a && i > 1)
		{
			DrawTriangle(client, vecStart, vecLastPosition, vecPosition, r, g, b, a, noDepthTest, duration);
		}
	}

	return MRES_Supercede;
}

MRESReturn UTIL_GetLocalPlayer(DHookReturn hReturn)
{
	int client = localplayer_index.IntValue;
	
	if(IsClientInGame(client)) {
		hReturn.Value = client;
	} else {
		hReturn.Value = -1;
	}
	return MRES_Supercede;
}

MRESReturn UTIL_GetListenServerHost(DHookReturn hReturn)
{
	int client = localplayer_index.IntValue;
	
	if(IsClientInGame(client)) {
		hReturn.Value = client;
	} else {
		hReturn.Value = -1;
	}
	return MRES_Supercede;
}