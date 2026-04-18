package main

import "core:fmt"

main :: proc(){
    p := makePlayer()

    bake_trig()

    p.f = 45

    move(&p, 1, 1, true, true, false, false)
    move(&p, 1, 1, true, true, false, false)

    fmt.println("Hello vz =", p.vz, "!")
}