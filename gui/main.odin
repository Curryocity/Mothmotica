package main

import im "../third_party/odin-imgui"
import "../third_party/odin-imgui/imgui_impl_glfw"
import "../third_party/odin-imgui/imgui_impl_opengl3"

import "vendor:glfw"
import gl "vendor:OpenGL"

main :: proc() {
    assert(cast(bool)glfw.Init())
    defer glfw.Terminate()

    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 2)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1)

    window := glfw.CreateWindow(1100, 720, "Mothmotica", nil, nil)
    assert(window != nil)
    defer glfw.DestroyWindow(window)

    glfw.MakeContextCurrent(window)
    glfw.SwapInterval(1)

    gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
        (cast(^rawptr)p)^ = glfw.GetProcAddress(name)
    })

    im.CHECKVERSION()
    im.CreateContext()
    defer im.DestroyContext()

    io := im.GetIO()
    io.ConfigFlags += {.NavEnableKeyboard}
    xscale, yscale := glfw.GetWindowContentScale(window)
    loadFonts(max(xscale, yscale))
    loadBotAvatarTexture()
    defer destroyBotAvatarTexture()
    defer destroyPlayerAvatarTexture()

    applyTheme(.Dark)

    imgui_impl_glfw.InitForOpenGL(window, true)
    defer imgui_impl_glfw.Shutdown()
    imgui_impl_opengl3.Init("#version 150")
    defer imgui_impl_opengl3.Shutdown()

    state := new(AppState)
    defer free(state)
    state.showHome = true
    state.nextNoteID = 1
    state.sendHotkey = .Enter
    state.theme = .Dark
    bufferSet(state.playerName[:], "Curryocity")
    bufferSet(state.botName[:], "Mothball")
    loadSettings(state)
    loadPlayerAvatarTexture(state)
    applyTheme(state.theme)
    last_theme := state.theme
    last_autosave_time := im.GetTime()
    ensureBooksDir(state)

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        updateShortcuts(window, state)

        imgui_impl_opengl3.NewFrame()
        imgui_impl_glfw.NewFrame()
        im.NewFrame()
        if state.theme != last_theme {
            applyTheme(state.theme)
            last_theme = state.theme
        }
        ensureDraftMsg(activeNote(state))

        draw(state)
        now := im.GetTime()
        if now - last_autosave_time >= AUTOSAVE_INTERVAL_SECONDS {
            saveDirtySettings(state)
            saveDirtyNotes(state)
            last_autosave_time = now
        }

        im.Render()
        display_w, display_h := glfw.GetFramebufferSize(window)
        gl.Viewport(0, 0, display_w, display_h)
        gl.ClearColor(0.04, 0.04, 0.04, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

        glfw.SwapBuffers(window)
    }

    for i in 0..<state.noteCount {
        state.notes[i].dirty = true
    }
    state.settingsDirty = true
    saveDirtySettings(state)
    saveDirtyNotes(state)
}
