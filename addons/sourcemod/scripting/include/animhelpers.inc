#if defined animhelpers_included
	#endinput
#endif
#define animhelpers_included

methodmap BaseAnimating
{
	public BaseAnimating(int entity) { return view_as<BaseAnimating>(entity); }

	public native Address GetModelPtr();
	public native float SetPoseParameter(int iParameter, float value);
	public native int FindAttachment(const char[] pAttachmentName);
	public native int LookupPoseParameter(const char[] szName);
	public native int LookupSequence(const char[] anim);
	public native int GetSequenceActivity(int iSequence);
	public native int LookupActivity(const char[] activity);
	public native float GetAnimTimeInterval();
	public native bool GetIntervalMovement(float flIntervalUsed, bool &bMoveSeqFinished, float newPosition[3], float newAngles[3]);
	public native float GetPoseParameter(int iParameter);
	public native int FindBodygroupByName(const char[] name);
	public native int SelectWeightedSequence(int activity, int curSequence);
	public native void ResetSequenceInfo();
	public native void StudioFrameAdvance();
	public native void DispatchAnimEvents();
	public native void GetAttachment(const char[] szName, float absOrigin[3], float absAngles[3]);
	public native void SetBodygroup(int iGroup, int iValue);
	public native void GetVectors(float pForward[3], float pRight[3], float pUp[3]);

	public void ResetSequence(int sequence)
	{
		int entity = view_as<int>(this);
		int old = GetEntProp(entity, Prop_Send, "m_nSequence");
		bool changed = (old != sequence);
		SetEntProp(entity, Prop_Send, "m_nSequence", sequence);
		if(changed) {
			SetEntPropFloat(entity, Prop_Data, "m_flAnimTime", GetGameTime());
			SetEntPropFloat(entity, Prop_Send, "m_flCycle", 0.0);
			this.ResetSequenceInfo();
		}
	}
}

methodmap BaseAnimatingOverlay < BaseAnimating
{
	public native void AddGesture(const char[] anim, bool bAutoKill = true);
	public native bool IsPlayingGesture(const char[] anim);
}

#if !defined REQUIRE_PLUGIN
public void __pl_animhelpers_SetNTVOptional()
{
	MarkNativeAsOptional("BaseAnimating.GetModelPtr");
	MarkNativeAsOptional("BaseAnimating.SetPoseParameter");
	MarkNativeAsOptional("BaseAnimating.FindAttachment");
	MarkNativeAsOptional("BaseAnimating.LookupPoseParameter");
	MarkNativeAsOptional("BaseAnimating.LookupSequence");
	MarkNativeAsOptional("BaseAnimating.GetSequenceActivity");
	MarkNativeAsOptional("BaseAnimating.LookupActivity");
	MarkNativeAsOptional("BaseAnimating.GetAnimTimeInterval");
	MarkNativeAsOptional("BaseAnimating.GetIntervalMovement");
	MarkNativeAsOptional("BaseAnimating.GetPoseParameter");
	MarkNativeAsOptional("BaseAnimating.FindBodygroupByName");
	MarkNativeAsOptional("BaseAnimating.SelectWeightedSequence");
	MarkNativeAsOptional("BaseAnimating.ResetSequenceInfo");
	MarkNativeAsOptional("BaseAnimating.StudioFrameAdvance");
	MarkNativeAsOptional("BaseAnimating.DispatchAnimEvents");
	MarkNativeAsOptional("BaseAnimating.GetAttachment");
	MarkNativeAsOptional("BaseAnimating.SetBodygroup");
	MarkNativeAsOptional("BaseAnimating.GetAttachment");
	MarkNativeAsOptional("BaseAnimating.SetBodygroup");
	MarkNativeAsOptional("BaseAnimating.GetVectors");
	MarkNativeAsOptional("BaseAnimatingOverlay.AddGesture");
	MarkNativeAsOptional("BaseAnimatingOverlay.IsPlayingGesture");
}
#endif

public SharedPlugin __pl_animhelpers =
{
	name = "animhelpers",
	file = "animhelpers.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};