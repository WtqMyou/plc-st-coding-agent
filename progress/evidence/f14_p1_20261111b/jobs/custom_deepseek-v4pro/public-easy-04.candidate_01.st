// Convert TIME inputs to LTIME for accumulation and comparison
CycleTime_LTIME := TIME_TO_LTIME(CycleTime);
DebounceTime_LTIME := TIME_TO_LTIME(DebounceTime);

// Viscosity debouncing
IF NOT VISCOSITY_OK THEN
    // Invalidate immediately on false
    ViscosityValid := FALSE;
    DebounceTimer := LTIME#0s;
ELSIF NOT ViscosityValid THEN
    // Only accumulate debounce time when emergency stop is not active
    IF PASTE_E_STOP_NC THEN
        DebounceTimer := DebounceTimer + CycleTime_LTIME;
    ELSE
        // Emergency stop clears any incomplete debounce timing
        DebounceTimer := LTIME#0s;
    END_IF;

    // Check if debounce time has been reached
    IF DebounceTimer >= DebounceTime_LTIME THEN
        ViscosityValid := TRUE;
        DebounceTimer := DebounceTime_LTIME; // Clamp to avoid overflow
    END_IF;
END_IF;

// Emergency stop priority: run output only when e-stop closed and viscosity valid
IF PASTE_E_STOP_NC AND ViscosityValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

// Accumulate runtime only while pump is running
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime_LTIME;
END_IF;

// Maintenance due latching at 500 hours
IF NOT PUMP_MAINT_DUE AND (PUMP_RUNTIME_ACC >= LTIME#500h) THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;