@tool
class_name InteractionRay extends RayCast3D


## The owner of this interaction ray, receives calls to 'on_interaction()' when
## the action is active with the first interactable hit as the only parameter.
@export var interactor: Node3D = null

## How far the interaction ray travels
@export_range(0.01, 2.0, 0.01, 'or_greater', 'suffix:m')
var distance: float = 1.0:
    set = set_distance

## How many interactions the ray can store
@export_range(1, 5, 1, 'or_greater')
var max_interactions: int = 3

## Action which triggers interactions
var action: GUIDEAction = null

## The list of InteractionArea currently being looked at, sorted by priority,
## where higher values appear first.
var interactables: Array[InteractionArea]


func _init() -> void:
    # NOTE: interaction ray uses specific settings always

    # NOTE: manually updated by the owner, never process automatically
    enabled = false
    exclude_parent = true

    # NOTE: interaction ray only works with areas
    collide_with_bodies = false
    collide_with_areas = true

    # NOTE: always allow internal collision
    hit_from_inside = true
    hit_back_faces = true

    # Force target position update
    distance = distance

    interactables = []

## Hide most properties from the editor to simplify configuration, as this
## node uses very specific settings that should not be changed
func _validate_property(property: Dictionary) -> void:
    const HIDDEN_PROPERTIES: PackedStringArray = [
        'collide_with_bodies',
        'collide_with_areas',
        'enabled',
        'exclude_parent',
        'target_position',
        'hit_back_faces',
        'hit_from_inside',
    ]

    if HIDDEN_PROPERTIES.has(property.name):
        property.usage &= ~PROPERTY_USAGE_EDITOR

func set_distance(value: float) -> void:
    distance = value
    target_position = Vector3.FORWARD * distance

## Casts the ray to collect all interaction areas and sorts them by priority.
## If the action is pressed, the owner object is called with the first interaction
## in the list, if one is available.
func update() -> void:
    interactables.clear()
    clear_exceptions()

    for i in range(max_interactions):
        force_raycast_update()

        if not is_colliding():
            break

        # Start by adding the exception
        var collider_rid: RID = get_collider_rid()
        if collider_rid.is_valid():
            add_exception_rid(collider_rid)

        var interaction_area: InteractionArea = get_collider() as InteractionArea
        if interaction_area == null:
            continue

        interactables.append(interaction_area)

    if interactables.size() == 0:
        return

    interactables.sort_custom(_sort_interactions)

    if (interactor != null) and (action != null) and action.is_triggered():
        interactor.call(&'on_interaction', interactables[0])

func _sort_interactions(left: InteractionArea, right: InteractionArea) -> bool:
    return left.priority > right.priority
