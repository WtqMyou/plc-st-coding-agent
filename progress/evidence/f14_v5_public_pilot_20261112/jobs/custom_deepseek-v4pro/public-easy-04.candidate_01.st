FUNCTION_BLOCK FB_JamPumpDebounceRuntime
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
    DebounceTimer : TON;
    TonIn : BOOL;
    ViscosityValid : BOOL;
    AccRuntime : LTIME := LTIME#0s;
    MAINT_THRESHOLD : LTIME := LTIME#500h;
END_VAR

(*
ENGINEERING_CONTRACT:
- VFD_RUN activation: PASTE_E_STOP_NC AND ViscosityValid; no latch.
- ViscosityValid: TON Q; debounce reset when VISCOSITY_OK FALSE or E-STOP FALSE while incomplete (PUB002/PUB003).
- E-stop same-scan priority: VFD_RUN false if PASTE_E_STOP_NC false; incomplete timer cleared.
- PUMP_RUNTIME_ACC: retained while stopped; adds CycleTime only when VFD_RUN TRUE; init 0 (PUB004/PUB005).
- PUMP_MAINT_DUE: informational latch at >= LTIME#500h; does not affect VFD_RUN (PUB004/PUB005).
- Units: DebounceTime TIME ms, CycleTime TIME ms converted to LTIME ns; threshold 500h.
*)

TonIn := VISCOSITY_OK AND (PASTE_E_STOP_NC OR DebounceTimer.Q);
DebounceTimer(IN := TonIn, PT := DebounceTime);
ViscosityValid := DebounceTimer.Q;

VFD_RUN := PASTE_E_STOP_NC AND ViscosityValid;

IF VFD_RUN THEN
    AccRuntime := AccRuntime + TIME_TO_LTIME(CycleTime);
END_IF;

PUMP_RUNTIME_ACC := AccRuntime;
PUMP_MAINT_DUE := (AccRuntime >= MAINT_THRESHOLD);

END_FUNCTION_BLOCK