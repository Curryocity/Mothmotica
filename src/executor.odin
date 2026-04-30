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
        case "getx", "getz", "getvx", "getvz", "getf":
            return "Error: cannot assign to pseudo variable", false
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
        setX(p, x)
        return "", true

    case .SetZ:
        msg, argsOK := expectPlainArgs(cmd, "z(...)", 1, 1)
        if !argsOK do return msg, false

        z, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: z(...) argument is not a valid number"), false
        setZ(p, z)
        return "", true

    case .SetPos:
        msg, argsOK := expectPlainArgs(cmd, "pos(...)", 2, 2)
        if !argsOK do return msg, false

        x, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return parserErrorOr(prs, "Error: first argument of pos(...) is not a valid number"), false

        z, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return parserErrorOr(prs, "Error: second argument of pos(...) is not a valid number"), false

        setX(p, x)
        setZ(p, z)
        return "", true

    case .SetVx, .SetVxAir:
        name := (cmd.type == .SetVxAir) ? "vxa(...)" : "vx(...)"
        msg, argsOK := expectPlainArgs(cmd, name, 1, 1)
        if !argsOK do return msg, false

        vx, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: vx(...) argument is not a valid number"), false

        airborne := (cmd.type == .SetVxAir)
        setVx(p, vx, airborne)
        return "", true

    case .SetVz, .SetVzAir:
        name := (cmd.type == .SetVzAir) ? "vza(...)" : "vz(...)"
        msg, argsOK := expectPlainArgs(cmd, name, 1, 1)
        if !argsOK do return msg, false

        vz, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: vz(...) argument is not a valid number"), false

        airborne := (cmd.type == .SetVzAir)
        setVz(p, vz, airborne)
        return "", true

    case .SetVel, .SetVelAir:
        name := (cmd.type == .SetVelAir) ? "vela(...)" : "vel(...)"
        msg, argsOK := expectPlainArgs(cmd, name, 2, 2)
        if !argsOK do return msg, false

        vx, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return parserErrorOr(prs, "Error: first argument of vel(...) is not a valid number"), false

        vz, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return parserErrorOr(prs, "Error: second argument of vel(...) is not a valid number"), false

        airborne := (cmd.type == .SetVelAir)
        setVel(p, vx, vz, airborne)
        return "", true

    case .SetF:
        msg, argsOK := expectPlainArgs(cmd, "f(...)", 1, 1)
        if !argsOK do return msg, false

        f, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: f(...) argument is not a valid number"), false
        setF(p, f32(f))
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

    case .OutVx:
        msg, argsOK := expectPlainArgs(cmd, "outvx(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "Vx", p.vx, cmd.args[:], "outvx")

    case .OutVz:
        msg, argsOK := expectPlainArgs(cmd, "outvz(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "Vz", p.vz, cmd.args[:], "outvz")

    case .OutF:
        msg, argsOK := expectPlainArgs(cmd, "outf(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "F", f64(p.f), cmd.args[:], "outf")

    case .OutTurn:
        msg, argsOK := expectPlainArgs(cmd, "outt(...)", 0, 1)
        if !argsOK do return msg, false
        return formatOutValue(prs, p, "T", f64(p.f), cmd.args[:], "outt")

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
                return "Error: slow(...) argument should be an integer between 0 and 255", false
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

    case .XInv:
        msg, argsOK := expectCodeArgs(cmd, "xinv(...){}", 1, 1)
        if !argsOK do return msg, false

        tarX, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: xinv(...){} argument is not a valid number"), false

        // Original Mothball doesn't reset x, but I think it is less confusing that way
        p.x = 0
        ss := saveState(p^)
        prs_ss := cloneParserState(prs)
        defer delete(prs_ss.vars)

        // inertia is off for successful lerping
        p.inertia_on = false
        p.vx = 0
        output, simOk := exeCode(prs, p, cmd.code[:], true)
        if !simOk do return output, false
        x0 := p.x

        loadState(p, ss)
        loadParserState(prs, prs_ss)
        p.inertia_on = false
        p.vx = 1
        output, simOk = exeCode(prs, p, cmd.code[:], true)
        if !simOk do return output, false
        x1 := p.x

        if abs(x1 - x0) < 1e-15 {
            loadParserState(prs, prs_ss)
            return "Cannot interpolate xinv because the two simulated samples are identical.", false
        }

        // tarX = tarVx * (x1 - x0) + x0
        tarVx := (tarX - x0)/(x1 - x0) 

        // doesn't disable inertia in the final real simulation
        loadState(p, ss)
        loadParserState(prs, prs_ss)
        p.vx = tarVx
        output, simOk = exeCode(prs, p, cmd.code[:], false)
        if !simOk do return output, false

        buf: [dynamic]u8
        defer delete(buf)

        append(&buf, fmt.tprintf("Lerped Vx: %s\n", formatNum(prs, tarVx)))
        append(&buf, output)

        return strings.clone(string(buf[:])), true
    case .ZInv:
        msg, argsOK := expectCodeArgs(cmd, "zinv(...){}", 1, 1)
        if !argsOK do return msg, false

        tarZ, ok := eval(prs, p, cmd.args[0])
        if !ok do return parserErrorOr(prs, "Error: zinv(...){} argument is not a valid number"), false

        // Original Mothball doesn't reset z, but I think it is less confusing that way
        p.z = 0
        ss := saveState(p^)
        prs_ss := cloneParserState(prs)
        defer delete(prs_ss.vars)

        // inertia is off for successful lerping
        p.inertia_on = false
        p.vz = 0
        output, simOk := exeCode(prs, p, cmd.code[:], true)
        if !simOk do return output, false
        z0 := p.z

        loadState(p, ss)
        loadParserState(prs, prs_ss)
        p.inertia_on = false
        p.vz = 1
        output, simOk = exeCode(prs, p, cmd.code[:], true)
        if !simOk do return output, false
        z1 := p.z

        if abs(z1 - z0) < 1e-15 {
            loadParserState(prs, prs_ss)
            return "Cannot interpolate zinv because the two simulated samples are identical.", false
        }

        // tarZ = tarVz * (z1 - z0) + z0
        tarVz := (tarZ - z0)/(z1 - z0) 

        // doesn't disable inertia in the final real simulation
        loadState(p, ss)
        loadParserState(prs, prs_ss)
        p.vz = tarVz
        output, simOk = exeCode(prs, p, cmd.code[:], false)
        if !simOk do return output, false

        buf: [dynamic]u8
        defer delete(buf)

        append(&buf, fmt.tprintf("Lerped Vz: %s\n", formatNum(prs, tarVz)))
        append(&buf, output)

        return strings.clone(string(buf[:])), true

    case .XZInv:
        msg, argsOK := expectCodeArgs(cmd, "xzinv(...){}", 2, 2)
        if !argsOK do return msg, false

        tarX, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return parserErrorOr(prs, "Error: xzinv(...){} argument is not a valid number"), false

        tarZ, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return parserErrorOr(prs, "Error: xzinv(...){} argument is not a valid number"), false

        // Original Mothball doesn't reset position, but I think it is less confusing that way
        p.x, p.z = 0, 0
        ss := saveState(p^)
        prs_ss := cloneParserState(prs)
        defer delete(prs_ss.vars)

        // inertia is off for successful lerping
        p.inertia_on = false
        p.vx, p.vz = 0, 0
        output, simOk := exeCode(prs, p, cmd.code[:], true)
        if !simOk do return output, false
        x0, z0 := p.x, p.z

        loadState(p, ss)
        loadParserState(prs, prs_ss)
        p.inertia_on = false
        p.vx, p.vz = 1, 1
        output, simOk = exeCode(prs, p, cmd.code[:], true)
        if !simOk do return output, false
        x1, z1 := p.x, p.z

        if abs(x1 - x0) < 1e-15 {
            loadParserState(prs, prs_ss)
            return "Cannot interpolate xzinv because the two simulated samples are identical on X.", false
        }
        if abs(z1 - z0) < 1e-15 {
            loadParserState(prs, prs_ss)
            return "Cannot interpolate xzinv because the two simulated samples are identical on Z.", false
        }

        tarVx := (tarX - x0)/(x1 - x0) 
        tarVz := (tarZ - z0)/(z1 - z0) 

        // doesn't disable inertia in the final real simulation
        loadState(p, ss)
        loadParserState(prs, prs_ss)
        p.vx, p.vz = tarVx, tarVz
        output, simOk = exeCode(prs, p, cmd.code[:], false)
        if !simOk do return output, false

        buf: [dynamic]u8
        defer delete(buf)

        append(&buf, fmt.tprintf("Lerped Vx: %s\n", formatNum(prs, tarVx)))
        append(&buf, fmt.tprintf("Lerped Vz: %s\n", formatNum(prs, tarVz)))
        append(&buf, output)

        return strings.clone(string(buf[:])), true

    case .VxInv:
        return "Error: vxinv(...) not implemented yet", false
    case .VzInv:
        return "Error: vzinv(...) not implemented yet", false
    case .VxzInv:
        return "Error: vxzinv(...) not implemented yet", false

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
        return "Error: anglequeue(...) not implemented yet", false
    case .TurnQueue:
        return "Error: turnqueue(...) not implemented yet", false

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
            pendingOutput, codeOK := exeCode(prs, p, cmd.code[:], false)
            if !codeOK do return pendingOutput, false

            if pendingOutput != "" {
                append(&buf, pendingOutput)
                append(&buf, "\n")
            }
            times -= 1
        }

        return strings.clone(string(buf[:])), true

    case .Define:
        return "Error: define(...) not implemented yet", false
    case .Save:
        return "Error: save(...) not implemented yet", false
    case .Load:
        return "Error: load(...) not implemented yet", false
    case .XPoss:
        return "Error: xposs(...) not implemented yet", false
    case .ZPoss:
        return "Error: zposs(...) not implemented yet", false

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
        pendingOutput, ok := exeArg(prs, p, arg)
        if !ok do return pendingOutput, false

        if !silent && pendingOutput != "" {
            append(&buf, pendingOutput)
            append(&buf, "\n")
        }
    }

    if silent do return "", true
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
    case:
        return ""
    }
}

eval :: proc(prs: ^ParserState, p: ^Player, expr: Arg) -> (f64, bool) {
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
        }else if cmd.type == .Abs ||cmd.type == .Sqrt || cmd.type == .Sin || cmd.type == .Cos || cmd.type == .Tan || cmd.type == .Atan {
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

    originalF := p.f
    localF := mf.rotUsed? mf.rot : originalF

    p.f = localF

    if mf.strafe45 {
        if mf.jump {
            // jump tick
            if mf.sprint { // sprint jump at f0
                move(p, 1, 0, false, mf.sprint, mf.sneak, true)
            }else {
                p.f = localF + 45
                move(p, 1, 1, false, mf.sprint, mf.sneak, true)
            } // add support for snsj45 angle
            
            p.f = localF + 45
            for _ in 0..<(mf.t - 1) {
                // air ticks
                move(p, 1, 1, true, mf.sprint, mf.sneak, false)
            }
        }else {
            p.f = localF + 45
            for _ in 0..<mf.t {
                move(p, 1, 1, mf.airborne, mf.sprint, mf.sneak, false)
            }
        }
    }else {
        if mf.jump {
            // jump tick
            move(p, mf.w, mf.a, false, mf.sprint, mf.sneak, true)
            for _ in 0..<(mf.t - 1) {
                // air ticks
                move(p, mf.w, mf.a, true, mf.sprint, mf.sneak, false)
            }
        }else {
            for _ in 0..<mf.t {
                move(p, mf.w, mf.a, mf.airborne, mf.sprint, mf.sneak, false)
            }
        }
    }

    p.f = originalF
}
