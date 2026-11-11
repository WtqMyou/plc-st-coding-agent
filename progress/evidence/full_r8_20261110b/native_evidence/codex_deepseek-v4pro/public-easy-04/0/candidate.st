FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK     : BOOL;
    PASTE_E_STOP_NC  : BOOL;
    DebounceMs       : DINT;
    CycleMs          : DINT;
END_VAR
VAR_OUTPUT
    VFD_RUN          : BOOL;
    PUMP_MAINT_DUE   : BOOL;
    PUMP_RUNTIME_ACC : LINT;
END_VAR
VAR
    validDuration    : LINT := 0;
    runtimeAccum     : LINT := 0;
END_VAR

IF VISCOSITY_OK AND PASTE_E_STOP_NC THEN
    validDuration := validDuration + DINT_TO_LINT(CycleMs);
    VFD_RUN := validDuration >= DINT_TO_LINT(DebounceMs);
ELSE
    validDuration := 0;
    VFD_RUN := FALSE;
END_IF;

IF VFD_RUN THEN
    runtimeAccum := runtimeAccum + DINT_TO_LINT(CycleMs);
END_IF;

PUMP_RUNTIME_ACC := runtimeAccum;
PUMP_MAINT_DUE := runtimeAccum >= LINT#1800000000;

END_FUNCTION_BLOCK