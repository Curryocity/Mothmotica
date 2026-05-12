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
    forceInertiaX: bool,
    forceInertiaZ: bool,
    inertia_on: bool,
    posRec: bool,
    posStorage: [dynamic] vec2,
    angleQueue: Queue(f32),
    tick: int,
    blockQ: bool,
    soulSandQ: bool,
    ladderQ: bool,
    webQ: bool,
    prev_webQ: bool,
    use_fsj: bool,
    fsj: f32,

    // y states
    y: f64,
    vy: f64,
    prev_vy: f64,
    jump_boost: u8,
    slow_falling: bool,
    ceilQueue: Queue(f64),
    slimeQueue: Queue(f64),
    h: f64,
}

makePlayer :: proc() -> Player {
    return Player{ground_slip = 0.6, prev_slip = -1, inertia_threshold = 0.005, sprint_delay = true, inertia_on = true, h = 1.8}
}


move :: proc(p: ^Player, w: f32, a: f32, airborne: bool, sprint: bool, sneak: bool, jump: bool, tempRot: f32 = 0, usedRot: bool = false, temp45: bool = false) 
{
    // aq, tq overwrites f globally
    if angle, ok := qPop(&p.angleQueue); ok {
        p.f = angle
    }

    rot := p.f
    // fsj override f locally on sj-ticks
    if p.use_fsj && sprint && jump {
        rot = p.fsj
    }
    // tempRot override f and fsj locally
    if usedRot do rot = tempRot
    // 45 always applies (it is not possible to have sj and 45 at the same tick tho)
    if temp45 do rot += 45

    forward: f32 = w
    strafe: f32 = a

    slip: f32 = airborne ? 1.0 : p.ground_slip

    p.x += p.vx
    p.z += p.vz

    // I don't know if it is accurate
    if p.soulSandQ {
        p.vx *= 0.4
        p.vz *= 0.4
    }

    if p.prev_slip == -1 do p.prev_slip = slip

    p.vx *= f64(f32(0.91) * p.prev_slip)
    p.vz *= f64(f32(0.91) * p.prev_slip)

    if (abs(p.vx) < p.inertia_threshold && p.inertia_on) || p.forceInertiaX || p.prev_webQ do p.vx = 0
    if (abs(p.vz) < p.inertia_threshold && p.inertia_on) || p.forceInertiaZ || p.prev_webQ do p.vz = 0

    // only force for one tick
    p.forceInertiaX = false
    p.forceInertiaZ = false

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

    // [Sprint]
    // Air:    accel += accel * 0.3
    // Ground: accel *= 1 + 0.3f (!= 1.3f btw)

    if !airborne && sprint {
        accel *= 1 + widenf32(0.3) // f64(1 + f32(0.3)))
    }else if airborne && (p.prev_sprint && p.sprint_delay || sprint && !p.sprint_delay){
        accel += accel * 0.3
    }

    accelf := f32(accel)

    drag: f32 = 0
    if !airborne {
        drag = f32(0.91) * slip
        accelf *= f32(0.16277136) / (drag * drag * drag)
    }

    if sprint && jump {
        rad := rot * f32(0.017453292)
        p.vx -= f64(sinr(rad) * f32(0.2))
        p.vz += f64(cosr(rad) * f32(0.2))
        // I believe sinr(rad) returns a runtime f32 value so it'll be fine
    }

    if p.blockQ {
        forward *= f32(0.2)
        strafe  *= f32(0.2)
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

    p.vx += f64(strafe * cos(rot) - forward * sin(rot))
    p.vz += f64(forward * cos(rot) + strafe * sin(rot))

    if p.webQ {
        p.vx /= 4
        p.vz /= 4
    }

    if p.ladderQ {
        p.vx = clamp(p.vx, -0.15, 0.15)
        p.vz = clamp(p.vz, -0.15, 0.15)
    }

    p.prev_slip = slip
    p.prev_sprint = sprint
    p.prev_webQ = p.webQ

    if p.posRec {
        append(&p.posStorage, vec2{x = p.x, z = p.z})
    }
    p.tick += 1
}

// Return (ceilq, bounceQ)
moveY :: proc(p: ^Player, jump: bool) -> (bool, bool){ 

    ceilQ, bounceQ: bool
    originalY := p.y
    p.y += p.vy

    p.prev_vy = p.vy

    if !qEmpty(&p.ceilQueue) {
        ceilH, _ := qPeek(&p.ceilQueue)
        if(p.y + p.h >= ceilH && originalY + p.h < ceilH){
            ceilQ = true
            p.y = ceilH - p.h
            p.vy = 0
            qPop(&p.ceilQueue)
        }
    }

    if jump {
        jb_signed := transmute(i8)p.jump_boost
        p.vy = 0.42 + 0.1 * f64(jb_signed)
    } else {
        if !qEmpty(&p.slimeQueue){
            slimeH, _ := qPeek(&p.slimeQueue)
            if(originalY > slimeH && p.y <= slimeH){
                bounceQ = true
                p.y = slimeH
                p.vy = -p.vy
                qPop(&p.slimeQueue)
            }
        }

        gravity := p.slow_falling? 0.01 : 0.08
        p.vy = (p.vy - gravity) * 0.98
  
    }

    if abs(p.vy) < p.inertia_threshold && p.inertia_on do p.vy = 0

    p.tick += 1

    return ceilQ, bounceQ
}

prevGround :: proc(p: ^Player) {
    p.prev_slip = p.ground_slip
}

prevAir :: proc(p: ^Player) {
    p.prev_slip = 1.0
}

saveState :: proc(p: Player) -> Player {
    copy := p
    copy.angleQueue = cloneQueue(p.angleQueue)
    copy.ceilQueue = cloneQueue(p.ceilQueue)
    copy.slimeQueue = cloneQueue(p.slimeQueue)
    copy.posStorage = nil
    for sto in p.posStorage{
        append(&copy.posStorage, sto)
    }
    
    return copy
}

loadState :: proc(dst: ^Player, src: Player) {
    qDelete(&dst.angleQueue)
    qDelete(&dst.ceilQueue)
    qDelete(&dst.slimeQueue)
    delete(dst.posStorage)

    dst^ = src

    dst.angleQueue = cloneQueue(src.angleQueue)
    dst.ceilQueue = cloneQueue(src.ceilQueue)
    dst.slimeQueue = cloneQueue(src.slimeQueue)

    dst.posStorage = nil
    for sto in src.posStorage {
        append(&dst.posStorage, sto)
    }
}

deletePlayerState :: proc(p: ^Player) {
    qDelete(&p.angleQueue)
    qDelete(&p.ceilQueue)
    qDelete(&p.slimeQueue)
    delete(p.posStorage)
    p.posStorage = nil
}

clearPosStorage:: proc(p: ^Player){
    clear(&p.posStorage)
}
