Handle dhFPlayerCanTakeDamage = null;

void FPlayerCanTakeDamageCreate(GameData gamedata)
{
	dhFPlayerCanTakeDamage = DHookCreateFromConf(gamedata, "CTeamplayRules::FPlayerCanTakeDamage");
}

void FPlayerCanTakeDamageMapStart()
{
	DHookGamerules(dhFPlayerCanTakeDamage, false, INVALID_FUNCTION, FPlayerCanTakeDamagePre);
}

MRESReturn FPlayerCanTakeDamagePre(int pThis, Handle hReturn, Handle hParams)
{
	int owner = GetOwner(DHookGetParam(hParams, 2));
	int other = GetOwner(DHookGetParam(hParams, 1));

	Call_StartForward(fwCanDamage);
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