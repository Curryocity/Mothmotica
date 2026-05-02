# Mothmotica 

> State: Work In Progress

Mothball awaken, this project wouldn't be mothballed.

**This is an Mothball Language editor, Credits:**
- Original [Mothball](https://github.com/CyrenArkade/mothball) (by CyrenArkade)
- [Extended Mothball](https://github.com/anon-noob/mothball) (forked, by Anonnoob)
- [MothballApp2](https://github.com/anon-noob/mothballapp2) (by Anonnoob)

Mothmotica adds more stratfinding features to the existing mothball, the syntax were also modified to make more sense in a PC editor (the original mothball syntax is more suitable for discord/mobile users)

Like the language it was implemented in, Odin, mothmotica also emphasizes clarity, simplicity and **the joy of Mothballing.**

## Modified Mothball (Compared to Anonnoob's extended mothball)

#### Use `{}` for code block:

In original mothball, the repeat function `r(...)` had such syntax:

```
r(strat, times)

Example:
r(sj(3) s.wa sa(8) outz outx x(0), 50)
```

In the example above, the entire `sj(3) s.wa sa(8) outz outx x(0)` is treated as an argument, strat. However, it consists of several commands, and several "identifiers" should really be separated by comma. But they are seperated by spaces here, it is clearly a different structure.

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


## A Few Examples (Guide/Wiki WIP):

**1bm 5-1**
```text
Chat:
;s pre(16) f(33.8) wa.sd(1) wj.sd(12) w.sd zmm | sj.wa f(0) sa45(11) zmm | sj45(14) zb

Mothball:
Zmm: -0.9645575333436178
Zmm: 0.9999674696973333
Zb: 5.0044307480362358
```

**1.1875bm 4.4375b**
```
Chat:
;s wj.s(2) wa.sa(2) wa.s(8) w.s zmm(-1.1875) | sj45(12) zmm(1.1875) | sj45(12) zb(4.4375)

Mothball:
Zmm: -1.1875 + 0.403479
Zmm: 1.1875 - 0.000008
Zb: 4.4375 + 0.013197
```

**slowness I 1.5bm 6-1 to ladder**
```
Chat:
;s pre(9) slow(1) inv(1.5+bx){ sj sa.wa(11,45.01) zmm} | poss(0.02, bx/2){sj sa.wa(24,45.01)}

Mothball:
Lerped Vz: -0.127684424
Zmm: 1.5
Poss: (t = 1...25, thres = 0.02)
t = 10: 3.5 + 0.009757577
t = 14: 4.6875 + 0.016093186
t = 15: 5 + 0.000000137
t = 18: 5.875 + 0.01039939
t = 21: 6.75 + 0.016182457
t = 24: 7.625 + 0.018486902
```

**debug**
```
Chat:
;s f(15) wj.wd sa.wd(11) s.wd mes(x,z,vx,vz) vec

Mothball:
(x, z, vx, vz) = (-1.507294, 0.870365, -0.274478, 0.158493)
(Speed/Angle) (0.316952, 30.003662)
```

**fibonacci time**
```
Chat:
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

Mothball:
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

**Savestates**

```
Chat:
;s pre(16) inv(5 + bx){ sj45(12) sj45(12)} | save("mm") 
print("Normal:") poss(0.01){sj45(25)}
print("Ladder:") load("mm") poss(0.01, bx/2){sj45(25)}
print("Blockage:") load("mm") poss(0.01, 0){sj45(25)}

Mothball:
Lerped Vz: -0.2495832400300028
Normal:
Poss: (t = 1...25, thres = 0.01)
t = 2: 1.5 + 0.0005505595011548
t = 6: 2.875 + 0.00795550362125
t = 10: 4.1875 + 0.0065730441414464
t = 17: 6.375 + 0.0053375311914863
t = 23: 8.1875 + 0.0019762212056911
Ladder:
Poss: (t = 1...25, thres = 0.01)
t = 9: 3.5625 + 0.0091108086188942
t = 19: 6.6875 + 0.0007703568550106
Blockage:
Poss: (t = 1...25, thres = 0.01)
t = 3: 1.25 + 0.0044081298542935
t = 5: 1.9375 + 0.0076080373176459
t = 8: 2.9375 + 0.0083281413311118
t = 20: 6.6875 + 0.0027332776700701
```


