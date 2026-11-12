FUNCTION_BLOCK SlabThicknessMonitor
VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN            : BOOL;
    FaultTimestamp         : DINT;
    CycleTime              : TIME;
END_VAR

VAR_OUTPUT
    THICKNESS_ALARM          : BOOL;
    Slab_Fault_Counter       : UINT;
    Slab_Runtime_Accumulator : LTIME;
    Slab_Fault_History       : ARRAY[0..4] OF DINT;
END_VAR

VAR
    AlarmHoldTimer     : TON;
    PreviousFaultValid : BOOL;
    FirstScan          : BOOL;
    idx                : INT;
END_VAR

IF FirstScan THEN
    FirstScan := FALSE;
    Slab_Fault_Counter := 0;
    Slab_Runtime_Accumulator := LTIME#0ms;
    FOR idx := 0 TO 4 DO
        Slab_Fault_History[idx] := 0;
    END_FOR;
END_IF;

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    AlarmHoldTimer(IN := FALSE);
    PreviousFaultValid := FALSE;
ELSE
    IF THICKNESS_FAULT AND NOT PreviousFaultValid THEN
        Slab_Fault_Counter := Slab_Fault_Counter + 1;
        FOR idx := 4 TO 1 BY -1 DO
            Slab_Fault_History[idx] := Slab_Fault_History[idx-1];
        END_FOR;
        Slab_Fault_History[0] := FaultTimestamp;
    END_IF;
    PreviousFaultValid := THICKNESS_FAULT;

    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TO_LTIME(CycleTime);
    END_IF;

    IF THICKNESS_FAULT THEN
        THICKNESS_ALARM := TRUE;
        AlarmHoldTimer(IN := FALSE);
    ELSIF THICKNESS_ALARM AND NOT AlarmHoldTimer.Q THEN
        AlarmHoldTimer(IN := TRUE, PT := T#500ms);
    ELSIF NOT AlarmHoldTimer.Q THEN
        THICKNESS_ALARM := FALSE;
    END_IF;
END_IF;
END_FUNCTION_BLOCK