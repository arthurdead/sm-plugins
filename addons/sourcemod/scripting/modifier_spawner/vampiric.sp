enum struct VampiricInfo
{
	int ref;

	int proj_ref;
}

#define ModifierInfo LightningInfo

static ArrayList modifier_data;

void vampiric_plugin_init()
{
	modifier_data = new ArrayList(sizeof(ModifierInfo));
}

static bool modifier_entity_init(int entity)
{
	ModifierInfo data;
	data.ref = EntIndexToEntRef(entity);

	SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
	SetEntityRenderColor(entity, 255, 50, 50, 255);

	int proj = create_dummy_projectile("tf_projectile_spellbats", entity);

	SetEntProp(proj, Prop_Send, "m_iTeamNum", 2);

	SetEntityNextThink(proj, TIME_NEVER_THINK);

	data.proj_ref = EntIndexToEntRef(proj);

	modifier_data.PushArray(data, sizeof(data));

	return true;
}

void vampiric_check_late_load(int entity, const char[] classname)
{
	if(!EntityIsCombatCharacter(entity)) {
		return;
	}

	if(GetEntityRenderMode(entity) != RENDER_TRANSCOLOR) {
		return;
	}

	int r; int g; int b; int a;
	GetEntityRenderColor(entity, r, g, b, a);

	if(r == 255 && g == 50 && b == 50 && a == 255) {
		modifier_entity_init(entity);
	}
}

bool vampiric_entity_init(int entity)
{
	return modifier_entity_init(entity);
}

static Action modifier_takedamage(int entity, CTakeDamageInfo info, int &result)
{
	int idx = modifier_data.FindValue(EntIndexToEntRef(info.m_hAttacker), ModifierInfo::ref);
	if(idx != -1) {
		info.m_iDamageCustom = TF_CUSTOM_SPELL_BATS;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

static Action modifier_takedamagealive(int entity, CTakeDamageInfo info, int &result)
{
	int attacker = info.m_hAttacker;
	int attacker_ref = EntIndexToEntRef(info.m_hAttacker);

	int idx = modifier_data.FindValue(attacker_ref, ModifierInfo::ref);
	if(idx != -1) {
		int maxhealth = GetEntProp(attacker, Prop_Data, "m_iMaxHealth");
		int health = GetEntProp(attacker, Prop_Data, "m_iHealth");

		health += RoundToFloor(info.m_flDamage);
		if(health > maxhealth) {
			health = maxhealth;
		}

		SetEntProp(attacker, Prop_Data, "m_iHealth", health);
	}

	return Plugin_Continue;
}

void vampiric_entity_created(int entity, const char[] classname)
{
	if(EntityIsCombatCharacter(entity)) {
		HookEntityOnTakeDamage(entity, modifier_takedamage, false);
		HookEntityOnTakeDamageAlive(entity, modifier_takedamagealive, true);
	}
}

void vampiric_entity_destroyed(int entity)
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

bool vampiric_parse(CustomPopulationSpawner spawner, KeyValues data)
{
	return true;
}