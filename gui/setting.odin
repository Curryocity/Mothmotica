package main

import "core:c"
import "core:os"
import "core:strings"
import im "../third_party/odin-imgui"

SavedMacroDirectory :: struct {
    name: string,
    path: string,
}

Settings :: struct {
    version: int,
    player_name: string,
    bot_name: string,
    player_pfp_path: string,
    macro_export_path: string,
    mpk_export_path: string,
    cyv_export_path: string,
    macro_directories: []SavedMacroDirectory,
    last_macro_directory: int,
    send_hotkey: int,
    theme: int,
}

SendHotkey :: enum {
    Enter,
    ShiftEnter,
}

SubmitState :: struct {
    state: ^AppState,
    submitted: ^bool,
}

setAvatarStatus :: proc(state: ^AppState, message: string, is_error: bool) {
    bufferSet(state.settings.playerAvatarStatus[:], message)
    state.settings.playerAvatarStatusError = is_error
}

drawMacroDirectoryEditorPopup :: proc(state: ^AppState) {
    editing := state.ui.macroDirectoryEditIndex >= 0
    popup_title: cstring = "Edit Macro Directory" if editing else "Add Macro Directory"

    if state.ui.openMacroDirectoryEditorPopup {
        im.OpenPopup(popup_title)
        state.ui.openMacroDirectoryEditorPopup = false
    }

    viewport := im.GetMainViewport()
    center := im.Vec2{
        viewport.Pos.x + viewport.Size.x * 0.5,
        viewport.Pos.y + viewport.Size.y * 0.5,
    }
    im.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
    im.SetNextWindowSize({480, 0}, .Appearing)
    if !im.BeginPopupModal(popup_title, nil, {.NoResize}) do return
    defer im.EndPopup()

    protected := editing && state.ui.macroDirectoryEditIndex == 0

    im.Text("Display Name")
    im.SetNextItemWidth(-1)
    im.InputText(
        "##new-macro-directory-name",
        cstring(&state.ui.macroDirectoryNameInput[0]),
        c.size_t(len(state.ui.macroDirectoryNameInput)),
        protected ? im.InputTextFlags{.ReadOnly} : {},
    )

    im.Text("Directory Path")
    im.SetNextItemWidth(-1)
    im.InputText(
        "##new-macro-directory-path",
        cstring(&state.ui.macroDirectoryPathInput[0]),
        c.size_t(len(state.ui.macroDirectoryPathInput)),
        protected ? im.InputTextFlags{.ReadOnly} : {},
    )

    name := strings.trim_space(bufferString(state.ui.macroDirectoryNameInput[:]))
    path := strings.trim_space(bufferString(state.ui.macroDirectoryPathInput[:]))

    if editing {
        if im.Button("Locate Directory", {150, 34}) {
            if protected {
                openMacrosFolder(state, 0)
            } else {
                openMacroDirectoryPath(path)
            }
        }
    }

    if editing && !protected {
        im.SameLine()
        if im.Button("Delete", {100, 34}) {
            removeMacroDirectory(state, state.ui.macroDirectoryEditIndex)
            im.CloseCurrentPopup()
            return
        }
    }

    if editing do im.Spacing()
    if im.Button("Cancel", {100, 34}) {
        im.CloseCurrentPopup()
    }
    im.SameLine()
    im.BeginDisabled((name == "" || path == "") && !protected)
    if im.Button("OK", {100, 34}) {
        if !editing {
            if addMacroDirectory(state, name, path) do im.CloseCurrentPopup()
        } else if protected {
            im.CloseCurrentPopup()
        } else {
            directory := &state.settings.macroDirectories[state.ui.macroDirectoryEditIndex]
            bufferSet(directory.name[:], name)
            bufferSet(directory.path[:], path)
            state.settings.dirty = true
            im.CloseCurrentPopup()
        }
    }
    im.EndDisabled()
}

drawSettings :: proc(state: ^AppState) {
    total := im.GetContentRegionAvail()
    im.Dummy({0, max(total.y * 0.12, 28)})

    pushTextScale(1.7)
    title_size := im.CalcTextSize("Settings")
    im.SetCursorPosX(max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD))
    im.TextColored(titleColor(state.settings.theme), "Settings")
    popTextScale()

    panel_w := min(max(total.x * 0.48, 320), 520)
    im.Dummy({0, 18})
    im.SetCursorPosX(max((im.GetWindowWidth() - panel_w) * 0.5, SIDE_PAD))
    if im.BeginChild("SettingsPanel", {panel_w, 0}, {.Borders}, {}) {
        im.AlignTextToFramePadding()
        im.Text("Name:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        if im.InputText("##player-name", cstring(&state.settings.playerName[0]), c.size_t(len(state.settings.playerName))) {
            state.settings.dirty = true
        }
        im.AlignTextToFramePadding()
        im.Text("Bot Name:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        if im.InputText("##bot-name", cstring(&state.settings.botName[0]), c.size_t(len(state.settings.botName))) {
            state.settings.dirty = true
        }

        im.Dummy({0, 12})
        im.SeparatorText("Profile Picture")
        im.AlignTextToFramePadding()
        im.Text("Source Path:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        im.InputText("##pfp-path", cstring(&state.settings.playerAvatarImportPath[0]), c.size_t(len(state.settings.playerAvatarImportPath)))
        if im.Button("Use Image", {120, 34}) {
            source := strings.trim_space(bufferString(state.settings.playerAvatarImportPath[:]))
            if source == "" {
                setAvatarStatus(state, "Choose an image path first.", true)
            } else if !os.is_file(source) {
                setAvatarStatus(state, "Could not find an image at that path.", true)
            } else if usePlayerPfp(state, source) {
                setAvatarStatus(state, "Copied profile picture locally.", false)
                bufferSet(state.settings.playerAvatarImportPath[:], "")
            } else {
                setAvatarStatus(state, "Could not use that image.", true)
            }
        }
        im.SameLine()
        if im.Button("Delete", {90, 34}) {
            destroyPlayerpfpTex()
            bufferSet(state.settings.playerAvatarPath[:], "")
            state.settings.dirty = true
            setAvatarStatus(state, "Removed profile picture.", false)
        }
        avatar_status := bufferString(state.settings.playerAvatarStatus[:])
        if len(avatar_status) > 0 {
            avatar_status_c := strings.clone_to_cstring(avatar_status)
            defer delete(avatar_status_c)
            im.Spacing()
            status_color := im.Vec4{0.95, 0.36, 0.31, 1} if state.settings.playerAvatarStatusError else mutedColor(state.settings.theme)
            im.PushTextWrapPos(0)
            im.TextColored(status_color, "%s", avatar_status_c)
            im.PopTextWrapPos()
        }

        im.Dummy({0, 12})
        im.SeparatorText("Macro Export")
        default_macro_dir, default_macro_err := defaultMacrosDir()
        if im.BeginChild("MacroDirectories", {0, 200}, {.Borders}, {}) {
            for i in 0..<state.settings.macroDirectoryCount {
                directory := &state.settings.macroDirectories[i]
                im.PushIDInt(c.int(i))

                name := strings.trim_space(bufferString(directory.name[:]))
                name_c := strings.clone_to_cstring(name)
                im.AlignTextToFramePadding()
                im.Text("%s", name_c)
                delete(name_c)
                im.SameLine(max(im.GetWindowWidth() - 88, 16))
                if im.Button("Edit", {70, 28}) {
                    bufferSet(state.ui.macroDirectoryNameInput[:], name)
                    path := strings.trim_space(bufferString(directory.path[:]))
                    if i == 0 {
                        path = default_macro_dir if default_macro_err == nil else "Unavailable"
                    }
                    bufferSet(state.ui.macroDirectoryPathInput[:], path)
                    state.ui.macroDirectoryEditIndex = i
                    state.ui.openMacroDirectoryEditorPopup = true
                }
                im.PopID()
                if i + 1 < state.settings.macroDirectoryCount do im.Separator()
            }
        }
        im.EndChild()

        im.BeginDisabled(state.settings.macroDirectoryCount >= MAX_MACRO_DIRECTORIES)
        if im.Button("Add Directory", {140, 34}) {
            bufferSet(state.ui.macroDirectoryNameInput[:], "")
            bufferSet(state.ui.macroDirectoryPathInput[:], "")
            state.ui.macroDirectoryEditIndex = -1
            state.ui.openMacroDirectoryEditorPopup = true
        }
        im.EndDisabled()
        drawMacroDirectoryEditorPopup(state)
        if default_macro_err == nil {
            delete(default_macro_dir)
        }

        im.Dummy({0, 12})
        im.SeparatorText("Send Hotkey")
        if im.RadioButton("Enter", state.settings.sendHotkey == .Enter) {
            state.settings.sendHotkey = .Enter
            state.settings.dirty = true
        }
        if im.RadioButton("Shift + Enter", state.settings.sendHotkey == .ShiftEnter) {
            state.settings.sendHotkey = .ShiftEnter
            state.settings.dirty = true
        }

        im.Dummy({0, 12})
        im.SeparatorText("Theme")
        if im.RadioButton("Dark", state.settings.theme == .Dark) {
            state.settings.theme = .Dark
            state.settings.dirty = true
        }
        if im.RadioButton("Soft", state.settings.theme == .Soft) {
            state.settings.theme = .Soft
            state.settings.dirty = true
        }
        if im.RadioButton("Light", state.settings.theme == .Light) {
            state.settings.theme = .Light
            state.settings.dirty = true
        }

        im.Dummy({0, 12})
        im.Separator()
        if im.Button("Back", {120, 36}) {
            state.ui.scene = .Home
        }
    }
    im.EndChild()
}
