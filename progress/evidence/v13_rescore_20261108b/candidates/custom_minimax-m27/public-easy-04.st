FUNCTION_BLOCK FB
VAR_INPUT
    VISCOSITY_OK      : BOOL;
    PASTE_E_STOP_NC   : BOOL;
    DebounceTime      : TIME;
    CycleTime         : TIME;
END_VAR

VAR_OUTPUT
    VFD_RUN           : BOOL;
    PUMP_MAINT_DUE    : BOOL;
    PUMP_RUNTIME_ACC  : LINT;
END_VAR

VAR
    debounceTimer : TON;
    firstScan     : BOOL := TRUE;
END_VAR

// Power‑up initialisation
IF firstScan THEN
    VFD_RUN          := FALSE;
    PUMP_RUNTIME_ACC := 0;
    PUMP_MAINT_DUE   := FALSE;
    debounceTimer(IN := FALSE, PT := DebounceTime);
    firstScan := FALSE;
ELSE
    // Debounce the viscosity signal – timer resets when ESTOP opens
    debounceTimer(IN := VISCOSITY_OK AND PASTE_E_STOP_NC, PT := DebounceTime);

    // Run command requires ESTOP closed and viscosity condition validated
    VFD_RUN := PASTE_E_STOP_NC AND debounceTimer.Q;

    // Accumulate runtime while the pump is actually running
    IF VFD_RUN THEN
        PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime; // TIME converts to ms
    END_IF;

    // Maintenance due after 500 h (500 h = 500·3600·1000 ms)
    PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= LINT#500 * 3600 * 1000);
END_IF

END_FUNCTION_BLOCK