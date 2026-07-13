package main

import "base:runtime"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

CliResult :: struct {
    stdout: string,
    errMsg: string,
    ok: bool,
}

MacroExportResult :: enum {
    Success,
    Exists,
    Failed,
}

deleteCliResult :: proc(result: ^CliResult) {
    delete(result.stdout)
    delete(result.errMsg)
    result^ = {}
}

cliFailure :: proc(message: string) -> CliResult {
    return CliResult{errMsg = strings.clone(message)}
}

runMothmoticaCli :: proc(input: string, args: []string) -> CliResult {
    stdin_file, temp_err := os.create_temp_file("", "mothmotica-input-*.txt", {.Inheritable})
    if temp_err != nil do return cliFailure("Could not create temporary input file.")

    temp_name := strings.clone(os.name(stdin_file))
    defer delete(temp_name)
    defer os.remove(temp_name)
    defer os.close(stdin_file)

    stdin_text := fmt.tprintf("%s\n\n", input)
    _, write_err := os.write(stdin_file, transmute([]byte)stdin_text)
    if write_err != nil do return cliFailure("Could not write temporary input file.")
    os.seek(stdin_file, 0, .Start)

    exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
    if exe_dir_err != nil do return cliFailure("Could not find the GUI executable directory.")
    defer delete(exe_dir)

    cli_name := "mothmotica-cli"
    when ODIN_OS == .Windows {
        cli_name = "mothmotica-cli.exe"
    }

    cli_path, join_err := os.join_path({exe_dir, cli_name}, context.allocator)
    if join_err != nil do return cliFailure("Could not resolve mothmotica-cli path.")
    defer delete(cli_path)

    command: [dynamic]string
    defer delete(command)
    append(&command, cli_path)
    append(&command, ..args)

    desc := os.Process_Desc {
        working_dir = exe_dir,
        command = command[:],
        stdin = stdin_file,
    }

    proc_state, stdout, stderr, proc_err := os.process_exec(desc, context.allocator)
    defer delete(stdout)
    defer delete(stderr)

    if proc_err != nil {
        return cliFailure(fmt.tprintf("Could not run mothmotica-cli: %v", proc_err))
    }

    stderr_text := strings.trim_space(string(stderr))
    if stderr_text != "" do return cliFailure(stderr_text)
    if !proc_state.success {
        return cliFailure(fmt.tprintf("Mothmotica exited with code %d.", proc_state.exit_code))
    }

    return CliResult{
        stdout = strings.clone(string(stdout)),
        ok = true,
    }
}

runMothball :: proc(input: string, output: []byte) -> bool {
    if input == "" {
        bufferSet(output, "")
        return false
    }

    result := runMothmoticaCli(input, []string{"--once"})
    defer deleteCliResult(&result)
    if !result.ok {
        bufferSet(output, result.errMsg)
        return true
    }

    text := strings.trim_space(result.stdout)
    if text == "" {
        if strings.has_prefix(input, ";s") || strings.has_prefix(input, ";y") {
            bufferSet(output, "Mothmotica returned no output.")
            return true
        }
        bufferSet(output, "")
        return false
    }

    bufferSet(output, text)
    return true
}

exportMacro :: proc(
    state: ^AppState,
    input, name: string,
    macro_type: int,
    status: []byte,
    overwrite := false,
) -> MacroExportResult {
    trimmed_name := strings.trim_space(name)
    if trimmed_name == "" {
        bufferSet(status, "Macro name is required.")
        return .Failed
    }
    if strings.contains(trimmed_name, "/") || strings.contains(trimmed_name, "\\") {
        bufferSet(status, "Macro name cannot contain path separators.")
        return .Failed
    }

    type_name := "mpk" if macro_type == 0 else "cyv"
    extension := ".csv" if macro_type == 0 else ".json"
    filename := trimmed_name
    existing_ext := strings.to_lower(filepath.ext(filename))
    defer delete(existing_ext)
    if existing_ext == ".csv" || existing_ext == ".json" {
        filename = filename[:len(filename) - len(existing_ext)]
    }
    filename = strings.trim_space(filename)
    if filename == "" {
        bufferSet(status, "Macro name is required.")
        return .Failed
    }
    filename = fmt.tprintf("%s%s", filename, extension)

    dir, dir_err := macrosDir(state, macro_type)
    if dir_err != nil {
        bufferSet(status, "Could not resolve the macro export directory.")
        return .Failed
    }
    defer delete(dir)

    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        bufferSet(status, "Could not create the macro export directory.")
        return .Failed
    }

    path, path_err := os.join_path({dir, filename}, context.allocator)
    if path_err != nil {
        bufferSet(status, "Could not resolve the macro export path.")
        return .Failed
    }
    defer delete(path)

    if os.is_file(path) && !overwrite {
        bufferSet(status, fmt.tprintf("A macro named \"%s\" already exists.", filename))
        return .Exists
    }

    cli_result := runMothmoticaCli(input, []string{"--macro", type_name})
    defer deleteCliResult(&cli_result)
    if !cli_result.ok {
        bufferSet(status, cli_result.errMsg)
        return .Failed
    }

    if write_err := os.write_entire_file(path, transmute([]byte)cli_result.stdout); write_err != nil {
        bufferSet(status, "Could not write the macro file.")
        return .Failed
    }

    bufferSet(status, fmt.tprintf("Exported to %s", path))
    return .Success
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
