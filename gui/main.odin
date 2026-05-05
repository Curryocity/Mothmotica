package main

import "base:runtime"

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"

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
MAX_NOTES :: 12
MAX_MSGS :: 128
NOTE_TITLE_SIZE :: 128
PATH_SIZE :: 1024
BOOKS_DIR :: "books"
SETTINGS_PATH :: "mothmotica-settings.json"
SIDEBAR_WIDTH :: f32(240)

REPO_URL :: "https://github.com/Curryocity/Mothmotica"

SEND_HOTKEY_ENTER :: 0
SEND_HOTKEY_SHIFT_ENTER :: 1
THEME_DARK :: 0
THEME_SOFT :: 1
THEME_LIGHT :: 2

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
    titleEdit: [NOTE_TITLE_SIZE]byte,
    playerName: [NOTE_TITLE_SIZE]byte,
    botName: [NOTE_TITLE_SIZE]byte,
    sendHotkey: int,
    theme: int,
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

sendHotkeyDown :: proc(state: ^AppState) -> bool {
    io := im.GetIO()
    if state != nil && state.sendHotkey == SEND_HOTKEY_SHIFT_ENTER {
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
    wants_shift := state.sendHotkey == SEND_HOTKEY_SHIFT_ENTER
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

freeSavedSettings :: proc(settings: ^SavedSettings) {
    delete(settings.player_name)
    delete(settings.bot_name)
}

loadSettings :: proc(state: ^AppState) {
    data, read_err := os.read_entire_file(SETTINGS_PATH, context.allocator)
    if read_err != nil do return
    defer delete(data)

    saved: SavedSettings
    if json.unmarshal(data, &saved, allocator = context.allocator) != nil do return
    defer freeSavedSettings(&saved)

    if strings.trim_space(saved.player_name) != "" {
        bufferSet(state.playerName[:], saved.player_name)
    }
    if strings.trim_space(saved.bot_name) != "" {
        bufferSet(state.botName[:], saved.bot_name)
    }
    if saved.send_hotkey == SEND_HOTKEY_ENTER || saved.send_hotkey == SEND_HOTKEY_SHIFT_ENTER {
        state.sendHotkey = saved.send_hotkey
    }
    if saved.theme == THEME_DARK || saved.theme == THEME_SOFT || saved.theme == THEME_LIGHT {
        state.theme = saved.theme
    }
    state.settingsDirty = false
}

saveSettings :: proc(state: ^AppState) {
    saved := SavedSettings {
        version = 1,
        player_name = bufferString(state.playerName[:]),
        bot_name = bufferString(state.botName[:]),
        send_hotkey = state.sendHotkey,
        theme = state.theme,
    }

    data, marshal_err := json.marshal(saved, {pretty = true}, context.allocator)
    if marshal_err != nil do return
    defer delete(data)

    if os.write_entire_file(SETTINGS_PATH, data) == nil {
        state.settingsDirty = false
    }
}

saveDirtySettings :: proc(state: ^AppState) {
    if state.settingsDirty {
        saveSettings(state)
    }
}

booksDir :: proc() -> (string, os.Error) {
    return os.get_absolute_path(BOOKS_DIR, context.allocator)
}

bookPagesDir :: proc(state: ^AppState) -> (string, os.Error) {
    path := bufferString(state.currentBookPath[:])
    if path == "" {
        return "", os.General_Error.Not_Exist
    }
    return strings.clone(path), nil
}

defaultNotePath :: proc(state: ^AppState, note: ^Note) -> (string, os.Error) {
    dir, dir_err := bookPagesDir(state)
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)
    return os.join_path({dir, fmt.tprintf("note-%d.json", note.id)}, context.allocator)
}

notePath :: proc(state: ^AppState, note: ^Note) -> (string, os.Error) {
    path := bufferString(note.path[:])
    if len(path) > 0 {
        return strings.clone(path), nil
    }
    return titleNotePath(state, note, noteTitle(note))
}

noteFilenameSlug :: proc(title: string) -> string {
    b := strings.builder_make()
    wrote := false
    last_dash := false

    for r in strings.trim_space(title) {
        if unicode.is_letter(r) || unicode.is_digit(r) {
            strings.write_rune(&b, unicode.to_lower(r))
            wrote = true
            last_dash = false
        } else if wrote && !last_dash {
            strings.write_byte(&b, '-')
            last_dash = true
        }
    }

    result := strings.to_string(b)
    if len(result) > 0 && result[len(result) - 1] == '-' {
        result = result[:len(result) - 1]
    }
    if len(result) == 0 {
        strings.write_string(&b, "untitled-note")
        result = strings.to_string(b)
    }
    return strings.clone(result)
}

titleNotePath :: proc(state: ^AppState, note: ^Note, title: string) -> (string, os.Error) {
    dir, dir_err := bookPagesDir(state)
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    slug := noteFilenameSlug(title)
    defer delete(slug)

    candidate: string
    for n := 0; ; n += 1 {
        filename := fmt.tprintf("%s.json", slug) if n == 0 else fmt.tprintf("%s-%d.json", slug, n + 1)
        path, path_err := os.join_path({dir, filename}, context.allocator)
        if path_err != nil {
            return "", path_err
        }

        current := bufferString(note.path[:])
        if !os.is_file(path) || path == current {
            candidate = path
            break
        }
        delete(path)
    }
    return candidate, nil
}

renameNoteFileToTitle :: proc(state: ^AppState, note: ^Note, title: string, status: []byte) {
    if note == nil do return

    old_path := bufferString(note.path[:])
    if old_path == "" && !noteHasContent(note) {
        bufferSet(note.title[:], title)
        note.dirty = false
        bufferSet(status, "")
        return
    } else if old_path == "" {
        bufferSet(note.title[:], title)
        note.dirty = true
        saveNote(state, note, status)
        return
    }

    new_path, path_err := titleNotePath(state, note, title)
    if path_err != nil {
        bufferSet(status, "Could not resolve renamed note path.")
        return
    }
    defer delete(new_path)

    if old_path == new_path {
        bufferSet(status, "Filename already matches the note title.")
        return
    }

    if rename_err := os.rename(old_path, new_path); rename_err != nil {
        bufferSet(status, fmt.tprintf("Could not rename note file: %v", rename_err))
        return
    }

    bufferSet(note.path[:], new_path)
    bufferSet(note.title[:], filepath.stem(new_path))
    note.dirty = true
    saveNote(state, note, status)
}

setNoteFilename :: proc(state: ^AppState, note: ^Note, title: string, status: []byte) {
    if note == nil do return

    current_title := noteTitle(note)
    new_title := strings.trim_space(title)
    if new_title == "" {
        bufferSet(status, "Filename cannot be empty.")
        return
    }
    if new_title == current_title {
        return
    }

    renameNoteFileToTitle(state, note, new_title, status)
}

freeSavedNote :: proc(saved: ^SavedNote) {
    for i in 0..<len(saved.messages) {
        delete(saved.messages[i].text)
        delete(saved.messages[i].reply)
    }
    delete(saved.messages)
}

noteHasContent :: proc(note: ^Note) -> bool {
    if note == nil do return false

    for i in 0..<note.msgCount {
        if i == note.msgCount - 1 do continue
        if strings.trim_space(bufferString(note.msgs[i].text[:])) != "" {
            return true
        }
    }
    return false
}

saveNote :: proc(state: ^AppState, note: ^Note, status: []byte) {
    if note == nil do return

    if !noteHasContent(note) {
        path := bufferString(note.path[:])
        if path != "" && os.is_file(path) {
            _ = os.remove(path)
        }
        note.dirty = false
        bufferSet(status, "")
        return
    }

    dir, dir_err := bookPagesDir(state)
    if dir_err != nil {
        bufferSet(status, "Create or open a book before saving pages.")
        return
    }
    defer delete(dir)

    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        bufferSet(status, fmt.tprintf("Could not create notes folder: %v (%s)", mkdir_err, dir))
        return
    }

    path, path_err := notePath(state, note)
    if path_err != nil {
        bufferSet(status, "Could not resolve note path.")
        return
    }
    defer delete(path)

    messages := make([]SavedMessage, note.msgCount, context.allocator)
    defer delete(messages)
    for i in 0..<note.msgCount {
        msg := &note.msgs[i]
        messages[i] = SavedMessage {
            text = bufferString(msg.text[:]),
            reply = bufferString(msg.reply[:]),
            has_reply = msg.has_reply,
            starred = msg.starred,
        }
    }

    saved := SavedNote {
        version = 1,
        id = note.id,
        messages = messages,
    }

    data, marshal_err := json.marshal(saved, {pretty = true}, context.allocator)
    if marshal_err != nil {
        bufferSet(status, "Could not encode note JSON.")
        return
    }
    defer delete(data)

    if write_err := os.write_entire_file(path, data); write_err != nil {
        bufferSet(status, fmt.tprintf("Could not save note: %v (%s)", write_err, path))
        return
    }

    bufferSet(note.path[:], path)
    note.dirty = false
    bufferSet(status, fmt.tprintf("Saved %s", path))
}

saveDirtyNotes :: proc(state: ^AppState) {
    for i in 0..<state.noteCount {
        if state.notes[i].dirty {
            saveNote(state, &state.notes[i], state.saveStatus[:])
        }
    }
}

loadNoteFile :: proc(state: ^AppState, path: string) -> bool {
    if state.noteCount >= len(state.notes) do return false

    data, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil do return false
    defer delete(data)

    saved: SavedNote
    unmarshal_err := json.unmarshal(data, &saved, allocator = context.allocator)
    if unmarshal_err != nil do return false
    defer freeSavedNote(&saved)

    note := &state.notes[state.noteCount]
    note^ = Note{}
    note.id = max(saved.id, state.nextNoteID)
    bufferSet(note.path[:], path)
    bufferSet(note.title[:], noteTitle(note))

    message_count := min(len(saved.messages), len(note.msgs))
    for i in 0..<message_count {
        msg := &note.msgs[i]
        bufferSet(msg.text[:], saved.messages[i].text)
        bufferSet(msg.reply[:], saved.messages[i].reply)
        msg.has_reply = saved.messages[i].has_reply
        msg.starred = saved.messages[i].starred
        msg.dirty = false
    }
    note.msgCount = message_count
    ensureDraftMsg(note)
    note.dirty = false

    state.noteCount += 1
    state.nextNoteID = max(state.nextNoteID, note.id + 1)
    return true
}

findOpenNoteByPath :: proc(state: ^AppState, path: string) -> int {
    for i in 0..<state.noteCount {
        if bufferString(state.notes[i].path[:]) == path {
            return i
        }
    }
    return -1
}

clearPages :: proc(state: ^AppState) {
    state.noteCount = 0
    state.activeNote = 0
    state.nextNoteID = 1
    state.editingTitleNote = 0
}

loadBookPages :: proc(state: ^AppState, dir: string) -> bool {
    if !os.is_dir(dir) do return false

    loaded := false
    walker := os.walker_create(dir)
    defer os.walker_destroy(&walker)

    for info in os.walker_walk(&walker) {
        if _, walk_err := os.walker_error(&walker); walk_err != nil {
            continue
        }
        if info.type != .Regular || !strings.has_suffix(info.name, ".json") {
            continue
        }
        if loadNoteFile(state, info.fullpath) {
            bufferSet(state.notes[state.noteCount - 1].path[:], info.fullpath)
            loaded = true
        }
    }

    if loaded {
        state.activeNote = 0
        bufferSet(state.saveStatus[:], "Loaded pages.")
    }
    return loaded
}

openBookFromPath :: proc(state: ^AppState, path: string) -> bool {
    trimmed := strings.trim_space(path)
    if trimmed == "" {
        bufferSet(state.openStatus[:], "Choose a book folder first.")
        return false
    }
    if !os.is_dir(trimmed) {
        bufferSet(state.openStatus[:], fmt.tprintf("Could not open book: %s", trimmed))
        return false
    }

    clearPages(state)
    bufferSet(state.currentBookPath[:], trimmed)
    bufferSet(state.currentBookName[:], filepath.base(trimmed))
    loadBookPages(state, trimmed)
    if state.noteCount == 0 {
        createNote(state)
    }
    state.activeNote = min(state.activeNote, state.noteCount - 1)
    state.showHome = false
    state.showSettings = false
    state.showStarred = false
    bufferSet(state.openStatus[:], fmt.tprintf("Opened book %s", bufferString(state.currentBookName[:])))
    return true
}

createBook :: proc(state: ^AppState) -> bool {
    name := strings.trim_space(bufferString(state.bookNameInput[:]))
    if name == "" {
        name = "new-book"
    }

    root, root_err := booksDir()
    if root_err != nil {
        bufferSet(state.openStatus[:], "Could not resolve books folder.")
        return false
    }
    defer delete(root)
    if mkdir_err := os.make_directory_all(root); mkdir_err != nil && !os.is_dir(root) {
        bufferSet(state.openStatus[:], fmt.tprintf("Could not create books folder: %v", mkdir_err))
        return false
    }

    slug := noteFilenameSlug(name)
    defer delete(slug)

    book_path: string
    for n := 0; ; n += 1 {
        folder := slug if n == 0 else fmt.tprintf("%s-%d", slug, n + 1)
        candidate, join_err := os.join_path({root, folder}, context.allocator)
        if join_err != nil {
            bufferSet(state.openStatus[:], "Could not resolve book path.")
            return false
        }
        if !os.is_dir(candidate) {
            book_path = candidate
            break
        }
        delete(candidate)
    }

    if mkdir_err := os.make_directory_all(book_path); mkdir_err != nil && !os.is_dir(book_path) {
        bufferSet(state.openStatus[:], fmt.tprintf("Could not create book: %v", mkdir_err))
        delete(book_path)
        return false
    }
    defer delete(book_path)

    return openBookFromPath(state, book_path)
}

ensureBooksDir :: proc(state: ^AppState) {
    root, root_err := booksDir()
    if root_err != nil {
        bufferSet(state.openStatus[:], "Could not resolve books folder.")
        return
    }
    defer delete(root)

    if mkdir_err := os.make_directory_all(root); mkdir_err != nil && !os.is_dir(root) {
        bufferSet(state.openStatus[:], fmt.tprintf("Could not create books folder: %v", mkdir_err))
    }
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

messageCount :: proc(note: ^Note) -> int {
    if note == nil do return 0
    return max(note.msgCount - 1, 0)
}

starredCount :: proc(note: ^Note) -> int {
    if note == nil do return 0

    count := 0
    for i in 0..<note.msgCount {
        if i == note.msgCount - 1 do continue
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

titleColor :: proc(theme: int) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return {0.120, 0.145, 0.190, 1}
    }
    return {0.93, 0.95, 1.0, 1.0}
}

mutedColor :: proc(theme: int) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return {0.365, 0.400, 0.475, 1}
    }
    return {0.50, 0.53, 0.61, 1}
}

bookColor :: proc(theme: int) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return {0.270, 0.345, 0.500, 1}
    }
    return {0.62, 0.68, 0.78, 1}
}

playerNameColor :: proc(theme: int) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return {0.490, 0.295, 0.030, 1}
    }
    return {0.95, 0.82, 0.25, 1.0}
}

botNameColor :: proc(theme: int) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return {0.090, 0.280, 0.575, 1}
    }
    return {0.34, 0.66, 1.0, 1.0}
}

messageBoxBgColor :: proc(theme: int, is_draft: bool) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return is_draft ? im.Vec4{0.965, 0.970, 0.982, 1} : im.Vec4{0.935, 0.942, 0.958, 1}
    }
    return is_draft ? im.Vec4{0.085, 0.092, 0.125, 1} : im.Vec4{0.055, 0.060, 0.080, 1}
}

messageBoxBorderColor :: proc(theme: int, is_draft: bool) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return is_draft ? im.Vec4{0.720, 0.755, 0.825, 1} : im.Vec4{0.780, 0.800, 0.850, 1}
    }
    return is_draft ? im.Vec4{0.380, 0.450, 0.620, 1} : im.Vec4{0.230, 0.255, 0.330, 1}
}

messageBoxTextColor :: proc(theme: int) -> im.Vec4 {
    if theme == THEME_LIGHT {
        return {0.080, 0.090, 0.115, 1}
    }
    return {0.93, 0.94, 0.97, 1}
}

applyTheme :: proc(theme: int) {
    if theme == THEME_LIGHT {
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
    if theme == THEME_LIGHT {
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
    } else if theme == THEME_SOFT {
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

drawReply :: proc(state: ^AppState, msg: ^ChatMsg) {
    if !msg.has_reply do return

    im.Dummy({0, 8})
    drawAvatar("M", {0.25, 0.46, 0.90, 1}, {0.46, 0.70, 1.0, 1}, {0.96, 0.98, 1.0, 1})
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

    bot_name := bufferString(state.botName[:])
    bot_name_c := strings.clone_to_cstring(bot_name)
    defer delete(bot_name_c)
    im.TextColored(botNameColor(state.theme), "%s", bot_name_c)

    reply := bufferString(msg.reply[:])
    height := max(f32(lineCount(reply)) * im.GetTextLineHeight() + 14, 36)
    im.PushStyleColorImVec4(im.Col.FrameBg, messageBoxBgColor(state.theme, false))
    im.PushStyleColorImVec4(im.Col.Border, messageBoxBorderColor(state.theme, false))
    im.PushStyleColorImVec4(im.Col.Text, messageBoxTextColor(state.theme))
    pushed_code_font := pushCodeFont()
    im.InputTextMultiline("##reply", cstring(&msg.reply[0]), c.size_t(len(msg.reply)), {-1, height}, {.ReadOnly})
    popFontIf(pushed_code_font)
    im.PopStyleColor(3)
    im.Unindent(AVATAR_SIZE + AVATAR_GAP)
}

drawUserMsg :: proc(state: ^AppState, note: ^Note, idx: int, is_draft: bool) {
    msg := &note.msgs[idx]
    im.PushIDInt(c.int(idx))

    im.Dummy({0, MESSAGE_GAP})
    drawAvatar("C", {0.78, 0.53, 0.16, 1}, {1.0, 0.79, 0.32, 1}, {0.07, 0.06, 0.04, 1})
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

    im.AlignTextToFramePadding()
    player_name := bufferString(state.playerName[:])
    player_name_c := strings.clone_to_cstring(player_name)
    defer delete(player_name_c)
    im.TextColored(playerNameColor(state.theme), "%s", player_name_c)
    if !is_draft {
        im.SameLine()
        if msg.starred {
            if im.SmallButton("Unstar") {
                msg.starred = false
                note.dirty = true
            }
        } else {
            if im.SmallButton("Star") {
                msg.starred = true
                note.dirty = true
            }
        }
        im.SameLine()
        if im.SmallButton("Delete") {
            deleteMsg(note, idx)
            im.Unindent(AVATAR_SIZE + AVATAR_GAP)
            im.PopID()
            return
        }
    }

    text := bufferString(msg.text[:])
    height := max(f32(lineCount(text)) * im.GetTextLineHeight() + 14, 36)
    im.PushStyleColorImVec4(im.Col.FrameBg, messageBoxBgColor(state.theme, is_draft))
    im.PushStyleColorImVec4(im.Col.Border, messageBoxBorderColor(state.theme, is_draft))
    im.PushStyleColorImVec4(im.Col.Text, messageBoxTextColor(state.theme))
    pushed_code_font := pushCodeFont()
    submit := false
    cb_data := SubmitHotkeyData{state = state, submitted = &submit}
    changed := im.InputTextMultiline(
        "##message",
        cstring(&msg.text[0]),
        c.size_t(len(msg.text)),
        {-1, height},
        {.AllowTabInput, .CallbackAlways, .CallbackCharFilter},
        submitHotkeyCallback,
        &cb_data,
    )
    item_active := im.IsItemActive()
    item_hovered := im.IsItemHovered(im.HoveredFlags_RectOnly)
    deactivated_after_edit := im.IsItemDeactivatedAfterEdit()
    popFontIf(pushed_code_font)
    if changed {
        msg.dirty = true
        note.dirty = true
    }
    im.PopStyleColor(3)

    clicked_outside := item_active &&
                       msg.dirty &&
                       im.IsMouseClicked(.Left, false) &&
                       !item_hovered

    if submit || (item_active && state.shiftEnterSignal) || deactivated_after_edit || clicked_outside {
        commitMsg(state, note, idx, is_draft)
    }

    im.Unindent(AVATAR_SIZE + AVATAR_GAP)
    drawReply(state, msg)
    im.PopID()
}

drawIntro :: proc() {
    im.Dummy({0, 24})

    im.SetWindowFontScale(2.2)
    title_size := im.CalcTextSize("Mothmotica")
    title_x := max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD)
    im.SetCursorPosX(title_x)
    im.TextColored(titleColor(THEME_DARK), "Mothmotica")
    im.SetWindowFontScale(1)

    im.Dummy({0, 14})
    im.Separator()
    im.Dummy({0, 10})
}

drawHome :: proc(state: ^AppState) {
    total := im.GetContentRegionAvail()
    im.Dummy({0, max(total.y * 0.18, 36)})

    im.SetWindowFontScale(2.1)
    title_size := im.CalcTextSize("Mothmotica")
    im.SetCursorPosX(max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD))
    im.TextColored(titleColor(state.theme), "Mothmotica")
    im.SetWindowFontScale(1)

    im.Dummy({0, 20})
    button_w := min(max(total.x * 0.35, 240), 340)
    button_h := f32(46)
    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    im.SetNextItemWidth(button_w)
    im.InputTextWithHint("##book-name", "book name", cstring(&state.bookNameInput[0]), c.size_t(len(state.bookNameInput)))

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    can_create_book := strings.trim_space(bufferString(state.bookNameInput[:])) != ""
    im.BeginDisabled(!can_create_book)
    if im.Button("Create Book", {button_w, button_h}) {
        createBook(state)
    }
    im.EndDisabled()

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    if im.Button("Open Book", {button_w, button_h}) {
        state.showOpenBookDialog = true
    }

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    if im.Button("Settings", {button_w, button_h}) {
        state.showSettings = true
    }

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    if im.Button("Visit the Github", {button_w, button_h}) {
        openExternal(REPO_URL, state.openStatus[:])
    }
}

drawSettings :: proc(state: ^AppState) {
    total := im.GetContentRegionAvail()
    im.Dummy({0, max(total.y * 0.12, 28)})

    im.SetWindowFontScale(1.7)
    title_size := im.CalcTextSize("Settings")
    im.SetCursorPosX(max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD))
    im.TextColored(titleColor(state.theme), "Settings")
    im.SetWindowFontScale(1)

    panel_w := min(max(total.x * 0.48, 320), 520)
    im.Dummy({0, 18})
    im.SetCursorPosX(max((im.GetWindowWidth() - panel_w) * 0.5, SIDE_PAD))
    if im.BeginChild("SettingsPanel", {panel_w, 0}, {.Borders}, {}) {
        im.AlignTextToFramePadding()
        im.Text("Player Name:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        if im.InputText("##player-name", cstring(&state.playerName[0]), c.size_t(len(state.playerName))) {
            state.settingsDirty = true
        }
        im.AlignTextToFramePadding()
        im.Text("Bot Name:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        if im.InputText("##bot-name", cstring(&state.botName[0]), c.size_t(len(state.botName))) {
            state.settingsDirty = true
        }

        im.SeparatorText("Send Hotkey")
        if im.RadioButton("Enter", state.sendHotkey == SEND_HOTKEY_ENTER) {
            state.sendHotkey = SEND_HOTKEY_ENTER
            state.settingsDirty = true
        }
        if im.RadioButton("Shift + Enter", state.sendHotkey == SEND_HOTKEY_SHIFT_ENTER) {
            state.sendHotkey = SEND_HOTKEY_SHIFT_ENTER
            state.settingsDirty = true
        }

        im.SeparatorText("Theme")
        if im.RadioButton("Dark", state.theme == THEME_DARK) {
            state.theme = THEME_DARK
            state.settingsDirty = true
        }
        if im.RadioButton("Soft", state.theme == THEME_SOFT) {
            state.theme = THEME_SOFT
            state.settingsDirty = true
        }
        if im.RadioButton("Light", state.theme == THEME_LIGHT) {
            state.theme = THEME_LIGHT
            state.settingsDirty = true
        }

        im.Separator()
        if im.Button("Back", {120, 36}) {
            state.showSettings = false
        }
    }
    im.EndChild()
}

drawTopBar :: proc(state: ^AppState, note: ^Note) {
    if im.Button("Home") {
        state.showHome = true
        state.showSettings = false
    }
    im.SameLine()
    if im.Button("Switch Book") {
        state.showOpenBookDialog = true
    }

    if note != nil {
        im.SameLine()
        book_name := bufferString(state.currentBookName[:])
        book_name_c := strings.clone_to_cstring(book_name)
        defer delete(book_name_c)
        im.TextColored(bookColor(state.theme), "%s", book_name_c)

        if state.editingTitleNote != note.id {
            bufferSet(state.titleEdit[:], noteTitle(note))
            state.editingTitleNote = note.id
        }

        avail := im.GetContentRegionAvail()
        im.SameLine(max(im.GetWindowWidth() - 470, SIDE_PAD))
        im.SetNextItemWidth(260)
        im.InputText("##note-title", cstring(&state.titleEdit[0]), c.size_t(len(state.titleEdit)))
        if im.IsItemDeactivatedAfterEdit() {
            setNoteFilename(state, note, bufferString(state.titleEdit[:]), state.saveStatus[:])
        }
        im.SameLine()

        all_count := messageCount(note)
        starred_count := starredCount(note)

        view_label := fmt.tprintf(state.showStarred ? "Starred (%d)" : "All Messages (%d)", 
            state.showStarred ? starred_count : all_count,
        )

        view_label_c := strings.clone_to_cstring(view_label)
        defer delete(view_label_c)

        if im.Button(view_label_c) {
            state.showStarred = !state.showStarred
        }
        
        _ = avail
    }

    save_status := bufferString(state.saveStatus[:])
    if len(save_status) > 0 {
        im.NewLine()
        save_status_c := strings.clone_to_cstring(save_status)
        defer delete(save_status_c)
        im.TextColored(mutedColor(state.theme), "Save: %s", save_status_c)
    }

    im.Separator()
}

drawBookDialogs :: proc(state: ^AppState) {
    if state.showCreateBookDialog {
        im.OpenPopup("Create Book")
    }

    if im.BeginPopupModal("Create Book", &state.showCreateBookDialog) {
        im.SetNextItemWidth(360)
        im.InputText("Book Name", cstring(&state.bookNameInput[0]), c.size_t(len(state.bookNameInput)))
        if im.Button("Create") {
            if createBook(state) {
                state.showCreateBookDialog = false
                im.CloseCurrentPopup()
            }
        }
        im.SameLine()
        if im.Button("Cancel") {
            state.showCreateBookDialog = false
            im.CloseCurrentPopup()
        }
        im.EndPopup()
    }

    if state.showOpenBookDialog {
        im.OpenPopup("Open Book")
    }

    viewport := im.GetMainViewport()
    popup_w := min(max(viewport.Size.x * 0.62, 420), max(viewport.Size.x - 80, 280))
    popup_h := min(max(viewport.Size.y * 0.66, 360), max(viewport.Size.y - 80, 280))
    popup_center := im.Vec2{
        viewport.Pos.x + viewport.Size.x * 0.5,
        viewport.Pos.y + viewport.Size.y * 0.5,
    }
    im.SetNextWindowPos(popup_center, {}, {0.5, 0.5})
    im.SetNextWindowSize({popup_w, popup_h})

    if im.BeginPopupModal("Open Book", &state.showOpenBookDialog, {.NoTitleBar, .NoMove, .NoResize}) {
        im.Dummy({0, 8})
        im.SetWindowFontScale(1.35)
        title_size := im.CalcTextSize("Select A Book")
        im.SetCursorPosX(max((im.GetWindowWidth() - title_size.x) * 0.5, 16))
        im.TextColored(titleColor(state.theme), "Select A Book")
        im.SetWindowFontScale(1)
        im.Dummy({0, 8})
        im.Separator()
        im.Dummy({0, 8})

        list_h := max(im.GetContentRegionAvail().y - 78, 120)
        if im.BeginChild("BookList", {-1, list_h}, {.Borders}, {}) {
            dir, dir_err := booksDir()
            if dir_err == nil {
                defer delete(dir)
                _ = os.make_directory_all(dir)

                found := false
                row := 0
                walker := os.walker_create(dir)
                defer os.walker_destroy(&walker)
                for info in os.walker_walk(&walker) {
                    if _, walk_err := os.walker_error(&walker); walk_err != nil {
                        continue
                    }
                    if info.type != .Directory {
                        continue
                    }

                    found = true
                    im.PushIDInt(c.int(row))
                    row += 1
                    open_label := fmt.tprintf("Open##%s", info.name)
                    open_label_c := strings.clone_to_cstring(open_label)
                    defer delete(open_label_c)
                    if im.SmallButton(open_label_c) {
                        bufferSet(state.openPath[:], info.fullpath)
                        if openBookFromPath(state, info.fullpath) {
                            state.showOpenBookDialog = false
                            im.CloseCurrentPopup()
                        }
                        im.PopID()
                        break
                    }
                    im.SameLine()
                    name_c := strings.clone_to_cstring(info.name)
                    defer delete(name_c)
                    im.Text("%s", name_c)
                    im.PopID()
                }

                if !found {
                    im.TextColored(mutedColor(state.theme), "No books yet.")
                }
            } else {
                im.TextColored({0.95, 0.42, 0.36, 1}, "Could not find books folder.")
            }
        }
        im.EndChild()

        status := bufferString(state.openStatus[:])
        if len(status) > 0 {
            im.Separator()
            status_c := strings.clone_to_cstring(status)
            defer delete(status_c)
            im.TextWrapped("%s", status_c)
        }

        im.Separator()
        if im.Button("Close", {100, 34}) {
            state.showOpenBookDialog = false
            im.CloseCurrentPopup()
        }
        im.EndPopup()
    }
}

drawPageSidebar :: proc(state: ^AppState, size: im.Vec2) {
    if state.noteCount == 0 do return

    if im.BeginChild("PageSidebar", size, {.Borders}, {}) {
        item_w := max(im.GetContentRegionAvail().x, 1)
        if im.Button("New Page", {item_w, 34}) {
            createNote(state)
        }
        im.Separator()
        for i in 0..<state.noteCount {
            item_w = max(im.GetContentRegionAvail().x, 1)
            note := &state.notes[i]
            title := noteTitle(note)
            label := fmt.tprintf("%s##page-%d", title, note.id)
            label_c := strings.clone_to_cstring(label)
            defer delete(label_c)

            if im.Selectable(label_c, i == state.activeNote, {}, {item_w, 0}) {
                state.activeNote = i
            }
        }
    }
    im.EndChild()
}

drawStarredMessages :: proc(state: ^AppState, note: ^Note) {
    found := false
    for i in 0..<note.msgCount {
        if i == note.msgCount - 1 do continue
        if !note.msgs[i].starred do continue
        found = true
        drawUserMsg(state, note, i, false)
    }

    if !found {
        im.Dummy({0, 28})
        im.TextColored(mutedColor(state.theme), "No starred messages yet.")
    }
}

draw :: proc(state: ^AppState) {
    viewport := im.GetMainViewport()
    im.SetNextWindowPos(viewport.Pos)
    im.SetNextWindowSize(viewport.Size)

    flags := im.WindowFlags_NoDecoration | im.WindowFlags{.NoMove, .NoResize, .NoCollapse}
    if im.Begin("Mothmotica", nil, flags) {
        total := im.GetContentRegionAvail()

        if state.showSettings {
            if im.BeginChild("Settings", total, {}, {}) {
                drawSettings(state)
            }
            im.EndChild()
        } else if state.showHome {
            if im.BeginChild("Home", total, {}, {}) {
                drawHome(state)
            }
            im.EndChild()
        } else {
            note := activeNote(state)
            if note == nil {
                createNote(state)
                note = activeNote(state)
            }

            drawTopBar(state, note)
            body := im.GetContentRegionAvail()
            sidebar_w := min(SIDEBAR_WIDTH, max(body.x * 0.35, 180))
            drawPageSidebar(state, {sidebar_w, body.y})
            im.SameLine()

            chat_w := max(body.x - sidebar_w - 12, 240)
            if im.BeginChild("ChatLog", {chat_w, body.y}, {}, {.HorizontalScrollbar}) {
                im.Indent(SIDE_PAD)
                if state.showStarred {
                    drawStarredMessages(state, note)
                } else {
                    for i in 0..<note.msgCount {
                        is_draft := i == note.msgCount - 1
                        drawUserMsg(state, note, i, is_draft)
                    }
                }
                im.Unindent(SIDE_PAD)

                if state.newMsgQ {
                    im.SetScrollHereY(1.0)
                    state.newMsgQ = false
                }
            }
            im.EndChild()
        }
        drawBookDialogs(state)
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

    applyTheme(THEME_DARK)

    imgui_impl_glfw.InitForOpenGL(window, true)
    defer imgui_impl_glfw.Shutdown()
    imgui_impl_opengl3.Init("#version 150")
    defer imgui_impl_opengl3.Shutdown()

    state := new(AppState)
    defer free(state)
    state.showHome = true
    state.nextNoteID = 1
    state.sendHotkey = SEND_HOTKEY_ENTER
    state.theme = THEME_DARK
    bufferSet(state.playerName[:], "Curryocity")
    bufferSet(state.botName[:], "Mothball")
    loadSettings(state)
    ensureBooksDir(state)

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        updateShortcuts(window, state)

        imgui_impl_opengl3.NewFrame()
        imgui_impl_glfw.NewFrame()
        im.NewFrame()
        applyTheme(state.theme)
        ensureDraftMsg(activeNote(state))

        draw(state)
        saveDirtySettings(state)
        saveDirtyNotes(state)

        im.Render()
        display_w, display_h := glfw.GetFramebufferSize(window)
        gl.Viewport(0, 0, display_w, display_h)
        gl.ClearColor(0.04, 0.04, 0.04, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

        glfw.SwapBuffers(window)
    }

    for i in 0..<state.noteCount {
        state.notes[i].dirty = true
    }
    state.settingsDirty = true
    saveDirtySettings(state)
    saveDirtyNotes(state)
}
