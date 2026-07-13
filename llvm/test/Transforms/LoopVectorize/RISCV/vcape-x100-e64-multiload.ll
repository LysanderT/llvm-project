; RUN: opt -passes=loop-vectorize -S %s | FileCheck %s --check-prefix=DEFAULT
; RUN: opt -passes=loop-vectorize -vcape-enable-certificate-decision -S %s | FileCheck %s --check-prefix=DECISION-X100
; RUN: opt -passes=loop-vectorize -vcape-dump-certificate -disable-output %s 2>&1 | FileCheck %s --check-prefix=CERT-X100
; RUN: sed -e 's/spacemit-x100/spacemit-a100/g' -e 's/vscale_range(4,1024)/vscale_range(16,1024)/g' %s | opt -passes=loop-vectorize -vcape-enable-certificate-decision -vcape-dump-certificate -S -o - 2>&1 | FileCheck %s --check-prefix=DECISION-A100
; RUN: sed 's/fmul double/fdiv double/g' %s | opt -passes=loop-vectorize -vcape-dump-certificate -disable-output - 2>&1 | FileCheck %s --check-prefix=CERT-DIV
;
; DECISION-X100-LABEL: define dso_local void @fma1(
; DECISION-X100: vector.body:
; DECISION-X100: <vscale x 2 x double>
;
; DEFAULT-LABEL: define dso_local void @stencil7_coeff_array(
; DEFAULT: vector.body:
; DEFAULT: <vscale x 2 x double>
;
; DECISION-X100-LABEL: define dso_local void @stencil7_coeff_array(
; DECISION-X100-NOT: vector.body:
; DECISION-X100-NOT: <vscale
; DECISION-X100: ret void
;
; CERT-X100: V-CAPE-CERTIFICATE: function=fma1 target=spacemit-x100 vf=vscale x 1 {{.*}}f64_fma_ops=1{{.*}}coverage=none{{.*}}decision=uncovered action=observe
; CERT-X100: V-CAPE-CERTIFICATE: function=stencil7_coeff_array target=spacemit-x100 vf=vscale x 1 sew=64 estimated_lmul=1 f64_unit_loads=14 {{.*}}f64_mul_ops=1 f64_fma_ops=6{{.*}}coverage=x100-e64-unit-load-v2 confidence=medium provenance=placement-v2-20260713 samples=6{{.*}}predicted_ratio_lower_x1000=1630 predicted_ratio_upper_x1000=2810 decision=prefer-scalar action=observe
; CERT-X100: V-CAPE-CERTIFICATE: function=stencil7_coeff_array target=spacemit-x100 vf=vscale x 2 sew=64 estimated_lmul=2 f64_unit_loads=14 {{.*}}coverage=x100-e64-unit-load-v2{{.*}}predicted_ratio_lower_x1000=1583 predicted_ratio_upper_x1000=2980 decision=prefer-scalar action=observe
;
; DECISION-A100: V-CAPE-CERTIFICATE: function=stencil7_coeff_array target=spacemit-a100 vf=vscale x 1 {{.*}}nominal_ratio_x1000=120 coverage=a100-e64-unit-load-v2{{.*}}residual_lower_x1000=124 residual_upper_x1000=3326 predicted_ratio_lower_x1000=244 predicted_ratio_upper_x1000=3446 decision=uncertain action=preserve
; DECISION-A100: V-CAPE-CERTIFICATE: function=stencil7_coeff_array target=spacemit-a100 vf=vscale x 2 {{.*}}nominal_ratio_x1000=115 coverage=a100-e64-unit-load-v2{{.*}}residual_lower_x1000=-107 residual_upper_x1000=100 predicted_ratio_lower_x1000=8 predicted_ratio_upper_x1000=215 decision=robust-vectorize action=accept
; DECISION-A100-LABEL: define dso_local void @stencil7_coeff_array(
; DECISION-A100: vector.body:
; DECISION-A100: <vscale x 2 x double>
;
; CERT-DIV: V-CAPE-CERTIFICATE: function=stencil7_coeff_array target=spacemit-x100 vf=vscale x 1 {{.*}}f64_divrem_ops=1{{.*}}coverage=none{{.*}}decision=uncovered action=observe
;
; Reduced dense e64 multi-load candidate and non-matching positive controls.
; ModuleID = 'vcape-x100-e64-multiload.ll'
source_filename = "/home/lysander/spec-rvv-attribution/v-cape/prototype-test/kernel-controls/vcape_kernel_controls.c"
target datalayout = "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128"
target triple = "riscv64-unknown-linux-gnu"

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable vscale_range(4,1024)
define dso_local void @fma1(ptr noalias nofree noundef writeonly captures(none) %0, ptr noalias nofree noundef readonly captures(none) %1, ptr noalias nofree noundef readonly captures(none) %2, ptr noalias nofree noundef readonly captures(none) %3, i64 noundef %4) local_unnamed_addr #0 {
  %6 = icmp eq i64 %4, 0
  br i1 %6, label %7, label %8

7:                                                ; preds = %8, %5
  ret void

8:                                                ; preds = %5, %8
  %9 = phi i64 [ %18, %8 ], [ 0, %5 ]
  %10 = getelementptr inbounds nuw [8 x i8], ptr %1, i64 %9
  %11 = load double, ptr %10, align 8, !tbaa !13
  %12 = getelementptr inbounds nuw [8 x i8], ptr %2, i64 %9
  %13 = load double, ptr %12, align 8, !tbaa !13
  %14 = getelementptr inbounds nuw [8 x i8], ptr %3, i64 %9
  %15 = load double, ptr %14, align 8, !tbaa !13
  %16 = tail call double @llvm.fmuladd.f64(double %11, double %13, double %15)
  %17 = getelementptr inbounds nuw [8 x i8], ptr %0, i64 %9
  store double %16, ptr %17, align 8, !tbaa !13
  %18 = add nuw i64 %9, 1
  %19 = icmp eq i64 %18, %4
  br i1 %19, label %7, label %8, !llvm.loop !15
}

; Function Attrs: mustprogress nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare double @llvm.fmuladd.f64(double, double, double) #1

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable vscale_range(4,1024)
define dso_local void @stencil3(ptr noalias nofree noundef writeonly captures(none) %0, ptr noalias nofree noundef readonly captures(none) %1, ptr noalias nofree noundef readonly captures(none) %2, i64 noundef %3) local_unnamed_addr #0 {
  %5 = icmp ugt i64 %3, 2
  br i1 %5, label %6, label %12

6:                                                ; preds = %4
  %7 = load double, ptr %2, align 8, !tbaa !13
  %8 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %9 = load double, ptr %8, align 8, !tbaa !13
  %10 = getelementptr inbounds nuw i8, ptr %2, i64 16
  %11 = load double, ptr %10, align 8, !tbaa !13
  br label %13

12:                                               ; preds = %13, %4
  ret void

13:                                               ; preds = %6, %13
  %14 = phi i64 [ 2, %6 ], [ %26, %13 ]
  %15 = phi i64 [ 1, %6 ], [ %14, %13 ]
  %16 = getelementptr [8 x i8], ptr %1, i64 %15
  %17 = getelementptr i8, ptr %16, i64 -8
  %18 = load double, ptr %17, align 8, !tbaa !13
  %19 = load double, ptr %16, align 8, !tbaa !13
  %20 = fmul double %9, %19
  %21 = tail call double @llvm.fmuladd.f64(double %7, double %18, double %20)
  %22 = getelementptr inbounds nuw [8 x i8], ptr %1, i64 %14
  %23 = load double, ptr %22, align 8, !tbaa !13
  %24 = tail call double @llvm.fmuladd.f64(double %11, double %23, double %21)
  %25 = getelementptr inbounds nuw [8 x i8], ptr %0, i64 %15
  store double %24, ptr %25, align 8, !tbaa !13
  %26 = add nuw i64 %14, 1
  %27 = icmp eq i64 %26, %3
  br i1 %27, label %12, label %13, !llvm.loop !18
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable vscale_range(4,1024)
define dso_local void @stencil7(ptr noalias nofree noundef writeonly captures(none) %0, ptr noalias nofree noundef readonly captures(none) %1, ptr noalias nofree noundef readonly captures(none) %2, i64 noundef %3) local_unnamed_addr #0 {
  %5 = icmp ugt i64 %3, 6
  br i1 %5, label %6, label %21

6:                                                ; preds = %4
  %7 = load double, ptr %2, align 8, !tbaa !13
  %8 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %9 = load double, ptr %8, align 8, !tbaa !13
  %10 = getelementptr inbounds nuw i8, ptr %2, i64 16
  %11 = load double, ptr %10, align 8, !tbaa !13
  %12 = getelementptr inbounds nuw i8, ptr %2, i64 24
  %13 = load double, ptr %12, align 8, !tbaa !13
  %14 = getelementptr inbounds nuw i8, ptr %2, i64 32
  %15 = load double, ptr %14, align 8, !tbaa !13
  %16 = getelementptr inbounds nuw i8, ptr %2, i64 40
  %17 = load double, ptr %16, align 8, !tbaa !13
  %18 = getelementptr inbounds nuw i8, ptr %2, i64 48
  %19 = load double, ptr %18, align 8, !tbaa !13
  %20 = add i64 %3, -4
  br label %22

21:                                               ; preds = %22, %4
  ret void

22:                                               ; preds = %6, %22
  %23 = phi i64 [ 6, %6 ], [ %48, %22 ]
  %24 = phi i64 [ 3, %6 ], [ %37, %22 ]
  %25 = getelementptr [8 x i8], ptr %1, i64 %24
  %26 = getelementptr i8, ptr %25, i64 -24
  %27 = load double, ptr %26, align 8, !tbaa !13
  %28 = getelementptr i8, ptr %25, i64 -16
  %29 = load double, ptr %28, align 8, !tbaa !13
  %30 = fmul double %9, %29
  %31 = tail call double @llvm.fmuladd.f64(double %7, double %27, double %30)
  %32 = getelementptr i8, ptr %25, i64 -8
  %33 = load double, ptr %32, align 8, !tbaa !13
  %34 = tail call double @llvm.fmuladd.f64(double %11, double %33, double %31)
  %35 = load double, ptr %25, align 8, !tbaa !13
  %36 = tail call double @llvm.fmuladd.f64(double %13, double %35, double %34)
  %37 = add nuw i64 %24, 1
  %38 = getelementptr inbounds nuw [8 x i8], ptr %1, i64 %37
  %39 = load double, ptr %38, align 8, !tbaa !13
  %40 = tail call double @llvm.fmuladd.f64(double %15, double %39, double %36)
  %41 = getelementptr i8, ptr %25, i64 16
  %42 = load double, ptr %41, align 8, !tbaa !13
  %43 = tail call double @llvm.fmuladd.f64(double %17, double %42, double %40)
  %44 = getelementptr inbounds nuw [8 x i8], ptr %1, i64 %23
  %45 = load double, ptr %44, align 8, !tbaa !13
  %46 = tail call double @llvm.fmuladd.f64(double %19, double %45, double %43)
  %47 = getelementptr inbounds nuw [8 x i8], ptr %0, i64 %24
  store double %46, ptr %47, align 8, !tbaa !13
  %48 = add nuw i64 %24, 4
  %49 = icmp eq i64 %24, %20
  br i1 %49, label %21, label %22, !llvm.loop !19
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable vscale_range(4,1024)
define dso_local void @stencil7_coeff_array(ptr noalias nofree noundef writeonly captures(none) %0, ptr noalias nofree noundef readonly captures(none) %1, ptr noalias nofree noundef readonly captures(none) %2, ptr noalias nofree noundef readonly captures(none) %3, ptr noalias nofree noundef readonly captures(none) %4, ptr noalias nofree noundef readonly captures(none) %5, ptr noalias nofree noundef readonly captures(none) %6, ptr noalias nofree noundef readonly captures(none) %7, ptr noalias nofree noundef readonly captures(none) %8, i64 noundef %9) local_unnamed_addr #0 {
  %11 = icmp ugt i64 %9, 6
  br i1 %11, label %12, label %14

12:                                               ; preds = %10
  %13 = add i64 %9, -4
  br label %15

14:                                               ; preds = %15, %10
  ret void

15:                                               ; preds = %12, %15
  %16 = phi i64 [ %55, %15 ], [ 6, %12 ]
  %17 = phi i64 [ %40, %15 ], [ 3, %12 ]
  %18 = getelementptr inbounds nuw [8 x i8], ptr %2, i64 %17
  %19 = load double, ptr %18, align 8, !tbaa !13
  %20 = getelementptr [8 x i8], ptr %1, i64 %17
  %21 = getelementptr i8, ptr %20, i64 -24
  %22 = load double, ptr %21, align 8, !tbaa !13
  %23 = getelementptr inbounds nuw [8 x i8], ptr %3, i64 %17
  %24 = load double, ptr %23, align 8, !tbaa !13
  %25 = getelementptr i8, ptr %20, i64 -16
  %26 = load double, ptr %25, align 8, !tbaa !13
  %27 = fmul double %24, %26
  %28 = tail call double @llvm.fmuladd.f64(double %19, double %22, double %27)
  %29 = getelementptr inbounds nuw [8 x i8], ptr %4, i64 %17
  %30 = load double, ptr %29, align 8, !tbaa !13
  %31 = getelementptr i8, ptr %20, i64 -8
  %32 = load double, ptr %31, align 8, !tbaa !13
  %33 = tail call double @llvm.fmuladd.f64(double %30, double %32, double %28)
  %34 = getelementptr inbounds nuw [8 x i8], ptr %5, i64 %17
  %35 = load double, ptr %34, align 8, !tbaa !13
  %36 = load double, ptr %20, align 8, !tbaa !13
  %37 = tail call double @llvm.fmuladd.f64(double %35, double %36, double %33)
  %38 = getelementptr inbounds nuw [8 x i8], ptr %6, i64 %17
  %39 = load double, ptr %38, align 8, !tbaa !13
  %40 = add nuw i64 %17, 1
  %41 = getelementptr inbounds nuw [8 x i8], ptr %1, i64 %40
  %42 = load double, ptr %41, align 8, !tbaa !13
  %43 = tail call double @llvm.fmuladd.f64(double %39, double %42, double %37)
  %44 = getelementptr inbounds nuw [8 x i8], ptr %7, i64 %17
  %45 = load double, ptr %44, align 8, !tbaa !13
  %46 = getelementptr i8, ptr %20, i64 16
  %47 = load double, ptr %46, align 8, !tbaa !13
  %48 = tail call double @llvm.fmuladd.f64(double %45, double %47, double %43)
  %49 = getelementptr inbounds nuw [8 x i8], ptr %8, i64 %17
  %50 = load double, ptr %49, align 8, !tbaa !13
  %51 = getelementptr inbounds nuw [8 x i8], ptr %1, i64 %16
  %52 = load double, ptr %51, align 8, !tbaa !13
  %53 = tail call double @llvm.fmuladd.f64(double %50, double %52, double %48)
  %54 = getelementptr inbounds nuw [8 x i8], ptr %0, i64 %17
  store double %53, ptr %54, align 8, !tbaa !13
  %55 = add nuw i64 %17, 4
  %56 = icmp eq i64 %17, %13
  br i1 %56, label %14, label %15, !llvm.loop !20
}

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable vscale_range(4,1024) "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="spacemit-x100" "target-features"="+64bit,+a,+b,+c,+d,+f,+h,+i,+m,+relax,+sha,+shcounterenw,+shgatpa,+shtvala,+shvsatpa,+shvstvala,+shvstvecd,+smepmp,+smnpm,+smstateen,+ssccptr,+sscofpmf,+sscounterenw,+ssnpm,+sspm,+ssstateen,+sstc,+sstvala,+sstvecd,+ssu64xl,+supm,+svade,+svbare,+svinval,+svnapot,+svpbmt,+unaligned-scalar-mem,+v,+xsmtvdot,+za64rs,+zaamo,+zalrsc,+zawrs,+zba,+zbb,+zbc,+zbkc,+zbs,+zca,+zcb,+zcd,+zcmop,+zfa,+zfbfmin,+zfh,+zfhmin,+zic64b,+zicbom,+zicbop,+zicboz,+ziccamoa,+ziccif,+zicclsm,+ziccrse,+zicntr,+zicond,+zicsr,+zifencei,+zihintntl,+zihintpause,+zihpm,+zimop,+zkt,+zmmul,+zvbb,+zvbc,+zve32f,+zve32x,+zve64d,+zve64f,+zve64x,+zvfbfmin,+zvfbfwma,+zvfh,+zvfhmin,+zvkb,+zvkg,+zvkn,+zvknc,+zvkned,+zvkng,+zvknha,+zvknhb,+zvks,+zvksc,+zvksed,+zvksg,+zvksh,+zvkt,+zvl128b,+zvl256b,+zvl32b,+zvl64b,-e,-experimental-p,-experimental-smpmpmt,-experimental-svukte,-experimental-xqccmt,-experimental-xsfmclic,-experimental-xsfsclic,-experimental-y,-experimental-zibi,-experimental-zicfilp,-experimental-zicfiss,-experimental-zvabd,-experimental-zvbc32e,-experimental-zvdot4a8i,-experimental-zvfbdota32f,-experimental-zvfbfa,-experimental-zvfofp8min,-experimental-zvfqwbdota8f,-experimental-zvfqwdota8f,-experimental-zvfwbdota16bf,-experimental-zvfwdota16bf,-experimental-zvkgs,-experimental-zvqwbdota16i,-experimental-zvqwbdota8i,-experimental-zvqwdota16i,-experimental-zvqwdota8i,-experimental-zvvfmm,-experimental-zvvmm,-experimental-zvvmtls,-experimental-zvvmttls,-experimental-zvzip,-q,-sdext,-sdtrig,-shlcofideleg,-smaia,-smcdeleg,-smcntrpmf,-smcsrind,-smctr,-smdbltrp,-smmpm,-smrnmi,-ssaia,-ssccfg,-sscsrind,-ssctr,-ssdbltrp,-ssqosid,-ssstrict,-svadu,-svrsw60t59b,-svvptc,-xaifet,-xandesbfhcvt,-xandesperf,-xandesvbfhcvt,-xandesvdot,-xandesvpackfph,-xandesvsinth,-xandesvsintload,-xcheriot,-xcvalu,-xcvbi,-xcvbitmanip,-xcvelw,-xcvmac,-xcvmem,-xcvsimd,-xmipscbop,-xmipscmov,-xmipsexectl,-xmipslsp,-xqccmp,-xqci,-xqcia,-xqciac,-xqcibi,-xqcibm,-xqcicli,-xqcicm,-xqcics,-xqcicsr,-xqciint,-xqciio,-xqcilb,-xqcili,-xqcilia,-xqcilo,-xqcilsm,-xqcisim,-xqcisls,-xqcisync,-xsfcease,-xsfmm128t,-xsfmm16t,-xsfmm32a,-xsfmm32a16f,-xsfmm32a32f,-xsfmm32a8f,-xsfmm32a8i,-xsfmm32t,-xsfmm64a64f,-xsfmm64t,-xsfmmbase,-xsfvcp,-xsfvfbfexp16e,-xsfvfexp16e,-xsfvfexp32e,-xsfvfexpa,-xsfvfexpa64e,-xsfvfnrclipxfqf,-xsfvfwmaccqqq,-xsfvqmaccdod,-xsfvqmaccqoq,-xsifivecdiscarddlone,-xsifivecflushdlone,-xtheadba,-xtheadbb,-xtheadbs,-xtheadcmo,-xtheadcondmov,-xtheadfmemidx,-xtheadmac,-xtheadmemidx,-xtheadmempair,-xtheadsync,-xtheadvdot,-xventanacondops,-xwchc,-za128rs,-zabha,-zacas,-zalasr,-zama16b,-zbkb,-zbkx,-zce,-zcf,-zclsd,-zcmp,-zcmt,-zdinx,-zfinx,-zhinx,-zhinxmin,-ziccamoc,-ziccid,-zilsd,-zk,-zkn,-zknd,-zkne,-zknh,-zkr,-zks,-zksed,-zksh,-ztso,-zvl1024b,-zvl16384b,-zvl2048b,-zvl32768b,-zvl4096b,-zvl512b,-zvl65536b,-zvl8192b" }
attributes #1 = { mustprogress nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }

!llvm.module.flags = !{!0, !1, !3, !4, !5, !6}
!llvm.ident = !{!7}
!llvm.errno.tbaa = !{!8}

!0 = !{i32 1, !"target-abi", !"lp64d"}
!1 = !{i32 6, !"riscv-isa", !2}
!2 = !{!"rv64i2p1_m2p0_a2p1_f2p2_d2p2_c2p0_b1p0_v1p0_h1p0_zic64b1p0_zicbom1p0_zicbop1p0_zicboz1p0_ziccamoa1p0_ziccif1p0_zicclsm1p0_ziccrse1p0_zicntr2p0_zicond1p0_zicsr2p0_zifencei2p0_zihintntl1p0_zihintpause2p0_zihpm2p0_zimop1p0_zmmul1p0_za64rs1p0_zaamo1p0_zalrsc1p0_zawrs1p0_zfa1p0_zfbfmin1p0_zfh1p0_zfhmin1p0_zca1p0_zcb1p0_zcd1p0_zcmop1p0_zba1p0_zbb1p0_zbc1p0_zbkc1p0_zbs1p0_zkt1p0_zvbb1p0_zvbc1p0_zve32f1p0_zve32x1p0_zve64d1p0_zve64f1p0_zve64x1p0_zvfbfmin1p0_zvfbfwma1p0_zvfh1p0_zvfhmin1p0_zvkb1p0_zvkg1p0_zvkn1p0_zvknc1p0_zvkned1p0_zvkng1p0_zvknha1p0_zvknhb1p0_zvks1p0_zvksc1p0_zvksed1p0_zvksg1p0_zvksh1p0_zvkt1p0_zvl128b1p0_zvl256b1p0_zvl32b1p0_zvl64b1p0_sha1p0_shcounterenw1p0_shgatpa1p0_shtvala1p0_shvsatpa1p0_shvstvala1p0_shvstvecd1p0_smepmp1p0_smnpm1p0_smstateen1p0_ssccptr1p0_sscofpmf1p0_sscounterenw1p0_ssnpm1p0_sspm1p0_ssstateen1p0_sstc1p0_sstvala1p0_sstvecd1p0_ssu64xl1p0_supm1p0_svade1p0_svbare1p0_svinval1p0_svnapot1p0_svpbmt1p0_xsmtvdot1p0"}
!3 = !{i32 8, !"PIC Level", i32 2}
!4 = !{i32 7, !"PIE Level", i32 2}
!5 = !{i32 7, !"uwtable", i32 2}
!6 = !{i32 8, !"SmallDataLimit", i32 0}
!7 = !{!"clang version 23.0.0git (git@github.com:LysanderT/llvm-project.git 6984592c69e23899576cd8b7e6cc76a1c9af89f2)"}
!8 = !{!9, !10, i64 0}
!9 = !{!"__libc_errno", !10, i64 0}
!10 = !{!"int", !11, i64 0}
!11 = !{!"omnipotent char", !12, i64 0}
!12 = !{!"Simple C/C++ TBAA"}
!13 = !{!14, !14, i64 0}
!14 = !{!"double", !11, i64 0}
!15 = distinct !{!15, !16, !17}
!16 = !{!"llvm.loop.mustprogress"}
!17 = !{!"llvm.loop.unroll.disable"}
!18 = distinct !{!18, !16, !17}
!19 = distinct !{!19, !16, !17}
!20 = distinct !{!20, !16, !17}
