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
    PowerUp : BOOL := TRUE;
    LastValidFault : BOOL := FALSE;
    CurrentFault : BOOL;
    AlarmHoldActive : BOOL := FALSE;
    AlarmHoldElapsed : TIME := T#0ms;
    LoopIndex : INT;
END_VAR

IF PowerUp THEN
    THICKNESS_ALARM := FALSE;
    Slab_Fault_Counter := 0;
    Slab_Runtime_Accumulator := TIME_TO_LTIME(T#0ms);
    FOR LoopIndex := 0 TO 4 DO
        Slab_Fault_History[LoopIndex] := 0;
    END_FOR;
    LastValidFault := FALSE;
    AlarmHoldActive := FALSE;
    AlarmHoldElapsed := T#0ms;
    PowerUp := FALSE;
END_IF;

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    AlarmHoldActive := FALSE;
    AlarmHoldElapsed := T#0ms;
    LastValidFault := FALSE;
ELSE
    CurrentFault := THICKNESS_FAULT;

    IF CurrentFault AND NOT LastValidFault THEN
        Slab_Fault_Counter := Slab_Fault_Counter + 1;
        FOR LoopIndex := 4 TO 1 BY -1 DO
            Slab_Fault_History[LoopIndex] := Slab_Fault_History[LoopIndex - 1];
        END_FOR;
        Slab_Fault_History[0] := FaultTimestamp;
    END_IF;

    IF CurrentFault THEN
        THICKNESS_ALARM := TRUE;
        AlarmHoldActive := TRUE;
        AlarmHoldElapsed := T#0ms;
    ELSIF AlarmHoldActive THEN
        AlarmHoldElapsed := AlarmHoldElapsed + CycleTime;
        IF AlarmHoldElapsed >= T#500ms THEN
            THICKNESS_ALARM := FALSE;
            AlarmHoldActive := FALSE;
            AlarmHoldElapsed := T#0ms;
        ELSE
            THICKNESS_ALARM := TRUE;
        END_IF;
    ELSE
        THICKNESS_ALARM := FALSE;
    END_IF;

    LastValidFault := CurrentFault;
END_IF;

IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LTIME(CycleTime);
END_IF;

END_FUNCTION_BLOCK