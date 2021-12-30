Handle dhBackstabVMThink = null;
Handle dhDoSwingTrace = null;
Handle dhPrimaryAttack = null;
Handle dhCanPerformBackstabAgainstTarget = null;

void CanPerformBackstabAgainstTargetCreate(GameData gamedata)
{
	dhBackstabVMThink = DHookCreateFromConf(gamedata, "CTFKnife::BackstabVMThink");
	dhDoSwingTrace = DHookCreateFromConf(gamedata, "CTFWeaponBaseMelee::DoSwingTrace");
	dhPrimaryAttack = DHookCreateFromConf(gamedata, "CBaseCombatWeapon::PrimaryAttack");
	dhCanPerformBackstabAgainstTarget = DHookCreateFromConf(gamedata, "CTFKnife::CanPerformBackstabAgainstTarget");

	DHookEnableDetour(dhBackstabVMThink, false, BackstabVMThinkPre);
	DHookEnableDetour(dhBackstabVMThink, true, BackstabVMThinkPost);

	DHookEnableDetour(dhCanPerformBackstabAgainstTarget, false, CanPerformBackstabAgainstTargetPre);

	#define CGameTracem_pEntOffset 76
}

void CanPerformBackstabAgainstTargetEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_weapon_knife")) {
		if(dhDoSwingTrace) {
			DHookEntity(dhDoSwingTrace, true, entity, INVALID_FUNCTION, DoSwingTracePost);
		}
		if(dhPrimaryAttack) {
			DHookEntity(dhPrimaryAttack, false, entity, INVALID_FUNCTION, PrimaryAttackPre);
			DHookEntity(dhPrimaryAttack, true, entity, INVALID_FUNCTION, PrimaryAttackPost);
		}
	}
}

bool InBackstabVMThink = false;
bool InPrimaryAttack = false;

int DoSwingTraceTempTeam = -1;
int DoSwingTraceTempEntity = -1;

MRESReturn DoSwingTracePost(int pThis, Handle hReturn, Handle hParams)
{
	if(!InBackstabVMThink && !InPrimaryAttack) {
		return MRES_Ignored;
	}

	int ret = DHookGetReturn(hReturn);
	if(ret == 0) {
		return MRES_Ignored;
	}

	int entity = DHookGetParamObjectPtrVar(hParams, 1, CGameTracem_pEntOffset, ObjectValueType_CBaseEntityPtr);
	if(entity == 0 || entity > MaxClients) {
		return MRES_Ignored;
	}

	Call_StartForward(fwCanBackstab);
	Call_PushCell(pThis);
	Call_PushCell(entity);

	Action result = Plugin_Continue;
	Call_Finish(result);

#if defined DEBUG
	PrintToServer("fwCanBackstab %i", result);
#endif

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else if(result == Plugin_Changed) {
		int owner_team = GetEntityTeam(pThis);
		DoSwingTraceTempTeam = GetEntityTeam(entity);
		SetEntityTeam(entity, GetOppositeTeam(owner_team), true);
	} else {
		DoSwingTraceTempTeam = GetEntityTeam(entity);
		SetEntityTeam(entity, GetEntityTeam(pThis), true);
	}

	DoSwingTraceTempEntity = entity;

	return MRES_Ignored;
}

MRESReturn BackstabVMThinkPre(int pThis)
{
	DoSwingTraceTempTeam = -1;
	DoSwingTraceTempEntity = -1;
	InBackstabVMThink = true;
	return MRES_Ignored;
}

MRESReturn BackstabVMThinkPost(int pThis)
{
	if(DoSwingTraceTempTeam != -1) {
		SetEntityTeam(DoSwingTraceTempEntity, DoSwingTraceTempTeam, true);
		DoSwingTraceTempTeam = -1;
		DoSwingTraceTempEntity = -1;
	}

	InBackstabVMThink = false;
	return MRES_Ignored;
}

MRESReturn CanPerformBackstabAgainstTargetPre(int pThis, Handle hReturn, Handle hParams)
{
	if(DoSwingTraceTempTeam != -1) {
		int other = DHookGetParam(hParams, 1);
		SetEntityTeam(other, DoSwingTraceTempTeam, true);
		DoSwingTraceTempTeam = -1;
		DoSwingTraceTempEntity = -1;
	}

	return MRES_Ignored;
}

MRESReturn PrimaryAttackPre(int pThis)
{
	DoSwingTraceTempTeam = -1;
	DoSwingTraceTempEntity = -1;
	InPrimaryAttack = true;
	return MRES_Ignored;
}

MRESReturn PrimaryAttackPost(int pThis)
{
	if(DoSwingTraceTempTeam != -1) {
		SetEntityTeam(DoSwingTraceTempEntity, DoSwingTraceTempTeam, true);
		DoSwingTraceTempTeam = -1;
		DoSwingTraceTempEntity = -1;
	}

	InPrimaryAttack = false;
	return MRES_Ignored;
}