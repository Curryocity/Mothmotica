package main

import "base:runtime"

import "core:c"
import "core:os"
import "core:strings"

import im "../third_party/odin-imgui"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

monoFont: ^im.Font
bot_pfpTex: u32
user_pfpTex: u32

Theme :: enum {
    Dark,
    Soft,
    Light,
}

loadFonts :: proc(scale: f32) {
    io := im.GetIO()
    font_scale := max(scale, 1)
    font_path := resolveAssetPath("asset/fonts/JetBrainsMono-Regular.ttf")
    defer delete(font_path)

    font_path_c := strings.clone_to_cstring(font_path)
    defer delete(font_path_c)
    monoFont = im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path_c, FONT_SIZE * font_scale)
    im.GetStyle().FontScaleMain = 1 / font_scale

    if monoFont != nil {
        io.FontDefault = monoFont
    }
}

pushMonoFont :: proc() -> bool {
    if monoFont != nil {
        im.PushFontFloat(monoFont, monoFont.LegacySize)
        return true
    }
    return false
}

popFontIf :: proc(pushed: bool) {
    if pushed do im.PopFont()
}

pushTextScale :: proc(scale: f32) {
    im.PushFontFloat(nil, im.GetStyle().FontSizeBase * scale)
}

popTextScale :: proc() {
    im.PopFont()
}

macroPopupBgColor :: proc(theme: Theme) -> im.Vec4 {
    switch theme {
    case .Light:
        return {0.965, 0.975, 0.995, 1}
    case .Soft:
        return {0.135, 0.115, 0.150, 1}
    case .Dark:
        return {0.105, 0.120, 0.165, 1}
    }
    return {0.105, 0.120, 0.165, 1}
}

macroPopupBorderColor :: proc(theme: Theme) -> im.Vec4 {
    switch theme {
    case .Light:
        return {0.410, 0.535, 0.760, 1}
    case .Soft:
        return {0.555, 0.390, 0.620, 1}
    case .Dark:
        return {0.385, 0.490, 0.720, 1}
    }
    return {0.385, 0.490, 0.720, 1}
}

macroPopupTitleColor :: proc(theme: Theme) -> im.Vec4 {
    switch theme {
    case .Light:
        return {0.885, 0.910, 0.965, 1}
    case .Soft:
        return {0.185, 0.145, 0.205, 1}
    case .Dark:
        return {0.125, 0.150, 0.215, 1}
    }
    return {0.125, 0.150, 0.215, 1}
}

resolveAssetPath :: proc(path: string) -> string {
    if os.is_file(path) {
        return strings.clone(path)
    }

    exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
    if exe_dir_err != nil {
        return strings.clone(path)
    }
    defer delete(exe_dir)

    when ODIN_OS == .Darwin {
        resource_path, resource_err := os.join_path({exe_dir, "..", "Resources", path}, context.allocator)
        if resource_err == nil {
            if os.is_file(resource_path) {
                return resource_path
            }
            delete(resource_path)
        }
    }

    joined, join_err := os.join_path({exe_dir, path}, context.allocator)
    if join_err != nil {
        return strings.clone(path)
    }
    return joined
}

loadTextureRGBA :: proc(path: string) -> u32 {
    resolved := resolveAssetPath(path)
    defer delete(resolved)

    path_c := strings.clone_to_cstring(resolved)
    defer delete(path_c)

    width, height, channels: c.int
    pixels := stbi.load(path_c, &width, &height, &channels, 4)
    if pixels == nil || width <= 0 || height <= 0 {
        return 0
    }
    defer stbi.image_free(pixels)

    texture: u32
    gl.GenTextures(1, &texture)
    if texture == 0 {
        return 0
    }

    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.TexImage2D(gl.TEXTURE_2D, 0, i32(gl.RGBA), width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, rawptr(pixels))
    gl.BindTexture(gl.TEXTURE_2D, 0)
    return texture
}

loadBotpfpTex :: proc() {
    bot_pfpTex = loadTextureRGBA(BOT_AVATAR_PATH)
}

destroyBotpfpTex :: proc() {
    if bot_pfpTex != 0 {
        gl.DeleteTextures(1, &bot_pfpTex)
        bot_pfpTex = 0
    }
}

loadPlayerpfpTex :: proc(state: ^AppState) -> bool {
    path := strings.trim_space(bufferString(state.settings.playerAvatarPath[:]))
    if path == "" {
        destroyPlayerpfpTex()
        return false
    }

    texture := loadTextureRGBA(path)
    if texture == 0 {
        return false
    }

    destroyPlayerpfpTex()
    user_pfpTex = texture
    return true
}

usePlayerPfp :: proc(state: ^AppState, source_path: string) -> bool {
    source := strings.trim_space(source_path)
    if source == "" || !os.is_file(source) {
        return false
    }

    avatar_dir, dir_err := userAvatarDir()
    if dir_err != nil {
        return false
    }
    defer delete(avatar_dir)

    if mkdir_err := os.make_directory_all(avatar_dir); mkdir_err != nil && !os.is_dir(avatar_dir) {
        return false
    }

    avatar_path, path_err := playerpfpPath()
    if path_err != nil {
        return false
    }
    defer delete(avatar_path)

    if copy_err := os.copy_file(avatar_path, source); copy_err != nil {
        return false
    }

    bufferSet(state.settings.playerAvatarPath[:], avatar_path)
    if !loadPlayerpfpTex(state) {
        return false
    }

    state.settings.dirty = true
    return true
}

destroyPlayerpfpTex :: proc() {
    if user_pfpTex != 0 {
        gl.DeleteTextures(1, &user_pfpTex)
        user_pfpTex = 0
    }
}

titleColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.120, 0.145, 0.190, 1}
    }
    return {0.93, 0.95, 1.0, 1.0}
}

mutedColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.365, 0.400, 0.475, 1}
    }
    return {0.50, 0.53, 0.61, 1}
}

subTextColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.270, 0.345, 0.500, 1}
    }
    return {0.62, 0.68, 0.78, 1}
}

playerNameColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.490, 0.295, 0.030, 1}
    }
    return {0.95, 0.82, 0.25, 1.0}
}

botNameColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.330, 0.210, 0.560, 1}
    }
    return {0.640, 0.540, 0.940, 1.0}
}

msgBoxBgColor :: proc(theme: Theme, is_draft: bool) -> im.Vec4 {
    if theme == .Light {
        return is_draft ? im.Vec4{0.965, 0.970, 0.982, 1} : im.Vec4{0.935, 0.942, 0.958, 1}
    }
    return is_draft ? im.Vec4{0.085, 0.092, 0.125, 1} : im.Vec4{0.055, 0.060, 0.080, 1}
}

msgBoxBorderColor :: proc(theme: Theme, is_draft: bool) -> im.Vec4 {
    if theme == .Light {
        return is_draft ? im.Vec4{0.720, 0.755, 0.825, 1} : im.Vec4{0.780, 0.800, 0.850, 1}
    }
    return is_draft ? im.Vec4{0.380, 0.450, 0.620, 1} : im.Vec4{0.230, 0.255, 0.330, 1}
}

msgBoxTextColor :: proc(theme: Theme) -> im.Vec4 {
    if theme == .Light {
        return {0.080, 0.090, 0.115, 1}
    }
    return {0.93, 0.94, 0.97, 1}
}

applyTheme :: proc(theme: Theme) {
    if theme == .Light {
        im.StyleColorsLight()
    } else {
        im.StyleColorsDark()
    }

    style := im.GetStyle()
    style.WindowRounding = 7
    style.ChildRounding = 6
    style.FrameRounding = 5
    style.GrabRounding = 4
    style.ScrollbarRounding = 6
    style.WindowBorderSize = 1
    style.FrameBorderSize = 1
    style.WindowPadding = {18, 14}
    style.FramePadding = {10, 7}
    style.ItemSpacing = {10, 9}

    c := &style.Colors
    if theme == .Light {
        c[im.Col.Text] = {0.115, 0.125, 0.150, 1}
        c[im.Col.TextDisabled] = {0.500, 0.535, 0.600, 1}
        c[im.Col.WindowBg] = {0.955, 0.960, 0.972, 1}
        c[im.Col.ChildBg] = {0.985, 0.987, 0.992, 1}
        c[im.Col.PopupBg] = {1.000, 1.000, 1.000, 1}
        c[im.Col.FrameBg] = {0.915, 0.925, 0.945, 1}
        c[im.Col.FrameBgHovered] = {0.875, 0.900, 0.940, 1}
        c[im.Col.FrameBgActive] = {0.820, 0.860, 0.925, 1}
        c[im.Col.Button] = {0.820, 0.865, 0.940, 1}
        c[im.Col.ButtonHovered] = {0.735, 0.800, 0.910, 1}
        c[im.Col.ButtonActive] = {0.635, 0.725, 0.880, 1}
        c[im.Col.Header] = {0.820, 0.865, 0.940, 1}
        c[im.Col.HeaderHovered] = {0.735, 0.800, 0.910, 1}
        c[im.Col.HeaderActive] = {0.635, 0.725, 0.880, 1}
        c[im.Col.Border] = {0.705, 0.735, 0.790, 1}
        c[im.Col.Separator] = {0.780, 0.805, 0.850, 1}
    } else if theme == .Soft {
        c[im.Col.Text] = {0.93, 0.94, 0.97, 1}
        c[im.Col.TextDisabled] = {0.50, 0.53, 0.61, 1}
        c[im.Col.WindowBg] = {0.060, 0.057, 0.068, 1}
        c[im.Col.ChildBg] = {0.082, 0.077, 0.092, 1}
        c[im.Col.PopupBg] = {0.095, 0.088, 0.106, 1}
        c[im.Col.FrameBg] = {0.115, 0.105, 0.128, 1}
        c[im.Col.FrameBgHovered] = {0.145, 0.135, 0.165, 1}
        c[im.Col.FrameBgActive] = {0.180, 0.158, 0.190, 1}
        c[im.Col.Button] = {0.185, 0.155, 0.205, 1}
        c[im.Col.ButtonHovered] = {0.255, 0.200, 0.285, 1}
        c[im.Col.ButtonActive] = {0.335, 0.245, 0.365, 1}
        c[im.Col.Header] = {0.185, 0.155, 0.205, 1}
        c[im.Col.HeaderHovered] = {0.255, 0.200, 0.285, 1}
        c[im.Col.HeaderActive] = {0.335, 0.245, 0.365, 1}
        c[im.Col.Border] = {0.315, 0.270, 0.335, 1}
        c[im.Col.Separator] = {0.260, 0.220, 0.285, 1}
    } else {
        c[im.Col.Text] = {0.93, 0.94, 0.97, 1}
        c[im.Col.TextDisabled] = {0.50, 0.53, 0.61, 1}
        c[im.Col.WindowBg] = {0.035, 0.037, 0.047, 1}
        c[im.Col.ChildBg] = {0.052, 0.055, 0.070, 1}
        c[im.Col.PopupBg] = {0.075, 0.080, 0.100, 1}
        c[im.Col.FrameBg] = {0.080, 0.086, 0.110, 1}
        c[im.Col.FrameBgHovered] = {0.105, 0.114, 0.150, 1}
        c[im.Col.FrameBgActive] = {0.125, 0.140, 0.190, 1}
        c[im.Col.Button] = {0.145, 0.170, 0.235, 1}
        c[im.Col.ButtonHovered] = {0.205, 0.245, 0.340, 1}
        c[im.Col.ButtonActive] = {0.290, 0.350, 0.520, 1}
        c[im.Col.Header] = {0.145, 0.170, 0.235, 1}
        c[im.Col.HeaderHovered] = {0.205, 0.245, 0.340, 1}
        c[im.Col.HeaderActive] = {0.290, 0.350, 0.520, 1}
        c[im.Col.Border] = {0.230, 0.255, 0.330, 1}
        c[im.Col.Separator] = {0.185, 0.205, 0.270, 1}
    }
}
