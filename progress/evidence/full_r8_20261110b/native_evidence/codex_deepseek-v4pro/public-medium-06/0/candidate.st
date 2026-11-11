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
    LastValidFaultSignal : BOOL;
    AlarmHoldRemaining : USINT;
    ShiftIndex : INT;
END_VAR

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    AlarmHoldRemaining := 0;
    LastValidFaultSignal := FALSE;
ELSE
    IF THICKNESS_FAULT THEN
        THICKNESS_ALARM := TRUE;
        AlarmHoldRemaining := 25;

        IF NOT LastValidFaultSignal THEN
            IF Slab_Fault_Counter < 65535 THEN
                Slab_Fault_Counter := Slab_Fault_Counter + 1;
            END_IF;

            Slab_Fault_History[0] := FaultTimestamp;
            FOR ShiftIndex := 4 TO 1 BY -1 DO
                Slab_Fault_History[ShiftIndex] := Slab_Fault_History[ShiftIndex - 1];
            END_FOR;
        END_IF;

        LastValidFaultSignal := TRUE;
    ELSE
        IF AlarmHoldRemaining > 0 THEN
            THICKNESS_ALARM := TRUE;
            AlarmHoldRemaining := AlarmHoldRemaining - 1;
        ELSE
            THICKNESS_ALARM := FALSE;
        END_IF;

        LastValidFaultSignal := FALSE;
    END_IF;
END_IF;

IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + 1;
END_IF;

END_FUNCTION_BLOCK