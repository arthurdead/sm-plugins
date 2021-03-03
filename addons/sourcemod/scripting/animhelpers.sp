#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

Handle g_hGetVectors = null;
Handle g_hDispatchAnimEvents = null;
Handle g_hStudioFrameAdvance = null;
Handle g_hLookupPoseParameter = null;
Handle g_hSetPoseParameter = null;
Handle g_hGetPoseParameter = null;
Handle g_hLookupActivity = null;
Handle g_hSDKWorldSpaceCenter = null;
Handle g_hStudio_FindAttachment = null;
Handle g_hGetAttachment = null;
Handle g_hAddGesture = null;
Handle g_hLookupSequence = null;
Handle g_hGetSequenceActivity = null;
Handle g_hIsPlayingGesture = null;
Handle g_hFindBodygroupByName = null;
Handle g_hSetBodyGroup = null;
Handle g_hSelectWeightedSequence = null;
Handle g_hResetSequenceInfo = null;

public APLRes AskPluginLoad2(Handle plugin, bool lateload, char[] error, int err_max)
{
	CreateNative("BaseAnimating.GetModelPtr", Native_GetModelPtr);
	CreateNative("BaseAnimating.SetPoseParameter", Native_SetPoseParameter);
	CreateNative("BaseAnimating.FindAttachment", Native_FindAttachment);
	CreateNative("BaseAnimating.LookupPoseParameter", Native_LookupPoseParameter);
	CreateNative("BaseAnimating.LookupSequence", Native_LookupSequence);
	CreateNative("BaseAnimating.GetSequenceActivity", Native_GetSequenceActivity);
	CreateNative("BaseAnimating.LookupActivity", Native_LookupActivity);
	CreateNative("BaseAnimating.GetAnimTimeInterval", Native_GetAnimTimeInterval);
	CreateNative("BaseAnimating.GetIntervalMovement", Native_GetIntervalMovement);
	CreateNative("BaseAnimating.GetPoseParameter", Native_GetPoseParameter);
	CreateNative("BaseAnimating.FindBodygroupByName", Native_FindBodygroupByName);
	CreateNative("BaseAnimating.SelectWeightedSequence", Native_SelectWeightedSequence);
	CreateNative("BaseAnimating.ResetSequenceInfo", Native_ResetSequenceInfo);
	CreateNative("BaseAnimating.StudioFrameAdvance", Native_StudioFrameAdvance);
	CreateNative("BaseAnimating.DispatchAnimEvents", Native_DispatchAnimEvents);
	/*CreateNative("BaseAnimating.GetAttachment", Native_GetAttachment);
	CreateNative("BaseAnimating.SetBodygroup", Native_SetBodygroup);
	CreateNative("BaseAnimating.SetSequence", Native_SetSequence);
	CreateNative("BaseAnimating.SetPlaybackRate", Native_SetPlaybackRate);
	CreateNative("BaseAnimating.SetCycle", Native_SetCycle);
	CreateNative("BaseAnimating.GetVectors", Native_GetVectors);
	CreateNative("BaseAnimating.RestartMainSequence", Native_RestartMainSequence);
	CreateNative("BaseAnimating.IsSequenceFinished", Native_IsSequenceFinished);
	CreateNative("BaseAnimating.SequenceLoops", Native_SequenceLoops);*/
	CreateNative("BaseAnimatingOverlay.AddGesture", Native_AddGesture);
	CreateNative("BaseAnimatingOverlay.IsPlayingGesture", Native_IsPlayingGesture);
	RegPluginLibrary("animhelpers");
	return APLRes_Success;
}

Address GetModelPtr(int entity)
{
	int index = FindSendPropInfo("CBaseAnimating", "m_flFadeScale") + 28;
	//static const int index = 283 * 4;

	if(IsValidEntity(entity)) {
		int data = GetEntData(entity, index);
		return view_as<Address>(data);
	} else {
		return Address_Null;
	}
}

int LookupActivity(int entity, const char[] activity)
{
	Address pStudioHdr = GetModelPtr(entity);
	if(pStudioHdr == Address_Null) {
		return -1;
	}

	return SDKCall(g_hLookupActivity, pStudioHdr, activity);
}

int Native_GetModelPtr(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	return view_as<int>(GetModelPtr(entity));
}

int Native_SetPoseParameter(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	Address pStudioHdr = GetModelPtr(entity);
	if(pStudioHdr == Address_Null) {
		return 0;
	}

	int iParameter = GetNativeCell(2);
	float value = GetNativeCell(3);

	float ret = SDKCall(g_hSetPoseParameter, entity, pStudioHdr, iParameter, value);
	return view_as<int>(ret);
}

int Native_FindAttachment(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	Address pStudioHdr = GetModelPtr(entity);
	if(pStudioHdr == Address_Null) {
		return -1;
	}

	int len = 0;
	GetNativeStringLength(2, len);
	len++;

	char[] pAttachmentName = new char[len];
	GetNativeString(2, pAttachmentName, len);

	return SDKCall(g_hStudio_FindAttachment, pStudioHdr, pAttachmentName) + 1;
}

int Native_LookupPoseParameter(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	Address pStudioHdr = GetModelPtr(entity);
	if(pStudioHdr == Address_Null) {
		return -1;
	}

	int len = 0;
	GetNativeStringLength(2, len);
	len++;

	char[] szName = new char[len];
	GetNativeString(2, szName, len);

	return SDKCall(g_hLookupPoseParameter, entity, pStudioHdr, szName);
}

int Native_LookupSequence(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	Address pStudioHdr = GetModelPtr(entity);
	if(pStudioHdr == Address_Null) {
		return -1;
	}

	int len = 0;
	GetNativeStringLength(2, len);
	len++;

	char[] anim = new char[len];
	GetNativeString(2, anim, len);

	int seq = SDKCall(g_hLookupSequence, pStudioHdr, anim);
	return seq;
}

int Native_GetSequenceActivity(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	int iSequence = GetNativeCell(2);

	return SDKCall(g_hGetSequenceActivity, entity, iSequence);
}

int Native_LookupActivity(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	int len = 0;
	GetNativeStringLength(2, len);
	len++;

	char[] activity = new char[len];
	GetNativeString(2, activity, len);

	return LookupActivity(entity, activity);
}

int Native_AddGesture(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	int len = 0;
	GetNativeStringLength(2, len);
	len++;

	char[] anim = new char[len];
	GetNativeString(2, anim, len);

	int iSequence = LookupActivity(entity, anim);
	if(iSequence < 0) {
		return 0;
	}

	int bAutoKill = GetNativeCell(3);
	SDKCall(g_hAddGesture, entity, iSequence, bAutoKill);
	return 0;
}

int Native_IsPlayingGesture(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	int len = 0;
	GetNativeStringLength(2, len);
	len++;

	char[] anim = new char[len];
	GetNativeString(2, anim, len);

	int iSequence = LookupActivity(entity, anim);
	if(iSequence < 0) {
		return 0;
	}

	return SDKCall(g_hIsPlayingGesture, entity, iSequence);
}

int Native_GetAnimTimeInterval(Handle plugin, int numParams)
{
	/*int entity = GetNativeCell(1);

	static float MAX_ANIMTIME_INTERVAL = 0.2;

	float m_flAnimTime = GetEntPropFloat(entity, Prop_Data, "m_flAnimTime");
	float m_flPrevAnimTime = GetEntPropFloat(entity, Prop_Data, "m_flPrevAnimTime");

	float flInterval;
	if(m_flAnimTime < GetGameTime()) {
		flInterval = clamp(GetGameTime() - m_flAnimTime, 0.0, MAX_ANIMTIME_INTERVAL);
	} else {
		flInterval = clamp(m_flAnimTime - m_flPrevAnimTime, 0.0, MAX_ANIMTIME_INTERVAL);
	}

	return view_as<int>(flInterval);*/
	return 0;
}

int Native_GetIntervalMovement(Handle plugin, int numParams)
{
	/*Address pStudioHdr = this.GetModelPtr();
	if(pStudioHdr == Address_Null) {
		return 0;
	}

	float m_flPlaybackRate = GetEntPropFloat(this.index, Prop_Data, "m_flPlaybackRate");
	float m_flCycle = GetEntPropFloat(this.index, Prop_Data, "m_flCycle");
	int m_nSequence = GetEntProp(this.index, Prop_Data, "m_nSequence");

	float flComputedCycleRate = SDKCall(g_hSGetSequenceCycleRate, this.index, m_nSequence);
	float flNextCycle = m_flCycle + flIntervalUsed * flComputedCycleRate * m_flPlaybackRate;

	if((!GetEntProp(this.index, Prop_Data, "m_bSequenceLoops")) && flNextCycle > 1.0) {
		flIntervalUsed = m_flCycle / (flComputedCycleRate * m_flPlaybackRate);
		flNextCycle = 1.0;
		bMoveSeqFinished = true;
	} else {
		bMoveSeqFinished = false;
	}

	float deltaPos[3];
	float deltaAngles[3];

	float vLocalAngles[3];
	GetEntPropVector(this.index, Prop_Data, "m_angRotation", vLocalAngles);

	if(SDKCall(g_hStudio_SeqMovement, pStudioHdr, m_nSequence, m_flCycle, flNextCycle, (GetEntData(this.index, FindDataMapInfo(this.index, "m_flPoseParameter"))), deltaPos, deltaAngles)) {
		this.VectorYawRotate(deltaPos, vLocalAngles[1], deltaPos);
		AddVectors(GetAbsOrigin(this.index), deltaPos, newPosition);
		newAngles[1] = vLocalAngles[1] + deltaAngles[1];
		return 1;
	} else {
		GetAbsOrigin(this.index, newPosition);
		newAngles = vLocalAngles;
		return 0;
	}*/

	return 0;
}

int Native_GetPoseParameter(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	int iParameter = GetNativeCell(2);

	return SDKCall(g_hGetPoseParameter, entity, iParameter);
}

int Native_FindBodygroupByName(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	int len = 0;
	GetNativeStringLength(2, len);
	len++;

	char[] name = new char[len];
	GetNativeString(2, name, len);

	return SDKCall(g_hFindBodygroupByName, entity, name);
}

int Native_SelectWeightedSequence(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	Address pStudioHdr = GetModelPtr(entity);
	if(pStudioHdr == Address_Null) {
		return -1;
	}

	int activity = GetNativeCell(2);
	int curSequence = GetNativeCell(3);

	return SDKCall(g_hSelectWeightedSequence, entity, pStudioHdr, activity, curSequence);
}

int Native_ResetSequenceInfo(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	SDKCall(g_hResetSequenceInfo, entity);

	return 0;
}

int Native_StudioFrameAdvance(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	SDKCall(g_hStudioFrameAdvance, entity);

	return 0;
}

int Native_DispatchAnimEvents(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);

	SDKCall(g_hDispatchAnimEvents, entity, entity);

	return 0;
}

public void OnPluginStart()
{
	GameData hConf = new GameData("animhelpers");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseEntity::WorldSpaceCenter");
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByRef);
	g_hSDKWorldSpaceCenter = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseAnimating::StudioFrameAdvance");
	g_hStudioFrameAdvance = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::ResetSequenceInfo");
	g_hResetSequenceInfo = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseAnimating::DispatchAnimEvents");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hDispatchAnimEvents = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CBaseEntity::GetVectors");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	g_hGetVectors = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::GetPoseParameter");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	g_hGetPoseParameter = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::FindBodygroupByName");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hFindBodygroupByName = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::SetBodygroup");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_hSetBodyGroup = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "SelectWeightedSequence");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hSelectWeightedSequence = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::SetPoseParameter");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	g_hSetPoseParameter = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::LookupPoseParameter");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hLookupPoseParameter = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "LookupSequence");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hLookupSequence = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::GetSequenceActivity");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hGetSequenceActivity = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "LookupActivity");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hLookupActivity = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "Studio_FindAttachment");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hStudio_FindAttachment = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimating::GetAttachment");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	g_hGetAttachment = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimatingOverlay::IsPlayingGesture");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_hIsPlayingGesture = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CBaseAnimatingOverlay::AddGesture");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hAddGesture = EndPrepSDKCall();

	delete hConf;
}