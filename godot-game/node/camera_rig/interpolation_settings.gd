## Camera target interpolation settings resource
extends Resource

## Time in seconds of the interpolation
var duration: float = 1.0

## Easing curve.
## See https://raw.githubusercontent.com/godotengine/godot-docs/master/img/ease_cheatsheet.png
var curve: float = -2.0

## If the interpolation should remember the local position on the previous
## target and track from there, as if a wire was connected between the old
## and new target on which the camera followed. With this disabled, the
## wire is effectively connected to the camera directly and pulls it in.
var track_previous: bool = false

## If the initial_global_xform should be applied before interpolation begins.
## Use this when the camera rig may have already moved before calling attach().
var enable_initial_xform: bool = false

## When enable_initial_xform is true, this global transform is applied at the
## start of interpolation. Use this when the camera rig may have already moved
## before calling attach().
var initial_global_xform: Transform3D = Transform3D.IDENTITY
