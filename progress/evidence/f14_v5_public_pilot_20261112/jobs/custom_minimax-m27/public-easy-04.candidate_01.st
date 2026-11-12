FUNCTION_BLOCK FB_JamPumpControl
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN          : BOOL;
    PUMP_MAINT_DUE   : BOOL;
    PUMP_RUNTIME_ACC : LTIME;
END_VAR
VAR
    DebounceTimer : TON;
END_VAR

(*
ENGINEERING_CONTRACT - FB_JamPumpControl
================================================================================
| Output/State      | Activation           | Retention      | Reset/Deactivation           | Same-Scan | Units/Boundaries     |
|-------------------|----------------------|----------------|------------------------------|-----------|----------------------|
| VFD_RUN           | ESTOP AND vis_valid  | Hold TRUE      | Immediate: ESTOP=FALSE or    | ESTOP pri | Boolean              |
|                   |                      |                | viscosity_valid=FALSE        |           |                      |
| viscosity_valid   | DebounceTimer.Q=TRUE | Hold TRUE      | Immediate on VISCOSITY_OK=   | -         | Internal TON state   |
|                   |                      |                | FALSE or PASTE_E_STOP_NC=FALSE|          |                      |
| PUMP_RUNTIME_ACC  | Add CycleTime when   | Retain when    | Power-up init to 0 LTIME     | -         | LTIME (nanoseconds)  |
|                   | VFD_RUN=TRUE         | VFD_RUN=FALSE  |                              |           |                      |
| PUMP_MAINT_DUE    | ACC >= 500h (1.8e12ns)| Indefinite    | None (informational only)    | -         | Boolean              |
================================================================================
PUB001: Jam transfer pump control with viscosity debouncing, E-stop priority.
PUB002: VISCOSITY_OK debounced after DebounceTime; invalidated immediately on FALSE.
PUB003: VFD_RUN requires PASTE_E_STOP_NC=TRUE AND viscosity_valid; E-stop clears debounce.
PUB004: PUMP_RUNTIME_ACC accumulates via CycleTime only when VFD_RUN=TRUE; retains.
PUB005: PUMP_MAINT_DUE at 500h; informational, non-interlocking.
PUB006: Power-up: VFD_RUN=FALSE, PUMP_RUNTIME_ACC=0, PUMP_MAINT_DUE=FALSE.
================================================================================
*)

// Debounce viscosity signal
// Start timer when viscosity good AND E-stop permits; reset on E-stop loss or viscosity drop
DebounceTimer(
    IN  := VISCOSITY_OK AND PASTE_E_STOP_NC,
    PT  := DebounceTime
);

// Pump runs only when E-stop is active AND viscosity has been continuously valid for DebounceTime
VFD_RUN := PASTE_E_STOP_NC AND DebounceTimer.Q;

// Accumulate runtime while pump is running
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + LTIME_TO_LTIME(CycleTime);
END_IF;

// Maintenance due indication at 500 hours (500 * 3600 * 1000 * 1000000 nanoseconds)
PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= T#500h) OR PUMP_MAINT_DUE;

END_FUNCTION_BLOCK