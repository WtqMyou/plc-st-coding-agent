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
    ViscosityValid         : BOOL := FALSE;
    ViscosityDebounceAccum : LTIME := LTIME#0s;
    DebounceTarget         : LTIME;
    CycleAsLTIME           : LTIME;
END_VAR
// ENGINEERING_CONTRACT
// | Output/State             | Activation                          | Retention            | Reset/Deactivation                      | Priority | Units/Boundaries |
// |--------------------------|-------------------------------------|----------------------|-----------------------------------------|----------|-------------------|
// | VFD_RUN                  | TRUE when safety permissive AND     | Retained while       | Cleared on E-Stop or viscosity invalid  | Safety   | Boolean permissive|
// |                          | viscosity valid (PUB003)            | conditions met       | (PUB003)                                | first    |                   |
// | PUMP_MAINT_DUE           | Set when runtime >= 500h (PUB004)   | Latched TRUE         | No reset (informational only, PUB004)   | None     | 500h threshold    |
// | PUMP_RUNTIME_ACC         | Increments by CycleTime when        | Preserved when       | Init to 0 at power-up only (PUB005)     | None     | LTIME nanoseconds |
// |                          | VFD_RUN = TRUE (PUB003)             | VFD_RUN = FALSE      |                                         |          | 0 to max          |
// | ViscosityValid           | After DebounceTime continuous TRUE  | Retained while       | Immediate on VISCOSITY_OK=FALSE or      | None     | Debounced state   |
// |                          | (PUB002)                            | VISCITY_OK=TRUE      | E-Stop (PUB002, PUB003)                 |          |                   |
// | ViscosityDebounceAccum   | Accumulates elapsed time when       | Reset to 0 when      | Reset on VISCOSITY_OK=FALSE or          | None     | LTIME nanoseconds |
// |                          | VISCOSITY_OK=TRUE (PUB002)          | VISCITY_OK=FALSE     | E-Stop (PUB003)                         |          | >= 0              |

DebounceTarget := TIME_TO_LTIME(DebounceTime);
CycleAsLTIME   := TIME_TO_LTIME(CycleTime);

// Emergency stop immediately clears run output and debounce state (PUB003)
IF NOT PASTE_E_STOP_NC THEN
    VFD_RUN := FALSE;
    ViscosityDebounceAccum := LTIME#0s;
    ViscosityValid := FALSE;
END_IF;

// Viscosity debouncing (PUB002): invalidate immediately on FALSE
IF NOT VISCOSITY_OK THEN
    ViscosityDebounceAccum := LTIME#0s;
    ViscosityValid := FALSE;
ELSE
    // Accumulate only when viscosity TRUE and not yet valid
    IF NOT ViscosityValid THEN
        ViscosityDebounceAccum := ViscosityDebounceAccum + CycleAsLTIME;
        IF ViscosityDebounceAccum >= DebounceTarget THEN
            ViscosityValid := TRUE;
        END_IF;
    END_IF;
END_IF;

// VFD_RUN permissive (PUB003)
IF PASTE_E_STOP_NC AND ViscosityValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

// Runtime accumulation (PUB003, PUB004)
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleAsLTIME;
END_IF;

IF PUMP_RUNTIME_ACC >= LTIME#500h THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;
END_FUNCTION_BLOCK