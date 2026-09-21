// Native bot aim/fire integration from sentry_bot_test v1.0.5, Nullifidian, OpenAI.
#define SGB_UPDATES_PER_FRAME 4
#define SGB_UPDATE_INTERVAL 0.1
#define SGB_SEARCH_INTERVAL 0.5
#define SGB_AIM_DOT 0.9995
#define SGB_BTN_ATTACK1 (1 << 0)
#define SGB_BTN_RELOAD (1 << 11)

enum struct SGB_BotState {
	int UserId;
	int Layout;
	int Slot;
	int TargetRef;
	int WeaponRef;
	int ReloadRef;
	int SearchCursor;
	bool WeaponAllowed;
	bool ReloadSupported;
	PropType ReloadType;
	bool Pressing;
	bool AllowFire;
	float NextUpdate;
	float LastCheck;
	float NextReload;
	float AimPoint[3];
}

SGB_BotState SGB_Bots[MAXPLAYERS + 1];
bool SGB_Ready;
int SGB_Cursor;
Handle SGB_GetBody, SGB_Aim, SGB_AimReady, SGB_PressFire, SGB_ReleaseFire, SGB_CanAttack;
Address SGB_GetBodyAddress, SGB_AimAddress, SGB_AimReadyAddress, SGB_PressAddress, SGB_ReleaseAddress;
int SGB_NextBotOffset, SGB_InputOffset, SGB_GetBodySlot, SGB_AimSlot, SGB_ReadySlot;

bool SGB_ValidBot(int bot) {
	return bot > 0 && bot <= MaxClients && IsClientInGame(bot) && IsFakeClient(bot)
		&& IsPlayerAlive(bot) && GetClientTeam(bot) >= 2;
}

void SGB_Release(int bot) {
	SGB_Bots[bot].AllowFire = false;
	SGB_Bots[bot].ReloadRef = INVALID_ENT_REFERENCE;
	if (SGB_Bots[bot].Pressing && SGB_Ready && SGB_Bots[bot].Layout == 1
		&& IsClientInGame(bot) && GetClientUserId(bot) == SGB_Bots[bot].UserId)
		SDKCall(SGB_ReleaseFire, SGB_InputObject(bot));
	SGB_Bots[bot].Pressing = false;
}

void SGB_DropTarget(int bot) {
	SGB_Release(bot);
	SGB_Bots[bot].Slot = 0;
	SGB_Bots[bot].TargetRef = INVALID_ENT_REFERENCE;
	SGB_Bots[bot].NextUpdate = GetGameTime() + SGB_SEARCH_INTERVAL;
}

void SGB_ResetClient(int bot) {
	SGB_Release(bot);
	SGB_BotState empty;
	SGB_Bots[bot] = empty;
	SGB_Bots[bot].TargetRef = INVALID_ENT_REFERENCE;
	SGB_Bots[bot].WeaponRef = INVALID_ENT_REFERENCE;
	SGB_Bots[bot].ReloadRef = INVALID_ENT_REFERENCE;
	SGB_Bots[bot].SearchCursor = bot % MaxClients;
	SGB_Bots[bot].NextUpdate = GetGameTime() + float(bot % 10) * 0.01;
}

void SGB_ResetAll() {
	for (int bot = 1; bot <= MaxClients; bot++)
		SGB_ResetClient(bot);
	SGB_Cursor = 0;
}

void SGB_RecheckSettings() {
	float now = GetGameTime();
	for (int bot = 1; bot <= MaxClients; bot++) {
		SGB_DropTarget(bot);
		SGB_Bots[bot].NextUpdate = now + float(bot % 10) * 0.01;
	}
}

void SGB_RemoveTarget(int slot) {
	for (int bot = 1; bot <= MaxClients; bot++)
		if (SGB_Bots[bot].Slot == slot)
			SGB_DropTarget(bot);
}

void SGB_CacheWeapon(int bot, int weapon) {
	SGB_Release(bot);
	SGB_Bots[bot].WeaponRef = INVALID_ENT_REFERENCE;
	SGB_Bots[bot].WeaponAllowed = false;
	SGB_Bots[bot].ReloadSupported = false;
	SGB_Bots[bot].ReloadType = Prop_Send;
	SGB_Bots[bot].NextReload = 0.0;
	if (weapon <= MaxClients || !IsValidEntity(weapon))
		return;
	SGB_Bots[bot].WeaponRef = EntIndexToEntRef(weapon);
	SGB_Bots[bot].WeaponAllowed = HasEntProp(weapon, Prop_Send, "m_iClip1")
		&& (GetPlayerWeaponSlot(bot, 0) == weapon || GetPlayerWeaponSlot(bot, 1) == weapon);
	if (HasEntProp(weapon, Prop_Send, "m_bInReload"))
		SGB_Bots[bot].ReloadSupported = true;
	else if (HasEntProp(weapon, Prop_Data, "m_bInReload")) {
		SGB_Bots[bot].ReloadSupported = true;
		SGB_Bots[bot].ReloadType = Prop_Data;
	}
}

void SGB_WeaponDeploy(int bot) {
	if (!SGB_Ready || !SG_g_BotAttackEnabled || !SGB_ValidBot(bot))
		return;
	SGB_DropTarget(bot);
	SGB_CacheWeapon(bot, -1);
	// Resolve the new active weapon after deployment has completed.
	RequestFrame(SGB_DeployFrame, GetClientUserId(bot));
}

public void SGB_DeployFrame(any userId) {
	int bot = GetClientOfUserId(userId);
	if (SGB_ValidBot(bot))
		SGB_CacheWeapon(bot, GetEntPropEnt(bot, Prop_Send, "m_hActiveWeapon"));
}

public void SGB_FireOnEmpty(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("userid"));
	if (!SGB_ControlsBot(bot) || !SGB_Bots[bot].WeaponAllowed)
		return;
	int weapon = GetEntPropEnt(bot, Prop_Send, "m_hActiveWeapon");
	if (weapon <= MaxClients || !IsValidEntity(weapon)
		|| EntIndexToEntRef(weapon) != SGB_Bots[bot].WeaponRef
		|| GetEntProp(weapon, Prop_Send, "m_iClip1") > 0)
		return;
	SGB_Release(bot);
	if (GetGameTime() >= SGB_Bots[bot].NextReload && !SGB_WeaponReloading(bot, weapon))
		SGB_Bots[bot].ReloadRef = SGB_Bots[bot].WeaponRef;
}

bool SGB_TargetValid(int bot, int slot) {
	return slot > 0 && slot <= MaxClients && SG_g_Sentries[slot].Enabled
		&& !SG_g_Sentries[slot].Removing && SG_g_Sentries[slot].Team != GetClientTeam(bot)
		&& EntRefToEntIndex(SG_g_Sentries[slot].SentryBase) > MaxClients;
}

bool SGB_ControlsBot(int bot) {
	if (!SGB_Ready || !SG_g_BotAttackEnabled || !SG_g_SentryCount || bot < 1 || bot > MaxClients || !SGB_Bots[bot].Slot || !SGB_ValidBot(bot))
		return false;
	int slot = SGB_Bots[bot].Slot;
	return SGB_Bots[bot].UserId == GetClientUserId(bot) && SGB_TargetValid(bot, slot)
		&& SGB_Bots[bot].TargetRef == SG_g_Sentries[slot].SentryBase
		&& GetGameTime() - SGB_Bots[bot].LastCheck <= 0.2;
}

public any SGB_NativeControlsBot(Handle plugin, int numParams) {
	return SGB_ControlsBot(GetNativeCell(1));
}

public bool SGB_TraceSight(int entity, int mask, any bot) {
	return entity != bot;
}

bool SGB_Facing(int bot, const float angles[3]) {
	float eye[3], direction[3], facing[3];
	GetClientEyePosition(bot, eye);
	MakeVectorFromPoints(eye, SGB_Bots[bot].AimPoint, direction);
	NormalizeVector(direction, direction);
	GetAngleVectors(angles, facing, NULL_VECTOR, NULL_VECTOR);
	return GetVectorDotProduct(direction, facing) >= SGB_AIM_DOT;
}

void SGB_OnGameFrame() {
	if (!SGB_Ready || !SG_g_BotAttackEnabled || !SG_g_SentryCount)
		return;
	float now = GetGameTime();
	int budget = SGB_UPDATES_PER_FRAME;
	int start = SGB_Cursor;
	for (int offset = 0; offset < MaxClients && budget > 0; offset++) {
		int bot = (start + offset) % MaxClients + 1;
		if (now < SGB_Bots[bot].NextUpdate || !SGB_ValidBot(bot))
			continue;
		SGB_Update(bot, now);
		SGB_Cursor = bot;
		budget--;
	}
}

void SGB_Update(int bot, float now) {
	if (SGB_Bots[bot].UserId != GetClientUserId(bot)) {
		SGB_ResetClient(bot);
		SGB_Bots[bot].UserId = GetClientUserId(bot);
	}
	SGB_Bots[bot].NextUpdate = now + SGB_SEARCH_INTERVAL;
	if (SGB_Bots[bot].Layout < 0)
		return;
	int weapon = GetEntPropEnt(bot, Prop_Send, "m_hActiveWeapon");
	int weaponRef = weapon > MaxClients && IsValidEntity(weapon) ? EntIndexToEntRef(weapon) : INVALID_ENT_REFERENCE;
	if (weaponRef != SGB_Bots[bot].WeaponRef)
		SGB_CacheWeapon(bot, weapon);
	if (weaponRef == INVALID_ENT_REFERENCE || !SGB_Bots[bot].WeaponAllowed) {
		SGB_DropTarget(bot);
		return;
	}
	float eye[3], point[3];
	GetClientEyePosition(bot, eye);
	int slot = SGB_Bots[bot].Slot;
	if (slot && (!SGB_TargetValid(bot, slot) || SGB_Bots[bot].TargetRef != SG_g_Sentries[slot].SentryBase)) {
		SGB_DropTarget(bot);
		slot = 0;
	}
	if (!slot) {
		for (int offset = 0; offset < MaxClients; offset++) {
			int candidate = (SGB_Bots[bot].SearchCursor + offset) % MaxClients + 1;
			if (!SGB_TargetValid(bot, candidate))
				continue;
			GetEntPropVector(EntRefToEntIndex(SG_g_Sentries[candidate].SentryBase), Prop_Data, "m_vecAbsOrigin", point);
			point[2] += 8.0;
			if (GetVectorDistance(eye, point, true) > SG_g_BotRangeSquared)
				continue;
			slot = candidate;
			SGB_Bots[bot].SearchCursor = candidate;
			break;
		}
		if (!slot)
			return;
	} else {
		GetEntPropVector(EntRefToEntIndex(SGB_Bots[bot].TargetRef), Prop_Data, "m_vecAbsOrigin", point);
		point[2] += 8.0;
	}
	if (GetVectorDistance(eye, point, true) > SG_g_BotRangeSquared) {
		SGB_DropTarget(bot);
		return;
	}
	Handle trace = TR_TraceRayFilterEx(eye, point, MASK_SHOT, RayType_EndPoint, SGB_TraceSight, bot);
	bool visible = !TR_StartSolid(trace) && TR_DidHit(trace) && SG_EntitySlot(TR_GetEntityIndex(trace)) == slot;
	delete trace;
	if (!visible) {
		SGB_DropTarget(bot);
		return;
	}
	Address body;
	if (!SGB_ValidateBotLayout(bot, body)) {
		SGB_Bots[bot].Layout = -1;
		SGB_DropTarget(bot);
		return;
	}
	SGB_Bots[bot].Layout = 1;
	SGB_Bots[bot].Slot = slot;
	SGB_Bots[bot].TargetRef = SG_g_Sentries[slot].SentryBase;
	SGB_Bots[bot].AimPoint = point;
	SGB_Bots[bot].LastCheck = now;
	SGB_Bots[bot].NextUpdate = now + SGB_UPDATE_INTERVAL;
	SGB_Bots[bot].AllowFire = false;
	SGB_Bots[bot].ReloadRef = INVALID_ENT_REFERENCE;
	if (SGB_WeaponReloading(bot, weapon)) {
		SGB_Release(bot);
		return;
	}
	if (GetEntProp(weapon, Prop_Send, "m_iClip1") <= 0) {
		SGB_Release(bot);
		if (now >= SGB_Bots[bot].NextReload)
			SGB_Bots[bot].ReloadRef = weaponRef;
		return;
	}
	SDKCall(SGB_Aim, body, point, 4, 0.25, 0, 0);
	float angles[3];
	GetClientEyeAngles(bot, angles);
	if (!SDKCall(SGB_AimReady, body) || !SGB_Facing(bot, angles) || !SDKCall(SGB_CanAttack, bot)) {
		SGB_Release(bot);
		return;
	}
	SDKCall(SGB_PressFire, SGB_InputObject(bot), 0.12);
	SGB_Bots[bot].Pressing = SGB_Bots[bot].AllowFire = true;
}

Action SGB_RunCmd(int bot, int &buttons, const float angles[3]) {
	if (!SGB_Bots[bot].Slot)
		return Plugin_Continue;
	if (!SGB_ControlsBot(bot)) {
		SGB_DropTarget(bot);
		buttons &= ~SGB_BTN_ATTACK1;
		return Plugin_Changed;
	}
	int weapon = GetEntPropEnt(bot, Prop_Send, "m_hActiveWeapon");
	if (weapon <= MaxClients || !IsValidEntity(weapon) || EntIndexToEntRef(weapon) != SGB_Bots[bot].WeaponRef) {
		SGB_DropTarget(bot);
		buttons &= ~SGB_BTN_ATTACK1;
		return Plugin_Changed;
	}
	if ((buttons & SGB_BTN_ATTACK1) && (!SGB_Bots[bot].AllowFire || !SGB_Facing(bot, angles) || GetEntProp(weapon, Prop_Send, "m_iClip1") <= 0))
		buttons &= ~SGB_BTN_ATTACK1;
	if (SGB_Bots[bot].ReloadRef != INVALID_ENT_REFERENCE) {
		int reference = SGB_Bots[bot].ReloadRef;
		SGB_Bots[bot].ReloadRef = INVALID_ENT_REFERENCE;
		if (reference == SGB_Bots[bot].WeaponRef && GetEntProp(weapon, Prop_Send, "m_iClip1") <= 0 && !SGB_WeaponReloading(bot, weapon)) {
			buttons = (buttons & ~SGB_BTN_ATTACK1) | SGB_BTN_RELOAD;
			SGB_Bots[bot].NextReload = GetGameTime() + 1.0;
		}
	}
	return Plugin_Changed;
}

bool SGB_Prepare() {
	GameData config = new GameData(SG_GAMEDATA_FILE);
	if (config == null) {
		LogError("Sentry bot attacks disabled: missing %s.txt", SG_GAMEDATA_FILE);
		return false;
	}
	SGB_NextBotOffset = config.GetOffset("SentryBotTest::NextBotOffset");
	SGB_InputOffset = config.GetOffset("SentryBotTest::InputOffset");
	SGB_GetBodySlot = config.GetOffset("SentryBotTest::BodyGetterSlot");
	SGB_AimSlot = config.GetOffset("SentryBotTest::AimPositionSlot");
	SGB_ReadySlot = config.GetOffset("SentryBotTest::AimReadySlot");
	SGB_GetBodyAddress = config.GetMemSig("CINSNextBot::GetBodyInterface");
	SGB_AimAddress = config.GetMemSig("PlayerBody::AimHeadTowardsPosition");
	SGB_AimReadyAddress = config.GetMemSig("PlayerBody::IsHeadAimingOnTarget");
	SGB_PressAddress = config.GetMemSig("NextBotPlayer<CINSPlayer>::PressFireButton");
	SGB_ReleaseAddress = config.GetMemSig("NextBotPlayer<CINSPlayer>::ReleaseFireButton");
	Address canAttack = config.GetMemSig("CINSNextBot::CanIAttack");
	if (SGB_NextBotOffset < 0
		|| SGB_InputOffset < 0
		|| SGB_GetBodySlot < 0
		|| SGB_AimSlot < 0
		|| SGB_ReadySlot < 0
		|| SGB_GetBodyAddress == Address_Null
		|| SGB_AimAddress == Address_Null
		|| SGB_AimReadyAddress == Address_Null
		|| SGB_PressAddress == Address_Null
		|| SGB_ReleaseAddress == Address_Null
		|| canAttack == Address_Null) {
		LogError("Sentry bot attacks disabled: install shared gamedata with the tested sentry bot signatures/offsets.");
		delete config;
		return false;
	}
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetAddress(SGB_GetBodyAddress);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	SGB_GetBody = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetAddress(SGB_AimAddress);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	SGB_Aim = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetAddress(SGB_AimReadyAddress);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	SGB_AimReady = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetAddress(SGB_PressAddress);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	SGB_PressFire = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetAddress(SGB_ReleaseAddress);
	SGB_ReleaseFire = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetAddress(canAttack);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	SGB_CanAttack = EndPrepSDKCall();
	delete config;
	bool ready = SGB_GetBody != null && SGB_Aim != null && SGB_AimReady != null
		&& SGB_PressFire != null && SGB_ReleaseFire != null && SGB_CanAttack != null;
	if (!ready)
		LogError("Sentry bot attacks disabled: SDKCall preparation failed.");
	return ready;
}

Address SGB_VFunction(Address instance, int slot) {
	if (instance == Address_Null)
		return Address_Null;
	Address table = view_as<Address>(LoadFromAddress(instance, NumberType_Int32));
	if (table == Address_Null)
		return Address_Null;
	return view_as<Address>(LoadFromAddress(table + view_as<Address>(slot * 4), NumberType_Int32));
}

Address SGB_InputObject(int bot) {
	return GetEntityAddress(bot) + view_as<Address>(SGB_InputOffset);
}

bool SGB_ValidateBotLayout(int bot, Address &body) {
	Address entity = GetEntityAddress(bot);
	Address nextBot = entity + view_as<Address>(SGB_NextBotOffset);
	Address input = entity + view_as<Address>(SGB_InputOffset);
	if (SGB_VFunction(nextBot, SGB_GetBodySlot) != SGB_GetBodyAddress || SGB_VFunction(input, 0) != SGB_PressAddress || SGB_VFunction(input, 1) != SGB_ReleaseAddress) {
		LogError("Sentry bot: bot %d has an unexpected NextBot/input vtable. Check gamedata and server binary version.", bot);
		return false;
	}
	body = view_as<Address>(SDKCall(SGB_GetBody, nextBot));
	if (body == Address_Null) {
		LogError("Sentry bot v%s: bot %d body getter returned NULL (getter=0x%08X slot=%d).", "3.79.0", bot, SGB_GetBodyAddress, SGB_GetBodySlot);
		return false;
	}
	Address actualAim = SGB_VFunction(body, SGB_AimSlot);
	Address actualReady = SGB_VFunction(body, SGB_ReadySlot);
	if (actualAim != SGB_AimAddress || actualReady != SGB_AimReadyAddress) {
		LogError("Sentry bot v%s: bot %d body=0x%08X getter=0x%08X slot=%d; aim[%d]=0x%08X expected=0x%08X; ready[%d]=0x%08X expected=0x%08X. Install matching plugin/gamedata and restart server.", "3.79.0", bot, body, SGB_GetBodyAddress, SGB_GetBodySlot, SGB_AimSlot, actualAim, SGB_AimAddress, SGB_ReadySlot, actualReady, SGB_AimReadyAddress);
		return false;
	}
	return true;
}

bool SGB_WeaponReloading(int bot, int weapon) {
	return SGB_Bots[bot].ReloadSupported && GetEntProp(weapon, SGB_Bots[bot].ReloadType, "m_bInReload") != 0;
}

