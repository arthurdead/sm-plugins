Handle dhInSameTeam = null;

void InSameTeamCreate(GameData gamedata)
{
	dhInSameTeam = DHookCreateFromConf(gamedata, "CBaseEntity::InSameTeam");

	DHookEnableDetour(dhInSameTeam, false, InSameTeamPre);
}

MRESReturn InSameTeamPre(int pThis, Handle hReturn, Handle hParams)
{
	int other = DHookGetParam(hParams, 1);

	Call_StartForward(fwInSameTeam);
	Call_PushCell(pThis);
	Call_PushCell(other);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG && 0
	PrintToServer("fwInSameTeam %i", result);
#endif

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else {
		DHookSetReturn(hReturn, result == Plugin_Changed);
		return MRES_Supercede;
	}
}