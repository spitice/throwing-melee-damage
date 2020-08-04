
# Sanity test by my hands :)

PREREQUISITES: SM Plugins are stored in proper directory.

- Launch CS:GO w/ -insecure
- `map de_dust2` > Wait until the game finishes initialization
- `sv_cheats 1; bot_stop 1; mp_roundtime_defuse 9999; mp_autokick 0; mp_drop_knife_enable 1`
- Join to the game
- `mp_warmup_end` > New round begins
- `give weapon_axe; give weapon_hammer; give weapon_spanner`
- Drop your knife > Grab any melee weapon

> NOTE: Nice to have a bind to spawn melee weapon. `bind q "give weapon_axe"`

## Test Case 1: Self damage

- `sm_throwing_melee_self_damage 10`
  - throw melee to zenith > walk forward > hit to weapon thrown
  - EXPECTED: you should get 5 damage
- `sm_throwing_melee_ignore_armor 1`
  - throw melee to zenith > walk forward > hit to weapon thrown
  - EXPECTED: you should get 10 damage
- `sm_throwing_melee_aimpunch_pitch_yaw 100; sm_throwing_melee_aimpunch_roll 50`
  - throw melee to zenith > walk forward > hit to weapon thrown
  - EXPECTED: you should get 10 damage and your camera should be shook
- `sm_throwing_melee_self_damage 0`
  - throw melee to zenith > walk forward > hit to weapon thrown
  - EXPECTED: you should get no damage and your camera SHOULD BE shook ([#1](https://github.com/spitice/throwing-melee-damage/issues/1))
- `sm_throwing_melee_self_damage 1000`
  - throw melee to zenith > walk forward > hit to weapon thrown
  - EXPECTED: you should get fatal damage and death notification should show your suicidal attempt
- `mp_restartgame 1`
  - EXPECTED: new round should start
- `give weapon_axe; give weapon_hammer; give weapon_spanner`

## Test Case 2: Friendly fire

- NONE
  - throw melee to your teammate
  - EXPECTED: your teammate should not get hurt
- `ff_damage_reduction_other 1`
  - throw melee to your teammate
  - EXPECTED: your teammate should get 60 damage
- `sm_throwing_melee_ignore_armor 0`
  - throw melee to your teammate
  - EXPECTED: your teammate should get 30 damage
- `sm_throwing_melee_ff_damage 0`
  - throw melee to your teammate
  - EXPECTED: your teammate should not get hurt
- `sm_throwing_melee_ff_damage 1000`
  - throw melee to your teammate
  - EXPECTED: your teammate should be killed and death notification should show your TK with proper icon
  - NOTE: Try with every weapon types

## Test Case 3: Damages to enemies

> NOTE: You can check the amount of damage dealt to the enemy in the console.

- NONE
  - throw melee to enemy
  - EXPECTED: Enemy should get hurt
- `sm_throwing_melee_damage 0`
  - throw melee to enemy
  - EXPECTED: Enemy should not get hurt
- `sm_throwing_melee_damage 10; sm_throwing_melee_damage_variance 7`
  - throw melee to enemy
  - EXPECTED: The damage dealt should be varied in every attempt
- `sm_throwing_melee_critical_damage 30; sm_throwing_melee_critical_chance 1`
  - throw melee to enemy
  - EXPECTED: The damage should be from ciritical hit
- `sm_throwing_melee_critical_chance 0.5`
  - throw melee to enemy several times
  - EXPECTED: Both normal and critical hits should be observed
- `sm_throwing_melee_damage 1000; sm_throwing_melee_critical_damage 1000`
  - throw melee to eenemy
  - EXPECTED: enemy should be killed and death notification should show your kill with proper icon
  - NOTE: Try with every weapon types

## Test Case 4: Multiple melee weapons

- Drop your melee weapon
- `give weapon_fists; ent_fire weapon_fists addoutput "classname weapon_knifegg"`
- `give weapon_taser`
- Grab your melee weapon
- `sm_throwing_melee_ff_damage 10`
  - throw melee to teammate
  - EXPECTED: your teammate should get 5 damage

## Test Case 5: Screen shake

- `sm_throwing_melee_test_aimpunch`
  - EXPECTED: your screen should be swung
- `sm_throwing_melee_aimpunch_pitch_yaw 0`
- `sm_throwing_melee_test_aimpunch` several times
  - EXPECTED: both clockwise and counterclockwise should be observed
- `sm_throwing_melee_aimpunch_pitch_yaw 100`
- type `!throwing_melee_test_aimpunch` in chat
  - EXPECTED: nothing happens
- `sm_throwing_melee_allow_test_aimpunch 1`
- type `!throwing_melee_test_aimpunch` in chat
  - EXPECTED: your screen should be swung

## Test Case 6: Weapon-specific damage

- `mp_restartgame 1`
- `sm_throwing_melee_self_damage 10; sm_throwing_melee_ff_damage 10; sm_throwing_melee_ignore_armor 1`
- `sm_throwing_melee_damage_mult_axe 0; sm_throwing_melee_damage_mult_hammer 0.5; sm_throwing_melee_damage_mult_spanner 2`
- throw any melee to zenith > walk forward > hit to weapon thrown
  - EXPECTED: The damage should be 10 and should not be varied by the weapon type
- throw any melee to your teammate
  - EXPECTED: The damage should be 10 and should not be varied by the weapon type
- `sm_throwing_melee_damage 10; sm_throwing_melee_critical_chance 0; sm_throwing_melee_damage_variance 0`
- throw an axe to an enemy
  - EXPECTED: The damage dealt should be 0
- throw a hammer to an enemy
  - EXPECTED: The damage dealt should be 5
- throw a spanner to an enemy
  - EXPECTED: the damage dealt should be 20
- `sm_throwing_melee_critical_chance 0.5; sm_throwing_melee_critical_damage 20`
- `sm_throwing_melee_damage_mult_axe 1; sm_throwing_melee_critical_chance_override_hammer 1; sm_throwing_melee_critical_chance_override_spanner 0`
- throw several axes to enemies
  - EXPECTED: The damage dealt should always be either 10 or 20
- throw several hammers to enemies
  - EXPECTED: The damage dealt should always be 10 w/ critical hit
- throw several spanners to enemies
  - EXPECTED: The damage dealt should always be 20 w/o critical hit

## Test Case 7: Weapon-specific screen shake

- `sm_throwing_melee_self_damage 0`
- `sm_throwing_melee_aimpunch_mult_hammer 0; sm_throwing_melee_aimpunch_mult_spanner 3`
- throw a hammer to yourself:
  - EXPECTED: Screen shake effect should not be applied
- throw a spanner to yourself:
  - EXPECTED: Screen shake effect should be applied and magnified
