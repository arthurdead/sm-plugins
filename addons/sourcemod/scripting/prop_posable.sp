#include <sourcemod>
#include <datamaps>
#include <animhelpers>

public void OnPluginStart()
{
	CustomEntityFactory factory = EntityFactoryDictionary.register_based("prop_posable", "prop_dynamic_override");
	CustomSendtable table = CustomSendtable.from_factory(factory);
	table.set_shared_name("PropPosable");
	table.set_client_class_id("CRagdollPropAttached");
	table.add_prop_qangles("m_ragAngles", 13, _, RAGDOLL_MAX_ELEMENTS);
	table.add_prop_vector("m_ragPos", _, _, -1, SPROP_COORD_MP, RAGDOLL_MAX_ELEMENTS);
	table.add_prop_float("m_flBlendWeight", 0.0, 1.0, 8, SPROP_ROUNDDOWN);
	table.add_prop_int("m_nOverlaySequence", 4, 11);
}