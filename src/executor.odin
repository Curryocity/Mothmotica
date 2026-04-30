package main

import "core:fmt"
import "core:math"

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
    case .Print:
        return "Error: print(...) not implemented yet", false
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

    case .Move:
        return "Error: move(...) not implemented yet", false

    case .XInv:
        return "Error: xinv(...) not implemented yet", false
    case .ZInv:
        return "Error: zinv(...) not implemented yet", false
    case .XZInv:
        return "Error: xzinv(...) not implemented yet", false
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

    case .Loop:
        return "Error: loop(...) not implemented yet", false
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
