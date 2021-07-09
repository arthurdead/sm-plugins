Handle dhJarExplode = null;
Handle dhJarOnHit = null;

void JarExplodeCreate(GameData gamedata)
{
	dhJarExplode = DHookCreateFromConf(gamedata, "JarExplode");
	dhJarOnHit = DHookCreateFromConf(gamedata, "CTFProjectile_Jar::OnHit");

	DHookEnableDetour(dhJarExplode, false, JarExplodePre);
	DHookEnableDetour(dhJarExplode, true, JarExplodePost);
}

void JarExplodeEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "tf_projectile_jar") != -1 ||
		StrEqual(classname, "tf_projectile_cleaver") ||
		StrContains(classname, "tf_projectile_spell") != -1) {
		DHookEntity(dhJarOnHit, false, entity, INVALID_FUNCTION, JarOnHitPre);
		DHookEntity(dhJarOnHit, true, entity, INVALID_FUNCTION, JarOnHitPost);
	}
}

int JarOnHitTempTeam = -1;

MRESReturn JarOnHitPre(int pThis, Handle hParams)
{
	int owner = GetOwner(pThis);
	int other = DHookGetParam(hParams, 1);
	int other_owner = GetOwner(other);

	JarOnHitTempTeam = -1;

	Call_StartForward(fwCanDamage);
	Call_PushCell(owner);
	Call_PushCell(other_owner);

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int enemy_team = GetOppositeTeam(owner);
		JarOnHitTempTeam = GetEntityTeam(other_owner);
		SetEntityTeam(other, enemy_team, true);
	} else {
		int owner_team = GetEntityTeam(owner);
		JarOnHitTempTeam = GetEntityTeam(other_owner);
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