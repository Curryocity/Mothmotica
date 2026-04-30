package main

import "core:math"

PIf: f32 = 3.14159265358979323846
PId: f64 = 3.14159265358979323846264338327950288

SIN_TABLE: [65536]f32

widenf32 :: proc(x: f32) -> f64{
    return f64(x)
}

bake_trig :: proc() {
    for i in 0..<65536 {
        SIN_TABLE[i] = f32(math.sin(f64(i) * PId * 2.0 / 65536.0))
    }
}

sinr :: proc(rad: f32) -> f32 {
    return SIN_TABLE[int(rad * 10430.378) & 65535]
}

sin :: proc(deg: f32) -> f32 {
    rad:f32 = deg * PIf / 180.0
    return SIN_TABLE[int(rad * 10430.378) & 65535]
}

cosr :: proc(rad: f32) -> f32 {
    return SIN_TABLE[int(rad * 10430.378 + 16384.0) & 65535]
}

cos :: proc(deg: f32) -> f32 {
    rad:f32 = deg * PIf / 180.0
    return SIN_TABLE[int(rad * 10430.378 + 16384.0) & 65535]
}