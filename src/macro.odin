package main

MacroTick :: struct {
    w: bool,
    a: bool,
    s: bool,
    d: bool,
    jump: bool,
    sprint: bool,
    sneak: bool,
    rotation: f32,
}

Macro :: struct {
    ticks: [dynamic]MacroTick,
}

recordMacroTick :: proc(
    macro: ^Macro,
    forward, strafe: f32,
    jump, sprint, sneak: bool,
    rotation: f32,
) {
    append(&macro.ticks, MacroTick{
        w = forward > 0,
        a = strafe > 0,
        s = forward < 0,
        d = strafe < 0,
        jump = jump,
        sprint = sprint,
        sneak = sneak,
        rotation = rotation,
    })
}
