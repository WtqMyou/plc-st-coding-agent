(*
ENGINEERING_CONTRACT
===================
PUB001: Jam transfer pump control - viscosity debouncing, E-stop, runtime, maintenance

Output States:
- VFD_RUN:
  - Activation: TRUE when PASTE_E_STOP_NC=TRUE AND viscosity_valid=TRUE
  - Retention: Hold TRUE across scans while conditions remain valid
  - Explicit Reset: Immediate OFF on PASTE_E_STOP_NC=FALSE
  - Same-scan Priority: Evaluated after safety check (E-stop wins)

- PUMP_RUNTIME_ACC:
  - Activation: Increments by CycleTime each scan when VFD_RUN=TRUE
  - Retention: Maintains value when VFD_RUN=FALSE (no decay)
  - Reset: Zero at power-up only (PUB006)
  - Units: LTIME (nanoseconds)

- PUMP_MAINT_DUE:
  - Activation: Set TRUE when PUMP_RUNTIME_ACC >= 500 hours
  - Retention: Hold TRUE once set (informational, PUB005)
  - Reset: Not specified (no auto-reset)
  - Units: LTIME comparison vs 500*3600*1e9 nanoseconds

Safety:
- E-stop (PASTE_E_STOP_NC=FALSE) immediately disables VFD_RUN
- E-stop clears any incomplete debounce timing (TON disabled resets)
- Maintenance indication does not affect pump operation or safety (PUB005)
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
    tmpViscosityValid : BOOL;
END_VAR

// Single TON call per scan with correct input determined by E-stop
IF NOT PASTE_E_STOP_NC THEN
    ViscosityDebounce(IN := FALSE, PT := DebounceTime);
ELSE
    ViscosityDebounce(IN := VISCOSITY_OK, PT := DebounceTime);
END_IF;

tmpViscosityValid := ViscosityDebounce.Q;

IF NOT PASTE_E_STOP_NC THEN
    VFD_RUN := FALSE;
ELSE
    VFD_RUN := tmpViscosityValid;
END_IF;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime);
END_IF;

IF PUMP_RUNTIME_ACC >= T#500h THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK