#include <sourcemod>
#include <datamaps>
#include <animhelpers>

public void OnPluginStart()
{
	CustomEntityFactory factory = EntityFactoryDictionary.register_based("prop_posable", "prop_dynamic_override");
	CustomSendtable sendtable = CustomSendtable.from_factory(factory, "CBaseAnimating");
	sendtable.set_shared_name("PropPosable");
	sendtable.set_client_class_id("CRagdollPropAttached");
	sendtable.add_prop_qangles("m_ragAngles", 13, _, RAGDOLL_MAX_ELEMENTS);
	sendtable.add_prop_vector("m_ragPos", _, _, -1, SPROP_COORD_MP, RAGDOLL_MAX_ELEMENTS);
	sendtable.add_prop_ehandle("m_hUnragdoll");
	sendtable.add_prop_float("m_flBlendWeight", 0.0, 1.0, 8, SPROP_ROUNDDOWN);
	sendtable.add_prop_int("m_nOverlaySequence", 4, 11);
	sendtable.add_prop_int("m_boneIndexAttached", 4, MAXSTUDIOBONEBITS, SPROP_UNSIGNED);
	sendtable.add_prop_int("m_ragdollAttachedObjectIndex", 4, RAGDOLL_INDEX_BITS, SPROP_UNSIGNED);
	sendtable.add_prop_vector("m_attachmentPointBoneSpace", _, _, -1, SPROP_COORD_MP);
	sendtable.add_prop_vector("m_attachmentPointRagdollSpace", _, _, -1, SPROP_COORD_MP);
	CustomDatamap datamap = CustomDatamap.from_factory(factory);
	datamap.set_shared_name("PropPosable");
	datamap.add_prop("m_iBoneIndexes", custom_prop_int, RAGDOLL_MAX_ELEMENTS);
	datamap.add_prop("m_nBoneIndexes", custom_prop_int);
}

static void posable_new_model(int entity)
{
	char model[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", model, PLATFORM_MAX_PATH);

	int indexes[RAGDOLL_MAX_ELEMENTS];
	int num = RagdollExtractBoneIndices(model, indexes, RAGDOLL_MAX_ELEMENTS);

	SetEntProp(entity, Prop_Data, "m_nBoneIndexes", num);

	for(int i = 0; i < RAGDOLL_MAX_ELEMENTS; ++i) {
		if(i < num) {
			SetEntProp(entity, Prop_Data, "m_iBoneIndexes", indexes[i], _, i);
		} else {
			SetEntProp(entity, Prop_Data, "m_iBoneIndexes", -1, _, i);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "prop_posable")) {
		AnimatingHookOnNewModel(entity, posable_new_model);
	}
}