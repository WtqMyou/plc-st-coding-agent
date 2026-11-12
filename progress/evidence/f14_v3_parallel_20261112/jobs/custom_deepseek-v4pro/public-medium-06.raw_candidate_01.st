FUNCTION_BLOCK SlabThicknessAlarm
VAR_INPUT
    THICKNESS_FAULT : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN : BOOL;
    FaultTimestamp : DINT;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM : BOOL := FALSE;
    Slab_Fault_Counter : UINT := 0;
    Slab_Runtime_Accumulator : LTIME := LTIME#0S;
    Slab_Fault_History : ARRAY[0..4] OF DINT := [0,0,0,0,0];
END_VAR
VAR
    lastValidFault : BOOL := FALSE;
    holdTimer : TIME := T#0MS;
    currentValidFault : BOOL;
    dt : LTIME;
    i : INT;
END_VAR

currentValidFault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    holdTimer := T#0MS;
ELSE
    dt := TIME_TO_LTIME(CycleTime);

    IF currentValidFault AND NOT lastValidFault THEN
        Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;

        FOR i := 4 TO 1 BY -1 DO
            Slab_Fault_History[i] := Slab_Fault_History[i - 1];
        END_FOR;

        Slab_Fault_History[0] := FaultTimestamp;
        holdTimer := T#500MS;
    END_IF;

    IF holdTimer > T#0MS THEN
        IF holdTimer > CycleTime THEN
            holdTimer := holdTimer - CycleTime;
        ELSE
            holdTimer := T#0MS;
        END_IF;
    END_IF;

    IF THICKNESS_FAULT OR (holdTimer > T#0MS) THEN
        THICKNESS_ALARM := TRUE;
    ELSE
        THICKNESS_ALARM := FALSE;
    END_IF;

    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + dt;
    END_IF;
END_IF;

lastValidFault := currentValidFault;

END_FUNCTION_BLOCK