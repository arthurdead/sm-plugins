Handle dhDeflectPlayer = null;
Handle dhDeflectEntity = null;

void DeflectProjectilesCreate(GameData gamedata)
{
	dhDeflectPlayer = DHookCreateFromConf(gamedata, "CTFWeaponBase::DeflectPlayer");
	dhDeflectEntity = DHookCreateFromConf(gamedata, "CTFWeaponBase::DeflectPlayer");
}

void DeflectProjectilesEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_weapon_flamethrower")) {
		DHookEntity(dhDeflectPlayer, false, entity, INVALID_FUNCTION, DeflectPlayerPre);
		DHookEntity(dhDeflectPlayer, true, entity, INVALID_FUNCTION, DeflectPlayerPost);

		DHookEntity(dhDeflectEntity, false, entity, INVALID_FUNCTION, DeflectEntityPre);
		DHookEntity(dhDeflectEntity, true, entity, INVALID_FUNCTION, DeflectEntityPost);
	}
}

int DeflectPlayerTempTeam = -1;

MRESReturn DeflectPlayerPre(int pThis, Handle hReturn, Handle hParams)
{
	int owner = DHookGetParam(hParams, 2);
	int other = DHookGetParam(hParams, 1);

	Call_StartForward(fwCanAirblast);
	Call_PushCell(owner);
	Call_PushCell(other);

	Action result = Plugin_Continue;
	Call_Finish(result);

	DeflectPlayerTempTeam = -1;

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int owner_team = GetEntityTeam(owner);
		DeflectPlayerTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, GetOppositeTeam(owner_team), true);
	} else {
		DeflectPlayerTempTeam = GetEntityTeam(other);
		SetEntityTeam(other, GetEntityTeam(owner), true);
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
	int other_owner = GetOwner(other);

	Call_StartForward(fwCanAirblast);
	Call_PushCell(owner);
	Call_PushCell(other_owner);

	Action result = Plugin_Continue;
	Call_Finish(result);

	DeflectEntityTempTeam = -1;

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int owner_team = GetEntityTeam(owner);
		DeflectEntityTempTeam = GetEntityTeam(other_owner);
		SetEntityTeam(other, GetOppositeTeam(owner_team), true);
	} else {
		DeflectEntityTempTeam = GetEntityTeam(other_owner);
		SetEntityTeam(other, GetEntityTeam(owner), true);
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