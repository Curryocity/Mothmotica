package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"

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
    if saved.send_hotkey >= int(SendHotkey.Enter) && saved.send_hotkey <= int(SendHotkey.Shift_Enter) {
        state.sendHotkey = SendHotkey(saved.send_hotkey)
    }
    if saved.theme >= int(Theme.Dark) && saved.theme <= int(Theme.Light) {
        state.theme = Theme(saved.theme)
    }
    state.settingsDirty = false
}

saveSettings :: proc(state: ^AppState) {
    saved := SavedSettings {
        version = 1,
        player_name = bufferString(state.playerName[:]),
        bot_name = bufferString(state.botName[:]),
        send_hotkey = int(state.sendHotkey),
        theme = int(state.theme),
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

    for i in 0..<realMessageCount(note) {
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
        bufferSet(state.openStatus[:], "Book name cannot be empty.")
        return false
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

