## Handles input context switching and mouse capture
extends Node


var input_global_context: GUIDEMappingContext = preload("uid://d03wntb6hv3sf")
var input_action_pause: GUIDEAction = preload("uid://djvqcq1sg55wm")
var input_action_speed: GUIDEAction = preload("uid://c8lqf68owbwtc")


## If the mouse is currently within the game window
var mouse_in_window: bool = false

## If the mouse cursor should be visible, enable this when showing UI elements
var show_cursor: bool = false

## If the mouse should be captured the next time it enters the window
var capture_mouse_on_enter: bool = false

## If the game scene should pause when the mouse exits the window
var allow_pause_on_exit: bool = true


func _ready() -> void:
    GUIDE.enable_mapping_context(input_global_context)

    var root := get_tree().root
    root.mouse_entered.connect(on_mouse_entered)
    root.mouse_exited.connect(on_mouse_exited)
    root.focus_entered.connect(on_focus_entered)
    root.focus_exited.connect(on_focus_exited)

    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
    if input_action_pause.is_triggered():
        if is_paused():
            unpause()
        else:
            pause()

    if input_action_speed.is_triggered():
        print('Time scale: %.4f' % input_action_speed.value_axis_1d)
        Engine.time_scale = clampf(input_action_speed.value_axis_1d, 0.25, 1.0)


func on_mouse_entered() -> void:
    mouse_in_window = true

    if capture_mouse_on_enter:
        capture_mouse_on_enter = false
        capture_mouse()

func on_mouse_exited() -> void:
    mouse_in_window = false

    # Ensure this method is called
    on_focus_exited()

func on_focus_entered() -> void:
    if capture_mouse_on_enter:
        capture_mouse_on_enter = false
        capture_mouse()

func on_focus_exited() -> void:
    # If we are captured, free the mouse and queue a recapture
    # This can happen if another window pulls focus or the mouse otherwise
    # just teleports outside the window
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        capture_mouse_on_enter = true

        # Also pause, just a nice thing to do
        if allow_pause_on_exit:
            pause()

func capture_mouse() -> void:
    if show_cursor or not mouse_in_window:
        return

    # Check that we are not hovering a mouse intercepting GUI element
    var gui: Control = get_tree().root.gui_get_hovered_control()
    while gui:
        if gui.mouse_filter == Control.MOUSE_FILTER_STOP:
            return
        elif gui.mouse_filter == Control.MOUSE_FILTER_PASS:
            gui = gui.get_parent() as Control
        break

    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    mouse_in_window = true

## Pause the game
func pause() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    get_tree().paused = true

## Unpauses the game, capturing the mouse if needed
func unpause() -> void:
    if not show_cursor:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    get_tree().paused = false

## Check if the game is paused
func is_paused() -> bool:
    return get_tree().paused
