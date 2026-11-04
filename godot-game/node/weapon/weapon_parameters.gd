## Parameters for defining weapons, shared among copies of the same weapon
@tool
class_name WeaponParameters extends Resource


## Weapon size, determines what slots it can be stored in
enum Size {
    Small,
    Medium,
    Large
}


#region General
@export_group('General')

## Weapon slot size
@export var size: Size = Size.Small

## Base damage per hit
@export_range(0, 100, 1, 'or_greater')
var base_damage: float = 20.0

## Shock damage per hit
@export_range(0, 100, 1, 'or_greater')
var shock_damage: float = 0.0

## Percentage of damage that ignores armor when the armor is fully in-tact.
## As armor is damaged, it blocks less, such that even a 0.0 armor ratio round
## may deal damage by the second hit.
@export_range(0.0, 1.0, 0.001)
var armor_ratio: float = 0.2

## Number of hits per shot, for instance a shotgun might have 8
@export_range(0, 10, 1, 'or_greater')
var hits_per_shot: int = 1

## Random angle of individual hits, should generally be small even for high
## spread weapons like a shotgun
@export_range(0.0, 10.0, 0.01, 'or_greater', 'radians_as_degrees')
var hit_spread: float = deg_to_rad(0.5)

## Distance that the sound of this weapon can be heard by AI
@export_range(0.0, 100.0, 0.01, 'or_greater', 'suffix:m')
var sound_radius: float = 50.0

## When true, this weapon cannot be dropped from the inventory
@export var key_weapon: bool = false


@export_subgroup('Loading')

## Maximum ammo in reserve
@export_range(1, 500, 1, 'or_greater')
var reserve_capacity: int = 200

## Loaded weapon capacity
@export_range(1, 100, 1, 'or_greater')
var weapon_capacity: int = 60

## Time to reload, when this time passes the weapon is loaded
@export_range(0.01, 5.0, 0.01, 'or_greater', 'suffix:s')
var reload_time: float = 1.5

## Recover time after reload, when this time passes the weapon can be fired
@export_range(0.0, 1.0, 0.01, 'or_greater', 'suffix:s')
var reload_recover_time: float = 0.5
#endregion General

#region Melee
@export_group('Melee')

## When true, this weapon can only melee. Primary fires are equivalent to melee.
@export var melee_only: bool = false

## Melee damage per hit
@export_range(0, 100, 1, 'or_greater')
var melee_damage: float = 40.0

## How long the melee attack is active
@export_range(0.01, 2.0, 0.01, 'or_greater', 'suffix:s')
var melee_time: float = 1.0

## Recover time after melee, when this time passes the weapon can be used again
@export_range(0.0, 1.0, 0.01, 'or_greater', 'suffix:s')
var melee_recover_time: float = 0.5
#endregion Melee

#region Fire Rate
@export_group('Fire Rate')

## If this weapon fires continuously while triggered
@export var automatic_enabled: bool = false

## Fire rate of the weapon. Note that in automatic-mode, the true fire rate is
## rounded so that the physics ticks between shots is equal. Fire rates that
## exceed 1 shot per tick will be rounded so each tick fires the same number of
## shots. This is only possible when automatic is enabled, otherwise players are
## effectively limited to the frequency of physics ticks. See the debug fields
## below for the rounded values that will be used.
@export_range(30, 1500, 1, 'or_greater', 'suffix:RPM')
var fire_rate: int = 300:
    set = set_fire_rate

@export_subgroup('Fire Rate Debug')

## True fire rate, calculated from ticks per activation and shots per tick
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0.0001,or_less,or_greater,hide_control,suffix:RPM',
    PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
)
var effective_fire_rate: float = 0

## How many ticks between each shot
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0,or_less,or_greater,hide_control',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var ticks_between_shots: int = 0

## How many shots are made in a firing tick
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0,or_less,or_greater,hide_control',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var shots_per_fire_tick: int = 0
#endregion Fire Rate

#region Recoil
@export_group('Recoil')

@export_subgroup('Linear', 'recoil_linear')

## Linear acceleration per shot fired
@export_range(0.01, 10.0, 0.01, 'or_greater', 'suffix:m/s\u00B2')
var recoil_linear_acceleration: float = 5.0

## Linear acceleration angle bias, zero points straight back
@export_range(-90.0, 90.0, 0.1, 'radians_as_degrees')
var recoil_linear_bias: float = 0.0

## Linear variability, random angle added to the current velocity direction
@export_range(0.0, 90.0, 0.1, 'radians_as_degrees')
var recoil_linear_variability: float = deg_to_rad(5.0)

## Linear velocity damping, as a percentage per second
@export_range(0.01, 20.0, 0.01, 'or_greater')
var recoil_linear_damping: float = 10.0

## Linear displacement recovery rate, as a percentage per second
@export_range(0.01, 20.0, 0.01, 'or_greater')
var recoil_linear_recovery: float = 10.0

## Maximum linear displacement on the positive axes: right, up, and backwards
@export var recoil_linear_limit_max: Vector3 = Vector3.ONE * 0.05

## Maximum linear displacement on the negative axes: left, down, and forwards
@export var recoil_linear_limit_min: Vector3 = Vector3.ONE * 0.01


@export_subgroup('Angular', 'recoil_angular')

## Angular acceleration per shot fired
@export_range(0.0, 360.0, 0.1, 'or_greater', 'radians_as_degrees', 'suffix:°/s\u00B2')
var recoil_angular_acceleration: float = deg_to_rad(20.0)

## Angular acceleration angle bias, zero points straight up
@export_range(-45.0, 45.0, 0.1, 'radians_as_degrees')
var recoil_angular_bias: float = 0.0

## Angular variability, random angle added to the current velocity direction
@export_range(0.0, 90.0, 0.1, 'radians_as_degrees')
var recoil_angular_variability: float = deg_to_rad(3.0)

## Angular pivot point, relative to the weapon node itself, not the weapon's
## offset. Positive Z is behind the weapon.
@export var recoil_angular_pivot: Vector3 = Vector3(-0.05, 0.25, 0.0)

## Angular velocity damping, as a percentage per second
@export_range(0.01, 20.0, 0.01, 'or_greater')
var recoil_angular_damping: float = 10.0

## Angular displacement recovery rate, as a percentage per second
@export_range(0.01, 20.0, 0.01, 'or_greater')
var recoil_angular_recovery: float = 10.0

## Maximum angular limit, as a cone facing forward (-Z) from the weapon node.
@export_range(0.0, 180.0, 0.1, 'radians_as_degrees')
var recoil_angular_limit: float = deg_to_rad(90.0)
#endregion Recoil

#region Charging
@export_group('Charging')

## If this weapon can be charged, banking shots while continuously triggered,
## and fired in rapid succession when released
@export var charge_enabled: bool = false

## Maximum number of banked shots when charging. If lock-on is enabled, this
## is ignored.
@export_range(1, 10, 1, 'or_greater')
var charge_max_shots: int = 1

## Shots banked per second when charging. If lock-on is enabled, this is
## ignored. Capped to ticks per second. See the debug field below for the true
## charging rate.
@export_range(1, 50, 1, 'or_greater', 'suffix:/s')
var charge_rate: int = 2:
    set = set_charge_rate

## True charge rate, calculated from ticks per charge
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0.0001,or_less,or_greater,hide_control,suffix:/s',
    PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
)
var effective_charge_rate: float = 0

## How many ticks between each charged shot
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0,or_less,or_greater,hide_control',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var ticks_between_charges: int = 0

## How long the weapon must be continuously triggered before the first charge.
## Releasing before this timer will fire immediately, using standard fire rate,
## without any delays or recovery time.
@export_range(0.01, 1.0, 0.01, 'or_greater', 'suffix:s')
var charge_activation_time: float = 0.5

## Recover time after firing charged shots, optionally multiplied by the number
## of charged shots fired.
@export_range(0.0, 1.0, 0.01, 'or_greater', 'suffix:s')
var charge_recover_time: float = 0.2

## If the recover time should be multiplied by the number of charged shots that
## were fired.
@export var charge_recover_per_shot: bool = false

## How long after releasing charge should the first shot be fired
@export_range(0.0, 1.0, 0.01, 'or_greater', 'suffix:s')
var charge_fire_delay: float = 0.0

## Fire rate during charge release
@export_range(30, 1500, 1, 'or_greater', 'suffix:RPM')
var charge_fire_rate: int = 300:
    set = set_charge_fire_rate

@export_subgroup('Charge Fire Rate Debug')

## True fire rate, calculated from ticks per activation and shots per tick
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0.0001,or_less,or_greater,hide_control,suffix:RPM',
    PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
)
var effective_charge_fire_rate: float = 0

## How many ticks between each charged shot
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0,or_less,or_greater,hide_control',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var ticks_between_charged_shots: int = 0

## How many shots are made in a charged firing tick
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0,or_less,or_greater,hide_control',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var shots_per_charged_fire_tick: int = 0
#endregion Charging

#region Lock-on
@export_group('Lock-on')

## If the weapon has lock-on capability. Actual lock-on is enabled via input.
@export var lock_on_enabled: bool = false

## Maximum targets for lock-on.
@export_range(1, 10, 1, 'or_greater')
var lock_on_max_targets: int = 5

## Lock-on cone angle, targets entering the cone can be locked-on at the next
## update, and locked targets which leave the cone will be dropped immediately.
@export_range(1.0, 180.0, 0.1, 'radians_as_degrees')
var lock_on_angle: float = deg_to_rad(45.0)

## Lock-on target update rate, controls the frequency that targets are added or
## switched. This overrides charge rate if charging is enabled. Capped to ticks
## per second. See the debug field below for the true lock-on rate.
@export_range(1, 10, 1, 'or_greater', 'suffix:/s')
var lock_on_rate: int = 4:
    set = set_lock_on_rate

@export_subgroup('Lock-on Rate Debug')

## True target rate, calculated from ticks per update
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0.0001,or_less,or_greater,hide_control,suffix:/s',
    PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
)
var effective_target_lock_rate: float = 0

## How many ticks between each target lock-on update
@export_custom(
    PROPERTY_HINT_RANGE,
    '0,0,0,or_less,or_greater,hide_control',
    PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
)
var ticks_between_target_lock: int = 0
#endregion Lock-on


## Sets and calculates actual fire rate parameters
func set_fire_rate(rate: int) -> void:
    fire_rate = rate

    const TICKS_PER_SECOND: int = InputManager.PHYSICS_TICKS

    var rpt: float = fire_rate * (1.0 / 60.0) * (1.0 / TICKS_PER_SECOND)
    if rpt <= 1.0:
        ticks_between_shots = roundi(1.0 / rpt)
        shots_per_fire_tick = 1
    else:
        ticks_between_shots = 1
        shots_per_fire_tick = roundi(rpt)

    effective_fire_rate = (float(TICKS_PER_SECOND) / float(ticks_between_shots)) * float(shots_per_fire_tick) * 60.0

## Sets and calculates actual charge rate parameters
func set_charge_rate(rate: int) -> void:
    charge_rate = rate

    const TICKS_PER_SECOND: int = InputManager.PHYSICS_TICKS

    var cpt: float = charge_rate * (1.0 / TICKS_PER_SECOND)
    if cpt <= 1.0:
        ticks_between_charges = roundi(1.0 / cpt)
    else:
        ticks_between_charges = 1

    effective_charge_rate = float(TICKS_PER_SECOND) / float(ticks_between_charges)

## Sets and calculates actual charged fire rate parameters
func set_charge_fire_rate(rate: int) -> void:
    charge_fire_rate = rate

    const TICKS_PER_SECOND: int = InputManager.PHYSICS_TICKS

    var rpt: float = charge_fire_rate * (1.0 / 60.0) * (1.0 / TICKS_PER_SECOND)
    if rpt <= 1.0:
        ticks_between_charged_shots = roundi(1.0 / rpt)
        shots_per_charged_fire_tick = 1
    else:
        ticks_between_charged_shots = 1
        shots_per_charged_fire_tick = roundi(rpt)

    effective_charge_fire_rate = (float(TICKS_PER_SECOND) / float(ticks_between_charged_shots)) * float(shots_per_charged_fire_tick) * 60.0

## Sets and calculates actual lock-on rate parameters
func set_lock_on_rate(rate: int) -> void:
    lock_on_rate = rate

    const TICKS_PER_SECOND: int = InputManager.PHYSICS_TICKS

    var upt: float = lock_on_rate * (1.0 / TICKS_PER_SECOND)
    if upt <= 1.0:
        ticks_between_target_lock = roundi(1.0 / upt)
    else:
        ticks_between_target_lock = 1

    effective_target_lock_rate = float(TICKS_PER_SECOND) / float(ticks_between_target_lock)
