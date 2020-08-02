
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
    version = "1.0",
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
#endif

//------------------------------------------------------------------------------
// Constants
//------------------------------------------------------------------------------
#define MAX_EDICTS 2048

#define WEAPONTYPE_KNIFE 0  // Unused
#define WEAPONTYPE_MELEE 16

#define WEAPONID_AXE        75 // == CSWeapon_AXE
#define WEAPONID_HAMMER     76 // == CSWeapon_HAMMER
#define WEAPONID_SPANNER    78 // == CSWeapon_SPANNER

#define DMG_THROWING_MELEE DMG_CLUB | DMG_NEVERGIB  // == 4224

char CLSNAME_AXE[]      = "weapon_axe";
char CLSNAME_HAMMER[]   = "weapon_hammer";
char CLSNAME_SPANNER[]  = "weapon_spanner";

// We use this to distinguish whom an OnTakeDamage event sent by between
// the game and the point_hurt entity we artificially create.
// Set a negative number so IsValidEdict() can bravely return false.
#define FROM_POINT_HURT -1

//------------------------------------------------------------------------------
// ConVars
//------------------------------------------------------------------------------
ConVar g_cvarDamage = null;
ConVar g_cvarFFDamage = null;
ConVar g_cvarSelfDamage = null;
ConVar g_cvarDamageVariance = null;
ConVar g_cvarCriticalDamage = null;
ConVar g_cvarCriticalChance = null;

//------------------------------------------------------------------------------
// Game state
//------------------------------------------------------------------------------
int g_entindexToOwner[MAX_EDICTS];
int g_entindexToWeaponId[MAX_EDICTS];


//------------------------------------------------------------------------------
// Setup
//------------------------------------------------------------------------------
public void OnPluginStart() {

    HookEvent( "item_equip", OnItemEquip );  // Where we update the information about melee weapons in game

    g_cvarDamage            = CreateConVar( "sm_throwing_melee_damage", "60", "Amount of damage from a throwing melee" );
    g_cvarFFDamage          = CreateConVar( "sm_throwing_melee_ff_damage", "60", "Amount of FF damage from a throwing melee" );
    g_cvarSelfDamage        = CreateConVar( "sm_throwing_melee_self_damage", "60", "Amount of FF damage from a throwing melee" );
    g_cvarDamageVariance    = CreateConVar( "sm_throwing_melee_damage_variance", "0", "Amount of damage variance for enemy hits. Actual damage = Base damage + RandomInt(-Variance, Variance)" );
    g_cvarCriticalDamage    = CreateConVar( "sm_throwing_melee_critical_damage", "180", "Amount of critical damage from throwing melee. Only for damages dealt to enemies; FF and self damages never cause critical hits." );
    g_cvarCriticalChance    = CreateConVar( "sm_throwing_melee_critical_chance", "0", "Chance of critical damage [0, 1]. Set 1 to make it always critical for nonsense" );

    // For development:
    // Adds hook for OnTakeDamage after invoking `sm plugins reload this-plugin-name.sp` in the game
    // Redundant on production build
#if DEV
    int client = -1;
    while ( ( client = FindEntityByClassname( client, "player" ) ) != -1 ) {
        SDKHook( client, SDKHook_OnTakeDamage, OnTakeDamage );
    }
#endif
}

public void OnClientPutInServer( int client ) {
    // Register a hook for overriding TakeDamage behavior
	SDKHook( client, SDKHook_OnTakeDamage, OnTakeDamage );
}

//------------------------------------------------------------------------------
// Hooks
//------------------------------------------------------------------------------

/**
 * @see https://wiki.alliedmods.net/Counter-Strike:_Global_Offensive_Events#item_equip
 */
public Action OnItemEquip( Event event, const char[] name, bool dontBroadcast ) {

    int weptype = GetEventInt( event, "weptype" );
    if ( weptype != WEAPONTYPE_MELEE ) {
        // We don't care any weapon slots other than melee
        return Plugin_Continue;
    }

    // Get the client's entindex
    int userid = GetEventInt( event, "userid" );
    int entClient = GetClientOfUserId( userid );

    // Get the melee weapon's entindex
    int entMelee = GetPlayerWeaponSlot( entClient, CS_SLOT_KNIFE );

    // Determine which melee weapon it actually is
    int defindex = GetEventInt( event, "defindex" );

    if (
        defindex != WEAPONID_AXE &&
        defindex != WEAPONID_HAMMER &&
        defindex != WEAPONID_SPANNER
    ) {
        // The weapon is not what we want. It might be a knife or something.
        return Plugin_Continue;
    }

    // Validation for SAFETY
    if ( !IsValidEdict( entClient ) ) {
        LogError( "[ThrowMeleeDmg][OnItemEquip] The client id is invalid. Something went wrong..." );
        return Plugin_Continue;
    }
    if ( !IsValidEdict( entMelee ) ) {
        LogError( "[ThrowMeleeDmg][OnItemEquip] entindex for the melee weapon is invalid. Something went wrong..." );
        return Plugin_Continue;
    }

    // Store the information for later use
    g_entindexToOwner[entMelee] = entClient;
    g_entindexToWeaponId[entMelee] = defindex;

    // Just logging
    char weaponClsname[16];
    MeleeWeaponIdToClassname( defindex, weaponClsname );
    LOG( "%s [%d] owned by %N [%d]", weaponClsname, entMelee, entClient, entClient );

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

    // Let's check the weapon's classname just in case!
    char inflictorClsname[256];
    GetEntityClassname( inflictor, inflictorClsname, sizeof(inflictorClsname) );

    if ( !StrEqual( inflictorClsname, "weapon_melee" ) ) {
        // It is not from an melee weapon. Ignore it.
        return Plugin_Continue;
    }

    // Grab the client who threw the melee weapon
    int thrower = g_entindexToOwner[inflictor];

    if ( thrower == FROM_POINT_HURT ) {
        // The damage is caused by the point_hurt we have created.
        // Just ignore it.
        // NOTE: Perhaps, this type of damage is filtered at `!StrEqual( inflictorClsname, "weapon_melee" )` line?
        return Plugin_Continue;
    }
    if ( !IsValidEdict( thrower ) ) {
        LogError( "[ThrowMeleeDmg][OnTakeDamage] entindex for the client who threw the melee weapon is invalid. Is he/she still connected?" );
        return Plugin_Continue;
    }

    int weaponId = g_entindexToWeaponId[inflictor];
    char weaponClsname[16];
    MeleeWeaponIdToClassname( weaponId, weaponClsname );

    LOG( "[ThrowMeleeDmg] Weapon: %s, Victim: %N", weaponClsname, victim );

    int teamVictim  = GetClientTeam( victim );
    int teamThrower = GetClientTeam( thrower );
    bool isFriendlyFire = teamVictim == teamThrower;
    bool isSelfFire = victim == thrower;

    int iDamage = 0;

    // No damage
    if ( isSelfFire ) {
        LOG( "[ThrowMeleeDmg] SELF FIRE" );
        iDamage = g_cvarSelfDamage.IntValue;

    } else if ( isFriendlyFire ) {
        LOG( "[ThrowMeleeDmg] FRIENDLY FIRE" );
        iDamage = g_cvarFFDamage.IntValue;

    } else {
        LOG( "[ThrowMeleeDmg] TO ENEMY" );
        // Base damage
        iDamage = g_cvarDamage.IntValue;

        // Is critical hit?
        float fCritChance = g_cvarCriticalChance.FloatValue;
        if ( GetURandomFloat() < fCritChance ) {
            LOG( "[ThrowMeleeDmg] CRITICAL HIT!" );
            iDamage = g_cvarCriticalDamage.IntValue;
        }

        // Randomize the damage
        int iVar = g_cvarDamageVariance.IntValue;
        int iDelta = GetRandomInt( -iVar, iVar );
        iDamage += iDelta;
        if ( iDamage < 0 ) {
            iDamage = 0;
        }
    }

    LOG( "[ThrowMeleeDmg] Damage = %d", iDamage );

    if ( iDamage > 0 ) {
        // point_hurt ironically generates a small amount of damage even if we put 0 damage.
        // To completely discard the damage, just don't call DealDamage function.

        //int newDamageType = DMG_NEVERGIB;  // Unused: Remove DMG_CLUB from the damagetype so the damage ignores armor completely
        DealDamage( victim, iDamage, thrower, DMG_THROWING_MELEE, weaponClsname, damageForce );
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
 */
void DealDamage( int victim, int damage, int attacker, int damagetype, const char[] weapon, float damageForce[3] ) {

    char strDamage[16];
    char strDamageType[32];
    char strDamageTarget[16];
    IntToString( damage, strDamage, sizeof(strDamage) );
    IntToString( damagetype, strDamageType, sizeof(strDamageType) );
    Format( strDamageTarget, sizeof(strDamageTarget), "hurtme%d", victim );

    // Calculate the position for the point_hurt
    // TODO: improve this
    float victimPos[3];
    float hurtPos[3];
    GetClientAbsOrigin( victim, victimPos );
    SubtractVectors( victimPos, damageForce, hurtPos );

    // Prepare
    int entHurt = CreateEntityByName( "point_hurt" );
    if ( !entHurt ) {
        return;
    }
    g_entindexToOwner[entHurt] = FROM_POINT_HURT;  // Invalidate the owner entindex so it won't accidentally use outdated data

    DispatchKeyValue( victim, "targetname", strDamageTarget );
    DispatchKeyValue( entHurt, "DamageTarget", strDamageTarget );
    DispatchKeyValue( entHurt, "Damage", strDamage );
    DispatchKeyValue( entHurt, "DamageType", strDamageType );
    DispatchKeyValue( entHurt, "classname", weapon );
    DispatchSpawn( entHurt );

    TeleportEntity( entHurt, hurtPos, NULL_VECTOR, NULL_VECTOR );
    AcceptEntityInput( entHurt, "Hurt", attacker );  // -> OnTakeDamage will be called again

    // Teardown
    DispatchKeyValue( entHurt, "classname", "point_hurt" );
    DispatchKeyValue( victim, "targetname", "null" );
    RemoveEdict( entHurt );
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
    }
}
