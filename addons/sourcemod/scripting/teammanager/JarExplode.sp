Handle dhJarExplode = null;

void JarExplodeCreate(GameData gamedata)
{
	dhJarExplode = DHookCreateFromConf(gamedata, "JarExplode");

	DHookEnableDetour(dhJarExplode, false, JarExplodePre);
	DHookEnableDetour(dhJarExplode, true, JarExplodePost);
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

	JarExplodeTempPlayers = new ArrayList(2);

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

		Call_StartForward(fwCanHeal);
		Call_PushCell(attacker);
		Call_PushCell(player);
		Call_PushCell(HEAL_PROJECTILE);

		Action result = Plugin_Continue;
		Call_Finish(result);

		if(result == Plugin_Continue) {
			JarExplodeTempPlayers.Erase(i--);
			--len;
			continue;
		}

		int oldteam = GetEntityTeam(player);
		JarExplodeTempPlayers.Set(i, oldteam, 1);

		if(result == Plugin_Changed) {
			SetEntityTeam(player, team, true);
		} else {
			SetEntityTeam(player, GetOppositeTeam(team), true);
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

			SetEntityTeam(player, oldteam, true);
		}

		delete JarExplodeTempPlayers;
	}

	return MRES_Ignored;
}