FUNCTION_BLOCK JamPumpControl
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
    viscosityValid : BOOL := FALSE;
    viscosityDebounce : TON;
END_VAR

(* ENGINEERING_CONTRACT
Viscosity state PUB001/PUB002: activation after VISCOSITY_OK remains TRUE for DebounceTime via TON; invalidated immediately on VISCOSITY_OK FALSE; already-valid state retained through E-stop; incomplete debounce timing cleared on E-stop FALSE.
VFD_RUN PUB002/PUB005: activation = PASTE_E_STOP_NC AND viscosityValid; no hold/latch; E-stop FALSE disables run immediately in same scan; initialized FALSE.
PUMP_RUNTIME_ACC PUB003/PUB005: activation after current VFD_RUN computation; adds TIME_TO_LTIME(CycleTime) while VFD_RUN TRUE; retained while stopped; no explicit reset; initialized LTIME#0s.
PUMP_MAINT_DUE PUB004/PUB005: activation and retention when PUMP_RUNTIME_ACC >= LTIME#500h; no reset; informational only, never gates run/permissive; initialized FALSE.
Same-scan priority: E-stop disable and viscosity invalidation occur before run accumulation; maintenance computation is independent.
Units/boundaries: DebounceTime TIME ms, CycleTime TIME ms, PUMP_RUNTIME_ACC LTIME ns, maintenance threshold >= 500 h.
*)

(* CONTRACT_RULES [] *)

viscosityDebounce(IN := VISCOSITY_OK AND PASTE_E_STOP_NC,
                  PT := DebounceTime);

IF NOT VISCOSITY_OK THEN
    viscosityValid := FALSE;
ELSIF viscosityDebounce.Q THEN
    viscosityValid := TRUE;
END_IF;

VFD_RUN := PASTE_E_STOP_NC AND viscosityValid;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TIME_TO_LTIME(CycleTime);
END_IF;

IF PUMP_RUNTIME_ACC >= LTIME#500h THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK