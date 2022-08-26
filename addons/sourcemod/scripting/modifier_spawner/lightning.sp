enum struct LightningInfo
{
	int ref;

	int proj_ref;
}

#define ModifierInfo LightningInfo

static ArrayList modifier_data;

void lightning_plugin_init()
{
	modifier_data = new ArrayList(sizeof(ModifierInfo));
}

static bool modifier_entity_init(int entity)
{
	ModifierInfo data;
	data.ref = EntIndexToEntRef(entity);

	SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
	SetEntityRenderColor(entity, 50, 50, 255, 255);

	int proj = create_dummy_projectile("tf_projectile_lightningorb", entity);

	SetEntityNextThink(proj, TIME_NEVER_THINK, "ExplodeAndRemoveThink");
	SetEntityNextThink(proj, TIME_NEVER_THINK, "VortexThink");

	data.proj_ref = EntIndexToEntRef(proj);

	modifier_data.PushArray(data, sizeof(data));

	return true;
}

void lightning_check_late_load(int entity, const char[] classname)
{
	if(!EntityIsCombatCharacter(entity)) {
		return;
	}

	if(GetEntityRenderMode(entity) != RENDER_TRANSCOLOR) {
		return;
	}

	int r; int g; int b; int a;
	GetEntityRenderColor(entity, r, g, b, a);

	if(r == 50 && g == 50 && b == 255 && a == 255) {
		modifier_entity_init(entity);
	}
}

bool lighting_entity_init(int entity)
{
	return modifier_entity_init(entity);
}

static Action modifier_takedamage(int entity, CTakeDamageInfo info, int &result)
{
	int idx = modifier_data.FindValue(EntIndexToEntRef(info.m_hAttacker), ModifierInfo::ref);
	if(idx != -1) {
		info.m_bitsDamageType |= DMG_SHOCK;
		info.m_iDamageCustom = TF_CUSTOM_SPELL_LIGHTNING;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

void lighting_entity_created(int entity, const char[] classname)
{
	if(EntityIsCombatCharacter(entity)) {
		HookEntityOnTakeDamage(entity, modifier_takedamage, false);
	}
}

void lightning_entity_destroyed(int entity)
{
	int idx = modifier_data.FindValue(EntIndexToEntRef(entity), ModifierInfo::ref);
	if(idx != -1) {
		ModifierInfo data;
		modifier_data.GetArray(idx, data, sizeof(data));

		int proj = EntRefToEntIndex(data.proj_ref);
		if(proj != -1) {
			RemoveEntity(proj);
		}

		modifier_data.Erase(idx);
	}
}

bool lightning_parse(CustomPopulationSpawner spawner, KeyValues data)
{
	return true;
}