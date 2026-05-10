package main

import "core:c"
import "core:os"
import "core:strings"
import im "../third_party/odin-imgui"

Settings :: struct {
    version: int,
    player_name: string,
    bot_name: string,
    player_pfp_path: string,
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

        im.SeparatorText("Send Hotkey")
        if im.RadioButton("Enter", state.settings.sendHotkey == .Enter) {
            state.settings.sendHotkey = .Enter
            state.settings.dirty = true
        }
        if im.RadioButton("Shift + Enter", state.settings.sendHotkey == .ShiftEnter) {
            state.settings.sendHotkey = .ShiftEnter
            state.settings.dirty = true
        }

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

        im.Separator()
        if im.Button("Back", {120, 36}) {
            state.ui.scene = .Home
        }
    }
    im.EndChild()
}
