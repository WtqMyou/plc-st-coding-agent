FUNCTION_BLOCK FB
VAR_INPUT
    pushEn  : BOOL;
    pushItem: INT;
    popEn   : BOOL;
END_VAR
VAR_IN_OUT
    fifo    : ARRAY[1..8] OF INT;
END_VAR
VAR_OUTPUT
    count   : INT := 0;
    full    : BOOL := FALSE;
    empty   : BOOL := TRUE;
    head    : INT := 0;
END_VAR
VAR
    pushR   : R_TRIG;
    popR    : R_TRIG;
    prevPushEn  : BOOL := FALSE;
    prevPopEn   : BOOL := FALSE;
    firstScan   : BOOL := TRUE;
END_VAR
VAR
    tmp_prevCount : INT;
END_VAR

(*
ENGINEERING_CONTRACT
================================================================================
PUB001 §rising-edge trigger·pushEn  → pushR.Q = pulse
PUB002 §rising-edge trigger·popEn   → popR.Q  = pulse
PUB003 §pop-first: popR then pushR; pop on count>0 only; push on count<8 only
PUB004 §output: count/empty/full/head consistent with array state each scan
PUB005 §fifo[1..count] compact, fifo[1]=head when count>0; others unspecified
PUB006 §full ∧ pushR only: count=8 (no change); empty ∧ popR only: count=0
PUB007 §simultaneous: prev(full)→pop frees slot, then push succeeds; count stays
PUB008 §simultaneous: prev(empty)→pop no-op, push succeeds; count = 1
PUB009 §head=0 when empty; head=fifo[1] when count>0
PUB010 §no hidden timers; state in VAR; edge detection via R_TRIG
PUB011 §IN_OUT fifo bound by caller; write to positions 1..count only
PUB012 §rising edge detected on transition FALSE→TRUE; hold does not repeat
PUB013 §shift-left only when count>1; count=1 pop leaves array unchanged
PUB014 §push to unfull queue: fifo[count]=pushItem on same scan
PUB015 §all outputs derived from same-scan state; no multi-scan buffering
PUB016 §R_TRIG/Q is valid only during the scan where rising edge occurs
PUB017 §first scan: init fifo to defined state via firstScan guard
PUB018 §prev(pushEn) tracked via prevPushEn; prev(popEn) via prevPopEn
PUB019 §S1: count∈[0,8], full↔count=8, empty↔count=0
PUB020 §S2: prev(full)∧pushR∧!popR → count=8
PUB021 §S3: prev(empty)∧popR∧!pushR → count=0
PUB022 §S6: count updated after pop+push chain; only successful actions change it
PUB023 §S7: accepted push → fifo[count]=pushItem
PUB024 §S8: shift-left by one position when pop succeeds; count>1 shift else nop
================================================================================
*)
    (* Capture tmp_prevCount before any state mutation this scan *)
    tmp_prevCount := count;

    (* Detect rising edges per PUB001, PUB002, PUB012 *)
    pushR(CLK := pushEn);
    popR(CLK := popEn);

    (* PUB003 §pop-first order: handle pop before push *)
    IF popR.Q AND tmp_prevCount > 0 THEN
        (* S8 §shift-left only when count>1; count=1 pop leaves array unchanged (PUB013) *)
        IF tmp_prevCount > 1 THEN
            fifo[1] := fifo[2];
            fifo[2] := fifo[3];
            fifo[3] := fifo[4];
            fifo[4] := fifo[5];
            fifo[5] := fifo[6];
            fifo[6] := fifo[7];
            fifo[7] := fifo[8];
            fifo[8] := 0;
        END_IF;
        count := count - 1;
    END_IF;

    (* PUB003 §push on count<8; PUB007/PUB008 §simultaneous pop+push chain *)
    IF pushR.Q AND count < 8 THEN
        (* PUB014/PUB023 §accepted push: fifo[count]=pushItem (position BEFORE increment) *)
        fifo[count + 1] := pushItem;
        count := count + 1;
    END_IF;

    (* PUB004/PUB009 §derive output signals from final same-scan state *)
    full  := (count = 8);
    empty := (count = 0);
    IF count > 0 THEN
        head := fifo[1];
    ELSE
        head := 0;
    END_IF;

    (* Track previous input state for next-scan edge detection (PUB018) *)
    prevPushEn := pushEn;
    prevPopEn  := popEn;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)