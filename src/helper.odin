package main

import "core:fmt"

makeCallPtr :: proc(type: CmdType, entries: ..Arg) -> ^Command {
    cmd := new(Command)
    cmd.type = type
    append(&cmd.args, ..entries)
    return cmd
}

cloneVars :: proc(vars: map[string]f64) -> map[string]f64 {
    cloned := make(map[string]f64)
    for key, value in vars {
        cloned[key] = value
    }
    return cloned
}

cloneSaves :: proc(saves: map[string]Player) -> map[string]Player {
    cloned := make(map[string]Player)
    for key, value in saves {
        cloned[key] = saveState(value)
    }
    return cloned
}

deleteSaves :: proc(saves: map[string]Player) {
    for _, &state in saves {
        deletePlayerState(&state)
    }
    delete(saves)
}

cloneParserState :: proc(prs: ^ParserState) -> ParserState {
    cloned := prs^
    cloned.vars = cloneVars(prs.vars)
    cloned.saves = cloneSaves(prs.saves)
    return cloned
}

loadParserState :: proc(dst: ^ParserState, src: ParserState) {
    oldVars := dst.vars
    oldSaves := dst.saves

    dst^ = src

    dst.vars = cloneVars(src.vars)
    dst.saves = cloneSaves(src.saves)

    delete(oldVars)
    deleteSaves(oldSaves)
}

deleteParserState :: proc(prs: ^ParserState) {
    delete(prs.vars)
    deleteSaves(prs.saves)
}

trimTrailingZeros :: proc(s: string) -> string {
    dot := -1
    for i in 0..<len(s){
        if s[i] == '.' {
            dot = i
            break
        }
    }

    if dot == -1 do return s

    end := len(s)
    for end > dot+1 && s[end-1] == '0' {
        end -= 1
    }
    if end == dot + 1 do end = dot

    return s[:end]
}

formatNum :: proc(prs: ^ParserState, x: f64) -> string {
    s := fmt.tprintf("%.*f", int(prs.precision), x)
    return trimTrailingZeros(s)
}

formatOutValue :: proc(prs: ^ParserState, p: ^Player, label: string, value: f64, args: []Arg, argName: string) -> (string, bool) {
    switch len(args) {
    case 0:
        return fmt.tprintf("%s: %s", label, formatNum(prs, value)), true
    case 1:
        base, ok := eval(prs, p, args[0])
        if !ok do return parserErrorOr(prs, fmt.tprintf("Error: %s(...) parameter cannot be evaluated", argName)), false

        remain := value - base
        return fmt.tprintf(
            "%s: %s %s %s",
            label,
            formatNum(prs, base),
            remain >= 0 ? "+" : "-",
            formatNum(prs, abs(remain)),
        ), true
    case:
        return fmt.tprintf("Error: too many parameters in %s(...)", argName), false
    }
}

expectArgsRange :: proc(cmd: ^Command, name: string, minCount, maxCount: int) -> (string, bool) {
    n := len(cmd.args)

    if n < minCount || n > maxCount {
        if minCount == maxCount {
            return fmt.tprintf("Error: %s expects %d argument(s)", name, minCount), false
        }

        return fmt.tprintf(
            "Error: %s expects between %d and %d argument(s)",
            name,
            minCount,
            maxCount,
        ), false
    }

    return "", true
}

expectNoCode :: proc(cmd: ^Command, name: string) -> (string, bool) {
    if len(cmd.code) != 0 {
        return fmt.tprintf("Error: %s does not accept a code block", name), false
    }
    return "", true
}

expectCode :: proc(cmd: ^Command, name: string) -> (string, bool) {
    if len(cmd.code) == 0 {
        return fmt.tprintf("Error: %s requires a code block", name), false
    }
    return "", true
}

expectPlainArgs :: proc(cmd: ^Command, name: string, minCount: int, maxCount: int) -> (string, bool) {
    argsMsg, argsOK := expectArgsRange(cmd, name, minCount, maxCount)
    if !argsOK do return argsMsg, false
    codeMsg, codeOK := expectNoCode(cmd, name)
    if !codeOK do return codeMsg, false

    return "", true
}

expectCodeArgs :: proc(cmd: ^Command, name: string, minCount: int, maxCount: int) -> (string, bool) {
    argsMsg, argsOK := expectArgsRange(cmd, name, minCount, maxCount)
    if !argsOK do return argsMsg, false
    codeMsg, codeOK := expectCode(cmd, name)
    if !codeOK do return codeMsg, false

    return "", true
}

failParse :: proc(prs: ^ParserState, msg: string) {
    if !prs.ok do return
    prs.ok = false
    prs.errMsg = msg
}

parserErrorOr :: proc(prs: ^ParserState, fallback: string) -> string {
    if !prs.ok && prs.errMsg != "" do return prs.errMsg
    return fallback
}

tokenToMessage :: proc(tok: Token) -> string {
    #partial switch tok.type {
    case .EOF:
        return "end of input"
    case .Text:
        return fmt.tprintf("\"%s\"", tok.content)
    case:
        if tok.content == "" do return "token"
        return fmt.tprintf("'%s'", tok.content)
    }
}

isCall :: proc(arg: ^Arg) -> bool {
    return arg.type == .Call || arg.type == .MoveCall
}

isRawPrintArg :: proc(arg: Arg) -> bool {
    return arg.type == .Call && arg.expr != nil && arg.expr.type == .PrintRaw
}

isRawOutputArg :: proc(arg: Arg) -> bool {
    if isRawPrintArg(arg) do return true

    if arg.type == .Call && arg.expr != nil && arg.expr.type == .Loop {
        return codeEndsRawOutput(arg.expr.code[:])
    }

    return false
}

codeEndsRawOutput :: proc(code: []Arg) -> bool {
    for i := len(code) - 1; i >= 0; i -= 1 {
        arg := code[i]
        if isRawOutputArg(arg) do return true
        if argMayOutput(arg) do return false
    }
    return false
}

argMayOutput :: proc(arg: Arg) -> bool {
    if arg.type != .Call do return arg.type != .MoveCall
    if arg.expr == nil do return true

    #partial switch arg.expr.type {
    case .SetVar, .SetPrecision,
         .SetX, .SetZ, .SetPos, .SetVx, .SetVz, .SetVel,
         .SetF, .SetTurn, .SetFSJ, .SetTick,
         .SetSlip, .SetSprintDelay, .SetInertia, .SetSlow, .SetSpeed,
         .PrevGround, .PrevAir,
         .ForceInertiaX, .ForceInertiaZ,
         .AngleQueue, .TurnQueue,
         .Save, .Load,
         .SetY, .SetVy, .SetPlayerHeight, .SetJumpBoost, .SetSlowFall, .SetYObserve,
         .CeilQueue, .SlimeQueue,
         .SetWeb, .SetLadder, .SetBlock, .SetSoulSand:
        return false
    case:
        return true
    }
}

argToString :: proc(prs: ^ParserState, p: ^Player, arg: Arg) -> (string, bool) {
    switch arg.type {
    case .Text:
        return arg.text, true

    case .Number, .Variable, .Call:
        value, ok := eval(prs, p, arg)
        if !ok do return parserErrorOr(prs, "Error: print(...) argument cannot be evaluated"), false
        return formatNum(prs, value), true

    case .MoveCall:
        return "Error: print(...) cannot print a movement command", false

    case:
        return "Error: print(...) argument cannot be printed", false
    }
}
