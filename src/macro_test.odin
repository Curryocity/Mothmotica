package main

import "core:testing"

@(test)
test_macro_serializers :: proc(t: ^testing.T) {
    macro := Macro{}
    defer delete(macro.ticks)

    append(&macro.ticks,
        MacroTick{w = true, jump = true, sneak = true, rotation = 90},
        MacroTick{d = true, sprint = true, rotation = 45},
    )

    mpk := serializeMacro(macro, .Mpk)
    defer delete(mpk)
    testing.expect_value(
        t,
        mpk,
        "X,Y,Z,YAW,PITCH,ANGLE_X,ANGLE_Y,W,A,S,D,SPRINT,SNEAK,JUMP,LMB,RMB,VEL_X,VEL_Y,VEL_Z\n" +
        "0.0,0.0,0.0,0.0,0.0,0,0.0,true,false,false,false,false,true,true,false,false,0.0,0.0,0.0\n" +
        "0.0,0.0,0.0,0.0,0.0,-45,0.0,false,false,false,true,true,false,false,false,false,0.0,0.0,0.0",
    )

    cyv := serializeMacro(macro, .Cyv)
    defer delete(cyv)
    testing.expect_value(
        t,
        cyv,
        "[\n" +
        "[\"true\", \"false\", \"false\", \"false\", \"true\", \"false\", \"true\", \"0\", \"0.0\"],\n" +
        "[\"false\", \"false\", \"false\", \"true\", \"false\", \"true\", \"false\", \"-45\", \"0.0\"]\n" +
        "]",
    )
}

@(test)
test_parse_result_includes_macro :: proc(t: ^testing.T) {
    bake_trig()

    result := parseMothballResult(";s w(2)")
    defer deleteParseResult(&result)

    testing.expect_value(t, result.ok, true)
    testing.expect_value(t, result.ctx, MothCtx.XZsim)
    testing.expect_value(t, len(result.macro.ticks), 2)
    testing.expect_value(t, result.macro.ticks[0].w, true)
    testing.expect_value(t, result.macro.ticks[1].w, true)

    failed := parseMothballResult(";s w(2) not_a_command")
    defer deleteParseResult(&failed)

    testing.expect_value(t, failed.ok, false)
    testing.expect_value(t, failed.ctx, MothCtx.XZsim)
    testing.expect_value(t, len(failed.macro.ticks), 0)
}
