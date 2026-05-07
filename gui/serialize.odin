package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"

freeSavedSettings :: proc(settings: ^Settings) {
    delete(settings.player_name)
    delete(settings.bot_name)
    delete(settings.player_avatar_path)
}

appDataDir :: proc() -> (string, os.Error) {
    root, root_err := os.user_data_dir(context.allocator)
    if root_err != nil {
        return "", root_err
    }
    defer delete(root)

    return os.join_path({root, APP_NAME}, context.allocator)
}

settingsPath :: proc() -> (string, os.Error) {
    dir, dir_err := appDataDir()
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    return os.join_path({dir, SETTINGS_FILE}, context.allocator)
}

booksDir :: proc() -> (string, os.Error) {
    dir, dir_err := appDataDir()
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    return os.join_path({dir, BOOKS_FOLDER}, context.allocator)
}

userAvatarDir :: proc() -> (string, os.Error) {
    dir, dir_err := appDataDir()
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    return os.join_path({dir, USER_DATA_FOLDER, AVATAR_FOLDER}, context.allocator)
}

playerAvatarPath :: proc() -> (string, os.Error) {
    dir, dir_err := userAvatarDir()
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    return os.join_path({dir, PLAYER_AVATAR_FILE}, context.allocator)
}

loadSettings :: proc(state: ^AppState) {
    path, path_err := settingsPath()
    if path_err != nil do return
    defer delete(path)

    data, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil do return
    defer delete(data)

    saved: Settings
    if json.unmarshal(data, &saved, allocator = context.allocator) != nil do return
    defer freeSavedSettings(&saved)

    if strings.trim_space(saved.player_name) != "" {
        bufferSet(state.playerName[:], saved.player_name)
    }
    if strings.trim_space(saved.bot_name) != "" {
        bufferSet(state.botName[:], saved.bot_name)
    }
    if strings.trim_space(saved.player_avatar_path) != "" {
        bufferSet(state.playerAvatarPath[:], saved.player_avatar_path)
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
    dir, dir_err := appDataDir()
    if dir_err != nil do return
    defer delete(dir)

    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        return
    }

    path, path_err := settingsPath()
    if path_err != nil do return
    defer delete(path)

    saved := Settings {
        version = 1,
        player_name = bufferString(state.playerName[:]),
        bot_name = bufferString(state.botName[:]),
        player_avatar_path = bufferString(state.playerAvatarPath[:]),
        send_hotkey = int(state.sendHotkey),
        theme = int(state.theme),
    }

    data, marshal_err := json.marshal(saved, {pretty = true}, context.allocator)
    if marshal_err != nil do return
    defer delete(data)

    if os.write_entire_file(path, data) == nil {
        state.settingsDirty = false
    }
}

saveDirtySettings :: proc(state: ^AppState) {
    if state.settingsDirty {
        saveSettings(state)
    }
}

bookPagesDir :: proc(state: ^AppState) -> (string, os.Error) {
    path := bufferString(state.currentBookPath[:])
    if path == "" {
        return "", os.General_Error.Not_Exist
    }
    return strings.clone(path), nil
}

defaultPagePath :: proc(state: ^AppState, page: ^Page) -> (string, os.Error) {
    dir, dir_err := bookPagesDir(state)
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)
    return os.join_path({dir, fmt.tprintf("page-%d.json", page.id)}, context.allocator)
}

pagePath :: proc(state: ^AppState, page: ^Page) -> (string, os.Error) {
    path := bufferString(page.path[:])
    if len(path) > 0 {
        return strings.clone(path), nil
    }
    return titlePagePath(state, page, pageTitle(page))
}

pageFilenameSlug :: proc(title: string) -> string {
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
        strings.write_string(&b, "untitled-page")
        result = strings.to_string(b)
    }
    return strings.clone(result)
}

titlePagePath :: proc(state: ^AppState, page: ^Page, title: string) -> (string, os.Error) {
    dir, dir_err := bookPagesDir(state)
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    slug := pageFilenameSlug(title)
    defer delete(slug)

    candidate: string
    for n := 0; ; n += 1 {
        filename := fmt.tprintf("%s.json", slug) if n == 0 else fmt.tprintf("%s-%d.json", slug, n + 1)
        path, path_err := os.join_path({dir, filename}, context.allocator)
        if path_err != nil {
            return "", path_err
        }

        current := bufferString(page.path[:])
        if !os.is_file(path) || path == current {
            candidate = path
            break
        }
        delete(path)
    }
    return candidate, nil
}

renamePageFileToTitle :: proc(state: ^AppState, page: ^Page, title: string, status: []byte) {
    if page == nil do return

    old_path := bufferString(page.path[:])
    if old_path == "" && !pageHasContent(page) {
        bufferSet(page.title[:], title)
        page.dirty = false
        bufferSet(status, "")
        return
    } else if old_path == "" {
        bufferSet(page.title[:], title)
        page.dirty = true
        savePage(state, page, status)
        return
    }

    new_path, path_err := titlePagePath(state, page, title)
    if path_err != nil {
        bufferSet(status, "Could not resolve renamed page path.")
        return
    }
    defer delete(new_path)

    if old_path == new_path {
        bufferSet(status, "Filename already matches the page title.")
        return
    }

    if rename_err := os.rename(old_path, new_path); rename_err != nil {
        bufferSet(status, fmt.tprintf("Could not rename page file: %v", rename_err))
        return
    }

    bufferSet(page.path[:], new_path)
    bufferSet(page.title[:], filepath.stem(new_path))
    page.dirty = true
    savePage(state, page, status)
}

setPageFilename :: proc(state: ^AppState, page: ^Page, title: string, status: []byte) {
    if page == nil do return

    current_title := pageTitle(page)
    new_title := strings.trim_space(title)
    if new_title == "" {
        bufferSet(status, "Filename cannot be empty.")
        return
    }
    if new_title == current_title {
        return
    }

    renamePageFileToTitle(state, page, new_title, status)
}

freeSavedPage :: proc(saved: ^SavedPage) {
    for i in 0..<len(saved.messages) {
        delete(saved.messages[i].text)
        delete(saved.messages[i].reply)
    }
    delete(saved.messages)
}

pageHasContent :: proc(page: ^Page) -> bool {
    if page == nil do return false

    for i in 0..<realMessageCount(page) {
        if strings.trim_space(bufferString(page.msgs[i].text[:])) != "" {
            return true
        }
    }
    return false
}

savePage :: proc(state: ^AppState, page: ^Page, status: []byte) {
    if page == nil do return

    if !pageHasContent(page) {
        path := bufferString(page.path[:])
        if path != "" && os.is_file(path) {
            _ = os.remove(path)
        }
        page.dirty = false
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
        bufferSet(status, fmt.tprintf("Could not create pages folder: %v (%s)", mkdir_err, dir))
        return
    }

    path, path_err := pagePath(state, page)
    if path_err != nil {
        bufferSet(status, "Could not resolve page path.")
        return
    }
    defer delete(path)

    messages := make([]SavedMessage, page.msgCount, context.allocator)
    defer delete(messages)
    for i in 0..<page.msgCount {
        msg := &page.msgs[i]
        messages[i] = SavedMessage {
            text = bufferString(msg.text[:]),
            reply = bufferString(msg.reply[:]),
            has_reply = msg.has_reply,
            starred = msg.starred,
        }
    }

    saved := SavedPage {
        version = 1,
        id = page.id,
        messages = messages,
    }

    data, marshal_err := json.marshal(saved, {pretty = true}, context.allocator)
    if marshal_err != nil {
        bufferSet(status, "Could not encode page JSON.")
        return
    }
    defer delete(data)

    if write_err := os.write_entire_file(path, data); write_err != nil {
        bufferSet(status, fmt.tprintf("Could not save page: %v (%s)", write_err, path))
        return
    }

    bufferSet(page.path[:], path)
    page.dirty = false
    bufferSet(status, fmt.tprintf("Saved %s", path))
}

saveDirtyPages :: proc(state: ^AppState) {
    for i in 0..<state.pageCount {
        if state.pages[i].dirty {
            savePage(state, &state.pages[i], state.saveStatus[:])
        }
    }
}

loadPageFile :: proc(state: ^AppState, path: string) -> bool {
    if state.pageCount >= len(state.pages) do return false

    data, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil do return false
    defer delete(data)

    saved: SavedPage
    unmarshal_err := json.unmarshal(data, &saved, allocator = context.allocator)
    if unmarshal_err != nil do return false
    defer freeSavedPage(&saved)

    page := &state.pages[state.pageCount]
    page^ = Page{}
    page.id = max(saved.id, state.nextPageID)
    bufferSet(page.path[:], path)
    bufferSet(page.title[:], pageTitle(page))

    message_count := min(len(saved.messages), len(page.msgs))
    for i in 0..<message_count {
        msg := &page.msgs[i]
        bufferSet(msg.text[:], saved.messages[i].text)
        bufferSet(msg.reply[:], saved.messages[i].reply)
        msg.has_reply = saved.messages[i].has_reply
        msg.starred = saved.messages[i].starred
        msg.dirty = false
    }
    page.msgCount = message_count
    ensureDraftMsg(page)
    page.dirty = false

    state.pageCount += 1
    state.nextPageID = max(state.nextPageID, page.id + 1)
    return true
}

findOpenPageByPath :: proc(state: ^AppState, path: string) -> int {
    for i in 0..<state.pageCount {
        if bufferString(state.pages[i].path[:]) == path {
            return i
        }
    }
    return -1
}

clearPages :: proc(state: ^AppState) {
    state.pageCount = 0
    state.activePage = 0
    state.nextPageID = 1
    state.editingTitlePage = 0
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
        if loadPageFile(state, info.fullpath) {
            bufferSet(state.pages[state.pageCount - 1].path[:], info.fullpath)
            loaded = true
        }
    }

    if loaded {
        state.activePage = 0
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
    if state.pageCount == 0 {
        createPage(state)
    }
    state.activePage = min(state.activePage, state.pageCount - 1)
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

    slug := pageFilenameSlug(name)
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
