package main

import "core:fmt"

main :: proc(){
    p := makePlayer()

    bake_trig()

    move(&p, 1, 1, false, true, false, false)

    fmt.println("Hello vz =", p.vz, "!")


    fmt.printf("widen (f64)            = %.17f\n", widenf32(0.1))
}