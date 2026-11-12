FUNCTION_BLOCK SlabThicknessFaultMonitor
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
    initDone : BOOL := FALSE;
    lastValidFault : BOOL := FALSE;
    holdActive : BOOL := FALSE;
    holdElapsed : TIME := T#0MS;
    tmp_i : INT;
    tmpHoldExpired : BOOL;
    localValidFault : BOOL;
    localRising : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   THICKNESS_ALARM: active on valid-fault FALSE->TRUE (PUB001); holdActive enforces >=500ms
   using CycleTime; cleared at power-up and whenever THICKNESS_SIGNAL_VALID=FALSE (PUB004);
   remains TRUE while a valid fault persists.
   Fault record edge: logical THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT false->true (PUB002).
   lastValidFault initialised FALSE, so first valid TRUE is a transition.
   Counter +1, timestamp to slot 0, shift old entries 0..3 to 1..4, keep newest five.
   Runtime accumulation only when CUTTING_RUN, valid, no fault (PUB003); otherwise preserved.
   Power-up initialises all reported statistics and history to zero (PUB005).
*)

(* CONTRACT_RULES [] *)

IF NOT initDone THEN
    THICKNESS_ALARM := FALSE;
    Slab_Fault_Counter := 0;
    Slab_Runtime_Accumulator := LTIME#0S;
    FOR tmp_i := 0 TO 4 DO
        Slab_Fault_History[tmp_i] := 0;
    END_FOR;

    holdActive := FALSE;
    holdElapsed := T#0MS;
    lastValidFault := FALSE;
    initDone := TRUE;
    (* No RETURN here: first invocation must also evaluate current inputs *)
END_IF;

localValidFault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;
localRising := localValidFault AND NOT lastValidFault;

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    holdActive := FALSE;
    holdElapsed := T#0MS;
    lastValidFault := FALSE;
ELSE
    IF localRising THEN
        Slab_Fault_Counter := Slab_Fault_Counter + 1;

        FOR tmp_i := 4 TO 1 BY -1 DO
            Slab_Fault_History[tmp_i] := Slab_Fault_History[tmp_i - 1];
        END_FOR;

        Slab_Fault_History[0] := FaultTimestamp;

        holdActive := TRUE;
        holdElapsed := T#0MS;
    END_IF;

    IF holdActive THEN
        holdElapsed := holdElapsed + CycleTime;
        tmpHoldExpired := (holdElapsed >= T#500MS);
    ELSE
        tmpHoldExpired := FALSE;
    END_IF;

    THICKNESS_ALARM := localValidFault OR holdActive;

    IF tmpHoldExpired THEN
        holdActive := FALSE;
        holdElapsed := T#0MS;
    END_IF;

    IF CUTTING_RUN AND NOT THICKNESS_FAULT THEN
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LTIME(CycleTime);
    END_IF;

    lastValidFault := localValidFault;
END_IF;
END_FUNCTION_BLOCK