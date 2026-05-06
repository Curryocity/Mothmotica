package main

import "core:c"
import "core:strings"

import im "../third_party/odin-imgui"

drawSettings :: proc(state: ^AppState) {
    total := im.GetContentRegionAvail()
    im.Dummy({0, max(total.y * 0.12, 28)})

    im.SetWindowFontScale(1.7)
    title_size := im.CalcTextSize("Settings")
    im.SetCursorPosX(max((im.GetWindowWidth() - title_size.x) * 0.5, SIDE_PAD))
    im.TextColored(titleColor(state.theme), "Settings")
    im.SetWindowFontScale(1)

    panel_w := min(max(total.x * 0.48, 320), 520)
    im.Dummy({0, 18})
    im.SetCursorPosX(max((im.GetWindowWidth() - panel_w) * 0.5, SIDE_PAD))
    if im.BeginChild("SettingsPanel", {panel_w, 0}, {.Borders}, {}) {
        im.AlignTextToFramePadding()
        im.Text("Player Name:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        if im.InputText("##player-name", cstring(&state.playerName[0]), c.size_t(len(state.playerName))) {
            state.settingsDirty = true
        }
        im.AlignTextToFramePadding()
        im.Text("Bot Name:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        if im.InputText("##bot-name", cstring(&state.botName[0]), c.size_t(len(state.botName))) {
            state.settingsDirty = true
        }

        im.SeparatorText("Player Avatar")
        im.AlignTextToFramePadding()
        im.Text("Source Path:")
        im.SameLine()
        im.SetNextItemWidth(-1)
        im.InputText("##player-avatar-path", cstring(&state.playerAvatarPath[0]), c.size_t(len(state.playerAvatarPath)))
        if im.Button("Use Image", {120, 34}) {
            if usePlayerAvatarImage(state) {
                bufferSet(state.settingsStatus[:], "Copied player avatar locally.")
            } else {
                bufferSet(state.settingsStatus[:], "Could not copy player avatar image.")
            }
        }
        im.SameLine()
        if im.Button("Reset", {90, 34}) {
            destroyPlayerAvatarTexture()
            bufferSet(state.playerAvatarPath[:], "")
            state.settingsDirty = true
            bufferSet(state.settingsStatus[:], "Reset player avatar.")
        }
        settings_status := bufferString(state.settingsStatus[:])
        if len(settings_status) > 0 {
            settings_status_c := strings.clone_to_cstring(settings_status)
            defer delete(settings_status_c)
            im.TextColored(mutedColor(state.theme), "%s", settings_status_c)
        }

        im.SeparatorText("Send Hotkey")
        if im.RadioButton("Enter", state.sendHotkey == .Enter) {
            state.sendHotkey = .Enter
            state.settingsDirty = true
        }
        if im.RadioButton("Shift + Enter", state.sendHotkey == .Shift_Enter) {
            state.sendHotkey = .Shift_Enter
            state.settingsDirty = true
        }

        im.SeparatorText("Theme")
        if im.RadioButton("Dark", state.theme == .Dark) {
            state.theme = .Dark
            state.settingsDirty = true
        }
        if im.RadioButton("Soft", state.theme == .Soft) {
            state.theme = .Soft
            state.settingsDirty = true
        }
        if im.RadioButton("Light", state.theme == .Light) {
            state.theme = .Light
            state.settingsDirty = true
        }

        im.Separator()
        if im.Button("Back", {120, 36}) {
            state.showSettings = false
        }
    }
    im.EndChild()
}
