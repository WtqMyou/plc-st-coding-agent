FUNCTION_BLOCK FB_SlabThicknessFaultMonitor
VAR_INPUT
    THICKNESS_FAULT        : BOOL;
    THICKNESS_SIGNAL_VALID : BOOL;
    CUTTING_RUN            : BOOL;
    FaultTimestamp         : DINT;
    CycleTime              : TIME; (* Must be positive *)
END_VAR
VAR_OUTPUT
    THICKNESS_ALARM        : BOOL;
    Slab_Fault_Counter     : UINT;
    Slab_Runtime_Accumulator : LTIME;
    Slab_Fault_History     : ARRAY[0..4] OF DINT; (* Read-only to callers *)
END_VAR
VAR
    Initialized    : BOOL;
    ValidFault     : BOOL;
    FaultRise      : R_TRIG;
    HoldTimer      : TON;
    HoldActive     : BOOL;
    HistoryStore   : ARRAY[0..4] OF DINT;
    i              : INT;
END_VAR

ValidFault := THICKNESS_SIGNAL_VALID AND THICKNESS_FAULT;

(* Power-up initialization *)
IF NOT Initialized THEN
    Slab_Fault_Counter := UINT#0;
    Slab_Runtime_Accumulator := LTIME#0S;

    FOR i := 0 TO 4 DO
        HistoryStore[i] := DINT#0;
    END_FOR;

    HoldActive := FALSE;
    HoldTimer(IN := FALSE, PT := T#500MS);
    Initialized := TRUE;
END_IF;

FaultRise(CLK := ValidFault);

IF NOT THICKNESS_SIGNAL_VALID THEN
    (* Signal invalid: alarm off, no holding, no fault records *)
    THICKNESS_ALARM := FALSE;
    HoldActive := FALSE;
    HoldTimer(IN := FALSE, PT := T#500MS);
ELSE
    IF FaultRise.Q THEN
        (* New valid thickness fault occurrence *)
        Slab_Fault_Counter := Slab_Fault_Counter + UINT#1;

        FOR i := 4 TO 1 BY -1 DO
            HistoryStore[i] := HistoryStore[i - 1];
        END_FOR;
        HistoryStore[0] := FaultTimestamp;

        (* Retrigger the minimum alarm hold *)
        HoldActive := FALSE;
    END_IF;

    HoldTimer(IN := HoldActive, PT := T#500MS);

    IF HoldTimer.Q THEN
        HoldActive := FALSE;
    END_IF;

    IF FaultRise.Q THEN
        HoldActive := TRUE;
    END_IF;

    THICKNESS_ALARM := THICKNESS_FAULT OR HoldActive;
END_IF;

(* Accumulate normal cutting runtime only under valid, fault-free running conditions *)
IF THICKNESS_SIGNAL_VALID
   AND CUTTING_RUN
   AND NOT THICKNESS_FAULT
   AND (CycleTime > T#0MS) THEN
    Slab_Runtime_Accumulator := Slab_Runtime_Accumulator + TIME_TO_LTIME(CycleTime);
END_IF;

(* Expose history as a copy; internal storage remains protected from direct caller changes *)
Slab_Fault_History := HistoryStore;