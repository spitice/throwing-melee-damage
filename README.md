
# [SourceMod Plugin/CSGO] Throwing Melee Damage

This plugin enables you to tweak damages done by throwing weapons. In addition, it can also apply screen shake effect on hit.


## Prerequisite

- A SM plugin that let you obtain melee weapons.


## Supported weapons

- `weapon_axe`
- `weapon_hammer`
- `weapon_spanner`


## ConVars and commands

```
sm_throwing_melee_damage 60
sm_throwing_melee_ff_damage 60
sm_throwing_melee_self_damage 60
sm_throwing_melee_damage_variance 0
sm_throwing_melee_critical_damage 180
sm_throwing_melee_critical_chance 0
sm_throwing_melee_ignore_kevlar 0
sm_throwing_melee_aimpunch_pitchyaw 0
sm_throwing_melee_aimpunch_roll 0
```

Commands:

```
sm_throwing_melee_test_aimpunch
```


## Example: ConVar settings

Fatal self damage:

```
sm_throwing_melee_self_damage 1000
```

Random damages:

```
sm_throwing_melee_damage_variance 40   // 60 ± 40 damage
sm_throwing_melee_critical_chance 0.3  // 30% chance to deal 180 ± 40 damage
```

Ignoring kevlar:

```
sm_throwing_melee_ignore_kevlar 1
sm_throwing_melee_damage 45
sm_throwing_melee_critical_damage 95
```

Screen shake on hit:

```
sm_throwing_melee_aimpunch_pitchyaw 100  // Rotates camera by 100 deg
sm_throwing_melee_aimpunch_roll 50       // Twists camera by 50 deg
```


## Damage types and how to calculate damage

There are three types of damage the plugin handles:

- Self damage
- Friendly fire
- Damage dealt to an enemy

For self inflicting damage:

```
self-damage = sm_throwing_melee_self_damage
```

For friendly fire:

```
ff-damage = sm_throwing_melee_ff_damage * ff_damage_reduction_other
```

For hits dealt to enemies:

```
is-critical-hit = RandFloat(0.0, 1.0) < sm_throwing_melee_critical_chance
damage-variance = RandInt(-sm_throwing_melee_damage_variance, sm_throwing_melee_damage_variance)

if is-critical-hit:
  damage = sm_throwing_melee_ciritical_damage + damage-variance

else:
  damage = sm_throwing_melee_damage + damage-variance
```

> NOTE: All damage values less than 0 will be safely ignored.

With `sm_throwing_melee_ignore_kevlar 0`, kevlar reduces damage from a throwing melee by **50%**.


## Enabling Friendly Fire

Besides setting the value for `sm_throwing_melee_ff_damage`, you need to set `ff_damage_reduction_other` greater than 0 to actually apply FF damages caused by the throwing melee weapons.


## Acknowledgements

The function to apply arbitrary damage to a client is borrowed from [`l4d_damage.sp` by AtomicStryker](https://forums.alliedmods.net/showthread.php?t=116668).