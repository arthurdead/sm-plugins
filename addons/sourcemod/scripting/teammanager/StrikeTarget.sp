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
	int projtype = GetEntProp(pThis, Prop_Send, "m_iProjectileType");

	StrikeTargetTempTeam = -1;

	if(IsHealingBolt(projtype) || IsBuildingBolt(projtype)) {
		int owner = GetOwner(pThis);
		int other = DHookGetParam(hParams, 2);
		int other_owner = GetOwner(other);

		if(IsBuildingBolt(projtype) && IsPlayer(other)) {
			return MRES_Ignored;
		}

		if(IsHealingBolt(projtype) && !IsPlayer(other)) {
			return MRES_Ignored;
		}

		Call_StartForward(fwCanHeal);
		Call_PushCell(owner);
		Call_PushCell(other_owner);
		Call_PushCell(HEAL_PROJECTILE);

		Action result = Plugin_Continue;
		Call_Finish(result);

		if(result == Plugin_Continue) {
			return MRES_Ignored;
		} else if(result == Plugin_Changed) {
			int owner_team = GetEntityTeam(owner);
			StrikeTargetTempTeam = GetEntityTeam(other_owner);
			SetEntityTeam(other, owner_team, true);
		} else {
			int enemy_team = GetOppositeTeam(owner);
			StrikeTargetTempTeam = GetEntityTeam(other_owner);
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