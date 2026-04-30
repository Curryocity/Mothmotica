package main

import "core:fmt"

makeCallPtr :: proc(type: CmdType, entries: ..Arg) -> ^Command {
    cmd := new(Command)
    cmd.type = type
    append(&cmd.args, ..entries)
    return cmd
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

