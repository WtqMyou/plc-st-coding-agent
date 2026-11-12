FUNCTION_BLOCK SlabThicknessMonitor
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
    tmp_ValidFault : BOOL := FALSE;
    tmp_PrevValidFault : BOOL := FALSE;
    tmp_FaultRisingEdge : BOOL := FALSE;
    tmp_HoldRemaining : TIME := T#0MS;
    tmp_Initialized : BOOL := FALSE;
    tmp_Index : INT := 0;
    tmp_CycleLT : LTIME := LTIME#0S;
END_VAR

(* ENGINEERING_CONTRACT
- THICKNESS_ALARM: active immediately on valid fault true; held for >= 500 ms from each valid fault rising edge; remains active while fault persists; cleared on signal invalid or power-up. Signal invalid has priority over fault. PUB001/PUB004.
- Slab_Fault_Counter: increments on each FALSE-to-TRUE transition of the valid fault composite signal; persists across scans while signal invalid; UINT overflow is unspecified. PUB002/PUB004.
- Slab_Fault_History: index 0 is newest, older fault timestamps shift toward index 4 before overwriting; zero-filled on power-up and with no records. PUB002/PUB005.
- Slab_Runtime_Accumulator: adds TIME_TO_LTIME(CycleTime) only when signal valid, CUTTING_RUN is TRUE, and no thickness fault is present; otherwise value is retained. PUB003.
- Hold timing: timer set on the fault rising edge and decremented by CycleTime only on subsequent valid invocations; first satisfying hold interval is 500 ms. PUB001.
- Invalid signal: alarm and hold state are cleared; no fault record or runtime accumulation occurs. PUB004/PUB005.
*)
(* CONTRACT_RULES [] *)

IF NOT tmp_Initialized THEN
    THICKNESS_ALARM := FALSE;
    Slab_Fault_Counter := 0;
    Slab_Runtime_Accumulator := LTIME#0S;
    FOR tmp_Index := 0 TO 4 DO
        Slab_Fault_History[tmp_Index] := 0;
    END_FOR;
    tmp_HoldRemaining := T#0MS;
    tmp_PrevValidFault := FALSE;
    tmp_Initialized := TRUE;
END_IF;

tmp_ValidFault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;
tmp_FaultRisingEdge := tmp_ValidFault AND NOT tmp_PrevValidFault;

IF NOT THICKNESS_SIGNAL_VALID THEN
    THICKNESS_ALARM := FALSE;
    tmp_HoldRemaining := T#0MS;
ELSE
    IF tmp_FaultRisingEdge THEN
        Slab_Fault_Counter := Slab_Fault_Counter + 1;
        FOR tmp_Index := 4 TO 1 BY -1 DO
            Slab_Fault_History[tmp_Index] := Slab_Fault_History[tmp_Index - 1];
        END_FOR;
        Slab_Fault_History[0] := FaultTimestamp;
        tmp_HoldRemaining := T#500MS;
    ELSIF tmp_HoldRemaining > T#0MS THEN
        IF CycleTime > T#0MS THEN
            IF tmp_HoldRemaining >= CycleTime THEN
                tmp_HoldRemaining := tmp_HoldRemaining - CycleTime;
            ELSE
                tmp_HoldRemaining := T#0MS;
            END_IF;
        END_IF;
    END_IF;

    IF THICKNESS_FAULT OR (tmp_HoldRemaining > T#0MS) THEN
        THICKNESS_ALARM := TRUE;
    ELSE
        THICKNESS_ALARM := FALSE;
    END_IF;

    IF CUTTING_RUN AND NOT THICKNESS_FAULT AND (CycleTime > T#0MS) THEN
        tmp_CycleLT := TIME_TO_LTIME(CycleTime);
        Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + tmp_CycleLT;
    END_IF;
END_IF;

tmp_PrevValidFault := tmp_ValidFault;
END_FUNCTION_BLOCK