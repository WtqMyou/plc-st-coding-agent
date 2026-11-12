FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN          : BOOL := FALSE;
    PUMP_MAINT_DUE   : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0s;
END_VAR
VAR
    TON_Viscosity     : TON;
    debouncedViscosity : BOOL := FALSE;
END_VAR

(* CONTRACT: Jam Pump Debouncing and Runtime Maintenance
 * =====================================================
 * | Output/State  | Activation            | Retention              | Reset/Deactivation         | Priority    | Units/Bounds         |
 * |---------------|-----------------------|------------------------|----------------------------|-------------|----------------------|
 * | VFD_RUN       | E_STOP_NC AND debouncedViscosity | Hold while both TRUE | E_STOP_NC=FALSE or viscosity invalid | Same-scan | BOOL |
 * | debouncedViscosity | VISCOSITY_OK held TRUE for DebounceTime | Hold while VISCOSITY_OK | VISCOSITY_OK=FALSE | Same-scan | BOOL |
 * | PUMP_RUNTIME_ACC | Accumulate CycleTime while VFD_RUN | Preserve while VFD_RUN=FALSE | Never reset by this block | N/A | LTIME nanoseconds |
 * | PUMP_MAINT_DUE   | PUMP_RUNTIME_ACC >= 500 hours | Hold once set | Not specified (informational only) | N/A | BOOL |
 * | TON_Viscosity    | debounceEnable = VISCITY_OK AND NOT debouncedViscosity | N/A | VISCOSITY_OK drops | Same-scan | TIME |
 *
 * PUB001: Accept viscosity after DebounceTime continuous TRUE; invalidate immediately on FALSE
 * PUB002: VFD_RUN only when E_STOP_NC=TRUE AND viscosity valid; E-STOP disables output and clears debounce
 * PUB003: Accumulate runtime using CycleTime only while VFD_RUN; preserve when stopped
 * PUB004: PUMP_MAINT_DUE at 500 hours; informational, no effect on operation or safety
 * PUB005: Power-up: VFD_RUN=FALSE, PUMP_RUNTIME_ACC=0, PUMP_MAINT_DUE=FALSE
 *)

(* Power-up initialization - first scan sets declared defaults (VAR_INIT) *)
(* Debounced viscosity and TON internal state default to cleared *)

(* Debounce logic: accumulate time only when transitioning from invalid to valid *)
TON_Viscosity(
    IN  := VISCOSITY_OK AND NOT debouncedViscosity,
    PT  := DebounceTime
);

(* Debounced output: TRUE when timer has elapsed *)
debouncedViscosity := TON_Viscosity.Q;

(* VFD command: requires E-STOP permissive AND viscosity debounced *)
VFD_RUN := PASTE_E_STOP_NC AND debouncedViscosity;

(* Runtime accumulation: only while pump is running *)
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime);
END_IF;

(* Maintenance due: informational flag, set at threshold, never auto-cleared *)
IF PUMP_RUNTIME_ACC >= LTIME#500h THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK
(* CONTRACT_RULES [{"kind": "hold_until_reset", "output": "PUMP_MAINT_DUE", "set_input": null, "reset_input": null}] *)