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

(* ENGINEERING_CONTRACT
   THICKNESS_ALARM: set when valid_fault TRUE; hold after fault deassert until 500ms TON.Q;
   clear on signal invalid or power-up; invalid signal has same-scan priority; PUB001/PUB004.
   Slab_Fault_Counter: increments on valid_fault FALSE->TRUE; power-up zero; UINT count; PUB002/PUB005.
   Slab_Runtime_Accumulator: adds CycleTime only while valid, CUTTING_RUN and no fault;
   preserved otherwise; power-up zero; LTIME ns; PUB003/PUB004/PUB005.
   Slab_Fault_History: index 0 newest; shifted right on fault edge; power-up all zero;
   DINT seconds per FaultTimestamp; PUB002/PUB005/PUB006.
   Alarm hold timer restarts on each fault deassert while signal remains valid; PUB001.
   Unspecified: UINT rollover behavior interpreted as natural wrap; PUB006.
*)
(* CONTRACT_RULES [] *)

valid_fault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;

IF NOT init_done THEN
    init_done := TRUE;
    prev_valid_fault := valid_fault;
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
ELSE
    IF valid_fault AND NOT prev_valid_fault THEN
        Slab_Fault_History[4] := Slab_Fault_History[3];
        Slab_Fault_History[3] := Slab_Fault_History[2];
        Slab_Fault_History[2] := Slab_Fault_History[1];
        Slab_Fault_History[1] := Slab_Fault_History[0];
        Slab_Fault_History[0] := FaultTimestamp;
        Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;
    END_IF;

    prev_valid_fault := valid_fault;

    IF valid_fault THEN
        alarm_hold := TRUE;
    ELSIF NOT THICKNESS_SIGNAL_VALID THEN
        alarm_hold := FALSE;
    ELSIF alarm_timer.Q THEN
        alarm_hold := FALSE;
    END_IF;

    alarm_timer(IN := THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT, PT := T#500MS);

    THICKNESS_ALARM := THICKNESS_SIGNAL_VALID AND (valid_fault OR alarm_hold);

    IF THICKNESS_SIGNAL_VALID AND CUTTING_RUN AND NOT THICKNESS_FAULT AND (CycleTime > T#0ms) THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
    END_IF;
END_IF;
END_FUNCTION_BLOCK