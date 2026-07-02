//- RISCVSchedSpacemitX100.td - Spacemit X100 Scheduling Defs -*- tablegen -*-//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// Scheduler model for the SpacemiT-X100 processor.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Helpers

class SMX100GetLMULValue<list<int> Values, string LMUL> {
  defvar Index = !cond(
    !eq(LMUL, "MF8"): 0,
    !eq(LMUL, "MF4"): 1,
    !eq(LMUL, "MF2"): 2,
    !eq(LMUL, "M1"):  3,
    !eq(LMUL, "M2"):  4,
    !eq(LMUL, "M4"):  5,
    !eq(LMUL, "M8"):  6
  );

  assert !lt(Index, !size(Values)),
    "Missing LMUL value for '" # LMUL # "'.";

  int c = Values[Index];
}

class SMX100IsWorstCaseMX<string mx, list<string> MxList> {
  string LLMUL = LargestLMUL<MxList>.r;
  bit c = !eq(mx, LLMUL);
}

class SMX100IsWorstCaseMXSEW<string mx, int sew, list<string> MxList,
                              bit isF = 0> {
  string LLMUL = LargestLMUL<MxList>.r;
  int SSEW = SmallestSEW<mx, isF>.r;
  bit c = !and(!eq(mx, LLMUL), !eq(sew, SSEW));
}

// X100 has 256-bit VLEN.
defvar SMX100VLEN = 256;

class SMX100GetLMulCycles<string mx> {
  int c = !cond(
    !eq(mx, "M1") : 1,
    !eq(mx, "M2") : 2,
    !eq(mx, "M4") : 4,
    !eq(mx, "M8") : 8,
    !eq(mx, "MF2") : 1,
    !eq(mx, "MF4") : 1,
    !eq(mx, "MF8") : 1
  );
}

class SMX100GetVLMAX<string mx, int sew> {
  defvar LMUL = SMX100GetLMulCycles<mx>.c;
  int val = !cond(
    !eq(mx, "MF2") : !div(!div(SMX100VLEN, 2), sew),
    !eq(mx, "MF4") : !div(!div(SMX100VLEN, 4), sew),
    !eq(mx, "MF8") : !div(!div(SMX100VLEN, 8), sew),
    true: !div(!mul(SMX100VLEN, LMUL), sew)
  );
}

class SMX100SegmentedLdStCycles<string mx, int sew, int nf> {
  int c = !mul(SMX100GetVLMAX<mx, sew>.val, nf);
}

def SpacemitX100Model : SchedMachineModel {
  let IssueWidth = 4;          // 4 micro-ops are dispatched per cycle.
  let MicroOpBufferSize = 192; // Max micro-ops that can be buffered.
                               // 64 entry ROB. Max 3 micro-ops share one entry.
  let LoadLatency = 3;         // Cycles for loads to access the cache.
  let MispredictPenalty = 9;   // Extra cycles for a mispredicted branch.

  let CompleteModel = 0;

  let UnsupportedFeatures = [HasStdExtZknd, HasStdExtZkne, HasStdExtZknh,
                             HasStdExtZksed, HasStdExtZksh, HasStdExtZkr];
}

let SchedModel = SpacemitX100Model in {

//===----------------------------------------------------------------------===//
// Define processor resources for Spacemit-X100
let BufferSize = 6 in {
  // IQ0, IQ1, BQ: 12 entry queue, can accept 2 ops and issue 1 op per cycle
  // To model the accept bandwidth, split into 2 sub-queues of 6 entry each
  def SMTX100_IQ0 : ProcResource<2>; //Integer Queue 0
  def SMTX100_IQ1 : ProcResource<2>; //Integer Queue 1
  def SMTX100_BQ  : ProcResource<2>; //Branch Queue
}

let BufferSize = 4 in {
  // LSQ: 16 entry queue, can accept 4 ops and issue 2 op per cycle
  // To model the accept bandwidth, split into 4 sub-queues of 4 entry each
  def SMTX100_LSQ : ProcResource<4>; //Load Store Queue
  // FQ0, FQ1: 8 entry queue, can accept 2 ops and issue 1 op per cycle
  // To model the accept bandwidth, split into 2 sub-queues of 4 entry each
  def SMTX100_FQ0 : ProcResource<2>; //Float Queue 0
  def SMTX100_FQ1 : ProcResource<2>; //Float Queue 1
}

let BufferSize = 0 in {
  def SMTX100_VLS  : ProcResource<1>; //Vector Load Store Unit
  def SMTX100_VIEU : ProcResource<1>; //Vector Integer Unit
  def SMTX100_VFP  : ProcResource<1>; //Vector Floating-Point Unit
}

def SMTX100_IQ : ProcResGroup<[SMTX100_IQ0, SMTX100_IQ1]>;
def SMTX100_FQ : ProcResGroup<[SMTX100_FQ0, SMTX100_FQ1]>;

//===----------------------------------------------------------------------===//

// Branching
let Latency = 2 in {
  def : WriteRes<WriteJmp,  [SMTX100_BQ]>;
  def : WriteRes<WriteJal,  [SMTX100_BQ]>;
  def : WriteRes<WriteJalr, [SMTX100_BQ]>;
}

// Integer arithmetic and logic
def : WriteRes<WriteIALU32,     [SMTX100_IQ]>;
def : WriteRes<WriteIALU,       [SMTX100_IQ]>;
def : WriteRes<WriteShiftImm32, [SMTX100_IQ]>;
def : WriteRes<WriteShiftImm,   [SMTX100_IQ]>;
def : WriteRes<WriteShiftReg32, [SMTX100_IQ]>;
def : WriteRes<WriteShiftReg,   [SMTX100_IQ]>;

// Integer multiplication
def : WriteRes<WriteIMul32, [SMTX100_IQ1]> { let Latency = 2; }
def : WriteRes<WriteIMul,   [SMTX100_IQ1]> { let Latency = 3; }

// Integer division/remainder
// Latency is 4-14, Worst case latency is used
let Latency = 14, ReleaseAtCycles = [14] in {
  def : WriteRes<WriteIDiv32, [SMTX100_IQ0]>;
  def : WriteRes<WriteIRem32, [SMTX100_IQ0]>;
}
// Latency is 4-22, Worst case latency is used
let Latency = 22, ReleaseAtCycles = [22] in {
  def : WriteRes<WriteIDiv, [SMTX100_IQ0]>;
  def : WriteRes<WriteIRem, [SMTX100_IQ0]>;
}

// Bitmanip
def : WriteRes<WriteRotateImm,   [SMTX100_IQ]>;
def : WriteRes<WriteRotateImm32, [SMTX100_IQ]>;
def : WriteRes<WriteRotateReg,   [SMTX100_IQ]>;
def : WriteRes<WriteRotateReg32, [SMTX100_IQ]>;

def : WriteRes<WriteCLZ,   [SMTX100_IQ]>;
def : WriteRes<WriteCLZ32, [SMTX100_IQ]>;
def : WriteRes<WriteCTZ,   [SMTX100_IQ]>;
def : WriteRes<WriteCTZ32, [SMTX100_IQ]>;

let Latency = 2 in {
  def : WriteRes<WriteCPOP,   [SMTX100_IQ]>;
  def : WriteRes<WriteCPOP32, [SMTX100_IQ]>;
}

def : WriteRes<WriteORCB,    [SMTX100_IQ]>;
def : WriteRes<WriteIMinMax, [SMTX100_IQ]>;
def : WriteRes<WriteREV8,    [SMTX100_IQ]>;

def : WriteRes<WriteSHXADD,   [SMTX100_IQ]>;
def : WriteRes<WriteSHXADD32, [SMTX100_IQ]>;

def : WriteRes<WriteCLMUL,  [SMTX100_IQ]> { let Latency = 2; }

// Single-bit instructions
def : WriteRes<WriteSingleBit,    [SMTX100_IQ]>;
def : WriteRes<WriteSingleBitImm, [SMTX100_IQ]>;
def : WriteRes<WriteBEXT,  [SMTX100_IQ]>;
def : WriteRes<WriteBEXTI, [SMTX100_IQ]>;

// Memory/Atomic memory
def : WriteRes<WriteSTB, [SMTX100_LSQ]>;
def : WriteRes<WriteSTH, [SMTX100_LSQ]>;
def : WriteRes<WriteSTW, [SMTX100_LSQ]>;
def : WriteRes<WriteSTD, [SMTX100_LSQ]>;
def : WriteRes<WriteFST16, [SMTX100_LSQ]>;
def : WriteRes<WriteFST32, [SMTX100_LSQ]>;
def : WriteRes<WriteFST64, [SMTX100_LSQ]>;

let Latency = 3 in {
  def : WriteRes<WriteLDB, [SMTX100_LSQ]>;
  def : WriteRes<WriteLDH, [SMTX100_LSQ]>;
  def : WriteRes<WriteLDW, [SMTX100_LSQ]>;
  def : WriteRes<WriteLDD, [SMTX100_LSQ]>;
}

let Latency = 4 in {
  def : WriteRes<WriteFLD16, [SMTX100_LSQ]>;
  def : WriteRes<WriteFLD32, [SMTX100_LSQ]>;
  def : WriteRes<WriteFLD64, [SMTX100_LSQ]>;
}

// Atomics
// Latency is at least 7, not sure worst case latency now
let Latency = 7 in {
  def : WriteRes<WriteAtomicSTW, [SMTX100_LSQ]>;
  def : WriteRes<WriteAtomicSTD, [SMTX100_LSQ]>;
  def : WriteRes<WriteAtomicLDW, [SMTX100_LSQ]>;
  def : WriteRes<WriteAtomicLDD, [SMTX100_LSQ]>;
  def : WriteRes<WriteAtomicW, [SMTX100_LSQ]>;
  def : WriteRes<WriteAtomicD, [SMTX100_LSQ]>;
}

// Floating point units Half precision
let Latency = 3 in {
  def : WriteRes<WriteFAdd16, [SMTX100_FQ]>;
  def : WriteRes<WriteFMul16, [SMTX100_FQ]>;
  def : WriteRes<WriteFSGNJ16,   [SMTX100_FQ]>;
  def : WriteRes<WriteFMinMax16, [SMTX100_FQ]>;
}
def : WriteRes<WriteFMA16, [SMTX100_FQ]> { let Latency = 5; }


// Latency is 4-12, Worst case latency is used
let Latency = 12, ReleaseAtCycles = [12] in {
  def :  WriteRes<WriteFDiv16,  [SMTX100_FQ0]>;
  def :  WriteRes<WriteFSqrt16, [SMTX100_FQ0]>;
}

// Single precision
let Latency = 3 in {
  def : WriteRes<WriteFAdd32,    [SMTX100_FQ]>;
  def : WriteRes<WriteFSGNJ32,   [SMTX100_FQ]>;
  def : WriteRes<WriteFMinMax32, [SMTX100_FQ]>;
}
def : WriteRes<WriteFMul32, [SMTX100_FQ]> { let Latency = 4; }
def : WriteRes<WriteFMA32,  [SMTX100_FQ]> { let Latency = 5; }

// Latency is 4-12, Worst case latency is used
let Latency = 12, ReleaseAtCycles = [12] in {
  def :  WriteRes<WriteFDiv32,  [SMTX100_FQ0]>;
  def :  WriteRes<WriteFSqrt32, [SMTX100_FQ0]>;
}

// Double precision
let Latency = 3 in {
  def : WriteRes<WriteFAdd64,    [SMTX100_FQ]>;
  def : WriteRes<WriteFSGNJ64,   [SMTX100_FQ]>;
  def : WriteRes<WriteFMinMax64, [SMTX100_FQ]>;
}
def : WriteRes<WriteFMul64, [SMTX100_FQ]> { let Latency = 4; }
def : WriteRes<WriteFMA64,  [SMTX100_FQ]> { let Latency = 4; }

// Latency is 4-20, Worst case latency is used
let Latency = 20, ReleaseAtCycles = [20] in {
  def :  WriteRes<WriteFDiv64,  [SMTX100_FQ0]>;
  def :  WriteRes<WriteFSqrt64, [SMTX100_FQ0]>;
}

// Zfa
let Latency = 3 in {
  def : WriteRes<WriteFRoundF16, [SMTX100_FQ1]>;
  def : WriteRes<WriteFRoundF32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFRoundF64, [SMTX100_FQ1]>;

  def : WriteRes<WriteFLI16, [SMTX100_FQ1]>;
  def : WriteRes<WriteFLI32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFLI64, [SMTX100_FQ1]>;
}

// Conversions
let Latency = 3 in {
  def : WriteRes<WriteFCvtF16ToI32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF32ToI32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF32ToI64, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF64ToI64, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF64ToI32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF16ToI64, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtI32ToF16, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtI32ToF32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtI32ToF64, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtI64ToF16, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtI64ToF32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtI64ToF64, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF16ToF32, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF16ToF64, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF32ToF16, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF32ToF64, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF64ToF16, [SMTX100_FQ1]>;
  def : WriteRes<WriteFCvtF64ToF32, [SMTX100_FQ1]>;

  def : WriteRes<WriteFClass16, [SMTX100_FQ]>;
  def : WriteRes<WriteFClass32, [SMTX100_FQ]>;
  def : WriteRes<WriteFClass64, [SMTX100_FQ]>;

  def : WriteRes<WriteFCmp16, [SMTX100_FQ]>;
  def : WriteRes<WriteFCmp32, [SMTX100_FQ]>;
  def : WriteRes<WriteFCmp64, [SMTX100_FQ]>;

  def : WriteRes<WriteFMovF16ToI16, [SMTX100_FQ]>;
  def : WriteRes<WriteFMovI16ToF16, [SMTX100_FQ]>;
  def : WriteRes<WriteFMovF32ToI32, [SMTX100_FQ]>;
  def : WriteRes<WriteFMovI32ToF32, [SMTX100_FQ]>;
  def : WriteRes<WriteFMovF64ToI64, [SMTX100_FQ]>;
  def : WriteRes<WriteFMovI64ToF64, [SMTX100_FQ]>;
}

// Others
def : WriteRes<WriteCSR,   [SMTX100_IQ0]>;
def : WriteRes<WriteNop,   [SMTX100_IQ]>;

//===----------------------------------------------------------------------===//
// Vector instructions

def : WriteRes<WriteVSETVLI,  [SMTX100_IQ0]> { let Latency = 2; }
def : WriteRes<WriteVSETIVLI, [SMTX100_IQ0]> { let Latency = 2; }
def : WriteRes<WriteVSETVL,   [SMTX100_IQ0]> { let Latency = 2; }

// Unit-stride vector loads and stores.
foreach mx = SchedMxList in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxList>.c;

  defvar VLDELatAndOcc = SMX100GetLMULValue<[4, 4, 4, 4, 4, 4, 8], mx>.c;
  let Latency = VLDELatAndOcc, ReleaseAtCycles = [VLDELatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVLDE", [SMTX100_VLS], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVLDFF", [SMTX100_VLS], mx, IsWorstCase>;
  }

  defvar VSTELatAndOcc = SMX100GetLMULValue<[2, 2, 2, 2, 3, 4, 8], mx>.c;
  let Latency = VSTELatAndOcc, ReleaseAtCycles = [VSTELatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVSTE", [SMTX100_VLS], mx, IsWorstCase>;
  }

  let Latency = 2, ReleaseAtCycles = [2] in {
    defm "" : LMULWriteResMX<"WriteVLDM", [SMTX100_VLS], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSTM", [SMTX100_VLS], mx, IsWorstCase>;
  }

  foreach eew = [8, 16, 32, 64] in {
    defvar StridedLdStLatAndOcc = SMX100GetVLMAX<mx, eew>.val;
    let Latency = StridedLdStLatAndOcc,
        ReleaseAtCycles = [StridedLdStLatAndOcc] in {
      defm "" : LMULWriteResMX<"WriteVLDS" # eew, [SMTX100_VLS], mx,
                               IsWorstCase>;
      defm "" : LMULWriteResMX<"WriteVSTS" # eew, [SMTX100_VLS], mx,
                               IsWorstCase>;
    }

    defvar IndexedLdStLatAndOcc = !div(SMX100GetVLMAX<mx, eew>.val, 2);
    let Latency = IndexedLdStLatAndOcc,
        ReleaseAtCycles = [IndexedLdStLatAndOcc] in {
      defm "" : LMULWriteResMX<"WriteVLDUX" # eew, [SMTX100_VLS], mx,
                               IsWorstCase>;
      defm "" : LMULWriteResMX<"WriteVLDOX" # eew, [SMTX100_VLS], mx,
                               IsWorstCase>;
      defm "" : LMULWriteResMX<"WriteVSTUX" # eew, [SMTX100_VLS], mx,
                               IsWorstCase>;
      defm "" : LMULWriteResMX<"WriteVSTOX" # eew, [SMTX100_VLS], mx,
                               IsWorstCase>;
    }
  }
}

// Segmented vector loads and stores.
foreach mx = SchedMxList in {
  foreach nf = 2-8 in {
    foreach eew = [8, 16, 32, 64] in {
      defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxList>.c;
      defvar SegmentedLdStLatAndOcc =
        SMX100SegmentedLdStCycles<mx, eew, nf>.c;
      let Latency = SegmentedLdStLatAndOcc,
          ReleaseAtCycles = [SegmentedLdStLatAndOcc] in {
        defm "" : LMULWriteResMX<"WriteVLSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVLSEGFF" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVLSSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSSSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVLOXSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVLUXSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSUXSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
        defm "" : LMULWriteResMX<"WriteVSOXSEG" # nf # "e" # eew,
                                 [SMTX100_VLS], mx, IsWorstCase>;
      }
    }
  }
}

foreach LMul = [1, 2, 4, 8] in {
  defvar WholeRegLdStLatAndOcc = !if(!eq(LMul, 1), 4, !mul(LMul, 2));
  let Latency = WholeRegLdStLatAndOcc,
      ReleaseAtCycles = [WholeRegLdStLatAndOcc] in {
    def : WriteRes<!cast<SchedWrite>("WriteVLD" # LMul # "R"), [SMTX100_VLS]>;
    def : WriteRes<!cast<SchedWrite>("WriteVST" # LMul # "R"), [SMTX100_VLS]>;
  }

  defvar VMovLatAndOcc = !if(!eq(LMul, 1), 3, !mul(LMul, 2));
  let Latency = VMovLatAndOcc, ReleaseAtCycles = [VMovLatAndOcc] in
    def : WriteRes<!cast<SchedWrite>("WriteVMov" # LMul # "V"), [SMTX100_VIEU]>;
}

// Vector integer arithmetic.
foreach mx = SchedMxList in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxList>.c;

  defvar VIALULatAndOcc = SMX100GetLMULValue<[3, 3, 3, 3, 3, 4, 8], mx>.c;
  let Latency = VIALULatAndOcc, ReleaseAtCycles = [VIALULatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVIALUV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIALUX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIALUI", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMinMaxV", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMinMaxX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
  }

  let Latency = VIALULatAndOcc in
    def SMX100WriteVCOPY_ # mx : SchedWriteRes<[]>;

  defvar VILogicalLatAndOcc = SMX100GetLMULValue<[3, 3, 3, 3, 3, 4, 8], mx>.c;
  let Latency = VILogicalLatAndOcc,
      ReleaseAtCycles = [VILogicalLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVExtV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMergeV", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMergeX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMergeI", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMovV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMovX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMovI", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVShiftV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVShiftX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVShiftI", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUI", [SMTX100_VIEU], mx, IsWorstCase>;
  }

  defvar VICmpLatAndOcc = SMX100GetLMULValue<[4, 4, 4, 4, 6, 10, 18], mx>.c;
  let Latency = VICmpLatAndOcc, ReleaseAtCycles = [VICmpLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVICALUMV", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUMX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICALUMI", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICmpV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICmpX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVICmpI", [SMTX100_VIEU], mx, IsWorstCase>;
  }

  defvar VIMulLatAndOcc = SMX100GetLMULValue<[4, 4, 4, 4, 5, 5, 8], mx>.c;
  let Latency = VIMulLatAndOcc, ReleaseAtCycles = [VIMulLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVIMulV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMulX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMulAddV", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIMulAddX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
  }
}

foreach mx = SchedMxListW in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxListW>.c;
  defvar VIWideningLatAndOcc = SMX100GetLMULValue<[4, 4, 4, 5, 8, 8], mx>.c;
  let Latency = VIWideningLatAndOcc,
      ReleaseAtCycles = [VIWideningLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVIWALUV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWALUX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWALUI", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulAddV", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIWMulAddX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
  }
}

foreach mx = SchedMxList in {
  foreach sew = SchedSEWSet<mx>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxList>.c;
    defvar VIDivLatAndOcc = !mul(SMX100GetLMulCycles<mx>.c, 20);
    let Latency = VIDivLatAndOcc, ReleaseAtCycles = [VIDivLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVIDivV", [SMTX100_VIEU], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVIDivX", [SMTX100_VIEU], mx, sew,
                                     IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListW in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxListW>.c;
  defvar VNarrowingLatAndOcc = SMX100GetLMULValue<[4, 4, 4, 4, 5, 8], mx>.c;
  let Latency = VNarrowingLatAndOcc,
      ReleaseAtCycles = [VNarrowingLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVNShiftV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNShiftX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNShiftI", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNClipV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNClipX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVNClipI", [SMTX100_VIEU], mx, IsWorstCase>;
  }
}

foreach mx = SchedMxList in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxList>.c;
  defvar VSALULatAndOcc = SMX100GetLMULValue<[3, 3, 3, 3, 3, 4, 8], mx>.c;
  let Latency = VSALULatAndOcc, ReleaseAtCycles = [VSALULatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVSALUV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSALUX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSALUI", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVAALUV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVAALUX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSMulV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSMulX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSShiftV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSShiftX", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSShiftI", [SMTX100_VIEU], mx, IsWorstCase>;
  }
}

// Vector floating-point arithmetic.
foreach mx = SchedMxListF in {
  foreach sew = SchedSEWSet<mx, isF=1>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxListF,
                                                isF=1>.c;
    defvar VFALULatAndOcc = SMX100GetLMULValue<[3, 3, 3, 3, 4, 4, 8], mx>.c;
    let Latency = VFALULatAndOcc, ReleaseAtCycles = [VFALULatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFALUV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFALUF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMinMaxV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMinMaxF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
    }

    defvar VFMulLatAndOcc = SMX100GetLMULValue<[4, 4, 4, 4, 4, 5, 8], mx>.c;
    let Latency = VFMulLatAndOcc, ReleaseAtCycles = [VFMulLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulAddV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFMulAddF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
    }

    let Latency = VFALULatAndOcc, ReleaseAtCycles = [VFALULatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRecpV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFSgnjV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFSgnjF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFCvtIToFV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
    }

    defvar VFDivLatAndOcc = !mul(SMX100GetLMulCycles<mx>.c, 12);
    let Latency = VFDivLatAndOcc, ReleaseAtCycles = [VFDivLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFDivF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFDivV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
    }

    defvar VFSqrtLatAndOcc = !mul(SMX100GetLMulCycles<mx>.c, 36);
    let Latency = VFSqrtLatAndOcc, ReleaseAtCycles = [VFSqrtLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFSqrtV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
    }
  }
}

foreach mx = SchedMxList in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxList>.c;

  defvar VFClassLatAndOcc = SMX100GetLMULValue<[3, 3, 3, 3, 4, 4, 8], mx>.c;
  let Latency = VFClassLatAndOcc, ReleaseAtCycles = [VFClassLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVFCmpV", [SMTX100_VFP], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFCmpF", [SMTX100_VFP], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFClassV", [SMTX100_VFP], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFMergeV", [SMTX100_VFP], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFMovV", [SMTX100_VFP], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFCvtFToIV", [SMTX100_VFP], mx,
                             IsWorstCase>;
  }
}

foreach mx = SchedMxListW in {
  foreach sew = SchedSEWSet<mx, isF=0, isWidening=1>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxListW>.c;
    defvar VFWCvtILatAndOcc =
        SMX100GetLMULValue<[4, 4, 4, 4, 5, 8], mx>.c;
    let Latency = VFWCvtILatAndOcc,
        ReleaseAtCycles = [VFWCvtILatAndOcc] in
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWCvtIToFV", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
  }
}

foreach mx = SchedMxListW in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxListW>.c;
  defvar VFWCvtLatAndOcc = SMX100GetLMULValue<[4, 4, 4, 4, 5, 8], mx>.c;
  let Latency = VFWCvtLatAndOcc, ReleaseAtCycles = [VFWCvtLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVFNCvtFToIV", [SMTX100_VFP], mx,
                             IsWorstCase>;
  }
}

foreach mx = SchedMxListFW in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxListFW>.c;
  defvar VFWLatAndOcc = SMX100GetLMULValue<[0, 4, 4, 4, 5, 8, 0], mx>.c;
  let Latency = VFWLatAndOcc, ReleaseAtCycles = [VFWLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVFWCvtFToIV", [SMTX100_VFP], mx,
                             IsWorstCase>;
  }
}

foreach mx = SchedMxListFW in {
  foreach sew = SchedSEWSet<mx, isF=1, isWidening=1>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxListFW,
                                                isF=1>.c;
    defvar VFWALULatAndOcc = SMX100GetLMULValue<[0, 4, 4, 4, 5, 8, 0], mx>.c;
    let Latency = VFWALULatAndOcc, ReleaseAtCycles = [VFWALULatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWCvtFToFV", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFNCvtIToFV", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFNCvtFToFV", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWALUV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWALUF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulF", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulV", [SMTX100_VFP], mx, sew,
                                     IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulAddV", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWMulAddF", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
    }
  }
}

// Reductions.
foreach mx = SchedMxList in {
  foreach sew = SchedSEWSet<mx>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxList>.c;
    defvar VIRedLatAndOcc = SMX100GetLMULValue<[5, 5, 5, 5, 8, 12, 24], mx>.c;
    let Latency = VIRedLatAndOcc, ReleaseAtCycles = [VIRedLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVIRedMinMaxV_From",
                                     [SMTX100_VIEU], mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVIRedV_From", [SMTX100_VIEU], mx,
                                     sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListWRed in {
  foreach sew = SchedSEWSet<mx, 0, 1>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxListWRed>.c;
    defvar VIWRedLatAndOcc =
        SMX100GetLMULValue<[5, 5, 5, 5, 8, 12, 24], mx>.c;
    let Latency = VIWRedLatAndOcc, ReleaseAtCycles = [VIWRedLatAndOcc] in
      defm "" : LMULSEWWriteResMXSEW<"WriteVIWRedV_From", [SMTX100_VIEU], mx,
                                     sew, IsWorstCase>;
  }
}

foreach mx = SchedMxListF in {
  foreach sew = SchedSEWSet<mx, 1>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxListF, 1>.c;
    defvar VFRedLatAndOcc = SMX100GetLMULValue<[6, 6, 6, 6, 10, 18, 36], mx>.c;
    let Latency = VFRedLatAndOcc, ReleaseAtCycles = [VFRedLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRedV_From", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRedMinMaxV_From", [SMTX100_VFP],
                                     mx, sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFRedOV_From", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
    }
  }
}

foreach mx = SchedMxListFWRed in {
  foreach sew = SchedSEWSet<mx, 1, 1>.val in {
    defvar IsWorstCase = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxListFWRed,
                                                1>.c;
    defvar VFWRedLatAndOcc =
        SMX100GetLMULValue<[0, 6, 6, 6, 10, 18, 36], mx>.c;
    let Latency = VFWRedLatAndOcc, ReleaseAtCycles = [VFWRedLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWRedV_From", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVFWRedOV_From", [SMTX100_VFP], mx,
                                     sew, IsWorstCase>;
    }
  }
}

// Mask and permutation instructions.
foreach mx = SchedMxList in {
  defvar IsWorstCase = SMX100IsWorstCaseMX<mx, SchedMxList>.c;
  defvar VMaskLatAndOcc = SMX100GetLMULValue<[3, 3, 3, 3, 4, 8, 16], mx>.c;
  let Latency = VMaskLatAndOcc, ReleaseAtCycles = [VMaskLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVMALUV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVMSFSV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVMPopV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVMFFSV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIotaV", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVIdxV", [SMTX100_VIEU], mx, IsWorstCase>;
  }

  defvar VPermLatAndOcc = SMX100GetLMULValue<[3, 3, 3, 3, 5, 9, 17], mx>.c;
  let Latency = VPermLatAndOcc, ReleaseAtCycles = [VPermLatAndOcc] in {
    defm "" : LMULWriteResMX<"WriteVSlideUpX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSlideDownX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVSlideI", [SMTX100_VIEU], mx, IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVISlide1X", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVFSlide1F", [SMTX100_VFP], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVRGatherVX", [SMTX100_VIEU], mx,
                             IsWorstCase>;
    defm "" : LMULWriteResMX<"WriteVRGatherVI", [SMTX100_VIEU], mx,
                             IsWorstCase>;
  }

  foreach sew = SchedSEWSet<mx>.val in {
    defvar IsWorstCaseSEW = SMX100IsWorstCaseMXSEW<mx, sew, SchedMxList>.c;
    let Latency = VPermLatAndOcc, ReleaseAtCycles = [VPermLatAndOcc] in {
      defm "" : LMULSEWWriteResMXSEW<"WriteVRGatherVV", [SMTX100_VIEU], mx,
                                     sew, IsWorstCaseSEW>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVRGatherEI16VV", [SMTX100_VIEU],
                                     mx, sew, IsWorstCaseSEW>;
      defm "" : LMULSEWWriteResMXSEW<"WriteVCompressV", [SMTX100_VIEU], mx,
                                     sew, IsWorstCaseSEW>;
    }
  }
}

let Latency = 3 in {
  def : WriteRes<WriteVMovXS, [SMTX100_VIEU]>;
  def : WriteRes<WriteVMovSX, [SMTX100_VIEU]>;
  def : WriteRes<WriteVMovFS, [SMTX100_VFP]>;
  def : WriteRes<WriteVMovSF, [SMTX100_VFP]>;
}

def : WriteRes<WriteRdVLENB, [SMTX100_IQ0]>;

//===----------------------------------------------------------------------===//
// Bypass and advance
def : ReadAdvance<ReadJmp, 0>;
def : ReadAdvance<ReadJalr, 0>;
def : ReadAdvance<ReadCSR, 0>;
def : ReadAdvance<ReadStoreData, 0>;
def : ReadAdvance<ReadMemBase, 0>;
def : ReadAdvance<ReadIALU, 0>;
def : ReadAdvance<ReadIALU32, 0>;
def : ReadAdvance<ReadShiftImm, 0>;
def : ReadAdvance<ReadShiftImm32, 0>;
def : ReadAdvance<ReadShiftReg, 0>;
def : ReadAdvance<ReadShiftReg32, 0>;
def : ReadAdvance<ReadIDiv, 0>;
def : ReadAdvance<ReadIDiv32, 0>;
def : ReadAdvance<ReadIRem, 0>;
def : ReadAdvance<ReadIRem32, 0>;
def : ReadAdvance<ReadIMul, 0>;
def : ReadAdvance<ReadIMul32, 0>;
def : ReadAdvance<ReadAtomicWA, 0>;
def : ReadAdvance<ReadAtomicWD, 0>;
def : ReadAdvance<ReadAtomicDA, 0>;
def : ReadAdvance<ReadAtomicDD, 0>;
def : ReadAdvance<ReadAtomicLDW, 0>;
def : ReadAdvance<ReadAtomicLDD, 0>;
def : ReadAdvance<ReadAtomicSTW, 0>;
def : ReadAdvance<ReadAtomicSTD, 0>;
def : ReadAdvance<ReadFStoreData, 0>;
def : ReadAdvance<ReadFMemBase, 0>;
def : ReadAdvance<ReadFAdd16, 0>;
def : ReadAdvance<ReadFAdd32, 0>;
def : ReadAdvance<ReadFAdd64, 0>;
def : ReadAdvance<ReadFMul16, 0>;
def : ReadAdvance<ReadFMA16, 0>;
def : ReadAdvance<ReadFMA16Addend, 0>;
def : ReadAdvance<ReadFMul32, 0>;
def : ReadAdvance<ReadFMul64, 0>;
def : ReadAdvance<ReadFMA32, 0>;
def : ReadAdvance<ReadFMA32Addend, 0>;
def : ReadAdvance<ReadFMA64, 0>;
def : ReadAdvance<ReadFMA64Addend, 0>;
def : ReadAdvance<ReadFDiv16, 0>;
def : ReadAdvance<ReadFDiv32, 0>;
def : ReadAdvance<ReadFDiv64, 0>;
def : ReadAdvance<ReadFSqrt16, 0>;
def : ReadAdvance<ReadFSqrt32, 0>;
def : ReadAdvance<ReadFSqrt64, 0>;
def : ReadAdvance<ReadFCmp16, 0>;
def : ReadAdvance<ReadFCmp32, 0>;
def : ReadAdvance<ReadFCmp64, 0>;
def : ReadAdvance<ReadFSGNJ16, 0>;
def : ReadAdvance<ReadFSGNJ32, 0>;
def : ReadAdvance<ReadFSGNJ64, 0>;
def : ReadAdvance<ReadFMinMax16, 0>;
def : ReadAdvance<ReadFMinMax32, 0>;
def : ReadAdvance<ReadFMinMax64, 0>;
def : ReadAdvance<ReadFCvtF16ToI32, 0>;
def : ReadAdvance<ReadFCvtF16ToI64, 0>;
def : ReadAdvance<ReadFCvtF32ToI32, 0>;
def : ReadAdvance<ReadFCvtF32ToI64, 0>;
def : ReadAdvance<ReadFCvtF64ToI32, 0>;
def : ReadAdvance<ReadFCvtF64ToI64, 0>;
def : ReadAdvance<ReadFCvtI32ToF16, 0>;
def : ReadAdvance<ReadFCvtI32ToF32, 0>;
def : ReadAdvance<ReadFCvtI32ToF64, 0>;
def : ReadAdvance<ReadFCvtI64ToF16, 0>;
def : ReadAdvance<ReadFCvtI64ToF32, 0>;
def : ReadAdvance<ReadFCvtI64ToF64, 0>;
def : ReadAdvance<ReadFCvtF32ToF64, 0>;
def : ReadAdvance<ReadFCvtF64ToF32, 0>;
def : ReadAdvance<ReadFCvtF16ToF32, 0>;
def : ReadAdvance<ReadFCvtF32ToF16, 0>;
def : ReadAdvance<ReadFCvtF16ToF64, 0>;
def : ReadAdvance<ReadFCvtF64ToF16, 0>;
def : ReadAdvance<ReadFMovF16ToI16, 0>;
def : ReadAdvance<ReadFMovI16ToF16, 0>;
def : ReadAdvance<ReadFMovF32ToI32, 0>;
def : ReadAdvance<ReadFMovI32ToF32, 0>;
def : ReadAdvance<ReadFMovF64ToI64, 0>;
def : ReadAdvance<ReadFMovI64ToF64, 0>;
def : ReadAdvance<ReadFClass16, 0>;
def : ReadAdvance<ReadFClass32, 0>;
def : ReadAdvance<ReadFClass64, 0>;

// Bitmanip
def : ReadAdvance<ReadRotateImm, 0>;
def : ReadAdvance<ReadRotateImm32, 0>;
def : ReadAdvance<ReadRotateReg, 0>;
def : ReadAdvance<ReadRotateReg32, 0>;
def : ReadAdvance<ReadCLZ, 0>;
def : ReadAdvance<ReadCLZ32, 0>;
def : ReadAdvance<ReadCTZ, 0>;
def : ReadAdvance<ReadCTZ32, 0>;
def : ReadAdvance<ReadCPOP, 0>;
def : ReadAdvance<ReadCPOP32, 0>;
def : ReadAdvance<ReadORCB, 0>;
def : ReadAdvance<ReadIMinMax, 0>;
def : ReadAdvance<ReadREV8, 0>;
def : ReadAdvance<ReadSHXADD, 0>;
def : ReadAdvance<ReadSHXADD32, 0>;
def : ReadAdvance<ReadCLMUL, 0>;
// Single-bit instructions
def : ReadAdvance<ReadSingleBit, 0>;
def : ReadAdvance<ReadSingleBitImm, 0>;
// Zfa
def : ReadAdvance<ReadFRoundF32, 0>;
def : ReadAdvance<ReadFRoundF64, 0>;
def : ReadAdvance<ReadFRoundF16, 0>;

// 6. Configuration-Setting Instructions
def : ReadAdvance<ReadVSETVLI, 0>;
def : ReadAdvance<ReadVSETVL, 0>;

// 7. Vector Loads and Stores
def : ReadAdvance<ReadVLDX, 0>;
def : ReadAdvance<ReadVSTX, 0>;
defm "" : LMULReadAdvance<"ReadVSTEV", 0>;
defm "" : LMULReadAdvance<"ReadVSTM", 0>;
def : ReadAdvance<ReadVLDSX, 0>;
def : ReadAdvance<ReadVSTSX, 0>;
defm "" : LMULReadAdvance<"ReadVSTS8V", 0>;
defm "" : LMULReadAdvance<"ReadVSTS16V", 0>;
defm "" : LMULReadAdvance<"ReadVSTS32V", 0>;
defm "" : LMULReadAdvance<"ReadVSTS64V", 0>;
defm "" : LMULReadAdvance<"ReadVLDUXV", 0>;
defm "" : LMULReadAdvance<"ReadVLDOXV", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX8", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX16", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX32", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX64", 0>;
defm "" : LMULReadAdvance<"ReadVSTUXV", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX8V", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX16V", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX32V", 0>;
defm "" : LMULReadAdvance<"ReadVSTUX64V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX8", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX16", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX32", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX64", 0>;
defm "" : LMULReadAdvance<"ReadVSTOXV", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX8V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX16V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX32V", 0>;
defm "" : LMULReadAdvance<"ReadVSTOX64V", 0>;
def : ReadAdvance<ReadVST1R, 0>;
def : ReadAdvance<ReadVST2R, 0>;
def : ReadAdvance<ReadVST4R, 0>;
def : ReadAdvance<ReadVST8R, 0>;

// 11. Vector Integer Arithmetic Instructions
defm : LMULReadAdvance<"ReadVIALUV", 0>;
defm : LMULReadAdvance<"ReadVIALUX", 0>;
defm : LMULReadAdvanceW<"ReadVIWALUV", 0>;
defm : LMULReadAdvanceW<"ReadVIWALUX", 0>;
defm : LMULReadAdvance<"ReadVExtV", 0>;
defm : LMULReadAdvance<"ReadVICALUV", 0>;
defm : LMULReadAdvance<"ReadVICALUX", 0>;
defm : LMULReadAdvance<"ReadVShiftV", 0>;
defm : LMULReadAdvance<"ReadVShiftX", 0>;
defm : LMULReadAdvanceW<"ReadVNShiftV", 0>;
defm : LMULReadAdvanceW<"ReadVNShiftX", 0>;
defm : LMULReadAdvance<"ReadVICmpV", 0>;
defm : LMULReadAdvance<"ReadVICmpX", 0>;
defm : LMULReadAdvance<"ReadVIMinMaxV", 0>;
defm : LMULReadAdvance<"ReadVIMinMaxX", 0>;
defm : LMULReadAdvance<"ReadVIMulV", 0>;
defm : LMULReadAdvance<"ReadVIMulX", 0>;
defm : LMULSEWReadAdvance<"ReadVIDivV", 0>;
defm : LMULSEWReadAdvance<"ReadVIDivX", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulV", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulX", 0>;
defm : LMULReadAdvance<"ReadVIMulAddV", 0>;
defm : LMULReadAdvance<"ReadVIMulAddX", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulAddV", 0>;
defm : LMULReadAdvanceW<"ReadVIWMulAddX", 0>;
defm : LMULReadAdvance<"ReadVIMergeV", 0>;
defm : LMULReadAdvance<"ReadVIMergeX", 0>;
defm : LMULReadAdvance<"ReadVIMovV", 0>;
defm : LMULReadAdvance<"ReadVIMovX", 0>;

// 12. Vector Fixed-Point Arithmetic Instructions
defm "" : LMULReadAdvance<"ReadVSALUV", 0>;
defm "" : LMULReadAdvance<"ReadVSALUX", 0>;
defm "" : LMULReadAdvance<"ReadVAALUV", 0>;
defm "" : LMULReadAdvance<"ReadVAALUX", 0>;
defm "" : LMULReadAdvance<"ReadVSMulV", 0>;
defm "" : LMULReadAdvance<"ReadVSMulX", 0>;
defm "" : LMULReadAdvance<"ReadVSShiftV", 0>;
defm "" : LMULReadAdvance<"ReadVSShiftX", 0>;
defm "" : LMULReadAdvanceW<"ReadVNClipV", 0>;
defm "" : LMULReadAdvanceW<"ReadVNClipX", 0>;

// 13. Vector Floating-Point Instructions
defm "" : LMULSEWReadAdvanceF<"ReadVFALUV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFALUF", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWALUV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWALUF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFDivV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFDivF", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulAddV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMulAddF", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulAddV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWMulAddF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFSqrtV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFRecpV", 0>;
defm "" : LMULReadAdvance<"ReadVFCmpV", 0>;
defm "" : LMULReadAdvance<"ReadVFCmpF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMinMaxV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFMinMaxF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFSgnjV", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFSgnjF", 0>;
defm "" : LMULReadAdvance<"ReadVFClassV", 0>;
defm "" : LMULReadAdvance<"ReadVFMergeV", 0>;
defm "" : LMULReadAdvance<"ReadVFMergeF", 0>;
defm "" : LMULReadAdvance<"ReadVFMovF", 0>;
defm "" : LMULSEWReadAdvanceF<"ReadVFCvtIToFV", 0>;
defm "" : LMULReadAdvance<"ReadVFCvtFToIV", 0>;
defm "" : LMULSEWReadAdvanceW<"ReadVFWCvtIToFV", 0>;
defm "" : LMULReadAdvanceFW<"ReadVFWCvtFToIV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFWCvtFToFV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFNCvtIToFV", 0>;
defm "" : LMULReadAdvanceW<"ReadVFNCvtFToIV", 0>;
defm "" : LMULSEWReadAdvanceFW<"ReadVFNCvtFToFV", 0>;

// 14. Vector Reduction Operations
def : ReadAdvance<ReadVIRedV, 0>;
def : ReadAdvance<ReadVIRedV0, 0>;
def : ReadAdvance<ReadVIWRedV, 0>;
def : ReadAdvance<ReadVIWRedV0, 0>;
def : ReadAdvance<ReadVFRedV, 0>;
def : ReadAdvance<ReadVFRedV0, 0>;
def : ReadAdvance<ReadVFRedOV, 0>;
def : ReadAdvance<ReadVFRedOV0, 0>;
def : ReadAdvance<ReadVFWRedV, 0>;
def : ReadAdvance<ReadVFWRedV0, 0>;
def : ReadAdvance<ReadVFWRedOV, 0>;
def : ReadAdvance<ReadVFWRedOV0, 0>;

// 15. Vector Mask Instructions
defm "" : LMULReadAdvance<"ReadVMALUV", 0>;
defm "" : LMULReadAdvance<"ReadVMPopV", 0>;
defm "" : LMULReadAdvance<"ReadVMFFSV", 0>;
defm "" : LMULReadAdvance<"ReadVMSFSV", 0>;
defm "" : LMULReadAdvance<"ReadVIotaV", 0>;

// 16. Vector Permutation Instructions
def : ReadAdvance<ReadVMovXS, 0>;
def : ReadAdvance<ReadVMovSX_V, 0>;
def : ReadAdvance<ReadVMovSX_X, 0>;
def : ReadAdvance<ReadVMovFS, 0>;
def : ReadAdvance<ReadVMovSF_V, 0>;
def : ReadAdvance<ReadVMovSF_F, 0>;
defm "" : LMULReadAdvance<"ReadVISlideV", 0>;
defm "" : LMULReadAdvance<"ReadVISlideX", 0>;
defm "" : LMULReadAdvance<"ReadVFSlideV", 0>;
defm "" : LMULReadAdvance<"ReadVFSlideF", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherVV_data", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherVV_index", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherEI16VV_data", 0>;
defm "" : LMULSEWReadAdvance<"ReadVRGatherEI16VV_index", 0>;
defm "" : LMULReadAdvance<"ReadVRGatherVX_data", 0>;
defm "" : LMULReadAdvance<"ReadVRGatherVX_index", 0>;
defm "" : LMULReadAdvance<"ReadVRGatherVI_data", 0>;
defm "" : LMULSEWReadAdvance<"ReadVCompressV", 0>;
def : ReadAdvance<ReadVMov1V, 0>;
def : ReadAdvance<ReadVMov2V, 0>;
def : ReadAdvance<ReadVMov4V, 0>;
def : ReadAdvance<ReadVMov8V, 0>;

// Others
def : ReadAdvance<ReadVMask, 0>;
def : ReadAdvance<ReadVPassthru_WorstCase, 0>;
foreach mx = SchedMxList in {
  def : ReadAdvance<!cast<SchedRead>("ReadVPassthru_" # mx), 0>;
  foreach sew = SchedSEWSet<mx>.val in
    def : ReadAdvance<!cast<SchedRead>("ReadVPassthru_" # mx # "_E" # sew),
                      0>;
}

//===----------------------------------------------------------------------===//
// Unsupported extensions
defm : UnsupportedSchedQ;
defm : UnsupportedSchedZabha;
defm : UnsupportedSchedZbkb;
defm : UnsupportedSchedZbkx;
defm : UnsupportedSchedZfaWithQ;
defm : UnsupportedSchedZvk;
defm : UnsupportedSchedSFB;
defm : UnsupportedSchedXsf;
}
