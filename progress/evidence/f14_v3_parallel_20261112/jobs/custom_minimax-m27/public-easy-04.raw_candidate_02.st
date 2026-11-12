FUNCTION_BLOCK JamPumpControl
VAR
    ViscosityValid : BOOL := FALSE;
    DebounceAccum  : LTIME  := LTIME#0s;
    PrevViscosity  : BOOL := FALSE;
END_VAR
VAR_OUTPUT
    VFD_RUN          : BOOL := FALSE;
    PUMP_MAINT_DUE   : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME  := LTIME#0s;
END_VAR
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR
    // Emergency stop priority: immediate disable and clear debounce state
    IF NOT PASTE_E_STOP_NC THEN
        VFD_RUN        := FALSE;
        ViscosityValid := FALSE;
        DebounceAccum  := LTIME#0s;
        PrevViscosity  := FALSE;
        RETURN;
    END_IF;

    // Viscosity debouncing
    IF NOT VISCOSITY_OK THEN
        ViscosityValid := FALSE;
        DebounceAccum  := LTIME#0s;
        PrevViscosity  := FALSE;
    ELSE
        IF NOT PrevViscosity THEN
            DebounceAccum := LTIME#0s;
        END_IF;

        DebounceAccum := DebounceAccum + TO_LTIME(TO_ULINT(CycleTime));

        IF DebounceAccum >= TO_LTIME(TO_ULINT(DebounceTime)) THEN
            ViscosityValid := TRUE;
        END_IF;

        PrevViscosity := TRUE;
    END_IF;

    // Run permissive
    IF PASTE_E_STOP_NC AND ViscosityValid AND VISCOSITY_OK THEN
        VFD_RUN := TRUE;
    ELSE
        VFD_RUN := FALSE;
    END_IF;

    // Accumulate runtime only while pump is running
    IF VFD_RUN THEN
        PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(TO_ULINT(CycleTime));
    END_IF;

    // Maintenance indication at 500 hours
    IF PUMP_RUNTIME_ACC >= LTIME#500h THEN
        PUMP_MAINT_DUE := TRUE;
    END_IF;

END_FUNCTION_BLOCK