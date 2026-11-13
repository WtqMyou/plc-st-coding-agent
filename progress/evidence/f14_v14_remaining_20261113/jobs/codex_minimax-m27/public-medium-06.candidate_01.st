FUNCTION_BLOCK SlabThicknessMonitor
VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN            : BOOL;
    FaultTimestamp         : DINT;
    CycleTime              : TIME;
END_VAR

VAR_OUTPUT
    THICKNESS_ALARM           : BOOL := FALSE;
    Slab_Fault_Counter        : UINT := 0;
    Slab_Runtime_Accumulator  : LTIME := LTIME#0s;
    Slab_Fault_History        : ARRAY[0..4] OF DINT := [5(0)];
END_VAR

VAR
    tmp_AlarmHoldTimer : TON;
    tmp_FaultRTrig     : R_TRIG;
END_VAR

(*
ENGINEERING_CONTRACT
================================================================================
| Output / State        | Activation              | Retention/Reset            |
|-----------------------|-------------------------|----------------------------|
| THICKNESS_ALARM       | Rising edge valid fault | Reset: signal invalid/Power|
| Hold Timer (500ms)    | Rising edge valid fault | Reset: elapsed or invalid  |
| Slab_Fault_Counter    | Rising edge valid fault | Retention: no reset        |
| Slab_Fault_History[0] | Rising edge valid fault | Shift register, newest=0   |
| Slab_Runtime_Accum.   | CUTTING_RUN+valid+no    | Retention: preserve unless |
|                       | fault per scan          | condition met              |
--------------------------------------------------------------------------------
Priority: Same-scan; alarm combinational with hold timer; no edge-only reset.
Units: LTIME nanoseconds; CycleTime T#1ms..T#1h; hold = T#500ms >= 500ms.
Boundaries: History array fixed 0..4; counter saturates at UINT MAX.
Pub Refs: PUB001, PUB002, PUB003, PUB004, PUB005, PUB006
================================================================================
*)

(* CONTRACT_RULES [] *)

tmp_FaultRTrig(CLK := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID);

IF tmp_FaultRTrig.Q THEN
    tmp_AlarmHoldTimer(IN := TRUE, PT := T#500ms);
END_IF;

IF tmp_AlarmHoldTimer.Q THEN
    tmp_AlarmHoldTimer(IN := FALSE);
END_IF;

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    tmp_AlarmHoldTimer(IN := FALSE);
ELSIF THICKNESS_FAULT THEN
    THICKNESS_ALARM := TRUE;
    tmp_AlarmHoldTimer(IN := TRUE, PT := T#500ms);
ELSIF tmp_AlarmHoldTimer.Q THEN
    THICKNESS_ALARM := TRUE;
ELSE
    THICKNESS_ALARM := FALSE;
END_IF;

IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
END_IF;

IF tmp_FaultRTrig.Q THEN
    Slab_Fault_History[4] := Slab_Fault_History[3];
    Slab_Fault_History[3] := Slab_Fault_History[2];
    Slab_Fault_History[2] := Slab_Fault_History[1];
    Slab_Fault_History[1] := Slab_Fault_History[0];
    Slab_Fault_History[0] := FaultTimestamp;
    Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;
END_IF;

END_FUNCTION_BLOCK