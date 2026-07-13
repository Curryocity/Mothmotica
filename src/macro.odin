package main

import "core:fmt"
import "core:strings"

MacroType :: enum {
    Mpk,
    Cyv,
}

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

boolToString :: proc(value: bool) -> string {
    return value ? "true" : "false"
}

macroTurn :: proc(macro: Macro, tick_index: int) -> f32 {
    if tick_index == 0 do return 0
    return macro.ticks[tick_index].rotation - macro.ticks[tick_index - 1].rotation
}

makeMpkMacro :: proc(macro: Macro) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(
        &builder,
        "X,Y,Z,YAW,PITCH,ANGLE_X,ANGLE_Y,W,A,S,D,SPRINT,SNEAK,JUMP,LMB,RMB,VEL_X,VEL_Y,VEL_Z",
    )

    for tick, i in macro.ticks {
        fmt.sbprintf(
            &builder,
            "\n0.0,0.0,0.0,0.0,0.0,%v,0.0,%s,%s,%s,%s,%s,%s,%s,false,false,0.0,0.0,0.0",
            macroTurn(macro, i),
            boolToString(tick.w),
            boolToString(tick.a),
            boolToString(tick.s),
            boolToString(tick.d),
            boolToString(tick.sprint),
            boolToString(tick.sneak),
            boolToString(tick.jump),
        )
    }

    return strings.clone(strings.to_string(builder))
}

makeCyvMacro :: proc(macro: Macro) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "[")
    for tick, i in macro.ticks {
        separator := i == 0 ? "\n" : ",\n"
        fmt.sbprintf(
            &builder,
            "%s[\"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%s\", \"%v\", \"0.0\"]",
            separator,
            boolToString(tick.w),
            boolToString(tick.a),
            boolToString(tick.s),
            boolToString(tick.d),
            boolToString(tick.jump),
            boolToString(tick.sprint),
            boolToString(tick.sneak),
            macroTurn(macro, i),
        )
    }
    if len(macro.ticks) > 0 do strings.write_string(&builder, "\n")
    strings.write_string(&builder, "]")

    return strings.clone(strings.to_string(builder))
}

serializeMacro :: proc(macro: Macro, macro_type: MacroType) -> string {
    switch macro_type {
    case .Mpk:
        return makeMpkMacro(macro)
    case .Cyv:
        return makeCyvMacro(macro)
    }

    return ""
}
