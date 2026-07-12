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
