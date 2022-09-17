Handle dhStrikeTarget = null;

void StrikeTargetCreate(GameData gamedata)
{
	dhStrikeTarget = DHookCreateFromConf(gamedata, "CTFProjectile_Arrow::StrikeTarget");

	DHookEnableDetour(dhStrikeTarget, false, StrikeTargetPre);
	DHookEnableDetour(dhStrikeTarget, true, StrikeTargetPost);
}

int StrikeTargetTempTeam = -1;

bool IsHealingBolt(int type)
{
	return (type == 11 || type == 32);
}

bool IsBuildingBolt(int type)
{
	return (type == 18);
}

MRESReturn StrikeTargetPre(int pThis, Handle hReturn, Handle hParams)
{
	StrikeTargetTempTeam = -1;

	if(fwCanHeal.FunctionCount == 0) {
		return MRES_Ignored;
	}

	int projtype = GetEntProp(pThis, Prop_Send, "m_iProjectileType");

	if(IsHealingBolt(projtype) || IsBuildingBolt(projtype)) {
		int other = DHookGetParam(hParams, 2);

		if(IsBuildingBolt(projtype) && IsPlayer(other)) {
			return MRES_Ignored;
		}

		if(IsHealingBolt(projtype) && !IsPlayer(other)) {
			return MRES_Ignored;
		}

		Call_StartForward(fwCanHeal);
		Call_PushCell(pThis);
		Call_PushCell(other);
		Call_PushCell(HEAL_PROJECTILE);

		Action result = Plugin_Continue;
		Call_Finish(result);

	#if defined DEBUG
		PrintToServer("fwCanHeal HEAL_PROJECTILE arrow %i", result);
	#endif

		if(result == Plugin_Continue) {
			return MRES_Ignored;
		} else if(result == Plugin_Changed) {
			int owner_team = GetEntityTeam(pThis);
			StrikeTargetTempTeam = GetEntityTeam(other);
			SetEntityTeam(other, owner_team, true);
		} else {
			int enemy_team = GetOppositeTeam(pThis);
			StrikeTargetTempTeam = GetEntityTeam(other);
			SetEntityTeam(other, enemy_team, true);
		}
	}

	return MRES_Ignored;
}

MRESReturn StrikeTargetPost(int pThis, Handle hReturn, Handle hParams)
{
	if(StrikeTargetTempTeam != -1) {
		int other = DHookGetParam(hParams, 2);
		SetEntityTeam(other, StrikeTargetTempTeam, true);
		StrikeTargetTempTeam = -1;
	}

	return MRES_Ignored;
}