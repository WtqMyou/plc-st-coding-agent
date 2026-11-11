FUNCTION_BLOCK SlabThicknessMonitor
VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    cutting_run            : BOOL;
    faulttimestamp         : DINT;
    cycletime              : TIME;
END_VAR

VAR_OUTPUT
    THICKNESS_ALARM           : BOOL;
    slab_fault_counter        : UINT;
    slab_runtime_accumulator  : LTIME;
    slab_fault_history        : ARRAY[0..4] OF DINT;
END_VAR

VAR
    AlarmHoldTimer   : TON;
    FaultWasActive   : BOOL;
    PowerUpComplete  : BOOL;
    i                : INT;
END_VAR

IF NOT PowerUpComplete THEN
    THICKNESS_ALARM           := FALSE;
    slab_fault_counter        := 0;
    slab_runtime_accumulator  := LTIME#0s;
    
    FOR i := 0 TO 4 DO
        slab_fault_history[i] := 0;
    END_FOR
    
    FaultWasActive  := FALSE;
    PowerUpComplete := TRUE;
END_IF

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    AlarmHoldTimer(IN := FALSE);
    FaultWasActive  := FALSE;
ELSE
    AlarmHoldTimer(IN := THICKNESS_FAULT, PT := T#500ms);
    THICKNESS_ALARM := THICKNESS_FAULT OR AlarmHoldTimer.Q;
    
    IF THICKNESS_FAULT AND NOT FaultWasActive THEN
        slab_fault_counter        := slab_fault_counter + 1;
        slab_fault_history[4]     := slab_fault_history[3];
        slab_fault_history[3]     := slab_fault_history[2];
        slab_fault_history[2]     := slab_fault_history[1];
        slab_fault_history[1]     := slab_fault_history[0];
        slab_fault_history[0]     := faulttimestamp;
    END_IF;
    
    FaultWasActive := THICKNESS_FAULT;
    
    IF cutting_run AND NOT THICKNESS_FAULT THEN
        slab_runtime_accumulator := slab_runtime_accumulator + cycletime;
    END_IF
END_IF

END_FUNCTION_BLOCK