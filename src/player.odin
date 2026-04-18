package main

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
    
    slip: f32 = airborne? f32(1.0) : p.ground_slip
    
    p.x += p.vx
    p.z += p.vz

    if p.prev_slip == -1 do p.prev_slip = slip

    p.vx *= f64(f32(0.91) * p.prev_slip)
    p.vz *= f64(f32(0.91) * p.prev_slip)

    if abs(p.vx) < p.inertia_threshold do p.vx = 0
    if abs(p.vz) < p.inertia_threshold do p.vz = 0

    accel: f64
    if airborne {
        accel = f64(f32(0.02))
    } else {
        accel = f64(f32(0.1))
        if p.speed > 0 do accel *= 1.0 + f64(f32(0.2)) * f64(p.speed)
        if p.slow  > 0 do accel *= 1.0 + f64(f32(-0.15)) * f64(p.slow)
        if accel < 0 do accel = 0
    }

    if (sprint && (!airborne || !p.sprint_delay)) || (p.prev_sprint && p.sprint_delay && airborne) {
        accel *= 1.300000011920929
    }

    accelf := f32(accel)

    if !airborne {
        drag := f32(0.91) * slip
        accelf *= f32(0.16277136) / (drag * drag * drag)
    }

    if sprint && jump {
        rad := p.f * f32(0.017453292)
        p.vx -= f64(sinr(rad) * f32(0.2))
        p.vz += f64(cosr(rad) * f32(0.2))
    }

    if sneak {
        forward *= f32(0.3)
        strafe  *= f32(0.3)
    }

    forward *= f32(0.98)
    strafe  *= f32(0.98)

    dist2 := f32(forward * forward + strafe * strafe)
    if dist2 > f32(1.0) {
        accelf /= math.sqrt_f32(dist2)
    }

    forward *= accelf
    strafe *= accelf

    p.vx += f64(strafe * cos(p.f) - forward * sin(p.f))
    p.vz += f64(forward * cos(p.f) + strafe * sin(p.f))

    p.prev_slip = slip
    p.prev_sprint = sprint

}