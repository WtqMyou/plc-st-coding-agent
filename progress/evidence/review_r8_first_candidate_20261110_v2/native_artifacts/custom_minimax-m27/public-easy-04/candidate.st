FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK      : BOOL;
    PASTE_E_STOP_NC   : BOOL;
    DebounceMs        : DINT;
    CycleMs           : DINT;
END_VAR
VAR_OUTPUT
    VFD_RUN           : BOOL := FALSE;
    PUMP_MAINT_DUE    : BOOL := FALSE;
    PUMP_RUNTIME_ACC  : LINT := 0;
END_VAR
VAR
    DebounceAccum     : DINT := 0;
END_VAR

// Debounce logic
IF VISCOSITY_OK AND PASTE_E_STOP_NC THEN
    DebounceAccum := DebounceAccum + CycleMs;
    VFD_RUN := (DebounceAccum >= DebounceMs);
ELSE
    DebounceAccum := 0;
    VFD_RUN := FALSE;
END_IF

// Runtime accumulation
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LINT(CycleMs);
END_IF

// Maintenance due indicator
PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= 1800000000);

END_FUNCTION_BLOCK