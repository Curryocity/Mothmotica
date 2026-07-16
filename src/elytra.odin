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

	// Minecraft 1.21.3 uses the float Mth lookup-table trig here.
	cos_yaw   := cosr(yaw_rad)
	sin_yaw   := sinr(yaw_rad)
	cos_pitch := cosr(pitch_rad)
	sin_pitch := sinr(pitch_rad)

	look_x := f64(sin_yaw * cos_pitch)
	look_z := f64(cos_yaw * cos_pitch)

	look_h  := math.sqrt(look_x*look_x + look_z*look_z)
	speed_h := math.sqrt(p.vx*p.vx + p.vz*p.vz)

	// Minecraft 1.21.3 uses Math.cos here, not the lookup-table cosine.
	cos_lift := math.cos(f64(pitch_rad))
	lift := cos_lift * cos_lift
	gravity := GRAVITY
	if p.slow_falling && p.vy <= 0 {
		gravity = SLOW_FALL_GRAVITY
	}

	vx := p.vx
	vy := p.vy + gravity*(-1.0 + lift*0.75)
	vz := p.vz

	// Falling generates speed in the horizontal look direction.
	if vy < 0 && look_h > 0 {
		change := vy * -0.1 * lift

		vx += look_x * change / look_h
		vy += change
		vz += look_z * change / look_h
	}

	// Looking upward converts horizontal speed into climb.
	if pitch_rad < 0 && look_h > 0 {
		change := speed_h * -f64(sin_pitch) * 0.04

		vx -= look_x * change / look_h
		vy += change * 3.2
		vz -= look_z * change / look_h
	}

	// Turn the horizontal velocity toward the horizontal look direction.
	if look_h > 0 {
		vx += (look_x/look_h*speed_h - vx) * 0.1
		vz += (look_z/look_h*speed_h - vz) * 0.1
	}

	p.vx = vx * HORIZONTAL_DRAG
	p.vy = vy * VERTICAL_DRAG
	p.vz = vz * HORIZONTAL_DRAG

	p.prev_elytra = true
}
