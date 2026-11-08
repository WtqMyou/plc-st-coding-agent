FUNCTION_BLOCK FB
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
    Slab_Runtime_Accumulator  : LINT := 0;
    Slab_Fault_History        : ARRAY[0..4] OF DINT;
END_VAR
VAR
    FaultPrev      : BOOL := FALSE;
    AlarmHoldTimer : TON;
    i              : INT;
END_VAR

    IF NOT THICKNESS_SIGNAL_VALID THEN
        THICKNESS_ALARM := FALSE;
        Slab_Fault_Counter := 0;
        Slab_Runtime_Accumulator := 0;
        Slab_Fault_History[0] := 0;
        Slab_Fault_History[1] := 0;
        Slab_Fault_History[2] := 0;
        Slab_Fault_History[3] := 0;
        Slab_Fault_History[4] := 0;
        AlarmHoldTimer(IN := FALSE);
        FaultPrev := FALSE;
    ELSE
        IF THICKNESS_FAULT THEN
            AlarmHoldTimer(IN := TRUE, PT := T#500ms);
            IF NOT FaultPrev THEN
                Slab_Fault_Counter := Slab_Fault_Counter + 1;
                FOR i := 4 TO 1 BY -1 DO
                    Slab_Fault_History[i] := Slab_Fault_History[i-1];
                END_FOR;
                Slab_Fault_History[0] := FaultTimestamp;
            END_IF;
        ELSE
            AlarmHoldTimer(IN := FALSE);
        END_IF;
        IF CUTTING_RUN THEN
            Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LINT(CycleTime);
        END_IF;
        THICKNESS_ALARM := THICKNESS_FAULT OR AlarmHoldTimer.Q;
        FaultPrev := THICKNESS_FAULT;
    END_IF;

END_FUNCTION_BLOCK