package main

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc(){
    bake_trig() // do not forget

    buf: [65536]byte

    if len(os.args) > 1 && os.args[1] == "--once" {
        n, err := os.read(os.stdin, buf[:])
        if err != nil do return

        input := strings.trim_space(string(buf[:n]))
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
