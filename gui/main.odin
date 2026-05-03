package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"

import im "../third_party/odin-imgui"
import "../third_party/odin-imgui/imgui_impl_glfw"
import "../third_party/odin-imgui/imgui_impl_opengl3"

import "vendor:glfw"
import gl "vendor:OpenGL"

code_font: ^im.Font
FONT_SIZE :: f32(18)
SIDE_PAD :: f32(28)
MESSAGE_GAP :: f32(10)
AVATAR_SIZE :: f32(38)
AVATAR_GAP :: f32(12)

AppState :: struct {
    msgs: [128]ChatMsg,
    msgCount: int,
    newMsgQ: bool,
    shiftEnterQ: bool,
    shiftEnterSignal: bool,
}

loadFonts :: proc(scale: f32) {
    io := im.GetIO()
    font_scale := max(scale, 1)
    font_path := "asset/fonts/JetBrainsMono-Regular.ttf"

    resolved: string
    if !os.is_file(font_path) {
        exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
        if exe_dir_err == nil {
            defer delete(exe_dir)
            joined, join_err := os.join_path({exe_dir, font_path}, context.allocator)
            if join_err == nil {
                resolved = joined
                if os.is_file(resolved) {
                    font_path = resolved
                }
            }
        }
    }
    defer if len(resolved) > 0 do delete(resolved)

    font_path_c := strings.clone_to_cstring(font_path)
    defer delete(font_path_c)
    code_font = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path_c, FONT_SIZE * font_scale)

    if code_font != nil {
        io.FontDefault = code_font
        io.FontGlobalScale = 1 / font_scale
    }
}

pushCodeFont :: proc() -> bool {
    if code_font != nil {
        im.PushFont(code_font)
        return true
    }
    return false
}

popFontIf :: proc(pushed: bool) {
    if pushed {
        im.PopFont()
    }
}

shiftEnterCallback :: proc "c" (data: ^im.InputTextCallbackData) -> c.int {
    submitted := cast(^bool)data.UserData
    if submitted == nil do return 0

    if .CallbackAlways in data.EventFlag && im.GetIO().KeyShift && im.IsKeyPressed(.Enter, false) {
        submitted^ = true
        return 0
    }

    if .CallbackCharFilter in data.EventFlag && im.GetIO().KeyShift {
        if data.EventChar == '\n' || data.EventChar == '\r' {
            submitted^ = true
            data.EventChar = 0
            return 1
        }
    }

    return 0
}

updateShortcuts :: proc(window: glfw.WindowHandle, state: ^AppState) {
    enter_down := glfw.GetKey(window, glfw.KEY_ENTER) == glfw.PRESS ||
                  glfw.GetKey(window, glfw.KEY_KP_ENTER) == glfw.PRESS
    shift_down := glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS ||
                  glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS
    down := enter_down && shift_down

    state.shiftEnterSignal = down && !state.shiftEnterQ
    state.shiftEnterQ = down
}

ChatMsg :: struct {
    text: [8192]byte,
    reply: [65536]byte,
    has_reply: bool,
    dirty: bool,
}

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

lineCount :: proc(text: string) -> int {
    if len(text) == 0 do return 1

    n := 1
    for ch in text {
        if ch == '\n' do n += 1
    }
    return n
}

drawAvatar :: proc(label: cstring, bg, ring, text_col: im.Vec4) {
    pos := im.GetCursorScreenPos()
    center := im.Vec2{pos.x + AVATAR_SIZE * 0.5, pos.y + AVATAR_SIZE * 0.5}
    radius := AVATAR_SIZE * 0.5
    draw_list := im.GetWindowDrawList()

    im.DrawList_AddCircleFilled(draw_list, center, radius, im.GetColorU32ImVec4(bg), 36)
    im.DrawList_AddCircle(draw_list, center, radius - 0.5, im.GetColorU32ImVec4(ring), 36, 1.5)

    text_size := im.CalcTextSize(label)
    text_pos := im.Vec2{
        center.x - text_size.x * 0.5,
        center.y - text_size.y * 0.5 - 0.5,
    }
    im.DrawList_AddText(draw_list, text_pos, im.GetColorU32ImVec4(text_col), label)
}

applyTheme :: proc() {
    im.StyleColorsDark()

    style := im.GetStyle()
    style.WindowRounding = 7
    style.ChildRounding = 6
    style.FrameRounding = 5
    style.GrabRounding = 4
    style.ScrollbarRounding = 6
    style.WindowBorderSize = 1
    style.FrameBorderSize = 1
    style.WindowPadding = {18, 14}
    style.FramePadding = {10, 7}
    style.ItemSpacing = {10, 9}

    c := &style.Colors
    c[im.Col.Text] = {0.93, 0.94, 0.97, 1}
    c[im.Col.TextDisabled] = {0.50, 0.53, 0.61, 1}
    c[im.Col.WindowBg] = {0.035, 0.037, 0.047, 1}
    c[im.Col.ChildBg] = {0.052, 0.055, 0.070, 1}
    c[im.Col.PopupBg] = {0.075, 0.080, 0.100, 1}
    c[im.Col.FrameBg] = {0.080, 0.086, 0.110, 1}
    c[im.Col.FrameBgHovered] = {0.105, 0.114, 0.150, 1}
    c[im.Col.FrameBgActive] = {0.125, 0.140, 0.190, 1}
    c[im.Col.Button] = {0.145, 0.170, 0.235, 1}
    c[im.Col.ButtonHovered] = {0.205, 0.245, 0.340, 1}
    c[im.Col.ButtonActive] = {0.290, 0.350, 0.520, 1}
    c[im.Col.Header] = {0.145, 0.170, 0.235, 1}
    c[im.Col.HeaderHovered] = {0.205, 0.245, 0.340, 1}
    c[im.Col.HeaderActive] = {0.290, 0.350, 0.520, 1}
    c[im.Col.Border] = {0.230, 0.255, 0.330, 1}
    c[im.Col.Separator] = {0.185, 0.205, 0.270, 1}
}

runMothball :: proc(input: string, output: []byte) {
    if input == "" {
        bufferSet(output, "Nothing to run.")
        return
    }

    stdin_file, temp_err := os.create_temp_file("", "mothmotica-input-*.txt")
    if temp_err != nil {
        bufferSet(output, "Could not create temporary input file.")
        return
    }

    temp_name := strings.clone(os.name(stdin_file))
    defer delete(temp_name)
    defer os.remove(temp_name)
    defer os.close(stdin_file)

    stdin_text := fmt.tprintf("%s\n\n", input)
    _, write_err := os.write(stdin_file, transmute([]byte)stdin_text)
    if write_err != nil {
        bufferSet(output, "Could not write temporary input file.")
        return
    }
    os.seek(stdin_file, 0, .Start)

    exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
    if exe_dir_err != nil {
        bufferSet(output, "Could not find the GUI executable directory.")
        return
    }
    defer delete(exe_dir)

    cli_path, join_err := os.join_path({exe_dir, "src.bin"}, context.allocator)
    if join_err != nil {
        bufferSet(output, "Could not resolve src.bin path.")
        return
    }
    defer delete(cli_path)

    command := []string{cli_path}
    desc := os.Process_Desc {
        working_dir = exe_dir,
        command = command,
        stdin = stdin_file,
    }

    proc_state, stdout, stderr, proc_err := os.process_exec(desc, context.allocator)
    defer delete(stdout)
    defer delete(stderr)

    if proc_err != nil {
        bufferSet(output, "Could not run src.bin. Build it with `odin build src -out:src.bin`.")
        return
    }

    if len(stderr) > 0 {
        bufferSet(output, string(stderr))
        return
    }

    if !proc_state.success {
        bufferSet(output, fmt.tprintf("Mothmotica exited with code %d.", proc_state.exit_code))
        return
    }

    bufferSet(output, cliOutput(string(stdout)))
}

refreshMsg :: proc(msg: ^ChatMsg) {
    input := strings.trim_space(bufferString(msg.text[:]))
    if strings.has_prefix(input, ";s") {
        msg.has_reply = true
        runMothball(input, msg.reply[:])
    } else {
        msg.has_reply = false
        bufferSet(msg.reply[:], "")
    }
    msg.dirty = false
}

addMsg :: proc(state: ^AppState) {
    if state.msgCount == 0 do return

    draft := &state.msgs[state.msgCount - 1]
    input := strings.trim_space(bufferString(draft.text[:]))
    if input == "" do return

    bufferSet(draft.text[:], input)
    refreshMsg(draft)
    appendEmptyMsg(state)
    state.newMsgQ = true
}

commitMsg :: proc(state: ^AppState, idx: int, is_draft: bool) {
    if idx < 0 || idx >= state.msgCount do return

    msg := &state.msgs[idx]
    trimmed := strings.trim_space(bufferString(msg.text[:]))
    bufferSet(msg.text[:], trimmed)

    if is_draft {
        addMsg(state)
    } else {
        refreshMsg(msg)
    }
}

deleteMsg :: proc(state: ^AppState, idx: int) {
    if idx < 0 || idx >= state.msgCount do return

    for i in idx..<state.msgCount - 1 {
        state.msgs[i] = state.msgs[i + 1]
    }
    state.msgCount -= 1
    ensureDraftMsg(state)
}

appendEmptyMsg :: proc(state: ^AppState) {
    if state.msgCount >= len(state.msgs) {
        copy(state.msgs[:len(state.msgs)-1], state.msgs[1:])
        state.msgCount = len(state.msgs) - 1
    }

    msg := &state.msgs[state.msgCount]
    msg^ = ChatMsg{}
    state.msgCount += 1
}

ensureDraftMsg :: proc(state: ^AppState) {
    if state.msgCount == 0 {
        appendEmptyMsg(state)
    }
}

drawReply :: proc(msg: ^ChatMsg) {
    if !msg.has_reply do return

    im.Dummy({0, 8})
    drawAvatar("M", {0.25, 0.46, 0.90, 1}, {0.46, 0.70, 1.0, 1}, {0.96, 0.98, 1.0, 1})
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

    im.TextColored({0.34, 0.66, 1.0, 1.0}, "Mothball")

    reply := bufferString(msg.reply[:])
    height := max(f32(lineCount(reply)) * im.GetTextLineHeight() + 14, 36)
    im.PushStyleColorImVec4(im.Col.FrameBg, {0.070, 0.076, 0.105, 1})
    im.PushStyleColorImVec4(im.Col.Border, {0.240, 0.285, 0.390, 1})
    im.PushStyleColorImVec4(im.Col.Text, {0.93, 0.94, 0.97, 1})
    pushed_code_font := pushCodeFont()
    im.InputTextMultiline("##reply", cstring(&msg.reply[0]), c.size_t(len(msg.reply)), {-1, height}, {.ReadOnly})
    popFontIf(pushed_code_font)
    im.PopStyleColor(3)
    im.Unindent(AVATAR_SIZE + AVATAR_GAP)
}

drawUserMsg :: proc(state: ^AppState, idx: int, is_draft: bool) {
    msg := &state.msgs[idx]
    im.PushIDInt(c.int(idx))

    im.Dummy({0, MESSAGE_GAP})
    drawAvatar("C", {0.78, 0.53, 0.16, 1}, {1.0, 0.79, 0.32, 1}, {0.07, 0.06, 0.04, 1})
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

    im.AlignTextToFramePadding()
    im.TextColored({0.95, 0.82, 0.25, 1.0}, "Curryocity")
    if !is_draft {
        im.SameLine()
        if im.Button("Delete") {
            deleteMsg(state, idx)
            im.Unindent(AVATAR_SIZE + AVATAR_GAP)
            im.PopID()
            return
        }
    }

    text := bufferString(msg.text[:])
    height := max(f32(lineCount(text)) * im.GetTextLineHeight() + 14, 36)
    im.PushStyleColorImVec4(im.Col.FrameBg, is_draft ? im.Vec4{0.085, 0.092, 0.125, 1} : im.Vec4{0.055, 0.060, 0.080, 1})
    im.PushStyleColorImVec4(im.Col.Border, is_draft ? im.Vec4{0.380, 0.450, 0.620, 1} : im.Vec4{0.230, 0.255, 0.330, 1})
    pushed_code_font := pushCodeFont()
    submit := false
    changed := im.InputTextMultiline(
        "##message",
        cstring(&msg.text[0]),
        c.size_t(len(msg.text)),
        {-1, height},
        {.AllowTabInput, .CallbackAlways, .CallbackCharFilter},
        shiftEnterCallback,
        &submit,
    )
    item_active := im.IsItemActive()
    item_hovered := im.IsItemHovered(im.HoveredFlags_RectOnly)
    deactivated_after_edit := im.IsItemDeactivatedAfterEdit()
    popFontIf(pushed_code_font)
    if changed {
        msg.dirty = true
    }
    im.PopStyleColor(2)

    clicked_outside := item_active &&
                       msg.dirty &&
                       im.IsMouseClicked(.Left, false) &&
                       !item_hovered

    if submit || (item_active && state.shiftEnterSignal) || deactivated_after_edit || clicked_outside {
        commitMsg(state, idx, is_draft)
    }

    im.Unindent(AVATAR_SIZE + AVATAR_GAP)
    drawReply(msg)
    im.PopID()
}

drawIntro :: proc() {
    im.Dummy({0, 24})

    im.SetWindowFontScale(2.2)
    title_size := im.CalcTextSize("Mothmotica")
    title_x := max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD)
    im.SetCursorPosX(title_x)
    im.TextColored({0.93, 0.95, 1.0, 1.0}, "Mothmotica")
    im.SetWindowFontScale(1)

    im.Dummy({0, 14})
    im.Separator()
    im.Dummy({0, 10})
}

draw :: proc(state: ^AppState) {
    viewport := im.GetMainViewport()
    im.SetNextWindowPos(viewport.Pos)
    im.SetNextWindowSize(viewport.Size)

    flags := im.WindowFlags_NoDecoration | im.WindowFlags{.NoMove, .NoResize, .NoCollapse}
    if im.Begin("Mothmotica", nil, flags) {
        total := im.GetContentRegionAvail()

        if im.BeginChild("ChatLog", total, {}, {.HorizontalScrollbar}) {
            drawIntro()
            im.Indent(SIDE_PAD)
            for i in 0..<state.msgCount {
                is_draft := i == state.msgCount - 1
                drawUserMsg(state, i, is_draft)
            }
            im.Unindent(SIDE_PAD)

            if state.newMsgQ {
                im.SetScrollHereY(1.0)
                state.newMsgQ = false
            }
        }
        im.EndChild()
    }
    im.End()
}

main :: proc() {
    assert(cast(bool)glfw.Init())
    defer glfw.Terminate()

    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 2)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1)

    window := glfw.CreateWindow(1100, 720, "Mothmotica", nil, nil)
    assert(window != nil)
    defer glfw.DestroyWindow(window)

    glfw.MakeContextCurrent(window)
    glfw.SwapInterval(1)

    gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
        (cast(^rawptr)p)^ = glfw.GetProcAddress(name)
    })

    im.CHECKVERSION()
    im.CreateContext()
    defer im.DestroyContext()

    io := im.GetIO()
    io.ConfigFlags += {.NavEnableKeyboard}
    xscale, yscale := glfw.GetWindowContentScale(window)
    loadFonts(max(xscale, yscale))

    applyTheme()

    imgui_impl_glfw.InitForOpenGL(window, true)
    defer imgui_impl_glfw.Shutdown()
    imgui_impl_opengl3.Init("#version 150")
    defer imgui_impl_opengl3.Shutdown()

    state := new(AppState)
    defer free(state)
    appendEmptyMsg(state)
    bufferSet(state.msgs[0].text[:], ";s sj45(12) zmm")

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        updateShortcuts(window, state)

        imgui_impl_opengl3.NewFrame()
        imgui_impl_glfw.NewFrame()
        im.NewFrame()
        ensureDraftMsg(state)

        draw(state)

        im.Render()
        display_w, display_h := glfw.GetFramebufferSize(window)
        gl.Viewport(0, 0, display_w, display_h)
        gl.ClearColor(0.04, 0.04, 0.04, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

        glfw.SwapBuffers(window)
    }
}
