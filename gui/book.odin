package main

import "base:runtime"

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"

import im "../third_party/odin-imgui"

Page :: struct {
    id: int,
    title: [PAGE_TITLE_SIZE]byte,
    path: [PATH_SIZE]byte,
    msgs: [MAX_MSGS]ChatMsg,
    msgCount: int,
    dirty: bool,
}

SavedPage :: struct {
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

ChatMsg :: struct {
    text: [8192]byte,
    reply: [65536]byte,
    has_reply: bool,
    dirty: bool,
    starred: bool,
}

drawBookUI :: proc(state: ^AppState){
    page := activePage(state)
    if page == nil {
        createPage(state)
        page = activePage(state)
    }

    ensureDraftMsg(page)

    drawTopBar(state, page)
    body := im.GetContentRegionAvail()
    sidebar_w := min(SIDEBAR_WIDTH, max(body.x * 0.35, 180))
    drawPageSidebar(state, {sidebar_w, body.y})
    im.SameLine()

    chat_w := max(body.x - sidebar_w - 12, 240)
    if im.BeginChild("ChatLog", {chat_w, body.y}, {}, {.HorizontalScrollbar}) {
        im.Indent(SIDE_PAD)
        if state.showStarred {
            drawStarredMessages(state, page)
        } else {
            for i in 0..<page.msgCount {
                is_draft := i == realMessageCount(page)
                drawUserMsg(state, page, i, is_draft)
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

drawReply :: proc(state: ^AppState, msg: ^ChatMsg) {
    if !msg.has_reply do return

    im.Dummy({0, 8})
    bot_name := bufferString(state.botName[:])
    if bot_avatar_texture != 0 {
        drawAvatarImage(bot_avatar_texture)
    } else {
        bot_avatar := avatarLabel(bot_name, 'M')
        drawAvatar(cstring(&bot_avatar[0]), {0.27, 0.24, 0.58, 1}, {0.49, 0.42, 0.82, 1}, {0.96, 0.95, 1.0, 1})
    }
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

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

drawUserMsg :: proc(state: ^AppState, page: ^Page, idx: int, is_draft: bool) {
    msg := &page.msgs[idx]
    im.PushIDInt(c.int(idx))

    im.Dummy({0, MESSAGE_GAP})
    player_name := bufferString(state.playerName[:])
    if player_avatar_texture != 0 {
        drawAvatarImage(player_avatar_texture)
    } else {
        player_avatar := avatarLabel(player_name, 'C')
        drawAvatar(cstring(&player_avatar[0]), {0.78, 0.53, 0.16, 1}, {1.0, 0.79, 0.32, 1}, {0.07, 0.06, 0.04, 1})
    }
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

    im.AlignTextToFramePadding()
    player_name_c := strings.clone_to_cstring(player_name)
    defer delete(player_name_c)
    im.TextColored(playerNameColor(state.theme), "%s", player_name_c)
    if !is_draft {
        im.SameLine()
        star_label: cstring = "Unstar" if msg.starred else "Star"
        if im.SmallButton(star_label) {
            msg.starred = !msg.starred
            page.dirty = true
        }
        im.SameLine()
        if im.SmallButton("Delete") {
            deleteMsg(page, idx)
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
    cb_data := SubmitState{state = state, submitted = &submit}
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
        page.dirty = true
    }
    im.PopStyleColor(3)

    clicked_outside := item_active &&
                       msg.dirty &&
                       im.IsMouseClicked(.Left, false) &&
                       !item_hovered

    if submit || (item_active && state.shiftEnterSignal) || deactivated_after_edit || clicked_outside {
        commitMsg(state, page, idx, is_draft)
    }

    im.Unindent(AVATAR_SIZE + AVATAR_GAP)
    drawReply(state, msg)
    im.PopID()
}


drawTopBar :: proc(state: ^AppState, page: ^Page) {
    if im.Button("Home") {
        state.showHome = true
        state.showSettings = false
    }
    im.SameLine()
    if im.Button("Switch Book") {
        state.showOpenBookDialog = true
    }
    im.SameLine()
    if im.Button("Locate Book") {
        openCurrentBookFolder(state)
    }

    if page != nil {
        im.SameLine()
        book_name := bufferString(state.currentBookName[:])
        book_name_c := strings.clone_to_cstring(book_name)
        defer delete(book_name_c)
        im.TextColored(bookColor(state.theme), "%s", book_name_c)

        if state.editingTitlePage != page.id {
            bufferSet(state.titleEdit[:], pageTitle(page))
            state.editingTitlePage = page.id
        }

        avail := im.GetContentRegionAvail()
        im.SameLine(max(im.GetWindowWidth() - 470, SIDE_PAD))
        im.SetNextItemWidth(260)
        im.InputText("##page-title", cstring(&state.titleEdit[0]), c.size_t(len(state.titleEdit)))
        if im.IsItemDeactivatedAfterEdit() {
            setPageFilename(state, page, bufferString(state.titleEdit[:]), state.saveStatus[:])
        }
        im.SameLine()

        all_count := messageCount(page)
        starred_count := starredCount(page)

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

    im.Separator()
}

createBookPopup :: proc(state: ^AppState) {
    if state.showCreateBookDialog {
        im.OpenPopup("Create Book")
    }

    if im.BeginPopupModal("Create Book", &state.showCreateBookDialog) {
        im.SetNextItemWidth(360)
        im.InputText("Book Name", cstring(&state.bookNameInput[0]), c.size_t(len(state.bookNameInput)))
        can_create_book := strings.trim_space(bufferString(state.bookNameInput[:])) != ""
        im.BeginDisabled(!can_create_book)
        if im.Button("Create") {
            if createBook(state) {
                state.showCreateBookDialog = false
                im.CloseCurrentPopup()
            }
        }
        im.EndDisabled()
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
        book_folder_w := f32(118)
        im.SameLine(max(im.GetWindowWidth() - book_folder_w - 18, 16))
        if im.Button("Book Folder", {book_folder_w, 32}) {
            openBooksFolder(state)
        }
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

        im.Separator()
        close_w := f32(100)
        im.SetCursorPosX(max((im.GetWindowWidth() - close_w) * 0.5, 16))
        if im.Button("Close", {close_w, 34}) {
            state.showOpenBookDialog = false
            im.CloseCurrentPopup()
        }
        im.EndPopup()
    }
}

drawPageSidebar :: proc(state: ^AppState, size: im.Vec2) {
    if state.pageCount == 0 do return

    if im.BeginChild("PageSidebar", size, {.Borders}, {}) {
        item_w := max(im.GetContentRegionAvail().x, 1)
        if im.Button("New Page", {item_w, 34}) {
            createPage(state)
        }
        im.Separator()
        for i in 0..<state.pageCount {
            item_w = max(im.GetContentRegionAvail().x, 1)
            page := &state.pages[i]
            title := pageTitle(page)
            label := fmt.tprintf("%s##page-%d", title, page.id)
            label_c := strings.clone_to_cstring(label)
            defer delete(label_c)

            if im.Selectable(label_c, i == state.activePage, {}, {item_w, 0}) {
                state.activePage = i
            }
        }
    }
    im.EndChild()
}

drawStarredMessages :: proc(state: ^AppState, page: ^Page) {
    found := false
    for i in 0..<realMessageCount(page) {
        if !page.msgs[i].starred do continue
        found = true
        drawUserMsg(state, page, i, false)
    }

    if !found {
        im.Dummy({0, 28})
        im.TextColored(mutedColor(state.theme), "No starred messages yet.")
    }
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

sendHotkeyDown :: proc(state: ^AppState) -> bool {
    io := im.GetIO()
    if state != nil && state.sendHotkey == .Shift_Enter {
        return io.KeyShift
    }
    return !io.KeyShift
}

submitHotkeyCallback :: proc "c" (data: ^im.InputTextCallbackData) -> c.int {
    context = runtime.default_context()

    payload := cast(^SubmitState)data.UserData
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

pageTitle :: proc(page: ^Page) -> string {
    path := bufferString(page.path[:])
    if path != "" {
        stem := filepath.stem(path)
        if stem != "" do return stem
    }

    title := strings.trim_space(bufferString(page.title[:]))
    if title == "" do return "untitled-page"
    return title
}

activePage :: proc(state: ^AppState) -> ^Page {
    if state.pageCount == 0 do return nil
    state.activePage = min(max(state.activePage, 0), state.pageCount - 1)
    return &state.pages[state.activePage]
}

appendEmptyMsg :: proc(page: ^Page) {
    if page.msgCount >= len(page.msgs) {
        copy(page.msgs[:len(page.msgs)-1], page.msgs[1:])
        page.msgCount = len(page.msgs) - 1
    }

    msg := &page.msgs[page.msgCount]
    msg^ = ChatMsg{}
    page.msgCount += 1
}

ensureDraftMsg :: proc(page: ^Page) {
    if page != nil && page.msgCount == 0 {
        appendEmptyMsg(page)
    }
}

createPage :: proc(state: ^AppState) -> ^Page {
    if state.pageCount >= len(state.pages) {
        state.activePage = len(state.pages) - 1
        return &state.pages[state.activePage]
    }

    idx := state.pageCount
    page := &state.pages[idx]
    page^ = Page{}
    for {
        page.id = state.nextPageID
        path, path_err := defaultPagePath(state, page)
        if path_err != nil {
            break
        }
        exists := os.is_file(path)
        delete(path)
        if !exists {
            break
        }
        state.nextPageID += 1
    }
    bufferSet(page.title[:], fmt.tprintf("page-%d", page.id))
    state.nextPageID += 1
    appendEmptyMsg(page)
    page.dirty = true

    state.pageCount += 1
    state.activePage = idx
    state.showHome = false
    state.showStarred = false
    state.newMsgQ = true
    return page
}

openFirstPage :: proc(state: ^AppState) {
    if state.pageCount == 0 {
        createPage(state)
        return
    }
    state.activePage = min(max(state.activePage, 0), state.pageCount - 1)
    state.showHome = false
    state.showStarred = false
}

realMessageCount :: proc(page: ^Page) -> int {
    if page == nil do return 0
    return max(page.msgCount - 1, 0)
}

messageCount :: proc(page: ^Page) -> int {
    return realMessageCount(page)
}

starredCount :: proc(page: ^Page) -> int {
    if page == nil do return 0

    count := 0
    for i in 0..<realMessageCount(page) {
        if page.msgs[i].starred do count += 1
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

    cli_name := "mothmotica-cli"
    when ODIN_OS == .Windows {
        cli_name = "mothmotica-cli.exe"
    }

    cli_path, join_err := os.join_path({exe_dir, cli_name}, context.allocator)
    if join_err != nil {
        bufferSet(output, "Could not resolve mothmotica-cli path.")
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
        bufferSet(output, "Could not run mothmotica-cli. Build it with `make gui`.")
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

addMsg :: proc(state: ^AppState, page: ^Page) {
    if page == nil || page.msgCount == 0 do return

    draft := &page.msgs[page.msgCount - 1]
    input := strings.trim_space(bufferString(draft.text[:]))
    if input == "" do return

    bufferSet(draft.text[:], input)
    refreshMsg(draft)
    appendEmptyMsg(page)
    page.dirty = true
    state.newMsgQ = true
}

commitMsg :: proc(state: ^AppState, page: ^Page, idx: int, is_draft: bool) {
    if page == nil || idx < 0 || idx >= page.msgCount do return

    msg := &page.msgs[idx]
    trimmed := strings.trim_space(bufferString(msg.text[:]))
    bufferSet(msg.text[:], trimmed)

    if is_draft {
        addMsg(state, page)
    } else {
        refreshMsg(msg)
        page.dirty = true
    }
}

deleteMsg :: proc(page: ^Page, idx: int) {
    if page == nil || idx < 0 || idx >= page.msgCount do return

    for i in idx..<page.msgCount - 1 {
        page.msgs[i] = page.msgs[i + 1]
    }
    page.msgCount -= 1
    ensureDraftMsg(page)
    page.dirty = true
}