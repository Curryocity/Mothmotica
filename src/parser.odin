package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:math"

TokenType :: enum{
    Invalid,
    EOF,

    Identifier,
    Number,
    Text,

    Dot,
    Comma,
    LParen,
    RParen,
    Op,
    Pipe,
    DoublePipe,
}

Token :: struct{
    content : string,
    type : TokenType,
}

Lexer :: struct {
    data : string,
    pos: int,
    nextCache: Token,
    nextOk: bool,
}

lexerNext :: proc(lex : ^Lexer) -> Token {
    if !lex.nextOk do updateNext(lex)
    lex.nextOk = false
    return lex.nextCache
}

lexerPeek :: proc(lex : ^Lexer) -> Token {
    if !lex.nextOk do updateNext(lex)
    return lex.nextCache
}

skipSpace :: proc(lex : ^Lexer){
    n := len(lex.data)
    for lex.pos < n && isSpace(lex.data[lex.pos]) do lex.pos += 1
}

isSpace :: proc(ch: byte) -> bool {
    return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

updateNext :: proc(lex : ^Lexer) {
    skipSpace(lex)

    n := len(lex.data)

    if lex.pos >= n {
        lex.nextCache = Token{type = .EOF, content = ""}
        lex.nextOk = true
        return
    }

    c := lex.data[lex.pos]

    if c >= '0' && c <= '9' {
        start := lex.pos

        for lex.pos < n && lex.data[lex.pos] >= '0' && lex.data[lex.pos] <= '9' {
            lex.pos += 1
        }

        if lex.pos < n && lex.data[lex.pos] == '.' {
            lex.pos += 1
            for lex.pos < n && lex.data[lex.pos] >= '0' && lex.data[lex.pos] <= '9' {
                lex.pos += 1
            }
        }

        lex.nextCache = Token{
            type = .Number,
            content = lex.data[start:lex.pos],
        }
        lex.nextOk = true
        return
    }

    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
        start := lex.pos

        for lex.pos < n {
            ch := lex.data[lex.pos]
            if (ch >= 'a' && ch <= 'z') ||
               (ch >= 'A' && ch <= 'Z') ||
               (ch >= '0' && ch <= '9') ||
               ch == '_' {
                lex.pos += 1
            } else {
                break
            }
        }

        lex.nextCache = Token{
            type = .Identifier,
            content = lex.data[start:lex.pos],
        }
        lex.nextOk = true
        return
    }

    if c == '"' {
        lex.pos += 1
        textStart := lex.pos

        for lex.pos < n && lex.data[lex.pos] != '"' {
            lex.pos += 1
        }

        if lex.pos >= n {
            lex.nextCache = Token{type = .Invalid, content = "unterminated string"}
            lex.nextOk = true
            return
        }

        lex.nextCache = Token{
            type = .Text,
            content = lex.data[textStart:lex.pos],
        }
        lex.pos += 1
        lex.nextOk = true
        return
    }

    if c == '|' {
        if lex.pos + 1 < n && lex.data[lex.pos + 1] == '|' {
            lex.nextCache = Token{
                type = .DoublePipe,
                content = lex.data[lex.pos:lex.pos+2],
            }
            lex.pos += 2
        } else {
            lex.nextCache = Token{
                type = .Pipe,
                content = lex.data[lex.pos:lex.pos+1],
            }
            lex.pos += 1
        }
        lex.nextOk = true
        return
    }

    lex.pos += 1

    tok_type: TokenType
    switch c {
    case '.':
        tok_type = .Dot
    case ',':
        tok_type = .Comma
    case '(':
        tok_type = .LParen
    case ')':
        tok_type = .RParen
    case '+', '-', '*', '/':
        tok_type = .Op
    case:
        tok_type = .Invalid
    }

    lex.nextCache = Token{
        type = tok_type,
        content = lex.data[lex.pos-1:lex.pos],
    }
    lex.nextOk = true
}

CmdType :: enum {
    Plus, Minus, Mul, Div, 
    SetVar, SetPrecision,

    SetX, SetZ, SetPos, 
    SetVz, SetVx, SetVel,
    SetVzAir, SetVxAir, SetVelAir,
    ResetPos, ResetPosVel,

    OutXRaw, OutXBlock, OutXMM,
    OutZRaw, OutZBlock, OutZMM,

    OutVx, OutVz,

    SetF, OutF, SetTurn, OutTurn,
    Move,

    XInv, ZInv, XZInv,

    EndVx, EndVz, EndVxVz,
    InertiaX, InertiaZ,

    SetSlip, SetSprintDelay, SetInertia,

    Invalid,
}

Command :: struct {
    type: CmdType,
    args: [dynamic]Arg,
}

ArgType :: enum {
    Number, Text, Variable, Call, MoveCall
}

Arg :: struct {
    type: ArgType,
    value: f64,
    text: string,
    expr: ^Command,
    mvfunc: MoveFunc,
}

makeCallPtr :: proc(type: CmdType, entries: ..Arg) -> ^Command {
    cmd := new(Command)
    cmd.type = type
    append(&cmd.args, ..entries)
    return cmd
}

// ENTRY !!!!!
parseMothball :: proc(input: string) -> string {
    buf: [dynamic]u8
    defer delete(buf)

    COMMAND_PREFIX :: ";s"
    prefix := COMMAND_PREFIX
    prefix_len := len(prefix)

    if len(input) < prefix_len || input[:prefix_len] != prefix do return ""

    prs := ParserState{
        lex = Lexer{
            data = input,
            pos = prefix_len,
            nextOk = false,
        },
        err = .None,
        vars = make(map[string]f64),
        precision = 6,
    }

    p := makePlayer()

    for lexerPeek(&prs.lex).type != .EOF {
        cmd := parseArg(&prs, &p, 0)

        if(prs.err != .None){
            // Todo: Output custom error message
            return "Error"
        }

        pendingOutput: string
        ok: bool
        // Execute command
        if cmd.type == .Call{
            pendingOutput, ok = executeCommand(&prs, &p, cmd.expr)
            if !ok {
                return "Error"
            }
        }else if cmd.type == .MoveCall{
            if cmd.mvfunc.t <= 0 {
                return "Error: Duration must be positive"
            }
            exeMoveFunc(&p, cmd.mvfunc)
        }else{
            return "Error: Expected a command"
        }
        
        // fmt.println("PendingOutput:" , pendingOutput)

        if(pendingOutput != ""){
            append(&buf, pendingOutput)
            append(&buf, "\n")
        }
    }

    result := strings.clone(string(buf[:]))

    return result
}

formatNum :: proc(prs: ^ParserState, x: f64) -> string {
    return fmt.tprintf("%.*f", int(prs.precision), x)
}

executeCommand :: proc(prs: ^ParserState, p: ^Player, cmd: ^Command) -> (string, bool) {
    if cmd == nil do return "Error: null command", false

    switch cmd.type {
    case .SetVar:
        if len(cmd.args) != 2 {
            return "Error: set(...) expects 2 arguments", false
        }

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
            return "Error: second argument of set(...) is not a valid number", false
        }

        prs.vars[target.text] = value
        return "", true

    case .SetPrecision:
        if len(cmd.args) != 1 {
            return "Error: pre(...) expects 1 argument", false
        }

        pre, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: pre(...) argument is not a valid number", false
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
        if len(cmd.args) != 1 {
            return "Error: x(...) expects 1 argument", false
        }

        x, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: x(...) argument is not a valid number", false
        setX(p, x)
        return "", true

    case .SetZ:
        if len(cmd.args) != 1 {
            return "Error: z(...) expects 1 argument", false
        }

        z, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: z(...) argument is not a valid number", false
        setZ(p, z)
        return "", true

    case .SetPos:
        if len(cmd.args) != 2 {
            return "Error: pos(...) expects 2 arguments", false
        }

        x, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return "Error: first argument of pos(...) is not a valid number", false

        z, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return "Error: second argument of pos(...) is not a valid number", false

        setX(p, x)
        setZ(p, z)
        return "", true

    case .SetVx, .SetVxAir:
        if len(cmd.args) != 1 {
            return "Error: vx(...) expects 1 argument", false
        }

        vx, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: vx(...) argument is not a valid number", false

        airborne := (cmd.type == .SetVxAir)
        setVx(p, vx, airborne)
        return "", true

    case .SetVz, .SetVzAir:
        if len(cmd.args) != 1 {
            return "Error: vz(...) expects 1 argument", false
        }

        vz, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: vz(...) argument is not a valid number", false

        airborne := (cmd.type == .SetVzAir)
        setVz(p, vz, airborne)
        return "", true

    case .SetVel, .SetVelAir:
        if len(cmd.args) != 2 {
            return "Error: vel(...) expects 2 arguments", false
        }

        vx, ok1 := eval(prs, p, cmd.args[0])
        if !ok1 do return "Error: first argument of vel(...) is not a valid number", false

        vz, ok2 := eval(prs, p, cmd.args[1])
        if !ok2 do return "Error: second argument of vel(...) is not a valid number", false

        airborne := (cmd.type == .SetVelAir)
        setVel(p, vx, vz, airborne)
        return "", true

    case .ResetPos:
        p.x = 0
        p.z = 0
        return "", true

    case .ResetPosVel:
        p.x = 0
        p.z = 0
        p.vx = 0
        p.vz = 0
        return "", true

    case .OutXRaw:
        return fmt.tprintf("X: %s", formatNum(prs, p.x)), true
    case .OutXBlock:
        return fmt.tprintf("Xb: %s", formatNum(prs, p.x + 0.6)), true
    case .OutXMM:
        return fmt.tprintf("Xmm: %s", formatNum(prs, p.x - 0.6)), true

    case .OutZRaw:
        return fmt.tprintf("Z: %s", formatNum(prs, p.z)), true
    case .OutZBlock:
        return fmt.tprintf("Zb: %s", formatNum(prs, p.z + 0.6)), true
    case .OutZMM:
        return fmt.tprintf("Zmm: %s", formatNum(prs, p.z - 0.6)), true

    case .OutVx:
        return fmt.tprintf("Vx: %s", formatNum(prs, p.vx)), true
    case .OutVz:
        return fmt.tprintf("Vz: %s", formatNum(prs, p.vz)), true

    case .SetF:
        if len(cmd.args) != 1 {
            return "Error: f(...) expects 1 argument", false
        }

        f, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: f(...) argument is not a valid number", false
        setF(p, f32(f))
        return "", true

    case .OutF:
        return fmt.tprintf("F: %s", formatNum(prs, f64(p.f))), true

    case .SetTurn:
        if len(cmd.args) != 1 {
            return "Error: t(...) expects 1 argument", false
        }

        t, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: t(...) argument is not a valid number", false
        p.f += f32(t)
        return "", true

    case .OutTurn:
        return fmt.tprintf("T: %s", formatNum(prs, f64(p.f))), true

    case .SetSlip:
        if len(cmd.args) != 1 {
            return "Error: slip(...) expects 1 argument", false
        }

        slip, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: slip(...) argument is not a valid number", false
        p.ground_slip = f32(slip)
        return "", true

    case .SetSprintDelay:
        if len(cmd.args) != 1 {
            return "Error: sprintdelay(...) expects 1 argument", false
        }

        v, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: sprintdelay(...) argument is not a valid number", false
        p.sprint_delay = v != 0
        return "", true

    case .SetInertia:
        if len(cmd.args) != 1 {
            return "Error: inertia(...) expects 1 argument", false
        }

        inertia, ok := eval(prs, p, cmd.args[0])
        if !ok do return "Error: inertia(...) argument is not a valid number", false
        p.inertia_threshold = inertia
        return "", true

    case .Move:
        return "Error: move(...) not implemented yet", false

    case .XInv:
        return "Error: xinv(...) not implemented yet", false
    case .ZInv:
        return "Error: zinv(...) not implemented yet", false
    case .XZInv:
        return "Error: xzinv(...) not implemented yet", false

    case .EndVx:
        return "Error: endvx(...) not implemented yet", false
    case .EndVz:
        return "Error: endvz(...) not implemented yet", false
    case .EndVxVz:
        return "Error: endvxvz(...) not implemented yet", false

    case .InertiaX:
        return "Error: inertiax(...) not implemented yet", false
    case .InertiaZ:
        return "Error: inertiaz(...) not implemented yet", false

    case .Plus, .Minus, .Mul, .Div:
        return "Error: operator call cannot be executed as a top-level statement", false

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
        return 0, false

    case .MoveCall:
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
            if !ok do return 0, false
            return value, true
        }

    case .Call:
        if expr.expr == nil do return 0, false

        cmd := expr.expr

        if len(cmd.args) != 2 do return 0, false

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
            if rhs == 0 do return 0, false
            return lhs / rhs, true
        case:
            return 0, false
        }

    case:
        return 0, false
    }
}

exeMoveFunc :: proc(p: ^Player, mf: MoveFunc){

    originalF := p.f

    if mf.rotUsed {
        p.f = mf.rot
    }

    if mf.strafe45 {
        if mf.jump {
            // jump tick
            if mf.sprint { // sprint jump at f0
                move(p, 1, 0, false, mf.sprint, mf.sneak, true)
            }else {
                p.f = originalF + 45
                move(p, 1, 1, false, mf.sprint, mf.sneak, true)
            } // add support for snsj45 angle
            
            p.f = originalF + 45
            for _ in 0..<(mf.t - 1) {
                // air ticks
                move(p, 1, 1, true, mf.sprint, mf.sneak, false)
            }
        }else {
            p.f = originalF + 45
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


ParseError :: enum {
    None, 
    MissingRParen,
    UnexpectedToken,
    InvalidPrefixToken,
    DivisionByZero,
    InvalidNumber,
    InvalidCommand,
    nonEmptyStop,
    BadInput,
    nonEmpty45Input,
}

ParserState :: struct {
    lex: Lexer,
    err: ParseError,
    vars: map[string]f64,
    precision: u8,
}

parseArg :: proc(prs: ^ParserState, p: ^Player, minBP: int) -> Arg{
    if prs.err != .None do return Arg{}
    lhs: Arg

    prefix := lexerNext(&prs.lex)

    #partial switch prefix.type {
        case .Number:
            lhs = parseNumber(prs, prefix)
            if prs.err != .None do return Arg{}
        case .Text:
            lhs.type = .Text
            lhs.text = prefix.content
        case .Identifier:
            // this one is versatile
            lhs = parseIdentifier(prs, p, prefix)
            if prs.err != .None do return Arg{}
        case .Op:
            if prefix.content == "-" {
                unaryMinusBP :: 30
                rhs := parseArg(prs, p, unaryMinusBP)
                if prs.err != .None do return Arg{}
                NEG_ONE :: Arg{type = .Number, value = -1}
                MULT_TOKEN :: Token{type = .Op, content = "*"}
                lhs = combine(prs, NEG_ONE, rhs, MULT_TOKEN)
            }else{
                prs.err = .InvalidPrefixToken
                return Arg{}
            }
        case .LParen:
            lhs = parseArg(prs, p, 0)
            if prs.err != .None do return Arg{}
            if lexerNext(&prs.lex).type != .RParen {
                prs.err = .MissingRParen
                return Arg{}
            }
        case .Pipe:
            lhs = Arg{
                type = .Call,
                expr = makeCallPtr(.ResetPos)
            }
        case .DoublePipe:
            lhs = Arg{
                type = .Call,
                expr = makeCallPtr(.ResetPosVel)
            }
        case:
            prs.err = .InvalidPrefixToken
            return Arg{}
    }

    if lhs.type != .Number && lhs.type != .Variable do return lhs

    for {
        op: Token = lexerPeek(&prs.lex)

        if op.type != .Op do break 
        
        baseBP := getBP(op)

        if baseBP.left < minBP do break 
        lexerNext(&prs.lex)

        rhs := parseArg(prs, p, baseBP.right)
        if prs.err != .None do return Arg{}

        lhs = combine(prs, lhs, rhs, op)
        if prs.err != .None do return Arg{}
    }

    return lhs
}

parseNumber :: proc(prs: ^ParserState, tok: Token) -> Arg {
    if prs.err != .None do return Arg{}
    value, ok := strconv.parse_f64(tok.content)
    if !ok {
        prs.err = .InvalidNumber
        return Arg{}
    }

    return Arg{
        type = .Number,
        value = value,
    }
}

parseIdentifier :: proc(prs: ^ParserState, p: ^Player, tok: Token) -> Arg {
    if prs.err != .None do return Arg{}


    mf, isMf := parseMoveFunc(tok.content)

    if isMf {
        if lexerPeek(&prs.lex).type == .Dot{
            if mf.stop {
                prs.err = .nonEmptyStop
                return Arg{}
            }
            if mf.strafe45 {
                prs.err = .nonEmpty45Input
                return Arg{}
            }
            lexerNext(&prs.lex)

            inputTok := lexerNext(&prs.lex)

            if inputTok.type != .Identifier {
                prs.err = .BadInput
                return Arg{}
            }

            s := inputTok.content

            if len(s) == 0 {
                prs.err = .BadInput
                return Arg{}
            }

            if len(s) > 0 && (s[0] == 'w' || s[0] == 's'){
                mf.w = (s[0] == 'w')? 1 : -1
                s = s[1:]
            }

            if len(s) > 0 && (s[0] == 'a' || s[0] == 'd'){
                mf.a = (s[0] == 'a')? 1 : -1
                s = s[1:]
            }

            if len(s) > 0 {
                prs.err = .BadInput
                return Arg{}
            }
        } else if !mf.stop{
            mf.w = 1
        }

        paren: if lexerPeek(&prs.lex).type == .LParen{
            lexerNext(&prs.lex)
            targ := parseArg(prs, p, 0)
            t, ok1 := eval(prs, p, targ)

            if !ok1 {
                prs.err = .InvalidNumber
                return Arg{}
            }

            roundt := math.round(t)

            if(abs(t - roundt) < 1e-15){
                mf.t = int(roundt)
            }else{
                prs.err = .InvalidNumber
                return Arg{}
            }

            next := lexerPeek(&prs.lex)
            if next.type == .RParen {
                lexerNext(&prs.lex)
                break paren
            }else if next.type == .Comma {
                lexerNext(&prs.lex)
            }else {
                prs.err = .MissingRParen
                return Arg{}
            }

            rotarg := parseArg(prs, p, 0)
            rot64, ok2 := eval(prs, p, rotarg)

            if !ok2 {
                prs.err = .InvalidNumber
                return Arg{}
            }

            mf.rot = f32(rot64)
            mf.rotUsed = true

            next = lexerPeek(&prs.lex)
            if next.type != .RParen {
                prs.err = .MissingRParen
                return Arg{}
            }else {
                lexerNext(&prs.lex)
            }

        }else{
            mf.t = 1
        }

        return Arg{
            type = .MoveCall,
            mvfunc = mf
        }
    }

    // a command/function with parameters
    if lexerPeek(&prs.lex).type == .LParen{
        lexerNext(&prs.lex)

        cmd_type := getCommandType(tok.content)
        if cmd_type == .Invalid {
            prs.err = .InvalidCommand
            return Arg{}
        }

        cmd := makeCallPtr(cmd_type)

        if lexerPeek(&prs.lex).type != .RParen{
            for {
                arg := parseArg(prs, p, 0)
                if prs.err != .None{
                    delete(cmd.args)
                    free(cmd)
                    return Arg{}
                }

                append(&cmd.args, arg)

                next := lexerPeek(&prs.lex)
                if next.type == .Comma {
                    lexerNext(&prs.lex)
                    continue
                }
                if next.type == .RParen {
                    lexerNext(&prs.lex)
                    break
                }

                prs.err = .MissingRParen
                delete(cmd.args)
                free(cmd)
                return Arg{}
            }
        }else{
            lexerNext(&prs.lex) // consume ')' immediately
        }

        return Arg{
            type = .Call,
            expr = cmd
        }
    }

    // No parenthesis -> variable or parameterless call
    cmd_type := getCommandType(tok.content)
    if cmd_type != .Invalid {
        return Arg{
            type = .Call,
            expr = makeCallPtr(cmd_type)
        }
    }

    // variable
    return Arg{
        type = .Variable,
        text = tok.content
    }

}

MoveFunc :: struct {
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

parseMoveFunc :: proc(name: string) -> (MoveFunc, bool){
    mf := MoveFunc{}
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

getCommandType :: proc(cmdName: string) -> CmdType {
    switch cmdName {
        case "set":
            return .SetVar
        case "pre", "precision":
            return .SetPrecision
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
        case "vza":
            return .SetVzAir
        case "vxa":
            return .SetVxAir
        case "vela":
            return .SetVelAir
        case "xr", "outx":
            return .OutXRaw
        case "xb":
            return .OutXBlock
        case "xmm":
            return .OutXMM
        case "zr", "outz":
            return .OutZRaw
        case "zb":
            return .OutZBlock
        case "zmm":
            return .OutZMM
        case "outvx":
            return .OutVx
        case "outvz":
            return .OutVz
        case "f":
            return .SetF
        case "outf":
            return .OutF
        case "t":
            return .SetTurn
        case "outt":
            return .OutTurn
        case:
            return .Invalid
    }
}

combine :: proc(prs: ^ParserState, lhs: Arg, rhs: Arg, op: Token) -> Arg {
    if prs.err != .None do return Arg{}
    reducible := (lhs.type == .Number && rhs.type == .Number)
    switch op.content {
        case "+":
            if reducible{
                return Arg{type = .Number, value = lhs.value + rhs.value}
            }else{
                return Arg{
                    type = .Call,
                    expr = makeCallPtr(.Plus, lhs, rhs)
                }
            }
        case "-":
            if reducible {
                return Arg{type = .Number, value = lhs.value - rhs.value}
            } else {
                return Arg{
                    type = .Call,
                    expr = makeCallPtr(.Minus, lhs, rhs),
                }
            }

        case "*":
            if reducible {
                return Arg{type = .Number, value = lhs.value * rhs.value}
            } else {
                return Arg{
                    type = .Call,
                    expr = makeCallPtr(.Mul, lhs, rhs),
                }
            }

        case "/":
            if reducible {
                if rhs.value == 0 {
                    prs.err = .DivisionByZero
                    return Arg{}
                }
                return Arg{type = .Number, value = lhs.value / rhs.value}
            } else {
                return Arg{
                    type = .Call,
                    expr = makeCallPtr(.Div, lhs, rhs),
                }
            }

        case:
            prs.err = .UnexpectedToken
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