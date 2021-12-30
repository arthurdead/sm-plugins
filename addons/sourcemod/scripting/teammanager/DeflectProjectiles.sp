Handle dhDeflectPlayer = null;
Handle dhDeflectEntity = null;

void DeflectProjectilesCreate(GameData gamedata)
{
	dhDeflectPlayer = DHookCreateFromConf(gamedata, "CTFWeaponBase::DeflectPlayer");
	dhDeflectEntity = DHookCreateFromConf(gamedata, "CTFWeaponBase::DeflectEntity");
}

void DeflectProjectilesEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_weapon_flamethrower")) {
		if(dhDeflectPlayer) {
			DHookEntity(dhDeflectPlayer, false, entity, INVALID_FUNCTION, DeflectPlayerPre);
			DHookEntity(dhDeflectPlayer, true, entity, INVALID_FUNCTION, DeflectPlayerPost);
		}
		if(dhDeflectEntity) {
			DHookEntity(dhDeflectEntity, false, entity, INVALID_FUNCTION, DeflectEntityPre);
			DHookEntity(dhDeflectEntity, true, entity, INVALID_FUNCTION, DeflectEntityPost);
		}
	}
}

int DeflectPlayerTempTeam = -1;

MRESReturn DeflectPlayerPre(int pThis, Handle hReturn, Handle hParams)
{
	int owner = DHookGetParam(hParams, 2);
	int other = DHookGetParam(hParams, 1);

	Call_StartForward(fwCanAirblast);
	Call_PushCell(pThis);
	Call_PushCell(owner);
	Call_PushCell(other);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG
	PrintToServer("fwCanAirblast player %i", result);
#endif

	DeflectPlayerTempTeam = -1;

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int owner_team = GetEntityTeam(pThis);
		DeflectPlayerTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, GetOppositeTeam(owner_team), true);
	} else {
		DeflectPlayerTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, GetEntityTeam(pThis), true);
	}

	return MRES_Ignored;
}

MRESReturn DeflectPlayerPost(int pThis, Handle hReturn, Handle hParams)
{
	int other = DHookGetParam(hParams, 1);

	if(DeflectPlayerTempTeam != -1) {
		SetEntityTeam(other, DeflectPlayerTempTeam, true);
		DeflectPlayerTempTeam = -1;
	}

	return MRES_Ignored;
}

int DeflectEntityTempTeam = -1;

MRESReturn DeflectEntityPre(int pThis, Handle hReturn, Handle hParams)
{
	int owner = DHookGetParam(hParams, 2);
	int other = DHookGetParam(hParams, 1);

	Call_StartForward(fwCanAirblast);
	Call_PushCell(pThis);
	Call_PushCell(owner);
	Call_PushCell(other);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG
	PrintToServer("fwCanAirblast entity %i", result);
#endif

	DeflectEntityTempTeam = -1;

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int owner_team = GetEntityTeam(pThis);
		DeflectEntityTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, GetOppositeTeam(owner_team), true);
	} else {
		DeflectEntityTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, GetEntityTeam(pThis), true);
	}

	return MRES_Ignored;
}

MRESReturn DeflectEntityPost(int pThis, Handle hReturn, Handle hParams)
{
	int other = DHookGetParam(hParams, 1);

	if(DeflectEntityTempTeam != -1) {
		SetEntityTeam(other, DeflectEntityTempTeam, true);
		DeflectEntityTempTeam = -1;
	}

	return MRES_Ignored;
}