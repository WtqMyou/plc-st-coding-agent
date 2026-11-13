(*
ENGINEERING_CONTRACT
- VFD_RUN: combinational; TRUE only when PASTE_E_STOP_NC TRUE and debounced viscosity valid; no retention; E-stop FALSE immediately disables (PUB002).
- Viscosity debounce: TON IN = VISCOSITY_OK AND NOT(incomplete AND E-stop FALSE); VISCOSITY_OK FALSE invalidates immediately; E-stop clears incomplete debounce only (PUB001,PUB002).
- Accumulator: updates by TO_LTIME(CycleTime) only while VFD_RUN TRUE this scan; otherwise holds; initial LTIME#0s (PUB003,PUB005).
- Maintenance: computed as accumulated >= LTIME#500h, informational only, remains TRUE while runtime above threshold, no reset (PUB004).
- Units: DebounceTime/CycleTime are TIME; runtime/output are LTIME; threshold uses >= boundary (PUB004).
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB_JamPumpDebouncingRuntime
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL := FALSE;
    PUMP_MAINT_DUE : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0s;
END_VAR
VAR
    tmp_DebounceTimer : TON;
    tmp_PrevDebounceQ : BOOL;
    tmp_EStopClearIncomplete : BOOL;
    tmp_Debounced : BOOL;
    tmp_RuntimeAcc : LTIME := LTIME#0s;
    tmp_MaintenanceLimit : LTIME := LTIME#500h;
END_VAR

tmp_PrevDebounceQ := tmp_DebounceTimer.Q;
tmp_EStopClearIncomplete := (NOT PASTE_E_STOP_NC) AND (NOT tmp_PrevDebounceQ);

tmp_DebounceTimer(IN := VISCOSITY_OK AND (NOT tmp_EStopClearIncomplete),
                 PT := DebounceTime);
tmp_Debounced := tmp_DebounceTimer.Q;

VFD_RUN := PASTE_E_STOP_NC AND tmp_Debounced;

IF VFD_RUN THEN
    tmp_RuntimeAcc := tmp_RuntimeAcc + TO_LTIME(CycleTime);
END_IF;

PUMP_RUNTIME_ACC := tmp_RuntimeAcc;
PUMP_MAINT_DUE := (tmp_RuntimeAcc >= tmp_MaintenanceLimit);

END_FUNCTION_BLOCK