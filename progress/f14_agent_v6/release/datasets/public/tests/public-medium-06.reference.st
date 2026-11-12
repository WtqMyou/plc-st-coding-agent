FUNCTION_BLOCK FB_SlabThicknessMonitor
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
    previousFault : BOOL;
    fault : BOOL;
    remaining : TIME;
    i : INT;
END_VAR
fault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;
IF NOT THICKNESS_SIGNAL_VALID THEN
    remaining := T#0ms;
ELSIF fault AND NOT previousFault THEN
    remaining := T#500ms;
    IF Slab_Fault_Counter < 65535 THEN
        Slab_Fault_Counter := Slab_Fault_Counter + 1;
    END_IF;
    FOR i := 4 TO 1 BY -1 DO
        Slab_Fault_History[i] := Slab_Fault_History[i - 1];
    END_FOR;
    Slab_Fault_History[0] := FaultTimestamp;
ELSIF remaining > CycleTime THEN
    remaining := remaining - CycleTime;
ELSE
    remaining := T#0ms;
END_IF;
THICKNESS_ALARM := THICKNESS_SIGNAL_VALID AND (fault OR remaining > T#0ms);
IF CUTTING_RUN AND THICKNESS_SIGNAL_VALID AND NOT THICKNESS_FAULT THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LTIME(CycleTime);
END_IF;
previousFault := fault;
END_FUNCTION_BLOCK
