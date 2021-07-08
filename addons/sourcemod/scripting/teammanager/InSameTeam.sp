Handle dhInSameTeam = null;

void InSameTeamCreate(GameData gamedata)
{
	dhInSameTeam = DHookCreateFromConf(gamedata, "CBaseEntity::InSameTeam");

	DHookEnableDetour(dhInSameTeam, false, InSameTeamPre);
}

MRESReturn InSameTeamPre(int pThis, Handle hReturn, Handle hParams)
{
	int owner = GetOwner(pThis);
	int other = GetOwner(DHookGetParam(hParams, 1));

	Call_StartForward(fwInSameTeam);
	Call_PushCell(owner);
	Call_PushCell(other);

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else {
		DHookSetReturn(hReturn, result == Plugin_Changed);
		return MRES_Supercede;
	}
}