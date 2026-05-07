package main

import "base:runtime"

import "core:fmt"
import "core:os"
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


openExternal :: proc(url: string, status: []byte) {
    command: []string
    when ODIN_OS == .Darwin {
        command = []string{"/usr/bin/open", url}
    } else when ODIN_OS == .Windows {
        command = []string{"cmd", "/c", "start", "", url}
    } else {
        command = []string{"xdg-open", url}
    }

    desc := os.Process_Desc{command = command}
    _, stdout, stderr, err := os.process_exec(desc, context.allocator)
    defer delete(stdout)
    defer delete(stderr)
    if err != nil {
        bufferSet(status, fmt.tprintf("Could not open %s", url))
        return
    }
    bufferSet(status, fmt.tprintf("Opening %s", url))
}

openCurrentBookFolder :: proc(state: ^AppState) {
    path := bufferString(state.currentBookPath[:])
    if path == "" || !os.is_dir(path) {
        bufferSet(state.saveStatus[:], "No open book folder to show.")
        return
    }
    openExternal(path, state.saveStatus[:])
}

openBooksFolder :: proc(state: ^AppState) {
    dir, dir_err := booksDir()
    if dir_err != nil {
        bufferSet(state.openStatus[:], "Could not resolve books folder.")
        return
    }
    defer delete(dir)

    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        bufferSet(state.openStatus[:], fmt.tprintf("Could not create books folder: %v", mkdir_err))
        return
    }
    openExternal(dir, state.openStatus[:])
}


