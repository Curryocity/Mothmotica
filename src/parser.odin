package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:math"

ParserState :: struct {
    ctx: MothCtx,
    lex: Lexer,
    ok: bool,
    errMsg: string,
    vars: map[string]f64,
    saves: map[string]Player,
    precision: u8,
    printSep: string,
    yObserve: bool,
    silent: bool,
    macro: Macro,
	version: MCVersion,
}

MothCtx :: enum {
    XZsim, Ysim, ElytraSim, Invalid,
}

ParseResult :: struct {
    output: string,
    macro: Macro,
    ctx: MothCtx,
    ok: bool,
}

deleteParseResult :: proc(result: ^ParseResult) {
    delete(result.output)
    delete(result.macro.ticks)
    result^ = {}
}

MoveFunc :: struct {
    name: string,
    sprint: bool,
    sneak: bool,
    strafe45: bool,
    jump: bool,
    airborne: bool,
    stop: bool,
    w: f32,
    a: f32,
    t: int,
    rot: f32,
    rotUsed: bool,
}

CmdType :: enum {
    Plus, Minus, Mul, Div, 
    Abs, Min, Max, Sign, Sqrt, Floor, Ceil, Round, Sin, Cos, Tan, Atan, ArgAngle,

    Print, Println, SetPrintSep, SetSilent, Measure, Polar,

    SetX, SetZ, SetPos, 
    SetVz, SetVx, SetVel,
    ResetPos, ResetPosVel,

    OutXRaw, OutXBlock, OutXMM, OutXLadder,
    OutZRaw, OutZBlock, OutZMM, OutZLadder,
    OutGlobalX, OutGlobalY, OutGlobalZ,

    OutVx, OutVz, OutAngle, OutVec,

    SetF, OutF, SetTurn, OutTurn, Set45,

    SetTick, OutTick,

    Move, Taps,

    XPoss, ZPoss,

    XInv, ZInv, BWMM, XZInv,
    VxInv, VzInv, VxzInv,

    ForceInertiaX, ForceInertiaZ,

    SetPrecision, SetSlip, SetSprintDelay, SetSneakDelay, SetInertia, SetVersion,
    SetSlow, SetSpeed,

    PrevGround, PrevAir,

    AngleQueue, TurnQueue,

    Loop, SetVar, Define, Save, Load,

    // Y commands

    Coast, Jump, UpAction, DownAction, LadderHold,
    SetY, OutY, SetVy, OutVy, OutYTop,
    SetPlayerHeight, SetJumpBoost, SetSlowFall, SetYObserve,
    SetWeb, SetLadder, SetBlock, SetSoulSand,

    JumpTo, CoastTo, tier,

    // XYZ Elytra commands
    Elytra, ElytraJump, ElytraSprintJump, ElytraLand, SetPitch, OutPitch, PitchQueue,
    
    CeilQueue, SlimeQueue,

    Invalid,
}

Command :: struct {
    type: CmdType,
    name: string,
    args: [dynamic]Arg,
    code: [dynamic]Arg,
}

ArgType :: enum {
    Number, Text, Variable, Call, MoveCall
}

ArgModifier :: enum {
    None, MM, B, LD,
}

Arg :: struct {
    type: ArgType,
    modifier: ArgModifier,
    value: f64,
    text: string,
    expr: ^Command,
    mvfunc: MoveFunc,
}

ArgContext :: enum {
    Default,
    FuncArg,
    OffsetValue,
}

// ENTRY !!!!!
parseMothballResult :: proc(input: string) -> ParseResult {
    buf: [dynamic]u8
    defer delete(buf)

    prefix_len := 2
    if len(input) < prefix_len do return ParseResult{ctx = .Invalid}

    ctx: MothCtx
    switch input[:prefix_len] {
        case ";s":
            ctx = .XZsim
        case ";y":
            ctx = .Ysim
        case ";e":
            ctx = .ElytraSim
        case:
            return ParseResult{ctx = .Invalid}
    }

    prs := ParserState{
        ctx = ctx,
        lex = Lexer{
            data = input,
            pos = prefix_len,
            nextOk = false,
        },
        ok = true,
        errMsg = "",
        vars = make(map[string]f64),
        saves = make(map[string]Player),
        precision = 6,
        printSep = strings.clone(" "),
        yObserve = true,
        silent = false,
		version = default_mcversion(ctx),
    }
    defer deleteParserState(&prs)

    map_insert(&prs.vars, "bx", f64(f32(0.6)))
    map_insert(&prs.vars, "px", 0.0625)
    map_insert(&prs.vars, "pi", PId)

    p := makePlayer()
	apply_version_defaults(&p, prs.version)
    defer deletePlayerState(&p)

    for lexerPeek(&prs.lex).type != .EOF {
        cmd := parseArg(&prs, &p, 0, .Default)

        if !prs.ok {
            return ParseResult{
                output = strings.clone(fmt.tprintf("%s\n", prs.errMsg)),
                ctx = prs.ctx,
                ok = false,
            }
        }

        s, ok := exeArg(&prs, &p, cmd)
        if !ok {
            return ParseResult{
                output = strings.clone(fmt.tprintf("%s\n", s)),
                ctx = prs.ctx,
                ok = false,
            }
        }

        if(s != ""){
            append(&buf, s)
            if !isRawOutputArg(cmd) && s[len(s) - 1] != '\n'{
                append(&buf, "\n")
            }
        }
    }

    result := strings.clone(string(buf[:]))
    if result == "" {
        delete(result)
        result = strings.clone("ok\n")
    }

    return ParseResult{
        output = result,
        macro = cloneMacro(prs.macro),
        ctx = prs.ctx,
        ok = true,
    }
}

parseMothball :: proc(input: string) -> string {
    result := parseMothballResult(input)
    output := result.output
    result.output = ""
    deleteParseResult(&result)
    return output
}

parseArg :: proc(prs: ^ParserState, p: ^Player, minBP: int, argCtx := ArgContext.Default) -> Arg{
    if !prs.ok do return Arg{}
    if argCtx == .FuncArg && lexerPeek(&prs.lex).type == .At {
        lexerNext(&prs.lex)
        return parseOffsetModifier(prs, p)
    }

    lhs: Arg

    prefix := lexerNext(&prs.lex)

    #partial switch prefix.type {
        case .Number:
            lhs = parseNumber(prs, prefix)
            if !prs.ok do return Arg{}
        case .Text:
            lhs.type = .Text
            lhs.text = prefix.content
        case .Identifier:
            // this one is versatile
            lhs = parseIdentifier(prs, p, prefix)
            if !prs.ok do return Arg{}
        case .Op:
            if prefix.content == "-" {
                unaryMinusBP :: 30
                rhs := parseArg(prs, p, unaryMinusBP, .Default)
                if !prs.ok do return Arg{}
                NEG_ONE :: Arg{type = .Number, value = -1}
                MULT_TOKEN :: Token{type = .Op, content = "*"}
                lhs = combine(prs, NEG_ONE, rhs, MULT_TOKEN)
            }else{
                failParse(prs, fmt.tprintf("Error: unexpected operator %s", tokenToMessage(prefix)))
                return Arg{}
            }
        case .At:
            failParse(prs, "Error: offset modifiers can only appear at the start of a function argument")
            return Arg{}
        case .LParen:
            lhs = parseArg(prs, p, 0, .Default)
            if !prs.ok do return Arg{}
            if lexerNext(&prs.lex).type != .RParen {
                failParse(prs, "Error: missing ')' to close grouped expression")
                return Arg{}
            }
        case .Pipe:
            cmd := makeCallPtr(.ResetPos)
            cmd.name = "|"
            lhs = Arg{
                type = .Call,
                expr = cmd,
            }
        case .DoublePipe:
            cmd := makeCallPtr(.ResetPosVel)
            cmd.name = "||"
            lhs = Arg{
                type = .Call,
                expr = cmd,
            }
        case .Invalid:
            if prefix.content == "unterminated string" {
                failParse(prs, "Error: unterminated string literal")
            } else {
                failParse(prs, fmt.tprintf("Error: unexpected character %s", tokenToMessage(prefix)))
            }
            return Arg{}
        case:
            failParse(prs, fmt.tprintf("Error: unexpected token %s", tokenToMessage(prefix)))
            return Arg{}
    }

    if !canContinueExpr(lhs) do return lhs

    for {
        op: Token = lexerPeek(&prs.lex)

        if op.type != .Op do break 
        
        baseBP := getBP(op)

        if baseBP.left < minBP do break 
        lexerNext(&prs.lex)

        rhs := parseArg(prs, p, baseBP.right, .Default)
        if !prs.ok do return Arg{}

        lhs = combine(prs, lhs, rhs, op)
        if !prs.ok do return Arg{}
    }

    return lhs
}

canContinueExpr :: proc(arg: Arg) -> bool {
    #partial switch arg.type {
    case .Number, .Variable:
        return true
    case .Call:
        if arg.expr == nil do return false
        #partial switch arg.expr.type {
        case .Plus, .Minus, .Mul, .Div, .Abs, .Min, .Max, .Sign, .Sqrt, .Floor, .Ceil, .Round, .Sin, .Cos, .Tan, .Atan, .ArgAngle:
            return true
        case:
            return false
        }
    case:
        return false
    }

    return false
}

parseOffsetModifier :: proc(prs: ^ParserState, p: ^Player) -> Arg {
    modifierTok := lexerNext(&prs.lex)
    if modifierTok.type != .Identifier {
        failParse(prs, fmt.tprintf("Error: expected offset modifier after '@', got %s", tokenToMessage(modifierTok)))
        return Arg{}
    }

    modifier: ArgModifier
    switch modifierTok.content {
    case "mm":
        modifier = .MM
    case "b":
        modifier = .B
    case "ld":
        modifier = .LD
    case:
        failParse(prs, fmt.tprintf("Error: unknown offset modifier '@%s'", modifierTok.content))
        return Arg{}
    }

    arg := parseArg(prs, p, 0, .OffsetValue)
    if !prs.ok do return Arg{}
    if arg.modifier != .None {
        failParse(prs, "Error: offset modifiers cannot be stacked")
        return Arg{}
    }

    arg.modifier = modifier
    return arg
}

parseNumber :: proc(prs: ^ParserState, tok: Token) -> Arg {
    if !prs.ok do return Arg{}
    value, ok := strconv.parse_f64(tok.content)
    if !ok {
        failParse(prs, fmt.tprintf("Error: invalid number %s", tokenToMessage(tok)))
        return Arg{}
    }

    return Arg{
        type = .Number,
        value = value,
    }
}

parseIdentifier :: proc(prs: ^ParserState, p: ^Player, tok: Token) -> Arg {
    if !prs.ok do return Arg{}

    mf, isMf := checkMoveFunc(tok.content)
    if isMf do return parseMoveFunc(prs, p, &mf, tok)

    cmd_type := getCommandType(prs, tok.content)
    if cmd_type == .Invalid {
        if lexerPeek(&prs.lex).type == .LParen || lexerPeek(&prs.lex).type == .LBrace {
            failParse(prs, fmt.tprintf("Error: unknown command '%s'", tok.content))
            return Arg{}
        }

        return Arg{
            type = .Variable,
            text = tok.content,
        }
    }

    cmd := makeCallPtr(cmd_type)
    cmd.name = tok.content
    // Note: f is treated the same as f()

    // f(...), arguments separated by commas
    paren: if lexerPeek(&prs.lex).type == .LParen{
        lexerNext(&prs.lex)

        // No Arguments, consume ')' immediately and break
        if lexerPeek(&prs.lex).type == .RParen{
            lexerNext(&prs.lex)
            break paren
        }

        for {
            arg := parseArg(prs, p, 0, .FuncArg)
            if !prs.ok{
                delete(cmd.args)
                free(cmd)
                return Arg{}
            }

            append(&cmd.args, arg)

            next := lexerPeek(&prs.lex)
            if next.type == .Comma {
                lexerNext(&prs.lex)
            } else if next.type == .RParen {
                lexerNext(&prs.lex)
                break
            }else {
                failParse(prs, fmt.tprintf("Error: expected ',' or ')' in %s(...), got %s", tok.content, tokenToMessage(next)))
                delete(cmd.args)
                free(cmd)
                return Arg{}
            }
        }
    }

    // f(){...} or f{...} arguments is a code block, i.e. list of commands separated by space
    brace: if lexerPeek(&prs.lex).type == .LBrace{
        lexerNext(&prs.lex)

        // No code in braces are invalid (For now)
        if lexerPeek(&prs.lex).type == .RBrace{
            failParse(prs, "Error: {...} cannot be empty")
            delete(cmd.args)
            free(cmd)
            return Arg{}
        }

        for {
            inner_cmd := parseArg(prs, p, 0, .Default)

            if !prs.ok{
                delete(cmd.args)
                delete(cmd.code)
                free(cmd)
                return Arg{}
            }

            if !isCall(&inner_cmd) {
                failParse(prs, "Error: code block {} can only contain commands")
                delete(cmd.args)
                delete(cmd.code)
                free(cmd)
                return Arg{}
            }

            append(&cmd.code, inner_cmd)

            if lexerPeek(&prs.lex).type == .RBrace {
                lexerNext(&prs.lex)
                break
            }else if lexerPeek(&prs.lex).type == .EOF {
                failParse(prs, "Error: missing '}' to close code block")
                delete(cmd.args)
                delete(cmd.code)
                free(cmd)
                return Arg{}
            }
        }
    }

    return Arg{
        type = .Call,
        expr = cmd,
    }
}

getCommandType :: proc(prs: ^ParserState, cmdName: string) -> CmdType {
    if cmd := getCommonCommandType(cmdName); cmd != .Invalid {
        return cmd
    }

    #partial switch prs.ctx {
        case .XZsim:
            return getXZCommandType(cmdName)
        case .Ysim:
            return getYCommandType(cmdName)
        case .ElytraSim:
            return getXYZCommandType(cmdName)
    }

    return .Invalid
}

getCommonCommandType :: proc(cmdName: string) -> CmdType {
    switch cmdName {
        case "print":
            return .Print
        case "println":
            return .Println
        case "sep":
            return .SetPrintSep
        case "silent":
            return .SetSilent
        case "mes", "measure":
            return .Measure
        case "polar":
            return .Polar
        case "set":
            return .SetVar
        case "pre", "precision":
            return .SetPrecision
        case "tick":
            return .SetTick
        case "outtick":
            return .OutTick
        case "inertia":
            return .SetInertia
		case "v", "ver", "version":
			return .SetVersion
        case "web":
            return .SetWeb
        case "ld", "ladder":
            return .SetLadder
        case "abs":
            return .Abs
        case "min":
            return .Min
        case "max":
            return .Max
        case "sign":
            return .Sign
        case "sqrt":
            return .Sqrt
        case "floor":
            return .Floor
        case "ceil":
            return .Ceil
        case "round":
            return .Round
        case "sin":
            return .Sin
        case "cos":
            return .Cos
        case "tan":
            return .Tan
        case "atan":
            return .Atan
        case "arg":
            return .ArgAngle
        case "r", "loop", "repeat":
            return .Loop
        case "def", "define":
            return .Define
        case "save":
            return .Save
        case "load":
            return .Load
        case:
            return .Invalid
    }
    return .Invalid
}

getXZCommandType :: proc(cmdName: string) -> CmdType {
    switch cmdName {
        case "x":
            return .SetX
        case "z":
            return .SetZ
        case "pos":
            return .SetPos
        case "vz":
            return .SetVz
        case "vx":
            return .SetVx
        case "vel":
            return .SetVel
        case "xr", "outx":
            return .OutXRaw
        case "outgx":
            return .OutGlobalX
        case "xb":
            return .OutXBlock
        case "xmm":
            return .OutXMM
        case "xld":
            return .OutXLadder
        case "zr", "outz":
            return .OutZRaw
        case "outgz":
            return .OutGlobalZ
        case "zb":
            return .OutZBlock
        case "zmm":
            return .OutZMM
        case "zld":
            return .OutZLadder
        case "outvx":
            return .OutVx
        case "outvz":
            return .OutVz
        case "vec":
            return .OutVec
        case "f":
            return .SetF
        case "outf":
            return .OutF
        case "tu", "turn":
            return .SetTurn
        case "outtu", "outturn":
            return .OutTurn
        case "how45":
            return .Set45
        case "outa":
            return .OutAngle
        case "slip":
            return .SetSlip
        case "slow", "slowness":
            return .SetSlow
        case "speed":
            return .SetSpeed
        case "gnd":
            return .PrevGround
        case "air":
            return .PrevAir
        case "sdel":
            return .SetSprintDelay
        case "sndel", "sneakdelay":
            return .SetSneakDelay
        case "poss", "zposs":
            return .ZPoss
        case "xposs":
            return .XPoss
        case "inv", "zinv":
            return .ZInv
        case "bwmm":
            return .BWMM
        case "xinv":
            return .XInv
        case "xzinv":
            return .XZInv
        case "vxinv":
            return .VxInv
        case "vzinv":
            return .VzInv
        case "vxzinv":
            return .VxzInv
        case "ix":
            return .ForceInertiaX
        case "iz":
            return .ForceInertiaZ
        case "move":
            return .Move
        case "taps":
            return .Taps
        case "aq", "anglequeue":
            return .AngleQueue
        case "tq", "turnqueue":
            return .TurnQueue
        case "bl", "block":
            return .SetBlock
        case "ss", "soulsand":
            return .SetSoulSand
        case:
            return .Invalid
    }
    return .Invalid
}

getYCommandType :: proc(cmdName: string) -> CmdType {
    switch cmdName {
        case "c", "coast":
            return .Coast
        case "j", "jump":
            return .Jump
        case "up":
            return .UpAction
        case "hold":
            return .LadderHold
        case "y":
            return .SetY
        case "outy", "yr":
            return .OutY
        case "outgy":
            return .OutGlobalY
        case "vy":
            return .SetVy
        case "outvy":
            return .OutVy
        case "ytop":
            return .OutYTop
        case "height":
            return .SetPlayerHeight
        case "jb", "jumpboost":
            return .SetJumpBoost
        case "sf", "slowfall", "slowfalling":
            return .SetSlowFall
        case "obs", "observe":
            return .SetYObserve
        case "jto", "jumpto":
            return .JumpTo
        case "cto", "coastto":
            return .CoastTo
        case "cq", "ceilq", "ceilqueue":
            return .CeilQueue
        case "sq", "slimeq", "slimequeue":
            return .SlimeQueue
        case "tier":
            return .tier
        case:
            return .Invalid
    }
    return .Invalid
}

getXYZCommandType :: proc(cmdName: string) -> CmdType {
    switch cmdName {
        case "e":
            return .Elytra
        case "ej", "ejump":
            return .ElytraJump
        case "esj":
            return .ElytraSprintJump
        case "el", "eland":
            return .ElytraLand
        case "pitch", "p":
            return .SetPitch
        case "outp":
            return .OutPitch
        case "pitchqueue", "pq":
            return .PitchQueue
    }

	if cmd := getXZCommandType(cmdName); cmd != .Invalid {
		return cmd
	}

	#partial switch getYCommandType(cmdName) {
	case .SetY, .OutY, .OutGlobalY, .SetVy, .OutVy, .OutYTop,
	     .SetPlayerHeight, .SetJumpBoost, .SetSlowFall, .SetYObserve,
	     .CeilQueue, .SlimeQueue, .tier:
		return getYCommandType(cmdName)
	case:
		return .Invalid
	}
}

checkMoveFunc :: proc(name: string) -> (MoveFunc, bool){
    mf := MoveFunc{name = name}
    s := name

    if len(s) >= 2 && s[len(s)-2:] == "45" {
        mf.strafe45 = true
        s = s[:len(s)-2]
    }

    if len(s) > 0 && s[len(s)-1] == 'a' {
        mf.airborne = true
        s = s[:len(s)-1]
    } else if len(s) > 0 && s[len(s)-1] == 'j' {
        mf.jump = true
        s = s[:len(s)-1]
    }

    switch s {
        case "w":
        case "s":
            mf.sprint = true
        case "sn":
            mf.sneak = true
        case "sns":
            mf.sneak = true
            mf.sprint = true
        case "st":
            mf.stop = true
            if mf.strafe45{
                return mf, false
            }
        case:
            return mf, false
    }

    return mf, true
}

parseMoveFunc :: proc(prs: ^ParserState, p: ^Player, mf: ^MoveFunc, tok: Token) -> Arg {
    if lexerPeek(&prs.lex).type == .Dot{
        if mf.stop {
            failParse(prs, "Error: stop movement functions cannot have appended inputs")
            return Arg{}
        }
        if mf.strafe45 {
            failParse(prs, "Error: 45 movement functions cannot have appended inputs")
            return Arg{}
        }
        lexerNext(&prs.lex)

        inputTok := lexerNext(&prs.lex)

        if inputTok.type != .Identifier {
            failParse(prs, fmt.tprintf("Error: expected a movement input after '.', got %s", tokenToMessage(inputTok)))
            return Arg{}
        }

        w, a, ok := wasdToVec(inputTok.content)

        if !ok {
            failParse(prs, fmt.tprintf("Error: invalid movement input '%s'", inputTok.content))
            return Arg{}
        }

        mf.w, mf.a = w, a

    } else if !mf.stop{
        mf.w = 1
    }

    paren: if lexerPeek(&prs.lex).type == .LParen{
        lexerNext(&prs.lex)
        targ := parseArg(prs, p, 0, .FuncArg)
        t, ok1 := eval(prs, p, targ)

        if !ok1 {
            if !prs.ok do return Arg{}
            failParse(prs, fmt.tprintf("Error: duration in %s(...) must be a whole number", tok.content))
            return Arg{}
        }

        roundt := math.round(t)

        if(abs(t - roundt) < 1e-15){
            mf.t = int(roundt)
        }else{
            failParse(prs, fmt.tprintf("Error: duration in %s(...) must be a whole number", tok.content))
            return Arg{}
        }

        if mf.t <= 0 {
            failParse(prs, fmt.tprintf("Error: duration in %s(...) must be positive", tok.content))
            return Arg{}
        }

        next := lexerPeek(&prs.lex)
        if next.type == .RParen {
            lexerNext(&prs.lex)
            break paren
        }else if next.type == .Comma {
            lexerNext(&prs.lex)
        }else {
            failParse(prs, fmt.tprintf("Error: expected ',' or ')' after duration in %s(...), got %s", tok.content, tokenToMessage(next)))
            return Arg{}
        }

        rotarg := parseArg(prs, p, 0, .FuncArg)
        rot64, ok2 := eval(prs, p, rotarg)

        if !ok2 {
            if !prs.ok do return Arg{}
            failParse(prs, fmt.tprintf("Error: rotation in %s(..., rotation) must be a number", tok.content))
            return Arg{}
        }

        mf.rot = f32(rot64)
        mf.rotUsed = true

        next = lexerPeek(&prs.lex)
        if next.type != .RParen {
            failParse(prs, fmt.tprintf("Error: expected ')' after %s(..., rotation), got %s", tok.content, tokenToMessage(next)))
            return Arg{}
        }else {
            lexerNext(&prs.lex)
        }

    }else{
        mf.t = 1
    }

    return Arg{
        type = .MoveCall,
        mvfunc = mf^
    }
}

combine :: proc(prs: ^ParserState, lhs: Arg, rhs: Arg, op: Token) -> Arg {
    if !prs.ok do return Arg{}
    reducible := (lhs.type == .Number && lhs.modifier == .None && rhs.type == .Number && rhs.modifier == .None)
    switch op.content {
        case "+":
            if reducible{
                return Arg{type = .Number, value = lhs.value + rhs.value}
            }else{
                cmd := makeCallPtr(.Plus, lhs, rhs)
                cmd.name = "+"
                return Arg{
                    type = .Call,
                    expr = cmd,
                }
            }
        case "-":
            if reducible {
                return Arg{type = .Number, value = lhs.value - rhs.value}
            } else {
                cmd := makeCallPtr(.Minus, lhs, rhs)
                cmd.name = "-"
                return Arg{
                    type = .Call,
                    expr = cmd,
                }
            }

        case "*":
            if reducible {
                return Arg{type = .Number, value = lhs.value * rhs.value}
            } else {
                cmd := makeCallPtr(.Mul, lhs, rhs)
                cmd.name = "*"
                return Arg{
                    type = .Call,
                    expr = cmd,
                }
            }

        case "/":
            if reducible {
                if rhs.value == 0 {
                    failParse(prs, "Error: division by zero")
                    return Arg{}
                }
                return Arg{type = .Number, value = lhs.value / rhs.value}
            } else {
                cmd := makeCallPtr(.Div, lhs, rhs)
                cmd.name = "/"
                return Arg{
                    type = .Call,
                    expr = cmd,
                }
            }

        case:
            failParse(prs, fmt.tprintf("Error: unsupported operator %s", tokenToMessage(op)))
            return Arg{}

    }
}

BP :: struct {
    left:int, right:int,
}

getBP :: proc(op: Token) -> BP{
    switch op.content{
        case "+", "-":
            return BP{10, 11}
        case "*", "/":
            return BP{20, 21}
        case:
            return BP{-1, -1}
    }
}
