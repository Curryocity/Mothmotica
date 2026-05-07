package main

import "core:strings"


bufferString :: proc(buf: []byte) -> string {
    end := 0
    for end < len(buf) && buf[end] != 0 {
        end += 1
    }
    return string(buf[:end])
}

bufferSet :: proc(buf: []byte, text: string) {
    if len(buf) == 0 do return

    src := strings.clone(text)
    defer delete(src)

    for i in 0..<len(buf) {
        buf[i] = 0
    }

    n := min(len(buf) - 1, len(src))
    copy(buf[:n], transmute([]byte)src[:n])
}




