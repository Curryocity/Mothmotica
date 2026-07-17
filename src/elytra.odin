package main

import "core:math"

ELYTRA_DEG_TO_RAD :: f32(0.017453292)

HORIZONTAL_DRAG :: 0.9900000095367432
VERTICAL_DRAG :: 0.9800000190734863
GRAVITY :: 0.08
SLOW_FALL_GRAVITY :: 0.01

elytra_tick :: proc(p: ^Player, pitch: f32, yaw: f32) {

    p.x += p.vx
	p.y += p.vy
	p.z += p.vz

    elytra_vel_update(p, pitch, yaw)
}

// Modelled from Minecraft 1.21.3
elytra_vel_update :: proc(p: ^Player, pitch: f32, yaw: f32) {

    // post movement update from non-elytra tick
    if !p.prev_elytra {
        p.vx *= f64(f32(0.91) * p.prev_slip)
        p.vz *= f64(f32(0.91) * p.prev_slip)
        
        gravity := p.slow_falling ? widenf32(0.01) : widenf32(0.08)
        p.vy = (p.vy - gravity) * widenf32(0.98)
    }

	if math.abs(p.vx) < p.inertia_threshold do p.vx = 0
	if math.abs(p.vy) < p.inertia_threshold do p.vy = 0
	if math.abs(p.vz) < p.inertia_threshold do p.vz = 0

	clamped_pitch := clamp(pitch, -90.0, 90.0)

	pitch_rad := clamped_pitch * ELYTRA_DEG_TO_RAD
	yaw_rad   := -yaw * ELYTRA_DEG_TO_RAD

	cos_yaw   := cosr(yaw_rad)
	sin_yaw   := sinr(yaw_rad)
	cos_pitch := cosr(pitch_rad)
	sin_pitch := sinr(pitch_rad)

	proj_x := f64(sin_yaw * cos_pitch)
	proj_z := f64(cos_yaw * cos_pitch)

	proj_xznorm  := math.sqrt(proj_x*proj_x + proj_z*proj_z)
	speed_xz := math.sqrt(p.vx*p.vx + p.vz*p.vz)

	// Minecraft 1.21.3 uses Math.cos here, not the lookup-table
	cos_lift := math.cos(f64(pitch_rad))
	lift := cos_lift * cos_lift
	gravity := GRAVITY
	if p.slow_falling && p.vy <= 0 {
		gravity = SLOW_FALL_GRAVITY
	}

	vx := p.vx
	vy := p.vy + gravity*(-1.0 + lift*0.75)
	vz := p.vz

	// Falling generates speed in the proj_xz direction.
	if vy < 0 && proj_xznorm > 0 {
		yConvert := vy * -0.1 * lift

		vx += proj_x * yConvert / proj_xznorm
		vy += yConvert
		vz += proj_z * yConvert / proj_xznorm
	}

	// Upward pitch converts horizontal speed into climb.
	if pitch_rad < 0 && proj_xznorm > 0 {
		climb := speed_xz * -f64(sin_pitch) * 0.04

		vx -= proj_x * climb / proj_xznorm
		vy += climb * 3.2
		vz -= proj_z * climb / proj_xznorm
	}

	// Accelerate in proj_xz direction
	if proj_xznorm > 0 {
		vx += (proj_x/proj_xznorm*speed_xz - vx) * 0.1
		vz += (proj_z/proj_xznorm*speed_xz - vz) * 0.1
	}

	p.vx = vx * HORIZONTAL_DRAG
	p.vy = vy * VERTICAL_DRAG
	p.vz = vz * HORIZONTAL_DRAG

	p.prev_elytra = true
}

elytra_jump :: proc(p: ^Player, floor_y: f64, pitch: f32, yaw: f32, sprinting: bool) {
    p.x += p.vx
    p.y += p.vy
    p.z += p.vz
    if p.y < floor_y do p.y = floor_y

    p.prev_vy = p.vy

    jb_signed := transmute(i8)p.jump_boost
    p.vy = widenf32(0.42) + widenf32(0.1) * f64(jb_signed)

    if sprinting {
        rad := yaw * f32(0.017453292)
        p.vx -= f64(sinr(rad) * f32(0.2))
        p.vz += f64(cosr(rad) * f32(0.2))
    }

    p.prev_elytra = true
    elytra_vel_update(p, pitch, yaw)
}

elytra_land :: proc(p: ^Player, floor_y: f64, pitch: f32, yaw: f32) {
    p.y = floor_y
    p.vy = 0
    p.prev_vy = 0
    elytra_tick(p, pitch, yaw)
}
