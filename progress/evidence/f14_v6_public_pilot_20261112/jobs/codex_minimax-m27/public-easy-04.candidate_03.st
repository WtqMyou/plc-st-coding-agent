(*
ENGINEERING_CONTRACT
===================
PUB001: Jam transfer pump control - viscosity debouncing, E-stop, runtime, maintenance

Output States:
- VFD_RUN:
  - Activation: TRUE when PASTE_E_STOP_NC=TRUE AND viscosity_valid=TRUE (TON.Q)
  - Retention: Hold TRUE across scans while conditions remain valid
  - Explicit Reset: Immediate OFF on PASTE_E_STOP_NC=FALSE (PUB003)
  - Same-scan Priority: E-stop disables first, then viscosity checked
  - Units: Boolean permissive

- PUMP_RUNTIME_ACC:
  - Activation: Increment by CycleTime each scan when VFD_RUN=TRUE (PUB004)
  - Retention: Maintains value when VFD_RUN=FALSE (no decay)
  - Reset: Zero at power-up only (PUB006)
  - Units: LTIME nanoseconds

- PUMP_MAINT_DUE:
  - Activation: Set TRUE when PUMP_RUNTIME_ACC >= 500 hours (PUB005)
  - Retention: Hold TRUE once set (informational, no auto-reset per PUB005)
  - Reset: Not specified
  - Units: LTIME comparison

Safety:
- E-stop (PASTE_E_STOP_NC=FALSE) immediately disables VFD_RUN (PUB003)
- E-stop clears debounce by disabling TON (PUB003)
- Maintenance has no effect on operation or safety (PUB005)
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR

VAR_OUTPUT
    VFD_RUN         : BOOL;
    PUMP_MAINT_DUE  : BOOL;
    PUMP_RUNTIME_ACC: LTIME;
END_VAR

VAR
    ViscosityDebounce : TON;
END_VAR

ViscosityDebounce(
    IN  := PASTE_E_STOP_NC AND VISCOSITY_OK,
    PT  := DebounceTime
);

VFD_RUN := PASTE_E_STOP_NC AND ViscosityDebounce.Q;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime);
END_IF;

IF PUMP_RUNTIME_ACC >= T#500h THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK