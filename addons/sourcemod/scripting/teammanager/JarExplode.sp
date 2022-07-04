Handle dhJarExplode = null;
Handle dhJarOnHit = null;

void JarExplodeCreate(GameData gamedata)
{
	dhJarExplode = DHookCreateFromConf(gamedata, "JarExplode");
	dhJarOnHit = DHookCreateFromConf(gamedata, "CTFProjectile_Jar::OnHit");

	DHookEnableDetour(dhJarExplode, false, JarExplodePre);
	DHookEnableDetour(dhJarExplode, true, JarExplodePost);
}

void JarExplodeEntityCreated(int entity)
{
	if(dhJarOnHit) {
		DHookEntity(dhJarOnHit, false, entity, INVALID_FUNCTION, JarOnHitPre);
		DHookEntity(dhJarOnHit, true, entity, INVALID_FUNCTION, JarOnHitPost);
	}
}

int JarOnHitTempTeam = -1;

MRESReturn JarOnHitPre(int pThis, Handle hParams)
{
	int other = DHookGetParam(hParams, 1);

	JarOnHitTempTeam = -1;

	Call_StartForward(fwCanDamage);
	Call_PushCell(pThis);
	Call_PushCell(other);
	Call_PushCell(DAMAGE_PROJECTILE);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG
	PrintToServer("fwCanDamage jar %i", result);
#endif

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int enemy_team = GetOppositeTeam(pThis);
		JarOnHitTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, enemy_team, true);
	} else {
		int owner_team = GetEntityTeam(pThis);
		JarOnHitTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, owner_team, true);
	}

	return MRES_Ignored;
}

MRESReturn JarOnHitPost(int pThis, Handle hParams)
{
	if(JarOnHitTempTeam != -1) {
		int other = DHookGetParam(hParams, 1);
		SetEntityTeam(other, JarOnHitTempTeam, true);
		JarOnHitTempTeam = -1;
	}

	return MRES_Ignored;
}

bool EnumPlayers(int entity, any data)
{
	ArrayList arr = view_as<ArrayList>(data);
	if(entity >= 1 && entity <= MaxClients) {
		arr.Push(entity);
	}
	return true;
}

bool TraceFilterIgnorePlayers(int entity, int contentsMask, any data)
{
	if(entity == data || entity >= 1 && entity <= MaxClients) {
		return false;
	} else {
		return true;
	}
}

ArrayList JarExplodeTempPlayers = null;

MRESReturn JarExplodePre(Handle hParams)
{
	float pos[3];
	DHookGetParamVector(hParams, 5, pos);

	float radius = DHookGetParam(hParams, 7);

	int attacker = DHookGetParam(hParams, 2);

	int team = DHookGetParam(hParams, 6);

	JarExplodeTempPlayers = new ArrayList(4);

	TR_EnumerateEntitiesSphere(pos, radius, PARTITION_SOLID_EDICTS, EnumPlayers, JarExplodeTempPlayers);

	int len = JarExplodeTempPlayers.Length;
	for(int i = 0; i < len; ++i) {
		int player = JarExplodeTempPlayers.Get(i);

		if(player == attacker ||
			!IsClientInGame(player) ||
			!IsPlayerAlive(player)) {
			JarExplodeTempPlayers.Erase(i--);
			--len;
			continue;
		}

		float plrpos[3];
		GetClientAbsOrigin(player, plrpos);

		Handle tr = TR_TraceRayFilterEx(pos, plrpos, MASK_SHOT & ~CONTENTS_HITBOX, RayType_EndPoint, TraceFilterIgnorePlayers, attacker);
		bool hitworld = (TR_GetEntityIndex(tr) == 0);
		delete tr;

		if(hitworld) {
			JarExplodeTempPlayers.Erase(i--);
			--len;
			continue;
		}

		Call_StartForward(fwCanGetJarated);
		Call_PushCell(attacker);
		Call_PushCell(player);

		Action result = Plugin_Continue;
		Call_Finish(result);

	#if defined DEBUG
		PrintToServer("fwCanGetJarated %i", result);
	#endif

		if(result == Plugin_Continue) {
			JarExplodeTempPlayers.Erase(i--);
			--len;
			continue;
		}

		int oldteam = GetEntityTeam(player);
		JarExplodeTempPlayers.Set(i, oldteam, 1);
		JarExplodeTempPlayers.Set(i, TF2_IsPlayerInCondition(player, TFCond_PasstimeInterception), 2);
		JarExplodeTempPlayers.Set(i, TF2_IsPlayerInCondition(player, TFCond_OnFire), 3);

		switch(result) {
			case Plugin_Changed: {
				SetEntityTeam(player, team, true);
			}
			case Plugin_Handled: {
				SetEntityTeam(player, GetOppositeTeam(team), true);
			}
			case Plugin_Stop: {
				TF2_AddCondition(player, TFCond_PasstimeInterception);
				TF2_RemoveCondition(player, TFCond_OnFire);
			}
		}
	}

	if(len == 0) {
		delete JarExplodeTempPlayers;
	}

	return MRES_Ignored;
}

MRESReturn JarExplodePost(int pThis, Handle hReturn, Handle hParams)
{
	if(JarExplodeTempPlayers != null) {
		for(int i = 0, len = JarExplodeTempPlayers.Length; i < len; ++i) {
			int player = JarExplodeTempPlayers.Get(i);
			int oldteam = JarExplodeTempPlayers.Get(i, 1);
			bool waspasstime = JarExplodeTempPlayers.Get(i, 2);
			bool wasburning = JarExplodeTempPlayers.Get(i, 3);

			SetEntityTeam(player, oldteam, true);

			if(!waspasstime) {
				TF2_RemoveCondition(player, TFCond_PasstimeInterception);
			}

			if(wasburning) {
				TF2_AddCondition(player, TFCond_OnFire);
			}
		}

		delete JarExplodeTempPlayers;
	}

	return MRES_Ignored;
}