class_name ForcePoint2D extends Marker2D

static var color_index: int = 0
static var colors: PackedColorArray = [
        Color(0.49803922, 1, 0.83137256),
        Color(1, 0.84313726, 0),
        Color(0.9607843, 0.9607843, 0.9607843),
        Color(0.9411765, 0.5019608, 0.5019608),
        Color(0.39215687, 0.58431375, 0.92941177),
        Color(0.93333334, 0.50980395, 0.93333334),
        Color(0.69803923, 0.13333334, 0.13333334),
        Color(0.5019608, 0.5019608, 0.5019608),
]


func _ready() -> void:
    var point := MeshInstance2D.new()

    var mesh := SphereMesh.new()
    mesh.radius = 5.0
    mesh.height = 10.0
    point.mesh = mesh

    var tex := GradientTexture1D.new()
    tex.width = 1
    tex.gradient = Gradient.new()
    tex.gradient.add_point(0.0, get_color())
    point.texture = tex

    add_child(point)

static func get_color() -> Color:
    var color := colors[color_index]
    color_index = (color_index + 1) % colors.size()
    return color
