package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode"

BOOKS_FOLDER :: "books"
SETTINGS_FILE :: "mothmotica-settings.json"
PAGE_ORDER_FILE:: "order.txt"
BOT_AVATAR_PATH :: "asset/image/mothballpfp.png"
USER_DATA_FOLDER :: "user_data"
AVATAR_FOLDER :: "avatar"
PLAYER_AVATAR_FILE :: "player_avatar.png"
MACROS_FOLDER :: "Macros"

// App data paths

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

defaultMacrosDir :: proc() -> (string, os.Error) {
    dir, dir_err := appDataDir()
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    return os.join_path({dir, MACROS_FOLDER}, context.allocator)
}

macrosDir :: proc(state: ^AppState, directory_index: int) -> (string, os.Error) {
    if directory_index < 0 || directory_index >= state.settings.macroDirectoryCount {
        return defaultMacrosDir()
    }

    configured := strings.trim_space(bufferString(state.settings.macroDirectories[directory_index].path[:]))
    if configured != "" do return strings.clone(configured), nil
    return defaultMacrosDir()
}

addMacroDirectory :: proc(state: ^AppState, name, path: string) -> bool {
    if state.settings.macroDirectoryCount >= MAX_MACRO_DIRECTORIES do return false

    index := state.settings.macroDirectoryCount
    display_name := strings.trim_space(name)
    if display_name == "" {
        display_name = fmt.tprintf("Directory %d", index + 1)
    }
    bufferSet(state.settings.macroDirectories[index].name[:], display_name)
    bufferSet(state.settings.macroDirectories[index].path[:], strings.trim_space(path))
    state.settings.macroDirectoryCount += 1
    state.settings.dirty = true
    return true
}

removeMacroDirectory :: proc(state: ^AppState, index: int) {
    if index <= 0 || index >= state.settings.macroDirectoryCount do return

    for i in index..<state.settings.macroDirectoryCount - 1 {
        state.settings.macroDirectories[i] = state.settings.macroDirectories[i + 1]
    }
    state.settings.macroDirectoryCount -= 1
    state.settings.macroDirectories[state.settings.macroDirectoryCount] = {}

    if state.settings.lastMacroDirectory > index {
        state.settings.lastMacroDirectory -= 1
    } else if state.settings.lastMacroDirectory >= state.settings.macroDirectoryCount {
        state.settings.lastMacroDirectory = state.settings.macroDirectoryCount - 1
    }
    state.settings.dirty = true
}

ensureMacroDirectories :: proc(state: ^AppState) {
    if state.settings.macroDirectoryCount == 0 {
        _ = addMacroDirectory(state, "Default", "")
    }
    state.settings.lastMacroDirectory = clamp(
        state.settings.lastMacroDirectory,
        0,
        state.settings.macroDirectoryCount - 1,
    )
}

bookPagesDir :: proc(state: ^AppState) -> (string, os.Error) {
    path := bufferString(state.book.curBookPath[:])
    if path == "" {
        return "", os.General_Error.Not_Exist
    }
    return strings.clone(path), nil
}

userAvatarDir :: proc() -> (string, os.Error) {
    dir, dir_err := appDataDir()
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    return os.join_path({dir, USER_DATA_FOLDER, AVATAR_FOLDER}, context.allocator)
}

playerpfpPath :: proc() -> (string, os.Error) {
    dir, dir_err := userAvatarDir()
    if dir_err != nil {
        return "", dir_err
    }
    defer delete(dir)

    return os.join_path({dir, PLAYER_AVATAR_FILE}, context.allocator)
}

// Settings persistence

freeSavedSettings :: proc(settings: ^Settings) {
    delete(settings.player_name)
    delete(settings.bot_name)
    delete(settings.player_pfp_path)
    delete(settings.macro_export_path)
    delete(settings.mpk_export_path)
    delete(settings.cyv_export_path)
    for &directory in settings.macro_directories {
        delete(directory.name)
        delete(directory.path)
    }
    delete(settings.macro_directories)
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
        bufferSet(state.settings.playerName[:], saved.player_name)
    }
    if strings.trim_space(saved.bot_name) != "" {
        bufferSet(state.settings.botName[:], saved.bot_name)
    }
    if strings.trim_space(saved.player_pfp_path) != "" {
        bufferSet(state.settings.playerAvatarPath[:], saved.player_pfp_path)
    }
    _ = addMacroDirectory(state, "Default", "")

    if len(saved.macro_directories) > 0 {
        for directory in saved.macro_directories {
            if state.settings.macroDirectoryCount >= MAX_MACRO_DIRECTORIES do break
            if directory.name == "Default" && strings.trim_space(directory.path) == "" do continue
            _ = addMacroDirectory(state, directory.name, directory.path)
        }
    } else {
        legacy_macro_path := strings.trim_space(saved.macro_export_path)
        mpk_path := strings.trim_space(saved.mpk_export_path)
        cyv_path := strings.trim_space(saved.cyv_export_path)
        if mpk_path == "" do mpk_path = legacy_macro_path
        if cyv_path == "" do cyv_path = legacy_macro_path

        if mpk_path != "" && mpk_path == cyv_path {
            _ = addMacroDirectory(state, "Macros", mpk_path)
        } else {
            if mpk_path != "" do _ = addMacroDirectory(state, "Mpk", mpk_path)
            if cyv_path != "" do _ = addMacroDirectory(state, "Cyv", cyv_path)
        }
    }
    state.settings.lastMacroDirectory = clamp(
        saved.last_macro_directory,
        0,
        state.settings.macroDirectoryCount - 1,
    )
    if saved.send_hotkey >= int(SendHotkey.Enter) && saved.send_hotkey <= int(SendHotkey.ShiftEnter) {
        state.settings.sendHotkey = SendHotkey(saved.send_hotkey)
    }
    if saved.theme >= int(Theme.Dark) && saved.theme <= int(Theme.Light) {
        state.settings.theme = Theme(saved.theme)
    }
    state.settings.dirty = saved.version < 3 || len(saved.macro_directories) == 0
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

    directories: [dynamic]SavedMacroDirectory
    defer delete(directories)
    for i in 0..<state.settings.macroDirectoryCount {
        append(&directories, SavedMacroDirectory{
            name = bufferString(state.settings.macroDirectories[i].name[:]),
            path = bufferString(state.settings.macroDirectories[i].path[:]),
        })
    }

    saved := Settings {
        version = 3,
        player_name = bufferString(state.settings.playerName[:]),
        bot_name = bufferString(state.settings.botName[:]),
        player_pfp_path = bufferString(state.settings.playerAvatarPath[:]),
        macro_directories = directories[:],
        last_macro_directory = state.settings.lastMacroDirectory,
        send_hotkey = int(state.settings.sendHotkey),
        theme = int(state.settings.theme),
    }

    data, marshal_err := json.marshal(saved, {pretty = true}, context.allocator)
    if marshal_err != nil do return
    defer delete(data)

    if os.write_entire_file(path, data) == nil {
        state.settings.dirty = false
    }
}

saveDirtySettings :: proc(state: ^AppState) {
    if state.settings.dirty {
        saveSettings(state)
    }
}

// Page paths and filenames

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
    return titlePagePath(state, page, getTitle(page))
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

pageHasContent :: proc(page: ^Page) -> bool {
    if page == nil do return false

    for i in 0..<msgCount(page) {
        if strings.trim_space(bufferString(page.msgs[i].text[:])) != "" {
            return true
        }
    }
    return false
}

setPageFilename :: proc(state: ^AppState, page: ^Page, title: string) {
    if page == nil do return

    current_title := getTitle(page)
    new_title := strings.trim_space(title)
    if new_title == "" {
        return
    }
    if new_title == current_title {
        return
    }

    old_path := bufferString(page.path[:])
    if old_path == "" && !pageHasContent(page) {
        bufferSet(page.title[:], title)
        page.dirty = false
        return
    } else if old_path == "" {
        bufferSet(page.title[:], title)
        page.dirty = true
        savePage(state, page)
        savePagesOrder(state)
        return
    }

    new_path, path_err := titlePagePath(state, page, title)
    if path_err != nil {
        return
    }
    defer delete(new_path)

    if old_path == new_path {
        return
    }

    if rename_err := os.rename(old_path, new_path); rename_err != nil {
        return
    }

    bufferSet(page.path[:], new_path)
    bufferSet(page.title[:], filepath.stem(new_path))
    page.dirty = true
    savePage(state, page)
    savePagesOrder(state)
}

// Page persistence

freeSavedPage :: proc(saved: ^SavedPage) {
    for i in 0..<len(saved.messages) {
        delete(saved.messages[i].text)
        delete(saved.messages[i].reply)
    }
    delete(saved.messages)
}

savePage :: proc(state: ^AppState, page: ^Page) {
    if page == nil do return

    dir, dir_err := bookPagesDir(state)
    if dir_err != nil {
        return
    }
    defer delete(dir)

    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        return
    }

    path, path_err := pagePath(state, page)
    if path_err != nil {
        return
    }
    defer delete(path)

    realCount := savedMsgCount(page)

    messages := make([]SavedMessage, realCount, context.allocator)
    defer delete(messages)

    for i in 0..<realCount {
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
        return
    }
    defer delete(data)

    if write_err := os.write_entire_file(path, data); write_err != nil {
        return
    }

    bufferSet(page.path[:], path)
    page.dirty = false
}

saveDirtyPages :: proc(state: ^AppState) {
    saved_any := false
    for i in 0..<state.book.pageCount {
        page := state.book.pages[i]
        if page != nil && page.dirty {
            savePage(state, page)
            saved_any = true
        }
    }
    if saved_any {
        savePagesOrder(state)
    }
}

loadPageFile :: proc(state: ^AppState, path: string) -> bool {
    if state.book.pageCount >= len(state.book.pages) do return false

    data, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil do return false
    defer delete(data)

    saved: SavedPage
    unmarshal_err := json.unmarshal(data, &saved, allocator = context.allocator)
    if unmarshal_err != nil do return false
    defer freeSavedPage(&saved)

    page := new(Page)
    state.book.pages[state.book.pageCount] = page
    page^ = Page{}
    page.id = max(saved.id, state.book.nextPageID)
    bufferSet(page.path[:], path)
    bufferSet(page.title[:], getTitle(page))

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
    addEmptyMsg(page)
    page.dirty = false

    state.book.pageCount += 1
    state.book.nextPageID = max(state.book.nextPageID, page.id + 1)
    return true
}

findOpenPageByPath :: proc(state: ^AppState, path: string) -> int {
    for i in 0..<state.book.pageCount {
        page := state.book.pages[i]
        if page != nil && bufferString(page.path[:]) == path {
            return i
        }
    }
    return -1
}

// Page ordering

orderFileExist :: proc(state: ^AppState) -> bool {
    path, err := getPageOrderPath(state)
    if err != nil {
        return false
    }
    defer delete(path)
    return os.is_file(path)
}

getPageOrderPath :: proc(state: ^AppState)  -> (string, os.Error) {
    dir, err := bookPagesDir(state)
    if err != nil {
        return "", err
    }
    defer delete(dir)
    return os.join_path({dir, PAGE_ORDER_FILE}, context.allocator)
}

savePagesOrder :: proc(state: ^AppState) -> bool {
    path, err := getPageOrderPath(state)
    if err != nil {
        return false
    }
    defer delete(path)

    b := strings.builder_make()
    defer strings.builder_destroy(&b)

    for i in 0..<state.book.pageCount {
        page := state.book.pages[i]
        if page == nil {
            continue
        }
        page_path := bufferString(page.path[:])
        if page_path == "" {
            continue
        }
        filename := filepath.base(page_path)
        if filename == "" || filename == PAGE_ORDER_FILE {
            continue
        }
        strings.write_string(&b, fmt.tprintf("%s\n", filename))
    }

    text := strings.to_string(b)
    err = os.write_entire_file(path, transmute([]byte)text)

    return err == nil
}

loadPagesOrder :: proc(state: ^AppState, dir: string) -> bool {
    order_path, err := getPageOrderPath(state)
    if err != nil {
        return false
    }
    defer delete(order_path)

    data, read_err := os.read_entire_file(order_path, context.allocator)
    if read_err != nil {
        return false
    }
    defer delete(data)

    lines := strings.split(string(data), "\n", context.allocator)
    defer delete(lines)

    loaded := false

    for line in lines {
        filename := strings.trim_space(line)
        if filename == "" {
            continue
        }
        if !strings.has_suffix(filename, ".json") {
            filename = fmt.tprintf("%s.json", filename)
        }

        if state.book.pageCount >= MAX_PAGES {
            break
        }

        page_path, join_err := os.join_path({dir, filename}, context.allocator)
        if join_err != nil {
            return false
        }

        if !os.is_file(page_path) {
            delete(page_path)
            continue
        }

        if findOpenPageByPath(state, page_path) >= 0 {
            delete(page_path)
            continue
        }

        if !loadPageFile(state, page_path) {
            delete(page_path)
            continue
        }

        bufferSet(state.book.pages[state.book.pageCount - 1].path[:], page_path)
        delete(page_path)

        loaded = true
    }

    return loaded
}

// Book folders and loaded page sets

clearPages :: proc(state: ^AppState) {
    for i in 0..<state.book.pageCount {
        if state.book.pages[i] != nil {
            free(state.book.pages[i])
            state.book.pages[i] = nil
        }
    }
    state.book.pageCount = 0
    state.book.activePage = 0
    state.book.nextPageID = 1
    state.ui.editingTitlePage = 0
}

loadBookPages :: proc(state: ^AppState, dir: string) -> bool {
    if !os.is_dir(dir) do return false

    loaded := false

    if orderFileExist(state) {
        loaded = loadPagesOrder(state, dir)
    }

    walker := os.walker_create(dir)
    defer os.walker_destroy(&walker)
    for info in os.walker_walk(&walker) {
        if _, walk_err := os.walker_error(&walker); walk_err != nil {
            continue
        }
        if info.type != .Regular || !strings.has_suffix(info.name, ".json") {
            continue
        }
        if findOpenPageByPath(state, info.fullpath) >= 0 {
            continue
        }
        if loadPageFile(state, info.fullpath) {
            bufferSet(state.book.pages[state.book.pageCount - 1].path[:], info.fullpath)
            loaded = true
        }
    }

    if loaded {
        savePagesOrder(state)
    }

    state.book.activePage = 0

    return loaded
}

openBookFromPath :: proc(state: ^AppState, path: string) -> bool {
    trimmed := strings.trim_space(path)
    if trimmed == "" {
        return false
    }
    if !os.is_dir(trimmed) {
        return false
    }

    clearPages(state)
    bufferSet(state.book.curBookPath[:], trimmed)
    bufferSet(state.book.curBookName[:], filepath.base(trimmed))
    loadBookPages(state, trimmed)
    if state.book.pageCount == 0 {
        createPage(state)
    }
    state.book.activePage = min(state.book.activePage, state.book.pageCount - 1)
    state.ui.scene = .Book
    state.ui.showStarred = false
    state.runtime.chatPageID = -1
    state.runtime.scrollBottomFrames = 3
    return true
}

createBook :: proc(state: ^AppState) -> bool {
    name := strings.trim_space(bufferString(state.ui.bookNameInput[:]))
    if name == "" {
        return false
    }

    root, root_err := booksDir()
    if root_err != nil {
        return false
    }
    defer delete(root)
    if mkdir_err := os.make_directory_all(root); mkdir_err != nil && !os.is_dir(root) {
        return false
    }

    slug := pageFilenameSlug(name)
    defer delete(slug)

    book_path, join_err := os.join_path({root, slug}, context.allocator)
    if join_err != nil {
        return false
    }

    if os.is_dir(book_path) {
        delete(book_path)
        return false
    }

    if mkdir_err := os.make_directory_all(book_path); mkdir_err != nil && !os.is_dir(book_path) {
        delete(book_path)
        return false
    }
    defer delete(book_path)

    if !openBookFromPath(state, book_path) {
        return false
    }

    bufferSet(state.ui.bookNameInput[:], "")
    return true
}

canCreateBook :: proc(state: ^AppState) -> bool {
    name := strings.trim_space(bufferString(state.ui.bookNameInput[:]))
    if name == "" {
        return false
    }

    root, root_err := booksDir()
    if root_err != nil {
        return false
    }
    defer delete(root)

    slug := pageFilenameSlug(name)
    defer delete(slug)

    book_path, join_err := os.join_path({root, slug}, context.allocator)
    if join_err != nil {
        return false
    }
    defer delete(book_path)

    return !os.is_dir(book_path)
}

ensureBooksDir :: proc(state: ^AppState) {
    root, root_err := booksDir()
    if root_err != nil {
        return
    }
    defer delete(root)

    if mkdir_err := os.make_directory_all(root); mkdir_err != nil && !os.is_dir(root) {
        return
    }
}

// External folder and URL actions

openExternal :: proc(url: string) {
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
        return
    }
}

openCurrentBookFolder :: proc(state: ^AppState) {
    path := bufferString(state.book.curBookPath[:])
    if path == "" || !os.is_dir(path) {
        return
    }
    openExternal(path)
}

openBooksFolder :: proc(state: ^AppState) {
    dir, dir_err := booksDir()
    if dir_err != nil {
        return
    }
    defer delete(dir)

    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        return
    }
    openExternal(dir)
}

openMacrosFolder :: proc(state: ^AppState, directory_index: int) {
    dir, dir_err := macrosDir(state, directory_index)
    if dir_err != nil {
        return
    }
    defer delete(dir)

    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        return
    }
    openExternal(dir)
}

openMacroDirectoryPath :: proc(path: string) {
    dir := strings.trim_space(path)
    if dir == "" do return
    if mkdir_err := os.make_directory_all(dir); mkdir_err != nil && !os.is_dir(dir) {
        return
    }
    openExternal(dir)
}
