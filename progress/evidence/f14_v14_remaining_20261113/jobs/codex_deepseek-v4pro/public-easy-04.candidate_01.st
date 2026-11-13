FUNCTION_BLOCK FB_JamPumpControl
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL;
    PUMP_MAINT_DUE : BOOL;
    PUMP_RUNTIME_ACC : LTIME;
END_VAR
VAR
    tmp_first_scan : BOOL := TRUE;
    tmp_debounce_enable : BOOL;
    tmp_debounce_timer : TON;
    tmp_viscosity_valid : BOOL;
    tmp_runtime_acc : LTIME;
    tmp_maintenance_threshold : LTIME;
END_VAR

(* ENGINEERING_CONTRACT
VFD_RUN: active iff PASTE_E_STOP_NC AND tmp_viscosity_valid; any false permissive deactivates immediately; final same-scan inputs decide run and accumulation (PUB002).
Debounce validity: set same scan TON.Q fires; hold while VISCOSITY_OK remains TRUE; reset only when VISCOSITY_OK=FALSE (PUB001).
E-stop: clears incomplete debounce timing; completed viscosity validity is retained while VISCOSITY_OK remains TRUE (PUB002).
PUMP_RUNTIME_ACC: add TIME_TO_LTIME(CycleTime) only when final VFD_RUN=TRUE; preserve while stopped; starts at 0ns (PUB003).
PUMP_MAINT_DUE: remains TRUE when accumulated LTIME >= TIME_TO_LTIME(T#500h); informational only; starts FALSE (PUB004).
Initialization: first scan sets run OFF, accumulated runtime 0ns, maintenance FALSE (PUB005).
Units: TIME inputs in ms; LTIME accumulation in ns; maintenance threshold strictly by >= at 500h.
*)

(* CONTRACT_RULES [] *)

IF tmp_first_scan THEN
    tmp_first_scan := FALSE;
    tmp_viscosity_valid := FALSE;
    tmp_runtime_acc := TIME_TO_LTIME(T#0ms);
    VFD_RUN := FALSE;
    PUMP_MAINT_DUE := FALSE;
    PUMP_RUNTIME_ACC := TIME_TO_LTIME(T#0ms);
END_IF;

tmp_maintenance_threshold := TIME_TO_LTIME(T#500h);
tmp_debounce_enable := VISCOSITY_OK AND PASTE_E_STOP_NC AND NOT tmp_viscosity_valid;
tmp_debounce_timer(IN := tmp_debounce_enable, PT := DebounceTime);

IF VISCOSITY_OK THEN
    IF tmp_debounce_timer.Q THEN
        tmp_viscosity_valid := TRUE;
    END_IF;
ELSE
    tmp_viscosity_valid := FALSE;
END_IF;

VFD_RUN := PASTE_E_STOP_NC AND tmp_viscosity_valid;

IF VFD_RUN THEN
    tmp_runtime_acc := tmp_runtime_acc + TIME_TO_LTIME(CycleTime);
END_IF;

PUMP_RUNTIME_ACC := tmp_runtime_acc;
PUMP_MAINT_DUE := tmp_runtime_acc >= tmp_maintenance_threshold;

END_FUNCTION_BLOCK