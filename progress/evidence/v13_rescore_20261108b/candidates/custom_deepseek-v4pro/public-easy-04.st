FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK: BOOL;
    PASTE_E_STOP_NC: BOOL;
    DebounceTime: TIME;
    CycleTime: TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN: BOOL;
    PUMP_MAINT_DUE: BOOL;
    PUMP_RUNTIME_ACC: LINT;
END_VAR
VAR
    DebounceAccum: LINT := 0;               (* Debounce accumulated time in ms *)
    AccumRuntime: LINT := 0;                (* Accumulated pump runtime in ms *)
    MaintDue: BOOL := FALSE;                (* Maintenance due latch *)
    DebounceTimeMs: LINT := 0;              (* DebounceTime in ms *)
    MAINT_THRESHOLD: LINT := 1800000000;    (* 500 hours in ms *)
END_VAR

(* Convert DebounceTime to milliseconds (CODESYS TIME_TO_LINT preserves ms value) *)
DebounceTimeMs := TIME_TO_LINT(DebounceTime);

(* Debounce logic with E-stop priority:
   - VISCOSITY_OK FALSE immediately clears debounce.
   - E-stop active clears only incomplete debounce, keeps completed condition.
   - Normal condition accumulates when signal is stable and E-stop is OK.
*)
IF NOT VISCOSITY_OK THEN
    DebounceAccum := 0;
ELSIF NOT PASTE_E_STOP_NC THEN
    IF DebounceAccum < DebounceTimeMs THEN
        DebounceAccum := 0;
    END_IF;
ELSE
    IF DebounceAccum < DebounceTimeMs THEN
        DebounceAccum := DebounceAccum + TIME_TO_LINT(CycleTime);
        IF DebounceAccum > DebounceTimeMs THEN
            DebounceAccum := DebounceTimeMs;
        END_IF;
    END_IF;
END_IF;

(* Run command requires E-stop OK, viscosity raw signal TRUE and debounced condition valid *)
VFD_RUN := PASTE_E_STOP_NC AND VISCOSITY_OK AND (DebounceAccum >= DebounceTimeMs);

(* Accumulate enabled runtime only while pump is running *)
IF VFD_RUN THEN
    AccumRuntime := AccumRuntime + TIME_TO_LINT(CycleTime);
END_IF;

(* Maintenance due latch when accumulated time reaches 500 hours (1,800,000,000 ms) *)
IF AccumRuntime >= MAINT_THRESHOLD THEN
    MaintDue := TRUE;
END_IF;

(* Map internal state to outputs *)
PUMP_RUNTIME_ACC := AccumRuntime;
PUMP_MAINT_DUE := MaintDue;

END_FUNCTION_BLOCK