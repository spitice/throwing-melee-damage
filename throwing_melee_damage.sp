
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

//
// PREREQUISITE:
//
// A plugin that enables players to pick up danger zone melee weapons.
//

//
// REMARKS:
//
// To enable FF damage, you need to set `ff_damage_reduction_other` greater than 0
// (default might be 0 for casual gamemode) otherwise `sm_throwing_melee_ff_damage` would be useless.
// The value of `sm_throwing_melee_ff_damage` should be `damage-you-want-to-set / ff_damage_reduction_other`.
// For example, when you set `ff_damage_reduction_other` to 0.1 and you want to give FF damage
// exact 50, set `sm_throwing_melee_ff_damage 500` rather than `50`.
//

public Plugin myinfo = {
    name = "Throwing Melee Damage",
    author = "Spitice (10 shots 0 kills)",
    description = "Modifies damage caused by throwing melee weapons (axe, hammer, and wrench)",
    version = "1.1.1",
    url = "https://github.com/spitice"
};

//------------------------------------------------------------------------------
// DEV
//------------------------------------------------------------------------------
#define DEV 0

// Logging
#if DEV
#define LOG PrintToChatAll
#else
#define LOG LogMessage
#endif // DEV

#if DEV
// Required to change entity's mass
//
// vphysics by asherkin:
// https://forums.alliedmods.net/showthread.php?t=136350
#pragma newdecls optional
#include <vphysics>
#pragma newdecls required
#endif // DEV

//------------------------------------------------------------------------------
// Constants
//------------------------------------------------------------------------------
#define MAX_EDICTS 2048
#define MAX_WEAPONS 64  // The array length of m_hMyWeapons

#define WEAPONTYPE_KNIFE 0  // Unused. Just for reference
#define WEAPONTYPE_MELEE 16

#define WEAPONID_AXE        75 // == CSWeapon_AXE
#define WEAPONID_HAMMER     76 // == CSWeapon_HAMMER
#define WEAPONID_SPANNER    78 // == CSWeapon_SPANNER

#define DMG_HEADSHOT (1 << 30)  // Unused.
#define DMG_THROWING_MELEE DMG_CLUB | DMG_NEVERGIB  // (1<<7) | (1<<12) == 4224

char CLSNAME_AXE[]      = "weapon_axe";
char CLSNAME_HAMMER[]   = "weapon_hammer";
char CLSNAME_SPANNER[]  = "weapon_spanner";

// The placeholder of corresponding owner entindex for melee weapons. The
// owner's entindex will be this value by default when the melee weapon is not
// owned by anyone yet AND it somehow hurts a player (e.g., a grenade explosion
// launches the melee weapon then hits someone)
#define NOT_OWNED_YET 0

// If the melee weapon's world model is modified by other plugins, we cannot
// detect weapon type via WorldModelIndex. We use this weaponId in those cases.
#define WEAPONID_NOT_OWNED_FALLBACK WEAPONID_AXE

//------------------------------------------------------------------------------
// ConVars
//------------------------------------------------------------------------------
ConVar g_cvarFFDamage           = null;
ConVar g_cvarSelfDamage         = null;

ConVar g_cvarDamage             = null;
ConVar g_cvarDamageVariance     = null;
ConVar g_cvarCriticalDamage     = null;
ConVar g_cvarCriticalChance     = null;

ConVar g_cvarIgnoreArmor        = null;

ConVar g_cvarAimpunchPitchYaw   = null;
ConVar g_cvarAimpunchRoll       = null;
ConVar g_cvarAllowTestAimpunch  = null;

ConVar g_cvarDamageMultAxe                  = null;
ConVar g_cvarDamageMultHammer               = null;
ConVar g_cvarDamageMultSpanner              = null;
ConVar g_cvarCriticalChanceOverrideAxe      = null;
ConVar g_cvarCriticalChanceOverrideHammer   = null;
ConVar g_cvarCriticalChanceOverrideSpanner  = null;
ConVar g_cvarAimpunchMultAxe                = null;
ConVar g_cvarAimpunchMultHammer             = null;
ConVar g_cvarAimpunchMultSpanner            = null;


//------------------------------------------------------------------------------
// Game state
//------------------------------------------------------------------------------
int g_entindexToOwner[MAX_EDICTS];
int g_entindexToWeaponId[MAX_EDICTS];


//------------------------------------------------------------------------------
// Setup
//------------------------------------------------------------------------------
public void OnPluginStart() {

    HookEvent( "round_start", OnRoundStart );   // Resets entindex states every round
    HookEvent( "item_equip", OnItemEquip );     // Where we update the information about melee weapons in game

    //
    // ConVars
    //
    // FF/Self damage
    g_cvarFFDamage          = CreateConVar( "sm_throwing_melee_ff_damage", "60", "Amount of FF damage from a throwing melee" );
    g_cvarSelfDamage        = CreateConVar( "sm_throwing_melee_self_damage", "60", "Amount of self damage from a throwing melee" );

    // Damage to an enemy
    g_cvarDamage            = CreateConVar( "sm_throwing_melee_damage", "60", "Amount of damage from a throwing melee" );
    g_cvarDamageVariance    = CreateConVar( "sm_throwing_melee_damage_variance", "0", "Amount of damage variance for enemy hits. Actual damage = Base damage + RandomInt(-Variance, Variance)" );
    g_cvarCriticalDamage    = CreateConVar( "sm_throwing_melee_critical_damage", "180", "Amount of critical damage from throwing melee. Only for damages dealt to enemies; FF and self damages never cause critical hits." );
    g_cvarCriticalChance    = CreateConVar( "sm_throwing_melee_critical_chance", "0", "Chance of critical damage [0, 1]. Set 1 to make it always critical for nonsense" );

    // Armor penetration
    g_cvarIgnoreArmor       = CreateConVar( "sm_throwing_melee_ignore_armor", "0", "If 1, all throwing melee damages penetrate armor.", 0, true, 0.0, true, 1.0 );

    // Aimpunch (screen shake effect on hit)
    g_cvarAimpunchPitchYaw  = CreateConVar( "sm_throwing_melee_aimpunch_pitch_yaw", "0", "Amount of screen shake on hit in degrees. Only affects pitch and yaw." );
    g_cvarAimpunchRoll      = CreateConVar( "sm_throwing_melee_aimpunch_roll", "0", "Amount of screen shake on hit in degrees. Only affects roll." );
    g_cvarAllowTestAimpunch = CreateConVar( "sm_throwing_melee_allow_test_aimpunch", "0", "Allows clients to execute test_aimpunch command.", 0, true, 0.0, true, 1.0 );

    // Weapon specific parameters
    g_cvarDamageMultAxe     = CreateConVar( "sm_throwing_melee_damage_mult_axe", "1", "Damage multiplier for axes" );
    g_cvarDamageMultHammer  = CreateConVar( "sm_throwing_melee_damage_mult_hammer", "1", "Damage multiplier for hammers" );
    g_cvarDamageMultSpanner = CreateConVar( "sm_throwing_melee_damage_mult_spanner", "1", "Damage multiplier for wrenches" );

    g_cvarCriticalChanceOverrideAxe     = CreateConVar( "sm_throwing_melee_critical_chance_override_axe", "-1", "Critical chance for axes. -1 to inherit sm_throwing_critical_chance" );
    g_cvarCriticalChanceOverrideHammer  = CreateConVar( "sm_throwing_melee_critical_chance_override_hammer", "-1", "Critical chance for hammers. -1 to inherit sm_throwing_critical_chance" );
    g_cvarCriticalChanceOverrideSpanner = CreateConVar( "sm_throwing_melee_critical_chance_override_spanner", "-1", "Critical chance for wrenches. -1 to inherit sm_throwing_critical_chance" );

    g_cvarAimpunchMultAxe     = CreateConVar( "sm_throwing_melee_aimpunch_mult_axe", "1", "Aimpunch effect multiplier for axes" );
    g_cvarAimpunchMultHammer  = CreateConVar( "sm_throwing_melee_aimpunch_mult_hammer", "1", "Aimpunch effect multiplier for hammers" );
    g_cvarAimpunchMultSpanner = CreateConVar( "sm_throwing_melee_aimpunch_mult_spanner", "1", "Aimpunch effect multiplier for wrenches" );

    //
    // Commands
    //
    RegConsoleCmd( "sm_throwing_melee_test_aimpunch", Command_TestAimpunch );

    // Initialization and set up entity hooks
    Initialize();

    int ent = -1;
    while ( ( ent = FindEntityByClassname( ent, "player" ) ) != -1 ) {
        SDKHook( ent, SDKHook_OnTakeDamage, OnTakeDamage );
    }

#if DEV
    while ( ( ent = FindEntityByClassname( ent, "weapon_melee" ) ) != -1 ) {
        SDKHook( ent, SDKHook_OnTakeDamage, OnTakeDamage_MeleeWeapon );
    }
#endif // DEV
}

public void OnClientPutInServer( int client ) {
    // Register a hook for overriding TakeDamage behavior
    SDKHook( client, SDKHook_OnTakeDamage, OnTakeDamage );
}

#if DEV
public void OnEntityCreated( int ent, const char[] classname ) {
    if ( StrEqual( classname, "weapon_melee" ) ) {
        SDKHook( ent, SDKHook_OnTakeDamage, OnTakeDamage_MeleeWeapon );
    }
}
#endif // DEV

void Initialize() {
    for ( int i = 0; i < MAX_EDICTS; i++ ) {
        g_entindexToOwner[i] = NOT_OWNED_YET;
        g_entindexToWeaponId[i] = WEAPONID_NOT_OWNED_FALLBACK;
    }
}

//------------------------------------------------------------------------------
// Hooks
//------------------------------------------------------------------------------

/**
 * @see https://wiki.alliedmods.net/Counter-Strike:_Global_Offensive_Events#round_start
 */
public Action OnRoundStart( Event event, const char[] name, bool dontBroadcast ) {
    Initialize();
}

/**
 * @see https://wiki.alliedmods.net/Counter-Strike:_Global_Offensive_Events#item_equip
 */
public Action OnItemEquip( Event event, const char[] name, bool dontBroadcast ) {

    int weptype = GetEventInt( event, "weptype" );
    if ( weptype != WEAPONTYPE_MELEE ) {
        // We don't care any weapon slots other than melee
        return Plugin_Continue;
    }

    // Determine which melee weapon it actually is
    int defindex = GetEventInt( event, "defindex" );

    if (
        defindex != WEAPONID_AXE &&
        defindex != WEAPONID_HAMMER &&
        defindex != WEAPONID_SPANNER
    ) {
        // The weapon is not what we want. It might be a knife, fists or something.
        return Plugin_Continue;
    }

    // Get the client's entindex
    int userid = GetEventInt( event, "userid" );
    int entClient = GetClientOfUserId( userid );

    //
    // Get the melee weapon's entindex
    //
    // NOTE: `GetPlayerWeaponSlot( entClient, CS_SLOT_KNIFE )` won't work if the player has `knifegg`
    //
    int entMelee = -1;
    for ( int i = 0; i < MAX_WEAPONS; i++ ) {
        int entWeapon = GetEntPropEnt( entClient, Prop_Send, "m_hMyWeapons", i );
        if ( entWeapon == -1 ) {
            continue;
        }

        char clsname[256];
        GetEntityClassname( entWeapon, clsname, sizeof(clsname) );
        if ( StrEqual( clsname, "weapon_melee" ) ) {
            // We've found the weapon. Yay!
            entMelee = entWeapon;
            break;
        }
    }

    if ( entMelee == -1 ) {
        LogError( "[OnItemEquip] Failed to find the melee weapon from the player's inventory..." );
        return Plugin_Continue;
    }

    // Validation for SAFETY
    if ( !IsValidEdict( entClient ) ) {
        LogError( "[OnItemEquip] The client id is invalid. Something went wrong..." );
        return Plugin_Continue;
    }
    if ( !IsValidEdict( entMelee ) ) {
        LogError( "[OnItemEquip] entindex for the melee weapon is invalid. Something went wrong..." );
        return Plugin_Continue;
    }

    // Store the information for later use
    g_entindexToOwner[entMelee] = entClient;
    g_entindexToWeaponId[entMelee] = defindex;

    // Just logging
#if DEV
    char weaponClsname[16];
    MeleeWeaponIdToClassname( defindex, weaponClsname );
    LOG( "%s [%d] owned by %N [%d]", weaponClsname, entMelee, entClient, entClient );
#endif

    return Plugin_Continue;
}


public Action OnTakeDamage(
    int victim,
    int& attacker,
    int& inflictor,
    float& damage,
    int& damagetype,
    int& weapon,
    float damageForce[3],
    float damagePosition[3]
) {
    // *** DANGER ***
    // Any runtime error occurred in this hook function would break the game! (e.g., players become invincible)
    // Please be careful to review/modify this code section :)

    // We only care about damages triggered by melee weapons thrown
    if ( damagetype != DMG_THROWING_MELEE ) {
        // Eject as fast as possible so this hook barely affect the game performance
        return Plugin_Continue;
    }

    // Let's check the weapon's classname
    char inflictorClsname[256];
    GetEntityClassname( inflictor, inflictorClsname, sizeof(inflictorClsname) );
    if ( !StrEqual( inflictorClsname, "weapon_melee" ) ) {
        // It is not from a throwing melee weapon.
        //
        // This filter also catches damages caused by our point_hurt because
        // their class name would be either "weapon_axe/hammer/spanner".
        return Plugin_Continue;
    }

    // Grab the client who threw the melee weapon
    int thrower  = g_entindexToOwner[inflictor];
    int weaponId = g_entindexToWeaponId[inflictor];

    if ( thrower == NOT_OWNED_YET ) {
        // This melee weapon apparently has never been owned by any players.
        // Therefore, we don't know which type of melee weapon it is yet.
        //
        // Let's assume it is self-infliction.
        thrower = victim;
        weaponId = GetMeleeWeaponId( inflictor );

    } else if ( !IsValidEdict( thrower ) || !IsClientInGame( thrower ) ) {
        // The player who threw the melee has been disconnected.
        // Let's assume it is self-infliction.
        thrower = victim;
    }

    // Weapon-specific parameters
    char weaponClsname[16];
    MeleeWeaponIdToClassname( weaponId, weaponClsname );

    float fDamageMult   = GetDamageMultiplier( weaponId );
    float fCritChance   = GetCriticalChance( weaponId );
    float fAimpunchMult = GetAimpunchMultiplier( weaponId );

    // Determine the type of damage
    int teamVictim  = GetClientTeam( victim );
    int teamThrower = GetClientTeam( thrower );
    bool isFriendlyFire = teamVictim == teamThrower;
    bool isSelfFire = victim == thrower;

    LOG( "Weapon: %s", weaponClsname );
    if ( !isFriendlyFire ) {
        // Weapon-specific damage parameters will only affects on non FF damages
        LOG( " - Dmg: x%.2f, Crit chance: %d%%", fDamageMult, RoundToNearest( fCritChance * 100 ) );
    }
    LOG( " - Aimpunch: x%.2f", fAimpunchMult );
    LOG( " - Victim: %N (%d)", victim, victim );
    LOG( " - Attacker: %N (%d)", thrower, thrower );

    // Calculate the damage
    float fDamage = 0.0;

    if ( isSelfFire ) {
        LOG( " - (SELF FIRE)" );
        fDamage = g_cvarSelfDamage.FloatValue;

    } else if ( isFriendlyFire ) {
        LOG( " - (FRIENDLY FIRE)" );
        fDamage = g_cvarFFDamage.FloatValue;

    } else {
        // Base damage
        fDamage = g_cvarDamage.FloatValue;

        // Is critical hit?
        if ( GetURandomFloat() < fCritChance ) {
            LOG( " - ** CRITICAL HIT! **" );
            fDamage = g_cvarCriticalDamage.FloatValue;
        }

        // Randomize the damage
        int iVar = g_cvarDamageVariance.IntValue;
        int iDelta = GetRandomInt( -iVar, iVar );
        fDamage += float(iDelta);

        // Apply weapon-specific damage multiplier
        fDamage *= fDamageMult;

        // Clamp the damage value
        if ( fDamage < 0 ) {
            fDamage = 0.0;
        }
    }

    int iDamage = RoundToNearest( fDamage );
    LOG( " - Damage = %d", iDamage );

    if ( iDamage > 0 ) {
        // point_hurt ironically generates a small amount of damage even if we put 0 damage.
        // To completely discard the damage, just don't call DealDamage function.

        int newDamageType = DMG_THROWING_MELEE;  // == damagetype
        if ( g_cvarIgnoreArmor.BoolValue ) {
            // Remove DMG_CLUB from the damagetype so the damage ignores armor completely
            newDamageType = DMG_NEVERGIB;
            LOG( " - Ignored armor" );
        }
        DealDamage( victim, iDamage, thrower, newDamageType, weaponClsname, damageForce );
    }

    // Aimpunch effect will be applied regardless of how much damage is done
    ApplyAimpunch( victim, fAimpunchMult );

    return Plugin_Handled;
}


#if DEV
public Action OnTakeDamage_MeleeWeapon(
    int victim,
    int& attacker,
    int& inflictor,
    float& damage,
    int& damagetype,
    int& weapon,
    float damageForce[3],
    float damagePosition[3]
) {
    // Default = 150
    Phys_SetMass( victim, 1.0 );
    return Plugin_Continue;
}
#endif // DEV


public Action Command_TestAimpunch( int client, int args ) {

    if ( client == 0 ) {
        // Server admin can always execute test_aimpunch command.
        // Applies to all players
        client = -1;
        while ( ( client = FindEntityByClassname( client, "player" ) ) != -1 ) {
            ApplyAimpunch( client );
        }

    } else {
        if ( g_cvarAllowTestAimpunch.BoolValue ) {
            ApplyAimpunch( client );
        }
    }

    return Plugin_Handled;
}

//------------------------------------------------------------------------------
// Utilities
//------------------------------------------------------------------------------

/**
 * Deals damage that might show the death notification with the proper icon.
 *
 * It temporarily creates a `point_hurt` that pretends to be the given weapon type.
 * After it applies the damage to the victim, immediately disappears from the game.
 *
 * Shamelessly borrowed the code from `l4d_damage.sp` by AtomicStryker.
 * https://forums.alliedmods.net/showthread.php?t=116668
 * which is based on a code snippet by pimpinjuice
 * https://forums.alliedmods.net/showthread.php?t=111684
 */
void DealDamage( int victim, int damage, int attacker, int damagetype, const char[] weapon, float damageForce[3] ) {

    char strDamage[16];
    char strDamageType[32];
    char strDamageTarget[16];
    IntToString( damage, strDamage, sizeof(strDamage) );
    IntToString( damagetype, strDamageType, sizeof(strDamageType) );
    Format( strDamageTarget, sizeof(strDamageTarget), "hurtme%d", victim );

    // Backup the victim's targetname
    char strOrigName[256];
    GetEntPropString( victim, Prop_Data, "m_iName", strOrigName, sizeof(strOrigName) );

    // Calculate the position for the point_hurt
    float victimPos[3];
    float hurtPos[3];
    GetClientAbsOrigin( victim, victimPos );
    SubtractVectors( victimPos, damageForce, hurtPos );

    // Prepare
    int entHurt = CreateEntityByName( "point_hurt" );
    if ( !entHurt ) {
        return;
    }

    DispatchKeyValue( victim, "targetname", strDamageTarget );
    DispatchKeyValue( entHurt, "DamageTarget", strDamageTarget );
    DispatchKeyValue( entHurt, "Damage", strDamage );
    DispatchKeyValue( entHurt, "DamageType", strDamageType );
    DispatchKeyValue( entHurt, "classname", weapon );
    DispatchSpawn( entHurt );

    TeleportEntity( entHurt, hurtPos, NULL_VECTOR, NULL_VECTOR );

    // Give damage
    AcceptEntityInput( entHurt, "Hurt", attacker );  // -> OnTakeDamage will be called again

    // Teardown
    DispatchKeyValue( entHurt, "classname", "point_hurt" );
    DispatchKeyValue( victim, "targetname", strOrigName );
    RemoveEdict( entHurt );
}

/**
 * Determines the melee weapon type from the melee weapon entity.
 */
int GetMeleeWeaponId( int ent ) {
    int worldModelIndex = GetEntProp( ent, Prop_Send, "m_iWorldModelIndex" );
    if ( worldModelIndex == PrecacheModel( "models/weapons/w_axe.mdl" ) ) {
        return WEAPONID_AXE;
    } else if ( worldModelIndex == PrecacheModel( "models/weapons/w_hammer.mdl" ) ) {
        return WEAPONID_HAMMER;
    } else if ( worldModelIndex == PrecacheModel( "models/weapons/w_spanner.mdl" ) ) {
        return WEAPONID_SPANNER;
    }
    return WEAPONID_NOT_OWNED_FALLBACK;
}

/**
 * Applies aimpunch effect on the client.
 */
void ApplyAimpunch( int client, float multiplier = 1.0 ) {

    float magnitudeXY = g_cvarAimpunchPitchYaw.FloatValue * multiplier;
    float magnitudeZ = g_cvarAimpunchRoll.FloatValue * multiplier;

    if ( magnitudeXY == 0 && magnitudeZ == 0 ) {
        return;
    }

    // Pitch & Yaw
    float theta = GetURandomFloat() * FLOAT_PI * 2;
    float pitch = -Cosine( theta );
    float yaw = -Sine( theta );

    // Roll
    bool isCCW = GetURandomFloat() > 0.5;
    float roll = isCCW ? 1.0 : -1.0;

    float angle[3] = {0.0, 0.0, 0.0};  // (pitch, yaw, roll) in degree
    angle[0] = pitch * magnitudeXY;
    angle[1] = yaw * magnitudeXY;
    angle[2] = roll * magnitudeZ;

    // Apply the screen shake
    SetEntPropVector( client, Prop_Send, "m_aimPunchAngle", angle );
    SetEntPropVector( client, Prop_Send, "m_aimPunchAngleVel", angle );  // Almost meaningless but it adds subtle shake
}

/**
 * Converts the given weapon id to its corresponding classname.
 *
 * Don't feed any weapon id that is not of melee weapon!
 */
void MeleeWeaponIdToClassname( int weaponId, char out[16] ) {
    switch ( weaponId ) {
        case WEAPONID_AXE:
            strcopy( out, sizeof(out), CLSNAME_AXE );
        case WEAPONID_HAMMER:
            strcopy( out, sizeof(out), CLSNAME_HAMMER );
        case WEAPONID_SPANNER:
            strcopy( out, sizeof(out), CLSNAME_SPANNER );
        default:
            LogError( "[MeleeWeaponIdToClassname] Invalid weapon id: %d", weaponId );
    }
}

/**
 * Gets the damage multiplier for the weapon.
 */
float GetDamageMultiplier( int weaponId ) {
    switch ( weaponId ) {
        case WEAPONID_AXE:
            return g_cvarDamageMultAxe.FloatValue;
        case WEAPONID_HAMMER:
            return g_cvarDamageMultHammer.FloatValue;
        case WEAPONID_SPANNER:
            return g_cvarDamageMultSpanner.FloatValue;
    }

    LogError( "[GetDamageMultiplier] Invalid weapon id: %d", weaponId );
    return 1.0;
}

/**
 * Gets the damage multiplier for the weapon.
 */
float GetCriticalChance( int weaponId ) {
    float overriddenChance = -1.0;

    switch ( weaponId ) {
        case WEAPONID_AXE:
            overriddenChance = g_cvarCriticalChanceOverrideAxe.FloatValue;
        case WEAPONID_HAMMER:
            overriddenChance = g_cvarCriticalChanceOverrideHammer.FloatValue;
        case WEAPONID_SPANNER:
            overriddenChance = g_cvarCriticalChanceOverrideSpanner.FloatValue;
        default:
            LogError( "[GetCriticalChance] Invalid weapon id: %d", weaponId );
    }

    if ( overriddenChance < 0.0 ) {
        // Use the global critical chance
        return g_cvarCriticalChance.FloatValue;
    }
    return overriddenChance;
}

/**
 * Gets the multiplier of aimpunch effect for the weapon.
 */
float GetAimpunchMultiplier( int weaponId ) {
    switch ( weaponId ) {
        case WEAPONID_AXE:
            return g_cvarAimpunchMultAxe.FloatValue;
        case WEAPONID_HAMMER:
            return g_cvarAimpunchMultHammer.FloatValue;
        case WEAPONID_SPANNER:
            return g_cvarAimpunchMultSpanner.FloatValue;
    }

    LogError( "[GetAimpunchMultiplier] Invalid weapon id: %d", weaponId );
    return 1.0;
}
