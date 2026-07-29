extends Control


## A data series holding points, axis scales, and rendering parameters
class Series extends RefCounted:
    ## Chart bounds, represented as min-max X, then min-max Y.
    var scale: Vector4 = Vector4(-10.0, 10.0, -10.0, 10.0)

    ## Set to true to enable auto scaling, which recalculates the chart scale
    ## whenever the data is updated
    var auto_scale_x: bool = false
    var auto_scale_y: bool = false

    ## Color for rendering the series
    var color: Color

    ## Series data represented as x-y pairs
    var data: PackedVector2Array

    ## Name shown on charts
    var name: StringName

    ## Maximum data count, set to zero to disable limit
    var max_size: int = 0


    func calc_bounds() -> Vector4:
        var bounds: Vector4 = Vector4(INF, -INF, INF, -INF)
        for d in data:
            bounds.x = minf(bounds.x, d.x)
            bounds.y = maxf(bounds.y, d.x)
            bounds.z = minf(bounds.z, d.y)
            bounds.w = maxf(bounds.w, d.y)
        return bounds


static var PRESET_COLOR_LIST: PackedColorArray = [
    Color.DODGER_BLUE,
    Color.FIREBRICK,
    Color.DARK_GOLDENROD,
    Color.OLIVE_DRAB,
    Color.TEAL,
    Color.MEDIUM_ORCHID,
    Color.INDIGO,
    Color.FOREST_GREEN,
]


var font: Font
var series_list: Array[Series]
var _next_color: int = 0


func _init() -> void:
    series_list = []
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    font = SystemFont.new()
    font.font_names = ['monospace', 'mono']

func _draw() -> void:
    var legend_y: int = 10
    var legend_x: int = 10
    var box_size: int = 10
    var box_gap: int = 6
    var line_skip: int = font.get_height()
    var line_ascent: int = font.get_ascent()

    const TITLE_SIZE: int = 20
    draw_string(
        font,
        Vector2(legend_x, legend_y + font.get_ascent(TITLE_SIZE)),
        name,
        HORIZONTAL_ALIGNMENT_LEFT, -1, # Defaults
        TITLE_SIZE,
        Color.DARK_SLATE_GRAY
    )
    legend_y += font.get_height(TITLE_SIZE)

    var series_rect: Rect2 = Rect2(Vector2(0, 0), size)
    for series in series_list:
        draw_rect(
                Rect2(legend_x, legend_y + line_ascent - box_size, box_size, minf(box_size, line_ascent)),
                series.color
        )
        draw_string(
                font,
                Vector2(box_size + box_gap + legend_x, legend_y + line_ascent),
                series.name,
                HORIZONTAL_ALIGNMENT_LEFT, -1, 16, # Defaults
                series.color
        )
        _draw_series(series_rect, series)
        legend_y += line_skip


func create_series(
        series_name: StringName,
        series_scale: Vector4 = Vector4.INF,
        series_color: Color = Color(0, 0, 0, 0),
) -> int:
    var id: int = series_list.size()

    var series: Series = Series.new()
    series.name = series_name

    if series_scale.x == INF:
        series.scale.x = INF
        series.scale.y = -INF
        series.auto_scale_x = true
    else:
        series.scale.x = series_scale.x
        series.scale.y = series_scale.y

    if series_scale.z == INF:
        series.scale.z = INF
        series.scale.w = -INF
        series.auto_scale_y = true
    else:
        series.scale.z = series_scale.z
        series.scale.w = series_scale.w

    if series_color == Color(0, 0, 0, 0):
        series_color = PRESET_COLOR_LIST[_next_color]
        _next_color = (_next_color + 1) % PRESET_COLOR_LIST.size()
    series.color = series_color

    series_list.append(series)
    return id

## Set the maximum data count limit, use zero to disable the limit
func set_data_limit(series_id: int, limit: int) -> void:
    var series: Series = series_list[series_id]
    series.max_size = limit

## Simply adds a value to the series data, using the previous X+1
func insert(series_id: int, value: float) -> void:
    var series: Series = series_list[series_id]
    var x: float = 0
    var data_size: int = series.data.size()
    if data_size > 0:
        x = series.data[data_size - 1].x + 1
    series.data.append(Vector2(x, value))
    if series.max_size > 0 and data_size >= series.max_size:
        series.data = series.data.slice(-series.max_size)
        if series.auto_scale_x or series.auto_scale_y:
            var bounds: Vector4 = series.calc_bounds()
            if series.auto_scale_x:
                series.scale.x = bounds.x
                series.scale.y = bounds.y
            if series.auto_scale_y:
                series.scale.z = bounds.z
                series.scale.w = bounds.w
    else:
        if series.auto_scale_x:
            series.scale.x = minf(series.scale.x, x)
            series.scale.y = maxf(series.scale.y, x)
        if series.auto_scale_y:
            series.scale.z = minf(series.scale.z, value)
            series.scale.w = maxf(series.scale.w, value)
    queue_redraw()

## Helper to set the exact same domain and range scale for multiple series
func sync_scale(series_to_sync: PackedInt32Array) -> void:
    var combined_scale: Vector4 = Vector4.ZERO
    var is_first: bool = true

    for series_id in series_to_sync:
        if series_id < 0 or series_id >= series_list.size():
            continue

        var series: Series = series_list[series_id]
        if is_first:
            combined_scale = series.scale
            is_first = false
            continue

        combined_scale.x = minf(combined_scale.x, series.scale.x)
        combined_scale.y = maxf(combined_scale.y, series.scale.y)
        combined_scale.z = minf(combined_scale.z, series.scale.z)
        combined_scale.w = maxf(combined_scale.w, series.scale.w)

    for series_id in series_to_sync:
        if series_id < 0 or series_id >= series_list.size():
            continue

        var series: Series = series_list[series_id]
        series.scale = combined_scale
    queue_redraw()


static var SCALED_BOUNDS: PackedVector2Array = [
        Vector2(0, 0),
        Vector2(0, 1),
        Vector2(1, 1),
        Vector2(1, 0)
]
var POLYLINE: PackedVector2Array
func _draw_series(region: Rect2, series: Series) -> void:
    var last_scaled_point: Vector2
    var is_in_region: bool = false

    var bounds: Vector4 = series.scale
    var domain: float = bounds.y - bounds.x
    var range: float = bounds.w - bounds.z
    var data_size: int = series.data.size()

    if POLYLINE.size() < data_size:
        POLYLINE.resize(data_size * 1.5)

    var index: int = 0
    var point: Vector2
    var data_index: int = -1
    var scaled_point: Vector2
    var bounds_min: Vector2 = Vector2(bounds.x, bounds.z)
    var bounds_scale: Vector2 = Vector2(1.0 / domain, 1.0 / range)
    while data_index < data_size - 1:
        data_index += 1
        scaled_point = (series.data[data_index] - bounds_min) * bounds_scale
        scaled_point.y = 1.0 - scaled_point.y

        # First data point
        if index == 0:
            is_in_region = (
                        scaled_point.x >= 0.0 and scaled_point.x <= 1.0
                    and scaled_point.y >= 0.0 and scaled_point.y <= 1.0
            )
            if is_in_region:
                POLYLINE[index] = region.size * scaled_point + region.position
            else:
                # Will be scaled later
                POLYLINE[index] = scaled_point
            index = 1
            last_scaled_point = scaled_point
            continue

        var start_in_region: bool = is_in_region
        is_in_region = (
                    scaled_point.x >= 0.0 and scaled_point.x <= 1.0
                and scaled_point.y >= 0.0 and scaled_point.y <= 1.0
        )

        # Special case, must clamp start point or update to be new point if no
        # crossing happens
        var start: Vector2 = last_scaled_point
        last_scaled_point = scaled_point
        if start_in_region:
            # Save and continue to next point
            if is_in_region:
                POLYLINE[index] = region.size * scaled_point + region.position
                index += 1
                continue

            # Exiting the region, draw up to this point
            var end: Vector2 = scaled_point
            for i in range(4):
                var crossing = Geometry2D.segment_intersects_segment(
                    start, end, SCALED_BOUNDS[i], SCALED_BOUNDS[(i + 1) % 4]
                )

                if crossing == null:
                    continue

                POLYLINE[index] = region.size * crossing + region.position
                draw_polyline(POLYLINE.slice(0, index + 1), series.color, 1.0, true)
                break

            POLYLINE[0] = end
            index = 1
            continue

        assert(index == 1, 'Previously left the region without a draw+reset, bad!')

        if is_in_region:
            # Entered region, find intersection of starting point
            var found_intersection: bool = false
            for i in range(4):
                var crossing = Geometry2D.segment_intersects_segment(
                    start, scaled_point, SCALED_BOUNDS[i], SCALED_BOUNDS[(i + 1) % 4]
                )

                if crossing == null:
                    continue

                # Less than 1px at 1920 resolution, skip it
                if (crossing - scaled_point).length_squared() < 2.5e-7:
                    break

                # Found good intersection, save and continue
                found_intersection = true
                POLYLINE[0] = region.size * crossing + region.position
                POLYLINE[1] = region.size * scaled_point + region.position
                index = 2
                break

            # Start at this point instead
            if not found_intersection:
                POLYLINE[0] = region.size * scaled_point + region.position
                index = 1

            continue

        # Check if the line has two intersections. This is a case where
        # we either draw one detached line or skip this segment.
        var first_intersection: Variant = null
        for i in range(4):
            var crossing = Geometry2D.segment_intersects_segment(
                start, scaled_point, SCALED_BOUNDS[i], SCALED_BOUNDS[(i + 1) % 4]
            )

            if crossing == null:
                continue

            if first_intersection == null:
                first_intersection = crossing
                continue

            # Less than 1px at 1920 resolution
            if (first_intersection - crossing).length_squared() < 2.5e-7:
                break

            # Crosses at two points
            draw_line(
                region.size * first_intersection + region.position,
                region.size * crossing + region.position,
                series.color, 1.0, true
            )
            break

        POLYLINE[0] = scaled_point
        index = 1

    if index > 1:
        draw_polyline(POLYLINE.slice(0, index), series.color)
