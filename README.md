# Mothballn't

An Odin version of Mothball with improved syntax and more powerful stratfinding features. While maintaining simplicity and joy of Mothballing :) 

## Example:

```text
Chat:
;s pre(16) f(33.8) wa.sd(1) wj.sd(12) w.sd zmm | sj.wa f(0) sa45(11) zmm | sj45(14) zb

Mothball:
Zmm: -0.9645575333436178
Zmm: 0.9999674696973333
Zb: 5.0044307480362358

Chat:
;s wj.s(2) wa.sa(2) wa.s(8) w.s zmm(-1.1875) | sj45(12) zmm(1.1875) | sj45(12) zb(4.4375)

Mothball:
Zmm: -1.1875 + 0.403479
Zmm: 1.1875 - 0.000008
Zb: 4.4375 + 0.013197

Chat:
;s set(a,0) set(b,1) x(a) outx x(b) outx r(8){set(c,a+b) x(c) outx set(a,b) set(b,c)}

Mothball:
X: 0
X: 1
X: 1
X: 2
X: 3
X: 5
X: 8
X: 13
X: 21
X: 34
```
