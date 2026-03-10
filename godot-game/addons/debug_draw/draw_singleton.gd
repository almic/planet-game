extends Node2D


var camera: Camera3D
var last_transform: Transform3D

## View planes: near, far, left, top, right, bottom
var frustum: Array[Plane]

enum PLANE {
    NEAR = 0,
    FAR,
    LEFT,
    TOP,
    RIGHT,
    BOTTOM
}

enum TYPE {
    VECTOR = 1,
    TEXT,
}

var id_counter: int = 1
var items: Dictionary = {}
var font: Font


func _init() -> void:
    font = SystemFont.new()
    font.font_names = ['monospace', 'mono']

func _process(delta: float) -> void:

    # Tick timed items
    for d in items.values():
        if d.t == 0.0:
            continue

        d.t -= delta
        if d.t > 0.0:
            continue

        # Queue to delete on draw
        d.set(&'delete', true)
        queue_redraw()

    var active_camera: Camera3D = get_viewport().get_camera_3d()
    if active_camera != camera:
        camera = active_camera
        queue_redraw()

    if camera and not last_transform.is_equal_approx(camera.global_transform):
        last_transform = camera.global_transform
        frustum = camera.get_frustum()
        queue_redraw()

func _draw() -> void:
    if not camera:
        return

    var keys = items.keys()
    for k in keys:
        var d: Dictionary = items.get(k)
        if (not d) or d.has(&'delete'):
            items.erase(k)
            continue

        if d.type == TYPE.VECTOR:
            var coords: Vector3 = d.get(&'pos')
            var vec: Vector3 = d.get(&'vec')
            var color: Color = d.get(&'color')

            _draw_vector(coords, vec, color)
        elif d.type == TYPE.TEXT:
            var coords: Vector3 = d.get(&'pos')
            var string: String = d.get(&'str')
            var color: Color = d.get(&'color')

            _draw_text(coords, string, color)
        else:
            push_error('DebugDraw: Unknown type id %d!' % d.type)
            items.erase(k)


func text(coordinates: Vector3, string: String, color: Color, id: int = 0, time: float = 0.0) -> int:
    var d: Dictionary = {}
    id = _get_item(id, TYPE.TEXT, d)

    d.set(&'pos', coordinates)
    d.set(&'str', string)
    d.set(&'color', color)
    d.set(&'t', time)

    items.set(id, d)
    queue_redraw()
    return id

func _draw_text(pos: Vector3, string: String, color: Color) -> void:
    if not camera.is_position_in_frustum(pos):
        return

    var screen: Vector2 = camera.unproject_position(pos)
    draw_string(
            font,
            screen,
            string,
            HORIZONTAL_ALIGNMENT_CENTER,
            -1.0,
            32.0 / pos.distance_to(camera.global_position),
            color
    )

## Draw a vector at a given position. Returns an ID that can be used to update this
## vector later.
func vector(coordinates: Vector3, vec: Vector3, color: Color, id: int = 0, time: float = 0.0) -> int:
    var d: Dictionary = {}
    id = _get_item(id, TYPE.VECTOR, d)

    d.set(&'pos', coordinates)
    d.set(&'vec', vec)
    d.set(&'color', color)
    d.set(&'t', time)

    items.set(id, d)
    queue_redraw()
    return id

func _draw_vector(pos: Vector3, vec: Vector3, color: Color) -> void:
    if vec.is_zero_approx():
        return

    var segment: Vector4 = _clamp_segment(pos, pos + vec)
    if not segment.is_finite():
        return

    var s: Vector2 = Vector2(segment.x, segment.y)
    var e: Vector2 = Vector2(segment.z, segment.w)
    var vec2d: Vector2 = e - s

    if vec2d.is_zero_approx():
        return

    var length: float = vec2d.length()

    # Vector line
    draw_line(s, e, color, -1.0, true)

    # Arrow

    var p: Vector3 = Vector3.FORWARD.cross(Vector3(segment.x, segment.y, 0.0))
    p.z = 0.0
    if p.is_zero_approx():
        p = Vector3.RIGHT
    else:
        p = p.normalized()

    var up: Vector2 = vec2d / length
    var right: Vector2 = Vector2(p.x, p.y)

    draw_line(
        e,
        e + (right - up) * minf(5.0, length / 2.0),
        color, -1.0, true
    )


## Clamps a segment in 3D world coordinates to 2D screen space. Returns a vector
## with x = INF if the segment does not intersect the frustum.
func _clamp_segment(start: Vector3, end: Vector3) -> Vector4:

    # Collect each points frustum info
    var s_frustum: Array[Plane]
    var e_frustum: Array[Plane]
    for idx in range(len(frustum)):
        var face: Plane = frustum[idx]
        if face.is_point_over(start):
            s_frustum.append(face)
        if face.is_point_over(end):
            e_frustum.append(face)

    # Both points are in the frustum
    if s_frustum.size() == 0 and e_frustum.size() == 0:
        var s: Vector2 = camera.unproject_position(start)
        var e: Vector2 = camera.unproject_position(end)
        return Vector4(s.x, s.y, e.x, e.y)

    # At least one point is outside, for each point determine its intersection
    # with the frustum. This is a point intersected on plane A which is behind
    # all other planes

    var s: Vector2
    var e: Vector2

    if s_frustum.size() > 0:
        start = _intersect_planes(start, end, s_frustum)
        if not start.is_finite():
            return Vector4(INF, 0, 0, 0)
    s = camera.unproject_position(start)

    if e_frustum.size() > 0:
        end = _intersect_planes(end, start, e_frustum)
        if not end.is_finite():
            return Vector4(INF, 0, 0, 0)
    e = camera.unproject_position(end)

    return Vector4(s.x, s.y, e.x, e.y)

## Finds the intersection point on a plane in the list which is not over any of
## the other planes.
func _intersect_planes(from: Vector3, to: Vector3, planes: Array[Plane]) -> Vector3:
    var point: Variant

    for i in range(len(planes)):
        point = planes[i].intersects_segment(from, to)
        if not point:
            continue

        var is_over: bool = false
        for k in range(len(planes)):
            if i == k:
                continue

            if planes[k].is_point_over(point):
                is_over = true
                break

        if is_over:
            continue

        return point

    return Vector3(INF, 0, 0)

func _get_next_id() -> int:
    var result: int = id_counter
    id_counter += 1
    return result

func _get_item(id: int, type: TYPE, result: Dictionary) -> int:
    if id < 1:
        id = _get_next_id()
        result.set(&'type', type)
        return id

    var item: Variant = items.get(id)
    if not item:
        id = _get_next_id()
        result.set(&'type', type)
        return id

    if item.type == type:
        result.assign(item)

        # NOTE: remove queued deletion if the item ran out of time this frame
        result.erase(&'delete')

        return id

    push_error(
        'DebugDraw: Updating item %d as a %s type, but it is a %s' % [
            id, TYPE.find_key(type), TYPE.find_key(item.type)
        ]
    )

    id = _get_next_id()
    result.set(&'type', type)
    return id
