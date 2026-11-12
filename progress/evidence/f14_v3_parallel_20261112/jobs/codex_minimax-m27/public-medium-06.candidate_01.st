FUNCTION_BLOCK SlabThicknessAlarm
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
    AlarmHoldTimer : TON;
    FallEdgeFault : R_TRIG;
    PreviousFaultValid : BOOL := FALSE;
    PreviousSignalValid : BOOL := FALSE;
END_VAR

// Detect FALSE-to-TRUE transition of valid fault signal
IF THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT AND NOT PreviousFaultValid THEN
    // Shift history and record new fault
    Slab_Fault_History[4] := Slab_Fault_History[3];
    Slab_Fault_History[3] := Slab_Fault_History[2];
    Slab_Fault_History[2] := Slab_Fault_History[1];
    Slab_Fault_History[1] := Slab_Fault_History[0];
    Slab_Fault_History[0] := FaultTimestamp;
    Slab_Fault_Counter := Slab_Fault_Counter + 1;
END_IF;

// Alarm control
IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    AlarmHoldTimer(IN := FALSE);
ELSE
    IF THICKNESS_FAULT THEN
        THICKNESS_ALARM := TRUE;
        AlarmHoldTimer(IN := FALSE);
    ELSE
        FallEdgeFault(CLK := PreviousFaultValid AND NOT THICKNESS_FAULT);
        IF FallEdgeFault.Q THEN
            AlarmHoldTimer(IN := TRUE, PT := T#500ms);
        END_IF;
        IF AlarmHoldTimer.Q THEN
            THICKNESS_ALARM := FALSE;
        END_IF;
    END_IF;
END_IF;

// Runtime accumulation
IF NOT THICKNESS_SIGNAL_VALID THEN
    Slab_Runtime_Accumulator := LTIME#0s;
ELSE
    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + LTIME_TO_LINT(CycleTime);
    END_IF;
END_IF;

// Update state tracking
PreviousFaultValid := THICKNESS_FAULT;
PreviousSignalValid := THICKNESS_SIGNAL_VALID;

END_FUNCTION_BLOCK