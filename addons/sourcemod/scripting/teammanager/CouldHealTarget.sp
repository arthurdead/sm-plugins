Handle dhCouldHealTarget = null;

void CouldHealTargetCreate(GameData gamedata)
{
	dhCouldHealTarget = DHookCreateFromConf(gamedata, "CObjectDispenser::CouldHealTarget");

	DHookEnableDetour(dhCouldHealTarget, false, CouldHealTargetPre);
	DHookEnableDetour(dhCouldHealTarget, true, CouldHealTargetPost);
}

int CouldHealTargetTempTeam = -1;

MRESReturn CouldHealTargetPre(int pThis, Handle hReturn, Handle hParams)
{
	CouldHealTargetTempTeam = -1;

	if(fwCanHeal.FunctionCount == 0) {
		return MRES_Ignored;
	}

	int other = DHookGetParam(hParams, 1);

	Call_StartForward(fwCanHeal);
	Call_PushCell(pThis);
	Call_PushCell(other);
	Call_PushCell(HEAL_DISPENSER);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG
	PrintToServer("fwCanHeal HEAL_DISPENSER %i", result);
#endif

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int owner_team = GetEntityTeam(pThis);

		CouldHealTargetTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, owner_team, true);
		return MRES_Ignored;
	} else {
		DHookSetReturn(hReturn, 0);
		return MRES_Supercede;
	}
}

MRESReturn CouldHealTargetPost(int pThis, Handle hReturn, Handle hParams)
{
	int other = DHookGetParam(hParams, 1);

	if(CouldHealTargetTempTeam != -1) {
		SetEntityTeam(other, CouldHealTargetTempTeam, true);
		CouldHealTargetTempTeam = -1;
	}

	return MRES_Ignored;
}