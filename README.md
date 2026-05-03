# Mothmotica 

> State: Work In Progress

Mothball awakened, this project wouldn't be mothballed.

**This is a Mothball language editor, Credits:**
- Original [Mothball](https://github.com/CyrenArkade/mothball) (by CyrenArkade)
- [Extended Mothball](https://github.com/anon-noob/mothball) (forked, by Anonnoob)
- [MothballApp2](https://github.com/anon-noob/mothballapp2) (by Anonnoob)

Mothmotica adds more stratfinding features to the existing mothball, the syntax was also modified to make more sense in a PC editor (the original mothball syntax is more suitable for discord/mobile users)

Like Odin, the language it is implemented in, Mothmotica emphasizes clarity, simplicity, and **the joy of Mothballing.**

## Modified Mothball (Compared to Anonnoob's extended mothball)

### Use `{}` for code block:

In original mothball, the repeat function `r(...)` had such syntax:

```
r(strat, times)

Example:
r(sj(3) s.wa sa(8) outz outx x(0), 50)
```

In the example above, the entire `sj(3) s.wa sa(8) outz outx x(0)` is treated as an argument, strat. However, it consists of several commands, and several "identifiers" should really be separated by comma. But they are separated by spaces here, it is clearly a different structure.

In **Mothmotica**:

```
r(times){
    strat 
}

Example:
r(50){
    sj(3) s.wa sa(8) outz outx x(0)
}
```

### Explicit `inv()`:

In original mothball, there exists `bwmm/inv/speedreq` each differed by more/less a player hitbox width. But mothmotica prefers to add player hitbox width via the **built-in variable `bx = f32(0.6)`**

Instead of `bwmm(n, ...), speedreq(n, ..)`. We use `inv(n + bx){...} ,  inv(n - bx){...}`.

Now you don't have to worry about whether to use `xinv(n){zbwmm(m) {...}}` or `xzinv(n, m+bx){...}` or `xzbwmm(n-bx, m){...}` Just keep it simple. The syntax sugar isn't worth it.

Also the names `bwmm/speedreq` were not accurate at all: `bwmm` could output forward speed, `speedreq` could represent double walled momentum. Honestly it may get really confusing and I don't think it is a good practice.

### Savestates:

Look at this:

```
;s inv(5 + bx){ sj45(12) sj45(12)} | 
save("mm") 

print("Normal:") 
poss(0.01){sj45(25)}

print("Ladder:") load("mm") 
poss(0.01, bx/2){sj45(25)}

print("Blockage:") load("mm") 
poss(0.01, 0){sj45(25)}
```

Output:
```
Lerped Vz: -0.249583
Normal:
Poss: (t = 1...25, thres = 0.01)
t = 2: 1.5 + 0.000551
t = 6: 2.875 + 0.007956
t = 10: 4.1875 + 0.006573
t = 17: 6.375 + 0.005338
t = 23: 8.1875 + 0.001976
Ladder:
Poss: (t = 1...25, thres = 0.01)
t = 9: 3.5625 + 0.009111
t = 19: 6.6875 + 0.00077
Blockage:
Poss: (t = 1...25, thres = 0.01)
t = 3: 1.25 + 0.004408
t = 5: 1.9375 + 0.007608
t = 8: 2.9375 + 0.008328
t = 20: 6.6875 + 0.002733
```

In this particular example, the savestate could be replaced by storing the velocity in a variable and resetting the vz to that variable.(Although savestate is more readable) 

But there is so much more you can do with savestates.

### Powerful Player Set/Output function

| Command | What it does |
| --- | --- |
| `\|` | `pos(0, 0)` |
| `\|\|` | `pos(0, 0)` + `vel(0, 0)` |
| `x(n)` | Set `X = n` |
| `z(n)` | Set `Z = n` |
| `pos(n, m)` | Set `(X,Z) = (n, m)` |
| `vx(n)` | Set `Vx = n` |
| `vz(n)` | Set `Vz = n` |
| `vel(n, m)` | Set `(Vx,Vz) = (n, m)` |
| `f(n)` | Set `facing = n` degrees |
| `t(n)` | Turn facing by `n` degrees |
| `xr` / `outx` | Output `X` |
| `zr` / `outz` | Output `Z` |
| `xb` | Output `X + bx` |
| `zb` | Output `Z + bx` |
| `xmm` | Output `X - bx` |
| `zmm` | Output `Z - bx` |
| `xld` | Output `X + bx/2` |
| `zld` | Output `Z + bx/2` |
| `outvx` | Output `Vx` |
| `outvz` | Output `Vz` |
| `vec` | Output speed and angle |
| `outf` | Output facing |
| `outt` | Output turn/facing |

### `print()/printn()` and `mes()`

`print()` accepts multiple arguments and tries to print its text or value separated by `' '` char.

`printn()`'s separator char is empty, allowing more flexible formatting.

Like:

```
;s 
set(i,0) set(a,0) set(b,1) 
printn(i,"th fibonacci: ",a)
set(i,i+1)
printn(i,"th fibonacci: ",b) 
r(8){
    set(i,i+1) set(c,a+b) 
    printn(i,"th fibonacci: ",c) 
    set(a,b) set(b,c)
}
```

Output:
```
0th fibonacci: 0
1th fibonacci: 1
2th fibonacci: 1
3th fibonacci: 2
4th fibonacci: 3
5th fibonacci: 5
6th fibonacci: 8
7th fibonacci: 13
8th fibonacci: 21
9th fibonacci: 34
```

`mes()` ( full name `measure()`) is really good for debugging

It accept multiple variables like `mes(var1, var2, var3)`
And it outputs like `(var1, var2, var3) = (3.5, -4, 0.67)` in a single line.

Apart from variables, you can put in built-in identifier `x/xb/xmm/xld/z/zb/zmm/zld/vx/vz/f/t` to measure the state of the player. Like:

```
;s f(15) wj.wd sa.wd(11) s.wd mes(x,z,vx,vz)
```

Output:
```
(x, z, vx, vz) = (-1.507294, 0.870365, -0.274478, 0.158493)
```

### Explcit speed-type support: `gnd` and `air`

From the original mothball README:

> Finding the speed required for a 5 block, no 45: `sta speedreq(5, sj(12)) b`. Note the sta before the speedreq. This is to make the player start midair, since mothball usually assumes the player starts on the ground.

As you can see, they use `sta` to hint the next velocity is going to be airborned. This works by implicitly setting `player.prev_sprint` into `airslip(=1.0)`

That works in mothmotica, but we prefer to use `air` for explicitly setting player's `prev_sprint` to `airslip`.

Example 1:
```
;s air inv(2.5+bx){sj45(12) zmm} | poss(0.005){sj45(25)}
```

Output:

```
Lerped Vz: 0.086059
Zmm: 2.5
Poss: (t = 1...25, thres = 0.005)
t = 11: 4.375 + 0.000153
t = 19: 6.8125 + 0.003243
```

Example 2:

```
;s gnd inv(1.3125){sa(11) zr} outvz
```

```
Lerped Vz: 0.057208
Z: 1.3125
Vz: 0.192659
```

> Note: `zr` (Z Raw) is an alias to `outz`

### Read only variables: `getx`,`getz`,`getvx`,`getvz`,`getf`

In mothball, although you can do `var(a, outx)` to store the current x position into variable `a`. But the `outx` command also execute and prints the line. Which is a really stupid design.

> I quit making a number guessing game in mothball because that outx/z cannot shut up

(Note that mothmotica uses `set()` instead of `var()`)

In mothmotica, we can do `set(a, getx)` and it will be silent. Or even `set(b, getx * getz + getz)`. Just treat it as a variable that you cannot modify it with `set()`.

### Force inertia next tick with `ix` and `iz`

Sometimes you hate movement branching or just want to test what if next tick hits inertia. Use this. 

### Handy math functions: `abs()`,`sqrt()`,`sin()`,`cos()`,`tan()`,`atan()`

I don't think I need to explain anything of it except that **the unit of angle is always in degrees.**

Tip: `pi` is a built-in variable.

## A Few Examples (Guide/Wiki WIP):

**1.1875bm jumps**
```
Chat:
;s wj.s(2) wa.sa(2) wa.s(8) w.s zmm(-1.1875) | sj45(12) zmm(1.1875) | poss(0.02){ sj45(25)}

Mothball:
Zmm: -1.1875 + 0.403479
Zmm: 1.1875 - 0.000008
Poss: (t = 1...25, thres = 0.02)
t = 1: 0.8125 + 0.015714
t = 12: 4.4375 + 0.013197
t = 13: 4.75 + 0.000981
t = 17: 5.9375 + 0.005244
t = 20: 6.8125 + 0.016381
t = 24: 8 + 0.003147
```

**slowness I 1.5bm 6-1 to ladder**
```
Chat:
;s pre(9) f(45.01) slow(1) inv(1.5+bx){ sj(1,0) sa.wa(11) zmm} | sj(1,0) sa.wa(14) zld(5)

Mothball:
Lerped Vz: -0.127684424
Zmm: 1.5
Zld: 5 + 0.000000137
```
