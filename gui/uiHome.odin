package main

import "core:c"
import "core:strings"

import im "../third_party/odin-imgui"

drawIntro :: proc() {
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

