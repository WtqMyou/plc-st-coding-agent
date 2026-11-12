(*
ENGINEERING_CONTRACT
PUB001: Jam pump control with viscosity debounce, E-stop priority, runtime accumulation, maintenance indication.
PUB002: Viscosity condition valid only after VISCOSITY_OK has remained TRUE for DebounceTime continuously; invalid immediately when VISCOSITY_OK false. Hold: TON Q while IN true. Reset/deactivate: IN false -> Q false and ET=0.
PUB003: VFD_RUN activation: PASTE_E_STOP_NC TRUE and viscosityTON.Q TRUE. Hold while both TRUE. Deactivation immediate if PASTE_E_STOP_NC false or viscosity invalid. E-stop clears incomplete debounce via TON IN false. Priority: E-stop over run.
PUB004: PUMP_RUNTIME_ACC add TIME_TO_LTIME(CycleTime) each scan only while VFD_RUN TRUE. Retain accumulated time when stopped. Units LTIME ns; CycleTime positive TIME.
PUB005: PUMP_MAINT_DUE activation: PUMP_RUNTIME_ACC >= LTIME#500h; holds true, no reset input. Informational only; no VFD_RUN influence.
PUB006: Power-up first scan: VFD_RUN = FALSE, PUMP_RUNTIME_ACC = LTIME#0s, PUMP_MAINT_DUE = FALSE.
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK: BOOL;
    PASTE_E_STOP_NC: BOOL;
    DebounceTime: TIME;
    CycleTime: TIME;
END_VAR

VAR_OUTPUT
    VFD_RUN: BOOL;
    PUMP_MAINT_DUE: BOOL;
    PUMP_RUNTIME_ACC: LTIME;
END_VAR

VAR
    local_initialized: BOOL;
    viscosityTON: TON;
END_VAR

IF NOT local_initialized THEN
    VFD_RUN := FALSE;
    PUMP_MAINT_DUE := FALSE;
    PUMP_RUNTIME_ACC := LTIME#0s;
    local_initialized := TRUE;
END_IF;

viscosityTON(IN := VISCOSITY_OK AND PASTE_E_STOP_NC, PT := DebounceTime);

VFD_RUN := viscosityTON.Q AND PASTE_E_STOP_NC;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TIME_TO_LTIME(CycleTime);
END_IF;

IF PUMP_RUNTIME_ACC >= LTIME#500h THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK