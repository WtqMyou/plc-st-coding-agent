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
    AlarmHoldActive : BOOL := FALSE;
    AlarmHoldElapsed : TIME := T#0ms;
    LastValidFault : BOOL := FALSE;
    InitDone : BOOL := FALSE;
    i : INT;
END_VAR

IF NOT InitDone THEN
    // Power-up initialization
    THICKNESS_ALARM := FALSE;
    Slab_Fault_Counter := 0;
    Slab_Runtime_Accumulator := LTIME#0s;
    FOR i := 0 TO 4 DO
        Slab_Fault_History[i] := 0;
    END_FOR
    AlarmHoldActive := FALSE;
    AlarmHoldElapsed := T#0ms;
    LastValidFault := FALSE;
    InitDone := TRUE;
END_IF

IF NOT THICKNESS_SIGNAL_VALID THEN
    // Signal lost: clear alarm and holding state, no recording or accumulation
    THICKNESS_ALARM := FALSE;
    AlarmHoldActive := FALSE;
    AlarmHoldElapsed := T#0ms;
    LastValidFault := FALSE;
ELSE
    // Detect FALSE->TRUE transition of valid fault signal
    IF (THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID) AND NOT LastValidFault THEN
        // Increment fault counter
        Slab_Fault_Counter := Slab_Fault_Counter + 1;

        // Shift history, store newest timestamp at index 0
        Slab_Fault_History[4] := Slab_Fault_History[3];
        Slab_Fault_History[3] := Slab_Fault_History[2];
        Slab_Fault_History[2] := Slab_Fault_History[1];
        Slab_Fault_History[1] := Slab_Fault_History[0];
        Slab_Fault_History[0] := FaultTimestamp;

        // Start minimum 500 ms hold
        AlarmHoldActive := TRUE;
        AlarmHoldElapsed := T#0ms;
    END_IF

    // Update alarm hold timer
    IF AlarmHoldActive THEN
        AlarmHoldElapsed := AlarmHoldElapsed + CycleTime;
        IF AlarmHoldElapsed >= T#500ms THEN
            AlarmHoldActive := FALSE;
            AlarmHoldElapsed := T#0ms;
        END_IF
    END_IF

    // Alarm is active while fault persists or during minimum hold time
    THICKNESS_ALARM := (THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID) OR AlarmHoldActive;

    // Accumulate normal-cutting runtime only under valid, fault-free cutting conditions
    IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LTIME(CycleTime);
    END_IF

    // Store current valid fault state for next edge detection
    LastValidFault := THICKNESS_FAULT AND THICKNESS_SIGNAL_VALID;
END_IF