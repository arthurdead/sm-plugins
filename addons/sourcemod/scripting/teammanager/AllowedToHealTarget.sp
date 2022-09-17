Handle dhAllowedToHealTarget = null;

void AllowedToHealTargetCreate(GameData gamedata)
{
	dhAllowedToHealTarget = DHookCreateFromConf(gamedata, "CWeaponMedigun::AllowedToHealTarget");

	DHookEnableDetour(dhAllowedToHealTarget, false, AllowedToHealTargetPre);
	DHookEnableDetour(dhAllowedToHealTarget, true, AllowedToHealTargetPost);
}

int AllowedToHealTargetTempTeam = -1;

MRESReturn AllowedToHealTargetPre(int pThis, Handle hReturn, Handle hParams)
{
	AllowedToHealTargetTempTeam = -1;

	if(fwCanHeal.FunctionCount == 0) {
		return MRES_Ignored;
	}

	int other = DHookGetParam(hParams, 1);

	Call_StartForward(fwCanHeal);
	Call_PushCell(pThis);
	Call_PushCell(other);
	Call_PushCell(HEAL_MEDIGUN);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG && 0
	PrintToServer("fwCanHeal HEAL_MEDIGUN %i", result);
#endif

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int owner_team = GetEntityTeam(pThis);

		AllowedToHealTargetTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, owner_team, true);
		return MRES_Ignored;
	} else {
		DHookSetReturn(hReturn, 0);
		return MRES_Supercede;
	}
}

MRESReturn AllowedToHealTargetPost(int pThis, Handle hReturn, Handle hParams)
{
	int other = DHookGetParam(hParams, 1);

	if(AllowedToHealTargetTempTeam != -1) {
		SetEntityTeam(other, AllowedToHealTargetTempTeam, true);
		AllowedToHealTargetTempTeam = -1;
	}

	return MRES_Ignored;
}