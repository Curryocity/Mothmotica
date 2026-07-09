package main

import im "../third_party/odin-imgui"
import "../third_party/odin-imgui/imgui_impl_glfw"
import "../third_party/odin-imgui/imgui_impl_opengl3"

import "vendor:glfw"
import gl "vendor:OpenGL"

FONT_SIZE :: f32(18)
SIDE_PAD :: f32(28)
MESSAGE_GAP :: f32(10)
AVATAR_SIZE :: f32(38)
AVATAR_GAP :: f32(12)
MESSAGE_BOX_RIGHT_PAD :: f32(72)
MAX_PAGES :: 32
MAX_MSGS :: 1024
PAGE_TITLE_SIZE :: 128
PATH_SIZE :: 1024
APP_NAME :: "Mothmotica"
SIDEBAR_WIDTH :: f32(240)
AUTOSAVE_INTERVAL_SECONDS :: f64(1.0)

REPO_URL :: "https://github.com/Curryocity/Mothmotica"

Scene :: enum {
    Home,
    Settings,
    Book,
}

BookState :: struct {
    pages: [MAX_PAGES]^Page,
    pageCount: int,
    nextPageID: int,
    curBookPath: [PATH_SIZE]byte,
    curBookName: [PAGE_TITLE_SIZE]byte,
    activePage: int,
}

UIState :: struct {
    scene: Scene,
    showStarred: bool,
    showCreateBookPopup: bool,
    showOpenBookPopup: bool,
    openPath: [PATH_SIZE]byte,
    bookNameInput: [PAGE_TITLE_SIZE]byte,
    titleEdit: [PAGE_TITLE_SIZE]byte,
    editingTitlePage: int,
}

UserSettings :: struct {
    playerName: [PAGE_TITLE_SIZE]byte,
    botName: [PAGE_TITLE_SIZE]byte,
    playerAvatarPath: [PATH_SIZE]byte,
    playerAvatarImportPath: [PATH_SIZE]byte,
    playerAvatarStatus: [256]byte,
    playerAvatarStatusError: bool,
    sendHotkey: SendHotkey,
    theme: Theme,
    dirty: bool,
}

RuntimeState :: struct {
    newMsgQ: bool,
    scrollBottomFrames: int,
    chatPageID: int,
    chatShowStarred: bool,
    shiftEnterQ: bool,
    shiftEnterSignal: bool,
    lastTheme: Theme,
    lastAutosave: f64,
}

AppState :: struct {
    book: BookState,
    ui: UIState,
    settings: UserSettings,
    runtime: RuntimeState,
}

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
    loadBotpfpTex()
    defer destroyBotpfpTex()
    defer destroyPlayerpfpTex()

    applyTheme(.Dark)

    imgui_impl_glfw.InitForOpenGL(window, true)
    defer imgui_impl_glfw.Shutdown()
    imgui_impl_opengl3.Init("#version 150")
    defer imgui_impl_opengl3.Shutdown()

    state := init()

    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        updateSendSignal(window, state)

        imgui_impl_opengl3.NewFrame()
        imgui_impl_glfw.NewFrame()
        im.NewFrame()
        if state.settings.theme != state.runtime.lastTheme {
            applyTheme(state.settings.theme)
            state.runtime.lastTheme = state.settings.theme
        }

        draw(state)
        now := im.GetTime()
        if now - state.runtime.lastAutosave >= AUTOSAVE_INTERVAL_SECONDS {
            saveDirtySettings(state)
            saveDirtyPages(state)
            state.runtime.lastAutosave = now
        }

        im.Render()
        display_w, display_h := glfw.GetFramebufferSize(window)
        gl.Viewport(0, 0, display_w, display_h)
        gl.ClearColor(0.04, 0.04, 0.04, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

        glfw.SwapBuffers(window)
    }

    exit(state)
}

init :: proc() -> ^AppState{
    state := new(AppState)
    state.ui.scene = .Home
    state.book.nextPageID = 1
    state.settings.sendHotkey = .Enter
    state.settings.theme = .Dark
    bufferSet(state.settings.playerName[:], "Me")
    bufferSet(state.settings.botName[:], "Mothball")
    loadSettings(state)
    loadPlayerpfpTex(state)
    applyTheme(state.settings.theme)
    state.runtime.lastTheme = state.settings.theme
    state.runtime.lastAutosave = im.GetTime()
    ensureBooksDir(state)

    return state
}

draw :: proc(state: ^AppState) {
    viewport := im.GetMainViewport()
    im.SetNextWindowPos(viewport.Pos)
    im.SetNextWindowSize(viewport.Size)

    flags := im.WindowFlags_NoDecoration | im.WindowFlags{.NoMove, .NoResize, .NoCollapse}
    if im.Begin("Mothmotica", nil, flags) {
        total := im.GetContentRegionAvail()

        switch state.ui.scene {
        case .Settings:
            if im.BeginChild("Settings", total, {}, {}) {
                drawSettings(state)
            }
            im.EndChild()
        case .Home:
            if im.BeginChild("Home", total, {}, {}) {
                drawHomePage(state)
            }
            im.EndChild()
        case .Book:
            drawBookUI(state)
        }
        
        drawBookPopup(state)
    }
    im.End()
}

exit :: proc(state: ^AppState) {
    for i in 0..<state.book.pageCount {
        if state.book.pages[i] != nil {
            state.book.pages[i].dirty = true
        }
    }
    state.settings.dirty = true
    saveDirtySettings(state)
    saveDirtyPages(state)
    clearPages(state)

    free(state)
}
