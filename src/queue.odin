package main

Queue :: struct {
    data: [dynamic]f32,
    head: int,
}

qLen :: proc(q: ^Queue) -> int {
    return len(q.data) - q.head
}

qEmpty :: proc(q: ^Queue) -> bool {
    return len(q.data) == q.head
}

qAdd :: proc(q: ^Queue, xs: ..f32){
    append(&q.data, ..xs)
}

qPeek :: proc(q: ^Queue) -> (f32, bool) {
    if q.head >= len(q.data) {
        return 0, false
    }

    return q.data[q.head], true
}

qPop :: proc(q: ^Queue) -> (f32, bool){
    if q.head >= len(q.data) {
        resize(&q.data, 0)
        q.head = 0
        return 0, false
    }

    val := q.data[q.head]
    q.head += 1

    // auto compact
    if q.head > 256 && q.head * 2 > len(q.data) {
        qCompact(q)
    }

    return val, true
}

qClear :: proc(q: ^Queue){
    q.head = 0
    resize(&q.data, 0)
}

qDelete :: proc(q: ^Queue) {
    delete(q.data)
    q.data = nil
    q.head = 0
}

qCompact :: proc(q: ^Queue) {
    if q.head <= 0 do return

    n := qLen(q)

    if n <= 0 {
        resize(&q.data, 0)
        q.head = 0
        return
    }

    for i in 0..<n {
        q.data[i] = q.data[i + q.head]
    }

    q.head = 0
    resize(&q.data, n)
}

cloneQueue :: proc(q: Queue) -> Queue {
    out: Queue
    out.head = q.head
    for x in q.data {
        append(&out.data, x)
    }
    return out
}

loadQueue :: proc(dst: ^Queue, src: Queue) {
    qClear(dst)
    dst.head = src.head
    for x in src.data {
        append(&dst.data, x)
    }
}