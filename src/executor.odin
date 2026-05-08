package main

import "core:fmt"
import "core:math"
import "core:strings"

exeArg :: proc(prs: ^ParserState, p: ^Player, arg: Arg) -> (string, bool) {
    switch arg.type {
    case .Call:
        return exeCommand(prs, p, arg.expr)

    case .MoveCall:
        exeMoveFunc(p, arg.mvfunc)
        return "", true

    case .Number:
        return "Error: expected a command, got number", false
    case .Text:
        return "Error: expected a command, got text", false
    case .Variable:
        return fmt.tprintf("Error: expected a command, got variable '%s'", arg.text), false
    case:
        return "Error: expected a command", false
    }
}

exeCommand :: proc(prs: ^ParserState, p: ^Player, cmd: ^Command) -> (string, bool) {
    if cmd == nil do return "Error: null command", false

    hitbox := widenf32(0.6)

    switch cmd.type {
    case .Print, .Printn:
        msg, argsOK := expectPlainArgs(cmd, "print(...) or printn(...)", 1, 65536)
        if !argsOK do return msg, false

        buf: [dynamic]u8
        defer delete(buf)

        for arg, i in cmd.args {
            s, ok := argToString(prs, p, arg)
            if !ok do return s, false

            if i > 0 && cmd.type != .Printn{
                append(&buf, " ")
            }

            append(&buf, s)
        }

        return strings.clone(string(buf[:])), true

    case .Measure:
        msg, argsOK := expectPlainArgs(cmd, "measure(...)", 1, 65536)
        if !argsOK do return msg, false

        names: [dynamic]u8
        values: [dynamic]u8
        defer delete(names)
        defer delete(values)

        for arg, i in cmd.args {
            name, value, ok := measureArgValue(prs, p, arg)
            if !ok do return name, false

            if i > 0 {
                append(&names, ", ")
                append(&values, ", ")
            }

            append(&names, name)
            append(&values, formatNum(prs, value))
        }

        return fmt.tprintf(
            "(%s) = (%s)",
            string(names[:]),
            string(values[:]),
        ), true

    case .SetVar:
        msg, argsOK := expectPlainArgs(cmd, "set(...)", 2, 2)
        if !argsOK do return msg, false

        target := cmd.args[0]
        if target.type != .Variable {
            return "Error: first argument of set(...) must be a variable", false
        }

        switch target.text {
        case "getx", "getz", "getvx", "getvz", "getf", "getig", "getia":
            return "Error: cannot assign to pseudo variable", false
        case "bx", "px", "pi":
            return "Error: cannot assign to built-in constant", false
        }

        value, ok := eval(prs, p, cmd.args[1])
        if !ok {
            return parserErrorOr(prs, "Error: second argument of set(...) is not a valid number"), false
        }

        prs.vars[target.text] = value
        return "", true

    case .SetPrecision:
        msg, argsOK := expectPlainArgs(cmd, "pre(...)", 1, 1)
        if !argsOK do return msg, false

        pre, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: pre(...) argument is not a valid number"), false
        if pre < 0 || pre > 255 {
            return "Error: pre(...) argument should be an integer between 0 and 255", false
        }

        rounded := math.round(pre)
        if math.abs(pre - rounded) > 1e-15 {
            return "Error: pre(...) argument should be an integer between 0 and 255", false
        }

        prs.precision = u8(rounded)
        return "", true

    case .SetX:
        msg, argsOK := expectPlainArgs(cmd, "x(...)", 1, 1)
        if !argsOK do return msg, false

        x, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: x(...) argument is not a valid number"), false
        p.x = x
        return "", true

    case .SetZ:
        msg, argsOK := expectPlainArgs(cmd, "z(...)", 1, 1)
        if !argsOK do return msg, false

        z, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: z(...) argument is not a valid number"), false
        p.z = z
        return "", true

    case .SetPos:
        msg, argsOK := expectPlainArgs(cmd, "pos(...)", 2, 2)
        if !argsOK do return msg, false

        x, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return parserErrorOr(prs, "Error: first argument of pos(...) is not a valid number"), false

        z, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return parserErrorOr(prs, "Error: second argument of pos(...) is not a valid number"), false

        p.x = x
        p.z = z
        return "", true

    case .SetVx:
        msg, argsOK := expectPlainArgs(cmd, "vx(...)", 1, 1)
        if !argsOK do return msg, false

        vx, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: vx(...) argument is not a valid number"), false

        p.vx = vx
        return "", true

    case .SetVz:
        msg, argsOK := expectPlainArgs(cmd, "vz(...)", 1, 1)
        if !argsOK do return msg, false

        vz, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: vz(...) argument is not a valid number"), false

        p.vz = vz
        return "", true

    case .SetVel:
        msg, argsOK := expectPlainArgs(cmd, "vel(...)", 2, 2)
        if !argsOK do return msg, false

        vx, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return parserErrorOr(prs, "Error: first argument of vel(...) is not a valid number"), false

        vz, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return parserErrorOr(prs, "Error: second argument of vel(...) is not a valid number"), false

        p.vx, p.vz = vx, vz

        return "", true

    case .SetF:
        msg, argsOK := expectPlainArgs(cmd, "f(...)", 1, 1)
        if !argsOK do return msg, false

        f, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: f(...) argument is not a valid number"), false
        p.f = f32(f)
        return "", true
    case .SetTurn:
        msg, argsOK := expectPlainArgs(cmd, "t(...)", 1, 1)
        if !argsOK do return msg, false

        t, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: t(...) argument is not a valid number"), false
        p.f += f32(t)
        return "", true

    case .ResetPos:
        msg, argsOK := expectPlainArgs(cmd, "|", 0, 0)
        if !argsOK do return msg, false
        p.x = 0
        p.z = 0
        return "", true

    case .ResetPosVel:
        msg, argsOK := expectPlainArgs(cmd, "||", 0, 0)
        if !argsOK do return msg, false
        p.x = 0
        p.z = 0
        p.vx = 0
        p.vz = 0
        return "", true

    case .OutXRaw:
        msg, argsOK := expectPlainArgs(cmd, "xr(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "X", p.x, cmd.args[:], "xr")

    case .OutXBlock:
        msg, argsOK := expectPlainArgs(cmd, "xb(...)", 0, 1)
        if !argsOK do return msg, false
        xb := (p.x >= 0) ? p.x + hitbox : p.x - hitbox
        return formatOutValue(prs, p, "Xb", xb, cmd.args[:], "xb")

    case .OutXMM:
        msg, argsOK := expectPlainArgs(cmd, "xmm(...)", 0, 1)
        if !argsOK do return msg, false
        if abs(p.x) < hitbox {
            return fmt.tprintf("Xmm? (X: %s)", formatNum(prs, p.x)), true
        }
        xmm := (p.x >= 0) ? p.x - hitbox : p.x + hitbox
        return formatOutValue(prs, p, "Xmm", xmm, cmd.args[:], "xmm")
    
    case .OutXLadder:
        msg, argsOK := expectPlainArgs(cmd, "xld(...)", 0, 1)
        if !argsOK do return msg, false
        xld := (p.x >= 0) ? p.x + hitbox/2 : p.x - hitbox/2
        return formatOutValue(prs, p, "Xld", xld, cmd.args[:], "xld")

    case .OutZRaw:
        msg, argsOK := expectPlainArgs(cmd, "zr(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "Z", p.z, cmd.args[:], "zr")

    case .OutZBlock:
        msg, argsOK := expectPlainArgs(cmd, "zb(...)", 0, 1)
        if !argsOK do return msg, false
        zb := (p.z >= 0) ? p.z + hitbox : p.z - hitbox
        return formatOutValue(prs, p, "Zb", zb, cmd.args[:], "zb")

    case .OutZMM:
        msg, argsOK := expectPlainArgs(cmd, "zmm(...)", 0, 1)
        if !argsOK do return msg, false
        if abs(p.z) < hitbox {
            return fmt.tprintf("Zmm? (Z: %s)", formatNum(prs, p.z)), true
        }
        zmm := (p.z >= 0) ? p.z - hitbox : p.z + hitbox
        return formatOutValue(prs, p, "Zmm", zmm, cmd.args[:], "zmm")

    case .OutZLadder:
        msg, argsOK := expectPlainArgs(cmd, "zld(...)", 0, 1)
        if !argsOK do return msg, false
        zld := (p.z >= 0) ? p.z + hitbox/2 : p.z - hitbox/2
        return formatOutValue(prs, p, "Zld", zld, cmd.args[:], "zld")

    case .OutVx:
        msg, argsOK := expectPlainArgs(cmd, "outvx(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "Vx", p.vx, cmd.args[:], "outvx")

    case .OutVz:
        msg, argsOK := expectPlainArgs(cmd, "outvz(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "Vz", p.vz, cmd.args[:], "outvz")

    case .OutVec:
        msg, argsOK := expectPlainArgs(cmd, "vec", 0, 0)
        if !argsOK do return msg, false
        speed := math.sqrt(p.vx * p.vx + p.vz * p.vz)
        angle := math.atan2(p.vz, -p.vx) * 180 / PId
        return fmt.tprintf("(Speed/Angle) (%s, %s)", formatNum(prs, speed), formatNum(prs, angle)), true

    case .OutF:
        msg, argsOK := expectPlainArgs(cmd, "outf(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "F", f64(p.f), cmd.args[:], "outf")

    case .OutTurn:
        msg, argsOK := expectPlainArgs(cmd, "outt(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "T", f64(p.f), cmd.args[:], "outt")
    
    case .SetClock:
        msg, argsOK := expectPlainArgs(cmd, "clock(...)", 1, 1)
        if !argsOK do return msg, false

        slow, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: clock(...) argument is not a valid number"), false

        rounded := math.round(slow)
        if math.abs(slow - rounded) > 1e-15 {
            return "Error: clock(...) argument should be an integer", false
        }
        p.clock = int(rounded)

        return "", true
    
    case .OutClock:
        msg, argsOK := expectPlainArgs(cmd, "outclock(...)", 0, 0)
        if !argsOK do return msg, false
        return fmt.tprintf("Clock: %d",  p.clock), true

    case .SetSlip:
        msg, argsOK := expectPlainArgs(cmd, "slip(...)", 1, 1)
        if !argsOK do return msg, false

        slip, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: slip(...) argument is not a valid number"), false
        p.ground_slip = f32(slip)
        return "", true

    case .SetSprintDelay:
        msg, argsOK := expectPlainArgs(cmd, "sprintdelay(...)", 1, 1)
        if !argsOK do return msg, false

        v, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: sprintdelay(...) argument is not a valid number"), false
        p.sprint_delay = v != 0
        return "", true

    case .SetInertia:
        msg, argsOK := expectPlainArgs(cmd, "inertia(...)", 1, 1)
        if !argsOK do return msg, false

        inertia, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: inertia(...) argument is not a valid number"), false
        p.inertia_threshold = inertia
        return "", true

    case .SetSlow:
        msg, argsOK := expectPlainArgs(cmd, "slow(...)", 1, 1)
        if !argsOK do return msg, false

        slow, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: slow(...) argument is not a valid number"), false
        if slow < 0 || slow > 255 {
            return "Error: slow(...) argument should be an integer between 0 and 255", false
        }

        rounded := math.round(slow)
        if math.abs(slow - rounded) > 1e-15 {
            return "Error: slow(...) argument should be an integer between 0 and 255", false
        }

        p.slow = u8(rounded)
        return "", true

    case .SetSpeed:
        msg, argsOK := expectPlainArgs(cmd, "speed(...)", 1, 1)
        if !argsOK do return msg, false

        speed, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: speed(...) argument is not a valid number"), false
        if speed < 0 || speed > 255 {
            return "Error: speed(...) argument should be an integer between 0 and 255", false
        }

        rounded := math.round(speed)
        if math.abs(speed - rounded) > 1e-15 {
            return "Error: speed(...) argument should be an integer between 0 and 255", false
        }

        p.speed = u8(rounded)
        return "", true

    case .PrevGround:
        msg, argsOK := expectPlainArgs(cmd, "gnd", 0, 0)
        if !argsOK do return msg, false

        prevGround(p)
        return "", true
    
    case .PrevAir:
        msg, argsOK := expectPlainArgs(cmd, "air", 0, 0)
        if !argsOK do return msg, false

        prevAir(p)
        return "", true

    case .Move: // slip, accel, t, facing
        msg, argsOK := expectPlainArgs(cmd, "move(...)", 2, 4)
        if !argsOK do return msg, false

        slip, accel, facing: f64
        t: int
        ok: bool

        argCounts := len(cmd.args)

        slip, ok = eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: move(...)'s argument is not a valid number"), false

        accel, ok = eval(prs, p, cmd.args[1])
        if !ok do return parserErrorOr(prs, "Error: move(...)'s argument is not a valid number"), false

        if(argCounts >= 3){
            t_f64: f64
            t_f64, ok = eval(prs, p, cmd.args[2])
            if !ok do return parserErrorOr(prs, "Error: move(...)'s argument is not a valid number"), false

            rounded := math.round(t_f64)
            if math.abs(t_f64 - rounded) > 1e-15 {
                return "Error: move(...) argument should be an integer between 0 and 255", false
            }
            t = int(rounded)
        }else{
            t = 1
        }

        if(argCounts == 4){
            facing, ok = eval(prs, p, cmd.args[3])
            if !ok do return parserErrorOr(prs, "Error: move(...)'s argument is not a valid number"), false
        }else{
            facing = 0
        }

        sin_val := f64(sin(f32(facing)))
        cos_val := f64(cos(f32(facing)))

        for _ in 0..<t{
            p.x += p.vx
            p.z += p.vz

            p.vx *= slip
            p.vz *= slip

            if abs(p.vx) < p.inertia_threshold || p.forceInertiaX do p.vx = 0
            if abs(p.vz) < p.inertia_threshold || p.forceInertiaZ do p.vz = 0

            // only force for one tick
            p.forceInertiaX = false
            p.forceInertiaZ = false

            p.vx -= accel * sin_val
            p.vz += accel * cos_val
        }
        
        return "", true

    // This is loop with trailing st(x) bruh
    case .Taps:
        msg, argsOK := expectCodeArgs(cmd, "taps(...){}", 1, 1)

        times, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: taps(...){} argument is not a valid number"), false

        buf: [dynamic]u8
        defer delete(buf)

        for times > 0 {
            s, codeOK := exeCode(prs, p, cmd.code[:], false)
            if !codeOK do return s, false

            for p.vx != 0 || p.vz != 0 {
                move(p, 0, 0, false, false, false, false)
            }

            if s != "" {
                append(&buf, s)
                if s[len(s) - 1] != '\n'{
                    append(&buf, "\n")
                }
            }
            times -= 1
        }

        return strings.clone(string(buf[:])), true

    case .XInv:
        msg, argsOK := expectCodeArgs(cmd, "xinv(...){}", 1, 1)
        if !argsOK do return msg, false

        tarX, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: xinv(...){} argument is not a valid number"), false

        // Original Mothball doesn't reset x, but I think it is less confusing that way
        p.x = 0
        inv := saveInvState(prs, p)
        defer deleteInvState(&inv)

        output, simOk := invSample(prs, p, &inv, cmd.code[:], 0, inv.player.vz)
        if !simOk do return output, false
        x0 := p.x

        output, simOk = invSample(prs, p, &inv, cmd.code[:], 1, inv.player.vz)
        if !simOk do return output, false
        x1 := p.x

        if abs(x1 - x0) < 1e-15 {
            return "Cannot interpolate xinv because the two simulated samples are identical.", false
        }

        // tarX = tarVx * (x1 - x0) + x0
        tarVx := (tarX - x0)/(x1 - x0) 

        return finalInvSim(prs, p, &inv, cmd.code[:], tarVx, inv.player.vz, true, false)
    case .ZInv, .BWMM:
        cmdName := "zinv"
        if cmd.type == .BWMM {
            cmdName = "bwmm"
        }

        msg, argsOK := expectCodeArgs(cmd, fmt.tprintf("%s(...){}", cmdName), 1, 1)
        if !argsOK do return msg, false

        tarZ, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, fmt.tprintf("Error: %s(...){} argument is not a valid number", cmdName)), false
        if cmd.type == .BWMM {
            tarZ = offsetMM(tarZ)
        }

        // Original Mothball doesn't reset z, but I think it is less confusing that way
        p.z = 0
        inv := saveInvState(prs, p)
        defer deleteInvState(&inv)

        output, simOk := invSample(prs, p, &inv, cmd.code[:], inv.player.vx, 0)
        if !simOk do return output, false
        z0 := p.z

        output, simOk = invSample(prs, p, &inv, cmd.code[:], inv.player.vx, 1)
        if !simOk do return output, false
        z1 := p.z

        if abs(z1 - z0) < 1e-15 {
            return "Cannot interpolate zinv because the two simulated samples are identical.", false
        }

        // tarZ = tarVz * (z1 - z0) + z0
        tarVz := (tarZ - z0)/(z1 - z0) 

        return finalInvSim(prs, p, &inv, cmd.code[:], inv.player.vx, tarVz, false, true)

    case .XZInv:
        msg, argsOK := expectCodeArgs(cmd, "xzinv(...){}", 2, 2)
        if !argsOK do return msg, false

        tarX, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return parserErrorOr(prs, "Error: xzinv(...){} argument is not a valid number"), false

        tarZ, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return parserErrorOr(prs, "Error: xzinv(...){} argument is not a valid number"), false

        // Original Mothball doesn't reset position, but I think it is less confusing that way
        p.x, p.z = 0, 0
        inv := saveInvState(prs, p)
        defer deleteInvState(&inv)

        output, simOk := invSample(prs, p, &inv, cmd.code[:], 0, 0)
        if !simOk do return output, false
        x0, z0 := p.x, p.z

        output, simOk = invSample(prs, p, &inv, cmd.code[:], 1, 1)
        if !simOk do return output, false
        x1, z1 := p.x, p.z

        if abs(x1 - x0) < 1e-15 {
            return "Cannot interpolate xzinv because the two simulated samples are identical on X.", false
        }
        if abs(z1 - z0) < 1e-15 {
            return "Cannot interpolate xzinv because the two simulated samples are identical on Z.", false
        }

        tarVx := (tarX - x0)/(x1 - x0) 
        tarVz := (tarZ - z0)/(z1 - z0) 

        return finalInvSim(prs, p, &inv, cmd.code[:], tarVx, tarVz, true, true)

    case .VxInv:
        msg, argsOK := expectCodeArgs(cmd, "vxinv(...){}", 1, 1)
        if !argsOK do return msg, false

        tarVx, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: vxinv(...){} argument is not a valid number"), false

        inv := saveInvState(prs, p)
        defer deleteInvState(&inv)

        output, simOk := invSample(prs, p, &inv, cmd.code[:], 0, inv.player.vz)
        if !simOk do return output, false
        vx0 := p.vx

        output, simOk = invSample(prs, p, &inv, cmd.code[:], 1, inv.player.vz)
        if !simOk do return output, false
        vx1 := p.vx

        if abs(vx1 - vx0) < 1e-15 {
            return "Cannot interpolate vxinv because the two simulated samples are identical.", false
        }

        // tarVx = lerpedVx * (vx1 - vx0) + vx0
        lerpedVx := (tarVx - vx0)/(vx1 - vx0)

        return finalInvSim(prs, p, &inv, cmd.code[:], lerpedVx, inv.player.vz, true, false)
    case .VzInv:
        msg, argsOK := expectCodeArgs(cmd, "vzinv(...){}", 1, 1)
        if !argsOK do return msg, false

        tarVz, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: vzinv(...){} argument is not a valid number"), false

        inv := saveInvState(prs, p)
        defer deleteInvState(&inv)

        output, simOk := invSample(prs, p, &inv, cmd.code[:], inv.player.vx, 0)
        if !simOk do return output, false
        vz0 := p.vz

        output, simOk = invSample(prs, p, &inv, cmd.code[:], inv.player.vx, 1)
        if !simOk do return output, false
        vz1 := p.vz

        if abs(vz1 - vz0) < 1e-15 {
            return "Cannot interpolate vzinv because the two simulated samples are identical.", false
        }

        // tarVz = lerpedVz * (vz1 - vz0) + vz0
        lerpedVz := (tarVz - vz0)/(vz1 - vz0)

        return finalInvSim(prs, p, &inv, cmd.code[:], inv.player.vx, lerpedVz, false, true)
    case .VxzInv:
        msg, argsOK := expectCodeArgs(cmd, "vxzinv(...){}", 2, 2)
        if !argsOK do return msg, false

        tarVx, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return parserErrorOr(prs, "Error: vxzinv(...){} argument is not a valid number"), false

        tarVz, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return parserErrorOr(prs, "Error: vxzinv(...){} argument is not a valid number"), false

        inv := saveInvState(prs, p)
        defer deleteInvState(&inv)

        output, simOk := invSample(prs, p, &inv, cmd.code[:], 0, 0)
        if !simOk do return output, false
        vx0, vz0 := p.vx, p.vz

        output, simOk = invSample(prs, p, &inv, cmd.code[:], 1, 1)
        if !simOk do return output, false
        vx1, vz1 := p.vx, p.vz

        if abs(vx1 - vx0) < 1e-15 {
            return "Cannot interpolate vxzinv because the two simulated samples are identical on Vx.", false
        }
        if abs(vz1 - vz0) < 1e-15 {
            return "Cannot interpolate vxzinv because the two simulated samples are identical on Vz.", false
        }

        lerpedVx := (tarVx - vx0)/(vx1 - vx0)
        lerpedVz := (tarVz - vz0)/(vz1 - vz0)

        return finalInvSim(prs, p, &inv, cmd.code[:], lerpedVx, lerpedVz, true, true)

    case .ForceInertiaX:
        msg, argsOK := expectPlainArgs(cmd, "ix", 0, 0)
        if !argsOK do return msg, false
        p.forceInertiaX = true
        return "", true

    case .ForceInertiaZ:
        msg, argsOK := expectPlainArgs(cmd, "iz", 0, 0)
        if !argsOK do return msg, false
        p.forceInertiaZ = true
        return "", true

    case .AngleQueue:
        msg, argsOK := expectPlainArgs(cmd, "aq(...)", 1, 65536)
        if !argsOK do return msg, false

        idx := 0
        for arg in cmd.args {
            angle, ok := eval(prs, p, arg)
            if !ok do return parserErrorOr(prs, fmt.tprintf("Error: aq(...)'s argument[%d] is not a valid number", idx)), false
            qAdd(&p.angleQueue, f32(angle))
            idx += 1
        }

        return "", true
        
    case .TurnQueue:
        msg, argsOK := expectPlainArgs(cmd, "tq(...)", 1, 65536)
        if !argsOK do return msg, false

        idx := 0
        for arg in cmd.args {
            turn, ok := eval(prs, p, arg)
            if !ok do return parserErrorOr(prs, fmt.tprintf("Error: tq(...)'s argument[%d] is not a valid number", idx)), false
            qAdd(&p.turnQueue, f32(turn))
            idx += 1
        }

        return "", true

    case .XPoss, .ZPoss:
        msg, argsOK := expectCodeArgs(cmd, "(x/z)poss(...){...}", 0, 4)
        if !argsOK do return msg, false

        px :: 0.0625

        maxPoss := px
        offset := widenf32(0.6)
        maxMiss := 0.0
        has_miss := false
        tickOffset := 0

        if len(cmd.args) >= 1 {
            value, ok := eval(prs, p, cmd.args[0])
            if !ok do return parserErrorOr(prs, "Error: (x/z)poss(...) maxPoss is not a valid number"), false
            maxPoss = value
            if maxPoss > px || maxPoss < 0 {
                return fmt.tprintf("Error: (x/z)poss(...) maxPoss must be between 0 and 0.0625"), false
            }
        }

        if len(cmd.args) >= 2 {
            value, ok := eval(prs, p, cmd.args[1])
            if !ok do return parserErrorOr(prs, "Error: (x/z)poss(...) offset is not a valid number"), false
            offset = value
        }

        if len(cmd.args) >= 3 {
            value, ok := eval(prs, p, cmd.args[2])
            if !ok do return parserErrorOr(prs, "Error: (x/z)poss(...) maxMiss is not a valid number"), false
            maxMiss = value
            has_miss = true

            if maxMiss > px || maxMiss < 0{
                return fmt.tprintf("Error: (x/z)poss(...) maxMiss must be between 0 and 0.0625"), false
            }
        }

        if len(cmd.args) >= 4 {
            value, ok := eval(prs, p, cmd.args[3])
            if !ok do return parserErrorOr(prs, "Error: (x/z)poss(...) tick offset is not a valid number"), false

            rounded := math.round(value)
            if math.abs(value - rounded) > 1e-15 {
                return "Error: (x/z)poss(...) tick offset must be an integer", false
            }

            tickOffset = int(rounded)
        }

        buf: [dynamic]u8
        defer delete(buf)
        possBuf: [dynamic]u8
        defer delete(possBuf)

        old_posRec := p.posRec
        old_posStorage := p.posStorage

        p.posRec = true
        clearPosStorage(p)
        defer {
            clearPosStorage(p)
            p.posRec = old_posRec
            p.posStorage = old_posStorage
        }

        output, ok := exeCode(prs, p, cmd.code[:], false)
        if !ok do return output, false

        append(&buf, output)

        t := 1
        for pos in p.posStorage {

            axis := cmd.type == .XPoss? pos.x : pos.z
            if abs(axis) <= max(1e-15, -offset) {
                t += 1
                continue
            }

            sign := axis >= 0? f64(1) : f64(-1)
            dis := abs(axis) + offset
            jump :=  math.floor_f64(dis / px) * px
            made := dis - jump
            miss := px - made

            if made <= maxPoss {
                append(&possBuf, fmt.tprintf("t = %d: %s %s %s\n", t + tickOffset, formatNum(prs, sign * jump), (sign > 0)? "+" : "-", formatNum(prs, made)))
            } else if has_miss && miss <= maxMiss {
                next_jump := jump + px
                append(&possBuf, fmt.tprintf("t = %d: %s %s %s\n", t + tickOffset, formatNum(prs, sign * next_jump), (sign > 0)? "-" : "+", formatNum(prs, miss)))
            }

            t += 1
        }

        if len(possBuf) > 0 {
            if has_miss {
                append(
                    &buf,
                    fmt.tprintf(
                        "Poss: (t = %d...%d, thres = %s...%s)\n",
                        1 + tickOffset,
                        len(p.posStorage) + tickOffset,
                        formatNum(prs, -maxMiss),
                        formatNum(prs, maxPoss),
                    ),
                )
            } else {
                append(
                    &buf,
                    fmt.tprintf(
                        "Poss: (t = %d...%d, thres = %s)\n",
                        1 + tickOffset,
                        len(p.posStorage) + tickOffset,
                        formatNum(prs, maxPoss),
                    ),
                )
            }
            append(&buf, string(possBuf[:]))
        }

        return strings.clone(string(buf[:])), true

    case .Save:
        msg, argsOK := expectPlainArgs(cmd, "save(...)", 1, 1)
        if !argsOK do return msg, false

        nameArg := cmd.args[0]
        if nameArg.type != .Text {
            return "Error: save(...) name must be a double quoted string", false
        }

        if oldState, exists := prs.saves[nameArg.text]; exists {
            deletePlayerState(&oldState)
        }
        prs.saves[nameArg.text] = saveState(p^)
        return "", true

    case .Load:
        msg, ok := expectPlainArgs(cmd, "load(...)", 1, 1)
        if !ok do return msg, false

        nameArg := cmd.args[0]
        if nameArg.type != .Text {
            return "Error: load(...) name must be an identifier or string", false
        }

        state, exists := prs.saves[nameArg.text]
        if !exists {
            return fmt.tprintf("Error: no saved state named '%s'", nameArg.text), false
        }

        loadState(p, state)
        return "", true

    // r(x) repeats while x > 0, decrementing x by 1 each loop.
    // Non-integer x is intentionally allowed.
    case .Loop:
        msg, argsOK := expectCodeArgs(cmd, "r(...){...}", 1, 1)
        if !argsOK do return msg, false

        times, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: r(...) argument is not a valid number"), false

        buf: [dynamic]u8
        defer delete(buf)

        for times > 0 {
            s, codeOK := exeCode(prs, p, cmd.code[:], false)
            if !codeOK do return s, false

            if s != "" {
                append(&buf, s)
                if s[len(s) - 1] != '\n'{
                    append(&buf, "\n")
                }
            }
            times -= 1
        }

        return strings.clone(string(buf[:])), true

    case .Define:
        return "Error: define(...) not implemented yet", false

    case .Plus, .Minus, .Mul, .Div, .Abs, .Sqrt, .Sin, .Cos, .Tan, .Atan:
        return "Error: operator/computation call cannot be executed as a top-level statement", false

    case .Invalid:
        return "Error: invalid command", false

    case:
        return "Error: unhandled command", false
    }
}

exeCode :: proc(prs: ^ParserState, p: ^Player, code: []Arg, silent: bool) -> (string, bool) {
    buf: [dynamic]u8
    defer delete(buf)

    for arg in code {
        s, ok := exeArg(prs, p, arg)
        if !ok do return s, false

        if !silent && s != "" {
            append(&buf, s)
            if s[len(s) - 1] != '\n'{
                append(&buf, "\n")
            }
        }
    }

    if silent do return "", true
    return strings.clone(string(buf[:])), true
}

InvState :: struct {
    player: Player,
    parser: ParserState,
    posRec: bool,
}

saveInvState :: proc(prs: ^ParserState, p: ^Player) -> InvState {
    state := InvState{
        player = saveState(p^),
        parser = cloneParserState(prs),
        posRec = p.posRec,
    }
    p.posRec = false
    return state
}

deleteInvState :: proc(state: ^InvState) {
    deletePlayerState(&state.player)
    deleteParserState(&state.parser)
}

invSample :: proc(prs: ^ParserState, p: ^Player, state: ^InvState, code: []Arg, vx, vz: f64) -> (string, bool) {
    loadState(p, state.player)
    loadParserState(prs, state.parser)

    // Inverse samples avoid inertia and position recording so interpolation stays stable.
    p.inertia_on = false
    p.posRec = false
    p.vx, p.vz = vx, vz

    return exeCode(prs, p, code, true)
}

finalInvSim :: proc(prs: ^ParserState, p: ^Player, state: ^InvState, code: []Arg, vx, vz: f64, printVx, printVz: bool) -> (string, bool) {
    loadState(p, state.player)
    loadParserState(prs, state.parser)
    p.posRec = state.posRec
    p.vx, p.vz = vx, vz

    output, ok := exeCode(prs, p, code, false)
    if !ok do return output, false

    buf: [dynamic]u8
    defer delete(buf)

    if printVx do append(&buf, fmt.tprintf("Lerped Vx: %s\n", formatNum(prs, vx)))
    if printVz do append(&buf, fmt.tprintf("Lerped Vz: %s\n", formatNum(prs, vz)))
    append(&buf, output)

    return strings.clone(string(buf[:])), true
}

measureArgValue :: proc(prs: ^ParserState, p: ^Player, arg: Arg) -> (string, f64, bool) {
    hitbox := widenf32(0.6)

    #partial switch arg.type {
    case .Variable:
        value, ok := eval(prs, p, arg)
        if !ok do return parserErrorOr(prs, "Error: measure(...) argument cannot be evaluated"), 0, false
        return arg.text, value, true

    case .Call:
        if arg.expr == nil {
            return "Error: measure(...) argument is missing a command", 0, false
        }

        cmd := arg.expr
        if len(cmd.args) != 0 || len(cmd.code) != 0 {
            name := cmd.name
            if name == "" do name = "command"
            return fmt.tprintf("Error: measure(...) builtin '%s' must not have arguments or a code block", name), 0, false
        }

        name := cmd.name
        if name == "" do name = measureBuiltinDefaultName(cmd.type)

        #partial switch cmd.type {
        case .SetX:
            return name, p.x, true
        case .SetZ:
            return name, p.z, true
        case .SetF:
            return name, f64(p.f), true
        case .SetVx:
            return name, p.vx, true
        case .SetVz:
            return name, p.vz, true
        case .OutXBlock:
            value := (p.x >= 0) ? p.x + hitbox : p.x - hitbox
            return name, value, true
        case .OutZBlock:
            value := (p.z >= 0) ? p.z + hitbox : p.z - hitbox
            return name, value, true
        case .OutXMM:
            value := (p.x >= 0) ? p.x - hitbox : p.x + hitbox
            return name, value, true
        case .OutZMM:
            value := (p.z >= 0) ? p.z - hitbox : p.z + hitbox
            return name, value, true
        case .OutXLadder:
            value := (p.x >= 0) ? p.x + hitbox/2 : p.x - hitbox/2
            return name, value, true
        case .OutZLadder:
            value := (p.z >= 0) ? p.z + hitbox/2 : p.z - hitbox/2
            return name, value, true
        case:
            if name == "" do name = "command"
            return fmt.tprintf("Error: measure(...) cannot measure builtin '%s'", name), 0, false
        }

    case:
        return "Error: measure(...) arguments must be variables or builtin values", 0, false
    }
}

measureBuiltinDefaultName :: proc(type: CmdType) -> string {
    #partial switch type {
    case .SetX:
        return "x"
    case .SetZ:
        return "z"
    case .SetF:
        return "f"
    case .SetVx:
        return "vx"
    case .SetVz:
        return "vz"
    case .OutXBlock:
        return "xb"
    case .OutZBlock:
        return "zb"
    case .OutXMM:
        return "xmm"
    case .OutZMM:
        return "zmm"
    case .OutXLadder:
        return "xld"
    case .OutZLadder:
        return "zld"
    case:
        return ""
    }
}

offsetMM :: proc(x: f64) -> f64 {
    hitbox := widenf32(0.6)
    return x + ((x >= 0) ? hitbox : -hitbox)
}

offsetB :: proc(x: f64) -> f64 {
    hitbox := widenf32(0.6)
    return x + ((x >= 0) ? -hitbox : hitbox)
}

offsetLD :: proc(x: f64) -> f64 {
    hitbox := widenf32(0.6)
    return x + ((x >= 0) ? hitbox/2 : -hitbox/2)
}

applyArgModifier :: proc(value: f64, modifier: ArgModifier) -> f64 {
    switch modifier {
    case .MM:
        return offsetMM(value)
    case .B:
        return offsetB(value)
    case .LD:
        return offsetLD(value)
    case .None:
        return value
    }

    return value
}

eval :: proc(prs: ^ParserState, p: ^Player, expr: Arg) -> (f64, bool) {
    value, ok := evalRaw(prs, p, expr)
    if !ok do return 0, false
    return applyArgModifier(value, expr.modifier), true
}

evalRaw :: proc(prs: ^ParserState, p: ^Player, expr: Arg) -> (f64, bool) {
    switch expr.type {
    case .Number:
        return expr.value, true

    case .Text:
        failParse(prs, "Error: text values cannot be used as numbers")
        return 0, false

    case .MoveCall:
        failParse(prs, "Error: movement expressions cannot be used as numbers")
        return 0, false

    case .Variable:
        switch expr.text {
        case "getx":
            return p.x, true
        case "getz":
            return p.z, true
        case "getvx":
            return p.vx, true
        case "getvz":
            return p.vz, true
        case "getf":
            return f64(p.f), true
        case "getig":
            return p.inertia_threshold/f64(p.ground_slip)/0.91, true
        case "getia":
            return p.inertia_threshold/0.91, true
        case "getc", "getclock":
            return f64(p.clock), true
        case:
            value, ok := prs.vars[expr.text]
            if !ok{
                failParse(prs, fmt.tprintf("Error: unknown variable '%s'", expr.text))
                return 0, false
            } 
            return value, true
        }

    case .Call:
        if expr.expr == nil {
            failParse(prs, "Error: internal parser error: missing expression")
            return 0, false
        }

        cmd := expr.expr

        if cmd.type == .Plus || cmd.type == .Minus || cmd.type == .Mul || cmd.type == .Div{
            if len(cmd.args) != 2 {
                failParse(prs, "Error: expression operator is missing an operand")
                return 0, false
            }

            lhs, ok1 := eval(prs, p, cmd.args[0])
            if !ok1 do return 0, false

            rhs, ok2 := eval(prs, p, cmd.args[1])
            if !ok2 do return 0, false

            #partial switch cmd.type {
            case .Plus:
                return lhs + rhs, true
            case .Minus:
                return lhs - rhs, true
            case .Mul:
                return lhs * rhs, true
            case .Div:
                if rhs == 0 {
                    failParse(prs, "Error: division by zero")
                    return 0, false
                }
                return lhs / rhs, true
            case:
                failParse(prs, "Error: expression cannot be evaluated as a number")
                return 0, false
            }
        }else if cmd.type == .Abs || cmd.type == .Sqrt || cmd.type == .Sin || cmd.type == .Cos || cmd.type == .Tan || cmd.type == .Atan {
            if len(cmd.args) != 1 {
                failParse(prs, "Error: computing function should have exactly one parameter")
                return 0, false
            }

            arg, ok := eval(prs, p, cmd.args[0])
            if !ok do return 0, false

            #partial switch cmd.type {
                case .Sqrt:
                    if arg >= 0 {
                        return math.sqrt(arg), true
                    } else {
                        failParse(prs, "Error: Sqrt(...) cannot take in a negative number.")
                        return 0, false
                    }
                case .Sin:
                    rad := arg * PId/180
                    return math.sin(rad), true
                case .Cos:
                    rad := arg * PId/180
                    return math.cos(rad), true
                case .Tan:
                    rad := arg * PId/180
                    return math.tan(rad), true
                case .Atan:
                    rad := math.atan(arg)
                    return rad * 180/PId, true
                case .Abs:
                    return abs(arg), true
                case:
                    failParse(prs, "Error: expression cannot be evaluated as a number")
                    return 0, false
            }

        }

    case:
        failParse(prs, "Error: expression cannot be evaluated as a number")
        return 0, false
    }
    
    return 0, false
}

exeMoveFunc :: proc(p: ^Player, mf: MoveFunc){

    if mf.strafe45 {
        if mf.jump {
            // jump tick
            if mf.sprint { // sprint jump at f0
                move(p, 1, 0, false, mf.sprint, mf.sneak, true, mf.rot, mf.rotUsed)
            }else {
                move(p, 1, 1, false, mf.sprint, mf.sneak, true, mf.rot, mf.rotUsed, true)
            } // add support for snsj45 angle
            
            for _ in 0..<(mf.t - 1) {
                // air ticks
                move(p, 1, 1, true, mf.sprint, mf.sneak, false, mf.rot, mf.rotUsed, true)
            }
        }else {
            for _ in 0..<mf.t {
                move(p, 1, 1, mf.airborne, mf.sprint, mf.sneak, false, mf.rot, mf.rotUsed, true)
            }
        }
    }else {
        if mf.jump {
            // jump tick
            move(p, mf.w, mf.a, false, mf.sprint, mf.sneak, true, mf.rot, mf.rotUsed)
            for _ in 0..<(mf.t - 1) {
                // air ticks
                move(p, mf.w, mf.a, true, mf.sprint, mf.sneak, false, mf.rot, mf.rotUsed)
            }
        }else {
            for _ in 0..<mf.t {
                move(p, mf.w, mf.a, mf.airborne, mf.sprint, mf.sneak, false, mf.rot, mf.rotUsed)
            }
        }
    }

}
