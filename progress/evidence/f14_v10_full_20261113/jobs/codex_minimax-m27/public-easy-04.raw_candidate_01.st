(* ENGINEERING_CONTRACT
+------------------------------------------------------------------+
| Output/State  | Activation | Retention | Reset/Deactivation      |
+------------------------------------------------------------------+
| VFD_RUN       | TRUE when EStop=TRUE AND ViscosityValid=TRUE     |  PUB002
|               | (same-scan priority; no edge trigger)            |
+------------------------------------------------------------------+
| VFD_RUN       | Deactivates immediately when PASTE_E_STOP_NC=FALSE| PUB002
|               | or when ViscosityValid transitions to FALSE      |
+------------------------------------------------------------------+
| ViscosityValid| TRUE after VISCOSITY_OK held TRUE >= DebounceTime | PUB001
|               | Invalidated immediately when VISCOSITY_OK=FALSE  |
+------------------------------------------------------------------+
| ViscosityDebounce (TON) | Cleared on E-Stop or Viscosity=FALSE   | PUB002
+------------------------------------------------------------------+
| PUMP_RUNTIME_ACC | Accumulates LTIME += CycleTime while VFD_RUN   | PUB003
|                  | Retained when VFD_RUN=FALSE                   |
+------------------------------------------------------------------+
| PUMP_MAINT_DUE   | Set when PUMP_RUNTIME_ACC >= 500 hours         | PUB004
|                  | Informational only; no effect on VFD_RUN      |
+------------------------------------------------------------------+
| All outputs     | Initialize to FALSE/zero at power-up          | PUB005
+------------------------------------------------------------------+
Time boundary: 500 hours = 1,800,000,000 ms = 1,800,000,000,000 ns  PUB004
TON.Q: elapsed >= PT; first satisfying tick at ceil(DebounceTime/1ms) PUB001
CycleTime quantum: 1 ms; accumulated via LTIME nanoseconds           PUB003
+------------------------------------------------------------------+
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
    ViscosityValid  : BOOL := FALSE;
    ViscosityDebounce : TON;
    FirstScan       : BOOL := TRUE;
    tmpCycleNs      : LINT;
END_VAR

// Power-up initialization
IF FirstScan THEN
    VFD_RUN          := FALSE;
    PUMP_MAINT_DUE   := FALSE;
    PUMP_RUNTIME_ACC := LTIME#0s;
    FirstScan        := FALSE;
END_IF;

// Debounce state machine
ViscosityDebounce(IN  := VISCOSITY_OK AND PASTE_E_STOP_NC,
                  PT  := DebounceTime);

IF NOT VISCOSITY_OK THEN
    ViscosityValid := FALSE;
ELSIF ViscosityDebounce.Q THEN
    ViscosityValid := TRUE;
END_IF;

// VFD_RUN permissive: E-Stop OK AND viscosity condition valid
VFD_RUN := PASTE_E_STOP_NC AND ViscosityValid;

// Runtime accumulation while pump is running
IF VFD_RUN THEN
    tmpCycleNs := TO_LINT(CycleTime) * 1000000;
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(tmpCycleNs);
END_IF;

// Maintenance due at 500 hours
PUMP_MAINT_DUE := PUMP_RUNTIME_ACC >= LTIME#500h;

END_FUNCTION_BLOCK