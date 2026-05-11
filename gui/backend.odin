package main

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:strings"

runMothball :: proc(input: string, output: []byte) -> bool {
    if input == "" {
        bufferSet(output, "")
        return false
    }

    stdin_file, temp_err := os.create_temp_file("", "mothmotica-input-*.txt", {.Inheritable})
    if temp_err != nil {
        bufferSet(output, "Could not create temporary input file.")
        return true
    }

    temp_name := strings.clone(os.name(stdin_file))
    defer delete(temp_name)
    defer os.remove(temp_name)
    defer os.close(stdin_file)

    stdin_text := fmt.tprintf("%s\n\n", input)
    _, write_err := os.write(stdin_file, transmute([]byte)stdin_text)
    if write_err != nil {
        bufferSet(output, "Could not write temporary input file.")
        return true
    }
    os.seek(stdin_file, 0, .Start)

    exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
    if exe_dir_err != nil {
        bufferSet(output, "Could not find the GUI executable directory.")
        return true
    }
    defer delete(exe_dir)

    cli_name := "mothmotica-cli"
    when ODIN_OS == .Windows {
        cli_name = "mothmotica-cli.exe"
    }

    cli_path, join_err := os.join_path({exe_dir, cli_name}, context.allocator)
    if join_err != nil {
        bufferSet(output, "Could not resolve mothmotica-cli path.")
        return true
    }
    defer delete(cli_path)

    command := []string{cli_path, "--once"}
    desc := os.Process_Desc {
        working_dir = exe_dir,
        command = command,
        stdin = stdin_file,
    }

    proc_state, stdout, stderr, proc_err := os.process_exec(desc, context.allocator)
    defer delete(stdout)
    defer delete(stderr)

    if proc_err != nil {
        bufferSet(output, fmt.tprintf("Could not run mothmotica-cli: %v", proc_err))
        return true
    }

    if len(stderr) > 0 {
        bufferSet(output, string(stderr))
        return true
    }

    if !proc_state.success {
        bufferSet(output, fmt.tprintf("Mothmotica exited with code %d.", proc_state.exit_code))
        return true
    }

    result := strings.trim_space(string(stdout))
    if result == "" {
        if strings.has_prefix(input, ";s") || strings.has_prefix(input, ";y") {
            bufferSet(output, "Mothmotica returned no output.")
            return true
        }
        bufferSet(output, "")
        return false
    }

    bufferSet(output, result)
    return true
}

cliOutput :: proc(stdout: string) -> string {
    marker := "Mothball:\n"
    idx := strings.index(stdout, marker)
    if idx < 0 {
        return strings.trim_space(stdout)
    }

    result := stdout[idx + len(marker):]
    next_prompt := strings.index(result, "\n\nChat:")
    if next_prompt >= 0 {
        result = result[:next_prompt]
    }
    return strings.trim_space(result)
}
