(* ENGINEERING_CONTRACT
   THICKNESS_ALARM: latch on valid-fault FALSE->TRUE edge; hold via alarm_hold until TON reaches PT after fault deassert;
   clear on signal invalid; output = signal valid AND alarm_hold; PUB001/PUB004. Current TON.Q read after call.
   Slab_Fault_Counter: increment on same edge; wrap at UINT natural boundary; PUB002/PUB005.
   Slab_Runtime_Accumulator: add TO_LTIME(CycleTime) when valid and CUTTING_RUN and no fault and CycleTime>0 including first scan; LTIME ns; PUB003/PUB004.
   Slab_Fault_History[0..4]: shift oldest right, store timestamp at index0; PUB002/PUB006.
   Power-up: clear all stored state then process current inputs; prev_valid_fault starts false so first valid fault is a transition; PUB005.
   Unspecified: initial fault + invalid signal keeps alarm off until next edge; PUB004/PUB006.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK SlabThicknessAlarmFaultHistory
VAR_INPUT
    THICKNESS_FAULT : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN : BOOL;
    FaultTimestamp : DINT;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM : BOOL;
    Slab_Fault_Counter : UINT;
    Slab_Runtime_Accumulator : LTIME;
    Slab_Fault_History : ARRAY[0..4] OF DINT;
END_VAR
VAR
    alarm_hold : BOOL := FALSE;
    alarm_timer : TON;
    prev_valid_fault : BOOL := FALSE;
    init_done : BOOL := FALSE;
    valid_fault : BOOL;
END_VAR

valid_fault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;

IF NOT init_done THEN
    init_done := TRUE;
    Slab_Fault_Counter := UINT#0;
    Slab_Runtime_Accumulator := LTIME#0s;
    Slab_Fault_History[0] := DINT#0;
    Slab_Fault_History[1] := DINT#0;
    Slab_Fault_History[2] := DINT#0;
    Slab_Fault_History[3] := DINT#0;
    Slab_Fault_History[4] := DINT#0;
    alarm_hold := FALSE;
    alarm_timer(IN := FALSE, PT := T#500MS);
    THICKNESS_ALARM := FALSE;
END_IF;

IF valid_fault AND NOT prev_valid_fault THEN
    Slab_Fault_History[4] := Slab_Fault_History[3];
    Slab_Fault_History[3] := Slab_Fault_History[2];
    Slab_Fault_History[2] := Slab_Fault_History[1];
    Slab_Fault_History[1] := Slab_Fault_History[0];
    Slab_Fault_History[0] := FaultTimestamp;
    Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;
    alarm_hold := TRUE;
END_IF;

prev_valid_fault := valid_fault;

alarm_timer(IN := THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT, PT := T#500MS);

IF NOT THICKNESS_SIGNAL_VALID THEN
    alarm_hold := FALSE;
ELSIF NOT valid_fault AND alarm_timer.Q THEN
    alarm_hold := FALSE;
END_IF;

THICKNESS_ALARM := THICKNESS_SIGNAL_VALID AND alarm_hold;

IF THICKNESS_SIGNAL_VALID AND CUTTING_RUN AND NOT THICKNESS_FAULT AND (CycleTime > T#0ms) THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
END_IF;

END_FUNCTION_BLOCK