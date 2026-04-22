package main

import "core:fmt"
import "core:math"


Player :: struct {
    x: f64,
    z: f64,
    vx: f64,
    vz: f64,
    f: f32,
    ground_slip: f32,
    prev_slip: f32,
    prev_sprint: bool,
    speed: u8,
    slow: u8,
    inertia_threshold: f64,
    sprint_delay: bool,
}

makePlayer :: proc() -> Player {
    return Player{ground_slip = 0.6, prev_slip = -1, inertia_threshold = 0.005, sprint_delay = true}
    
}

move :: proc(p: ^Player, w: f32, a: f32, airborne: bool, sprint: bool, sneak: bool, jump: bool){
    forward: f32 = w
    strafe: f32 = a
    
    slip: f32 = airborne ? 1.0 : p.ground_slip
    
    p.x += p.vx
    p.z += p.vz

    if p.prev_slip == -1 do p.prev_slip = slip

    p.vx *= f64(f32(0.91) * p.prev_slip)
    p.vz *= f64(f32(0.91) * p.prev_slip)

    if abs(p.vx) < p.inertia_threshold do p.vx = 0
    if abs(p.vz) < p.inertia_threshold do p.vz = 0

    // The magic number arise from f64(f32(x)) 
    // Odin skips the inner f32()
    // I had to resort to using the converted f32 value

    accel: f64
    if airborne {
        accel = widenf32(0.02)
    } else {
        accel = widenf32(0.1)

        if p.speed > 0 do accel *= 1 + widenf32(0.2) * f64(p.speed)
        if p.slow  > 0 do accel *= 1 + widenf32(-0.15)  * f64(p.slow)
        if accel < 0 do accel = 0
    }

    if (sprint && (!airborne || !p.sprint_delay)) || (p.prev_sprint && p.sprint_delay && airborne) {
        accel *= 1 + widenf32(0.3) // f64(1 + f32(0.3)))
    }

    accelf := f32(accel)

    drag: f32 = 0
    if !airborne {
        drag = f32(0.91) * slip
        accelf *= f32(0.16277136) / (drag * drag * drag)
    }

    if sprint && jump {
        rad := p.f * f32(0.017453292)
        p.vx -= f64(sinr(rad) * f32(0.2))
        p.vz += f64(cosr(rad) * f32(0.2))
        // I believe sinr(rad) returns a runtime f32 value so it'll be fine
    }

    if sneak {
        forward *= f32(0.3)
        strafe  *= f32(0.3)
    }

    forward *= f32(0.98)
    strafe  *= f32(0.98)

    dist2: f32 = forward * forward + strafe * strafe
    if dist2 > 1.0 {
        accelf /= f32(math.sqrt(f64(dist2)))
    }

    forward *= accelf
    strafe *= accelf

    p.vx += f64(strafe * cos(p.f) - forward * sin(p.f))
    p.vz += f64(forward * cos(p.f) + strafe * sin(p.f))

    p.prev_slip = slip
    p.prev_sprint = sprint
}

setF :: proc(p: ^Player, rot: f32) {
    p.f = rot
}

setX :: proc(p: ^Player, value: f64) {
    p.x = value
}

setZ :: proc(p: ^Player, value: f64) {
    p.z = value
}

setVx :: proc(p: ^Player, value: f64, airborne: bool) {
    p.vx = value
    p.prev_slip = 1.0 if airborne else p.ground_slip
}

setVz :: proc(p: ^Player, value: f64, airborne: bool) {
    p.vz = value
    p.prev_slip = 1.0 if airborne else p.ground_slip
}

setVel :: proc(p: ^Player, x_value: f64, z_value: f64, airborne: bool) {
    p.vx = x_value
    p.vz = z_value
    p.prev_slip = 1.0 if airborne else p.ground_slip
}

saveState :: proc(p: Player) -> Player {
    return p
}

loadState :: proc(dst: ^Player, src: Player) {
    dst^ = src
}

setPrevSprint :: proc(p: ^Player, value: bool) {
    p.prev_sprint = value
}

setEffect :: proc(p: ^Player, speed: u8, slow: u8) {
    p.speed = speed
    p.slow = slow
}