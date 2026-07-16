package main

import "core:fmt"
import "core:os"
import "core:strings"

runMacroOutput :: proc(input, type_name: string) {
    macro_type: MacroType
    lower_type_name := strings.to_lower(type_name)
    defer delete(lower_type_name)
    switch lower_type_name {
    case "mpk":
        macro_type = .Mpk
    case "cyv":
        macro_type = .Cyv
    case:
        fmt.eprintf("Unknown macro type: %s\n", type_name)
        os.exit(1)
    }

    result := parseMothballResult(input)
    defer deleteParseResult(&result)

    if !result.ok {
        fmt.eprint(result.output)
        os.exit(1)
    }
    if result.ctx != .XZsim && result.ctx != .XYZsim {
        fmt.eprintln("Macro export is only supported for XZ and XYZ simulations.")
        os.exit(1)
    }

    output := serializeMacro(result.macro, macro_type)
    defer delete(output)
    fmt.print(output)
}

main :: proc(){
    bake_trig() // do not forget

    buf: [65536]byte

    if len(os.args) > 1 && (os.args[1] == "--once" || os.args[1] == "--macro") {
        data, err := os.read_entire_file_from_file(os.stdin, context.allocator)
        if err != nil do return
        defer delete(data)

        input := strings.trim_space(string(data))
        if os.args[1] == "--macro" {
            if len(os.args) < 3 {
                fmt.eprintln("Macro type is required: mpk or cyv.")
                os.exit(1)
            }
            runMacroOutput(input, os.args[2])
            return
        }

        output := parseMothball(input)
        if output != "" {
            fmt.print(output)
        }
        return
    }

    for {
        fmt.println("Chat:")
        
        n, err := os.read(os.stdin, buf[:])
        if err != nil {
            fmt.println("read failed:", err)
            return
        }

        input := strings.trim_space(string(buf[:n]))

        if input == "" do break

        output := parseMothball(input)

        fmt.println()
        if(output != ""){
            fmt.println("Mothball:")
            fmt.println(output)
        }

    }

}
