// Sentry Gun runtime, adapted from func_tank_test v1.9.1 by Nullifidian, OpenAI.
#define SG_GAMEDATA_FILE RESUPPLY_GAMEDATA_FILE
#define SG_SHOT_SAMPLE "weapons/m249/m249_tp.wav"
#define SG_SHOT_SOUND ")" ... SG_SHOT_SAMPLE
#define SG_TRACER_PARTICLE "weapon_tracers"
#define SG_MUZZLE_PARTICLE "muzzleflash_m249_3rd"
#define SG_SHELL_MODEL "models/weapons/shells/556x45.mdl"
#define SG_SENTRY_BASE_MODEL "models/botmassacre/sentry_v1/bm_sentry_base.mdl"
#define SG_SENTRY_YAW_MODEL "models/botmassacre/sentry_v1/bm_sentry_yaw.mdl"
#define SG_SENTRY_GUN_MODEL "models/botmassacre/sentry_v1/bm_sentry_gun.mdl"
#define SG_SENTRY_PIVOT_HEIGHT 27.0
#define SG_PARTICLE_CUSTOM_ORIGIN 2

#define SG_MAX_SENTRIES 6
#define SG_UPDATE_INTERVAL 0.1
#define SG_SEARCH_INTERVAL 0.5
#define SG_SEARCH_TRACES_PER_FRAME 4
#define SG_SEARCH_TRACES_PER_SENTRY 2

enum struct SG_SentryState {
	bool Removing;
	bool LowHpRed;
	int LowHpThreshold;
	int BlastTick;
	int BlastSource;
	float BlastDamage;
	int Tank;
	int Visual;
	int Weapon;
	int SentryBase;
	int SentryYaw;
	float LastSentryYaw;
	int Owner;
	int Team;
	int Target;
	int PinnedTarget;
	int Ammo;
	int OriginalAmmo[3];
	int FireOutputs;
	int DamageEvents;
	int Kills;
	bool Enabled;
	bool Active;
	float NextReport;
	int ScriptShots;
	int BotImpacts;
	int ShotEpoch;
	float NextShot;
	int MuzzleAttachment;
	int MuzzleFlashes;
	int ShellAttachment;
	int ShellsEjected;
	bool ShellReady;
	int TracerCalls;
	int WeaponDefinition;
	int BulletEffects;
	float NextUpdate;
	float NextSearch;
	int Candidates[MAXPLAYERS];
	int CandidateCount;
	int CandidateIndex;
}

SG_SentryState SG_g_Sentries[MAXPLAYERS + 1];
ArrayList SG_g_EntitySlots;
int SG_g_SentryCount;
int SG_g_SchedulerCursor;
int SG_g_BotCount;
int SG_g_BotUserIds[MAXPLAYERS];
int SG_g_BotTeams[MAXPLAYERS];
float SG_g_BotPositions[MAXPLAYERS][3];
float SG_g_NextBotSnapshot;

char SG_g_ShotSound[PLATFORM_MAX_PATH];
int SG_g_SoundLevel;
int SG_g_SoundPitch;
float SG_g_SoundVolume;
Handle SG_g_TEFireBullets;
Handle SG_g_GetWeaponDefinition;
Handle SG_g_ParticleTracer;
Handle SG_g_DispatchParticle;
Handle SG_g_LookupAttachment;
Handle SG_g_GetAttachment;
int SG_g_MuzzleParticle = INVALID_STRING_INDEX;
int SG_g_ShellModel;
bool SG_g_TracerReady;



ConVar SG_cvRange, SG_cvBotRange, SG_cvBotAttack;
ConVar SG_cvDamage, SG_cvFireRate, SG_cvTurnSpeed;
ConVar SG_cvTracerEvery;
ConVar SG_cvBuildEnabled;
bool SG_g_BuildEnabled = true;
int SG_g_TracerEvery = 2;
int SG_g_Damage = 20;
float SG_g_FireRate = 6.0;
float SG_g_ShotInterval = 0.16666667;
float SG_g_TurnSpeed = 240.0;
float SG_g_Range = 1500.0;
float SG_g_RangeSquared = 2250000.0;
float SG_g_BotRangeSquared = 2250000.0;
bool SG_g_BotAttackEnabled = true;

void SG_InitSettings() {
	SG_cvBuildEnabled = CreateConVar("sm_props_sentry_build_enabled", "1", "Allow building new sentries: 0 disabled, 1 enabled. Existing sentries can still operate and be moved.", _, true, 0.0, true, 1.0);
	SG_g_BuildEnabled = SG_cvBuildEnabled.BoolValue;
	SG_cvBuildEnabled.AddChangeHook(SG_BuildSettingsChanged);
	SG_cvRange = CreateConVar("sm_props_sentry_range", "1500", "Sentry detection and firing range in Source units. Applies to existing sentries.", _, true, 64.0, true, 16384.0);
	SG_cvBotRange = CreateConVar("sm_props_sentry_bot_range", "1500", "Range in Source units at which bots can target enemy sentries.", _, true, 64.0, true, 16384.0);
	SG_cvBotAttack = CreateConVar("sm_props_sentry_bot_attack", "1", "Allow bots to target enemy sentries: 0 disabled, 1 enabled.", _, true, 0.0, true, 1.0);
	SG_cvDamage = CreateConVar("sm_props_sentry_damage", "20", "Integer damage per sentry bullet. Applies to existing sentries.", _, true, 1.0, true, 1000.0);
	SG_cvFireRate = CreateConVar("sm_props_sentry_fire_rate", "6", "Sentry shots per second. Applies to existing sentries.", _, true, 0.1, true, 30.0);
	SG_cvTurnSpeed = CreateConVar("sm_props_sentry_turn_speed", "240", "Sentry yaw and pitch speed in degrees per second. Applies to existing sentries.", _, true, 1.0, true, 720.0);
	SG_cvTracerEvery = CreateConVar("sm_props_sentry_tracer_every", "2", "Emit a tracer every N fired sentry shots: 0 disabled, 1 every shot, 2 every second shot.", _, true, 0.0, true, 1000.0);
	SG_g_TracerEvery = SG_cvTracerEvery.IntValue;
	SG_cvTracerEvery.AddChangeHook(SG_TracerSettingsChanged);
	SG_g_Damage = SG_cvDamage.IntValue;
	SG_g_FireRate = SG_cvFireRate.FloatValue;
	SG_g_ShotInterval = 1.0 / SG_g_FireRate;
	SG_g_TurnSpeed = SG_cvTurnSpeed.FloatValue;
	SG_cvDamage.AddChangeHook(SG_CombatSettingsChanged);
	SG_cvFireRate.AddChangeHook(SG_CombatSettingsChanged);
	SG_cvTurnSpeed.AddChangeHook(SG_CombatSettingsChanged);
	SG_g_Range = SG_cvRange.FloatValue;
	SG_g_RangeSquared = SG_g_Range * SG_g_Range;
	float botRange = SG_cvBotRange.FloatValue;
	SG_g_BotRangeSquared = botRange * botRange;
	SG_g_BotAttackEnabled = SG_cvBotAttack.BoolValue;
	SG_cvRange.AddChangeHook(SG_SettingsChanged);
	SG_cvBotRange.AddChangeHook(SG_SettingsChanged);
	SG_cvBotAttack.AddChangeHook(SG_SettingsChanged);
}

public void SG_BuildSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	SG_g_BuildEnabled = convar.BoolValue;
}

public void SG_TracerSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	SG_g_TracerEvery = convar.IntValue;
}

public void SG_CombatSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == SG_cvDamage)
		SG_g_Damage = convar.IntValue;
	else if (convar == SG_cvFireRate) {
		SG_g_FireRate = convar.FloatValue;
		SG_g_ShotInterval = 1.0 / SG_g_FireRate;
	} else if (convar == SG_cvTurnSpeed)
		SG_g_TurnSpeed = convar.FloatValue;
	float now = GetGameTime();
	for (int slot = 1; slot <= MaxClients; slot++) {
		int tank = SG_TankEntity(slot);
		if (tank == -1 || SG_g_Sentries[slot].Removing)
			continue;
		SG_StopTank(slot);
		bool applied = true;
		if (convar == SG_cvDamage) {
			SetEntProp(tank, Prop_Data, "m_iBulletDamageVsPlayer", SG_g_Damage);
			SetVariantInt(SG_g_Damage);
			applied = AcceptEntityInput(tank, "SetDamage");
		} else if (convar == SG_cvFireRate) {
			SetVariantFloat(SG_g_FireRate);
			applied = AcceptEntityInput(tank, "SetFireRate");
			SG_g_Sentries[slot].NextShot = now + SG_g_ShotInterval;
		} else if (convar == SG_cvTurnSpeed) {
			SetEntPropFloat(tank, Prop_Data, "m_yawRate", SG_g_TurnSpeed);
			SetEntPropFloat(tank, Prop_Data, "m_pitchRate", SG_g_TurnSpeed);
		}
		if (!applied) {
			SG_g_Sentries[slot].Enabled = false;
			LogError("Sentry %d stopped: could not apply combat settings.", slot);
		}
		SG_g_Sentries[slot].NextUpdate = now + SG_UPDATE_INTERVAL * float(slot % SG_MAX_SENTRIES) / float(SG_MAX_SENTRIES);
	}
}

public void SG_SettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == SG_cvRange) {
		SG_g_Range = convar.FloatValue;
		SG_g_RangeSquared = SG_g_Range * SG_g_Range;
		float now = GetGameTime();
		for (int slot = 1; slot <= MaxClients; slot++) {
			int tank = SG_TankEntity(slot);
			if (tank == -1 || SG_g_Sentries[slot].Removing)
				continue;
			SG_StopTank(slot);
			SetVariantFloat(SG_g_Range);
			if (!AcceptEntityInput(tank, "SetMaxRange")) {
				SG_g_Sentries[slot].Enabled = false;
				LogError("Sentry %d stopped: could not apply sm_props_sentry_range.", slot);
			}
			SG_g_Sentries[slot].NextUpdate = now + SG_UPDATE_INTERVAL * float(slot % SG_MAX_SENTRIES) / float(SG_MAX_SENTRIES);
		}
		return;
	}
	if (convar == SG_cvBotRange) {
		float range = convar.FloatValue;
		SG_g_BotRangeSquared = range * range;
	} else if (convar == SG_cvBotAttack)
		SG_g_BotAttackEnabled = convar.BoolValue;
	SGB_RecheckSettings();
}

void SG_ResetSentries() {
	SGB_ResetAll();
	for (int slot = 1; slot <= MaxClients; slot++) {
		SG_SentryState empty;
		int epoch = SG_g_Sentries[slot].ShotEpoch + 1;
		SG_g_Sentries[slot] = empty;
		SG_g_Sentries[slot].ShotEpoch = epoch;
		SG_g_Sentries[slot].Tank = INVALID_ENT_REFERENCE;
		SG_g_Sentries[slot].Visual = INVALID_ENT_REFERENCE;
		SG_g_Sentries[slot].Weapon = INVALID_ENT_REFERENCE;
		SG_g_Sentries[slot].SentryBase = INVALID_ENT_REFERENCE;
		SG_g_Sentries[slot].SentryYaw = INVALID_ENT_REFERENCE;

	}
	SG_g_EntitySlots.Clear();
	SG_g_EntitySlots.Resize(GetMaxEntities());
	for (int entity = 0; entity < SG_g_EntitySlots.Length; entity++)
		SG_g_EntitySlots.Set(entity, 0);
	SG_g_SentryCount = 0;
	SG_g_SchedulerCursor = 0;
	SG_g_BotCount = 0;
	SG_g_NextBotSnapshot = 0.0;
}

void SG_RegisterSentryEntity(int slot, int entity) {
	if (entity >= SG_g_EntitySlots.Length) {
		int previous = SG_g_EntitySlots.Length;
		SG_g_EntitySlots.Resize(entity + 1);
		for (int index = previous; index <= entity; index++)
			SG_g_EntitySlots.Set(index, 0);
	}
	SG_g_EntitySlots.Set(entity, slot);
}

int SG_EntitySlot(int entity) {
	if (SG_g_EntitySlots == null || entity <= MaxClients || entity >= SG_g_EntitySlots.Length)
		return 0;
	return SG_g_EntitySlots.Get(entity);
}


void SG_RemoveAllSentries() {
	if (!SG_g_SentryCount)
		return;
	for (int slot = 1; slot <= MaxClients; slot++)
		if (SG_g_Sentries[slot].Tank != INVALID_ENT_REFERENCE)
			SG_RemoveTank(slot);
}

bool SG_PrepareBulletEffects() {
	GameData config = new GameData(SG_GAMEDATA_FILE);
	if (config == null) {
		LogError("Missing addons/sourcemod/gamedata/%s.txt", SG_GAMEDATA_FILE);
		delete config;
		return false;
	}
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "TE_FireBullets")) {
		LogError("Could not resolve TE_FireBullets.");
		delete config;
		return false;
	}
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	for (int i = 0; i < 4; i++)
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	SG_g_TEFireBullets = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CINSWeapon::GetWeaponDefinitionHandle")) {
		LogError("Could not resolve CINSWeapon::GetWeaponDefinitionHandle.");
		delete config;
		return false;
	}
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	SG_g_GetWeaponDefinition = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(config, SDKConf_Signature, "UTIL_ParticleTracer")) {
		LogError("Could not resolve UTIL_ParticleTracer. Install the updated %s.txt gamedata.", SG_GAMEDATA_FILE);
		delete config;
		return false;
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	SG_g_ParticleTracer = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Static);
	if (PrepSDKCall_SetFromConf(config, SDKConf_Signature, "DispatchParticleEffect")) {
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
		PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		SG_g_DispatchParticle = EndPrepSDKCall();
	}
	if (SG_g_DispatchParticle == null)
		LogError("Muzzle flash disabled: DispatchParticleEffect unavailable. Update %s.txt.", SG_GAMEDATA_FILE);
	StartPrepSDKCall(SDKCall_Entity);
	if (PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseAnimating::LookupAttachment")) {
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		SG_g_LookupAttachment = EndPrepSDKCall();
	}
	StartPrepSDKCall(SDKCall_Entity);
	if (PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseAnimating::GetAttachment")) {
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, 0, VENCODE_FLAG_COPYBACK);
		PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef, 0, VENCODE_FLAG_COPYBACK);
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
		SG_g_GetAttachment = EndPrepSDKCall();
	}
	if (SG_g_LookupAttachment == null || SG_g_GetAttachment == null)
		LogError("Muzzle flash disabled: attachment SDKCalls unavailable. Update %s.txt.", SG_GAMEDATA_FILE);
	delete config;
	if (SG_g_TEFireBullets == null || SG_g_GetWeaponDefinition == null || SG_g_ParticleTracer == null || SG_g_DispatchParticle == null
		|| SG_g_LookupAttachment == null || SG_g_GetAttachment == null) {
		LogError("Could not prepare turret bullet-effect SDKCalls.");
		delete config;
		return false;
	}
	return true;
}

void SG_PrepareTracer() {
	SG_g_TracerReady = false;
	int table = FindStringTable("ParticleEffectNames");
	if (table == INVALID_STRING_TABLE) {
		LogError("Turret tracer unavailable: ParticleEffectNames table is missing.");
		return;
	}
	int index = FindStringIndex(table, SG_TRACER_PARTICLE);
	if (index == INVALID_STRING_INDEX) {
		bool locked = LockStringTables(false);
		AddToStringTable(table, SG_TRACER_PARTICLE);
		LockStringTables(locked);
		index = FindStringIndex(table, SG_TRACER_PARTICLE);
	}
	SG_g_TracerReady = index != INVALID_STRING_INDEX;
	if (!SG_g_TracerReady)
		LogError("Could not register turret tracer particle %s.", SG_TRACER_PARTICLE);
}

void SG_PrepareMuzzleFlash(int slot) {
	SG_g_MuzzleParticle = INVALID_STRING_INDEX;
	SG_g_Sentries[slot].MuzzleAttachment = 0;
	SG_g_Sentries[slot].MuzzleFlashes = 0;
	if (SG_g_DispatchParticle == null || SG_g_LookupAttachment == null || SG_g_GetAttachment == null)
		return;
	int table = FindStringTable("ParticleEffectNames");
	if (table == INVALID_STRING_TABLE) {
		LogError("Muzzle flash disabled: ParticleEffectNames table is missing.");
		return;
	}
	SG_g_MuzzleParticle = FindStringIndex(table, SG_MUZZLE_PARTICLE);
	if (SG_g_MuzzleParticle == INVALID_STRING_INDEX) {
		bool locked = LockStringTables(false);
		AddToStringTable(table, SG_MUZZLE_PARTICLE);
		LockStringTables(locked);
		SG_g_MuzzleParticle = FindStringIndex(table, SG_MUZZLE_PARTICLE);
	}
	if (SG_g_MuzzleParticle == INVALID_STRING_INDEX)
		LogError("Could not register muzzle flash particle %s.", SG_MUZZLE_PARTICLE);
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	if (visual > MaxClients && IsValidEntity(visual))
		SG_g_Sentries[slot].MuzzleAttachment = SDKCall(SG_g_LookupAttachment, visual, "muzzle");
}

void SG_GetMuzzleTransform(int slot, const float shotOrigin[3], const float direction[3], float origin[3], float angles[3]) {
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	if (SG_g_LookupAttachment != null && SG_g_GetAttachment != null && visual > MaxClients && IsValidEntity(visual)) {
		if (SG_g_Sentries[slot].MuzzleAttachment == 0)
			SG_g_Sentries[slot].MuzzleAttachment = SDKCall(SG_g_LookupAttachment, visual, "muzzle");
		if (SG_g_Sentries[slot].MuzzleAttachment > 0 && SDKCall(SG_g_GetAttachment, visual, SG_g_Sentries[slot].MuzzleAttachment, origin, angles))
			return;
	}
	for (int i = 0; i < 3; i++)
		origin[i] = shotOrigin[i];
	GetVectorAngles(direction, angles);
}

void SG_EmitMuzzleFlash(int slot, int tank, const float origin[3], const float angles[3]) {
	if (SG_g_DispatchParticle == null || SG_g_MuzzleParticle == INVALID_STRING_INDEX)
		return;
	SDKCall(SG_g_DispatchParticle, SG_g_MuzzleParticle, origin, angles, SG_PARTICLE_CUSTOM_ORIGIN, tank, -1);
	SG_g_Sentries[slot].MuzzleFlashes++;
}

void SG_PrepareShellEjection(int slot) {
	SG_g_Sentries[slot].ShellReady = false;
	SG_g_Sentries[slot].ShellAttachment = 0;
	SG_g_Sentries[slot].ShellsEjected = 0;
	SG_g_ShellModel = PrecacheModel(SG_SHELL_MODEL, true);
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	if (SG_g_ShellModel <= 0 || SG_g_LookupAttachment == null || SG_g_GetAttachment == null
		|| visual <= MaxClients || !IsValidEntity(visual))
		return;
	SG_g_Sentries[slot].ShellAttachment = SDKCall(SG_g_LookupAttachment, visual, "shell");
	if (SG_g_Sentries[slot].ShellAttachment <= 0) {
		LogError("Shell ejection disabled: install the v1.0.6 sentry gun model with its shell attachment.");
		return;
	}
	TE_Start("breakmodel");
	char fields[][] = {"m_vecOrigin", "m_angRotation[0]", "m_angRotation[1]", "m_angRotation[2]",
		"m_vecSize", "m_vecVelocity", "m_nModelIndex", "m_nRandomization", "m_nCount", "m_fTime", "m_nFlags"};
	for (int i = 0; i < sizeof(fields); i++) {
		if (!TE_IsValidProp(fields[i])) {
			LogError("Shell ejection disabled: breakmodel property missing: %s", fields[i]);
			return;
		}
	}
	SG_g_Sentries[slot].ShellReady = true;
}

void SG_EmitShell(int slot) {
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	if (!SG_g_Sentries[slot].ShellReady || visual <= MaxClients || !IsValidEntity(visual))
		return;
	float origin[3], angles[3], direction[3], velocity[3];
	if (!SDKCall(SG_g_GetAttachment, visual, SG_g_Sentries[slot].ShellAttachment, origin, angles))
		return;
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	float speed = GetRandomFloat(70.0, 95.0);
	for (int i = 0; i < 3; i++) {
		origin[i] += direction[i] * 1.0;
		velocity[i] = direction[i] * speed;
	}
	velocity[2] += 25.0;
	TE_Start("breakmodel");
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteFloat("m_angRotation[0]", angles[0]);
	TE_WriteFloat("m_angRotation[1]", angles[1]);
	TE_WriteFloat("m_angRotation[2]", GetRandomFloat(0.0, 360.0));
	TE_WriteVector("m_vecSize", NULL_VECTOR);
	TE_WriteVector("m_vecVelocity", velocity);
	TE_WriteNum("m_nModelIndex", SG_g_ShellModel);
	TE_WriteNum("m_nRandomization", 10);
	TE_WriteNum("m_nCount", 1);
	TE_WriteFloat("m_fTime", 2.0);
	TE_WriteNum("m_nFlags", 2);
	TE_SendToAllInRange(origin, RangeType_Visibility);
	SG_g_Sentries[slot].ShellsEjected++;
}

public Action SG_BlockTurretPickup(int client, int weapon) {
	int slot = SG_EntitySlot(weapon);
	return slot && weapon == EntRefToEntIndex(SG_g_Sentries[slot].Weapon) ? Plugin_Handled : Plugin_Continue;
}

public Action SG_BlockTurretTouch(int entity, int other) {
	return Plugin_Handled;
}

public Action SG_BlockTurretUse(int entity, int activator, int caller, UseType type, float value) {
	return Plugin_Handled;
}

bool SG_PrecacheSentryModels() {
	char models[][] = {SG_SENTRY_BASE_MODEL, SG_SENTRY_YAW_MODEL, SG_SENTRY_GUN_MODEL};
	for (int i = 0; i < sizeof(models); i++) {
		char collision[PLATFORM_MAX_PATH];
		strcopy(collision, sizeof(collision), models[i]);
		ReplaceString(collision, sizeof(collision), ".mdl", ".phy");
		if (!FileExists(collision, true))
			return false;
		if (!FileExists(models[i], true) || !PrecacheModel(models[i], true))
			return false;
	}
	return true;
}

bool SG_CreateSentryPart(int slot, const char[] model, const float position[3], const float angles[3], int &reference) {
	int entity = CreateEntityByName("prop_dynamic_override");
	if (entity == -1)
		return false;
	SG_RegisterSentryEntity(slot, entity);
	reference = EntIndexToEntRef(entity);
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "DisableBoneFollowers", "1");
	TeleportEntity(entity, position, angles, NULL_VECTOR);
	if (!DispatchSpawn(entity) || !IsValidEntity(entity))
		return false;
	SetEntityMoveType(entity, MOVETYPE_NONE);
	ActivateEntity(entity);
	// Native turret traces must ignore its own solid parts.
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", SG_TankEntity(slot));
	if (!SG_IsSentryPartSolid(reference)) {
		LogError("Sentry collision did not initialize for %s. Install its matching .mdl and .phy files.", model);
		return false;
	}
	return true;
}

bool SG_IsSentryPartSolid(int reference) {
	int entity = EntRefToEntIndex(reference);
	return entity > MaxClients && IsValidEntity(entity)
		&& GetEntProp(entity, Prop_Send, "m_nSolidType") == 6
		&& !(GetEntProp(entity, Prop_Send, "m_usSolidFlags") & 4);
}

bool SG_CreateSentryMount(int slot, const float pivot[3], const float angles[3]) {
	float ground[3];
	for (int i = 0; i < 3; i++)
		ground[i] = pivot[i];
	ground[2] -= SG_SENTRY_PIVOT_HEIGHT;
	SG_g_Sentries[slot].LastSentryYaw = angles[1];
	return SG_CreateSentryPart(slot, SG_SENTRY_BASE_MODEL, ground, angles, SG_g_Sentries[slot].SentryBase)
		&& SG_CreateSentryPart(slot, SG_SENTRY_YAW_MODEL, pivot, angles, SG_g_Sentries[slot].SentryYaw);
}

void SG_OnGameFrame() {
	if (!SG_g_SentryCount)
		return;
	float now = GetGameTime();
	int budget = SG_SEARCH_TRACES_PER_FRAME;
	int start = SG_g_SchedulerCursor;
	for (int offset = 0; offset < MaxClients; offset++) {
		int slot = (start + offset) % MaxClients + 1;
		if (SG_g_Sentries[slot].Tank == INVALID_ENT_REFERENCE)
			continue;
		if (now >= SG_g_Sentries[slot].NextUpdate) {
			SG_g_Sentries[slot].NextUpdate = now + SG_UPDATE_INTERVAL;
			SG_UpdateTarget(slot);
		}
		if (SG_g_Sentries[slot].Tank == INVALID_ENT_REFERENCE)
			continue;
		if (budget > 0 && SG_g_Sentries[slot].Enabled && !SG_g_Sentries[slot].Active && !SG_g_Sentries[slot].PinnedTarget
			&& SG_g_Sentries[slot].CandidateIndex < SG_g_Sentries[slot].CandidateCount) {
			SG_SearchStep(slot, budget);
			SG_g_SchedulerCursor = slot;
		}
		if (SG_g_Sentries[slot].Active)
			SG_UpdateCradle(slot);
	}
}

void SG_UpdateCradle(int slot) {
	int tank = SG_TankEntity(slot);
	int cradle = EntRefToEntIndex(SG_g_Sentries[slot].SentryYaw);
	if (tank == -1 || cradle <= MaxClients || !IsValidEntity(cradle))
		return;
	float angles[3];
	GetEntPropVector(tank, Prop_Data, "m_angAbsRotation", angles);
	if (FloatAbs(angles[1] - SG_g_Sentries[slot].LastSentryYaw) < 0.01)
		return;
	SG_g_Sentries[slot].LastSentryYaw = angles[1];
	angles[0] = 0.0;
	angles[2] = 0.0;
	TeleportEntity(cradle, NULL_VECTOR, angles, NULL_VECTOR);
}

bool SG_CreateTurretWeapon(int slot, int tank, const float position[3], const float angles[3], const char[] model) {
	int weapon = CreateEntityByName("weapon_m249");
	if (weapon == -1)
		return false;
	SG_RegisterSentryEntity(slot, weapon);
	SG_g_Sentries[slot].Weapon = EntIndexToEntRef(weapon);
	DispatchKeyValue(weapon, "spawnflags", "1073741824");
	TeleportEntity(weapon, position, angles, NULL_VECTOR);
	if (!DispatchSpawn(weapon) || !IsValidEntity(weapon)) {
		LogError("Native M249 spawn failed.");
		return false;
	}
	if (GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") != -1) {
		LogError("New native M249 unexpectedly has an owner.");
		return false;
	}

	SG_g_Sentries[slot].Ammo = HasEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") ? GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") : -1;
	SG_g_Sentries[slot].WeaponDefinition = SDKCall(SG_g_GetWeaponDefinition, weapon);
	if (SG_g_Sentries[slot].Ammo < 0 || SG_g_Sentries[slot].WeaponDefinition < 0) {
		LogError("Spawned M249 has invalid bullet-effect data: ammo=%d definition=%d.", SG_g_Sentries[slot].Ammo, SG_g_Sentries[slot].WeaponDefinition);
		return false;
	}

	SetEntProp(weapon, Prop_Send, "m_fEffects", GetEntProp(weapon, Prop_Send, "m_fEffects") | 32);
	SetEntityMoveType(weapon, MOVETYPE_NONE);
	SetEntProp(weapon, Prop_Send, "m_nSolidType", 0);
	SetEntProp(weapon, Prop_Send, "m_usSolidFlags", GetEntProp(weapon, Prop_Send, "m_usSolidFlags") | 4);
	if (!SDKHookEx(weapon, SDKHook_Touch, SG_BlockTurretTouch) || !SDKHookEx(weapon, SDKHook_Use, SG_BlockTurretUse)) {
		LogError("Native M249 pickup-blocking hooks unavailable.");
		return false;
	}
	float stopped[3];
	TeleportEntity(weapon, position, angles, stopped);
	SetVariantString("!activator");
	if (!AcceptEntityInput(weapon, "SetParent", tank, weapon)
		|| GetEntPropEnt(weapon, Prop_Data, "m_hMoveParent") != tank) {
		LogError("Native M249 failed to parent to turret %d.", tank);
		return false;
	}
	// Weapon Activate rejects ownerless weapons in Insurgency and schedules removal.
	if (!SG_CreateSentryPart(slot, model, position, angles, SG_g_Sentries[slot].Visual)) {
		LogError("Could not spawn the visible sentry gun prop.");
		return false;
	}
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	SetVariantString("!activator");
	if (!AcceptEntityInput(visual, "SetParent", tank, visual)
		|| GetEntPropEnt(visual, Prop_Data, "m_hMoveParent") != tank) {
		LogError("Sentry gun prop failed to parent to turret %d.", tank);
		return false;
	}
	if (!SG_IsSentryPartSolid(SG_g_Sentries[slot].Visual)) {
		LogError("Sentry gun lost its solid collision after parenting.");
		return false;
	}
	return true;
}

void SG_PrepareShotSound() {
	SG_g_ShotSound[0] = '\0';
	SG_g_SoundVolume = 1.0;
	SG_g_SoundPitch = SNDPITCH_NORMAL;
	SG_g_SoundLevel = 94;
	if (!FileExists("sound/" ... SG_SHOT_SAMPLE, true)) {
		LogError("Turret shot sample not found in the game search paths: sound/%s", SG_SHOT_SAMPLE);
		return;
	}
	if (!PrecacheSound(SG_SHOT_SOUND, true)) {
		LogError("Could not precache turret shot sample: %s", SG_SHOT_SAMPLE);
		return;
	}
	strcopy(SG_g_ShotSound, sizeof(SG_g_ShotSound), SG_SHOT_SOUND);
}





int SG_TankEntity(int slot) {
	int entity = EntRefToEntIndex(SG_g_Sentries[slot].Tank);
	return entity > MaxClients && IsValidEntity(entity) ? entity : -1;
}

void SG_RemoveTank(int slot) {
	SGB_RemoveTarget(slot);
	if (SG_g_Sentries[slot].Tank != INVALID_ENT_REFERENCE)
		SG_g_SentryCount--;
	SG_g_Sentries[slot].Removing = true;
	SG_g_Sentries[slot].ShotEpoch++;

	int tank = SG_TankEntity(slot);
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	int weapon = EntRefToEntIndex(SG_g_Sentries[slot].Weapon);
	SG_UnregisterRoot(slot, SG_g_Sentries[slot].SentryBase);
	int base = EntRefToEntIndex(SG_g_Sentries[slot].SentryBase);
	int cradle = EntRefToEntIndex(SG_g_Sentries[slot].SentryYaw);
	SG_g_Sentries[slot].SentryBase = INVALID_ENT_REFERENCE;
	SG_g_Sentries[slot].SentryYaw = INVALID_ENT_REFERENCE;
	SG_g_Sentries[slot].Enabled = false;
	SG_g_Sentries[slot].Active = false;
	SG_g_Sentries[slot].Target = 0;
	SG_g_Sentries[slot].PinnedTarget = 0;
	SG_g_Sentries[slot].CandidateCount = 0;
	SG_g_Sentries[slot].CandidateIndex = 0;
	SG_g_Sentries[slot].NextSearch = 0.0;
	SG_g_Sentries[slot].Owner = 0;
	SG_g_Sentries[slot].Tank = INVALID_ENT_REFERENCE;
	SG_g_Sentries[slot].Visual = INVALID_ENT_REFERENCE;
	SG_g_Sentries[slot].Weapon = INVALID_ENT_REFERENCE;
	if (tank != -1)
		AcceptEntityInput(tank, "Deactivate");
	if (visual > MaxClients && IsValidEntity(visual))
		RemoveEntity(visual);
	if (weapon > MaxClients && IsValidEntity(weapon))
		RemoveEntity(weapon);
	if (tank != -1 && IsValidEntity(tank))
		RemoveEntity(tank);
	if (cradle > MaxClients && IsValidEntity(cradle))
		RemoveEntity(cradle);
	if (base > MaxClients && IsValidEntity(base))
		RemoveEntity(base);
}

void SG_StopTank(int slot) {
	SG_g_Sentries[slot].CandidateCount = 0;
	SG_g_Sentries[slot].CandidateIndex = 0;
	SG_g_Sentries[slot].NextSearch = 0.0;
	SG_UpdateCradle(slot);
	SG_g_Sentries[slot].ShotEpoch++;
	int tank = SG_TankEntity(slot);
	if (tank != -1) {
		AcceptEntityInput(tank, "Deactivate");
		AcceptEntityInput(tank, "ClearTargetEntity");
		float stopped[3];
		SetEntPropVector(tank, Prop_Data, "m_vecAngVelocity", stopped);
	}
	SG_g_Sentries[slot].Active = false;
	SG_g_Sentries[slot].Target = 0;
}



bool SG_IsEnemyBot(int slot, int client) {
	return client >= 1 && client <= MaxClients && IsClientInGame(client)
		&& IsPlayerAlive(client) && IsFakeClient(client)
		&& GetClientTeam(client) >= 2 && GetClientTeam(client) != SG_g_Sentries[slot].Team;
}



public bool SG_TraceSight(int entity, int mask, any slot) {
	return SG_EntitySlot(entity) != slot;
}

bool SG_VisibleBot(int slot, int bot, const float origin[3], float &distance) {
	if (!SG_IsEnemyBot(slot, bot))
		return false;
	float target[3];
	GetClientEyePosition(bot, target);
	target[2] -= 12.0;
	distance = GetVectorDistance(origin, target, true);
	if (distance < 64.0 * 64.0 || distance > SG_g_RangeSquared)
		return false;
	Handle trace = TR_TraceRayFilterEx(origin, target, MASK_SHOT, RayType_EndPoint, SG_TraceSight, slot);
	bool visible = !TR_StartSolid(trace) && (!TR_DidHit(trace) || TR_GetEntityIndex(trace) == bot);
	delete trace;
	return visible;
}

void SG_UpdateTarget(int slot) {
	int tank = SG_TankEntity(slot);
	if (tank == -1) {
		if (SG_g_Sentries[slot].Tank != INVALID_ENT_REFERENCE)
			SG_RemoveTank(slot);
		return;
	}
	if (SG_g_Sentries[slot].Removing)
		return;
	int owner = GetClientOfUserId(SG_g_Sentries[slot].Owner);
	if (!owner || !IsClientInGame(owner) || GetClientTeam(owner) != SG_g_Sentries[slot].Team) {
		SG_RemoveTank(slot);
		return;
	}
	int weapon = EntRefToEntIndex(SG_g_Sentries[slot].Weapon);
	if (weapon <= MaxClients || !IsValidEntity(weapon)
		|| GetEntPropEnt(weapon, Prop_Data, "m_hMoveParent") != tank) {
		LogError("Native turret weapon disappeared or detached; removing the sentry gun.");
		PrintToChat(owner, "[Sentry Gun] Gun disappeared or detached. Turret removed; check server errors.");
		SG_RemoveTank(slot);
		return;
	}
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	if (visual <= MaxClients || !IsValidEntity(visual)
		|| GetEntPropEnt(visual, Prop_Data, "m_hMoveParent") != tank) {
		LogError("Sentry gun prop disappeared or detached; removing the sentry gun.");
		SG_RemoveTank(slot);
		return;
	}
	if (EntRefToEntIndex(SG_g_Sentries[slot].SentryBase) == INVALID_ENT_REFERENCE || EntRefToEntIndex(SG_g_Sentries[slot].SentryYaw) == INVALID_ENT_REFERENCE) {
		LogError("Sentry mount disappeared; removing the sentry gun.");
		SG_RemoveTank(slot);
		return;
	}

	float origin[3];
	GetEntPropVector(tank, Prop_Data, "m_vecAbsOrigin", origin);
	if (!SG_g_Sentries[slot].Enabled)
		return;
	int bot = GetClientOfUserId(SG_g_Sentries[slot].PinnedTarget ? SG_g_Sentries[slot].PinnedTarget : SG_g_Sentries[slot].Target);
	float distance;
	if (SG_VisibleBot(slot, bot, origin, distance)) {
		SG_ActivateTarget(slot, bot);
		return;
	}
	if (SG_g_Sentries[slot].Active)
		SG_StopTank(slot);
	if (!SG_g_Sentries[slot].PinnedTarget && SG_g_Sentries[slot].CandidateIndex >= SG_g_Sentries[slot].CandidateCount
		&& GetGameTime() >= SG_g_Sentries[slot].NextSearch)
		SG_BuildSearch(slot, origin);
}

void SG_RefreshBotSnapshot() {
	float now = GetGameTime();
	if (now < SG_g_NextBotSnapshot)
		return;
	SG_g_NextBotSnapshot = now + SG_UPDATE_INTERVAL;
	SG_g_BotCount = 0;
	for (int bot = 1; bot <= MaxClients; bot++) {
		if (!IsClientInGame(bot) || !IsFakeClient(bot) || !IsPlayerAlive(bot) || GetClientTeam(bot) < 2)
			continue;
		SG_g_BotUserIds[SG_g_BotCount] = GetClientUserId(bot);
		SG_g_BotTeams[SG_g_BotCount] = GetClientTeam(bot);
		GetClientEyePosition(bot, SG_g_BotPositions[SG_g_BotCount]);
		SG_g_BotPositions[SG_g_BotCount][2] -= 12.0;
		SG_g_BotCount++;
	}
}

void SG_BuildSearch(int slot, const float origin[3]) {
	SG_RefreshBotSnapshot();
	SG_g_Sentries[slot].CandidateCount = 0;
	SG_g_Sentries[slot].CandidateIndex = 0;
	SG_g_Sentries[slot].NextSearch = GetGameTime() + SG_SEARCH_INTERVAL;
	float distances[MAXPLAYERS];
	for (int i = 0; i < SG_g_BotCount; i++) {
		if (SG_g_BotTeams[i] == SG_g_Sentries[slot].Team)
			continue;
		float distance = GetVectorDistance(origin, SG_g_BotPositions[i], true);
		if (distance < 64.0 * 64.0 || distance > SG_g_RangeSquared)
			continue;
		int index = SG_g_Sentries[slot].CandidateCount++;
		while (index > 0 && distances[index - 1] > distance) {
			distances[index] = distances[index - 1];
			SG_g_Sentries[slot].Candidates[index] = SG_g_Sentries[slot].Candidates[index - 1];
			index--;
		}
		distances[index] = distance;
		SG_g_Sentries[slot].Candidates[index] = SG_g_BotUserIds[i];
	}
}

void SG_SearchStep(int slot, int &budget) {
	int tank = SG_TankEntity(slot);
	if (tank == -1)
		return;
	float origin[3], distance;
	GetEntPropVector(tank, Prop_Data, "m_vecAbsOrigin", origin);
	for (int attempt = 0; attempt < SG_SEARCH_TRACES_PER_SENTRY && budget > 0
		&& SG_g_Sentries[slot].CandidateIndex < SG_g_Sentries[slot].CandidateCount; attempt++) {
		int index = SG_g_Sentries[slot].CandidateIndex++;
		int bot = GetClientOfUserId(SG_g_Sentries[slot].Candidates[index]);
		budget--;
		if (SG_VisibleBot(slot, bot, origin, distance)) {
			SG_g_Sentries[slot].CandidateCount = 0;
			SG_g_Sentries[slot].CandidateIndex = 0;
			SG_ActivateTarget(slot, bot);
			return;
		}
	}
	if (SG_g_Sentries[slot].CandidateIndex >= SG_g_Sentries[slot].CandidateCount)
		SG_g_Sentries[slot].NextSearch = GetGameTime() + SG_SEARCH_INTERVAL;
}

void SG_ActivateTarget(int slot, int target) {
	int tank = SG_TankEntity(slot);
	int owner = GetClientOfUserId(SG_g_Sentries[slot].Owner);
	if (tank == -1 || !owner)
		return;
	if (GetClientUserId(target) == SG_g_Sentries[slot].Target && SG_g_Sentries[slot].Active
		&& GetEntPropEnt(tank, Prop_Data, "m_hTarget") == target)
		return;
	SetVariantEntity(target);
	if (!AcceptEntityInput(tank, "SetTargetEntity", owner, owner)
		|| GetEntPropEnt(tank, Prop_Data, "m_hTarget") != target
		|| !AcceptEntityInput(tank, "Activate", owner, owner)) {
		SG_g_Sentries[slot].Enabled = false;
		SG_StopTank(slot);
		PrintToChat(owner, "[Sentry Gun] Native target assignment or activation failed. Stopped.");
		return;
	}
	SG_g_Sentries[slot].Target = GetClientUserId(target);
	SG_g_Sentries[slot].Active = true;
}

public void SG_OnTankFire(const char[] output, int caller, int activator, float delay) {
	int slot = SG_EntitySlot(caller);
	if (!slot || caller != SG_TankEntity(slot))
		return;
	SG_g_Sentries[slot].FireOutputs++;
	float now = GetGameTime();
	if (!SG_g_Sentries[slot].Enabled || !SG_g_Sentries[slot].Active || now < SG_g_Sentries[slot].NextShot)
		return;
	SG_g_Sentries[slot].NextShot = now + SG_g_ShotInterval;
	DataPack shot = new DataPack();
	shot.WriteCell(slot);
	shot.WriteCell(SG_g_Sentries[slot].Tank);
	shot.WriteCell(SG_g_Sentries[slot].ShotEpoch);
	shot.WriteCell(SG_g_Sentries[slot].Owner);
	shot.WriteCell(SG_g_Sentries[slot].Target);
	// Apply damage after the native output stack has returned.
	RequestFrame(SG_Frame_FireShot, shot);
}

public void SG_Frame_FireShot(DataPack shot) {
	shot.Reset();
	int slot = shot.ReadCell();
	int reference = shot.ReadCell();
	int epoch = shot.ReadCell();
	int ownerId = shot.ReadCell();
	int targetId = shot.ReadCell();
	delete shot;
	int tank = SG_TankEntity(slot);
	int owner = GetClientOfUserId(ownerId);
	int visual = EntRefToEntIndex(SG_g_Sentries[slot].Visual);
	if (tank == -1 || reference != SG_g_Sentries[slot].Tank || epoch != SG_g_Sentries[slot].ShotEpoch || !SG_g_Sentries[slot].Enabled || !SG_g_Sentries[slot].Active
		|| visual <= MaxClients || !IsValidEntity(visual)
		|| ownerId != SG_g_Sentries[slot].Owner || targetId != SG_g_Sentries[slot].Target || !owner || !IsClientInGame(owner)
		|| GetClientTeam(owner) != SG_g_Sentries[slot].Team || !SG_IsEnemyBot(slot, GetClientOfUserId(targetId)))
		return;
	float origin[3], angles[3], direction[3], end[3], impact[3];
	GetEntPropVector(tank, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(tank, Prop_Data, "m_angAbsRotation", angles);
	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	for (int i = 0; i < 3; i++)
		end[i] = origin[i] + direction[i] * SG_g_Range;
	Handle trace = TR_TraceRayFilterEx(origin, end, MASK_SHOT, RayType_EndPoint, SG_TraceSight, slot);
	bool startSolid = TR_StartSolid(trace);
	bool didHit = TR_DidHit(trace);
	int hit = TR_GetEntityIndex(trace);
	TR_GetEndPosition(impact, trace);
	delete trace;
	// Native OnFire can arrive while traversing; only fire once the barrel reaches its target.
	if (startSolid || !didHit || hit != GetClientOfUserId(targetId))
		return;
	SG_g_Sentries[slot].ScriptShots++;
	float muzzleOrigin[3], muzzleAngles[3];
	SG_GetMuzzleTransform(slot, origin, direction, muzzleOrigin, muzzleAngles);
	SG_EmitMuzzleFlash(slot, tank, muzzleOrigin, muzzleAngles);
	SG_EmitShell(slot);
	float spread[3], effectDirection[3];
	MakeVectorFromPoints(muzzleOrigin, impact, effectDirection);
	if (NormalizeVector(effectDirection, effectDirection) < 0.001)
		for (int i = 0; i < 3; i++)
			effectDirection[i] = direction[i];
	// A player source lets the client attach effects to their matching held weapon.
	SDKCall(SG_g_TEFireBullets, visual, muzzleOrigin, effectDirection, spread, 1.0, SG_g_Sentries[slot].WeaponDefinition, SG_g_Sentries[slot].Ammo, 0, GetURandomInt() & 0xFF);
	SG_g_Sentries[slot].BulletEffects++;
	if (SG_g_TracerReady && SG_g_TracerEvery > 0 && SG_g_Sentries[slot].ScriptShots % SG_g_TracerEvery == 0) {
		// Share the flash origin and retain the actual damage trace endpoint.
		SDKCall(SG_g_ParticleTracer, SG_TRACER_PARTICLE, muzzleOrigin, impact, tank, -1, false);
		SG_g_Sentries[slot].TracerCalls++;
	}
	if (SG_g_ShotSound[0]) {
		int clients[MAXPLAYERS];
		int count = GetClientsInRange(muzzleOrigin, RangeType_Audibility, clients, sizeof(clients));
		if (count > 0)
			EmitSound(clients, count, SG_g_ShotSound, visual, SNDCHAN_STATIC, SG_g_SoundLevel, SND_NOFLAGS,
				SG_g_SoundVolume, SG_g_SoundPitch, -1, muzzleOrigin, NULL_VECTOR, false);
	}
	if (!didHit || !SG_IsEnemyBot(slot, hit))
		return;
	SG_g_Sentries[slot].BotImpacts++;
	float force[3];
	for (int i = 0; i < 3; i++)
		force[i] = direction[i] * 100.0;
	// The ray stops at the first obstruction; damage has no penetration or hitgroup multiplier.
	SDKHooks_TakeDamage(hit, tank, owner, float(SG_g_Damage), DMG_BULLET, -1, force, impact, false);
}

int SG_DamageSentry(int attacker, int inflictor) {
	int slot = SG_EntitySlot(inflictor);
	if (slot && SG_TankEntity(slot) == inflictor)
		return slot;
	slot = SG_EntitySlot(attacker);
	return slot && SG_TankEntity(slot) == attacker ? slot : 0;
}

Action SG_FilterBotDamage(int victim, int attacker, int inflictor) {
	int slot = SG_DamageSentry(attacker, inflictor);
	if (slot && (!SG_g_Sentries[slot].Enabled || !SG_IsEnemyBot(slot, victim)))
		return Plugin_Handled;
	return Plugin_Continue;
}




bool SG_SpawnTank(int client, const float ground[3], float yaw) {
	int slot = client;
	float position[3], angles[3];
	position = ground;
	position[2] += SG_SENTRY_PIVOT_HEIGHT;
	angles[1] = yaw;
	char model[PLATFORM_MAX_PATH];
	strcopy(model, sizeof(model), SG_SENTRY_GUN_MODEL);
	int tank = CreateEntityByName("func_tank");
	if (tank == -1) {
		ReplyToCommand(client, "[Sentry Gun] This server could not create func_tank.");
		return false;
	}
	SG_RegisterSentryEntity(slot, tank);
	SG_g_SentryCount++;
	SG_g_Sentries[slot].Tank = EntIndexToEntRef(tank);
	DispatchKeyValue(tank, "model", model);
	char tankName[64];
	Format(tankName, sizeof(tankName), "bm_props_sentry_%d", GetClientUserId(client));
	DispatchKeyValue(tank, "targetname", tankName);
	DispatchKeyValue(tank, "spawnflags", "32784");
	DispatchKeyValue(tank, "bullet", "0");
	DispatchKeyValue(tank, "firespread", "0");
	DispatchKeyValue(tank, "ammo_count", "-1");
	DispatchKeyValueFloat(tank, "bullet_damage", float(SG_g_Damage));
	DispatchKeyValueFloat(tank, "bullet_damage_vs_player", float(SG_g_Damage));
	DispatchKeyValue(tank, "barrel", "0");
	DispatchKeyValue(tank, "barrely", "0");
	DispatchKeyValue(tank, "barrelz", "0");
	DispatchKeyValue(tank, "persistence", "0");
	DispatchKeyValue(tank, "persistence2", "0");
	DispatchKeyValueFloat(tank, "yawrate", SG_g_TurnSpeed);
	DispatchKeyValueFloat(tank, "pitchrate", SG_g_TurnSpeed);
	DispatchKeyValue(tank, "yawrange", "180");
	DispatchKeyValue(tank, "pitchrange", "80");
	DispatchKeyValue(tank, "yawtolerance", "3");
	DispatchKeyValue(tank, "pitchtolerance", "3");
	DispatchKeyValue(tank, "minRange", "64");
	DispatchKeyValueFloat(tank, "maxRange", SG_g_Range);
	DispatchKeyValueFloat(tank, "firerate", SG_g_FireRate);
	TeleportEntity(tank, position, angles, NULL_VECTOR);
	if (!DispatchSpawn(tank) || !IsValidEntity(tank)) {
		SG_RemoveTank(slot);
		ReplyToCommand(client, "[Sentry Gun] Native spawn failed.");
		return false;
	}
	char fields[][] = {"m_iSmallAmmoType", "m_iMediumAmmoType", "m_iLargeAmmoType", "m_iBulletDamageVsPlayer", "m_hTarget", "m_vecAngVelocity", "m_yawRate", "m_pitchRate"};
	for (int i = 0; i < sizeof(fields); i++) {
		if (!HasEntProp(tank, Prop_Data, fields[i])) {
			ReplyToCommand(client, "[Sentry Gun] Required datamap field missing: %s. Removed.", fields[i]);
			SG_RemoveTank(slot);
			return false;
		}
	}
	for (int i = 0; i < 3; i++)
		SG_g_Sentries[slot].OriginalAmmo[i] = GetEntProp(tank, Prop_Data, fields[i]);
	// CBaseEntity::FireBullets is empty in this build; native bullets stay disabled.
	SetEntProp(tank, Prop_Data, "m_iBulletDamageVsPlayer", SG_g_Damage);
	SetEntProp(tank, Prop_Send, "m_fEffects", GetEntProp(tank, Prop_Send, "m_fEffects") | 32);
	SetEntProp(tank, Prop_Send, "m_nSolidType", 0);
	SetEntProp(tank, Prop_Send, "m_usSolidFlags", GetEntProp(tank, Prop_Send, "m_usSolidFlags") | 4);
	SetEntProp(tank, Prop_Send, "m_iTeamNum", GetClientTeam(client));
	bool inputs = AcceptEntityInput(tank, "StopFindingNPCs");
	SetVariantFloat(SG_g_FireRate);
	inputs = AcceptEntityInput(tank, "SetFireRate") && inputs;
	SetVariantFloat(SG_g_Range);
	inputs = AcceptEntityInput(tank, "SetMaxRange") && inputs;
	SetVariantInt(SG_g_Damage);
	inputs = AcceptEntityInput(tank, "SetDamage") && inputs;
	inputs = AcceptEntityInput(tank, "Deactivate") && inputs;
	if (!inputs) {
		SG_RemoveTank(slot);
		ReplyToCommand(client, "[Sentry Gun] A required native configuration input failed. Removed.");
		return false;
	}
	if (!SG_CreateSentryMount(slot, position, angles)) {
		SG_RemoveTank(slot);
		ReplyToCommand(client, "[Sentry Gun] Could not create the sentry base or cradle. Removed.");
		return false;
	}
	if (!SG_CreateTurretWeapon(slot, tank, position, angles, model)) {
		SG_RemoveTank(slot);
		ReplyToCommand(client, "[Sentry Gun] Could not create or mount the native M249. Removed; check server errors.");
		return false;
	}
	SG_g_Sentries[slot].Removing = false;
	SG_g_Sentries[slot].BlastTick = -1;
	SG_g_Sentries[slot].Owner = GetClientUserId(client);
	SG_g_Sentries[slot].Team = GetClientTeam(client);
	SG_PrepareShotSound();
	SG_PrepareTracer();
	SG_PrepareMuzzleFlash(slot);
	SG_PrepareShellEjection(slot);

	SG_g_Sentries[slot].FireOutputs = 0;
	SG_g_Sentries[slot].DamageEvents = 0;
	SG_g_Sentries[slot].Kills = 0;
	SG_g_Sentries[slot].ScriptShots = 0;
	SG_g_Sentries[slot].BotImpacts = 0;
	SG_g_Sentries[slot].BulletEffects = 0;
	SG_g_Sentries[slot].TracerCalls = 0;
	SG_g_Sentries[slot].ShotEpoch++;
	SG_g_Sentries[slot].NextShot = 0.0;
	SG_g_Sentries[slot].Target = 0;
	SG_g_Sentries[slot].PinnedTarget = 0;
	SG_g_Sentries[slot].Enabled = false;
	SG_g_Sentries[slot].Active = false;
	SG_g_Sentries[slot].NextReport = 0.0;
	SG_g_Sentries[slot].NextUpdate = GetGameTime() + SG_UPDATE_INTERVAL * float(slot % SG_MAX_SENTRIES) / float(SG_MAX_SENTRIES);
	return true;
}

#include <props_sentry_bots>
