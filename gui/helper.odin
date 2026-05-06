package main

import "base:runtime"

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import im "../third_party/odin-imgui"
import "vendor:glfw"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

code_font: ^im.Font
bot_avatar_texture: u32
player_avatar_texture: u32
FONT_SIZE :: f32(18)
SIDE_PAD :: f32(28)
MESSAGE_GAP :: f32(10)
AVATAR_SIZE :: f32(38)
AVATAR_GAP :: f32(12)
MAX_NOTES :: 12
MAX_MSGS :: 128
NOTE_TITLE_SIZE :: 128
PATH_SIZE :: 1024
BOOKS_DIR :: "books"
SETTINGS_PATH :: "mothmotica-settings.json"
BOT_AVATAR_PATH :: "asset/image/mothballpfp.png"
USER_AVATAR_DIR :: "user_data/avatar"
PLAYER_AVATAR_PATH :: "user_data/avatar/player_avatar.png"
SIDEBAR_WIDTH :: f32(240)
AUTOSAVE_INTERVAL_SECONDS :: f64(1.0)

REPO_URL :: "https://github.com/Curryocity/Mothmotica"

SendHotkey :: enum {
    Enter,
    Shift_Enter,
}

Theme :: enum {
    Dark,
    Soft,
    Light,
}

AppState :: struct {
    notes: [MAX_NOTES]Note,
    noteCount: int,
    activeNote: int,
    nextNoteID: int,
    showHome: bool,
    showSettings: bool,
    showStarred: bool,
    showCreateBookDialog: bool,
    showOpenBookDialog: bool,
    openPath: [PATH_SIZE]byte,
    bookNameInput: [NOTE_TITLE_SIZE]byte,
    currentBookPath: [PATH_SIZE]byte,
    currentBookName: [NOTE_TITLE_SIZE]byte,
    openStatus: [256]byte,
    saveStatus: [256]byte,
    settingsStatus: [256]byte,
    titleEdit: [NOTE_TITLE_SIZE]byte,
    playerName: [NOTE_TITLE_SIZE]byte,
    botName: [NOTE_TITLE_SIZE]byte,
    playerAvatarPath: [PATH_SIZE]byte,
    sendHotkey: SendHotkey,
    theme: Theme,
    settingsDirty: bool,
    editingTitleNote: int,
    newMsgQ: bool,
    shiftEnterQ: bool,
    shiftEnterSignal: bool,
}

SubmitHotkeyData :: struct {
    state: ^AppState,
    submitted: ^bool,
}

Note :: struct {
    id: int,
    title: [NOTE_TITLE_SIZE]byte,
    path: [PATH_SIZE]byte,
    msgs: [MAX_MSGS]ChatMsg,
    msgCount: int,
    dirty: bool,
}

SavedNote :: struct {
    version: int,
    id: int,
    messages: []SavedMessage,
}

SavedMessage :: struct {
    text: string,
    reply: string,
    has_reply: bool,
    starred: bool,
}

SavedSettings :: struct {
    version: int,
    player_name: string,
    bot_name: string,
    player_avatar_path: string,
    send_hotkey: int,
    theme: int,
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

resolveAssetPath :: proc(path: string) -> string {
    if os.is_file(path) {
        return strings.clone(path)
    }

    exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
    if exe_dir_err != nil {
        return strings.clone(path)
    }
    defer delete(exe_dir)

    joined, join_err := os.join_path({exe_dir, path}, context.allocator)
    if join_err != nil {
        return strings.clone(path)
    }
    return joined
}

loadTextureRGBA :: proc(path: string) -> u32 {
    resolved := resolveAssetPath(path)
    defer delete(resolved)

    path_c := strings.clone_to_cstring(resolved)
    defer delete(path_c)

    width, height, channels: c.int
    pixels := stbi.load(path_c, &width, &height, &channels, 4)
    if pixels == nil || width <= 0 || height <= 0 {
        return 0
    }
    defer stbi.image_free(pixels)

    texture: u32
    gl.GenTextures(1, &texture)
    if texture == 0 {
        return 0
    }

    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.TexImage2D(gl.TEXTURE_2D, 0, i32(gl.RGBA), width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, rawptr(pixels))
    gl.BindTexture(gl.TEXTURE_2D, 0)
    return texture
}

loadBotAvatarTexture :: proc() {
    bot_avatar_texture = loadTextureRGBA(BOT_AVATAR_PATH)
}

destroyBotAvatarTexture :: proc() {
    if bot_avatar_texture != 0 {
        gl.DeleteTextures(1, &bot_avatar_texture)
        bot_avatar_texture = 0
    }
}

loadPlayerAvatarTexture :: proc(state: ^AppState) -> bool {
    path := strings.trim_space(bufferString(state.playerAvatarPath[:]))
    if path == "" {
        destroyPlayerAvatarTexture()
        return false
    }

    texture := loadTextureRGBA(path)
    if texture == 0 {
        return false
    }

    destroyPlayerAvatarTexture()
    player_avatar_texture = texture
    return true
}

usePlayerAvatarImage :: proc(state: ^AppState) -> bool {
    source := strings.trim_space(bufferString(state.playerAvatarPath[:]))
    if source == "" || !os.is_file(source) {
        return false
    }

    if mkdir_err := os.make_directory_all(USER_AVATAR_DIR); mkdir_err != nil && !os.is_dir(USER_AVATAR_DIR) {
        return false
    }

    if copy_err := os.copy_file(PLAYER_AVATAR_PATH, source); copy_err != nil {
        return false
    }

    bufferSet(state.playerAvatarPath[:], PLAYER_AVATAR_PATH)
    if !loadPlayerAvatarTexture(state) {
        return false
    }

    state.settingsDirty = true
    return true
}

destroyPlayerAvatarTexture :: proc() {
    if player_avatar_texture != 0 {
        gl.DeleteTextures(1, &player_avatar_texture)
        player_avatar_texture = 0
    }
}

sendHotkeyDown :: proc(state: ^AppState) -> bool {
    io := im.GetIO()
    if state != nil && state.sendHotkey == .Shift_Enter {
        return io.KeyShift
    }
    return !io.KeyShift
}

submitHotkeyCallback :: proc "c" (data: ^im.InputTextCallbackData) -> c.int {
    context = runtime.default_context()

    payload := cast(^SubmitHotkeyData)data.UserData
    if payload == nil || payload.submitted == nil do return 0

    if .CallbackAlways in data.EventFlag && sendHotkeyDown(payload.state) && im.IsKeyPressed(.Enter, false) {
        payload.submitted^ = true
        return 0
    }

    if .CallbackCharFilter in data.EventFlag && sendHotkeyDown(payload.state) {
        if data.EventChar == '\n' || data.EventChar == '\r' {
            payload.submitted^ = true
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
    wants_shift := state.sendHotkey == .Shift_Enter
    down := enter_down && (shift_down == wants_shift)

    state.shiftEnterSignal = down && !state.shiftEnterQ
    state.shiftEnterQ = down
}

ChatMsg :: struct {
    text: [8192]byte,
    reply: [65536]byte,
    has_reply: bool,
    dirty: bool,
    starred: bool,
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

noteTitle :: proc(note: ^Note) -> string {
    path := bufferString(note.path[:])
    if path != "" {
        stem := filepath.stem(path)
        if stem != "" do return stem
    }

    title := strings.trim_space(bufferString(note.title[:]))
    if title == "" do return "untitled-note"
    return title
}

activeNote :: proc(state: ^AppState) -> ^Note {
    if state.noteCount == 0 do return nil
    state.activeNote = min(max(state.activeNote, 0), state.noteCount - 1)
    return &state.notes[state.activeNote]
}

appendEmptyMsg :: proc(note: ^Note) {
    if note.msgCount >= len(note.msgs) {
        copy(note.msgs[:len(note.msgs)-1], note.msgs[1:])
        note.msgCount = len(note.msgs) - 1
    }

    msg := &note.msgs[note.msgCount]
    msg^ = ChatMsg{}
    note.msgCount += 1
}

ensureDraftMsg :: proc(note: ^Note) {
    if note != nil && note.msgCount == 0 {
        appendEmptyMsg(note)
    }
}

createNote :: proc(state: ^AppState) -> ^Note {
    if state.noteCount >= len(state.notes) {
        state.activeNote = len(state.notes) - 1
        return &state.notes[state.activeNote]
    }

    idx := state.noteCount
    note := &state.notes[idx]
    note^ = Note{}
    for {
        note.id = state.nextNoteID
        path, path_err := defaultNotePath(state, note)
        if path_err != nil {
            break
        }
        exists := os.is_file(path)
        delete(path)
        if !exists {
            break
        }
        state.nextNoteID += 1
    }
    bufferSet(note.title[:], fmt.tprintf("note-%d", note.id))
    state.nextNoteID += 1
    appendEmptyMsg(note)
    note.dirty = true

    state.noteCount += 1
    state.activeNote = idx
    state.showHome = false
    state.showStarred = false
    state.newMsgQ = true
    return note
}

openFirstNote :: proc(state: ^AppState) {
    if state.noteCount == 0 {
        createNote(state)
        return
    }
    state.activeNote = min(max(state.activeNote, 0), state.noteCount - 1)
    state.showHome = false
    state.showStarred = false
}

realMessageCount :: proc(note: ^Note) -> int {
    if note == nil do return 0
    return max(note.msgCount - 1, 0)
}

messageCount :: proc(note: ^Note) -> int {
    return realMessageCount(note)
}

starredCount :: proc(note: ^Note) -> int {
    if note == nil do return 0

    count := 0
    for i in 0..<realMessageCount(note) {
        if note.msgs[i].starred do count += 1
    }
    return count
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

avatarLabel :: proc(name: string, fallback: byte) -> [2]byte {
    label := [2]byte{fallback, 0}
    trimmed := strings.trim_space(name)
    if len(trimmed) > 0 {
        label[0] = trimmed[0]
    }
    return label
}

drawAvatar :: proc(label: cstring, bg, ring, text_col: im.Vec4) {
    pos := im.GetCursorScreenPos()
    center := im.Vec2{pos.x + AVATAR_SIZE * 0.5, pos.y + AVATAR_SIZE * 0.5}
    radius := AVATAR_SIZE * 0.5
    draw_list := im.GetWindowDrawList()

    im.DrawList_AddCircleFilled(draw_list, center, radius, im.GetColorU32ImVec4(bg), 36)
    im.DrawList_AddCircle(draw_list, center, radius - 0.5, im.GetColorU32ImVec4(ring), 36, 1.5)

    font := im.GetFont()
    font_size := im.GetFontSize()
    text_size := im.CalcTextSize(label)
    text_x := center.x - text_size.x * 0.5
    if font != nil && label != nil {
        label_bytes := cast(^u8)label
        glyph := im.Font_FindGlyph(font, im.Wchar(label_bytes^))
        if glyph != nil && font.FontSize > 0 {
            scale := font_size / font.FontSize
            text_x = center.x - (glyph.X0 + glyph.X1) * 0.5 * scale
        }
    }

    text_pos := im.Vec2{
        text_x,
        center.y - text_size.y * 0.5,
    }
    im.DrawList_AddText(draw_list, text_pos, im.GetColorU32ImVec4(text_col), label)
}

drawAvatarImage :: proc(texture: u32) {
    pos := im.GetCursorScreenPos()
    p_min := pos
    p_max := im.Vec2{pos.x + AVATAR_SIZE, pos.y + AVATAR_SIZE}
    radius := AVATAR_SIZE * 0.5
    draw_list := im.GetWindowDrawList()

    im.DrawList_AddImageRounded(
        draw_list,
        im.TextureID(texture),
        p_min,
        p_max,
        {0, 0},
        {1, 1},
        0xff_ff_ff_ff,
        radius,
        im.DrawFlags_RoundCornersAll,
    )
}

titleColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.120, 0.145, 0.190, 1}
    }
    return {0.93, 0.95, 1.0, 1.0}
}

mutedColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.365, 0.400, 0.475, 1}
    }
    return {0.50, 0.53, 0.61, 1}
}

bookColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.270, 0.345, 0.500, 1}
    }
    return {0.62, 0.68, 0.78, 1}
}

playerNameColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.490, 0.295, 0.030, 1}
    }
    return {0.95, 0.82, 0.25, 1.0}
}

botNameColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.330, 0.210, 0.560, 1}
    }
    return {0.640, 0.540, 0.940, 1.0}
}

messageBoxBgColor :: proc(theme: Theme, is_draft: bool) -> im.Vec4 {
    if theme == .Light {
        return is_draft ? im.Vec4{0.965, 0.970, 0.982, 1} : im.Vec4{0.935, 0.942, 0.958, 1}
    }
    return is_draft ? im.Vec4{0.085, 0.092, 0.125, 1} : im.Vec4{0.055, 0.060, 0.080, 1}
}

messageBoxBorderColor :: proc(theme: Theme, is_draft: bool) -> im.Vec4 {
    if theme == .Light {
        return is_draft ? im.Vec4{0.720, 0.755, 0.825, 1} : im.Vec4{0.780, 0.800, 0.850, 1}
    }
    return is_draft ? im.Vec4{0.380, 0.450, 0.620, 1} : im.Vec4{0.230, 0.255, 0.330, 1}
}

messageBoxTextColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.080, 0.090, 0.115, 1}
    }
    return {0.93, 0.94, 0.97, 1}
}

applyTheme :: proc(theme: Theme) {
    if theme == .Light {
        im.StyleColorsLight()
    } else {
        im.StyleColorsDark()
    }

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
    if theme == .Light {
        c[im.Col.Text] = {0.115, 0.125, 0.150, 1}
        c[im.Col.TextDisabled] = {0.500, 0.535, 0.600, 1}
        c[im.Col.WindowBg] = {0.955, 0.960, 0.972, 1}
        c[im.Col.ChildBg] = {0.985, 0.987, 0.992, 1}
        c[im.Col.PopupBg] = {1.000, 1.000, 1.000, 1}
        c[im.Col.FrameBg] = {0.915, 0.925, 0.945, 1}
        c[im.Col.FrameBgHovered] = {0.875, 0.900, 0.940, 1}
        c[im.Col.FrameBgActive] = {0.820, 0.860, 0.925, 1}
        c[im.Col.Button] = {0.820, 0.865, 0.940, 1}
        c[im.Col.ButtonHovered] = {0.735, 0.800, 0.910, 1}
        c[im.Col.ButtonActive] = {0.635, 0.725, 0.880, 1}
        c[im.Col.Header] = {0.820, 0.865, 0.940, 1}
        c[im.Col.HeaderHovered] = {0.735, 0.800, 0.910, 1}
        c[im.Col.HeaderActive] = {0.635, 0.725, 0.880, 1}
        c[im.Col.Border] = {0.705, 0.735, 0.790, 1}
        c[im.Col.Separator] = {0.780, 0.805, 0.850, 1}
    } else if theme == .Soft {
        c[im.Col.Text] = {0.93, 0.94, 0.97, 1}
        c[im.Col.TextDisabled] = {0.50, 0.53, 0.61, 1}
        c[im.Col.WindowBg] = {0.060, 0.057, 0.068, 1}
        c[im.Col.ChildBg] = {0.082, 0.077, 0.092, 1}
        c[im.Col.PopupBg] = {0.095, 0.088, 0.106, 1}
        c[im.Col.FrameBg] = {0.115, 0.105, 0.128, 1}
        c[im.Col.FrameBgHovered] = {0.145, 0.135, 0.165, 1}
        c[im.Col.FrameBgActive] = {0.180, 0.158, 0.190, 1}
        c[im.Col.Button] = {0.185, 0.155, 0.205, 1}
        c[im.Col.ButtonHovered] = {0.255, 0.200, 0.285, 1}
        c[im.Col.ButtonActive] = {0.335, 0.245, 0.365, 1}
        c[im.Col.Header] = {0.185, 0.155, 0.205, 1}
        c[im.Col.HeaderHovered] = {0.255, 0.200, 0.285, 1}
        c[im.Col.HeaderActive] = {0.335, 0.245, 0.365, 1}
        c[im.Col.Border] = {0.315, 0.270, 0.335, 1}
        c[im.Col.Separator] = {0.260, 0.220, 0.285, 1}
    } else {
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

addMsg :: proc(state: ^AppState, note: ^Note) {
    if note == nil || note.msgCount == 0 do return

    draft := &note.msgs[note.msgCount - 1]
    input := strings.trim_space(bufferString(draft.text[:]))
    if input == "" do return

    bufferSet(draft.text[:], input)
    refreshMsg(draft)
    appendEmptyMsg(note)
    note.dirty = true
    state.newMsgQ = true
}

commitMsg :: proc(state: ^AppState, note: ^Note, idx: int, is_draft: bool) {
    if note == nil || idx < 0 || idx >= note.msgCount do return

    msg := &note.msgs[idx]
    trimmed := strings.trim_space(bufferString(msg.text[:]))
    bufferSet(msg.text[:], trimmed)

    if is_draft {
        addMsg(state, note)
    } else {
        refreshMsg(msg)
        note.dirty = true
    }
}

deleteMsg :: proc(note: ^Note, idx: int) {
    if note == nil || idx < 0 || idx >= note.msgCount do return

    for i in idx..<note.msgCount - 1 {
        note.msgs[i] = note.msgs[i + 1]
    }
    note.msgCount -= 1
    ensureDraftMsg(note)
    note.dirty = true
}
