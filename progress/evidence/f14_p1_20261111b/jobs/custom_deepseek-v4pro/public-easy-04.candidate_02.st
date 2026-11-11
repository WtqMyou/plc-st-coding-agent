FUNCTION_BLOCK FB_JamPump
VAR_INPUT
    VISCOSITY_OK      : BOOL;   // Raw viscosity signal
    PASTE_E_STOP_NC   : BOOL;   // Emergency stop (TRUE = permits operation)
    DebounceTime      : TIME;   // Required continuous valid duration (positive)
    CycleTime         : TIME;   // Actual elapsed time for this invocation (positive)
END_VAR
VAR_OUTPUT
    VFD_RUN           : BOOL;   // Pump run command
    PUMP_MAINT_DUE    : BOOL;   // Maintenance indication (latched at 500h)
    PUMP_RUNTIME_ACC  : LTIME;  // Accumulated enabled runtime
END_VAR
VAR
    DebounceTimer     : LTIME;  // Internal debounce elapsed time
    ViscosityValid    : BOOL;   // Debounced viscosity state
    FirstScan         : BOOL := TRUE;  // Power‑up initialization flag
    CycleTime_LTIME   : LTIME;  // CycleTime converted to LTIME
    DebounceTime_LTIME: LTIME;  // DebounceTime converted to LTIME
END_VAR

// ---------------------------------------------------------------------------
// Power‑up initialization
// ---------------------------------------------------------------------------
IF FirstScan THEN
    VFD_RUN          := FALSE;
    PUMP_RUNTIME_ACC := LTIME#0s;
    PUMP_MAINT_DUE   := FALSE;
    DebounceTimer    := LTIME#0s;
    ViscosityValid   := FALSE;
    FirstScan        := FALSE;
END_IF;

// Convert TIME inputs to LTIME for safe arithmetic and comparison
CycleTime_LTIME    := TIME_TO_LTIME(CycleTime);
DebounceTime_LTIME := TIME_TO_LTIME(DebounceTime);

// ---------------------------------------------------------------------------
// Viscosity debouncing
// ---------------------------------------------------------------------------
IF NOT VISCOSITY_OK THEN
    // Raw signal false → immediately invalidate and reset timer
    ViscosityValid := FALSE;
    DebounceTimer  := LTIME#0s;
ELSIF NOT ViscosityValid THEN
    // Debouncing phase: only accumulate if emergency stop is not active
    IF PASTE_E_STOP_NC THEN
        DebounceTimer := DebounceTimer + CycleTime_LTIME;
    ELSE
        // Emergency stop clears any incomplete debounce timing
        DebounceTimer := LTIME#0s;
    END_IF;

    // Check if the required continuous valid time has been reached
    IF DebounceTimer >= DebounceTime_LTIME THEN
        ViscosityValid := TRUE;
        DebounceTimer  := DebounceTime_LTIME;  // Clamp to avoid overflow
    END_IF;
END_IF;

// ---------------------------------------------------------------------------
// Run output logic (safety permissive)
// ---------------------------------------------------------------------------
IF PASTE_E_STOP_NC AND ViscosityValid THEN
    VFD_RUN := TRUE;
ELSE
    VFD_RUN := FALSE;
END_IF;

// ---------------------------------------------------------------------------
// Runtime accumulation (only while pump is running)
// ---------------------------------------------------------------------------
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime_LTIME;
END_IF;

// ---------------------------------------------------------------------------
// Maintenance due indication (latched, informational only)
// ---------------------------------------------------------------------------
IF NOT PUMP_MAINT_DUE AND (PUMP_RUNTIME_ACC >= LTIME#500h) THEN
    PUMP_MAINT_DUE := TRUE;
END_IF;

END_FUNCTION_BLOCK