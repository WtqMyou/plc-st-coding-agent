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
    Initialized : BOOL := FALSE;
    CurrentValidFault : BOOL;
    LastValidFault : BOOL := FALSE;
    AlarmHolding : BOOL := FALSE;
    AlarmHoldTimer : TIME := T#0ms;
    ArrayIndex : INT;
END_VAR

IF NOT Initialized THEN
    THICKNESS_ALARM := FALSE;
    Slab_Fault_Counter := 0;
    Slab_Runtime_Accumulator := TIME_TO_LTIME(T#0ms);
    FOR ArrayIndex := 0 TO 4 DO
        Slab_Fault_History[ArrayIndex] := 0;
    END_FOR;
    AlarmHolding := FALSE;
    AlarmHoldTimer := T#0ms;
    LastValidFault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;
    Initialized := TRUE;
END_IF;

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    AlarmHolding := FALSE;
    AlarmHoldTimer := T#0ms;
    LastValidFault := FALSE;
ELSE
    CurrentValidFault := THICKNESS_FAULT;

    IF CurrentValidFault AND NOT LastValidFault THEN
        Slab_Fault_Counter := Slab_Fault_Counter + 1;
        FOR ArrayIndex := 4 TO 1 BY -1 DO
            Slab_Fault_History[ArrayIndex] := Slab_Fault_History[ArrayIndex - 1];
        END_FOR;
        Slab_Fault_History[0] := FaultTimestamp;
    END_IF;

    IF CurrentValidFault THEN
        THICKNESS_ALARM := TRUE;
        AlarmHolding := TRUE;
        AlarmHoldTimer := T#0ms;
    ELSIF AlarmHolding THEN
        AlarmHoldTimer := AlarmHoldTimer + CycleTime;
        THICKNESS_ALARM := TRUE;
        IF AlarmHoldTimer >= T#500ms THEN
            THICKNESS_ALARM := FALSE;
            AlarmHolding := FALSE;
            AlarmHoldTimer := T#0ms;
        END_IF;
    ELSE
        THICKNESS_ALARM := FALSE;
    END_IF;

    LastValidFault := CurrentValidFault;
END_IF;

IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LTIME(CycleTime);
END_IF;

END_FUNCTION_BLOCK