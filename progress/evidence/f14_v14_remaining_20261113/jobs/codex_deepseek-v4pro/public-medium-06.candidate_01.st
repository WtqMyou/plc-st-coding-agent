FUNCTION_BLOCK FB_SlabThicknessAlarmHistory
(* ENGINEERING_CONTRACT
THICKNESS_ALARM: set on valid-fault rising edge; TON holds >=500 ms; current fault keeps it on; signal invalid clears (PUB001,PUB004).
Slab_Fault_Counter: increments once per valid-fault rising edge; retained otherwise; UINT wrap unspecified (PUB002).
Slab_Fault_History: newest stored at index 0, older entries shifted upward, five entries retained; zero at power-up (PUB002,PUB005).
Slab_Runtime_Accumulator: adds TIME_TO_LTIME(CycleTime) only when CUTTING_RUN AND valid AND NOT fault; retained otherwise (PUB003).
Invalid/power-up: alarm false and timer cleared; no record or runtime accumulation while signal invalid (PUB004,PUB005).
Same-scan priority: record/alarm edge processed before runtime condition, so a faulted scan adds no normal runtime.
Hold timer: retriggerable; edge reset precedes enabled TON call; Q completion releases hold on the following valid scan.
Units/boundaries: hold threshold T#500MS inclusive via TON >=; runtime LTIME nanoseconds; history index 0 newest.
*)
(* CONTRACT_RULES [] *)
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
    local_valid_fault : BOOL;
    local_fault_rise : R_TRIG;
    local_alarm_timer : TON;
    local_hold_active : BOOL;
    local_cycle_ltime : LTIME;
    local_i : INT;
END_VAR

local_valid_fault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;
local_fault_rise(CLK := local_valid_fault);
local_cycle_ltime := TIME_TO_LTIME(CycleTime);

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    local_hold_active := FALSE;
    local_alarm_timer(IN := FALSE, PT := T#500MS);
ELSIF local_fault_rise.Q THEN
    Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;

    FOR local_i := 4 TO 1 BY -1 DO
        Slab_Fault_History[local_i] := Slab_Fault_History[local_i - 1];
    END_FOR;

    Slab_Fault_History[0] := FaultTimestamp;
    local_hold_active := TRUE;
    local_alarm_timer(IN := FALSE, PT := T#500MS);
END_IF;

IF THICKNESS_SIGNAL_VALID THEN
    IF local_alarm_timer.Q THEN
        local_hold_active := FALSE;
    END_IF;

    local_alarm_timer(IN := local_hold_active, PT := T#500MS);

    THICKNESS_ALARM := THICKNESS_FAULT OR local_hold_active;
END_IF;

IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + local_cycle_ltime;
END_IF;

END_FUNCTION_BLOCK