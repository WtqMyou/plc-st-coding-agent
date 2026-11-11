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
    valid_duration : LINT := 0;
END_VAR

IF PASTE_E_STOP_NC AND VISCOSITY_OK THEN
    valid_duration := valid_duration + CycleMs;
ELSE
    valid_duration := 0;
END_IF

VFD_RUN := (PASTE_E_STOP_NC AND VISCOSITY_OK) AND (valid_duration >= DebounceMs);

IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleMs;
END_IF

PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= 1800000000);

END_FUNCTION_BLOCK