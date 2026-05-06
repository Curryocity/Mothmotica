package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"

import im "../third_party/odin-imgui"

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

drawUserMsg :: proc(state: ^AppState, note: ^Note, idx: int, is_draft: bool) {
    msg := &note.msgs[idx]
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
            note.dirty = true
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


drawTopBar :: proc(state: ^AppState, note: ^Note) {
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
    for i in 0..<realMessageCount(note) {
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
                        is_draft := i == realMessageCount(note)
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
