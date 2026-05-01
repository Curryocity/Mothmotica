# Mothballn't

An Odin version of Mothball with improved syntax and more powerful stratfinding features. While maintaining simplicity and joy of Mothballing :) 

## Example:

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


