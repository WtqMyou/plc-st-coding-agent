(*
ENGINEERING_CONTRACT
===================
PUB001: Jam transfer pump control - viscosity debouncing, E-stop, runtime, maintenance

Output States (Pub Clause IDs):
- VFD_RUN (PUB002, PUB003):
  - Activation: TRUE when PASTE_E_STOP_NC=TRUE AND viscosity_valid=TRUE (debounce complete)
  - Retention: Hold TRUE across scans while conditions remain valid
  - Explicit Reset: Immediate OFF when PASTE_E_STOP_NC=FALSE (PUB003), also OFF when viscosity invalidates
  - Same-scan Priority: Safety check (E-stop) evaluated first; viscosity check completes debounce timing

- PUMP_RUNTIME_ACC (PUB004):
  - Activation: Increments by CycleTime*1e6 (ms to ns) each scan when VFD_RUN=TRUE
  - Retention: Maintains value when VFD_RUN=FALSE (no decay, PUB004 preserved across stops)
  - Reset: Zero at power-up only (PUB006); no auto-reset during operation
  - Units: LTIME nanoseconds; 500 hours = 1.8e12 ns for comparison

- PUMP_MAINT_DUE (PUB005):
  - Activation: Set TRUE when PUMP_RUNTIME_ACC >= 500 hours (LTIME#500h in ns)
  - Retention: Hold TRUE once set (informational, PUB005 specifies no auto-reset requirement)
  - Reset: Not specified; no reset implemented
  - Units: LTIME nanoseconds, 500 hours = 500*3600*1e9 = 1.8e12 nanoseconds

Safety (PUB003):
- E-stop (PASTE_E_STOP_NC=FALSE) immediately disables VFD_RUN
- E-stop clears any incomplete debounce timing (TON disabled via IN=FALSE resets ET to 0)
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
    tmpLocalIN        : BOOL;
END_VAR

IF NOT PASTE_E_STOP_NC THEN
    tmpLocalIN := FALSE;
ELSIF VISCOSITY_OK THEN
    tmpLocalIN := TRUE;
ELSE
    tmpLocalIN := FALSE;
END_IF;

ViscosityDebounce(IN := tmpLocalIN, PT := DebounceTime);
tmpViscosityValid := ViscosityDebounce.Q;

IF PASTE_E_STOP_NC AND tmpViscosityValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime) * 1000000;
END_IF;

IF PUMP_RUNTIME_ACC >= TO_LTIME(T#500h) THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK