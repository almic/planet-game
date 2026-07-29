extends Node2D


const Chart = preload("uid://dqa5gk08lqrqd")


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
    SPHERE,
    CIRCLE,
    POLYLINE,
}

var id_counter: int = 1
var items: Dictionary = {}
var font: Font
var layers: Dictionary = {}
var layer_add_queue: Array[CanvasLayer] = []


func _init() -> void:
    font = SystemFont.new()
    font.font_names = ['monospace', 'mono']

func _process(delta: float) -> void:

    if layer_add_queue.size() > 0 and get_parent().is_node_ready():
        for layer in layer_add_queue:
            add_sibling(layer, true)
        layer_add_queue.clear()

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
            var size: float = d.get(&'size')

            _draw_text(coords, string, color, size)
        elif d.type == TYPE.SPHERE:
            var coords: Vector3 = d.get(&'pos')
            var radius: float = d.get(&'r')
            var color: Color = d.get(&'color')

            _draw_sphere(coords, radius, color)
        elif d.type == TYPE.CIRCLE:
            var coords: Vector3 = d.get(&'pos')
            var radius: float = d.get(&'r')
            var axis: Vector3 = d.get(&'axis')
            var points: int = d.get(&'points')
            var color: Color = d.get(&'color')

            _draw_circle(coords, radius, axis, points, color)
        elif d.type == TYPE.POLYLINE:
            var poly: PackedVector3Array = d.get(&'poly')
            var color: Color = d.get(&'color')
            var points: bool = d.get(&'points')

            _draw_polyline(poly, color, points)
        else:
            push_error('DebugDraw: Unknown type id %d!' % d.type)
            items.erase(k)


## Helper, adds a new canvas layer sibling to DebugDraw, and returns it by name.
## If you plan to reuse the layer, consider saving to a static variable.
func get_layer(layer_name: StringName) -> CanvasLayer:
    if not layers.has(layer_name):
        var layer: CanvasLayer = CanvasLayer.new()
        layer.name = layer_name
        layers.set(layer_name, layer)
        if get_parent().is_node_ready():
            add_sibling(layer, true)
        else:
            layer_add_queue.append(layer)
    return layers.get(layer_name)

func text(coordinates: Vector3, string: String, color: Color, size: float = 16.0, id: int = 0, time: float = 0.0) -> int:
    var d: Dictionary = {}
    id = _get_item(id, TYPE.TEXT, d)

    d.set(&'pos', coordinates)
    d.set(&'str', string)
    d.set(&'size', size)
    d.set(&'color', color)
    d.set(&'t', time)

    items.set(id, d)
    queue_redraw()
    return id

func _draw_text(pos: Vector3, string: String, color: Color, size: float) -> void:
    if is_zero_approx(size):
        return

    if not camera.is_position_in_frustum(pos):
        return

    size = minf(4.0 * size / maxf(1.0, pos.distance_to(camera.global_position)), size)
    if size < 0.5:
        return
    var text_size: int = roundi(size)

    var screen: Vector2 = camera.unproject_position(pos)
    draw_string(
            font,
            screen,
            string,
            HORIZONTAL_ALIGNMENT_CENTER,
            -1.0,
            text_size,
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

func sphere(coordinates: Vector3, radius: float, color: Color, id: int = 0, time: float = 0.0) -> int:
    var d: Dictionary = {}
    id = _get_item(id, TYPE.SPHERE, d)

    d.set(&'pos', coordinates)
    d.set(&'r', radius)
    d.set(&'color', color)
    d.set(&'t', time)

    items.set(id, d)
    queue_redraw()
    return id

func _draw_sphere(pos: Vector3, radius: float, color: Color) -> void:
    if is_zero_approx(radius):
        return

    _draw_circle(pos, radius, Vector3.UP, 18, color)
    _draw_circle(pos, radius, Vector3.FORWARD, 18, color)
    _draw_circle(pos, radius, Vector3.RIGHT, 18, color)

func circle(coordinates: Vector3, radius: float, axis: Vector3, points: int, color: Color, id: int = 0, time: float = 0.0) -> int:
    var d: Dictionary = {}
    id = _get_item(id, TYPE.CIRCLE, d)

    d.set(&'pos', coordinates)
    d.set(&'r', radius)
    d.set(&'axis', axis)
    d.set(&'points', points)
    d.set(&'color', color)
    d.set(&'t', time)

    items.set(id, d)
    queue_redraw()
    return id

func _draw_circle(pos: Vector3, radius: float, axis: Vector3, points: int, color: Color) -> void:
    var basis: Basis = Basis(axis, TAU / points)
    var vec: Vector3 = axis.cross(Vector3.ONE)
    if vec.is_zero_approx():
        vec = axis.cross(Vector3.FORWARD)
    vec = vec.normalized()

    var line_data: PackedVector3Array
    line_data.resize(points + 1)
    var index: int = 0
    for i in range(points + 1):
        line_data[i] = pos + vec * radius
        vec = basis * vec

    _draw_polyline(line_data, color)

func polyline(polygon: PackedVector3Array, draw_points: bool, color: Color, id: int = 0, time: float = 0.0) -> int:
    var d: Dictionary = {}
    id = _get_item(id, TYPE.POLYLINE, d)

    d.set(&'poly', polygon)
    d.set(&'color', color)
    d.set(&'points', draw_points)
    d.set(&'t', time)

    items.set(id, d)
    queue_redraw()
    return id

func _draw_polyline(polygon: PackedVector3Array, color: Color, draw_points: bool = false) -> void:
    var size: int = polygon.size()
    if size < 2:
        return

    const POINT_COLORS: PackedColorArray = [
        Color.LIGHT_CORAL,
        Color.PLUM,
        Color.MEDIUM_ORCHID,
        Color.SKY_BLUE,
        Color.CORNFLOWER_BLUE,
    ]

    var poly: PackedVector2Array
    poly.resize(size)
    var initial_point: Vector3
    var index: int = 0
    var is_in_frustum: bool = false

    var point_index: int = -1

    for point in polygon:

        point_index += 1
        if (
                draw_points

                # Skip last point if it overlaps the first point
                and (
                    point_index != size - 1 or (point - polygon[0]).length_squared() > 1e-4
                )

                # Ensure point is in front of the camera
                and (not camera.is_position_behind(point))
        ):
            var col: Color
            if point_index == 0:
                col = Color.WHITE
            else:
                col = POINT_COLORS[(point_index - 1) % POINT_COLORS.size()]

            draw_circle(
                    camera.unproject_position(point),
                    5.0,
                    col * Color(1.0, 1.0, 1.0, 0.5),
                    true,
                    1.0, true
            )

        var start_in_frustum: bool = is_in_frustum
        is_in_frustum = camera.is_position_in_frustum(point)

        if index == 0:
            initial_point = point
            index = 1
            continue

        if not start_in_frustum:
            assert(index == 1, 'Previously left the frustum without a draw+reset, bad!')

            var start: Vector3 = _clamp_to_frustum(initial_point, point)

            # No intersection, ignore and start at the next point
            if not start.is_finite():
                initial_point = point
                index = 1
                continue

            if is_in_frustum:
                poly[0] = camera.unproject_position(start)
                poly[1] = camera.unproject_position(point)

                index = 2
                initial_point = point
                continue

            var end: Vector3 = _clamp_to_frustum(point, initial_point)
            if end.is_finite():
                draw_line(
                    camera.unproject_position(start),
                    camera.unproject_position(end),
                    color,
                    1.0, true
                )

            # Reset for next
            index = 1
            initial_point = point

            continue

        if index == 1:
            assert(start_in_frustum, 'Must have handled bad start already!')
            poly[0] = camera.unproject_position(initial_point)

        # Save and continue to next point
        if is_in_frustum:
            poly[index] = camera.unproject_position(point)
            initial_point = point
            index += 1
            continue

        # Left the frustum, must draw up to this point
        # Exiting the region, draw up to this point
        var end: Vector3 = _clamp_to_frustum(point, initial_point)
        if end.is_finite():
            poly[index] = camera.unproject_position(end)
            draw_polyline(poly.slice(0, index + 1), color, 1.0, true)

        initial_point = point
        index = 1

    if index > 1:
        draw_polyline(poly.slice(0, index), color, 1.0, true)

## Calculates the first point in the frustum from start -> end. Returns INF if
## no intersection happens.
func _clamp_to_frustum(start: Vector3, end: Vector3) -> Vector3:
    return _intersect_planes(start, end, _get_outside_faces(start))

func _get_outside_faces(point: Vector3) -> Array[Plane]:
    var result: Array[Plane]
    result.resize(3)
    var count: int = 0
    for idx in range(len(frustum)):
        var face: Plane = frustum[idx]
        if face.is_point_over(point):
            result[count] = face
            count += 1
            if count >= 3:
                break
    result.resize(count)
    return result

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
