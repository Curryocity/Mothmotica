package main

import "core:math"


Player :: struct {
    // xz states
    x: f64,
    z: f64,
    vx: f64,
    vz: f64,
    f: f32,
    pitch: f32,
    prev_elytra: bool,
    ground_slip: f32,
    prev_slip: f32,
    prev_sprint: bool,
    prev_sneak: bool,
    speed: u8,
    slow: u8,
    sprint_delay: bool,
    sneak_delay: bool,
    forceInertiaX: bool,
    forceInertiaZ: bool,
    posRec: bool,
    posStorage: [dynamic] vec2,
    angleQueue: Queue(f32),
    pitchQueue: Queue(f32),
    offset45: f32,
    w45: f32,
    a45: f32,
    blockQ: bool,
    soulSandQ: bool,

    // y states
    y: f64,
    vy: f64,
    prev_vy: f64,
    jump_boost: u8,
    slow_falling: bool,
    ceilQueue: Queue(f64),
    slimeQueue: Queue(f64),
    h: f64,

    // common states
    tick: int,
    inertia_threshold: f64,
    inertia_on: bool,
    webQ: bool, // todo in ;y
    prev_webQ: bool, 
    ladderQ: bool, // todo in ;y

    /*
    Note about the prev_webQ:
        It doesn't exist in Minecraft's src code.
        It is used to display the velocity "correctly"(the difference of positions)
        It is confusing to see the webbed player constantly moving with 0 velocity.
    */
    
}


makePlayer :: proc() -> Player {
    return Player{
        ground_slip = 0.6,
        prev_slip = -1, 
        inertia_threshold = 0.005, 
        sprint_delay = true, 
        inertia_on = true, 
        offset45 = 45,
        w45 = 1,
        a45 = 1,
        h = 1.8,
    }
}

consumeAngleQueues :: proc(p: ^Player) {
    if pitch, ok := qPop(&p.pitchQueue); ok {
        p.pitch = pitch
    }
    if yaw, ok := qPop(&p.angleQueue); ok {
        p.f = yaw
    }
}

apply_modern_sprint_jump_boost :: proc(p: ^Player, yaw: f32) {
	rad := yaw * f32(0.017453292)
	p.vx -= f64(sinr(rad)) * 0.2
	p.vz += f64(cosr(rad)) * 0.2
}

modern_jump_vy :: proc(jump_boost: u8) -> f64 {
	jump_boost_level := transmute(i8)jump_boost
	return f64(f32(0.42) + f32(0.1) * f32(jump_boost_level))
}

jump_vy :: proc(jump_boost: u8) -> f64 {
	jump_boost_level := transmute(i8)jump_boost
	jump_boost_velocity := f32(0.1) * f32(jump_boost_level)
	return f64(f32(0.42)) + f64(jump_boost_velocity)
}

air_gravity :: proc(p: ^Player, version: MCVersion) -> f64 {
	if version == .V1_21_3 && p.slow_falling && p.vy <= 0 {
		return SLOW_FALL_GRAVITY
	}
	return GRAVITY
}

ladder_fall_limit :: proc(version: MCVersion) -> f64 {
	return version == .V1_21_3 ? -f64(f32(0.15)) : -0.15
}

// Minecraft movement calculation order: Inertia -> Acceleration -> Update Position -> Apply Drag

// Mothball: tried to maintain Vel[t] = Pos[t+1] - Pos[t] property
// It cycles the order: Update Position -> Apply Drag -> Inertia -> Acceleration

moveXZ :: proc(macro: ^Macro, p: ^Player, w: f32, a: f32, airborne: bool, sprint: bool, sneak: bool, jump: bool, tempRot: f32 = 0, usedRot: bool = false, temp45: bool = false)
{
    // aq/tq and pq overwrite the stored look angles globally.
    consumeAngleQueues(p)

    forward: f32 = w
    strafe: f32 = a

    rot := p.f

    if usedRot do rot = tempRot
    if temp45 {
        rot += p.offset45
        forward = p.w45
        strafe = p.a45
    }

    recordMacroTick(macro, forward, strafe, jump, sprint, sneak, rot, p.pitch)
    
    slip: f32 = airborne ? 1.0 : p.ground_slip

    p.x += p.vx
    p.z += p.vz

    // I don't know if it is accurate
    if p.soulSandQ {
        p.vx *= 0.4
        p.vz *= 0.4
    }

    if p.prev_slip == -1 do p.prev_slip = slip

    // post-movement velocity update
    if !p.prev_elytra {
        p.vx *= f64(f32(0.91) * p.prev_slip)
        p.vz *= f64(f32(0.91) * p.prev_slip)
    }
    // END

    if (abs(p.vx) < p.inertia_threshold && p.inertia_on) || p.forceInertiaX || p.prev_webQ do p.vx = 0
    if (abs(p.vz) < p.inertia_threshold && p.inertia_on) || p.forceInertiaZ || p.prev_webQ do p.vz = 0

    // only force for one tick
    p.forceInertiaX = false
    p.forceInertiaZ = false

    accel: f64
    if airborne {
        accel = f64(f32(0.02))
    } else {
        accel = f64(f32(0.1))

        if p.speed > 0 do accel *= 1 + f64(f32(0.2)) * f64(p.speed)
        if p.slow  > 0 do accel *= 1 + f64(f32(-0.15)) * f64(p.slow)
        if accel < 0 do accel = 0
    }

    // [Sprint]
    // Air:    accel += accel * 0.3
    // Ground: accel *= 1 + 0.3f (!= 1.3f btw)

    if !airborne && sprint {
        accel *= 1 + f64(f32(0.3)) // f64(1 + f32(0.3)))
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

    effective_sneak := p.sneak_delay ? p.prev_sneak : sneak
    if effective_sneak {
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
        p.vx *= 0.25
        p.vz *= 0.25
    }

    if p.ladderQ {
        p.vx = clamp(p.vx, -0.15, 0.15)
        p.vz = clamp(p.vz, -0.15, 0.15)
    }

    p.prev_slip = slip
    p.prev_sprint = sprint
    p.prev_sneak = sneak
    p.prev_webQ = p.webQ

    if p.posRec {
        append(&p.posStorage, vec2{x = p.x, z = p.z})
    }
    p.tick += 1
}

// Minecraft 1.21.3 keeps movement input as doubles after the client-side f32 scaling.
moveXZModern :: proc(macro: ^Macro, p: ^Player, w: f32, a: f32, airborne: bool, sprint: bool, sneak: bool, jump: bool, tempRot: f32 = 0, usedRot: bool = false, temp45: bool = false) {
	consumeAngleQueues(p)

	forward: f32 = w
	strafe: f32 = a

	rot := p.f
	if usedRot do rot = tempRot
	if temp45 {
		rot += p.offset45
		forward = p.w45
		strafe = p.a45
	}

	recordMacroTick(macro, forward, strafe, jump, sprint, sneak, rot, p.pitch)

	slip: f32 = airborne ? 1.0 : p.ground_slip

	p.x += p.vx
	p.z += p.vz

	if p.soulSandQ {
		p.vx *= 0.4
		p.vz *= 0.4
	}

	if p.prev_slip == -1 do p.prev_slip = slip

	if !p.prev_elytra {
		p.vx *= f64(f32(0.91) * p.prev_slip)
		p.vz *= f64(f32(0.91) * p.prev_slip)
	}

	if (abs(p.vx) < p.inertia_threshold && p.inertia_on) || p.forceInertiaX || p.prev_webQ do p.vx = 0
	if (abs(p.vz) < p.inertia_threshold && p.inertia_on) || p.forceInertiaZ || p.prev_webQ do p.vz = 0
	p.forceInertiaX = false
	p.forceInertiaZ = false

	accel: f64 = f64(f32(0.1))
	if p.speed > 0 do accel *= 1 + f64(f32(0.2)) * f64(p.speed)
	if p.slow > 0 do accel *= 1 + f64(f32(-0.15)) * f64(p.slow)
	if accel < 0 do accel = 0
	if sprint do accel *= 1 + f64(f32(0.3))

	accelf := f32(accel)
	if airborne {
		if p.prev_sprint && p.sprint_delay || sprint && !p.sprint_delay {
			accelf = f32(0.025999999)
		} else {
			accelf = f32(0.02)
		}
	} else {
		drag_cubed := slip * slip * slip
		accelf *= f32(0.21600002) / drag_cubed
	}

	if sprint && jump {
		apply_modern_sprint_jump_boost(p, rot)
	}

	if p.blockQ {
		forward *= f32(0.2)
		strafe *= f32(0.2)
	}
	effective_sneak := p.sneak_delay ? p.prev_sneak : sneak
	if effective_sneak {
		forward *= f32(0.3)
		strafe *= f32(0.3)
	}

	forward *= f32(0.98)
	strafe *= f32(0.98)

	input_x := f64(strafe)
	input_z := f64(forward)
	input_length_squared := input_x*input_x + input_z*input_z
	if input_length_squared >= 1.0e-7 {
		if input_length_squared > 1 {
			input_length := math.sqrt(input_length_squared)
			input_x /= input_length
			input_z /= input_length
		}

		input_x *= f64(accelf)
		input_z *= f64(accelf)

		yaw_rad := rot * ELYTRA_DEG_TO_RAD
		sin_yaw := f64(sinr(yaw_rad))
		cos_yaw := f64(cosr(yaw_rad))
		p.vx += input_x*cos_yaw - input_z*sin_yaw
		p.vz += input_z*cos_yaw + input_x*sin_yaw
	}

	if p.webQ {
		p.vx *= 0.25
		p.vz *= 0.25
	}
	if p.ladderQ {
		ladder_limit := f64(f32(0.15))
		p.vx = clamp(p.vx, -ladder_limit, ladder_limit)
		p.vz = clamp(p.vz, -ladder_limit, ladder_limit)
	}

	p.prev_slip = slip
	p.prev_sprint = sprint
	p.prev_sneak = sneak
	p.prev_webQ = p.webQ

	if p.posRec {
		append(&p.posStorage, vec2{x = p.x, z = p.z})
	}
	p.tick += 1
}

// called by commands from ctx XZsim ELytraSim
move :: proc(prs: ^ParserState, p: ^Player, w: f32, a: f32, airborne: bool, sprint: bool, sneak: bool, jump: bool, tempRot: f32 = 0, usedRot: bool = false, temp45: bool = false) {
    starting_tick := p.tick
    previous_web := p.prev_webQ

	if prs.ctx == .ElytraSim && !airborne {
		p.vy = 0
		p.prev_vy = 0
	}

	if prs.version == .V1_21_3 {
		moveXZModern(&prs.macro, p, w, a, airborne, sprint, sneak, jump, tempRot, usedRot, temp45)
	} else {
		moveXZ(&prs.macro, p, w, a, airborne, sprint, sneak, jump, tempRot, usedRot, temp45)
	}

    if prs.ctx == .ElytraSim && (jump || airborne) {
        // Simulate Y independently, revert the XZ sim state change
        p.tick = starting_tick
        p.prev_webQ = previous_web
		moveY(p, jump, prs.version)
    }

    p.prev_elytra = false
}

// Return (ceilq, bounceQ)
moveY :: proc(p: ^Player, jump: bool, version := MCVersion.V1_8_9) -> (bool, bool) {

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

    // See the note in the player struct.
    if p.prev_webQ do p.vy = 0

    if jump {
        if version == .V1_21_3 {
            p.vy = max(p.vy, modern_jump_vy(p.jump_boost))
        } else {
            p.vy = jump_vy(p.jump_boost)
        }
    } else {
        if !qEmpty(&p.slimeQueue) && !p.webQ{
            slimeH, _ := qPeek(&p.slimeQueue)
            if(originalY > slimeH && p.y <= slimeH){
                bounceQ = true
                p.y = slimeH
                p.vy = -p.vy
                qPop(&p.slimeQueue)
            }
        }

        // post-movement velocity update
        if !p.prev_elytra {
            p.vy = (p.vy - air_gravity(p, version)) * f64(f32(0.98))
        }
        // END post-movement velocity update

    }

    if p.ladderQ {
        p.vy = max(p.vy, ladder_fall_limit(version))
    }

    if abs(p.vy) < p.inertia_threshold && p.inertia_on do p.vy = 0

    if p.webQ {
        p.vy *= f64(f32(0.05))
    }

    p.prev_webQ = p.webQ
    p.tick += 1

    return ceilQ, bounceQ
}

// Return (ceilq, ok)
moveUp :: proc(p: ^Player, version := MCVersion.V1_8_9) -> (bool, bool) {
    ceilQ, ok: bool

    originalY := p.y
    p.y += p.vy
    p.prev_vy = p.vy

    if !qEmpty(&p.ceilQueue) {
        ceilH, _ := qPeek(&p.ceilQueue)
        if p.y + p.h >= ceilH && originalY + p.h < ceilH {
            ceilQ = true
            p.y = ceilH - p.h
            p.vy = 0
            qPop(&p.ceilQueue)
        }
    }

    // See the note in the player struct.
    if p.prev_webQ do p.vy = 0

    if p.ladderQ {
        p.vy = (0.2 - air_gravity(p, version)) * f64(f32(0.98))
        ok = true
    } else {
        // invalid up action, unless water and lava is implemented
        ok = false
    }

    if abs(p.vy) < p.inertia_threshold && p.inertia_on {
        p.vy = 0
    }

    p.prev_webQ = p.webQ
    p.tick += 1

    return ceilQ, ok
}

// Return (ceilq, ok)
ladderHold :: proc(p: ^Player, version := MCVersion.V1_8_9) -> (bool, bool) {
    if !p.ladderQ {
        p.tick += 1
        return false, false
    }
    
    // See the note in the player struct.
    if p.prev_webQ do p.vy = 0

    if p.vy > 0 {
        ceilQ, _ := moveY(p, false, version)
        return ceilQ, true
    }

    p.y += p.vy
    p.prev_vy = p.vy

    p.vy = 0
    p.prev_webQ = p.webQ
    p.tick += 1
    return false, true
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
    copy.pitchQueue = cloneQueue(p.pitchQueue)
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
    qDelete(&dst.pitchQueue)
    qDelete(&dst.ceilQueue)
    qDelete(&dst.slimeQueue)
    delete(dst.posStorage)

    dst^ = src

    dst.angleQueue = cloneQueue(src.angleQueue)
    dst.pitchQueue = cloneQueue(src.pitchQueue)
    dst.ceilQueue = cloneQueue(src.ceilQueue)
    dst.slimeQueue = cloneQueue(src.slimeQueue)

    dst.posStorage = nil
    for sto in src.posStorage {
        append(&dst.posStorage, sto)
    }
}

deletePlayerState :: proc(p: ^Player) {
    qDelete(&p.angleQueue)
    qDelete(&p.pitchQueue)
    qDelete(&p.ceilQueue)
    qDelete(&p.slimeQueue)
    delete(p.posStorage)
    p.posStorage = nil
}

clearPosStorage:: proc(p: ^Player){
    clear(&p.posStorage)
}
