vsetvli a0, a1, e32, m1, ta, ma
vle32.v v8, (a0)
vse32.v v8, (a0)
vadd.vv v8, v8, v16
vmul.vv v8, v8, v16
vadd.vv v8, v8, v16
vfadd.vv v8, v8, v16
vfmul.vv v8, v8, v16
vredsum.vs v8, v8, v16
vslide1up.vx v24, v8, a0
vrgather.vv v24, v8, v16
vcompress.vm v8, v16, v0

vsetvli a0, a1, e32, m4, ta, ma
vle32.v v8, (a0)
vse32.v v8, (a0)
vadd.vv v8, v8, v16
vmul.vv v8, v8, v16
vfadd.vv v8, v8, v16
vfmul.vv v8, v8, v16

vsetvli a0, a1, e32, m8, ta, ma
vle32.v v8, (a0)
vse32.v v8, (a0)
vadd.vv v8, v8, v16
vredsum.vs v8, v8, v16
