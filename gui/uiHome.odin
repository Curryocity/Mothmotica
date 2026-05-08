package main

import "core:c"
import "core:os"
import "core:fmt"
import "core:strings"

import im "../third_party/odin-imgui"

drawTitle :: proc() {
    im.Dummy({0, 24})

    im.SetWindowFontScale(2.2)
    title_size := im.CalcTextSize("Mothmotica")
    title_x := max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD)
    im.SetCursorPosX(title_x)
    im.TextColored(titleColor(.Dark), "Mothmotica")
    im.SetWindowFontScale(1)

    im.Dummy({0, 14})
    im.Separator()
    im.Dummy({0, 10})
}

drawHomePage :: proc(state: ^AppState) {
    total := im.GetContentRegionAvail()
    im.Dummy({0, max(total.y * 0.18, 36)})

    im.SetWindowFontScale(2.1)
    title_size := im.CalcTextSize("Mothmotica")
    im.SetCursorPosX(max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD))
    im.TextColored(titleColor(state.settings.theme), "Mothmotica")
    im.SetWindowFontScale(1)

    im.Dummy({0, 20})
    button_w := min(max(total.x * 0.35, 240), 340)
    button_h := f32(46)
    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    im.SetNextItemWidth(button_w)
    im.InputTextWithHint("##book-name", "book name", cstring(&state.ui.bookNameInput[0]), c.size_t(len(state.ui.bookNameInput)))

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    can_create_book := strings.trim_space(bufferString(state.ui.bookNameInput[:])) != ""
    im.BeginDisabled(!can_create_book)
    if im.Button("Create Book", {button_w, button_h}) {
        createBook(state)
    }
    im.EndDisabled()

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    if im.Button("Open Book", {button_w, button_h}) {
        state.ui.showOpenBookPopup = true
    }

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    if im.Button("Settings", {button_w, button_h}) {
        state.ui.scene = .Settings
    }

    im.SetCursorPosX(max((im.GetWindowWidth() - button_w) * 0.5, SIDE_PAD))
    if im.Button("Visit the Github", {button_w, button_h}) {
        openExternal(REPO_URL)
    }
}

drawBookPopup :: proc(state: ^AppState) {
    if state.ui.showCreateBookPopup {
        im.OpenPopup("Create Book")
    }

    if im.BeginPopupModal("Create Book", &state.ui.showCreateBookPopup) {
        im.SetNextItemWidth(360)
        im.InputText("Book Name", cstring(&state.ui.bookNameInput[0]), c.size_t(len(state.ui.bookNameInput)))
        can_create_book := strings.trim_space(bufferString(state.ui.bookNameInput[:])) != ""
        im.BeginDisabled(!can_create_book)
        if im.Button("Create") {
            if createBook(state) {
                state.ui.showCreateBookPopup = false
                im.CloseCurrentPopup()
            }
        }
        im.EndDisabled()
        im.SameLine()
        if im.Button("Cancel") {
            state.ui.showCreateBookPopup = false
            im.CloseCurrentPopup()
        }
        im.EndPopup()
    }

    if state.ui.showOpenBookPopup {
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

    if im.BeginPopupModal("Open Book", &state.ui.showOpenBookPopup, {.NoTitleBar, .NoMove, .NoResize}) {
        im.Dummy({0, 8})
        im.SetWindowFontScale(1.35)
        title_size := im.CalcTextSize("Select A Book")
        im.SetCursorPosX(max((im.GetWindowWidth() - title_size.x) * 0.5, 16))
        im.TextColored(titleColor(state.settings.theme), "Select A Book")
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
                        bufferSet(state.ui.openPath[:], info.fullpath)
                        if openBookFromPath(state, info.fullpath) {
                            state.ui.showOpenBookPopup = false
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
                    im.TextColored(mutedColor(state.settings.theme), "No books yet.")
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
            state.ui.showOpenBookPopup = false
            im.CloseCurrentPopup()
        }
        im.EndPopup()
    }
}
