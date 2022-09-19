Handle dhInSameTeam = null;

void InSameTeamCreate(GameData gamedata)
{
	dhInSameTeam = DHookCreateFromConf(gamedata, "CBaseEntity::InSameTeam");

	DHookEnableDetour(dhInSameTeam, false, InSameTeamPre);
}

MRESReturn InSameTeamPre(int pThis, Handle hReturn, Handle hParams)
{
	Action result = Plugin_Continue;

	int other = -1;
	if(!DHookIsNullParam(hParams, 1)) {
		other = DHookGetParam(hParams, 1);
	}

	if(fwInSameTeam.FunctionCount > 0 && other != -1) {
		Call_StartForward(fwInSameTeam);
		Call_PushCell(pThis);
		Call_PushCell(other);

		Call_Finish(result);

	#if defined DEBUG && 0
		PrintToServer("fwInSameTeam %i", result);
	#endif
	}

	if(result == Plugin_Continue) {
		if(other != -1 && IsMannVsMachineMode()) {
			int team1 = GetEntityTeam(pThis);
			int team2 = GetEntityTeam(other);

			if((team1 == 3 || team1 == 4) &&
				(team2 == 3 || team2 == 4)) {
				DHookSetReturn(hReturn, true);
				return MRES_Supercede;
			}
		}
		return MRES_Ignored;
	} else {
		DHookSetReturn(hReturn, result == Plugin_Changed);
		return MRES_Supercede;
	}
}