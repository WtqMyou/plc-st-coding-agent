FUNCTION_BLOCK FB
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
    Slab_Runtime_Accumulator : LINT;
    Slab_Fault_History : ARRAY[0..4] OF DINT;
END_VAR
VAR
    PreviousValidFault : BOOL := FALSE;
    AlarmHoldActive : BOOL := FALSE;
    AlarmHoldElapsed : TIME := T#0MS;
    HistoryIndex : INT;
END_VAR

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    AlarmHoldActive := FALSE;
    AlarmHoldElapsed := T#0MS;
    PreviousValidFault := FALSE;
ELSE
    IF THICKNESS_FAULT AND NOT PreviousValidFault THEN
        Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;

        FOR HistoryIndex := 4 TO 1 BY -1 DO
            Slab_Fault_History[HistoryIndex] := Slab_Fault_History[HistoryIndex - 1];
        END_FOR;

        Slab_Fault_History[0] := FaultTimestamp;
        AlarmHoldActive := TRUE;
        AlarmHoldElapsed := T#0MS;
    END_IF;

    IF THICKNESS_FAULT THEN
        THICKNESS_ALARM := TRUE;
        AlarmHoldActive := TRUE;
    ELSE
        IF AlarmHoldActive AND (AlarmHoldElapsed < T#500MS) THEN
            THICKNESS_ALARM := TRUE;
        ELSE
            THICKNESS_ALARM := FALSE;
            AlarmHoldActive := FALSE;
            AlarmHoldElapsed := T#0MS;
        END_IF;
    END_IF;

    IF AlarmHoldActive AND (AlarmHoldElapsed < T#500MS) THEN
        AlarmHoldElapsed := AlarmHoldElapsed + CycleTime;
    END_IF;

    PreviousValidFault := THICKNESS_FAULT;

    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LINT(CycleTime);
    END_IF;
END_IF;
END_FUNCTION_BLOCK