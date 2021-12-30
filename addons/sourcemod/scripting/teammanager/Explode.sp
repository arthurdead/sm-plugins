Handle dhExplode = null;

void ExplodeCreate(GameData gamedata)
{
	dhExplode = DHookCreateFromConf(gamedata, "CTFBaseRocket::Explode");
}

void ExplodeEntityCreated(int entity, const char[] classname)
{
	if(dhExplode) {
		if(StrEqual(classname, "tf_projectile_rocket") ||
			StrEqual(classname, "tf_projectile_energy_ball") ||
			StrEqual(classname, "tf_projectile_flare") ||
			StrEqual(classname, "tf_projectile_arrow") ||
			StrEqual(classname, "tf_projectile_healing_bolt") ||
			StrEqual(classname, "tf_projectile_grapplinghook")) {
			DHookEntity(dhExplode, false, entity, INVALID_FUNCTION, ExplodePre);
			DHookEntity(dhExplode, true, entity, INVALID_FUNCTION, ExplodePost);
		}
	}
}

int ExplodeTempTeam = -1;

MRESReturn ExplodePre(int pThis, Handle hParams)
{
	int other = DHookGetParam(hParams, 2);

	ExplodeTempTeam = -1;

	Call_StartForward(fwCanDamage);
	Call_PushCell(pThis);
	Call_PushCell(other);
	Call_PushCell(DAMAGE_PROJECTILE);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG
	PrintToServer("fwCanDamage rocket %i", result);
#endif

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int enemy_team = GetOppositeTeam(pThis);
		ExplodeTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, enemy_team, true);
	} else {
		int owner_team = GetEntityTeam(pThis);
		ExplodeTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, owner_team, true);
	}

	return MRES_Ignored;
}

MRESReturn ExplodePost(int pThis, Handle hParams)
{
	if(ExplodeTempTeam != -1) {
		int other = DHookGetParam(hParams, 2);
		SetEntityTeam(other, ExplodeTempTeam, true);
		ExplodeTempTeam = -1;
	}

	return MRES_Ignored;
}