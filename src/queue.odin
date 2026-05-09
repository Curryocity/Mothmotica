package main

Queue :: struct($T: typeid) {
    data: [dynamic]T,
    head: int,
}

qLen :: proc(q: ^Queue($T)) -> int {
    return len(q.data) - q.head
}

qEmpty :: proc(q: ^Queue($T)) -> bool {
    return len(q.data) == q.head
}

qAdd :: proc(q: ^Queue($T), xs: ..T) {
    append(&q.data, ..xs)
}

qPeek :: proc(q: ^Queue($T)) -> (T, bool) {
    if q.head >= len(q.data) {
        return T{}, false
    }

    return q.data[q.head], true
}

qPop :: proc(q: ^Queue($T)) -> (T, bool) {
    if q.head >= len(q.data) {
        resize(&q.data, 0)
        q.head = 0
        return T{}, false
    }

    val := q.data[q.head]
    q.head += 1

    // auto compact
    if q.head > 256 && q.head * 2 > len(q.data) {
        qCompact(q)
    }

    return val, true
}

qClear :: proc(q: ^Queue($T)) {
    q.head = 0
    resize(&q.data, 0)
}

qDelete :: proc(q: ^Queue($T)) {
    delete(q.data)
    q.data = nil
    q.head = 0
}

qCompact :: proc(q: ^Queue($T)) {
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

cloneQueue :: proc(q: Queue($T)) -> Queue(T) {
    out: Queue(T)
    out.head = q.head
    for x in q.data {
        append(&out.data, x)
    }
    return out
}

loadQueue :: proc(dst: ^Queue($T), src: Queue(T)) {
    qClear(dst)
    dst.head = src.head
    for x in src.data {
        append(&dst.data, x)
    }
}

qTailOr :: proc(q: ^Queue($T), fallback: T) -> T {
    if qLen(q) <= 0 do return fallback
    return q.data[len(q.data) - 1]
}
