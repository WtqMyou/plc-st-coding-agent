FUNCTION_BLOCK FB
VAR_INPUT
    THICKNESS_FAULT: BOOL;
    THICKNESS_SIGNAL_VALID: BOOL;
    CUTTING_RUN: BOOL;
    FaultTimestamp: DINT;
    CycleTime: TIME;
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM: BOOL := FALSE;
    Slab_Fault_Counter: UINT := 0;
    Slab_Runtime_Accumulator: LINT := 0;
    Slab_Fault_History: ARRAY[0..4] OF DINT := [0,0,0,0,0];
END_VAR
VAR
    faultPrev: BOOL := FALSE;
    alarmHoldTimer: TIME := T#0ms;
    i: INT;
END_VAR

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    alarmHoldTimer := T#0ms;
    faultPrev := FALSE;
ELSE
    IF THICKNESS_FAULT AND NOT faultPrev THEN
        Slab_Fault_Counter := Slab_Fault_Counter + 1;
        i := 4;
        WHILE i >= 1 DO
            Slab_Fault_History[i] := Slab_Fault_History[i-1];
            i := i - 1;
        END_WHILE;
        Slab_Fault_History[0] := FaultTimestamp;
    END_IF;

    IF THICKNESS_FAULT THEN
        THICKNESS_ALARM := TRUE;
        alarmHoldTimer := T#0ms;
    ELSE
        IF THICKNESS_ALARM THEN
            alarmHoldTimer := alarmHoldTimer + CycleTime;
            IF alarmHoldTimer >= T#500ms THEN
                THICKNESS_ALARM := FALSE;
                alarmHoldTimer := T#0ms;
            ELSE
                THICKNESS_ALARM := TRUE;
            END_IF;
        ELSE
            THICKNESS_ALARM := FALSE;
            alarmHoldTimer := T#0ms;
        END_IF;
    END_IF;

    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LINT(CycleTime);
    END_IF;

    faultPrev := THICKNESS_FAULT;
END_IF;

END_FUNCTION_BLOCK