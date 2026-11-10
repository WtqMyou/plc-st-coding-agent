FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceMs : DINT;
    CycleMs : DINT;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL;
    PUMP_MAINT_DUE : BOOL;
    PUMP_RUNTIME_ACC : LINT;
END_VAR
VAR
    valid_duration : LINT;
END_VAR

IF PASTE_E_STOP_NC AND VISCOSITY_OK THEN
    valid_duration := valid_duration + DINT_TO_LINT(CycleMs);
    IF valid_duration >= DINT_TO_LINT(DebounceMs) THEN
        VFD_RUN := TRUE;
    ELSE
        VFD_RUN := FALSE;
    END_IF
ELSE
    valid_duration := 0;
    VFD_RUN := FALSE;
END_IF

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + DINT_TO_LINT(CycleMs);
END_IF

IF PUMP_RUNTIME_ACC >= 1800000000 THEN
    PUMP_MAINT_DUE := TRUE;
ELSE
    PUMP_MAINT_DUE := FALSE;
END_IF

END_FUNCTION_BLOCK