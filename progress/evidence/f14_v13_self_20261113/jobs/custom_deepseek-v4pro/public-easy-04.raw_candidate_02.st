FUNCTION_BLOCK JamPump
(*
ENGINEERING_CONTRACT
- VFD_RUN: active only when PASTE_E_STOP_NC AND debounce valid (PUB002); off immediately on estop false or viscosity false; no retention.
- Debounce: valid only after VISCOSITY_OK continuously true for DebounceTime; input false clears valid immediately. Incomplete timing is cleared while estop false; already-valid condition is not cleared by estop.
- Runtime: PUMP_RUNTIME_ACC adds CycleTime only when final same-scan VFD_RUN is true; retained while stopped; zero at init (PUB003/PUB005).
- Maintenance: PUMP_MAINT_DUE latches when accumulated LTIME >= 500h; no reset; informational and does not influence VFD_RUN (PUB004).
- Same-scan: reset/invalidate first, compute VFD_RUN, then add runtime using final VFD_RUN.
- Units: TIME inputs converted to LTIME; comparison >=; 500h = LTIME#500h.
*)
(* CONTRACT_RULES [] *)
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
    tmp_debounce_elapsed : LTIME := LTIME#0s;
    tmp_debounce_valid : BOOL := FALSE;
    tmp_runtime_acc : LTIME := LTIME#0s;
    tmp_maintenance_latched : BOOL := FALSE;
    tmp_cycle_lt : LTIME;
    tmp_debounce_pt_lt : LTIME;
    tmp_maint_threshold_lt : LTIME := LTIME#500h;
END_VAR

tmp_cycle_lt := TIME_TO_LTIME(CycleTime);
tmp_debounce_pt_lt := TIME_TO_LTIME(DebounceTime);

IF NOT VISCOSITY_OK THEN
    tmp_debounce_elapsed := LTIME#0s;
    tmp_debounce_valid := FALSE;
ELSIF NOT PASTE_E_STOP_NC THEN
    IF NOT tmp_debounce_valid THEN
        tmp_debounce_elapsed := LTIME#0s;
    END_IF;
ELSE
    IF NOT tmp_debounce_valid THEN
        tmp_debounce_elapsed := tmp_debounce_elapsed + tmp_cycle_lt;
        IF tmp_debounce_elapsed > tmp_debounce_pt_lt THEN
            tmp_debounce_valid := TRUE;
            tmp_debounce_elapsed := tmp_debounce_pt_lt;
        END_IF;
    END_IF;
END_IF;

VFD_RUN := PASTE_E_STOP_NC AND tmp_debounce_valid;

IF VFD_RUN THEN
    tmp_runtime_acc := tmp_runtime_acc + tmp_cycle_lt;
END_IF;

IF tmp_runtime_acc >= tmp_maint_threshold_lt THEN
    tmp_maintenance_latched := TRUE;
END_IF;

PUMP_MAINT_DUE := tmp_maintenance_latched;
PUMP_RUNTIME_ACC := tmp_runtime_acc;

END_FUNCTION_BLOCK