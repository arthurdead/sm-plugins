#if defined __listen_inc
	#endinput
#endif
#define __listen_inc

#define NDEBUG_PERSIST_TILL_NEXT_SERVER 0.0

#define VEC_HULL_MINS (view_as<float>({-24.0, -24.0, 0.0}))
#define VEC_HULL_MAXS (view_as<float>({24.0, 24.0, 82.0}))

stock void NDebugOverlay_Box(const float origin[3], const float mins[3], const float maxs[3], int r, int g, int b, int a, float flDuration)
{
	NDebugOverlay_BoxAngles(origin, mins, maxs, view_as<float>({0.0, 0.0, 0.0}), r, g, b, a, flDuration);
}

static float UTIL_VecToYaw( const float vec[3] )
{
	if (vec[0] == 0.0 && vec[0] == 0.0)
		return 0.0;
	
	float yaw = ArcTangent2( vec[1], vec[0] );

	yaw = RadToDeg(yaw);

	if (yaw < 0.0)
		yaw += 360.0;

	return yaw;
}

stock void NDebugOverlay_BoxDirection(const float origin[3], const float mins[3], const float maxs[3], const float fwd[3], int r, int g, int b, int a, float flDuration)
{
	float f_angles[3];
	f_angles[1] = UTIL_VecToYaw(fwd);

	NDebugOverlay_BoxAngles(origin, mins, maxs, f_angles, r, g, b, a, flDuration);
}

native void NDebugOverlay_BoxAngles(const float origin[3], const float mins[3], const float maxs[3], const float angles[3], int r, int g, int b, int a, float flDuration);
//native void NDebugOverlay_SweptBox(const Vector& start, const Vector& end, const Vector& mins, const Vector& maxs, const float angles[3], int r, int g, int b, int a, float flDuration);
//native void NDebugOverlay_EntityBounds( int entity, int r, int g, int b, int a, float flDuration );
native void NDebugOverlay_Line( const float origin[3], const float target[3], int r, int g, int b, bool noDepthTest, float flDuration );
//native void NDebugOverlay_Triangle( const float p1[3], const float p2[3], const float p3[3], int r, int g, int b, int a, bool noDepthTest, float duration );
//native void NDebugOverlay_EntityText( int entityID, int text_offset, const char[] text, float flDuration, int r = 255, int g = 255, int b = 255, int a = 255);
//native void NDebugOverlay_EntityTextAtPosition( const float origin[3], int text_offset, const char *text, float flDuration, int r = 255, int g = 255, int b = 255, int a = 255);
//native void NDebugOverlay_Grid( const float vPosition[3] );
//native void NDebugOverlay_Text( const float origin[3], const char[] text, bool bViewCheck, float flDuration );
//native void NDebugOverlay_ScreenText( float fXpos, float fYpos, const char[] text, int r, int g, int b, int a, float flDuration);

stock void NDebugOverlay_Cross3D1(const float position[3], const float mins[3], const float maxs[3], int r, int g, int b, bool noDepthTest, float flDuration )
{
	float start[3];
	AddVectors(mins, position, start);

	float end[3];
	AddVectors(maxs, position, end);

	NDebugOverlay_Line(start, end, r, g, b, noDepthTest, flDuration);

	start[0] += (maxs[0] - mins[0]);
	end[0] -= (maxs[0] - mins[0]);
	NDebugOverlay_Line(start, end, r, g, b, noDepthTest, flDuration);

	start[1] += (maxs[1] - mins[1]);
	end[1] -= (maxs[1] - mins[1]);
	NDebugOverlay_Line(start, end, r, g, b, noDepthTest, flDuration);

	start[0] -= (maxs[0] - mins[0]);
	end[0] += (maxs[0] - mins[0]);
	NDebugOverlay_Line(start, end, r, g, b, noDepthTest, flDuration);
}

stock void NDebugOverlay_Cross3D2(const float position[3], float size, int r, int g, int b, bool noDepthTest, float flDuration )
{
	float start[3];
	float end[3];

	start[0] = position[0] + size;
	start[1] = position[1];
	start[2] = position[2];

	end[0] = position[0] - size;
	end[1] = position[1];
	end[2] = position[2];

	NDebugOverlay_Line(start, end, r, g, b, noDepthTest, flDuration );

	start[0] = position[0];
	start[1] = position[1] + size;
	start[2] = position[2];

	end[0] = position[0];
	end[1] = position[1] - size;
	end[2] = position[2];

	NDebugOverlay_Line(start, end, r, g, b, noDepthTest, flDuration );

	start[0] = position[0];
	start[1] = position[1];
	start[2] = position[2] + size;

	end[0] = position[0];
	end[1] = position[1];
	end[2] = position[2] - size;

	NDebugOverlay_Line(start, end, r, g, b, noDepthTest, flDuration );
}

stock void NDebugOverlay_Cross3DOriented1( const float position[3], const float angles[3], float size, int r, int g, int b, bool noDepthTest, float flDuration )
{
	float fwd[3];
	float right[3];
	float up[3];
	GetAngleVectors( angles, fwd, right, up );

	ScaleVector(fwd, size);
	ScaleVector(right, size);
	ScaleVector(up, size);

	float start[3];
	float end[3];

	start[0] = position[0] + right[0];
	start[1] = position[1] + right[1];
	start[2] = position[2] + right[2];

	end[0] = position[0] - right[0];
	end[1] = position[1] - right[1];
	end[2] = position[2] - right[2];

	NDebugOverlay_Line( start, end, r, g, b, noDepthTest, flDuration );

	start[0] = position[0] + fwd[0];
	start[1] = position[1] + fwd[1];
	start[2] = position[2] + fwd[2];

	end[0] = position[0] - fwd[0];
	end[1] = position[1] - fwd[1];
	end[2] = position[2] - fwd[2];

	NDebugOverlay_Line( start, end, r, g, b, noDepthTest, flDuration );

	start[0] = position[0] + up[0];
	start[1] = position[1] + up[1];
	start[2] = position[2] + up[2];

	end[0] = position[0] - up[0];
	end[1] = position[1] - up[1];
	end[2] = position[2] - up[2];

	NDebugOverlay_Line( start, end, r, g, b, noDepthTest, flDuration );
}

//native void NDebugOverlay_Cross3DOriented2( const float m[3][4], float size, int c, bool noDepthTest, float flDuration );
//native void NDebugOverlay_DrawTickMarkedLine(const float startPos, const float endPos[3], float tickDist, int tickTextDist, int r, int g, int b, bool noDepthTest, float flDuration );
//native void NDebugOverlay_DrawGroundCrossHairOverlay();
//native void NDebugOverlay_HorzArrow( const float startPos[3], const float endPos[3], float width, int r, int g, int b, int a, bool noDepthTest, float flDuration);
//native void NDebugOverlay_YawArrow( const float startPos[3], float yaw, float length, float width, int r, int g, int b, int a, bool noDepthTest, float flDuration);
//native void NDebugOverlay_VertArrow( const float startPos[3], const float endPos[3], float width, int r, int g, int b, int a, bool noDepthTest, float flDuration);
//native void NDebugOverlay_Axis( const float position, const float angles[3], float size, bool noDepthTest, float flDuration );
//native void NDebugOverlay_Sphere1( const float center, float radius, int r, int g, int b, bool noDepthTest, float flDuration );
//native void NDebugOverlay_Sphere2( const float position[3], const float angles[3], float radius, int r, int g, int b, int a, bool bNoDepthTest, float flDuration );
//native void NDebugOverlay_Circle1( const float position[3], float radius, int r, int g, int b, int a, bool bNoDepthTest, float flDuration );
//native void NDebugOverlay_Circle2( const float position[3], const float angles[3], float radius, int r, int g, int b, int a, bool bNoDepthTest, float flDuration );
native void NDebugOverlay_Circle3( const float position[3], const float xAxis[3], const float yAxis[3], float radius, int r, int g, int b, int a, bool bNoDepthTest, float flDuration );

public SharedPlugin __pl_listen =
{
	name = "listen",
	file = "listen.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_listen_SetNTVOptional()
{
	
}
#endif