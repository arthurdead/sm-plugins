#include <tf2_stocks>

stock bool IsStealthed(int player)
{
	return (TF2_IsPlayerInCondition(player, TFCond_Stealthed) ||
			TF2_IsPlayerInCondition(player, TFCond_StealthedUserBuffFade) ||
			TF2_IsPlayerInCondition(player, TFCond_Cloaked));
}

stock bool IsAlive(int player)
{
	int lifestate = GetEntProp(player, Prop_Send, "m_lifeState");
	return (lifestate == 0);
}

stock int GetOppositeTeam(int team)
{
	switch(team) {
		case 2: return 3;
		case 3: return 2;
		case 0: return 5;
		case 5: return 0;
	}

	return 0;
}

stock int GetDisguiseTeam(int player)
{
	if(TF2_IsPlayerInCondition(player, TFCond_DisguisedAsDispenser)) {
		int team = GetClientTeam(player);
		return GetOppositeTeam(team);
	}

	return GetEntProp(player, Prop_Send, "m_nDisguiseTeam");
}

stock int GetEntityTeam(int entity)
{
	return GetEntProp(entity, Prop_Send, "m_iTeamNum");
}

stock bool IsEnemy(int entity, int other)
{
	return (GetEntityTeam(entity) != GetEntityTeam(other));
}

stock void SetEntityTeam(int entity, int team, bool raw)
{
	int old_team = GetEntityTeam(entity);
	if(team == old_team) {
		return;
	}

	if(IsPlayer(entity)) {
		if(raw) {
			SetEntProp(entity, Prop_Send, "m_iTeamNum", team);

			int processed = 0;

			int manager = -1;
			while((manager = FindEntityByClassname(manager, "tf_team")) != -1) {
				if(processed & ((1 << 0)|(1 << 1))) {
					break;
				}

				int manager_team = GetEntProp(manager, Prop_Send, "m_iTeamNum");
				if(manager_team == old_team) {
					SDKCall(hRemovePlayer, manager, entity);
					processed |= (1 << 0);
				} else if(manager_team == team) {
					SDKCall(hAddPlayer, manager, entity);
					processed |= (1 << 1);
				}
			}
		} else if(!raw) {
			int life = GetEntProp(entity, Prop_Send, "m_lifeState");
			SetEntProp(entity, Prop_Send, "m_lifeState", 2);
			ignore_team_override = true;
			ChangeClientTeam(entity, team);
			ignore_team_override = false;
			SetEntProp(entity, Prop_Send, "m_lifeState", life);
		}
	} else {
		SetEntProp(entity, Prop_Send, "m_iTeamNum", team);
	}
}

stock bool IsPlayer(int entity)
{
	return (entity >= 1 && entity <= MaxClients);
}

stock bool TraceFilterPlayers(int entity, int contentsMask, any data)
{
	return !IsPlayer(entity);
}

#if defined DEBUG
int laserbeam = -1;

stock void Precache()
{
	laserbeam = PrecacheModel("materials/sprites/laserbeam.vmt");
}

stock void DoLaser(const float start[3], const float end[3])
{
	TE_SetupBeamPoints(start, end, laserbeam, 0, 0, 0, 1.0, 1.0, 1.0, 0, 0.0, {255, 0, 0, 255}, 0);
	TE_SendToAll();
}

stock void DoBox(const float origin[3], const float angles[3], const float mins[3], const float maxs[3])
{
	float corners[8][3];
	
	for (int i = 0; i < 3; i++)
	{
		corners[0][i] = mins[i];
	}
	
	corners[1][0] = maxs[0];
	corners[1][1] = mins[1];
	corners[1][2] = mins[2];
	
	corners[2][0] = maxs[0];
	corners[2][1] = maxs[1];
	corners[2][2] = mins[2];
	
	corners[3][0] = mins[0];
	corners[3][1] = maxs[1];
	corners[3][2] = mins[2];
	
	corners[4][0] = mins[0];
	corners[4][1] = mins[1];
	corners[4][2] = maxs[2];
	
	corners[5][0] = maxs[0];
	corners[5][1] = mins[1];
	corners[5][2] = maxs[2];
	
	for (int i = 0; i < 3; i++)
	{
		corners[6][i] = maxs[i];
	}
	
	corners[7][0] = mins[0];
	corners[7][1] = maxs[1];
	corners[7][2] = maxs[2];

	for(int i = 0; i < sizeof(corners); i++)
	{
		float rad[3];
		rad[0] = DegToRad(angles[2]);
		rad[1] = DegToRad(angles[0]);
		rad[2] = DegToRad(angles[1]);

		float cosAlpha = Cosine(rad[0]);
		float sinAlpha = Sine(rad[0]);
		float cosBeta = Cosine(rad[1]);
		float sinBeta = Sine(rad[1]);
		float cosGamma = Cosine(rad[2]);
		float sinGamma = Sine(rad[2]);

		float x = corners[i][0], y = corners[i][1], z = corners[i][2];
		float newX, newY, newZ;
		newY = cosAlpha*y - sinAlpha*z;
		newZ = cosAlpha*z + sinAlpha*y;
		y = newY;
		z = newZ;

		newX = cosBeta*x + sinBeta*z;
		newZ = cosBeta*z - sinBeta*x;
		x = newX;
		z = newZ;

		newX = cosGamma*x - sinGamma*y;
		newY = cosGamma*y + sinGamma*x;
		x = newX;
		y = newY;
		
		corners[i][0] = x;
		corners[i][1] = y;
		corners[i][2] = z;
	}

	for(int i = 0; i < sizeof(corners); i++)
	{
		AddVectors(origin, corners[i], corners[i]);
	}

	for(int i = 0; i < 4; i++)
	{
		int j = ( i == 3 ? 0 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], laserbeam, 0, 0, 0, 1.0, 1.0, 1.0, 0, 0.0, {255, 0, 0, 255}, 0);
		TE_SendToAll();
	}

	for(int i = 4; i < 8; i++)
	{
		int j = ( i == 7 ? 4 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], laserbeam, 0, 0, 0, 1.0, 1.0, 1.0, 0, 0.0, {255, 0, 0, 255}, 0);
		TE_SendToAll();
	}

	for(int i = 0; i < 4; i++)
	{
		TE_SetupBeamPoints(corners[i], corners[i+4], laserbeam, 0, 0, 0, 1.0, 1.0, 1.0, 0, 0.0, {255, 0, 0, 255}, 0);
		TE_SendToAll();
	}
}
#endif
