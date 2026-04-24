package main

import "core:fmt"
import "core:strconv"

TokenType :: enum{
    Invalid,
    EOF,

    Identifier,
    Number,
    Text,

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

    lex.pos += 1

    tok_type: TokenType
    switch c {
    case ',':
        tok_type = .Comma
    case '(':
        tok_type = .LParen
    case ')':
        tok_type = .RParen
    case '+', '-', '*', '/':
        tok_type = .Op
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
    SetVar,

    SetX, SetZ, SetPos, SetVz, SetVx, SetVel,
    ResetPos, ResetPosVel,

    OutXRaw, OutXBlock, OutXMM,
    OutZRaw, OutZBlock, OutZMM,

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
    Number, Text, Variable, Call
}

Arg :: struct {
    type: ArgType,
    value: f64,
    text: string,
    expr: Command,
}

makeCall :: proc(type: CmdType, entries: ..Arg) -> Command {
    cmd := Command{
        type = type,
    }
    append(&cmd.args, ..entries)
    return cmd
}

parseCommands :: proc(cmd: string) -> string {
    output: string = ""

    COMMAND_PREFIX :: ";s"
    prefix := COMMAND_PREFIX
    prefix_len := len(prefix)

    if len(cmd) < prefix_len || cmd[:prefix_len] != prefix do return output

    p := Parser{
        lex = Lexer{
            data = cmd,
            pos = prefix_len,
            nextOk = false,
        },
        err = .None,
    }

    if lexerPeek(&p.lex).type == .EOF do return output

    // Start to recursively parseExpr

    expr := parseArg(&p, 0)

    return output
}

ParseError :: enum {
    None, 
    MissingRParen,
    UnexpectedToken,
    InvalidPrefixToken,
    DivisionByZero,
    InvalidNumber,
    InvalidCommand,
}

Parser :: struct {
    lex: Lexer,
    err: ParseError,
}

parseArg :: proc(p: ^Parser, minBP: int) -> Arg{
    if p.err != .None do return Arg{}
    lhs: Arg

    prefix := lexerNext(&p.lex)

    #partial switch prefix.type {
        case .Number:
            lhs = parseNumber(p, prefix)
            if p.err != .None do return Arg{}
        case .Text:
            lhs.type = .Text
            lhs.text = prefix.content
        case .Identifier:
            // this one is versatile
            lhs = parseIdentifier(p, prefix)
            if p.err != .None do return Arg{}
        case .Op:
            if prefix.content == "-" {
                unaryMinusBP :: 30
                rhs := parseArg(p, unaryMinusBP)
                if p.err != .None do return Arg{}
                NEG_ONE :: Arg{type = .Number, value = -1}
                MULT_TOKEN :: Token{type = .Op, content = "*"}
                lhs = combine(p, NEG_ONE, rhs, MULT_TOKEN)
            }else{
                p.err = .InvalidPrefixToken
                return Arg{}
            }
        case .LParen:
            lhs = parseArg(p, 0)
            if p.err != .None do return Arg{}
            if lexerNext(&p.lex).type != .RParen {
                p.err = .MissingRParen
                return Arg{}
            }
        case .Pipe:
            lhs = Arg{
                type = .Call,
                expr = Command{
                    type = .ResetPos
                }
            }
        case .DoublePipe:
            lhs = Arg{
                type = .Call,
                expr = Command{
                    type = .ResetPosVel
                }
            }
        case:
            p.err = .InvalidPrefixToken
            return Arg{}
    }

    if lhs.type != .Number && lhs.type != .Variable do return lhs

    for {
        op: Token = lexerPeek(&p.lex)

        if op.type != .Op do break 
        
        baseBP := getBP(op)

        if baseBP.left < minBP do break 
        lexerNext(&p.lex)

        rhs := parseArg(p, baseBP.right)
        if p.err != .None do return Arg{}

        lhs = combine(p, lhs, rhs, op)
        if p.err != .None do return Arg{}
    }

    return lhs
}

parseNumber :: proc(p: ^Parser, tok: Token) -> Arg {
    if p.err != .None do return Arg{}
    value, ok := strconv.parse_f64(tok.content)
    if !ok {
        p.err = .InvalidNumber
        return Arg{}
    }

    return Arg{
        type = .Number,
        value = value,
    }
}

parseIdentifier :: proc(p: ^Parser, tok: Token) -> Arg {
    if p.err != .None do return Arg{}

    // a command/function with parameters
    if lexerPeek(&p.lex).type == .LParen{
        lexerNext(&p.lex)

        cmd_type := getCommandType(tok.content)
        if cmd_type == .Invalid {
            p.err = .InvalidCommand
            return Arg{}
        }

        call := Command{type = cmd_type}

        if lexerPeek(&p.lex).type != .RParen{
            for {
                arg := parseArg(p, 0)
                if p.err != .None{
                    delete(call.args)
                    return Arg{}
                }

                append(&call.args, arg)

                next := lexerPeek(&p.lex)
                if next.type == .Comma {
                    lexerNext(&p.lex)
                    continue
                }
                if next.type == .RParen {
                    lexerNext(&p.lex)
                    break
                }

                p.err = .MissingRParen
                delete(call.args)
                return Arg{}
            }
        }else{
            lexerNext(&p.lex) // consume ')' immediately
        }

        return Arg{
            type = .Call,
            expr = call
        }
    }

    // No parenthesis -> variable or parameterless call
    cmd_type := getCommandType(tok.content)
    if cmd_type != .Invalid {
        return Arg{
            type = .Call,
            expr = Command{type = cmd_type}
        }
    }

    // variable
    return Arg{
        type = .Variable,
        text = tok.content
    }

}

getCommandType :: proc(cmdName: string) -> CmdType {
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
        case "xr":
            return .OutXRaw
        case "xb":
            return .OutXBlock
        case "xmm":
            return .OutXMM
        case "zr":
            return .OutZRaw
        case "zb":
            return .OutZBlock
        case "zmm":
            return .OutZMM
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

combine :: proc(p: ^Parser, lhs: Arg, rhs: Arg, op: Token) -> Arg {
    if p.err != .None do return Arg{}
    reducible := (lhs.type == .Number && rhs.type == .Number)
    switch op.content {
        case "+":
            if reducible{
                return Arg{type = .Number, value = lhs.value + rhs.value}
            }else{
                return Arg{
                    type = .Call,
                    expr = makeCall(.Plus, lhs, rhs)
                }
            }
        case "-":
            if reducible {
                return Arg{type = .Number, value = lhs.value - rhs.value}
            } else {
                return Arg{
                    type = .Call,
                    expr = makeCall(.Minus, lhs, rhs),
                }
            }

        case "*":
            if reducible {
                return Arg{type = .Number, value = lhs.value * rhs.value}
            } else {
                return Arg{
                    type = .Call,
                    expr = makeCall(.Mul, lhs, rhs),
                }
            }

        case "/":
            if reducible {
                if rhs.value == 0 {
                    p.err = .DivisionByZero
                    return Arg{}
                }
                return Arg{type = .Number, value = lhs.value / rhs.value}
            } else {
                return Arg{
                    type = .Call,
                    expr = makeCall(.Div, lhs, rhs),
                }
            }

        case:
            p.err = .UnexpectedToken
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