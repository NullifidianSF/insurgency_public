#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>

native bool Drag_IsEntityDragged(int entity);
native void Drag_ForceDrop(int entity);
native bool ChatFilter_BypassNextMessage(int client, const char[] expectedMessage);
native bool InsItems_IsAFFBlocking(int victim, int attacker);
Handle	g_hFwdRagdollReady = null;

#define TEAM_SPECTATOR	1
#define TEAM_SECURITY	2
#define TEAM_INSURGENT	3

// ---- Objective Resource access (read-only) ----
static int  g_iObjResEntity = -1;
static char g_sObjResNetClass[32];

//LUA Healing define values
#define Healthkit_Timer_Tickrate			0.5		// Basic Sound has 0.5 loop
#define Healthkit_Timer_Timeout				300.0	// 5 minutes
#define Healthkit_Radius					120.0
#define Revive_Indicator_Radius				100.0
#define SND_REVIVENOTIFY		"cues/nwi2_generic4.wav"
#define BLEEDOUT_TREAT_TICK		0.5
#define BLEEDOUT_SAME_HIT_GRACE	0.05
#define BLEEDOUT_TRACE_MAX_AGE	0.05
#define BLEED_PARTICLE_REFRESH_TIME	2.0
#define BLEEDOUT_CALL_SOUND		"player/voice/responses/security/subordinate/unsuppressed/wounded5.ogg"
#define BLEEDOUT_CALL_DELAY		1.0
#define BLEED_FADE_IN			0x0001
#define BLEEDOUT_MARKER_MODEL	"materials/medic/tourniquet_marker.vmt"		// https://steamcommunity.com/sharedfiles/filedetails/?id=3774574642
#define BLEEDOUT_MARKER_MIN_SCALE	0.035
#define BLEEDOUT_MARKER_MAX_SCALE	0.080
#define BLEEDOUT_MARKER_MIN_DISTANCE	196.0
#define BLEEDOUT_MARKER_MAX_DISTANCE	1575.0
#define BLEEDOUT_MARKER_ALPHA	"200"
#define BLEEDOUT_MARKER_BACK_OFFSET	-10.0
#define BLEEDOUT_MARKER_STAND_HEIGHT	94.0
#define BLEEDOUT_MARKER_CROUCH_HEIGHT	76.0
#define BLEEDOUT_MARKER_PRONE_HEIGHT	50.0
#define BLEEDOUT_MARKER_NAME		"medic_bleed_marker_"

#define HITGROUP_LEFTARM		4
#define HITGROUP_RIGHTARM		5
#define HITGROUP_LEFTLEG		6
#define HITGROUP_RIGHTLEG		7

#define MEDIC_CLASS_SLOT_1		6
#define MEDIC_CLASS_SLOT_2		14

#define MAX_ENTITIES 2048

enum BleedoutDeathReason {
	BleedoutDeath_None = 0,
	BleedoutDeath_Timeout,
	BleedoutDeath_SecondHit
};

enum TourniquetApplyResult {
	TourniquetApply_Progress = 0,
	TourniquetApply_Completed,
	TourniquetApply_Busy,
	TourniquetApply_NoKitUse
};

// Chat command anti-spam
#define MEDIC_CMD_COOLDOWN 10.0

static const char g_sAutoThanksMessages[][] = {
	"Thanks for the revive, %N!",
	"I owe you one, %N!",
	"Nice save, %N!",
	"Appreciate it, %N!",
	"You got me back in the fight, %N!",
	"That was close, thanks, %N!",
	"You're a lifesaver, %N!",
	"Great work, %N!",
	"I knew I could count on you, %N!",
	"Thanks, %N! Let's finish this.",
	"You're a legend, %N!",
	"Thanks, %N! I wasn't done yet.",
	"Perfect timing, %N!",
	"Thanks, %N! Now point me at the enemy.",
	"Thanks, %N! Time for some payback.",
	"Good save, %N! I have unfinished business.",
	"Thanks, %N! Death can wait.",
	"Nice one, %N! Let's ruin the enemy's plan.",
	"Thanks, %N! I'll try not to die again.",
	"Thanks, %N! The floor was getting cold.",
	"Thanks for getting me back on my feet, %N!",
	"Thanks for the express rescue, %N!",
	"You're a miracle worker, %N!",
	"Excellent timing, %N!",
	"Thanks, %N! My bullets missed me.",
	"Nap time is over, thanks, %N!",
	"Thanks, %N! My vacation on the floor is over.",
	"You cancelled my dirt nap, %N!",
	"Thanks for the express respawn, %N!",
	"Heartbeat restored, courtesy of %N!",
	"Back from the dead, thanks to %N!",
	"Thanks for patching me up, %N!",
	"I owe you a beer, %N!",
	"I owe you at least one supply point, %N!",
	"Rescue appreciated, %N!",
	"Someone promote %N for that revive!",
	"Congratulations, %N! You're my favorite teammate now.",
	"Reviving me was your best decision today, %N!",
	"Thanks, %N! I was one second from becoming a spectator.",
	"They celebrated too soon, thanks to %N!",
	"Thanks, %N! Revenge first, questions later.",
	"My gun missed me, thanks for the reunion, %N!",
	"Thanks, %N! I'm ready to fight again.",
	"Those paddles worked perfectly, %N!",
	"Thanks, %N! We just defied the statistics.",
	"Death rejected my application, thanks to %N!",
	"Grave reservation cancelled by %N!",
	"Thanks, %N! My body is still under warranty.",
	"Soul refund processed by %N!",
	"You're my hero for the next five minutes, %N!",
	"Take the credit, %N! You earned it.",
	"Thanks for setting up my dramatic entrance, %N!",
	"That death was just a warm-up, thanks, %N!",
	"Thanks, %N! The enemy now has extra paperwork.",
	"You gave me a second chance, %N!",
	"Thanks, %N! The chaos can continue.",
	"Funeral postponed by %N!",
	"Obituary cancelled, thanks, %N!",
	"The dirt can wait, %N!",
	"Thanks, %N! The enemy needs a status update.",
	"Thanks, %N! I'm alive enough.",
	"Let's never discuss this again, %N!",
	"One revive, one thank-you, %N!",
	"Thanks, %N! Revived and ready.",
	"That was a clutch revive, %N!",
	"I appreciate the rescue, %N!",
	"Flawless save, %N!",
	"I'm glad you're on my team, %N!",
	"I knew I was in good hands, %N!",
	"That revive was perfect, %N!",
	"You made my day, %N!",
	"Glad you were here, %N!",
	"This squad is lucky to have you, %N!",
	"That was an MVP moment, %N!",
	"Quick work, %N! Thank you.",
	"Rescue complete, thanks to %N!",
	"Thanks for the return ticket, %N!",
	"I'm back in action because of %N!",
	"Fully restored, thanks, %N!",
	"Reboot complete, courtesy of %N!",
	"Thanks, %N! You found the respawn button.",
	"Life support provided by %N!",
	"Another battlefield miracle by %N!",
	"Thanks, %N! Death is taking a timeout.",
	"Grave entry denied by %N!",
	"Tombstone refunded, thanks to %N!",
	"The afterlife sent me back with %N!",
	"My ghost shift ended early, thanks, %N!",
	"Corpse duty cancelled by %N!",
	"Thanks, %N! My relationship with the floor is over.",
	"Alive again, thanks to %N!",
	"Breathing restored by %N!",
	"Pulse restored, thanks, %N!",
	"You gave me a second wind, %N!",
	"Thanks, %N! I've rejoined the living.",
	"Unexpected sequel provided by %N!",
	"Round two begins, thanks to %N!",
	"Comeback activated by %N!",
	"Thanks for the encore, %N!",
	"Resurrection successful, %N!",
	"Thanks, %N! Spectator mode can wait.",
	"You got me back to my keyboard, %N!",
	"Thanks, %N! My mouse was getting lonely.",
	"You reunited me with my ammo, %N!",
	"Boots back on the ground, thanks to %N!",
	"The enemy is getting a surprise, thanks, %N!",
	"Tactical revival complete, %N!",
	"Operational again, thanks to %N!",
	"Combat ready, thanks, %N!",
	"The mission continues because of %N!",
	"Squad restored, thanks to %N!",
	"I've got your back, %N!",
	"I'll follow your lead, %N! Thanks.",
	"I'll repay that save, %N!",
	"I'll return the favour, %N!",
	"The team is stronger with you, %N!",
	"Thanks, %N! Let's keep moving.",
	"Let's push together, %N! Thanks.",
	"Back to the objective, thanks, %N!",
	"Let's win this, %N! Thanks for the revive.",
	"The enemy won't like this, thanks, %N!",
	"The enemy thought I was finished, thanks, %N!",
	"Their celebration was cancelled by %N!",
	"The enemy needs a new plan, thanks to %N!",
	"Reviving me was their problem, %N!",
	"The enemy is about to be confused, thanks, %N!",
	"Rematch accepted, thanks to %N!",
	"The enemy had such high hopes, %N! Thanks.",
	"Back to haunt the enemy, thanks, %N!",
	"Enemy paperwork increased by %N!",
	"Revenge delivery arranged by %N!",
	"Time for a return visit, thanks, %N!",
	"This fight is not over, thanks to %N!",
	"I've got a score to settle, thanks, %N!",
	"Surprise return sponsored by %N!",
	"What a plot twist, thanks, %N!",
	"You just changed the round, %N!",
	"The comeback tour starts with %N!",
	"Back for the final act, thanks, %N!",
	"The sequel starts now, courtesy of %N!",
	"Thanks, %N! I'll aim better this time.",
	"Thanks, %N! I'll try staying upright.",
	"I'll avoid the floor this time, %N!",
	"Helmet tightened, thanks, %N!",
	"Second life, better decisions, thanks, %N!",
	"I'll use this second life wisely, %N!",
	"No promises, but I'm grateful, %N!",
	"Still alive because of %N!",
	"My embarrassing death has been postponed by %N!",
	"Death speedrun failed, thanks, %N!",
	"You helped me skip the respawn queue, %N!",
	"Spectator ticket cancelled by %N!",
	"Loading screen avoided, thanks to %N!",
	"Death screen closed by %N!",
	"Redeployment complete, thanks, %N!",
	"Reboot successful, %N!",
	"Systems online, thanks to %N!",
	"Health restored, courtesy of %N!",
	"My legs work again, thanks, %N!",
	"Heartbeat reinstalled by %N!",
	"That is quality field medicine, %N!",
	"Medic magic confirmed, %N!",
	"You've got healing hands, %N!",
	"Five-star rescue service, %N!",
	"Fastest emergency response goes to %N!",
	"Special delivery: one revive from %N!",
	"Miracle delivered right on time, %N!",
	"Premium battlefield healthcare from %N!",
	"Best healthcare on the battlefield, %N!",
	"Top-class medic work, %N!",
	"Revive master at work, %N!",
	"Clutch specialist confirmed, %N!",
	"My guardian angel is called %N!",
	"Someone get %N a hero cape!",
	"Gold star for %N!",
	"Someone award %N a medal!",
	"Round of applause for %N!",
	"Salute to %N for the revive!",
	"Maximum respect, %N!",
	"All my gratitude goes to %N!",
	"Cheers for the revive, %N!",
	"Huge thanks, %N!",
	"Thank you kindly, %N!",
	"I really appreciate that, %N!",
	"Grateful for the save, %N!",
	"I owe you big time, %N!",
	"I won't forget that save, %N!",
	"You saved this round for me, %N!",
	"You saved my day, %N!",
	"You saved this run, %N!",
	"You kept the mission alive, %N!",
	"You kept hope alive, %N!",
	"You made the squad whole again, %N!",
	"Thanks for bringing your teammate back, %N!",
	"Happy to be back, thanks, %N!",
	"Ready to return the help, %N!",
	"Together again, thanks to %N!",
	"I'm alive because you cared, %N!",
	"That revive deserves another thank-you, %N!",
	"Final verdict: %N is a lifesaver!",
	"Thanks, %N! You saved me from taking a respawn screen to the knee.",
	"Fus Ro Revive! Thanks, %N!",
	"Thanks, %N! The cake can wait, we have a battle to finish.",
	"You are better than a Companion Cube, %N!",
	"Thanks, %N! Even a crowbar could not have fixed me that quickly.",
	"Revive here! Thanks, %N!",
	"Thanks, %N! I nearly missed the saferoom.",
	"Clutch revive, %N! That belongs in the highlight reel.",
	"Thanks, %N! That revive was faster than a five-second defuse.",
	"MEDIC! Oh, there you are, %N!",
	"Thanks, %N! I feel fully UberCharged.",
	"Thanks, %N! Back to ripping and tearing.",
	"Extra life acquired, thanks to %N!",
	"Thanks, %N! My bed was apparently obstructed.",
	"You work better than a Totem of Undying, %N!",
	"Thanks, %N! That revive cost fewer coins than the Nurse.",
	"You are my fairy in a bottle, %N!",
	"Thanks, %N! My heart containers are working again.",
	"One-Up delivered by %N!",
	"Thanks, %N! The revive was in this castle after all.",
	"Thanks, %N! I dropped all my rings for a second.",
	"I fainted, but %N used Revive!",
	"%N used Revive. It was super effective!",
	"Bonfire skipped, thanks to %N!",
	"Thanks, %N! The YOU DIED screen barely had time to load.",
	"Grace restored, courtesy of %N!",
	"Thanks, %N! I almost dropped my runes twice.",
	"That revive deserves a round of Gwent, %N!",
	"Even a Swallow potion could not beat that revive, %N!",
	"Commander %N has restored the squad!",
	"Thanks, %N! My shields are back online.",
	"Wake me when you need another teammate, %N!",
	"Thanks, %N! The whole COG squad would be proud.",
	"Stimpack efficiency: 100 percent. Thanks, %N!",
	"Thanks, %N! My Pip-Boy now says ALIVE.",
	"WASTED cancelled by %N!",
	"Redemption achieved, thanks to %N!",
	"Thanks, %N! Even Kratos would call that a worthy revive.",
	"Green herb energy restored by %N!",
	"Thanks, %N! The alert phase is over, but I am back.",
	"Second Heart activated by %N!",
	"Thanks, %N! My energy bar is ready for another day.",
	"Tom Nook cannot charge me for this revive, right, %N?",
	"Thanks, %N! I was not the impostor, just temporarily dead.",
	"Reboot card successfully collected by %N!",
	"Banner recovered, legend restored. Thanks, %N!",
	"Heroes apparently do not stay dead when %N is nearby!",
	"Guardian Angel activated by %N!",
	"Soulstone service provided by %N!",
	"Thanks, %N! That revive cleared my death screen like four perfect lines."
};

// ----------------------------------------------------------------------
// ConVars + cached values
// ----------------------------------------------------------------------
ConVar	g_cvReviveEnabled = null;
bool	g_bReviveEnabled;

ConVar	g_cvAutoThanksEnabled = null;
bool	g_bAutoThanksEnabled;

ConVar	g_cvFatalChance = null;
float	g_fFatalChance;

ConVar	g_cvFatalHeadChance = null;
float	g_fFatalHeadChance;

ConVar	g_cvFatalLimbDmg = null;
int		g_iFatalLimbDmg;

ConVar	g_cvFatalHeadDmg = null;
int		g_iFatalHeadDmg;

ConVar	g_cvFatalBurnDmg = null;
int		g_iFatalBurnDmg;

ConVar	g_cvFatalExplosiveDmg = null;
int		g_iFatalExplosiveDmg;

ConVar	g_cvFatalChestStomach = null;
int		g_iFatalChestStomach;

ConVar	g_cvBleedoutEnabled = null;
bool	g_bBleedoutEnabled;

ConVar	g_cvBleedoutChance = null;
float	g_fBleedoutChance;

ConVar	g_cvBleedoutTime = null;
float	g_fBleedoutTime;

ConVar	g_cvTourniquetMedicTime = null;
float	g_fTourniquetMedicTime;

ConVar	g_cvTourniquetNonMedicTime = null;
float	g_fTourniquetNonMedicTime;

ConVar	g_cvBleedoutPuddleLifetime = null;
float	g_fBleedoutPuddleLifetime;

ConVar	g_cvBleedoutFadeEnabled = null;
bool	g_bBleedoutFadeEnabled;

ConVar	g_cvBleedoutFadeAlpha = null;
int		g_iBleedoutFadeAlpha;

ConVar	g_cvReviveDistanceMetric = null;
bool	g_bDistanceFeet;	// true = feet, false = meters

ConVar	g_cvHealAmountMedpack = null;
int		g_iHealAmountMedpack;

ConVar	g_cvHealAmountPaddles = null;
int		g_iHealAmountPaddles;

ConVar	g_cvNonMedicHealAmt = null;
int		g_iNonMedicHealAmt;

ConVar	g_cvNonMedicReviveHp = null;
int		g_iNonMedicReviveHp;

ConVar	g_cvMedicMinorReviveHp = null;
int		g_iMedicMinorReviveHp;

ConVar	g_cvMedicModerateReviveHp = null;
int		g_iMedicModerateReviveHp;

ConVar	g_cvMedicCriticalReviveHp = null;
int		g_iMedicCriticalReviveHp;

ConVar	g_cvMinorWoundDmg = null;
int		g_iMinorWoundDmg;

ConVar	g_cvModerateWoundDmg = null;
int		g_iModerateWoundDmg;

ConVar	g_cvMedicHealSelfMax = null;
int		g_iMedicHealSelfMax;

ConVar	g_cvNonMedicHealSelfMax = null;
int		g_iNonMedicHealSelfMax;

ConVar	g_cvNonMedicMaxHealOther = null;
int		g_iNonMedicMaxHealOther;

ConVar	g_cvMinorReviveTime = null;
int		g_iMinorReviveTime;

ConVar	g_cvModerateReviveTime = null;
int		g_iModerateReviveTime;

ConVar	g_cvCriticalReviveTime = null;
int		g_iCriticalReviveTime;

ConVar	g_cvNonMedicReviveTime = null;
int		g_iNonMedicReviveTime;

ConVar	g_cvMedpackHealthAmount = null;
ConVar	g_cvPreRoundFirst = null;
ConVar	g_cvPreRound = null;
int		g_iMedpackHealthAmount;

// ----------------------------------------------------------------------
// Runtime state
// ----------------------------------------------------------------------
bool	g_bMapInit;
bool	g_bRoundActive;
bool	g_bReviveActive;

bool	g_bPreRoundInitial = false;
bool	g_bLateLoad = false;

int		g_iBeaconBeam;
int		g_iBeaconHalo;
int		m_hMyWeapons;

Handle	g_hForceRespawn = null;
Handle	g_hGameConfig = null;

// ----------------------------------------------------------------------
// Per-entity state
// ----------------------------------------------------------------------
int		ga_iTimeCheckHeight[MAX_ENTITIES + 1];
int		ga_iHealthPack_Amount[MAX_ENTITIES + 1];
float	ga_fLastHeight[MAX_ENTITIES + 1];
float	ga_fTimeCheck[MAX_ENTITIES + 1];
bool	ga_bHealthkitInit[MAX_ENTITIES + 1];

// ----------------------------------------------------------------------
// Per-player state
// ----------------------------------------------------------------------
int		ga_iReviveRemainingTime[MAXPLAYERS + 1];
int		ga_iReviveNonMedicRemainingTime[MAXPLAYERS + 1];

bool	ga_bHurtFatal[MAXPLAYERS + 1];
int		ga_iClientRagdolls[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iNearestBody[MAXPLAYERS + 1];

bool	ga_bBleedingOut[MAXPLAYERS + 1];
float	ga_fBleedoutEndsAt[MAXPLAYERS + 1];
float	ga_fTourniquetRemaining[MAXPLAYERS + 1];
float	ga_fLastTourniquetTick[MAXPLAYERS + 1];
int		ga_iTourniquetHealerUserId[MAXPLAYERS + 1];
bool	ga_bTourniquetHealerIsMedic[MAXPLAYERS + 1];
float	ga_fBleedoutStartedAt[MAXPLAYERS + 1];
float	ga_fNextBleedParticleRefresh[MAXPLAYERS + 1];
int		ga_iBleedParticleStance[MAXPLAYERS + 1] = {-1, ...};
float	ga_fBleedParticleForwardOffset[MAXPLAYERS + 1];
float	ga_fBleedParticleRightOffset[MAXPLAYERS + 1];
int		ga_iBleedoutHitgroup[MAXPLAYERS + 1];
int		ga_iBleedoutDamage[MAXPLAYERS + 1];
int		ga_iBleedoutAttackerUserId[MAXPLAYERS + 1];
int		ga_iBleedParticleRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iBleedPuddleRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int		ga_iBleedMarkerRef[MAXPLAYERS + 1][MAXPLAYERS + 1];
float	ga_fBleedMarkerScale[MAXPLAYERS + 1][MAXPLAYERS + 1];
int		ga_iBleedMarkerTargetByEntity[MAX_ENTITIES + 1];
int		ga_iBleedMarkerViewerByEntity[MAX_ENTITIES + 1];
int		ga_iBleedMarkerRefByEntity[MAX_ENTITIES + 1];
float	ga_fNextBleedFadeAt[MAXPLAYERS + 1];
bool	ga_bTourniquetPainPlayed[MAXPLAYERS + 1];
bool	ga_bBleedoutDeathPending[MAXPLAYERS + 1];
bool	ga_bBleedPuddlePending[MAXPLAYERS + 1];

int		ga_iLastTraceHitgroup[MAXPLAYERS + 1];
int		ga_iLastTraceAttackerUserId[MAXPLAYERS + 1];
int		ga_iLastTraceInflictor[MAXPLAYERS + 1];
float	ga_fLastTraceAt[MAXPLAYERS + 1];

bool	ga_bSecondHitDeathPending[MAXPLAYERS + 1];
int		ga_iSecondHitDamage[MAXPLAYERS + 1];
int		ga_iSecondHitHitgroup[MAXPLAYERS + 1];
BleedoutDeathReason ga_BleedoutDeathReason[MAXPLAYERS + 1];
bool	ga_bBleedoutDeathExplainedThisMap[MAXPLAYERS + 1];

int		ga_iTimeReviveCheck[MAXPLAYERS + 1] = {-1, ...};
int		ga_iClientDamageDone[MAXPLAYERS + 1];
int		ga_iPlayerWoundType[MAXPLAYERS + 1];
int		ga_iPlayerWoundTime[MAXPLAYERS + 1];
int		ga_iDeathStance[MAXPLAYERS + 1];

float	ga_fDeadAngle[MAXPLAYERS + 1][3];
float	ga_fRagdollPosition[MAXPLAYERS + 1][3];

// Ragdoll teleport safety (avoid TeleportEntity on ragdolls before physics is ready)
int		g_iOffsPhysicsObject = -1;

int		ga_iPendingRagTeleportRef[MAXPLAYERS + 1];
int		ga_iPendingRagTeleportTries[MAXPLAYERS + 1];
float	ga_fPendingRagTeleportPos[MAXPLAYERS + 1][3];
float	ga_fPendingRagTeleportAng[MAXPLAYERS + 1][3];
float	ga_fPendingRagTeleportVel[MAXPLAYERS + 1][3];

bool	ga_bBeingRevivedByMedic[MAXPLAYERS + 1];
bool	ga_bRevivedByMedic[MAXPLAYERS + 1];
bool	ga_bPlayerSelectNewClass[MAXPLAYERS + 1];
bool	ga_bPlayerPickSquad[MAXPLAYERS + 1];
bool	ga_bIsMedic[MAXPLAYERS + 1];
bool	ga_bAutoThanks[MAXPLAYERS + 1];
bool	ga_bAutoThanksCookieLoaded[MAXPLAYERS + 1];
bool	ga_bAutoThanksNotifiedThisMap[MAXPLAYERS + 1];
int		ga_iLastAutoThanksMessage[MAXPLAYERS + 1] = {-1, ...};

char	ga_sPlayerBGroups[MAXPLAYERS + 1][32];
char	ga_sClientLastClassString[MAXPLAYERS + 1][64];

// Revive/heal stats
int		ga_iStatRevives[MAXPLAYERS + 1];
int		ga_iStatHeals[MAXPLAYERS + 1];
int		ga_iTotalHP[MAXPLAYERS + 1];
int		ga_iStatReviveAssists[MAXPLAYERS + 1];
int		ga_iHealingSessions[MAXPLAYERS + 1];
int		ga_iStatBleedoutsTreated[MAXPLAYERS + 1];
int		ga_iHealingSessionTarget[MAXPLAYERS + 1];
int		ga_iHealingSessionHP[MAXPLAYERS + 1];
float	ga_fHealingSessionLastAt[MAXPLAYERS + 1];

#define HEAL_SESSION_TIMEOUT 1.0

float	ga_fNextMedicCmdTime[MAXPLAYERS + 1];

ArrayList g_hTrackedHealthkits = null;
Handle g_hAutoThanksCookie = null;

// Shared colors (avoid inline array literals for older compilers)
int		g_iColorReviveRing[4];
int		g_iColorHealRing[4];

public Plugin myinfo = {
	name = "medic",
	author = "Jared Ballou, Daimyo, naong, Lua, Nullifidian & GPT/Codex",
	description = "Adds the ability to revive with the Medic class and a health kit.",
	version = "1.3.21",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	MarkNativeAsOptional("Drag_IsEntityDragged");
	MarkNativeAsOptional("Drag_ForceDrop");
	MarkNativeAsOptional("ChatFilter_BypassNextMessage");
	MarkNativeAsOptional("InsItems_IsAFFBlocking");

	CreateNative("Medic_GetClientRagdollRef", Native_Medic_GetClientRagdollRef);
	CreateNative("Medic_IsClientMedic", Native_Medic_IsClientMedic);

	return APLRes_Success;
}

public any Native_Medic_GetClientRagdollRef(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
		return INVALID_ENT_REFERENCE;

	return ga_iClientRagdolls[client];
}

public any Native_Medic_IsClientMedic(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
		return false;

	return ga_bIsMedic[client];
}

public void OnPluginStart() {
	RegPluginLibrary("bm_medic");
	CleanupOrphanedMedicRagdolls();
	CleanupOrphanedHealthkits();
	CleanupOrphanedBleedMarkers();

	if (g_hFwdRagdollReady == null)
		g_hFwdRagdollReady = CreateGlobalForward("Medic_OnRagdollReady", ET_Ignore, Param_Cell, Param_Cell);

	g_iColorReviveRing[0] = 255;
	g_iColorReviveRing[1] = 0;
	g_iColorReviveRing[2] = 0;
	g_iColorReviveRing[3] = 255;

	g_iColorHealRing[0] = 0;
	g_iColorHealRing[1] = 200;
	g_iColorHealRing[2] = 0;
	g_iColorHealRing[3] = 75;

	for (int i = 1; i <= MaxClients; i++) {
		ClearPendingRagTeleport(i);
		ResetAutoThanksClient(i);
		ResetBleedoutClient(i, true);

		if (IsClientInGame(i)) {
			SDKHook(i, SDKHook_TraceAttack, Hook_PlayerTraceAttack);
			SDKHook(i, SDKHook_OnTakeDamageAlive, Hook_PlayerTakeDamage);
		}
	}

	if (g_hTrackedHealthkits == null)
		g_hTrackedHealthkits = new ArrayList();
	else
		g_hTrackedHealthkits.Clear();

	if ((m_hMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons")) == -1)
		SetFailState("Fatal Error: Unable to find property offset \"CBasePlayer::m_hMyWeapons\" !");

	if ((g_hGameConfig = LoadGameConfigFile("insurgency.games")) == INVALID_HANDLE)
		SetFailState("Fatal Error: Missing File \"insurgency.games\"!");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(g_hGameConfig, SDKConf_Signature, "ForceRespawn");
	if ((g_hForceRespawn = EndPrepSDKCall()) == INVALID_HANDLE)
		SetFailState("Fatal Error: Unable to find signature for \"ForceRespawn\"!");

	SetupConVars();
	g_hAutoThanksCookie = RegClientCookie("medic_autoty", "Enable automatic team-chat thanks after being revived", CookieAccess_Private);

	g_cvPreRoundFirst = FindConVar("mp_timer_preround_first");
	g_cvPreRound = FindConVar("mp_timer_preround");

	RegConsoleCmd("fatal", cmd_fatal, "Set your death to fatal");
	RegConsoleCmd("sm_medic", Cmd_MedicStats, "Show current medic heals/HP/revives");
	RegConsoleCmd("sm_autoty", Cmd_AutoThanks, "Toggle automatic thanks after being revived");
	RegAdminCmd("sm_bleedtest", Cmd_BleedTest, ADMFLAG_RCON,
		"sm_bleedtest <start|status|treat|hit|expire-fatal|expire-revive|revive|clear> [target] [leftarm|rightarm|leftleg|rightleg]");

	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsFakeClient(client) && AreClientCookiesCached(client))
			LoadAutoThanksCookie(client);
	}

	AddCommandListener(cmdListener, "kill");
	AddCommandListener(ChangeLevelListener, "changelevel");
	AddCommandListener(ChangeLevelListener, "map");
	AddCommandListener(ChangeLevelListener, "sm_map");

	HookEvent("grenade_thrown", Event_GrenadeThrown);
	HookEvent("player_hurt", Event_PlayerHurt_Pre, EventHookMode_Pre);
	HookEvent("round_end", Event_RoundEnd_Pre, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_spawn", Event_Spawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_pick_squad", Event_PlayerPickSquad_Post, EventHookMode_Post);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_connect", Event_PlayerConnect);
	HookEvent("game_end", Event_GameEnd, EventHookMode_PostNoCopy);

	//Load localization file
	LoadTranslations("common.phrases");
	LoadTranslations("nearest_player.phrases.txt");

	if (g_bLateLoad) {
		RebuildConnectedMedicStates();
		g_bRoundActive = true;
	}

	char sBuffer[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, sBuffer, sizeof(sBuffer));
	ReplaceString(sBuffer, sizeof(sBuffer), ".smx", "", false);
	AutoExecConfig(true, sBuffer);
}

public void OnMapStart() {
	PrecacheFiles();

	for (int client = 1; client <= MaxClients; client++) {
		ga_bAutoThanksNotifiedThisMap[client] = false;
		ga_bBleedoutDeathExplainedThisMap[client] = false;
	}

	CreateTimer(5.0, Timer_MapStart, _, TIMER_FLAG_NO_MAPCHANGE);
	if (!g_bLateLoad)
		g_bPreRoundInitial = true;
}

public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	FlushAllMedicStats(false);
	CleanupAllBleedParticles();
	for (int client = 1; client <= MaxClients; client++)
		ResetBleedoutClient(client, false);
	g_bReviveActive = false;
	g_bRoundActive = false;
	g_bLateLoad = false;
}

Action Timer_MapStart(Handle timer) {
	if (g_bMapInit) return Plugin_Stop;
	g_bMapInit = true;

	g_bReviveActive = g_bLateLoad;
	CreateTimer(1.0, Timer_ReviveMonitor, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.5, Timer_MedicMonitor, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.25, Timer_NearestBody, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public void OnMapEnd() {
	FlushAllMedicStats(false);
	CleanupAllBleedParticles();
	for (int client = 1; client <= MaxClients; client++)
		ResetBleedoutClient(client, false);
	g_bMapInit = false;
	g_bRoundActive = false;
	g_bReviveActive = false;
	g_bLateLoad = false;
	g_iObjResEntity = -1;
	g_sObjResNetClass[0] = '\0';

	if (g_hTrackedHealthkits != null)
		g_hTrackedHealthkits.Clear();
}

public void OnPluginEnd() {
	FlushAllMedicStats(false);
	CleanupAllBleedParticles();
	CleanupTrackedHealthkits();

	for (int client = 1; client <= MaxClients; client++)
		RemoveRagdoll(client);
}

public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients || entity > MAX_ENTITIES)
		return;

	int markerTarget = ga_iBleedMarkerTargetByEntity[entity];
	int markerViewer = ga_iBleedMarkerViewerByEntity[entity];
	if (markerTarget >= 1 && markerTarget <= MaxClients
		&& markerViewer >= 1 && markerViewer <= MaxClients
		&& ga_iBleedMarkerRef[markerTarget][markerViewer] == ga_iBleedMarkerRefByEntity[entity]) {
		ga_iBleedMarkerRef[markerTarget][markerViewer] = INVALID_ENT_REFERENCE;
		ga_fBleedMarkerScale[markerTarget][markerViewer] = 0.0;
	}
	ga_iBleedMarkerTargetByEntity[entity] = 0;
	ga_iBleedMarkerViewerByEntity[entity] = 0;
	ga_iBleedMarkerRefByEntity[entity] = INVALID_ENT_REFERENCE;

	ClearDestroyedBleedParticleRefs();
	UntrackHealthkit(entity);

	if (!ga_bHealthkitInit[entity] && ga_iHealthPack_Amount[entity] == 0)
		return;

	ga_bHealthkitInit[entity] = false;
	ga_iHealthPack_Amount[entity] = 0;
	ga_fLastHeight[entity] = 0.0;
	ga_fTimeCheck[entity] = 0.0;
	ga_iTimeCheckHeight[entity] = 0;
}

public void OnClientPutInServer(int client) {
	ResetBleedoutClient(client, true);
	ga_bBleedoutDeathExplainedThisMap[client] = false;
	SDKHook(client, SDKHook_TraceAttack, Hook_PlayerTraceAttack);
	SDKHook(client, SDKHook_OnTakeDamageAlive, Hook_PlayerTakeDamage);
	ResetMedicStats(client);
	ResetAutoThanksClient(client);
}

public void OnClientCookiesCached(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	LoadAutoThanksCookie(client);
}

public void OnClientPostAdminCheck(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	ga_bHurtFatal[client] = false;
	ResetBleedoutClient(client, true);
	ClearPendingRagTeleport(client);
	ResetMedicStats(client);
	ga_fNextMedicCmdTime[client] = 0.0;
	ga_bPlayerPickSquad[client] = false;
	ga_sClientLastClassString[client][0] = '\0';
	ga_bIsMedic[client] = false;
}

public Action Event_Spawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Continue;

	ResetBleedoutClient(client, false);
	RemoveRagdoll(client);
	ClearPendingRagTeleport(client);

	if (GetClientTeam(client) != TEAM_SECURITY)
		return Plugin_Continue;

	ga_bHurtFatal[client] = false;
	ga_bPlayerSelectNewClass[client] = false;
	ga_bBeingRevivedByMedic[client] = false;
	ga_iTimeReviveCheck[client] = -1;
	CreateTimer(0.5, Timer_RebuildMedicState, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients)
		return Plugin_Continue;

	ga_bPlayerPickSquad[client] = false;
	ga_bHurtFatal[client] = false;
	ResetBleedoutClient(client, true);
	ga_bIsMedic[client] = false;
	return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients) {
		for (int healer = 1; healer <= MaxClients; healer++) {
			if (healer != client && ga_iHealingSessionTarget[healer] == client)
				CloseHealingSession(healer);
		}

		FlushMedicStats(client, false);
		ga_bPlayerPickSquad[client] = false;
		ga_sClientLastClassString[client][0] = '\0';
		ga_fNextMedicCmdTime[client] = 0.0;
		ga_bIsMedic[client] = false;
		ResetAutoThanksClient(client);

		ResetBleedoutClient(client, true);
		RemoveRagdoll(client);
	}
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	g_bLateLoad = false;
	g_bReviveActive = false;

	int iPreRoundFirst = (g_cvPreRoundFirst != null) ? g_cvPreRoundFirst.IntValue : 0;
	int iPreRound = (g_cvPreRound != null) ? g_cvPreRound.IntValue : 0;
	if (g_bPreRoundInitial) {
		CreateTimer(float(iPreRoundFirst), PreReviveTimer, _, TIMER_FLAG_NO_MAPCHANGE);
		iPreRoundFirst = iPreRoundFirst + 5;
		g_bPreRoundInitial = false;
	} else
		CreateTimer(float(iPreRound), PreReviveTimer, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

Action PreReviveTimer(Handle timer) {
	g_bRoundActive = true;
	g_bReviveActive = true;
	return Plugin_Stop;
}

public Action Event_RoundEnd_Pre(Event event, const char[] name, bool dontBroadcast) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || IsFakeClient(client))
			continue;

		FlushMedicStats(client, true);
	}
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	g_bReviveActive = false;
	CleanupAllBleedParticles();
	for (int client = 1; client <= MaxClients; client++)
		ResetBleedoutClient(client, false);
	CleanupTrackedHealthkits();
	g_bRoundActive = false;
	return Plugin_Continue;
}

public Action Event_PlayerPickSquad_Post(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	char class_template[64];
	event.GetString("class_template", class_template, sizeof(class_template));
	strcopy(ga_sClientLastClassString[client], sizeof(ga_sClientLastClassString[]), class_template);
	UpdateClientMedicState(client);

	ga_bPlayerPickSquad[client] = true;

	// If player changed squad and remain ragdoll
	int team = GetClientTeam(client);
	if (!IsPlayerAlive(client) && !ga_bHurtFatal[client] && team == TEAM_SECURITY) {
		RemoveRagdoll(client);
		ga_bHurtFatal[client] = true;
		ga_bPlayerSelectNewClass[client] = true;
	}

	return Plugin_Continue;
}

public Action Hook_PlayerTraceAttack(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &ammotype, int hitbox, int hitgroup) {
	if (victim < 1 || victim > MaxClients || !IsClientInGame(victim) || !IsPlayerAlive(victim))
		return Plugin_Continue;

	ga_iLastTraceHitgroup[victim] = hitgroup;
	ga_iLastTraceAttackerUserId[victim] =
		(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)) ? GetClientUserId(attacker) : 0;
	ga_iLastTraceInflictor[victim] = inflictor;
	ga_fLastTraceAt[victim] = GetGameTime();
	return Plugin_Continue;
}

public Action Hook_PlayerTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (victim < 1 || victim > MaxClients || !IsClientInGame(victim) || !IsPlayerAlive(victim) || damage <= 0.0)
		return Plugin_Continue;

	float now = GetGameTime();
	int attackerUserId =
		(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)) ? GetClientUserId(attacker) : 0;

	bool traceMatches = ga_iLastTraceHitgroup[victim] > 0
		&& now - ga_fLastTraceAt[victim] <= BLEEDOUT_TRACE_MAX_AGE
		&& ga_iLastTraceAttackerUserId[victim] == attackerUserId
		&& ga_iLastTraceInflictor[victim] == inflictor;
	int hitgroup = traceMatches ? ga_iLastTraceHitgroup[victim] : 0;

	ga_iLastTraceHitgroup[victim] = 0;
	ga_iLastTraceAttackerUserId[victim] = 0;
	ga_iLastTraceInflictor[victim] = 0;
	ga_fLastTraceAt[victim] = 0.0;

	// Respect spawn protection and any other state that disables normal damage.
	if (HasEntProp(victim, Prop_Data, "m_takedamage")
		&& GetEntProp(victim, Prop_Data, "m_takedamage") != 2)
		return Plugin_Continue;

	// AFF blocks the real damage in ins_items_ae. Do not create a bleedout
	// or treat the blocked hit as a lethal second strike.
	if (attacker > 0
		&& attacker <= MaxClients
		&& IsClientInGame(attacker)
		&& GetFeatureStatus(FeatureType_Native, "InsItems_IsAFFBlocking") == FeatureStatus_Available
		&& InsItems_IsAFFBlocking(victim, attacker))
		return Plugin_Continue;

	if (ga_bBleedingOut[victim]) {
		// A shotgun can deliver several pellet callbacks in the same instant.
		// Suppress those callbacks so the shot that started bleedout is not also treated as the follow-up hit.
		if (now - ga_fBleedoutStartedAt[victim] <= BLEEDOUT_SAME_HIT_GRACE
			&& attackerUserId == ga_iBleedoutAttackerUserId[victim]) {
			damage = 0.0;
			return Plugin_Changed;
		}

		ga_bSecondHitDeathPending[victim] = true;
		ga_iSecondHitDamage[victim] = RoundToCeil(damage);
		ga_iSecondHitHitgroup[victim] = hitgroup;
		ga_BleedoutDeathReason[victim] = BleedoutDeath_SecondHit;
		ClearActiveBleedout(victim);

		// Any later positive damage kills, even if another plugin or external heal raised the player above 1 HP.
		damage = float(GetClientHealth(victim) + 1);
		return Plugin_Changed;
	}

	if (!g_bBleedoutEnabled
		|| !g_bReviveEnabled
		|| !g_bRoundActive
		|| GetClientTeam(victim) != TEAM_SECURITY
		|| !IsLimbHitgroup(hitgroup)
		|| damage < float(GetClientHealth(victim))
		|| g_fBleedoutChance <= 0.0)
		return Plugin_Continue;

	if (g_fBleedoutChance < 1.0 && GetRandomFloat(0.0, 1.0) > g_fBleedoutChance)
		return Plugin_Continue;

	int originalDamage = RoundToCeil(damage);
	StartBleedout(victim, hitgroup, originalDamage, attackerUserId, damagePosition);

	int remainingDamage = GetClientHealth(victim) - 1;
	damage = remainingDamage > 0 ? float(remainingDamage) : 0.0;
	return Plugin_Changed;
}

static bool RollFatalDamage(int attacker, int hitgroup, int damage, const char[] weapon) {
	if (g_fFatalChance <= 0.0)
		return false;

	float random = GetRandomFloat(0.0, 1.0);

	switch (hitgroup) {
		case 0: {
			if (!attacker)
				return random <= 0.25;

			if ((strcmp(weapon, "grenade_anm14", false) == 0)
			|| (strcmp(weapon, "grenade_molotov", false) == 0)
			|| (strcmp(weapon, "grenade_m203_incid", false) == 0)
			|| (strcmp(weapon, "grenade_gp25_incid", false) == 0)
			|| (strcmp(weapon, "grenade_m79_incen", false) == 0))
				return damage >= g_iFatalBurnDmg && random <= g_fFatalChance;

			if ((strcmp(weapon, "grenade_m67", false) == 0)
			|| (strcmp(weapon, "grenade_f1", false) == 0)
			|| (strcmp(weapon, "grenade_ied", false) == 0)
			|| (strcmp(weapon, "grenade_c4", false) == 0)
			|| (strcmp(weapon, "rocket_rpg7", false) == 0)
			|| (strcmp(weapon, "rocket_at4", false) == 0)
			|| (strcmp(weapon, "grenade_gp25_he", false) == 0)
			|| (strcmp(weapon, "grenade_m203_he", false) == 0)
			|| (strcmp(weapon, "grenade_m26a2", false) == 0)
			|| (strcmp(weapon, "grenade_c4_radius", false) == 0)
			|| (strcmp(weapon, "grenade_ied_radius", false) == 0)
			|| (strcmp(weapon, "grenade_ied_gunshot", false) == 0)
			|| (strcmp(weapon, "grenade_ied_fire", false) == 0)
			|| (strcmp(weapon, "grenade_ied_fire_bomber", false) == 0)
			|| (strcmp(weapon, "grenade_m79", false) == 0))
				return damage >= g_iFatalExplosiveDmg && random <= g_fFatalChance;
		}
		case 1: {
			return damage >= g_iFatalHeadDmg
				&& random <= g_fFatalHeadChance
				&& attacker > 0
				&& IsClientInGame(attacker)
				&& GetClientTeam(attacker) != TEAM_SECURITY;
		}
		case 2, 3: {
			return damage >= g_iFatalChestStomach && random <= g_fFatalChance;
		}
		case HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG: {
			return damage >= g_iFatalLimbDmg && random <= g_fFatalChance;
		}
	}

	return false;
}

static void SetWoundStateFromDamage(int client, int damage) {
	if (damage <= g_iMinorWoundDmg) {
		ga_iPlayerWoundTime[client] = g_iMinorReviveTime;
		ga_iPlayerWoundType[client] = 0;
	} else if (damage <= g_iModerateWoundDmg) {
		ga_iPlayerWoundTime[client] = g_iModerateReviveTime;
		ga_iPlayerWoundType[client] = 1;
	} else {
		ga_iPlayerWoundTime[client] = g_iCriticalReviveTime;
		ga_iPlayerWoundType[client] = 2;
	}
}

static void ExplainBleedoutDeathOnce(int client) {
	BleedoutDeathReason reason = ga_BleedoutDeathReason[client];
	ga_BleedoutDeathReason[client] = BleedoutDeath_None;

	if (reason == BleedoutDeath_None
		|| ga_bBleedoutDeathExplainedThisMap[client]
		|| IsFakeClient(client))
		return;

	ga_bBleedoutDeathExplainedThisMap[client] = true;

	if (reason == BleedoutDeath_Timeout) {
		PrintToChat(client, "\x070088cc[Medic]\x01 No \x0700cc44tourniquet\x01 was applied before you \x07cc2200bled out\x01.");
		PrintToChat(client, "\x01Without the bleedout system, the original \x07cc2200lethal limb hit\x01 would have killed you immediately.");
	} else if (reason == BleedoutDeath_SecondHit) {
		PrintToChat(client, "\x070088cc[Medic]\x01 You took \x07cc2200more damage\x01 while bleeding, which killed you.");
		PrintToChat(client, "\x01The original lethal limb hit gave you a \x0700cc44temporary chance\x01 to be saved by a \x070088ccmedic\x01.");
	}
}

public Action Event_PlayerHurt_Pre(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || victim > MaxClients || !IsClientInGame(victim))
		return Plugin_Continue;

	if (IsFakeClient(victim)
		&& !ga_bBleedoutDeathPending[victim]
		&& !ga_bSecondHitDeathPending[victim])
		return Plugin_Continue;

	if (event.GetInt("health") > 0)
		return Plugin_Continue;

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int dmg_taken = event.GetInt("dmg_health");
	int hitgroup = event.GetInt("hitgroup");

	if (ga_bSecondHitDeathPending[victim]) {
		dmg_taken = ga_iSecondHitDamage[victim];
		hitgroup = ga_iSecondHitHitgroup[victim];
		ga_bSecondHitDeathPending[victim] = false;
		ga_iSecondHitDamage[victim] = 0;
		ga_iSecondHitHitgroup[victim] = 0;
	}

	ga_iDeathStance[victim] = GetEntProp(victim, Prop_Send, "m_iCurrentStance");

	// Expiration was classified from the original lethal limb hit before the forced damage.
	if (ga_bBleedoutDeathPending[victim])
		return Plugin_Continue;

	ga_iClientDamageDone[victim] = dmg_taken;
	ga_bHurtFatal[victim] = false;

	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));
	ga_bHurtFatal[victim] = RollFatalDamage(attacker, hitgroup, dmg_taken, weapon);

	if (ga_bHurtFatal[victim]) {
		ga_iPlayerWoundTime[victim] = -1;
		ga_iPlayerWoundType[victim] = -1;
	} else
		SetWoundStateFromDamage(victim, dmg_taken);

	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim < 1 || !IsClientInGame(victim))
		return Plugin_Continue;

	ClearActiveBleedout(victim);
	int team = GetClientTeam(victim);

	// Fallback: some deaths don't go through our player_hurt logic, so ensure a non-zero revive time.
	if (!ga_bHurtFatal[victim] && ga_iPlayerWoundTime[victim] <= 0) {
		ga_iPlayerWoundTime[victim] = g_iMinorReviveTime;
		ga_iPlayerWoundType[victim] = 0;
	}

	if (g_bReviveEnabled && team == TEAM_SECURITY) {
		char sBuffer[32];
		IntToString(GetEntProp(victim, Prop_Send, "m_nBody"), sBuffer, sizeof(sBuffer));
		strcopy(ga_sPlayerBGroups[victim], sizeof(ga_sPlayerBGroups[]), sBuffer);

		int iWeapon;
		for (int offset = 0; offset < 128; offset += 4) {
			iWeapon = GetEntDataEnt2(victim, m_hMyWeapons + offset);
			if (iWeapon < 0)
				continue;

			char sWeapon[32];
			GetEdictClassname(iWeapon, sWeapon, sizeof(sWeapon));

			if (StrContains(sWeapon, "weapon_healthkit", false) != -1 && IsValidEntity(iWeapon)) {
				RemovePlayerItem(victim, iWeapon);
				SafeKillIdx(iWeapon);
			}
		}

		if (g_bReviveActive && g_bRoundActive) {
			// Convert ragdoll
			GetClientAbsAngles(victim, ga_fDeadAngle[victim]);	// Get current angles
			if (ga_iDeathStance[victim] == 2)
				ga_fDeadAngle[victim][0] += -90.0;

			RequestFrame(Frame_ConvertDeleteRagdoll, GetClientUserId(victim));
		}
	}

	char woundType[20];

	if      (ga_iPlayerWoundType[victim] == 0) FormatEx(woundType, sizeof(woundType), "MINORLY WOUNDED");
	else if (ga_iPlayerWoundType[victim] == 1) FormatEx(woundType, sizeof(woundType), "MODERATELY WOUNDED");
	else if (ga_iPlayerWoundType[victim] == 2) FormatEx(woundType, sizeof(woundType), "CRITICALLY WOUNDED");
	else                                        FormatEx(woundType, sizeof(woundType), "WOUNDED");

	if (g_fFatalChance > 0.0 && ga_bHurtFatal[victim]) {
		PrintHintText(victim, "You were fatally killed for %i damage", ga_iClientDamageDone[victim]);
		PrintToChat(victim, "\x01You were \x070088ccfatally\x01 killed for \x070088cc%i\x01 damage", ga_iClientDamageDone[victim]);
	} else {
		PrintHintText(victim, "You're %s for %i damage, call a medic for revive!", woundType, ga_iClientDamageDone[victim]);
		PrintToChat(victim, "\x01You're \x070088cc%s\x01 for \x070088cc%i\x01 damage, call a medic for revive!", woundType, ga_iClientDamageDone[victim]);
	}

	ExplainBleedoutDeathOnce(victim);
	ga_bBleedoutDeathPending[victim] = false;
	return Plugin_Continue;
}

// Convert dead body to new ragdoll
void Frame_ConvertDeleteRagdoll(int userid) {
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients)
		return;

	if (IsClientInGame(client)
		&& g_bRoundActive
		&& !IsPlayerAlive(client)
		&& (
			GetClientTeam(client) == TEAM_SECURITY
			|| GetClientTeam(client) == TEAM_INSURGENT
			)
		&& HasEntProp(client, Prop_Send, "m_hRagdoll")) {

		int clientRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (clientRagdoll > 0 && IsValidEntity(clientRagdoll) && g_bReviveActive) {
				if (!ga_bHurtFatal[client]) {
					float	fVelocity[3],
							fOrigin[3];
					GetEntPropVector(clientRagdoll, Prop_Send, "m_vecRagdollOrigin", fOrigin);
					GetEntPropVector(clientRagdoll, Prop_Send, "m_vecForce", fVelocity);

					char sModel[PLATFORM_MAX_PATH];
					GetClientModel(client, sModel, sizeof(sModel));

					if (!IsValidMedicRagdollModel(sModel)) {
						ga_bHurtFatal[client] = true;
						ga_bBleedPuddlePending[client] = false;
						ga_iPlayerWoundTime[client] = -1;
						ga_iPlayerWoundType[client] = -1;
						LogMessage("[Medic] Skipping revivable ragdoll for %N: invalid player model \"%s\"", client, sModel);
					}
					else {
						int tempRag = CreateEntityByName("prop_ragdoll");
						if (IsValidEntity(tempRag)) {
							ga_iClientRagdolls[client] = EntIndexToEntRef(tempRag);
							char sBuffer[64];
							SetEntityModel(tempRag, sModel);
							// Give custom ragdoll name for each client, this way other plugins can search for targetname to modify behavior
							FormatEx(sBuffer, sizeof(sBuffer), "playervital_ragdoll_%i", client);
							DispatchKeyValue(tempRag, "targetname", sBuffer);
							DispatchKeyValue(tempRag, "body", ga_sPlayerBGroups[client]);
		/*
						Format(sBuffer, sizeof(sBuffer), "%f %f %f", g_fDeadPosition[client][0], g_fDeadPosition[client][1], g_fDeadPosition[client][2] += 15.0);
						DispatchKeyValue(tempRag, "Origin", sBuffer);

						Format(sBuffer, sizeof(sBuffer), "%f %f %f", ga_fDeadAngle[client][0] += -90.0, ga_fDeadAngle[client][1], ga_fDeadAngle[client][2]);
						DispatchKeyValue(tempRag, "Angles", sBuffer);
		*/
							DispatchSpawn(tempRag);

							ActivateEntity(tempRag);

							//must be after DispatchSpawn
							DispatchKeyValue(tempRag, "CollisionGroup", "17");	//COLLISION_GROUP_PUSHAWAY

							fOrigin[2] += 50.0;
							VecCopy(fOrigin, ga_fRagdollPosition[client]);

							ga_iPendingRagTeleportRef[client] = EntIndexToEntRef(tempRag);
							ga_iPendingRagTeleportTries[client] = 0;
							VecCopy(fOrigin, ga_fPendingRagTeleportPos[client]);
							VecCopy(ga_fDeadAngle[client], ga_fPendingRagTeleportAng[client]);
							VecCopy(fVelocity, ga_fPendingRagTeleportVel[client]);

							RequestFrame(Frame_TeleportPendingRagdoll, userid);
							ga_iReviveRemainingTime[client] = ga_iPlayerWoundTime[client];
							ga_iReviveNonMedicRemainingTime[client] = g_iNonMedicReviveTime;
						}
					}
				}
				SafeKillIdx(clientRagdoll);
				clientRagdoll = INVALID_ENT_REFERENCE;
		}
	}
}

static bool IsValidMedicRagdollModel(const char[] model) {
	if (model[0] == '\0')
		return false;

	if (!HasMdlExtension(model))
		return false;

	if (StrContains(model, "error.mdl", false) != -1)
		return false;

	if (StrEqual(model, "models/player.mdl", false))
		return false;

	if (!FileExists(model, true))
		return false;

	if (!IsModelPrecached(model))
		return false;

	return true;
}

static bool HasMdlExtension(const char[] model) {
	int len = strlen(model);

	if (len < 5)
		return false;

	if (model[len - 4] != '.')
		return false;

	if (model[len - 3] != 'm' && model[len - 3] != 'M')
		return false;

	if (model[len - 2] != 'd' && model[len - 2] != 'D')
		return false;

	if (model[len - 1] != 'l' && model[len - 1] != 'L')
		return false;

	return true;
}

bool hasCorrectWeapon(const char[] sWeapon, bool melee = true) {
	if (melee) {
		if (StrContains(sWeapon, "weapon_defib", false) != -1
			|| StrContains(sWeapon, "weapon_knife", false) != -1
			|| StrContains(sWeapon, "weapon_kabar", false) != -1
			|| StrContains(sWeapon, "weapon_katana", false) != -1)
			// player has one of the above weapons
			return true;
	} else {
		if (StrContains(sWeapon, "weapon_healthkit", false) != -1)
			// player has one of the above
			return true;
	}
	return false;
}

static void UpdateClientMedicState(int client) {
	if (client < 1 || client > MaxClients) {
		return;
	}

	ga_bIsMedic[client] = (StrContains(ga_sClientLastClassString[client], "medic", false) != -1);
}

static bool ClientHasMedicClassSlot(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client)
		|| IsFakeClient(client)
		|| GetClientTeam(client) != TEAM_SECURITY)
		return false;

	int playerResource = GetPlayerResourceEntity();
	if (playerResource <= MaxClients || !IsValidEntity(playerResource))
		return false;

	int classSlot = GetEntProp(playerResource, Prop_Send, "m_iPlayerClass", 4, client);
	return classSlot == MEDIC_CLASS_SLOT_1 || classSlot == MEDIC_CLASS_SLOT_2;
}

static void RebuildClientMedicState(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	if (ga_sClientLastClassString[client][0] != '\0')
		UpdateClientMedicState(client);
	else
		ga_bIsMedic[client] = ClientHasMedicClassSlot(client);

	if (ga_bIsMedic[client])
		ga_bPlayerPickSquad[client] = true;
}

static void RebuildConnectedMedicStates() {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client))
			RebuildClientMedicState(client);
	}
}

static Action Timer_RebuildMedicState(Handle timer, any userid) {
	int client = GetClientOfUserId(userid);
	if (client >= 1 && client <= MaxClients && IsClientInGame(client))
		RebuildClientMedicState(client);

	return Plugin_Stop;
}

static bool GetClientSupportWeaponState(int client, int &activeWeapon, bool &canPaddle, bool &canMedpack) {
	activeWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	canPaddle = false;
	canMedpack = false;

	if (activeWeapon < 0 || !IsValidEntity(activeWeapon))
		return false;

	char sWeapon[32];
	GetEdictClassname(activeWeapon, sWeapon, sizeof(sWeapon));

	canPaddle = hasCorrectWeapon(sWeapon);
	canMedpack = hasCorrectWeapon(sWeapon, false);
	return true;
}

static int GetFirstAidKitUses(int client, int weapon) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client)
		|| weapon <= MaxClients || !IsValidEntity(weapon))
		return 0;

	char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));
	if (!hasCorrectWeapon(classname, false))
		return 0;

	int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
	if (ammoType < 0)
		return 0;

	return GetEntProp(client, Prop_Data, "m_iAmmo", _, ammoType);
}

static bool ConsumeFirstAidKitUse(int client, int weapon) {
	int uses = GetFirstAidKitUses(client, weapon);
	if (uses <= 0)
		return false;

	int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
	SetEntProp(client, Prop_Send, "m_iAmmo", uses - 1, _, ammoType);

	if (uses == 1) {
		if (GetPlayerWeaponSlot(client, 0) > 0)
			ClientCommand(client, "slot1");
		else if (GetPlayerWeaponSlot(client, 1) > 0)
			ClientCommand(client, "slot2");
	}

	return true;
}

static int GetClientRagdollEntity(int client) {
	if (client < 1 || client > MaxClients)
		return INVALID_ENT_REFERENCE;

	int ragdoll = EntRefToEntIndex(ga_iClientRagdolls[client]);
	if (ragdoll == INVALID_ENT_REFERENCE || ragdoll <= MaxClients || !IsValidEntity(ragdoll))
		return INVALID_ENT_REFERENCE;

	return ragdoll;
}

static void GetWoundTypeString(int client, char[] woundType, int maxlen) {
	if (ga_iPlayerWoundType[client] == 0)
		strcopy(woundType, maxlen, "minor wound");
	else if (ga_iPlayerWoundType[client] == 1)
		strcopy(woundType, maxlen, "moderate wound");
	else if (ga_iPlayerWoundType[client] == 2)
		strcopy(woundType, maxlen, "critical wound");
	else
		strcopy(woundType, maxlen, "wound");
}

static bool IsLimbHitgroup(int hitgroup) {
	return hitgroup >= HITGROUP_LEFTARM && hitgroup <= HITGROUP_RIGHTLEG;
}

static int GetBleedParticleStance(int client) {
	int stance = GetEntProp(client, Prop_Send, "m_iCurrentStance");
	if (stance < 0 || stance > 2)
		stance = 0;
	return stance;
}

static float GetBleedParticleHeight(int hitgroup, int stance) {
	bool arm = hitgroup == HITGROUP_LEFTARM || hitgroup == HITGROUP_RIGHTARM;

	switch (stance) {
		case 1: return arm ? 31.0 : 12.0;
		case 2: return arm ? 12.0 : 8.0;
	}

	return arm ? 48.0 : 22.0;
}

static bool GetBleedLegAttachmentName(int hitgroup, char[] attachment, int maxlen) {
	if (hitgroup == HITGROUP_LEFTLEG) {
		strcopy(attachment, maxlen, "L_Foota");
		return true;
	}
	if (hitgroup == HITGROUP_RIGHTLEG) {
		strcopy(attachment, maxlen, "R_Foota");
		return true;
	}

	attachment[0] = '\0';
	return false;
}

static void GetBleedHorizontalVectors(int client, float forwardVec[3], float rightVec[3]) {
	float angles[3], up[3];
	GetClientEyeAngles(client, angles);
	angles[0] = 0.0;
	angles[2] = 0.0;
	GetAngleVectors(angles, forwardVec, rightVec, up);
}

static void GetProneArmBleedPosition(int client, int hitgroup, float position[3]) {
	float forwardVec[3], rightVec[3];
	GetBleedHorizontalVectors(client, forwardVec, rightVec);
	GetClientAbsOrigin(client, position);

	for (int axis = 0; axis < 3; axis++)
		position[axis] += forwardVec[axis] * 8.0;
	position[2] += 8.0;

	float sideOffset = hitgroup == HITGROUP_LEFTARM ? -14.0 : 14.0;
	for (int axis = 0; axis < 3; axis++)
		position[axis] += rightVec[axis] * sideOffset;
}

static void GetBleedParticlePosition(int client, int hitgroup, float position[3]) {
	int stance = GetBleedParticleStance(client);
	if (stance == 2 && (hitgroup == HITGROUP_LEFTARM || hitgroup == HITGROUP_RIGHTARM)) {
		GetProneArmBleedPosition(client, hitgroup, position);
		return;
	}

	if (position[0] != 0.0 || position[1] != 0.0 || position[2] != 0.0)
		return;

	GetClientAbsOrigin(client, position);
	position[2] += GetBleedParticleHeight(hitgroup, stance);
}

static void CaptureBleedParticleHorizontalOffset(int client, const float position[3]) {
	float origin[3], forwardVec[3], rightVec[3], delta[3];
	GetClientAbsOrigin(client, origin);
	GetBleedHorizontalVectors(client, forwardVec, rightVec);

	for (int axis = 0; axis < 3; axis++)
		delta[axis] = position[axis] - origin[axis];

	ga_fBleedParticleForwardOffset[client] = GetVectorDotProduct(delta, forwardVec);
	ga_fBleedParticleRightOffset[client] = GetVectorDotProduct(delta, rightVec);
}

static void GetTrackedBleedParticlePosition(int client, int hitgroup, float position[3]) {
	int stance = GetBleedParticleStance(client);
	if (stance == 2 && (hitgroup == HITGROUP_LEFTARM || hitgroup == HITGROUP_RIGHTARM)) {
		GetProneArmBleedPosition(client, hitgroup, position);
		return;
	}

	float origin[3], forwardVec[3], rightVec[3];
	GetClientAbsOrigin(client, origin);
	GetBleedHorizontalVectors(client, forwardVec, rightVec);
	for (int axis = 0; axis < 3; axis++) {
		position[axis] = origin[axis]
			+ forwardVec[axis] * ga_fBleedParticleForwardOffset[client]
			+ rightVec[axis] * ga_fBleedParticleRightOffset[client];
	}
	position[2] = origin[2] + GetBleedParticleHeight(hitgroup, stance);
}

static int CreateBleedParticle(const char[] effect, const float position[3], int parent = 0) {
	int particle = CreateEntityByName("info_particle_system");
	if (particle == -1 || !IsValidEntity(particle))
		return INVALID_ENT_REFERENCE;

	DispatchKeyValue(particle, "effect_name", effect);
	DispatchSpawn(particle);
	TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);
	ActivateEntity(particle);

	if (parent > 0 && parent <= MaxClients && IsClientInGame(parent)) {
		SetVariantString("!activator");
		AcceptEntityInput(particle, "SetParent", parent, particle);
	}

	AcceptEntityInput(particle, "start");
	return EntIndexToEntRef(particle);
}

static int CreateArterialBleedParticle(int client, int hitgroup, const float position[3]) {
	int ref = CreateBleedParticle("blood_gore_arterial_drip", position, client);
	int particle = EntRefToEntIndex(ref);
	if (particle == INVALID_ENT_REFERENCE || particle <= MaxClients || !IsValidEntity(particle))
		return ref;

	char attachment[16];
	if (GetBleedLegAttachmentName(hitgroup, attachment, sizeof(attachment))) {
		SetVariantString(attachment);
		AcceptEntityInput(particle, "SetParentAttachment", client, particle);

		// L_Foota/R_Foota sit slightly beneath the boot on the player models.
		// Their attachment Z axis points downward, so a negative local Z raises
		// the emitter to the visible ankle area.
		SetVariantString("0 0 -6");
		AcceptEntityInput(particle, "SetLocalOrigin");
	}
	else if (hitgroup == HITGROUP_LEFTARM || hitgroup == HITGROUP_RIGHTARM) {
		SetVariantString("centermass");
		AcceptEntityInput(particle, "SetParentAttachment", client, particle);

		// The models have no arm or hand attachments. Centermass local X runs
		// vertically and local Z runs left/right, so these offsets place the
		// emitter beside and below the upper torso while following every stance.
		SetVariantString(hitgroup == HITGROUP_LEFTARM ? "8 0 14" : "8 0 -14");
		AcceptEntityInput(particle, "SetLocalOrigin");

		// Aim the arterial effect away from the body while keeping its local
		// upward axis pointed down, preventing the spray from firing skyward.
		SetVariantString(hitgroup == HITGROUP_LEFTARM ? "-90 0 0" : "90 0 180");
		AcceptEntityInput(particle, "SetLocalAngles");
	}

	return ref;
}

static void RemoveBleedParticle(int client) {
	int ref = ga_iBleedParticleRef[client];
	ga_iBleedParticleRef[client] = INVALID_ENT_REFERENCE;
	if (ref != INVALID_ENT_REFERENCE)
		SafeKillRef(ref);
}

static void RemoveBleedPuddle(int client) {
	int ref = ga_iBleedPuddleRef[client];
	ga_iBleedPuddleRef[client] = INVALID_ENT_REFERENCE;
	if (ref != INVALID_ENT_REFERENCE)
		SafeKillRef(ref);
}

static void RemoveBleedMarker(int target, int viewer) {
	int ref = ga_iBleedMarkerRef[target][viewer];
	ga_iBleedMarkerRef[target][viewer] = INVALID_ENT_REFERENCE;
	ga_fBleedMarkerScale[target][viewer] = 0.0;
	if (ref != INVALID_ENT_REFERENCE)
		SafeKillRef(ref);
}

static void RemoveBleedMarkers(int target) {
	for (int viewer = 1; viewer <= MaxClients; viewer++)
		RemoveBleedMarker(target, viewer);
}

public Action BleedMarker_SetTransmit(int entity, int client) {
	if (entity <= MaxClients || entity > MAX_ENTITIES
		|| client < 1 || client > MaxClients
		|| !IsClientInGame(client)
		|| !IsPlayerAlive(client)
		|| GetClientTeam(client) != TEAM_SECURITY
		|| !ga_bIsMedic[client])
		return Plugin_Stop;

	int target = ga_iBleedMarkerTargetByEntity[entity];
	int viewer = ga_iBleedMarkerViewerByEntity[entity];
	if (target < 1 || target > MaxClients
		|| viewer != client
		|| !IsClientInGame(target)
		|| !IsPlayerAlive(target)
		|| GetClientTeam(target) != TEAM_SECURITY
		|| !ga_bBleedingOut[target])
		return Plugin_Stop;

	return Plugin_Continue;
}

static float GetBleedMarkerScale(int target, int viewer) {
	float targetPosition[3], viewerPosition[3];
	GetClientAbsOrigin(target, targetPosition);
	GetClientAbsOrigin(viewer, viewerPosition);

	float distance = GetVectorDistance(targetPosition, viewerPosition);
	float fraction = (distance - BLEEDOUT_MARKER_MIN_DISTANCE)
		/ (BLEEDOUT_MARKER_MAX_DISTANCE - BLEEDOUT_MARKER_MIN_DISTANCE);
	if (fraction < 0.0)
		fraction = 0.0;
	else if (fraction > 1.0)
		fraction = 1.0;

	return BLEEDOUT_MARKER_MIN_SCALE
		+ fraction * (BLEEDOUT_MARKER_MAX_SCALE - BLEEDOUT_MARKER_MIN_SCALE);
}

static float GetBleedMarkerHeight(int target) {
	switch (GetBleedParticleStance(target)) {
		case 1: return BLEEDOUT_MARKER_CROUCH_HEIGHT;
		case 2: return BLEEDOUT_MARKER_PRONE_HEIGHT;
	}

	return BLEEDOUT_MARKER_STAND_HEIGHT;
}

static void UpdateBleedMarkerOrigin(int marker, int target) {
	char localOrigin[48];
	FormatEx(localOrigin, sizeof(localOrigin), "%.1f 0.0 %.1f",
		BLEEDOUT_MARKER_BACK_OFFSET, GetBleedMarkerHeight(target));
	SetVariantString(localOrigin);
	AcceptEntityInput(marker, "SetLocalOrigin");
}

static int CreateBleedMarker(int target, int viewer) {
	if (target < 1 || target > MaxClients || !IsClientInGame(target)
		|| viewer < 1 || viewer > MaxClients || !IsClientInGame(viewer))
		return INVALID_ENT_REFERENCE;

	if (!PrecacheBleedoutMarkerMaterial())
		return INVALID_ENT_REFERENCE;

	int marker = CreateEntityByName("env_sprite");
	if (marker == -1)
		return INVALID_ENT_REFERENCE;

	char targetName[64];
	FormatEx(targetName, sizeof(targetName), "%s%d_%d", BLEEDOUT_MARKER_NAME,
		GetClientUserId(target), GetClientUserId(viewer));

	DispatchKeyValue(marker, "targetname", targetName);
	DispatchKeyValue(marker, "model", BLEEDOUT_MARKER_MODEL);
	DispatchKeyValue(marker, "spawnflags", "1");
	DispatchKeyValue(marker, "scale", "0.035");
	DispatchKeyValue(marker, "rendermode", "1");
	DispatchKeyValue(marker, "renderamt", BLEEDOUT_MARKER_ALPHA);
	DispatchKeyValue(marker, "rendercolor", "255 255 255");
	DispatchKeyValue(marker, "renderfx", "0");
	DispatchKeyValue(marker, "disableshadows", "1");
	DispatchKeyValue(marker, "disableshadowdepth", "1");
	DispatchSpawn(marker);
	ActivateEntity(marker);
	AcceptEntityInput(marker, "DisableShadow");

	SetEntPropEnt(marker, Prop_Send, "m_hOwnerEntity", target);

	SetVariantString("!activator");
	AcceptEntityInput(marker, "SetParent", target, marker, 0);
	UpdateBleedMarkerOrigin(marker, target);

	// Keep the sprite eligible for every client so $ignorez can make it visible
	// through walls. SetTransmit restricts this copy to its assigned medic.
	SetEdictFlags(marker, GetEdictFlags(marker) | FL_EDICT_ALWAYS);
	ga_iBleedMarkerTargetByEntity[marker] = target;
	ga_iBleedMarkerViewerByEntity[marker] = viewer;
	ga_iBleedMarkerRefByEntity[marker] = EntIndexToEntRef(marker);
	SDKHook(marker, SDKHook_SetTransmit, BleedMarker_SetTransmit);
	AcceptEntityInput(marker, "ShowSprite");

	return ga_iBleedMarkerRefByEntity[marker];
}

static void UpdateBleedMarkers(int target) {
	for (int viewer = 1; viewer <= MaxClients; viewer++) {
		bool shouldShow = viewer != target
			&& IsClientInGame(viewer)
			&& IsPlayerAlive(viewer)
			&& GetClientTeam(viewer) == TEAM_SECURITY
			&& ga_bIsMedic[viewer];

		if (!shouldShow) {
			RemoveBleedMarker(target, viewer);
			continue;
		}

		int marker = EntRefToEntIndex(ga_iBleedMarkerRef[target][viewer]);
		if (marker == INVALID_ENT_REFERENCE) {
			ga_iBleedMarkerRef[target][viewer] = CreateBleedMarker(target, viewer);
			marker = EntRefToEntIndex(ga_iBleedMarkerRef[target][viewer]);
			if (marker == INVALID_ENT_REFERENCE)
				continue;
		}

		UpdateBleedMarkerOrigin(marker, target);

		float scale = GetBleedMarkerScale(target, viewer);
		if (FloatAbs(scale - ga_fBleedMarkerScale[target][viewer]) < 0.001)
			continue;

		SetVariantFloat(scale);
		AcceptEntityInput(marker, "SetScale");
		ga_fBleedMarkerScale[target][viewer] = scale;
	}
}

static int CountBleedMarkers(int target) {
	int count = 0;
	for (int viewer = 1; viewer <= MaxClients; viewer++) {
		if (EntRefToEntIndex(ga_iBleedMarkerRef[target][viewer]) != INVALID_ENT_REFERENCE)
			count++;
	}
	return count;
}

static void ClearActiveBleedout(int client) {
	if (client < 1 || client > MaxClients)
		return;

	RemoveBleedParticle(client);
	RemoveBleedMarkers(client);
	ga_bBleedingOut[client] = false;
	ga_fBleedoutEndsAt[client] = 0.0;
	ga_fTourniquetRemaining[client] = 0.0;
	ga_fLastTourniquetTick[client] = 0.0;
	ga_iTourniquetHealerUserId[client] = 0;
	ga_bTourniquetHealerIsMedic[client] = false;
	ga_fBleedoutStartedAt[client] = 0.0;
	ga_fNextBleedParticleRefresh[client] = 0.0;
	ga_iBleedParticleStance[client] = -1;
	ga_fBleedParticleForwardOffset[client] = 0.0;
	ga_fBleedParticleRightOffset[client] = 0.0;
	ga_fNextBleedFadeAt[client] = 0.0;
	ga_bTourniquetPainPlayed[client] = false;
	ga_iBleedoutHitgroup[client] = 0;
	ga_iBleedoutDamage[client] = 0;
	ga_iBleedoutAttackerUserId[client] = 0;
}

static void ResetBleedoutClient(int client, bool removePuddle) {
	if (client < 1 || client > MaxClients)
		return;

	ClearActiveBleedout(client);
	if (removePuddle)
		RemoveBleedPuddle(client);

	ga_bBleedoutDeathPending[client] = false;
	ga_bBleedPuddlePending[client] = false;
	ga_iLastTraceHitgroup[client] = 0;
	ga_iLastTraceAttackerUserId[client] = 0;
	ga_iLastTraceInflictor[client] = 0;
	ga_fLastTraceAt[client] = 0.0;
	ga_bSecondHitDeathPending[client] = false;
	ga_iSecondHitDamage[client] = 0;
	ga_iSecondHitHitgroup[client] = 0;
	ga_BleedoutDeathReason[client] = BleedoutDeath_None;
}

static void StartBleedout(int client, int hitgroup, int damage, int attackerUserId, const float damagePosition[3]) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return;

	ClearActiveBleedout(client);
	ga_bBleedingOut[client] = true;
	ga_fBleedoutStartedAt[client] = GetGameTime();
	ga_fBleedoutEndsAt[client] = ga_fBleedoutStartedAt[client] + g_fBleedoutTime;
	ga_fNextBleedParticleRefresh[client] = ga_fBleedoutStartedAt[client] + BLEED_PARTICLE_REFRESH_TIME;
	ga_iBleedParticleStance[client] = GetBleedParticleStance(client);
	ga_fTourniquetRemaining[client] = g_fTourniquetMedicTime;
	ga_iTourniquetHealerUserId[client] = 0;
	ga_bTourniquetHealerIsMedic[client] = false;
	ga_iBleedoutHitgroup[client] = hitgroup;
	ga_iBleedoutDamage[client] = damage;
	ga_iBleedoutAttackerUserId[client] = attackerUserId;
	ga_bBleedoutDeathPending[client] = false;
	ga_bBleedPuddlePending[client] = false;
	ga_bSecondHitDeathPending[client] = false;
	ga_BleedoutDeathReason[client] = BleedoutDeath_None;

	ga_fNextBleedFadeAt[client] = ga_fBleedoutStartedAt[client];

	float position[3];
	VecCopy(damagePosition, position);
	GetBleedParticlePosition(client, hitgroup, position);
	CaptureBleedParticleHorizontalOffset(client, position);
	ga_iBleedParticleRef[client] = CreateArterialBleedParticle(client, hitgroup, position);
	UpdateBleedMarkers(client);
	CreateTimer(BLEEDOUT_CALL_DELAY, Timer_PlayBleedoutCall, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

	PrintCenterText(client, "ARTERIAL BLEEDING: %.1f seconds\nAny further damage will kill you", g_fBleedoutTime);
	PrintToChat(client, "\x070088cc[Medic]\x01 ARTERIAL BLEEDING! You have \x07cc2200%.1f seconds\x01. A medic or teammate with a first-aid kit must apply a tourniquet.", g_fBleedoutTime);
}

static Action Timer_PlayBleedoutCall(Handle timer, any userid) {
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || !ga_bBleedingOut[client])
		return Plugin_Stop;

	EmitSoundToAll(BLEEDOUT_CALL_SOUND, client, SNDCHAN_VOICE, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
	return Plugin_Stop;
}

static void KeepBleedParticleActive(int client, float now) {
	int currentStance = GetBleedParticleStance(client);
	int previousStance = ga_iBleedParticleStance[client];
	bool stanceChanged = previousStance >= 0 && currentStance != previousStance;

	if (!stanceChanged && now < ga_fNextBleedParticleRefresh[client])
		return;

	ga_fNextBleedParticleRefresh[client] = now + BLEED_PARTICLE_REFRESH_TIME;

	int oldRef = ga_iBleedParticleRef[client];
	float position[3];
	GetTrackedBleedParticlePosition(client, ga_iBleedoutHitgroup[client], position);

	int newRef = CreateArterialBleedParticle(client, ga_iBleedoutHitgroup[client], position);
	if (newRef == INVALID_ENT_REFERENCE)
		return;

	ga_iBleedParticleRef[client] = newRef;
	ga_iBleedParticleStance[client] = currentStance;
	if (oldRef != INVALID_ENT_REFERENCE)
		SafeKillRef(oldRef);
}

static void CompleteTourniquet(int client, int helper) {
	if (client < 1 || client > MaxClients || !ga_bBleedingOut[client])
		return;

	bool validHelper = helper > 0 && helper <= MaxClients && IsClientInGame(helper)
		&& helper != client;
	bool helperIsMedic = validHelper && ga_bIsMedic[helper];
	if (helperIsMedic)
		ga_iStatBleedoutsTreated[helper]++;

	// HLstats uses the same action for medic and non-medic treatment.
	if (validHelper)
		LogToGame("\"%L\" triggered \"bleedout_treated\" against \"%L\"", helper, client);

	ClearActiveBleedout(client);
	PrintCenterText(client, "TOURNIQUET SECURED\nBleeding stopped");
	PrintToChat(client, "\x070088cc[Medic]\x01 Tourniquet secured. Bleeding stopped.");

	if (validHelper) {
		PrintHintText(helper, "Tourniquet secured on %N. Continue healing.", client);
		PrintToChat(helper, "\x070088cc[Medic]\x01 You secured a tourniquet on \x0700cc44%N\x01.", client);
	}
}

static void ExpireBleedout(int client, int forcedFatal = -1) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || !ga_bBleedingOut[client])
		return;

	int hitgroup = ga_iBleedoutHitgroup[client];
	int damage = ga_iBleedoutDamage[client];
	int attacker = GetClientOfUserId(ga_iBleedoutAttackerUserId[client]);
	if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker))
		attacker = 0;

	bool fatal;
	if (forcedFatal == 0)
		fatal = false;
	else if (forcedFatal == 1)
		fatal = true;
	else {
		char weapon[2];
		weapon[0] = '\0';
		fatal = RollFatalDamage(attacker, hitgroup, damage, weapon);
	}

	ga_iClientDamageDone[client] = damage;
	ga_bHurtFatal[client] = fatal;
	if (fatal) {
		ga_iPlayerWoundTime[client] = -1;
		ga_iPlayerWoundType[client] = -1;
	} else
		SetWoundStateFromDamage(client, damage);

	ga_bBleedoutDeathPending[client] = true;
	ga_bBleedPuddlePending[client] = !fatal;
	ga_BleedoutDeathReason[client] = BleedoutDeath_Timeout;
	ClearActiveBleedout(client);

	int inflictor = attacker > 0 ? attacker : 0;
	SDKHooks_TakeDamage(client, inflictor, attacker, 10000.0, DMG_SLASH, -1, NULL_VECTOR, NULL_VECTOR, true);
	if (IsPlayerAlive(client))
		ForcePlayerSuicide(client);
}

static void UpdateBleedoutStates(float now) {
	for (int client = 1; client <= MaxClients; client++) {
		if (!ga_bBleedingOut[client])
			continue;

		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SECURITY) {
			ClearActiveBleedout(client);
			continue;
		}

		float remaining = ga_fBleedoutEndsAt[client] - now;
		if (remaining <= 0.0) {
			ExpireBleedout(client);
			continue;
		}

		if (ga_iTourniquetHealerUserId[client] != 0
			&& now - ga_fLastTourniquetTick[client] > BLEEDOUT_TREAT_TICK * 1.5)
			ResetTourniquetTreatment(client);

		KeepBleedParticleActive(client, now);
		UpdateBleedMarkers(client);
		UpdateBleedoutFade(client, now, remaining);
		PrintCenterText(client, "ARTERIAL BLEEDING: %.1f seconds\nAny further damage will kill you\nTourniquet: %.1f seconds",
			remaining, ga_fTourniquetRemaining[client]);
	}
}

static void PlayTourniquetPainSound(int client) {
	char soundPath[96];
	FormatEx(soundPath, sizeof(soundPath),
		"player/voice/responses/security/subordinate/unsuppressed/wounded%d.ogg",
		GetRandomInt(6, 19));
	EmitSoundToAll(soundPath, client, SNDCHAN_VOICE, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
}

static void ResetTourniquetTreatment(int client) {
	ga_iTourniquetHealerUserId[client] = 0;
	ga_bTourniquetHealerIsMedic[client] = false;
	ga_fLastTourniquetTick[client] = 0.0;
	ga_fTourniquetRemaining[client] = g_fTourniquetMedicTime;
}

static TourniquetApplyResult ApplyTourniquetTick(int helper, int client, int activeWeapon, float now) {
	if (!ga_bBleedingOut[client])
		return TourniquetApply_Progress;

	bool helperIsMedic = ga_bIsMedic[helper];
	if (!helperIsMedic && GetFirstAidKitUses(helper, activeWeapon) <= 0)
		return TourniquetApply_NoKitUse;

	int helperUserId = GetClientUserId(helper);
	int currentHealerUserId = ga_iTourniquetHealerUserId[client];
	bool currentTreatmentActive = currentHealerUserId != 0
		&& ga_fLastTourniquetTick[client] > 0.0
		&& now - ga_fLastTourniquetTick[client] <= BLEEDOUT_TREAT_TICK * 1.5;

	if (currentTreatmentActive && currentHealerUserId != helperUserId) {
		// A medic may take over a slower non-medic attempt. Otherwise the first
		// active helper owns the treatment so progress cannot stack.
		if (!helperIsMedic || ga_bTourniquetHealerIsMedic[client])
			return TourniquetApply_Busy;
	}

	if (!currentTreatmentActive || currentHealerUserId != helperUserId) {
		ga_iTourniquetHealerUserId[client] = helperUserId;
		ga_bTourniquetHealerIsMedic[client] = helperIsMedic;
		ga_fTourniquetRemaining[client] = helperIsMedic
			? g_fTourniquetMedicTime
			: g_fTourniquetNonMedicTime;
		ga_fLastTourniquetTick[client] = now;

		if (!ga_bTourniquetPainPlayed[client]) {
			ga_bTourniquetPainPlayed[client] = true;
			PlayTourniquetPainSound(client);
		}
		return TourniquetApply_Progress;
	}

	if (!ga_bTourniquetPainPlayed[client]) {
		ga_bTourniquetPainPlayed[client] = true;
		PlayTourniquetPainSound(client);
	}

	float elapsed = now - ga_fLastTourniquetTick[client];
	if (elapsed >= BLEEDOUT_TREAT_TICK * 0.5) {
		ga_fLastTourniquetTick[client] = now;
		ga_fTourniquetRemaining[client] -= BLEEDOUT_TREAT_TICK;
	}

	if (ga_fTourniquetRemaining[client] <= 0.0) {
		if (!helperIsMedic && !ConsumeFirstAidKitUse(helper, activeWeapon)) {
			ResetTourniquetTreatment(client);
			return TourniquetApply_NoKitUse;
		}

		CompleteTourniquet(client, helper);
		return TourniquetApply_Completed;
	}

	return TourniquetApply_Progress;
}

public Action Timer_RemoveBleedParticle(Handle timer, int particleRef) {
	SafeKillRef(particleRef);
	return Plugin_Stop;
}

public bool TraceFilter_BleedPuddle(int entity, int contentsMask, any data) {
	if (entity == data)
		return false;
	return entity > MaxClients;
}

public Action Timer_SpawnBleedPuddle(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Stop;

	int ragdoll = GetClientRagdollEntity(client);
	if (ragdoll == INVALID_ENT_REFERENCE)
		return Plugin_Stop;

	float start[3], end[3], position[3];
	GetEntPropVector(ragdoll, Prop_Data, "m_vecAbsOrigin", start);
	VecCopy(start, end);
	start[2] += 32.0;
	end[2] -= 160.0;

	Handle trace = TR_TraceRayFilterEx(start, end, MASK_SOLID, RayType_EndPoint, TraceFilter_BleedPuddle, ragdoll);
	if (TR_DidHit(trace))
		TR_GetEndPosition(position, trace);
	else {
		VecCopy(end, position);
		position[2] += 1.0;
	}
	delete trace;

	position[2] += 1.0;
	RemoveBleedPuddle(client);
	ga_iBleedPuddleRef[client] = CreateBleedParticle("blood_bleedout", position);
	if (ga_iBleedPuddleRef[client] != INVALID_ENT_REFERENCE)
		CreateTimer(g_fBleedoutPuddleLifetime, Timer_RemoveBleedParticle, ga_iBleedPuddleRef[client], TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}

static void SendBleedoutFade(int client, int alpha) {
	Handle message = StartMessageOne("Fade", client, USERMSG_RELIABLE);
	if (message == null)
		return;

	int color[4];
	color[0] = 80;
	color[1] = 0;
	color[2] = 0;
	color[3] = alpha;

	if (GetUserMessageType() == UM_Protobuf) {
		PbSetInt(message, "duration", 256);
		PbSetInt(message, "hold_time", 0);
		PbSetInt(message, "flags", BLEED_FADE_IN);
		PbSetColor(message, "clr", color);
	}
	else {
		BfWriteShort(message, 256);
		BfWriteShort(message, 0);
		BfWriteShort(message, BLEED_FADE_IN);
		BfWriteByte(message, color[0]);
		BfWriteByte(message, color[1]);
		BfWriteByte(message, color[2]);
		BfWriteByte(message, color[3]);
	}

	EndMessage();
}

static void UpdateBleedoutFade(int client, float now, float remaining) {
	if (IsFakeClient(client)
		|| !g_bBleedoutFadeEnabled
		|| now < ga_fNextBleedFadeAt[client])
		return;

	float fraction = remaining / g_fBleedoutTime;
	if (fraction < 0.0)
		fraction = 0.0;
	else if (fraction > 1.0)
		fraction = 1.0;

	ga_fNextBleedFadeAt[client] = now + 0.5 + fraction * 0.9;
	int alpha = RoundToNearest(float(g_iBleedoutFadeAlpha) * (0.55 + (1.0 - fraction) * 0.45));
	SendBleedoutFade(client, alpha);
}

static void ClearDestroyedBleedParticleRefs() {
	for (int client = 1; client <= MaxClients; client++) {
		if (ga_iBleedParticleRef[client] != INVALID_ENT_REFERENCE
			&& EntRefToEntIndex(ga_iBleedParticleRef[client]) == INVALID_ENT_REFERENCE)
			ga_iBleedParticleRef[client] = INVALID_ENT_REFERENCE;

		if (ga_iBleedPuddleRef[client] != INVALID_ENT_REFERENCE
			&& EntRefToEntIndex(ga_iBleedPuddleRef[client]) == INVALID_ENT_REFERENCE)
			ga_iBleedPuddleRef[client] = INVALID_ENT_REFERENCE;

	}
}

static void CleanupAllBleedParticles() {
	for (int client = 1; client <= MaxClients; client++) {
		RemoveBleedParticle(client);
		RemoveBleedPuddle(client);
		RemoveBleedMarkers(client);
		ga_bBleedPuddlePending[client] = false;
	}
}

static void CleanupOrphanedBleedMarkers() {
	ArrayList orphanRefs = new ArrayList();
	char targetName[64];
	int entity = -1;

	while ((entity = FindEntityByClassname(entity, "env_sprite")) != -1) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if (StrContains(targetName, BLEEDOUT_MARKER_NAME, false) != 0)
			continue;

		int entref = EntIndexToEntRef(entity);
		if (entref != INVALID_ENT_REFERENCE)
			orphanRefs.Push(entref);
	}

	for (int i = 0; i < orphanRefs.Length; i++)
		SafeKillRef(orphanRefs.Get(i));

	delete orphanRefs;
}

static void TrackHealthkit(int entity) {
	if (g_hTrackedHealthkits == null || entity <= MaxClients || !IsValidEntity(entity))
		return;

	int entref = EntIndexToEntRef(entity);
	if (entref == INVALID_ENT_REFERENCE)
		return;

	for (int i = 0; i < g_hTrackedHealthkits.Length; i++) {
		if (g_hTrackedHealthkits.Get(i) == entref)
			return;
	}

	g_hTrackedHealthkits.Push(entref);
}

static void UntrackHealthkit(int entity) {
	if (g_hTrackedHealthkits == null || entity <= MaxClients)
		return;

	int entref = EntIndexToEntRef(entity);
	if (entref == INVALID_ENT_REFERENCE)
		return;

	for (int i = g_hTrackedHealthkits.Length - 1; i >= 0; i--) {
		if (g_hTrackedHealthkits.Get(i) == entref) {
			g_hTrackedHealthkits.Erase(i);
			return;
		}
	}
}

static void CleanupTrackedHealthkits() {
	if (g_hTrackedHealthkits == null)
		return;

	for (int i = g_hTrackedHealthkits.Length - 1; i >= 0; i--) {
		int entref = g_hTrackedHealthkits.Get(i);
		int entity = EntRefToEntIndex(entref);

		if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity)) {
			g_hTrackedHealthkits.Erase(i);
			continue;
		}

		SafeKillRef(entref);
	}

	g_hTrackedHealthkits.Clear();
}

static void CleanupOrphanedHealthkits() {
	ArrayList orphanRefs = new ArrayList();
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "healthkit")) != -1) {
		int entref = EntIndexToEntRef(entity);
		if (entref != INVALID_ENT_REFERENCE)
			orphanRefs.Push(entref);
	}

	for (int i = 0; i < orphanRefs.Length; i++)
		SafeKillRef(orphanRefs.Get(i));

	delete orphanRefs;
}

static bool EntHasPhysicsObject(int ent) {
	if (ent <= MaxClients || !IsValidEntity(ent))
		return false;

	if (g_iOffsPhysicsObject == -1) {
		g_iOffsPhysicsObject = FindDataMapInfo(ent, "m_pPhysicsObject");
		if (g_iOffsPhysicsObject == -1)
			g_iOffsPhysicsObject = -2;
	}

	if (g_iOffsPhysicsObject == -2)
		return true;

	return (GetEntData(ent, g_iOffsPhysicsObject) != 0);
}

static void ClearPendingRagTeleport(int client) {
	ga_iPendingRagTeleportRef[client] = INVALID_ENT_REFERENCE;
	ga_iPendingRagTeleportTries[client] = 0;

	ga_fPendingRagTeleportPos[client][0] = 0.0;
	ga_fPendingRagTeleportPos[client][1] = 0.0;
	ga_fPendingRagTeleportPos[client][2] = 0.0;

	ga_fPendingRagTeleportAng[client][0] = 0.0;
	ga_fPendingRagTeleportAng[client][1] = 0.0;
	ga_fPendingRagTeleportAng[client][2] = 0.0;

	ga_fPendingRagTeleportVel[client][0] = 0.0;
	ga_fPendingRagTeleportVel[client][1] = 0.0;
	ga_fPendingRagTeleportVel[client][2] = 0.0;
}

void Frame_TeleportPendingRagdoll(int userid) {
	int client = GetClientOfUserId(userid);
	if (client < 1 || client > MaxClients)
		return;

	int ref = ga_iPendingRagTeleportRef[client];
	if (ref == INVALID_ENT_REFERENCE)
		return;

	int ent = EntRefToEntIndex(ref);
	if (ent == INVALID_ENT_REFERENCE || ent <= MaxClients || !IsValidEntity(ent)) {
		ClearPendingRagTeleport(client);
		return;
	}

	if (!EntHasPhysicsObject(ent)) {
		if (++ga_iPendingRagTeleportTries[client] >= 10) {
			ClearPendingRagTeleport(client);
			return;
		}

		RequestFrame(Frame_TeleportPendingRagdoll, userid);
		return;
	}

	TeleportEntity(ent, ga_fPendingRagTeleportPos[client], ga_fPendingRagTeleportAng[client], ga_fPendingRagTeleportVel[client]);
	AcceptEntityInput(ent, "Wake");
	
	if (g_hFwdRagdollReady != null) {
		Call_StartForward(g_hFwdRagdollReady);
		Call_PushCell(client);
		Call_PushCell(EntIndexToEntRef(ent));
		Call_Finish();
	}

	if (ga_bBleedPuddlePending[client]) {
		ga_bBleedPuddlePending[client] = false;
		CreateTimer(0.35, Timer_SpawnBleedPuddle, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}

	ClearPendingRagTeleport(client);
}

void RemoveRagdoll(int client) {
	if (client < 1 || client > MaxClients) return;

	ClearPendingRagTeleport(client);

	int ref = ga_iClientRagdolls[client];
	if (ref == INVALID_ENT_REFERENCE) return;

	int entity = EntRefToEntIndex(ref);

	ga_iClientRagdolls[client] = INVALID_ENT_REFERENCE;

	if (entity > MaxClients && IsValidEntity(entity)) {
		bool dragged = false;
		if (GetFeatureStatus(FeatureType_Native, "Drag_IsEntityDragged") == FeatureStatus_Available)
			dragged = Drag_IsEntityDragged(entity);

		if (dragged && GetFeatureStatus(FeatureType_Native, "Drag_ForceDrop") == FeatureStatus_Available)
			Drag_ForceDrop(entity);

		SafeKillRef(ref);
	}
}

static void CleanupOrphanedMedicRagdolls() {
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_ragdoll")) != -1) {
		if (!HasEntProp(entity, Prop_Data, "m_iName"))
			continue;

		char targetname[64];
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if (StrContains(targetname, "playervital_ragdoll_", false) != 0)
			continue;

		bool dragged = false;
		if (GetFeatureStatus(FeatureType_Native, "Drag_IsEntityDragged") == FeatureStatus_Available)
			dragged = Drag_IsEntityDragged(entity);

		if (dragged && GetFeatureStatus(FeatureType_Native, "Drag_ForceDrop") == FeatureStatus_Available)
			Drag_ForceDrop(entity);

		SafeKillIdx(entity);
	}
}

void RespawnPlayerRevive(int client) {	// Revive player
	if (!IsClientInGame(client)) return;
	if (IsPlayerAlive(client) || !g_bRoundActive) return;

	SDKCall(g_hForceRespawn, client);	// Call forcerespawn fucntion
	SetEntProp(client, Prop_Send, "m_iDesiredStance", 2);	//spawn player in prone position

	int iHealth = GetClientHealth(client);
	if (ga_bRevivedByMedic[client]) {
		if (ga_iPlayerWoundType[client] == 0)
			iHealth = g_iMedicMinorReviveHp;
		else if (ga_iPlayerWoundType[client] == 1)
			iHealth = g_iMedicModerateReviveHp;
		else if (ga_iPlayerWoundType[client] == 2)
			iHealth = g_iMedicCriticalReviveHp;
	} else
		iHealth = g_iNonMedicReviveHp;

	SetEntityHealth(client, iHealth);
	RemoveRagdoll(client);	//Remove network ragdoll
	RespawnPlayerRevivePost(client);
}

void RespawnPlayerRevivePost(int client) {
	TeleportEntity(client, ga_fRagdollPosition[client], NULL_VECTOR, NULL_VECTOR);
	// Reset ragdoll position
	ga_fRagdollPosition[client][0] = 0.0;
	ga_fRagdollPosition[client][1] = 0.0;
	ga_fRagdollPosition[client][2] = 0.0;
}

void SendReviveFeedEvent(int reviver, int revivedPlayer) {
	if (reviver < 1 || reviver > MaxClients || revivedPlayer < 1 || revivedPlayer > MaxClients)
		return;
	if (!IsClientInGame(reviver) || !IsClientInGame(revivedPlayer) || !IsPlayerAlive(revivedPlayer))
		return;

	Event event = CreateEvent("player_death", true);
	if (event == null)
		return;

	char revivedName[MAX_NAME_LENGTH];
	char feedText[96];
	GetClientName(revivedPlayer, revivedName, sizeof(revivedName));

	bool deathNoticeCanDisplayName = true;
	for (int i = 0; revivedName[i] != '\0'; i++) {
		// Insurgency's death-notice weapon field does not decode UTF-8.
		if ((revivedName[i] & 0x80) != 0) {
			deathNoticeCanDisplayName = false;
			break;
		}
	}

	if (deathNoticeCanDisplayName)
		FormatEx(feedText, sizeof(feedText), "revived %s", revivedName);
	else
		FormatEx(feedText, sizeof(feedText), "revived teammate");

	event.SetInt("userid", 0);
	event.SetInt("attacker", GetClientUserId(reviver));
	event.SetString("weapon", feedText);

	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || IsFakeClient(client))
			continue;

		event.FireToClient(client);
	}

	event.Cancel();
}

void ResetAutoThanksClient(int client) {
	if (client < 1 || client > MaxClients)
		return;

	ga_bAutoThanks[client] = false;
	ga_bAutoThanksCookieLoaded[client] = false;
	ga_bAutoThanksNotifiedThisMap[client] = false;
	ga_iLastAutoThanksMessage[client] = -1;
}

void LoadAutoThanksCookie(int client) {
	if (client < 1 || client > MaxClients || g_hAutoThanksCookie == null)
		return;

	char value[8];
	GetClientCookie(client, g_hAutoThanksCookie, value, sizeof(value));
	ga_bAutoThanks[client] = StrEqual(value, "1");
	ga_bAutoThanksCookieLoaded[client] = true;
}

public Action Cmd_AutoThanks(int client, int args) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Handled;

	if (g_hAutoThanksCookie == null || !AreClientCookiesCached(client)) {
		PrintToChat(client, "\x070088cc[Medic]\x01 Your Auto Thanks preference is still loading. Please try again shortly.");
		return Plugin_Handled;
	}

	if (!ga_bAutoThanksCookieLoaded[client])
		LoadAutoThanksCookie(client);

	ga_bAutoThanks[client] = !ga_bAutoThanks[client];
	if (ga_bAutoThanks[client])
		SetClientCookie(client, g_hAutoThanksCookie, "1");
	else
		SetClientCookie(client, g_hAutoThanksCookie, "0");

	if (ga_bAutoThanks[client]) {
		PrintToChat(client, "\x070088cc[Medic]\x01 Auto Thanks enabled. Your choice has been saved.");
		if (!g_bAutoThanksEnabled)
			PrintToChat(client, "\x070088cc[Medic]\x01 Auto Thanks is currently disabled by the server.");
	} else {
		PrintToChat(client, "\x070088cc[Medic]\x01 Auto Thanks disabled. Your choice has been saved.");
	}

	return Plugin_Handled;
}

void SanitizeAutoThanksMessage(char[] message, int maxlen) {
	ReplaceString(message, maxlen, "\"", "'");
	ReplaceString(message, maxlen, ";", ",");
	ReplaceString(message, maxlen, "\\", "/");

	for (int i = 0; message[i] != '\0'; i++) {
		if (message[i] > 0 && message[i] < 32)
			message[i] = ' ';
	}

	TrimString(message);
}

void HandleAutoThanks(int revivedPlayer, int reviver) {
	if (!g_bAutoThanksEnabled)
		return;
	if (revivedPlayer < 1 || revivedPlayer > MaxClients || reviver < 1 || reviver > MaxClients)
		return;
	if (!IsClientInGame(revivedPlayer) || IsFakeClient(revivedPlayer) || !IsPlayerAlive(revivedPlayer))
		return;
	if (!IsClientInGame(reviver) || GetClientTeam(revivedPlayer) != TEAM_SECURITY || GetClientTeam(reviver) != TEAM_SECURITY)
		return;

	if (!ga_bAutoThanksCookieLoaded[revivedPlayer]) {
		if (!AreClientCookiesCached(revivedPlayer))
			return;
		LoadAutoThanksCookie(revivedPlayer);
	}

	bool firstReviveThisMap = !ga_bAutoThanksNotifiedThisMap[revivedPlayer];
	ga_bAutoThanksNotifiedThisMap[revivedPlayer] = true;

	if (!ga_bAutoThanks[revivedPlayer]) {
		if (firstReviveThisMap) {
			PrintToChat(revivedPlayer, "\x070088cc[Medic]\x01 Auto Thanks is available. Type \x0700cc44!autoty\x01 to automatically thank teammates who revive you. Your choice will be saved.");
		}
		return;
	}

	int messageCount = sizeof(g_sAutoThanksMessages);
	int messageIndex;
	if (ga_iLastAutoThanksMessage[revivedPlayer] >= 0 && messageCount > 1) {
		messageIndex = GetRandomInt(0, messageCount - 2);
		if (messageIndex >= ga_iLastAutoThanksMessage[revivedPlayer])
			messageIndex++;
	} else {
		messageIndex = GetRandomInt(0, messageCount - 1);
	}

	ga_iLastAutoThanksMessage[revivedPlayer] = messageIndex;

	char message[256];
	FormatEx(message, sizeof(message), g_sAutoThanksMessages[messageIndex], reviver);
	SanitizeAutoThanksMessage(message, sizeof(message));
	if (message[0] == '\0')
		return;

	if (GetFeatureStatus(FeatureType_Native, "ChatFilter_BypassNextMessage") == FeatureStatus_Available)
		ChatFilter_BypassNextMessage(revivedPlayer, message);

	FakeClientCommand(revivedPlayer, "say_team \"%s\"", message);
}

// Handles reviving for medics and non-medics
Action Timer_ReviveMonitor(Handle timer) {
	if (!g_bRoundActive)
		return Plugin_Continue;

	// Prevent multiple players decrementing the same revive timer in the same second
	static int s_iLastMedicDec[MAXPLAYERS + 1];
	static int s_iLastNonMedicDec[MAXPLAYERS + 1];

	float	flalivePlayerPosition[3];

	const float fReviveDistanceSq = 9025.0;

	int		deadPlayer,
			deadPlayerRagdoll,
			ActiveWeapon;

	char	woundType[20];
	int now = GetTime();

	for (int alivePlayer = 1; alivePlayer <= MaxClients; alivePlayer++) {
		if (!IsClientInGame(alivePlayer) || GetClientTeam(alivePlayer) != TEAM_SECURITY || !IsPlayerAlive(alivePlayer))
			continue;

		deadPlayer = ga_iNearestBody[alivePlayer];
		if (deadPlayer <= 0
			|| !IsClientInGame(deadPlayer)
			|| IsPlayerAlive(deadPlayer)
			|| ga_bHurtFatal[deadPlayer]
			|| deadPlayer == alivePlayer
			|| GetClientTeam(deadPlayer) != TEAM_SECURITY)
			continue;

		bool bCanHealPaddle, bCanHealMedpack;
		if (!GetClientSupportWeaponState(alivePlayer, ActiveWeapon, bCanHealPaddle, bCanHealMedpack))
			continue;

		deadPlayerRagdoll = GetClientRagdollEntity(deadPlayer);
		if (deadPlayerRagdoll == INVALID_ENT_REFERENCE)
			continue;

		GetClientAbsOrigin(alivePlayer, flalivePlayerPosition);
		GetEntPropVector(deadPlayerRagdoll, Prop_Data, "m_vecAbsOrigin", ga_fRagdollPosition[deadPlayer]);

		if (GetVectorDistanceSquared(ga_fRagdollPosition[deadPlayer], flalivePlayerPosition) > fReviveDistanceSq
			|| !ClientCanSeeVector(alivePlayer, ga_fRagdollPosition[deadPlayer]))
			continue;

		GetWoundTypeString(deadPlayer, woundType, sizeof(woundType));

		if (ga_bIsMedic[alivePlayer]) {
			/* I'm a medic */

			if (!bCanHealPaddle)
				continue;

			ga_bBeingRevivedByMedic[deadPlayer] = true;
			ga_iTimeReviveCheck[deadPlayer] = now;

			if (ga_iReviveRemainingTime[deadPlayer] > 0) {
				PrintHintText(alivePlayer, "Reviving %N in: %i seconds (%s)", deadPlayer, ga_iReviveRemainingTime[deadPlayer], woundType);
				PrintHintText(deadPlayer, "%N is reviving you in: %i seconds (%s)", alivePlayer, ga_iReviveRemainingTime[deadPlayer], woundType);

				if (s_iLastMedicDec[deadPlayer] != now) {
					s_iLastMedicDec[deadPlayer] = now;
					ga_iReviveRemainingTime[deadPlayer]--;
				}
				continue;
			}

			PrintHintText(alivePlayer, "You revived %N from a %s", deadPlayer, woundType);
			PrintHintText(deadPlayer, "%N revived you from a %s", alivePlayer, woundType);

			PlayVictimReviveSound(deadPlayer);
			EmitSoundToAll("weapons/defibrillator/defibrillator_revive.wav", alivePlayer, SNDCHAN_AUTO, _, _, 0.3);

			ga_iStatRevives[alivePlayer]++;

			Check_NearbyMedicsRevive(alivePlayer, deadPlayer);
			ga_bRevivedByMedic[deadPlayer] = true;
			ga_bBeingRevivedByMedic[deadPlayer] = false;
			s_iLastMedicDec[deadPlayer] = 0;

			RespawnPlayerRevive(deadPlayer);
			LogToGame("\"%L\" triggered \"revived\" against \"%L\"", alivePlayer, deadPlayer);
			SendReviveFeedEvent(alivePlayer, deadPlayer);
			HandleAutoThanks(deadPlayer, alivePlayer);
		} else {
			/* I'm not a medic */

			if (!bCanHealMedpack)
				continue;

			if (ga_iReviveNonMedicRemainingTime[deadPlayer] > 0) {
				PrintHintText(alivePlayer, "Reviving %N in: %i seconds (%s)", deadPlayer, ga_iReviveNonMedicRemainingTime[deadPlayer], woundType);
				PrintHintText(deadPlayer, "%N is reviving you in: %i seconds (%s)", alivePlayer, ga_iReviveNonMedicRemainingTime[deadPlayer], woundType);

				if (s_iLastNonMedicDec[deadPlayer] != now) {
					s_iLastNonMedicDec[deadPlayer] = now;
					ga_iReviveNonMedicRemainingTime[deadPlayer]--;
				}
				continue;
			}

			PrintHintText(alivePlayer, "You revived %N from a %s", deadPlayer, woundType);
			PrintHintText(deadPlayer, "%N revived you from a %s", alivePlayer, woundType);

			PlayVictimReviveSound(deadPlayer);
			ga_iStatRevives[alivePlayer]++;

			Check_NearbyMedicsRevive(alivePlayer, deadPlayer);
			ga_bRevivedByMedic[deadPlayer] = false;
			s_iLastNonMedicDec[deadPlayer] = 0;

			RespawnPlayerRevive(deadPlayer);
			LogToGame("\"%L\" triggered \"revived\" against \"%L\"", alivePlayer, deadPlayer);
			SendReviveFeedEvent(alivePlayer, deadPlayer);
			HandleAutoThanks(deadPlayer, alivePlayer);

			int iAmmoType = GetEntProp(ActiveWeapon, Prop_Data, "m_iPrimaryAmmoType");
			int iAmmo = GetEntProp(alivePlayer, Prop_Data, "m_iAmmo", _, iAmmoType);

			if (iAmmo > 0)
				SetEntProp(alivePlayer, Prop_Send, "m_iAmmo", iAmmo - 1, _, iAmmoType);

			if (iAmmo == 1) {
				if (GetPlayerWeaponSlot(alivePlayer, 0) > 0)
					ClientCommand(alivePlayer, "slot1");
				else if (GetPlayerWeaponSlot(alivePlayer, 1) > 0)
					ClientCommand(alivePlayer, "slot2");
			}
		}
	}

	char statusWoundType[20];
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client))
			continue;
		if (!ga_bPlayerPickSquad[client]
			|| IsPlayerAlive(client)
			|| GetClientTeam(client) != TEAM_SECURITY
			|| !g_bReviveActive
			|| ga_bPlayerSelectNewClass[client])
			continue;

		if (ga_bHurtFatal[client]) {
			PrintCenterText(client, "You were fatally killed for %i damage and must wait til next objective to spawn", ga_iClientDamageDone[client]);
			continue;
		}

		GetWoundTypeString(client, statusWoundType, sizeof(statusWoundType));
		PrintCenterText(client, "[You're %s for %d damage]..wait patiently for a medic..do NOT mic/chat spam!", statusWoundType, ga_iClientDamageDone[client]);
	}

	return Plugin_Continue;
}

// Handles medic functions (Inspecting health, healing)
Action Timer_MedicMonitor(Handle timer) {
	if (!g_bRoundActive)
		return Plugin_Continue;

	// Throttle healer HintText to avoid “ghosting” from rapid refresh.
	// (Insurgency 2014 doesn't support SyncHud.)
	static char sLastHint[MAXPLAYERS + 1][256];
	static float fNextHintAt[MAXPLAYERS + 1];

	float now = GetGameTime();
	UpdateBleedoutStates(now);

	bool	bCanHealPaddle = false,
			bCanHealMedpack = false;

	const float fReviveDistanceSq = 9025.0;
	const float fInspectDistanceSq = 562500.0;

	float
			vecOriginatingPlayer[3],
			vecTargetPlayer[3],
			tDistanceSq;

	int		ActiveWeapon,
			iHealth,
			targetPlayer;

	for (int originatingPlayer = 1; originatingPlayer <= MaxClients; originatingPlayer++) {
		char sNewHint[256];
		sNewHint[0] = '\0';
		CloseExpiredHealingSession(originatingPlayer, now);

		if (!IsClientInGame(originatingPlayer) || !IsPlayerAlive(originatingPlayer) || GetClientTeam(originatingPlayer) != TEAM_SECURITY) {
			sLastHint[originatingPlayer][0] = '\0';
			fNextHintAt[originatingPlayer] = 0.0;
			continue;
		}

		if (!GetClientSupportWeaponState(originatingPlayer, ActiveWeapon, bCanHealPaddle, bCanHealMedpack)) {
			sLastHint[originatingPlayer][0] = '\0';
			fNextHintAt[originatingPlayer] = 0.0;
			continue;
		}

		if (!bCanHealPaddle && !bCanHealMedpack) {
			sLastHint[originatingPlayer][0] = '\0';
			fNextHintAt[originatingPlayer] = 0.0;
			continue;
		}

		if (ga_bIsMedic[originatingPlayer]) {
			/* I'm a medic */

			targetPlayer = TraceClientViewEntity(originatingPlayer);
			if (targetPlayer > 0 && targetPlayer <= MaxClients && IsClientInGame(targetPlayer) && IsPlayerAlive(targetPlayer) && GetClientTeam(targetPlayer) == TEAM_SECURITY) {
				GetClientAbsOrigin(originatingPlayer, vecOriginatingPlayer);
				GetClientAbsOrigin(targetPlayer, vecTargetPlayer);
				tDistanceSq = GetVectorDistanceSquared(vecOriginatingPlayer, vecTargetPlayer);

				iHealth = GetClientHealth(targetPlayer);

				bool bInHealRange = (tDistanceSq <= fReviveDistanceSq && ClientCanSeeVector(originatingPlayer, vecTargetPlayer));

				if (bInHealRange && ga_bBleedingOut[targetPlayer]) {
					TourniquetApplyResult result = ApplyTourniquetTick(originatingPlayer, targetPlayer, ActiveWeapon, now);
					if (result == TourniquetApply_Completed)
						Format(sNewHint, sizeof(sNewHint), "%N\nTourniquet secured\nContinue healing", targetPlayer);
					else if (result == TourniquetApply_Busy)
						Format(sNewHint, sizeof(sNewHint), "%N\nAnother teammate is applying the tourniquet", targetPlayer);
					else {
						Format(sNewHint, sizeof(sNewHint), "%N\nApplying tourniquet: %.1f seconds",
							targetPlayer, ga_fTourniquetRemaining[targetPlayer]);
						PrintHintText(targetPlayer, "%N is applying a tourniquet: %.1f seconds",
							originatingPlayer, ga_fTourniquetRemaining[targetPlayer]);
					}
				} else if (bInHealRange && iHealth < 100) {
					int iAmount = bCanHealPaddle && !bCanHealMedpack ? g_iHealAmountPaddles : g_iHealAmountMedpack;
					int restoredHP = iAmount;
					if (restoredHP > 100 - iHealth)
						restoredHP = 100 - iHealth;

					iHealth += restoredHP;
					RecordHealingTick(originatingPlayer, targetPlayer, restoredHP, now);

					if (iHealth >= 100) {
						ga_iStatHeals[originatingPlayer]++;
						iHealth = 100;
						PrintHintText(targetPlayer, "You were healed by %N (HP: %i)", originatingPlayer, iHealth);
						PrintHintText(originatingPlayer, "You fully healed %N", targetPlayer);
						PrintToChat(originatingPlayer, "\x01You fully healed \x070088cc%N", targetPlayer);
						LogToGame("\"%L\" triggered \"healed\" against \"%L\"", originatingPlayer, targetPlayer);
					} else
						PrintHintText(targetPlayer, "DON'T MOVE! %N is healing you.(HP: %i)", originatingPlayer, iHealth);

					SetEntityHealth(targetPlayer, iHealth);
					if (iHealth >= 100)
						CloseHealingSession(originatingPlayer);

					Format(sNewHint, sizeof(sNewHint),
						"%N  HP: %i\nHealing: %s +%i",
						targetPlayer, iHealth,
						(bCanHealPaddle && !bCanHealMedpack) ? "paddle" : "medpack",
						restoredHP
					);
				} else if (tDistanceSq < fInspectDistanceSq)
					Format(sNewHint, sizeof(sNewHint), "%N\nHP: %i", targetPlayer, iHealth);
			} else {
				iHealth = GetClientHealth(originatingPlayer);
				if (ga_bBleedingOut[originatingPlayer])
					Format(sNewHint, sizeof(sNewHint), "ARTERIAL BLEEDING\nYou cannot apply your own tourniquet");
				else if (iHealth < g_iMedicHealSelfMax) {
					int iAmount = bCanHealPaddle && !bCanHealMedpack ? g_iHealAmountPaddles : g_iHealAmountMedpack;

					iHealth += iAmount;
					if (iHealth > g_iMedicHealSelfMax)
						iHealth = g_iMedicHealSelfMax;

					SetEntityHealth(originatingPlayer, iHealth);
					Format(sNewHint, sizeof(sNewHint), "Healing Self (HP: %i) | MAX: %i", iHealth, g_iMedicHealSelfMax);
				}
			}
		} else {
			/* I'm not a medic */

			if (!bCanHealMedpack) {
				sLastHint[originatingPlayer][0] = '\0';
				fNextHintAt[originatingPlayer] = 0.0;
				continue;
			}

			targetPlayer = TraceClientViewEntity(originatingPlayer);
			if (targetPlayer > 0 && targetPlayer <= MaxClients && IsClientInGame(targetPlayer) && IsPlayerAlive(targetPlayer) && GetClientTeam(targetPlayer) == TEAM_SECURITY) {
				GetClientAbsOrigin(originatingPlayer, vecOriginatingPlayer);
				GetClientAbsOrigin(targetPlayer, vecTargetPlayer);
				tDistanceSq = GetVectorDistanceSquared(vecOriginatingPlayer, vecTargetPlayer);

				if (tDistanceSq <= fReviveDistanceSq && ClientCanSeeVector(originatingPlayer, vecTargetPlayer)) {
					iHealth = GetClientHealth(targetPlayer);

					if (ga_bBleedingOut[targetPlayer]) {
						TourniquetApplyResult result = ApplyTourniquetTick(originatingPlayer, targetPlayer, ActiveWeapon, now);
						if (result == TourniquetApply_Completed)
							Format(sNewHint, sizeof(sNewHint), "%N\nTourniquet secured\n1 first-aid kit use consumed", targetPlayer);
						else if (result == TourniquetApply_Busy)
							Format(sNewHint, sizeof(sNewHint), "%N\nAnother teammate is applying the tourniquet", targetPlayer);
						else if (result == TourniquetApply_NoKitUse)
							Format(sNewHint, sizeof(sNewHint), "%N\nNo first-aid kit uses remaining", targetPlayer);
						else {
							Format(sNewHint, sizeof(sNewHint), "%N\nApplying tourniquet: %.1f seconds",
								targetPlayer, ga_fTourniquetRemaining[targetPlayer]);
							PrintHintText(targetPlayer, "%N is applying a tourniquet: %.1f seconds",
								originatingPlayer, ga_fTourniquetRemaining[targetPlayer]);
						}
					}
					else if (iHealth < g_iNonMedicMaxHealOther) {
						int iAmount = g_iNonMedicHealAmt;
						int restoredHP = iAmount;
						if (restoredHP > g_iNonMedicMaxHealOther - iHealth)
							restoredHP = g_iNonMedicMaxHealOther - iHealth;

						iHealth += restoredHP;
						RecordHealingTick(originatingPlayer, targetPlayer, restoredHP, now);

						if (iHealth >= g_iNonMedicMaxHealOther) {
							ga_iStatHeals[originatingPlayer]++;
							iHealth = g_iNonMedicMaxHealOther;
							PrintHintText(targetPlayer, "Non-Medic %N can only heal you to %i HP!", originatingPlayer, iHealth);
							PrintHintText(originatingPlayer, "You max healed %N", targetPlayer);
							PrintToChat(originatingPlayer, "\x01You max healed \x070088cc%N", targetPlayer);
							LogToGame("\"%L\" triggered \"healed\" against \"%L\"", originatingPlayer, targetPlayer);
						} else
							PrintHintText(targetPlayer, "DON'T MOVE! %N is healing you.(HP: %i)", originatingPlayer, iHealth);

						SetEntityHealth(targetPlayer, iHealth);
						if (iHealth >= g_iNonMedicMaxHealOther)
							CloseHealingSession(originatingPlayer);
						Format(sNewHint, sizeof(sNewHint), "%N\nHP: %i\nHealing.", targetPlayer, iHealth);
					} else
						Format(sNewHint, sizeof(sNewHint), "%N\nHP: %i (MAX YOU CAN HEAL)", targetPlayer, iHealth);
				}
			} else {
				iHealth = GetClientHealth(originatingPlayer);
				if (ga_bBleedingOut[originatingPlayer])
					Format(sNewHint, sizeof(sNewHint), "ARTERIAL BLEEDING\nYou cannot apply your own tourniquet");
				else if (iHealth < g_iNonMedicHealSelfMax) {
					iHealth += g_iNonMedicHealAmt;
					if (iHealth > g_iNonMedicHealSelfMax)
						iHealth = g_iNonMedicHealSelfMax;

					SetEntityHealth(originatingPlayer, iHealth);
					Format(sNewHint, sizeof(sNewHint), "Healing Self (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
				}
			}
		}

		if (sNewHint[0]) {
			if (now >= fNextHintAt[originatingPlayer] || !StrEqual(sNewHint, sLastHint[originatingPlayer])) {
				PrintHintText(originatingPlayer, "%s", sNewHint);
				strcopy(sLastHint[originatingPlayer], sizeof(sLastHint[]), sNewHint);
				fNextHintAt[originatingPlayer] = now + 0.75;
			}
		} else {
			sLastHint[originatingPlayer][0] = '\0';
			fNextHintAt[originatingPlayer] = 0.0;
		}
	}

	return Plugin_Continue;
}

Action Timer_NearestBody(Handle timer) {
	if (!g_bRoundActive)
		return Plugin_Continue;

	float	flAlivePlayerPosition[3],
			flAlivePlayerAngle[3],
			flClosestDistanceSq,
			fTempDistanceSq,
			flShortestDistanceSq;

	int		closestDeadPlayer,
			closestDeadPlayerWithoutMedic,
			now;

	int deadPlayers[MAXPLAYERS + 1];
	int deadPlayerCount = 0;

	char	sDirection[64],
			sDistance[64],
			sHeight[64],
			sDeadLine[160];

	now = GetTime();

	// Build the revivable-body list once per tick instead of validating every
	// dead client again for every living player.
	for (int deadPlayer = 1; deadPlayer <= MaxClients; deadPlayer++) {
		if (!IsClientInGame(deadPlayer)
			|| IsPlayerAlive(deadPlayer)
			|| GetClientTeam(deadPlayer) != TEAM_SECURITY
			|| ga_bHurtFatal[deadPlayer]
			|| GetClientRagdollEntity(deadPlayer) == INVALID_ENT_REFERENCE)
			continue;

		if (ga_bBeingRevivedByMedic[deadPlayer]
			&& (now - ga_iTimeReviveCheck[deadPlayer]) >= 2)
			ga_bBeingRevivedByMedic[deadPlayer] = false;

		deadPlayers[deadPlayerCount++] = deadPlayer;
	}

	for (int alivePlayer = 1; alivePlayer <= MaxClients; alivePlayer++) {
		if (!IsClientInGame(alivePlayer) || GetClientTeam(alivePlayer) != TEAM_SECURITY || !IsPlayerAlive(alivePlayer))
			continue;

		closestDeadPlayer = 0;
		closestDeadPlayerWithoutMedic = 0;
		flClosestDistanceSq = 0.0;
		flShortestDistanceSq = 0.0;
		sDeadLine[0] = '\0';
		GetClientAbsOrigin(alivePlayer, flAlivePlayerPosition);

		for (int i = 0; i < deadPlayerCount; i++) {
			int deadPlayer = deadPlayers[i];
			fTempDistanceSq = GetVectorDistanceSquared(flAlivePlayerPosition, ga_fRagdollPosition[deadPlayer]);

			if (flClosestDistanceSq == 0.0 || fTempDistanceSq < flClosestDistanceSq) {
				flClosestDistanceSq = fTempDistanceSq;
				closestDeadPlayer = deadPlayer;
			}

			if (ga_bIsMedic[alivePlayer]
				&& !ga_bBeingRevivedByMedic[deadPlayer]
				&& (flShortestDistanceSq == 0.0 || fTempDistanceSq < flShortestDistanceSq)) {
				flShortestDistanceSq = fTempDistanceSq;
				closestDeadPlayerWithoutMedic = deadPlayer;
			}
		}

		ga_iNearestBody[alivePlayer] = closestDeadPlayer != 0 ? closestDeadPlayer : -1;

		if (!ga_bIsMedic[alivePlayer])
			continue;

		if (closestDeadPlayerWithoutMedic != 0)
			GetClientAbsAngles(alivePlayer, flAlivePlayerAngle);

		if (closestDeadPlayerWithoutMedic != 0) {
			GetDirectionString(flAlivePlayerAngle, flAlivePlayerPosition, ga_fRagdollPosition[closestDeadPlayerWithoutMedic], sDirection, sizeof(sDirection));
			GetDistanceString(SquareRoot(flShortestDistanceSq), sDistance, sizeof(sDistance));
			GetHeightString(flAlivePlayerPosition, ga_fRagdollPosition[closestDeadPlayerWithoutMedic], sHeight, sizeof(sHeight));
			FormatEx(sDeadLine, sizeof(sDeadLine), "Nearest dead[%d]: %N ( %s | %s | %s )",
				deadPlayerCount, closestDeadPlayerWithoutMedic, sDistance, sDirection, sHeight);
		}

		if (sDeadLine[0] != '\0')
			PrintCenterText(alivePlayer, "%s", sDeadLine);
	}
	return Plugin_Continue;
}

// Direction string: e.g., "FWD", "RIGHT", "BACK-LEFT"
void GetDirectionString(const float fClientAngles[3], const float fClientPosition[3], const float fTargetPosition[3], char[] outDir, int outLen) {
	float v[3], ang[3];
	MakeVectorFromPoints(fClientPosition, fTargetPosition, v);
	GetVectorAngles(v, ang);

	float diff = fClientAngles[1] - ang[1];
	if (diff < -180.0) diff += 360.0;
	if (diff >  180.0) diff -= 360.0;

	if      (diff >=  -22.5 && diff <   22.5) FormatEx(outDir, outLen, "FWD");
	else if (diff >=   22.5 && diff <   67.5) FormatEx(outDir, outLen, "FWD-RIGHT");
	else if (diff >=   67.5 && diff <  112.5) FormatEx(outDir, outLen, "RIGHT");
	else if (diff >=  112.5 && diff <  157.5) FormatEx(outDir, outLen, "BACK-RIGHT");
	else if (diff >=  157.5 || diff < -157.5) FormatEx(outDir, outLen, "BACK");
	else if (diff >= -157.5 && diff < -112.5) FormatEx(outDir, outLen, "BACK-LEFT");
	else if (diff >= -112.5 && diff <  -67.5) FormatEx(outDir, outLen, "LEFT");
	else /* diff >= -67.5 && diff < -22.5 */   FormatEx(outDir, outLen, "FWD-LEFT");
}

// Distance string: meters or feet based on g_bDistanceFeet
void GetDistanceString(float fDistance, char[] outStr, int outLen) {
	float meters = fDistance * 0.01905;
	if (g_bDistanceFeet) {
		float feet = meters * 3.2808399;
		FormatEx(outStr, outLen, "%.0f feet", feet);
	} else
		FormatEx(outStr, outLen, "%.0f meter", meters);
}

// Height relation string: ABOVE / BELOW / LEVEL
void GetHeightString(const float fClientPosition[3], const float fTargetPosition[3], char[] outStr, int outLen) {
	float dz = FloatAbs(fClientPosition[2] - fTargetPosition[2]);
	float meters = dz * 0.01905;

	if (g_bDistanceFeet) {
		float feet = meters * 3.2808399;
		if (fClientPosition[2] + 64.0 < fTargetPosition[2])      FormatEx(outStr, outLen, "ABOVE %.0f'", feet);
		else if (fClientPosition[2] - 64.0 > fTargetPosition[2]) FormatEx(outStr, outLen, "BELOW %.0f'", feet);
		else                                                      FormatEx(outStr, outLen, "LEVEL");
	} else {
		if (fClientPosition[2] + 64.0 < fTargetPosition[2])      FormatEx(outStr, outLen, "ABOVE %.0fm", meters);
		else if (fClientPosition[2] - 64.0 > fTargetPosition[2]) FormatEx(outStr, outLen, "BELOW %.0fm", meters);
		else                                                      FormatEx(outStr, outLen, "LEVEL");
	}
}

int TraceClientViewEntity(int client) {
	float eyePos[3], eyeAng[3];
	GetClientEyePosition(client, eyePos);
	GetClientEyeAngles(client, eyeAng);
	Handle tr = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_VISIBLE, RayType_Infinite, TRDontHitSelf, client);
	int pEntity = -1;
	if (TR_DidHit(tr)) {
		pEntity = TR_GetEntityIndex(tr);
		delete tr;
		return pEntity;
	}
	delete tr;
	return -1;
}

public Action Event_GrenadeThrown(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int nade_id = event.GetInt("entityid");

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	if (nade_id <= MaxClients || !IsValidEntity(nade_id))
		return Plugin_Continue;

	char grenade_name[32];
	GetEntityClassname(nade_id, grenade_name, sizeof(grenade_name));

	if (!StrEqual(grenade_name, "healthkit"))
		return Plugin_Continue;

	// Your existing voice lines
	switch (GetRandomInt(0, 3)) {
		case 0: EmitSoundToAll("player/voice/radial/security/leader/unsuppressed/need_backup1.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/radial/security/leader/unsuppressed/holdposition2.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/radial/security/leader/suppressed/holdposition1.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/security/command/leader/setwaypoint2.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}

	// Start the healthkit timers/hooks next frame (safer than immediate)
	RequestFrame(Frame_InitHealthkit, EntIndexToEntRef(nade_id));

	return Plugin_Continue;
}

void InitHealthkitEntity(int entity) {
	if (entity <= MaxClients || entity > MAX_ENTITIES || !IsValidEntity(entity))
		return;

	if (ga_bHealthkitInit[entity])
		return;

	ga_bHealthkitInit[entity] = true;
	TrackHealthkit(entity);

	ga_iHealthPack_Amount[entity] = g_iMedpackHealthAmount;

	DataPack hDatapack;
	CreateDataTimer(Healthkit_Timer_Tickrate, Healthkit, hDatapack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	int entref = EntIndexToEntRef(entity);
	hDatapack.WriteCell(entref);
	hDatapack.WriteFloat(GetGameTime() + Healthkit_Timer_Timeout);

	ga_fLastHeight[entity] = -9999.0;

	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	ga_iTimeCheckHeight[entity] = RoundFloat(origin[2]);
	ga_fTimeCheck[entity] = GetGameTime();

	SDKHook(entity, SDKHook_VPhysicsUpdate, HealthkitGroundCheck);
	CreateTimer(0.1, HealthkitGroundCheckTimer, entref, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void Frame_InitHealthkit(any entref) {
	int entity = EntRefToEntIndex(entref);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity))
		return;

	InitHealthkitEntity(entity);
}

static void HealthkitForceLogoUp(int entity) {
	float ang[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", ang);

	ang[0] = 90.0;
	ang[2] = 0.0;

	float vel[3];
	vel[0] = 0.0; vel[1] = 0.0; vel[2] = 0.0;

	TeleportEntity(entity, NULL_VECTOR, ang, vel);

	if (HasEntProp(entity, Prop_Data, "m_vecAngVelocity")) {
		float avel[3];
		avel[0] = 0.0; avel[1] = 0.0; avel[2] = 0.0;
		SetEntPropVector(entity, Prop_Data, "m_vecAngVelocity", avel);
	}

	SetEntityMoveType(entity, MOVETYPE_NONE);
}

public void HealthkitGroundCheck(int entity) {
	if (entity <= MaxClients || !IsValidEntity(entity))
		return;

	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);

	int h = RoundFloat(origin[2]);
	if (h != ga_iTimeCheckHeight[entity]) {
		ga_iTimeCheckHeight[entity] = h;
		ga_fTimeCheck[entity] = GetGameTime();
	}
}

public Action HealthkitGroundCheckTimer(Handle timer, int entref) {
	int entity = EntRefToEntIndex(entref);
	if (entity == INVALID_ENT_REFERENCE || entity <= MaxClients || !IsValidEntity(entity))
		return Plugin_Stop;

	float now = GetGameTime();
	if (now - ga_fTimeCheck[entity] < 0.25)
		return Plugin_Continue;

	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);

	int h = RoundFloat(origin[2]);
	if (h != ga_iTimeCheckHeight[entity]) {
		ga_iTimeCheckHeight[entity] = h;
		ga_fTimeCheck[entity] = now;
		return Plugin_Continue;
	}

	HealthkitForceLogoUp(entity);

	SDKUnhook(entity, SDKHook_VPhysicsUpdate, HealthkitGroundCheck);
	return Plugin_Stop;
}

Action Healthkit(Handle timer, DataPack hDatapack) {
	hDatapack.Reset();

	int entref = hDatapack.ReadCell();
	float fEndTime = hDatapack.ReadFloat();

	int healthPack = EntRefToEntIndex(entref);
	if (healthPack == INVALID_ENT_REFERENCE || healthPack <= MaxClients || healthPack > MAX_ENTITIES || !IsValidEntity(healthPack))
		return Plugin_Stop;

	float fGameTime = GetGameTime();
	if (fGameTime > fEndTime || ga_iHealthPack_Amount[healthPack] <= 0) {
		ga_bHealthkitInit[healthPack] = false;
		ga_iHealthPack_Amount[healthPack] = 0;
		SafeKillIdx(healthPack);
		return Plugin_Stop;
	}

	float	fOrigin[3],
			fPlayerOrigin[3];

	int		ActiveWeapon,
			iHealth;
	int nearbyMedicClients[MAXPLAYERS + 1];
	float nearbyMedicPositions[MAXPLAYERS + 1][3];
	int nearbyMedicCount = 0;

	// Cache medics who can assist area healing once for this healthkit tick.
	for (int friendlyMedic = 1; friendlyMedic <= MaxClients; friendlyMedic++) {
		if (!IsClientInGame(friendlyMedic) || !IsPlayerAlive(friendlyMedic) || !ga_bIsMedic[friendlyMedic])
			continue;

		int medicWeapon;
		bool bCanHealPaddle, bCanHealMedpack;
		if (!GetClientSupportWeaponState(friendlyMedic, medicWeapon, bCanHealPaddle, bCanHealMedpack)
			|| (!bCanHealPaddle && !bCanHealMedpack))
			continue;

		nearbyMedicClients[nearbyMedicCount] = friendlyMedic;
		GetClientAbsOrigin(friendlyMedic, nearbyMedicPositions[nearbyMedicCount]);
		nearbyMedicCount++;
	}

	GetEntPropVector(healthPack, Prop_Data, "m_vecAbsOrigin", fOrigin);
	fOrigin[2] += 1.0;
	TE_SetupBeamRingPoint(fOrigin, 1.0, Healthkit_Radius*1.95, g_iBeaconBeam, g_iBeaconHalo, 0, 30, 3.0, 4.0, 0.0, g_iColorHealRing, 1, FBEAM_HALOBEAM);
	TE_SendToAll();
	fOrigin[2] -= 16.0;

	if (ga_fLastHeight[healthPack] == -9999.0)
		ga_fLastHeight[healthPack] = 0.0;

	if (fOrigin[2] != ga_fLastHeight[healthPack])
		ga_fLastHeight[healthPack] = fOrigin[2];

	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SECURITY)
			continue;
		if (ga_bBleedingOut[client])
			continue;

		GetClientEyePosition(client, fPlayerOrigin);
		if (GetVectorDistanceSquared(fPlayerOrigin, fOrigin) > Healthkit_Radius * Healthkit_Radius)
			continue;

		if (ga_bIsMedic[client]) {
			/* I'm a medic */
			bool bCanHealPaddle, bCanHealMedpack;
			if (!GetClientSupportWeaponState(client, ActiveWeapon, bCanHealPaddle, bCanHealMedpack) || !bCanHealPaddle)
				continue;

			iHealth = GetClientHealth(client);
			if (Check_NearbyMedics(client, nearbyMedicClients, nearbyMedicPositions, nearbyMedicCount)) {
				if (iHealth < 100) {
					iHealth += g_iHealAmountPaddles;
					ga_iHealthPack_Amount[healthPack] -= g_iHealAmountPaddles;
					if (iHealth >= 100) {
						iHealth = 100;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "A medic assisted in healing you (HP: %i)", iHealth);
					}
					else {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Self area healing (HP: %i)", iHealth);
					}
					SetEntityHealth(client, iHealth);
				}
			} else {
				if (iHealth < g_iMedicHealSelfMax) {
					iHealth += g_iHealAmountPaddles;
					ga_iHealthPack_Amount[healthPack] -= g_iHealAmountPaddles;
					if (iHealth >= g_iMedicHealSelfMax) {
						iHealth = g_iMedicHealSelfMax;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "You area healed yourself (HP: %i) | MAX: %i", iHealth, g_iMedicHealSelfMax);
					} else {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Self area healing (HP: %i) | MAX %i", iHealth, g_iMedicHealSelfMax);
					}
				} else {
					PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
					PrintHintText(client, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iMedicHealSelfMax);
				}
			}
		} else {
			/* I'm not a medic */
			if (Check_NearbyMedics(client, nearbyMedicClients, nearbyMedicPositions, nearbyMedicCount)) {
				iHealth = GetClientHealth(client);
				if (iHealth < 100) {
					iHealth += g_iHealAmountPaddles;
					ga_iHealthPack_Amount[healthPack] -= g_iHealAmountPaddles;
					if (iHealth >= 100) {
						iHealth = 100;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "A medic assisted in healing you (HP: %i)", iHealth);
					} else  {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Medic area healing you (HP: %i)", iHealth);
						switch (GetRandomInt(0, 1)) {
							case 0: EmitSoundToAll("weapons/universal/uni_crawl_l_01.wav", client, SNDCHAN_VOICE, _, _, 1.0);
							case 1: EmitSoundToAll("weapons/universal/uni_crawl_l_02.wav", client, SNDCHAN_VOICE, _, _, 1.0);
						}
					}
					SetEntityHealth(client, iHealth);
				}
			} else {
				bool bCanHealPaddle, bCanHealMedpack;
				if (!GetClientSupportWeaponState(client, ActiveWeapon, bCanHealPaddle, bCanHealMedpack))
					continue;
				iHealth = GetClientHealth(client);

				if (!bCanHealPaddle) {
					if (iHealth < g_iNonMedicHealSelfMax)
						PrintHintText(client, "No medics nearby! Pull knife out to heal! (HP: %i)", iHealth);
					continue;
				}

				if (iHealth < g_iNonMedicHealSelfMax) {
					iHealth += g_iNonMedicHealAmt;
					ga_iHealthPack_Amount[healthPack] -= g_iNonMedicHealAmt;
					if (iHealth >= g_iNonMedicHealSelfMax) {
						iHealth = g_iNonMedicHealSelfMax;
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
					} else {
						PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
						PrintHintText(client, "Healing Self (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
					}
					SetEntityHealth(client, iHealth);
				} else {
					PrintCenterText(client, "Medical Pack HP Left: %i", ga_iHealthPack_Amount[healthPack]);
					PrintHintText(client, "You healed yourself (HP: %i) | MAX: %i", iHealth, g_iNonMedicHealSelfMax);
				}
			}
		}
	}

	return Plugin_Continue;
}

bool Check_NearbyMedics(int client, const int[] medicClients, const float[][] medicPositions, int medicCount) {
	float clientPosition[3];
	GetClientAbsOrigin(client, clientPosition);

	for (int i = 0; i < medicCount; i++) {
		if (medicClients[i] == client)
			continue;

		float x = medicPositions[i][0] - clientPosition[0];
		float y = medicPositions[i][1] - clientPosition[1];
		float z = medicPositions[i][2] - clientPosition[2];
		if (x * x + y * y + z * z <= Healthkit_Radius * Healthkit_Radius)
			return true;
	}
	return false;
}

void Check_NearbyMedicsRevive(int client, int iInjured) {
	float	medicPosition[3],
			injuredPosition[3];

	int		ActiveWeapon;
	char	woundType[20];

	VecCopy(ga_fRagdollPosition[iInjured], injuredPosition);

	for (int assistingMedic = 1; assistingMedic <= MaxClients; assistingMedic++) {
		if (!IsClientInGame(assistingMedic) || !IsPlayerAlive(assistingMedic) || client == assistingMedic || !ga_bIsMedic[assistingMedic])
			continue;

		bool bCanHealPaddle, bCanHealMedpack;
		if (!GetClientSupportWeaponState(assistingMedic, ActiveWeapon, bCanHealPaddle, bCanHealMedpack))
			continue;
		if (!bCanHealPaddle)
			continue;

		GetClientAbsOrigin(assistingMedic, medicPosition);

		if (GetVectorDistanceSquared(medicPosition, injuredPosition) <= 65.0 * 65.0) {
			GetWoundTypeString(iInjured, woundType, sizeof(woundType));

			ga_iStatReviveAssists[assistingMedic]++;
			LogToGame("\"%L\" triggered \"revive_assist\" against \"%L\"", assistingMedic, iInjured);

			PrintHintText(assistingMedic, "You revived(assisted) %N from a %s", iInjured, woundType);
		}
	}
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	int oldTeam = event.GetInt("oldteam");
	int newTeam = event.GetInt("team");

	if (oldTeam == TEAM_SECURITY && newTeam != TEAM_SECURITY) {
		FlushMedicStats(client, false);
		ResetBleedoutClient(client, true);
		RemoveRagdoll(client);
	}

	if (newTeam != TEAM_SECURITY)
		ga_bIsMedic[client] = false;

	return Plugin_Continue;
}

public Action Cmd_MedicStats(int client, int args) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Handled;

	float now = GetGameTime();
	if (now < ga_fNextMedicCmdTime[client]) {
		float remain = ga_fNextMedicCmdTime[client] - now;
		if (remain < 1.0)
			remain = 1.0;
		PrintToChat(client, "\x070088cc[Medic]\x01 Please wait %.0f seconds before using !medic again.", remain);
		return Plugin_Handled;
	}
	ga_fNextMedicCmdTime[client] = now + MEDIC_CMD_COOLDOWN;

	bool found = false;
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != TEAM_SECURITY)
			continue;

		if ((ga_iStatRevives[i] > 0 || ga_iStatReviveAssists[i] > 0 || ga_iStatHeals[i] > 0
			|| ga_iTotalHP[i] > 0 || ga_iStatBleedoutsTreated[i] > 0) && ga_bIsMedic[i]) {
			PrintToChatAll("\x070088cc%N\x01 - Heals: \x0700cc44%d\x01  Sessions: \x0700cc44%d\x01  HP: \x0700cc44%d\x01  Revives: \x0700cc44%d\x01  Assists: \x0700cc44%d\x01  Tourniquets: \x0700cc44%d",
				i, ga_iStatHeals[i], ga_iHealingSessions[i], ga_iTotalHP[i], ga_iStatRevives[i],
				ga_iStatReviveAssists[i], ga_iStatBleedoutsTreated[i]);
			found = true;
		}
	}

	if (!found)
		PrintToChat(client, "\x070088cc[Medic]\x01 No medic stats yet.");

	return Plugin_Handled;
}

public Action cmd_fatal(int client, int args) {
	if (!IsPlayerAlive(client) && !ga_bHurtFatal[client]) {
		ga_bHurtFatal[client] = true;
		RemoveRagdoll(client);
		PrintToChat(client, "Changed your death to fatal.");
	}
	return Plugin_Handled;
}

static bool ParseBleedTestLimb(const char[] value, int &hitgroup) {
	if (StrEqual(value, "leftarm", false)) {
		hitgroup = HITGROUP_LEFTARM;
		return true;
	}
	if (StrEqual(value, "rightarm", false)) {
		hitgroup = HITGROUP_RIGHTARM;
		return true;
	}
	if (StrEqual(value, "leftleg", false)) {
		hitgroup = HITGROUP_LEFTLEG;
		return true;
	}
	if (StrEqual(value, "rightleg", false)) {
		hitgroup = HITGROUP_RIGHTLEG;
		return true;
	}
	return false;
}

static int ResolveBleedTestTarget(int client, const char[] value) {
	if (value[0] == '\0' || StrEqual(value, "@me", false))
		return client;

	if (StrEqual(value, "@aim", false)) {
		if (client < 1 || client > MaxClients || !IsClientInGame(client))
			return 0;

		int target = TraceClientViewEntity(client);
		if (target > 0 && target <= MaxClients && IsClientInGame(target))
			return target;
		return 0;
	}

	return FindTarget(client, value, false, false);
}

static void ReplyBleedTestUsage(int client) {
	ReplyToCommand(client, "[Medic Test] Usage:");
	ReplyToCommand(client, "sm_bleedtest start [target] [leftarm|rightarm|leftleg|rightleg]");
	ReplyToCommand(client, "sm_bleedtest <status|treat|hit|expire-fatal|expire-revive|revive|clear> [target]");
	ReplyToCommand(client, "[Medic Test] Target defaults to yourself and may be @me, @aim, a name, or #userid.");
}

public Action Cmd_BleedTest(int client, int args) {
	if (args < 1) {
		ReplyBleedTestUsage(client);
		return Plugin_Handled;
	}

	char action[32], targetArg[64], limbArg[16];
	GetCmdArg(1, action, sizeof(action));
	if (args >= 2)
		GetCmdArg(2, targetArg, sizeof(targetArg));
	if (args >= 3)
		GetCmdArg(3, limbArg, sizeof(limbArg));

	int hitgroup = GetRandomInt(HITGROUP_LEFTARM, HITGROUP_RIGHTLEG);
	if (StrEqual(action, "start", false) && targetArg[0] != '\0' && ParseBleedTestLimb(targetArg, hitgroup))
		targetArg[0] = '\0';
	else if (limbArg[0] != '\0' && !ParseBleedTestLimb(limbArg, hitgroup)) {
		ReplyToCommand(client, "[Medic Test] Invalid limb \"%s\".", limbArg);
		return Plugin_Handled;
	}

	int target = ResolveBleedTestTarget(client, targetArg);
	if (target < 1 || target > MaxClients || !IsClientInGame(target)) {
		ReplyToCommand(client, "[Medic Test] No valid target. Aim at a player or supply a name/#userid.");
		return Plugin_Handled;
	}

	if (StrEqual(action, "status", false)) {
		if (ga_bBleedingOut[target]) {
			float remaining = ga_fBleedoutEndsAt[target] - GetGameTime();
			if (remaining < 0.0)
				remaining = 0.0;
			ReplyToCommand(client,
				"[Medic Test] %N is bleeding: %.1fs remaining, %.1fs tourniquet, hitgroup %d, damage %d, arterial ref %d, markers %d.",
				target, remaining, ga_fTourniquetRemaining[target], ga_iBleedoutHitgroup[target],
				ga_iBleedoutDamage[target], ga_iBleedParticleRef[target], CountBleedMarkers(target));
		} else {
			ReplyToCommand(client, "[Medic Test] %N is not bleeding. Fatal=%d, ragdoll ref=%d, puddle ref=%d.",
				target, ga_bHurtFatal[target], ga_iClientRagdolls[target], ga_iBleedPuddleRef[target]);
		}
		return Plugin_Handled;
	}

	if (StrEqual(action, "start", false)) {
		if (!IsPlayerAlive(target) || GetClientTeam(target) != TEAM_SECURITY) {
			ReplyToCommand(client, "[Medic Test] %N must be an alive Security player or bot.", target);
			return Plugin_Handled;
		}

		ResetBleedoutClient(target, true);
		SetEntityHealth(target, 1);
		float position[3];
		StartBleedout(target, hitgroup, g_iFatalLimbDmg, 0, position);
		ReplyToCommand(client, "[Medic Test] Forced bleedout on %N at hitgroup %d. The 50%% gameplay chance was bypassed.", target, hitgroup);
		return Plugin_Handled;
	}

	if (StrEqual(action, "treat", false)) {
		if (!ga_bBleedingOut[target]) {
			ReplyToCommand(client, "[Medic Test] %N is not bleeding.", target);
			return Plugin_Handled;
		}
		if (!ga_bTourniquetPainPlayed[target]) {
			ga_bTourniquetPainPlayed[target] = true;
			PlayTourniquetPainSound(target);
		}
		CompleteTourniquet(target, 0);
		ReplyToCommand(client, "[Medic Test] Forced tourniquet completion on %N.", target);
		return Plugin_Handled;
	}

	if (StrEqual(action, "hit", false)) {
		if (!ga_bBleedingOut[target] || !IsPlayerAlive(target)) {
			ReplyToCommand(client, "[Medic Test] %N must be alive and bleeding.", target);
			return Plugin_Handled;
		}

		int attacker = (client > 0 && client <= MaxClients && IsClientInGame(client)) ? client : target;
		SDKHooks_TakeDamage(target, attacker, attacker, 10.0, DMG_BULLET, -1, NULL_VECTOR, NULL_VECTOR, false);
		ReplyToCommand(client, "[Medic Test] Applied a follow-up hit to %N.", target);
		return Plugin_Handled;
	}

	if (StrEqual(action, "expire-fatal", false) || StrEqual(action, "expire-revive", false)) {
		if (!ga_bBleedingOut[target] || !IsPlayerAlive(target)) {
			ReplyToCommand(client, "[Medic Test] %N must be alive and bleeding.", target);
			return Plugin_Handled;
		}

		bool forceFatal = StrEqual(action, "expire-fatal", false);
		ExpireBleedout(target, forceFatal ? 1 : 0);
		ReplyToCommand(client, "[Medic Test] Forced %s bleedout expiration on %N.",
			forceFatal ? "fatal" : "revivable", target);
		return Plugin_Handled;
	}

	if (StrEqual(action, "revive", false)) {
		if (IsPlayerAlive(target) || ga_bHurtFatal[target] || GetClientRagdollEntity(target) == INVALID_ENT_REFERENCE) {
			ReplyToCommand(client, "[Medic Test] %N needs a ready, non-fatal medic ragdoll.", target);
			return Plugin_Handled;
		}

		ga_bRevivedByMedic[target] = true;
		RespawnPlayerRevive(target);
		ReplyToCommand(client, "[Medic Test] Force-revived %N.", target);
		return Plugin_Handled;
	}

	if (StrEqual(action, "clear", false)) {
		ResetBleedoutClient(target, true);
		ReplyToCommand(client, "[Medic Test] Cleared bleedout state and particles for %N.", target);
		return Plugin_Handled;
	}

	ReplyBleedTestUsage(client);
	return Plugin_Handled;
}

void CloseHealingSession(int client) {
	if (client < 1 || client > MaxClients)
		return;

	int target = ga_iHealingSessionTarget[client];
	int restoredHP = ga_iHealingSessionHP[client];

	if (restoredHP > 0) {
		ga_iHealingSessions[client]++;

		if (IsClientInGame(client) && !IsFakeClient(client)
			&& target > 0 && target <= MaxClients && IsClientInGame(target))
		{
			LogToGame("\"%L\" triggered \"healing_session\" against \"%L\"", client, target);
		}
	}

	ga_iHealingSessionTarget[client] = 0;
	ga_iHealingSessionHP[client] = 0;
	ga_fHealingSessionLastAt[client] = 0.0;
}

void RecordHealingTick(int healer, int target, int restoredHP, float now) {
	if (healer < 1 || healer > MaxClients || target < 1 || target > MaxClients || restoredHP <= 0)
		return;

	if (ga_iHealingSessionTarget[healer] != 0 && ga_iHealingSessionTarget[healer] != target)
		CloseHealingSession(healer);

	ga_iHealingSessionTarget[healer] = target;
	ga_iHealingSessionHP[healer] += restoredHP;
	ga_fHealingSessionLastAt[healer] = now;
	ga_iTotalHP[healer] += restoredHP;
}

void CloseExpiredHealingSession(int client, float now) {
	if (client < 1 || client > MaxClients || ga_iHealingSessionHP[client] <= 0)
		return;

	if (now - ga_fHealingSessionLastAt[client] >= HEAL_SESSION_TIMEOUT)
		CloseHealingSession(client);
}

void FlushMedicStats(int client, bool announce = false) {
	if (client < 1 || client > MaxClients)
		return;

	CloseHealingSession(client);

	if (IsClientInGame(client) && !IsFakeClient(client)) {
		if (announce && (ga_iStatRevives[client] > 0 || ga_iStatReviveAssists[client] > 0 || ga_iStatHeals[client] > 0
			|| ga_iTotalHP[client] > 0 || ga_iStatBleedoutsTreated[client] > 0) && ga_bIsMedic[client]) {
			PrintToChatAll("\x070088cc%N\x01 - Heals: \x0700cc44%d\x01  Sessions: \x0700cc44%d\x01  HP: \x0700cc44%d\x01  Revives: \x0700cc44%d\x01  Assists: \x0700cc44%d\x01  Tourniquets: \x0700cc44%d",
				client, ga_iStatHeals[client], ga_iHealingSessions[client], ga_iTotalHP[client], ga_iStatRevives[client],
				ga_iStatReviveAssists[client], ga_iStatBleedoutsTreated[client]);
		}

		if (ga_iTotalHP[client] > 0)
			LogToGame("\"%L\" triggered \"healing_hp\" (value \"%d\")", client, ga_iTotalHP[client]);
	}

	ResetMedicStats(client);
}

void FlushAllMedicStats(bool announce = false) {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsFakeClient(client))
			FlushMedicStats(client, announce);
		else
			ResetMedicStats(client);
	}
}

void ResetMedicStats (int client) {
	ga_iStatRevives[client] = 0;
	ga_iStatHeals[client] = 0;
	ga_iTotalHP[client] = 0;
	ga_iStatReviveAssists[client] = 0;
	ga_iHealingSessions[client] = 0;
	ga_iStatBleedoutsTreated[client] = 0;
	ga_iHealingSessionTarget[client] = 0;
	ga_iHealingSessionHP[client] = 0;
	ga_fHealingSessionLastAt[client] = 0.0;
}

void PlayVictimReviveSound(int client) {
	char sBuffer[64];
	FormatEx(sBuffer, sizeof(sBuffer), "lua_sounds/medic/thx/medic_thanks%d.ogg", GetRandomInt(9, 11));
	EmitSoundToAll(sBuffer, client, SNDCHAN_VOICE, _, _, 1.0);
	EmitSoundToClient(client, SND_REVIVENOTIFY, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0);
}

public Action cmdListener(int client, const char[] cmd, int argc) {
	if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	if (GetRandomInt(0, 1) == 1)
		ga_bHurtFatal[client] = true;

	return Plugin_Continue;
}

public Action ChangeLevelListener(int client, const char[] command, int argc) {
	if (StrEqual(command, "sm_map", false)) {
		if (client > 0 && !CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP, true))
			return Plugin_Continue;
	}
	else if (StrEqual(command, "map", false) || StrEqual(command, "changelevel", false)) {
		if (client > 0)
			return Plugin_Continue;
	}
	else
		return Plugin_Continue;

	if (argc > 0) {
		char nextMap[PLATFORM_MAX_PATH];
		GetCmdArg(1, nextMap, sizeof(nextMap));
		if (IsMapValid(nextMap)) {
			g_bMapInit = false;
			g_bRoundActive = false;
			g_bReviveActive = false;
		}
	}
	return Plugin_Continue;
}

static void VecCopy(const float src[3], float dest[3]) {
	dest[0] = src[0];
	dest[1] = src[1];
	dest[2] = src[2];
}

static float GetVectorDistanceSquared(const float first[3], const float second[3]) {
	float x = first[0] - second[0];
	float y = first[1] - second[1];
	float z = first[2] - second[2];
	return x * x + y * y + z * z;
}

public bool TraceEntityFilterPlayers(int entity, int contentsMask, any data) {
	if (entity == data) return false;
	return (entity > MaxClients);
}

public bool TraceEntityFilterSolid(int entity, int contentsMask, any data) {
	return (entity > MaxClients);
}

public bool TRDontHitSelf(int entity, int contentsMask, any data) {
	return (entity != data);
}

void PrecacheFiles() {
	char sBuffer[128];
	g_iBeaconBeam = PrecacheModel("materials/sprites/laser.vmt");
	g_iBeaconHalo = PrecacheModel("materials/sprites/glow01.vmt");
	PrecacheBleedoutMarkerMaterial();

	// Deploying sounds
	PrecacheSound("player/voice/radial/security/leader/unsuppressed/need_backup1.ogg");
	PrecacheSound("player/voice/radial/security/leader/unsuppressed/holdposition2.ogg");
	PrecacheSound("player/voice/radial/security/leader/suppressed/holdposition1.ogg");
	PrecacheSound("player/voice/security/command/leader/setwaypoint2.ogg");
	//Lua sounds
	for (int i = 9; i <= 11; i++) {
		FormatEx(sBuffer, sizeof(sBuffer), "lua_sounds/medic/thx/medic_thanks%d.ogg", i);
		PrecacheSound(sBuffer);
	}
	for (int i = 1; i <= 2; i++) {
		FormatEx(sBuffer, sizeof(sBuffer), "weapons/universal/uni_crawl_l_0%d.wav", i);
		PrecacheSound(sBuffer);
	}
	//L4D2 defibrillator revive sound
	PrecacheSound("weapons/defibrillator/defibrillator_revive.wav");
	// Destory, Flip sounds
	PrecacheSound("ui/sfx/cl_click.wav");
	PrecacheBleedoutVoiceSounds();

	PrecacheSound(SND_REVIVENOTIFY);
}

static bool PrecacheBleedoutMarkerMaterial() {
	return PrecacheModel(BLEEDOUT_MARKER_MODEL, true) > 0;
}

static void PrecacheBleedoutVoiceSounds() {
	char soundPath[96];
	for (int i = 5; i <= 19; i++) {
		FormatEx(soundPath, sizeof(soundPath),
			"player/voice/responses/security/subordinate/unsuppressed/wounded%d.ogg", i);
		PrecacheSound(soundPath);
	}
}

static int OR_Cache(bool force = false) {
	if (force || g_iObjResEntity < 1 || !IsValidEntity(g_iObjResEntity)) {
		g_iObjResEntity = FindEntityByClassname(-1, "ins_objective_resource");
		if (g_iObjResEntity > 0)
			GetEntityNetClass(g_iObjResEntity, g_sObjResNetClass, sizeof g_sObjResNetClass);
		else
			g_sObjResNetClass[0] = '\0';
	}
	else {
		char classname[32];
		GetEntityClassname(g_iObjResEntity, classname, sizeof classname);
		if (classname[0] == '\0' || !StrEqual(classname, "ins_objective_resource", false))
			return OR_Cache(true);
	}
	return g_iObjResEntity;
}

stock int Ins_ObjectiveResource_GetProp(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1)
			return GetEntData(g_iObjResEntity, offs + (size * element));
	}
	return -1;
}

stock float Ins_ObjectiveResource_GetPropFloat(const char[] prop, int size = 4, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1)
			return GetEntDataFloat(g_iObjResEntity, offs + (size * element));
	}
	return -1.0;
}

stock int Ins_ObjectiveResource_GetPropEnt(const char[] prop, int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1)
			return GetEntData(g_iObjResEntity, offs + (4 * element));
	}
	return -1;
}

stock bool Ins_ObjectiveResource_GetPropVector(const char[] prop, float vec[3], int element = 0) {
	if (OR_Cache() > 0 && g_sObjResNetClass[0] != '\0') {
		int offs = FindSendPropInfo(g_sObjResNetClass, prop);
		if (offs != -1) {
			GetEntDataVector(g_iObjResEntity, offs + (12 * element), vec); // 3*4 bytes
			return true;
		}
	}
	return false;
}

// stock int Ins_ObjectiveResource_GetPropString(const char[] prop, char[] buffer, int maxlen) {
// 	buffer[0] = '\0';
// 	return 0;
// }

stock bool Ins_InCounterAttack() {
	return (GameRules_GetProp("m_bCounterAttack") != 0);
}

public bool TraceFilter_NoPlayersNoRagdolls(int entity, int contentsMask, any data) {
	if (entity >= 1 && entity <= MaxClients)
		return false;

	if (entity > MaxClients && IsValidEntity(entity)) {
		static char cls[32];
		GetEntityClassname(entity, cls, sizeof cls);
		if (StrContains(cls, "ragdoll", false) != -1)
			return false;
	}

	return true;
}

bool ClientCanSeeVector(int client, float vTargetPosition[3], float distance = 0.0, float height = 40.0) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return false;

	if (distance > 0.0) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		if (GetVectorDistance(pos, vTargetPosition, false) > distance)
			return false;
	}

	float start[3], end[3];
	GetClientEyePosition(client, start);
	end[0] = vTargetPosition[0];
	end[1] = vTargetPosition[1];
	end[2] = vTargetPosition[2] + height;
	
	Handle tr = TR_TraceRayFilterEx(start, end, MASK_VISIBLE, RayType_EndPoint, TraceFilter_NoPlayersNoRagdolls);
	bool blocked = TR_DidHit(tr);
	delete tr;
	return !blocked;
}

stock void SafeKillIdx(int ent) {
	if (ent <= MaxClients) return;
	int ref = EntIndexToEntRef(ent);
	if (ref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, ref);
}

stock void SafeKillRef(int entref) {
	if (entref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, entref);
}

stock void NF_KillEntity(any entref) {
	int ent = EntRefToEntIndex(entref);
	if (ent <= MaxClients || !IsValidEntity(ent)) return;

	if (!AcceptEntityInput(ent, "Kill"))
		RemoveEntity(ent);
}

void SetupConVars() {
	g_cvReviveEnabled = CreateConVar("sm_revive_enabled", "1", "Reviving enabled from medics?  This creates revivable ragdoll after death; 0 - disabled, 1 - enabled");
	g_bReviveEnabled = g_cvReviveEnabled.BoolValue;
	g_cvReviveEnabled.AddChangeHook(OnConVarChanged);

	g_cvAutoThanksEnabled = CreateConVar("sm_revive_thanks_enabled", "1", "Allow players to use saved automatic team-chat thanks after a revive; 0 - disabled, 1 - enabled");
	g_bAutoThanksEnabled = g_cvAutoThanksEnabled.BoolValue;
	g_cvAutoThanksEnabled.AddChangeHook(OnConVarChanged);

	g_cvFatalChance = CreateConVar("sm_respawn_fatal_chance", "0.20", "Chance for a kill to be fatal, 0.6 default = 60% chance to be fatal (To disable set 0.0)");
	g_fFatalChance = g_cvFatalChance.FloatValue;
	g_cvFatalChance.AddChangeHook(OnConVarChanged);

	g_cvFatalHeadChance = CreateConVar("sm_respawn_fatal_head_chance", "0.75", "Chance for a headshot kill to be fatal, 0.6 default = 60% chance to be fatal");
	g_fFatalHeadChance = g_cvFatalHeadChance.FloatValue;
	g_cvFatalHeadChance.AddChangeHook(OnConVarChanged);

	g_cvFatalLimbDmg = CreateConVar("sm_respawn_fatal_limb_dmg", "180", "Amount of damage to fatally kill player in limb");
	g_iFatalLimbDmg = g_cvFatalLimbDmg.IntValue;
	g_cvFatalLimbDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalHeadDmg = CreateConVar("sm_respawn_fatal_head_dmg", "200", "Amount of damage to fatally kill player in head");
	g_iFatalHeadDmg = g_cvFatalHeadDmg.IntValue;
	g_cvFatalHeadDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalBurnDmg = CreateConVar("sm_respawn_fatal_burn_dmg", "80", "Amount of damage to fatally kill player in burn");
	g_iFatalBurnDmg = g_cvFatalBurnDmg.IntValue;
	g_cvFatalBurnDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalExplosiveDmg = CreateConVar("sm_respawn_fatal_explosive_dmg", "220", "Amount of damage to fatally kill player in explosive");
	g_iFatalExplosiveDmg = g_cvFatalExplosiveDmg.IntValue;
	g_cvFatalExplosiveDmg.AddChangeHook(OnConVarChanged);

	g_cvFatalChestStomach = CreateConVar("sm_respawn_fatal_chest_stomach", "170", "Amount of damage to fatally kill player in chest/stomach");
	g_iFatalChestStomach = g_cvFatalChestStomach.IntValue;
	g_cvFatalChestStomach.AddChangeHook(OnConVarChanged);

	g_cvBleedoutEnabled = CreateConVar("sm_bleedout_enabled", "1",
		"Allow would-be lethal arm/leg hits to trigger arterial bleedout; 0 - disabled, 1 - enabled");
	g_bBleedoutEnabled = g_cvBleedoutEnabled.BoolValue;
	g_cvBleedoutEnabled.AddChangeHook(OnConVarChanged);

	g_cvBleedoutChance = CreateConVar("sm_bleedout_chance", "0.50",
		"Chance that a would-be lethal arm/leg hit triggers bleedout", _, true, 0.0, true, 1.0);
	g_fBleedoutChance = g_cvBleedoutChance.FloatValue;
	g_cvBleedoutChance.AddChangeHook(OnConVarChanged);

	g_cvBleedoutTime = CreateConVar("sm_bleedout_time", "15.0",
		"Seconds before an untreated arterial bleedout kills the player", _, true, 1.0, true, 120.0);
	g_fBleedoutTime = g_cvBleedoutTime.FloatValue;
	g_cvBleedoutTime.AddChangeHook(OnConVarChanged);

	g_cvTourniquetMedicTime = CreateConVar("sm_tourniquet_time", "3.0",
		"Seconds a medic must treat a teammate before the tourniquet is secured", _, true, 0.5, true, 30.0);
	g_fTourniquetMedicTime = g_cvTourniquetMedicTime.FloatValue;
	g_cvTourniquetMedicTime.AddChangeHook(OnConVarChanged);

	g_cvTourniquetNonMedicTime = CreateConVar("sm_tourniquet_nonmedic_time", "7.0",
		"Seconds a non-medic must treat a teammate before the tourniquet is secured", _, true, 0.5, true, 30.0);
	g_fTourniquetNonMedicTime = g_cvTourniquetNonMedicTime.FloatValue;
	g_cvTourniquetNonMedicTime.AddChangeHook(OnConVarChanged);

	g_cvBleedoutPuddleLifetime = CreateConVar("sm_bleedout_puddle_lifetime", "30.0",
		"Seconds the blood_bleedout puddle remains after a non-fatal bleedout death", _, true, 1.0, true, 120.0);
	g_fBleedoutPuddleLifetime = g_cvBleedoutPuddleLifetime.FloatValue;
	g_cvBleedoutPuddleLifetime.AddChangeHook(OnConVarChanged);

	g_cvBleedoutFadeEnabled = CreateConVar("sm_bleedout_fade_enabled", "1",
		"Pulse a subtle private red screen fade for the bleeding player; 0 - disabled, 1 - enabled");
	g_bBleedoutFadeEnabled = g_cvBleedoutFadeEnabled.BoolValue;
	g_cvBleedoutFadeEnabled.AddChangeHook(OnConVarChanged);

	g_cvBleedoutFadeAlpha = CreateConVar("sm_bleedout_fade_alpha", "45",
		"Maximum alpha of the private bleedout screen fade", _, true, 0.0, true, 120.0);
	g_iBleedoutFadeAlpha = g_cvBleedoutFadeAlpha.IntValue;
	g_cvBleedoutFadeAlpha.AddChangeHook(OnConVarChanged);

	g_cvReviveDistanceMetric = CreateConVar("sm_revive_distance_metric", "0", "Distance metric (0: meters / 1: feet)");
	g_bDistanceFeet = g_cvReviveDistanceMetric.BoolValue;
	g_cvReviveDistanceMetric.AddChangeHook(OnConVarChanged);

	g_cvHealAmountMedpack = CreateConVar("sm_heal_amount_medpack", "8", "Heal amount per 0.5 seconds when using medpack");
	g_iHealAmountMedpack = g_cvHealAmountMedpack.IntValue;
	g_cvHealAmountMedpack.AddChangeHook(OnConVarChanged);

	g_cvHealAmountPaddles = CreateConVar("sm_heal_amount_paddles", "4", "Heal amount per 0.5 seconds when using paddles");
	g_iHealAmountPaddles = g_cvHealAmountPaddles.IntValue;
	g_cvHealAmountPaddles.AddChangeHook(OnConVarChanged);

	g_cvNonMedicHealAmt = CreateConVar("sm_non_medic_heal_amt", "3", "Heal amount per 0.5 seconds when non-medic");
	g_iNonMedicHealAmt = g_cvNonMedicHealAmt.IntValue;
	g_cvNonMedicHealAmt.AddChangeHook(OnConVarChanged);

	g_cvNonMedicReviveHp = CreateConVar("sm_non_medic_revive_hp", "20", "Health given to target revive when non-medic reviving");
	g_iNonMedicReviveHp = g_cvNonMedicReviveHp.IntValue;
	g_cvNonMedicReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMedicMinorReviveHp = CreateConVar("sm_medic_minor_revive_hp", "70", "Health given to target revive when medic reviving minor wound");
	g_iMedicMinorReviveHp = g_cvMedicMinorReviveHp.IntValue;
	g_cvMedicMinorReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMedicModerateReviveHp = CreateConVar("sm_medic_moderate_revive_hp", "50", "Health given to target revive when medic reviving moderate wound");
	g_iMedicModerateReviveHp = g_cvMedicModerateReviveHp.IntValue;
	g_cvMedicModerateReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMedicCriticalReviveHp = CreateConVar("sm_medic_critical_revive_hp", "35", "Health given to target revive when medic reviving critical wound");
	g_iMedicCriticalReviveHp = g_cvMedicCriticalReviveHp.IntValue;
	g_cvMedicCriticalReviveHp.AddChangeHook(OnConVarChanged);

	g_cvMinorWoundDmg = CreateConVar("sm_minor_wound_dmg", "150", "Any amount of damage <= to this is considered a minor wound when killed");
	g_iMinorWoundDmg = g_cvMinorWoundDmg.IntValue;
	g_cvMinorWoundDmg.AddChangeHook(OnConVarChanged);

	g_cvModerateWoundDmg = CreateConVar("sm_moderate_wound_dmg", "250", "Any amount of damage <= to this is considered a minor wound when killed.	Anything greater is CRITICAL");
	g_iModerateWoundDmg = g_cvModerateWoundDmg.IntValue;
	g_cvModerateWoundDmg.AddChangeHook(OnConVarChanged);

	g_cvMedicHealSelfMax = CreateConVar("sm_medic_heal_self_max", "80", "Max medic can heal self to with med pack");
	g_iMedicHealSelfMax = g_cvMedicHealSelfMax.IntValue;
	g_cvMedicHealSelfMax.AddChangeHook(OnConVarChanged);

	g_cvNonMedicHealSelfMax = CreateConVar("sm_non_medic_heal_self_max", "60", "Max non-medic can heal self to with med pack");
	g_iNonMedicHealSelfMax = g_cvNonMedicHealSelfMax.IntValue;
	g_cvNonMedicHealSelfMax.AddChangeHook(OnConVarChanged);

	g_cvNonMedicMaxHealOther = CreateConVar("sm_non_medic_max_heal_other", "60", "Heal amount per 0.5 seconds when using paddles");
	g_iNonMedicMaxHealOther = g_cvNonMedicMaxHealOther.IntValue;
	g_cvNonMedicMaxHealOther.AddChangeHook(OnConVarChanged);

	g_cvMinorReviveTime = CreateConVar("sm_minor_revive_time", "4", "Seconds it takes medic to revive minor wounded");
	g_iMinorReviveTime = g_cvMinorReviveTime.IntValue;
	g_cvMinorReviveTime.AddChangeHook(OnConVarChanged);

	g_cvModerateReviveTime = CreateConVar("sm_moderate_revive_time", "6", "Seconds it takes medic to revive moderate wounded");
	g_iModerateReviveTime = g_cvModerateReviveTime.IntValue;
	g_cvModerateReviveTime.AddChangeHook(OnConVarChanged);

	g_cvCriticalReviveTime = CreateConVar("sm_critical_revive_time", "8", "Seconds it takes medic to revive critical wounded");
	g_iCriticalReviveTime = g_cvCriticalReviveTime.IntValue;
	g_cvCriticalReviveTime.AddChangeHook(OnConVarChanged);

	g_cvNonMedicReviveTime = CreateConVar("sm_non_medic_revive_time", "15", "Seconds it takes non-medic to revive minor wounded, requires medpack");
	g_iNonMedicReviveTime = g_cvNonMedicReviveTime.IntValue;
	g_cvNonMedicReviveTime.AddChangeHook(OnConVarChanged);

	g_cvMedpackHealthAmount = CreateConVar("sm_medpack_health_amount", "300", "Amount of health a deployed healthpack has");
	g_iMedpackHealthAmount = g_cvMedpackHealthAmount.IntValue;
	g_cvMedpackHealthAmount.AddChangeHook(OnConVarChanged);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvReviveEnabled)
		g_bReviveEnabled = g_cvReviveEnabled.BoolValue;
	else if (convar == g_cvAutoThanksEnabled)
		g_bAutoThanksEnabled = g_cvAutoThanksEnabled.BoolValue;
	else if (convar == g_cvFatalChance)
		g_fFatalChance = g_cvFatalChance.FloatValue;
	else if (convar == g_cvFatalHeadChance)
		g_fFatalHeadChance = g_cvFatalHeadChance.FloatValue;
	else if (convar == g_cvFatalLimbDmg)
		g_iFatalLimbDmg = g_cvFatalLimbDmg.IntValue;
	else if (convar == g_cvFatalHeadDmg)
		g_iFatalHeadDmg = g_cvFatalHeadDmg.IntValue;
	else if (convar == g_cvFatalBurnDmg)
		g_iFatalBurnDmg = g_cvFatalBurnDmg.IntValue;
	else if (convar == g_cvFatalExplosiveDmg)
		g_iFatalExplosiveDmg = g_cvFatalExplosiveDmg.IntValue;
	else if (convar == g_cvFatalChestStomach)
		g_iFatalChestStomach = g_cvFatalChestStomach.IntValue;
	else if (convar == g_cvBleedoutEnabled) {
		g_bBleedoutEnabled = g_cvBleedoutEnabled.BoolValue;
		if (!g_bBleedoutEnabled) {
			for (int client = 1; client <= MaxClients; client++)
				ClearActiveBleedout(client);
		}
	}
	else if (convar == g_cvBleedoutChance)
		g_fBleedoutChance = g_cvBleedoutChance.FloatValue;
	else if (convar == g_cvBleedoutTime)
		g_fBleedoutTime = g_cvBleedoutTime.FloatValue;
	else if (convar == g_cvTourniquetMedicTime)
		g_fTourniquetMedicTime = g_cvTourniquetMedicTime.FloatValue;
	else if (convar == g_cvTourniquetNonMedicTime)
		g_fTourniquetNonMedicTime = g_cvTourniquetNonMedicTime.FloatValue;
	else if (convar == g_cvBleedoutPuddleLifetime)
		g_fBleedoutPuddleLifetime = g_cvBleedoutPuddleLifetime.FloatValue;
	else if (convar == g_cvBleedoutFadeEnabled)
		g_bBleedoutFadeEnabled = g_cvBleedoutFadeEnabled.BoolValue;
	else if (convar == g_cvBleedoutFadeAlpha)
		g_iBleedoutFadeAlpha = g_cvBleedoutFadeAlpha.IntValue;
	else if (convar == g_cvReviveDistanceMetric)
		g_bDistanceFeet = g_cvReviveDistanceMetric.BoolValue;
	else if (convar == g_cvHealAmountMedpack)
		g_iHealAmountMedpack = g_cvHealAmountMedpack.IntValue;
	else if (convar == g_cvHealAmountPaddles)
		g_iHealAmountPaddles = g_cvHealAmountPaddles.IntValue;
	else if (convar == g_cvNonMedicHealAmt)
		g_iNonMedicHealAmt = g_cvNonMedicHealAmt.IntValue;
	else if (convar == g_cvNonMedicReviveHp)
		g_iNonMedicReviveHp = g_cvNonMedicReviveHp.IntValue;
	else if (convar == g_cvMedicMinorReviveHp)
		g_iMedicMinorReviveHp = g_cvMedicMinorReviveHp.IntValue;
	else if (convar == g_cvMedicModerateReviveHp)
		g_iMedicModerateReviveHp = g_cvMedicModerateReviveHp.IntValue;
	else if (convar == g_cvMedicCriticalReviveHp)
		g_iMedicCriticalReviveHp = g_cvMedicCriticalReviveHp.IntValue;
	else if (convar == g_cvMinorWoundDmg)
		g_iMinorWoundDmg = g_cvMinorWoundDmg.IntValue;
	else if (convar == g_cvModerateWoundDmg)
		g_iModerateWoundDmg = g_cvModerateWoundDmg.IntValue;
	else if (convar == g_cvMedicHealSelfMax)
		g_iMedicHealSelfMax = g_cvMedicHealSelfMax.IntValue;
	else if (convar == g_cvNonMedicHealSelfMax)
		g_iNonMedicHealSelfMax = g_cvNonMedicHealSelfMax.IntValue;
	else if (convar == g_cvNonMedicMaxHealOther)
		g_iNonMedicMaxHealOther = g_cvNonMedicMaxHealOther.IntValue;
	else if (convar == g_cvMinorReviveTime)
		g_iMinorReviveTime = g_cvMinorReviveTime.IntValue;
	else if (convar == g_cvModerateReviveTime)
		g_iModerateReviveTime = g_cvModerateReviveTime.IntValue;
	else if (convar == g_cvCriticalReviveTime)
		g_iCriticalReviveTime = g_cvCriticalReviveTime.IntValue;
	else if (convar == g_cvNonMedicReviveTime)
		g_iNonMedicReviveTime = g_cvNonMedicReviveTime.IntValue;
	else if (convar == g_cvMedpackHealthAmount)
		g_iMedpackHealthAmount = g_cvMedpackHealthAmount.IntValue;
}
