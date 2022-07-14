#include <datamaps>

public void OnPluginStart()
{
	CustomSendtable player_dt = CustomSendtable.from_classname("player", "CTFPlayer");
	player_dt.set_name("DT_TFPlayer");
	player_dt.set_network_name("CTFPlayer");
	player_dt.unexclude_prop("DT_TFPlayer", "m_flPoseParameter");
	player_dt.unexclude_prop("DT_TFPlayer", "m_flPlaybackRate");
	player_dt.unexclude_prop("DT_TFPlayer", "m_nSequence");
	player_dt.unexclude_prop("DT_TFPlayer", "m_nBody");
	player_dt.unexclude_prop("DT_TFPlayer", "m_angRotation");
	player_dt.unexclude_prop("DT_TFPlayer", "overlay_vars");
	player_dt.unexclude_prop("DT_TFPlayer", "m_nModelIndex");
	player_dt.unexclude_prop("DT_TFPlayer", "m_vecOrigin");
	player_dt.unexclude_prop("DT_TFPlayer", "m_flCycle");
	player_dt.unexclude_prop("DT_TFPlayer", "m_flAnimTime");
	player_dt.unexclude_prop("DT_TFPlayer", "m_flexWeight");
	player_dt.unexclude_prop("DT_TFPlayer", "m_blinktoggle");
	player_dt.unexclude_prop("DT_TFPlayer", "m_viewtarget");

	CustomSendtable viewmodel_dt = CustomSendtable.from_classname("viewmodel", "CBaseViewModel");
	viewmodel_dt.set_name("DT_BaseViewModel");
	viewmodel_dt.set_network_name("CBaseViewModel");
	viewmodel_dt.set_base_class("CBaseAnimating");

	CustomSendtable tf_viewmodel_dt = CustomSendtable.from_classname("tf_viewmodel", "CTFViewModel");
	tf_viewmodel_dt.set_name("DT_TFViewModel");
	tf_viewmodel_dt.set_network_name("CTFViewModel");
	tf_viewmodel_dt.set_base_class("CBaseViewModel");
}