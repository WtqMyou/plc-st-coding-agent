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
    ViscosityDebounceTimer : TON;
    ViscosityDebounceAccum : LTIME := LTIME#0s;
    ViscosityValid         : BOOL := FALSE;
END_VAR
// ENGINEERING_CONTRACT
// | Output/State    | Activation         | Retention          | Reset/Deactivation                      | Priority | Units/Boundaries |
// |-----------------|--------------------|--------------------|-----------------------------------------|----------|-------------------|
// | VFD_RUN         | TRUE when safety   | Retained while     | Cleared on E-Stop or viscosity invalid  | Safety   | Boolean permissive|
// |                 | permissive AND     | conditions met     | (PUB003)                                | first    |                   |
// |                 | viscosity valid    |                    |                                         |          |                   |
// | PUMP_MAINT_DUE  | Set when runtime   | Latched TRUE       | No reset (informational only, PUB004)   | None     | 500h threshold    |
// |                 | >= 500h (PUB004)   |                    |                                         |          |                   |
// | PUMP_RUNTIME_ACC| Increments by      | Preserved when     | Init to 0 at power-up only (PUB005)     | None     | LTIME (nanoseconds)|
// |                 | CycleTime when     | VFD_RUN = FALSE    |                                         |          | 0 to max          |
// |                 | VFD_RUN = TRUE     | (PUB003)           |                                         |          |                   |
// |                 | (PUB003)          |                    |                                         |          |                   |
// | ViscosityValid  | After DebounceTime | Retained while     | Immediate on VISCITY_OK=FALSE or        | None     | Debounced state   |
// |                 | continuous TRUE    | VISCOSITY_OK=TRUE  | E-Stop (PUB002, PUB003)                 |          |                   |
// |                 | (PUB002)          | (PUB002)           |                                         |          |                   |
// | ViscosityDebounceAccum | Accumulates  | Reset to 0 when   | Reset on VISCOSITY_OK=FALSE or          | None     | LTIME nanoseconds |
// |                 | elapsed time when  | VISCOSITY_OK=FALSE | E-Stop (PUB003)                         |          | >= 0              |
// |                 | VISCOSITY_OK=TRUE  |                    |                                         |          |                   |

// Viscosity debouncing (PUB002)
IF NOT VISCOSITY_OK THEN
    ViscosityDebounceAccum := LTIME#0s;
    ViscosityValid := FALSE;
    ViscosityDebounceTimer(IN := FALSE);
ELSIF ViscosityValid THEN
    ViscosityDebounceTimer(IN := TRUE, PT := DebounceTime);
ELSE
    ViscosityDebounceAccum := ViscosityDebounceAccum + CycleTime;
    IF ViscosityDebounceAccum >= DebounceTime THEN
        ViscosityValid := TRUE;
    END_IF;
    ViscosityDebounceTimer(IN := FALSE);
END_IF;

// Safety permissive and run command (PUB003)
IF NOT PASTE_E_STOP_NC THEN
    VFD_RUN := FALSE;
    ViscosityDebounceAccum := LTIME#0s;
    ViscosityValid := FALSE;
END_IF;

IF PASTE_E_STOP_NC AND ViscosityValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

// Runtime accumulation (PUB003, PUB004)
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime;
END_IF;

IF PUMP_RUNTIME_ACC >= T#500h THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;
END_FUNCTION_BLOCK