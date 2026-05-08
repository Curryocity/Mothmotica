package main

import "base:runtime"

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"

import im "../third_party/odin-imgui"
import "vendor:glfw"

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
    page := getActivePage(state)
    if page == nil {
        createPage(state)
        page = getActivePage(state)
    }

    atLeastOneMsg(page)

    drawTopBar(state, page)
    body := im.GetContentRegionAvail()
    sidebar_w := min(SIDEBAR_WIDTH, max(body.x * 0.35, 180))
    drawSidebar(state, {sidebar_w, body.y})
    im.SameLine()

    chat_w := max(body.x - sidebar_w - 12, 240)
    if im.BeginChild("ChatLog", {chat_w, body.y}, {}, {.HorizontalScrollbar}) {
        im.Indent(SIDE_PAD)
        if state.ui.showStarred {
            drawStarredMsg(state, page)
        } else {
            for i in 0..<page.msgCount {
                is_draft := (i == msgCount(page))
                drawAllMsg(state, page, i, is_draft)
            }
        }
        im.Unindent(SIDE_PAD)

        if state.runtime.newMsgQ {
            im.SetScrollHereY(1.0)
            state.runtime.newMsgQ = false
        }
    }
    im.EndChild()
}

drawReply :: proc(state: ^AppState, msg: ^ChatMsg) {
    if !msg.has_reply do return

    im.Dummy({0, 8})
    bot_name := bufferString(state.settings.botName[:])
    if bot_pfpTex != 0 {
        drawAvatarImage(bot_pfpTex)
    } else {
        bot_avatar := avatarLabel(bot_name)
        drawAvatar(cstring(&bot_avatar[0]), {0.27, 0.24, 0.58, 1}, {0.49, 0.42, 0.82, 1}, {0.96, 0.95, 1.0, 1})
    }
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

    bot_name_c := strings.clone_to_cstring(bot_name)
    defer delete(bot_name_c)
    im.TextColored(botNameColor(state.settings.theme), "%s", bot_name_c)

    reply := bufferString(msg.reply[:])
    height := max(f32(lineCount(reply)) * im.GetTextLineHeight() + 14, 36)
    im.PushStyleColorImVec4(im.Col.FrameBg, msgBoxBgColor(state.settings.theme, false))
    im.PushStyleColorImVec4(im.Col.Border, msgBoxBorderColor(state.settings.theme, false))
    im.PushStyleColorImVec4(im.Col.Text, msgBoxTextColor(state.settings.theme))
    pushed_code_font := pushMonoFont()
    im.InputTextMultiline("##reply", cstring(&msg.reply[0]), c.size_t(len(msg.reply)), {-1, height}, {.ReadOnly})
    popFontIf(pushed_code_font)
    im.PopStyleColor(3)
    im.Unindent(AVATAR_SIZE + AVATAR_GAP)
}

drawAllMsg :: proc(state: ^AppState, page: ^Page, idx: int, is_draft: bool) {
    msg := &page.msgs[idx]
    im.PushIDInt(c.int(idx))

    im.Dummy({0, MESSAGE_GAP})
    player_name := bufferString(state.settings.playerName[:])
    if user_pfpTex != 0 {
        drawAvatarImage(user_pfpTex)
    } else {
        player_avatar := avatarLabel(player_name)
        drawAvatar(cstring(&player_avatar[0]), {0.78, 0.53, 0.16, 1}, {1.0, 0.79, 0.32, 1}, {0.07, 0.06, 0.04, 1})
    }
    im.Indent(AVATAR_SIZE + AVATAR_GAP)

    im.AlignTextToFramePadding()
    player_name_c := strings.clone_to_cstring(player_name)
    defer delete(player_name_c)
    im.TextColored(playerNameColor(state.settings.theme), "%s", player_name_c)
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
    im.PushStyleColorImVec4(im.Col.FrameBg, msgBoxBgColor(state.settings.theme, is_draft))
    im.PushStyleColorImVec4(im.Col.Border, msgBoxBorderColor(state.settings.theme, is_draft))
    im.PushStyleColorImVec4(im.Col.Text, msgBoxTextColor(state.settings.theme))
    pushed_MonoFont := pushMonoFont()
    submit := false
    cb_data := SubmitState{state = state, submitted = &submit}
    changed := im.InputTextMultiline(
        "##message",
        cstring(&msg.text[0]),
        c.size_t(len(msg.text)),
        {-1, height},
        {.AllowTabInput, .CallbackAlways, .CallbackCharFilter},
        sendMsgCallback,
        &cb_data,
    )
    item_active := im.IsItemActive()
    item_hovered := im.IsItemHovered(im.HoveredFlags_RectOnly)
    deactivated_after_edit := im.IsItemDeactivatedAfterEdit()
    popFontIf(pushed_MonoFont)
    if changed {
        msg.dirty = true
        page.dirty = true
    }
    im.PopStyleColor(3)

    clicked_outside := item_active &&
                       msg.dirty &&
                       im.IsMouseClicked(.Left, false) &&
                       !item_hovered

    if submit || (item_active && state.runtime.shiftEnterSignal) || deactivated_after_edit || clicked_outside {
        commitMsg(state, page, idx, is_draft)
    }

    im.Unindent(AVATAR_SIZE + AVATAR_GAP)
    drawReply(state, msg)
    im.PopID()
}


drawTopBar :: proc(state: ^AppState, page: ^Page) {
    if im.Button("Home") {
        state.ui.scene = .Home
    }
    im.SameLine()
    if im.Button("Switch Book") {
        state.ui.showOpenBookPopup = true
    }
    im.SameLine()
    if im.Button("Locate Book") {
        openCurrentBookFolder(state)
    }

    if page != nil {
        im.SameLine()
        book_name := bufferString(state.book.curBookName[:])
        book_name_c := strings.clone_to_cstring(book_name)
        defer delete(book_name_c)
        im.TextColored(subTextColor(state.settings.theme), "%s", book_name_c)

        if state.ui.editingTitlePage != page.id {
            bufferSet(state.ui.titleEdit[:], getTitle(page))
            state.ui.editingTitlePage = page.id
        }

        im.SameLine(max(im.GetWindowWidth() - 470, SIDE_PAD))
        im.SetNextItemWidth(260)
        im.InputText("##page-title", cstring(&state.ui.titleEdit[0]), c.size_t(len(state.ui.titleEdit)))
        if im.IsItemDeactivatedAfterEdit() {
            setPageFilename(state, page, bufferString(state.ui.titleEdit[:]))
        }
        im.SameLine()

        all_count := msgCount(page)
        starred_count := starredCount(page)

        view_label := fmt.tprintf(state.ui.showStarred ? "Starred (%d)" : "All Messages (%d)", 
            state.ui.showStarred ? starred_count : all_count,
        )

        view_label_c := strings.clone_to_cstring(view_label)
        defer delete(view_label_c)

        if im.Button(view_label_c) {
            state.ui.showStarred = !state.ui.showStarred
        }
        
    }

    im.Separator()
}

drawSidebar :: proc(state: ^AppState, size: im.Vec2) {
    if state.book.pageCount == 0 do return

    if im.BeginChild("PageSidebar", size, {.Borders}, {}) {
        item_w := max(im.GetContentRegionAvail().x, 1)
        if im.Button("New Page", {item_w, 34}) {
            createPage(state)
        }
        im.Separator()
        for i in 0..<state.book.pageCount {
            item_w = max(im.GetContentRegionAvail().x, 1)
            page := &state.book.pages[i]
            title := getTitle(page)
            label := fmt.tprintf("%s##page-%d", title, page.id)
            label_c := strings.clone_to_cstring(label)
            defer delete(label_c)

            if im.Selectable(label_c, i == state.book.activePage, {}, {item_w, 0}) {
                state.book.activePage = i
            }
        }
    }
    im.EndChild()
}

drawStarredMsg :: proc(state: ^AppState, page: ^Page) {
    found := false
    for i in 0..<msgCount(page) {
        if !page.msgs[i].starred do continue
        found = true
        drawAllMsg(state, page, i, false)
    }

    if !found {
        im.Dummy({0, 28})
        im.TextColored(mutedColor(state.settings.theme), "No starred messages yet.")
    }
}

avatarLabel :: proc(name: string) -> [2]byte {
    label := [2]byte{' ', 0}
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

getTitle :: proc(page: ^Page) -> string {
    path := bufferString(page.path[:])
    if path != "" {
        stem := filepath.stem(path)
        if stem != "" do return stem
    }

    title := strings.trim_space(bufferString(page.title[:]))
    if title == "" do return "untitled-page"
    return title
}

getActivePage :: proc(state: ^AppState) -> ^Page {
    if state.book.pageCount == 0 do return nil
    state.book.activePage = min(max(state.book.activePage, 0), state.book.pageCount - 1)
    return &state.book.pages[state.book.activePage]
}

addEmptyMsg :: proc(page: ^Page) {
    if page.msgCount >= len(page.msgs) {
        copy(page.msgs[:len(page.msgs)-1], page.msgs[1:])
        page.msgCount = len(page.msgs) - 1
    }

    msg := &page.msgs[page.msgCount]
    msg^ = ChatMsg{}
    page.msgCount += 1
}

atLeastOneMsg :: proc(page: ^Page) {
    if page != nil && page.msgCount == 0 {
        addEmptyMsg(page)
    }
}

createPage :: proc(state: ^AppState) -> ^Page {
    if state.book.pageCount >= len(state.book.pages) {
        state.book.activePage = len(state.book.pages) - 1
        return &state.book.pages[state.book.activePage]
    }

    idx := state.book.pageCount
    page := &state.book.pages[idx]
    page^ = Page{}
    for {
        page.id = state.book.nextPageID
        path, path_err := defaultPagePath(state, page)
        if path_err != nil {
            break
        }
        exists := os.is_file(path)
        delete(path)
        if !exists {
            break
        }
        state.book.nextPageID += 1
    }
    bufferSet(page.title[:], fmt.tprintf("page-%d", page.id))
    state.book.nextPageID += 1
    addEmptyMsg(page)
    page.dirty = true

    state.book.pageCount += 1
    state.book.activePage = idx
    state.ui.scene = .Book
    state.ui.showStarred = false
    state.runtime.newMsgQ = true
    return page
}

msgCount :: proc(page: ^Page) -> int {
    if page == nil do return 0
    return max(page.msgCount - 1, 0)
}

starredCount :: proc(page: ^Page) -> int {
    if page == nil do return 0

    count := 0
    for i in 0..<msgCount(page) {
        if page.msgs[i].starred do count += 1
    }
    return count
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
    addEmptyMsg(page)
    page.dirty = true
    state.runtime.newMsgQ = true
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
    atLeastOneMsg(page)
    page.dirty = true
}

sendMsgQ :: proc(state: ^AppState) -> bool {
    io := im.GetIO()
    if state != nil && state.settings.sendHotkey == .ShiftEnter {
        return io.KeyShift
    }
    return !io.KeyShift
}

sendMsgCallback :: proc "c" (data: ^im.InputTextCallbackData) -> c.int {
    context = runtime.default_context()

    payload := cast(^SubmitState)data.UserData
    if payload == nil || payload.submitted == nil do return 0

    if .CallbackAlways in data.EventFlag && sendMsgQ(payload.state) && im.IsKeyPressed(.Enter, false) {
        payload.submitted^ = true
        return 0
    }

    if .CallbackCharFilter in data.EventFlag && sendMsgQ(payload.state) {
        if data.EventChar == '\n' || data.EventChar == '\r' {
            payload.submitted^ = true
            data.EventChar = 0
            return 1
        }
    }

    return 0
}

updateSendSignal :: proc(window: glfw.WindowHandle, state: ^AppState) {
    enter_down := glfw.GetKey(window, glfw.KEY_ENTER) == glfw.PRESS ||
                  glfw.GetKey(window, glfw.KEY_KP_ENTER) == glfw.PRESS
    shift_down := glfw.GetKey(window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS ||
                  glfw.GetKey(window, glfw.KEY_RIGHT_SHIFT) == glfw.PRESS
    wants_shift := state.settings.sendHotkey == .ShiftEnter
    down := enter_down && (shift_down == wants_shift)

    state.runtime.shiftEnterSignal = down && !state.runtime.shiftEnterQ
    state.runtime.shiftEnterQ = down
}
