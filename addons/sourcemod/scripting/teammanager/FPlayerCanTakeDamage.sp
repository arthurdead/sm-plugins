Handle dhFPlayerCanTakeDamage = null;

void FPlayerCanTakeDamageCreate(GameData gamedata)
{
	dhFPlayerCanTakeDamage = DHookCreateFromConf(gamedata, "CTeamplayRules::FPlayerCanTakeDamage");
}

void FPlayerCanTakeDamageMapStart()
{
	if(dhFPlayerCanTakeDamage) {
		DHookGamerules(dhFPlayerCanTakeDamage, false, INVALID_FUNCTION, FPlayerCanTakeDamagePre);
	}
}

MRESReturn FPlayerCanTakeDamagePre(Address pThis, Handle hReturn, Handle hParams)
{
	int owner = DHookGetParam(hParams, 1);
	int other = DHookGetParam(hParams, 2);

	Call_StartForward(fwCanDamage);
	Call_PushCell(other);
	Call_PushCell(owner);
	Call_PushCell(DAMAGE_NORMAL);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG && 0
	PrintToServer("fwCanDamage gamerules %i", result);
#endif

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else {
		DHookSetReturn(hReturn, result == Plugin_Changed);
		return MRES_Supercede;
	}
}