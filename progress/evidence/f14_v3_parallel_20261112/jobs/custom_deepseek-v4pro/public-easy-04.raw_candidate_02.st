FUNCTION_BLOCK FB_JamPumpControl
VAR_INPUT
    VISCOSITY_OK : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime : TIME;
    CycleTime : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN : BOOL := FALSE;
    PUMP_MAINT_DUE : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0s;
END_VAR
VAR
    ViscosityConditionValid : BOOL := FALSE;
    DebounceElapsed : TIME := T#0s;
    RuntimeAccumulator : LTIME := LTIME#0s;
    MaintenanceThreshold : LTIME := LTIME#500h;
    LastVFD_RUN : BOOL := FALSE;
END_VAR

// Debounce viscosity signal
IF NOT VISCOSITY_OK THEN
    ViscosityConditionValid := FALSE;
    DebounceElapsed := T#0s;
ELSE
    IF NOT PASTE_E_STOP_NC THEN
        // E-stop clears incomplete debounce, but keeps already valid condition
        DebounceElapsed := T#0s;
    ELSIF NOT ViscosityConditionValid THEN
        DebounceElapsed := DebounceElapsed + CycleTime;
        IF DebounceElapsed >= DebounceTime THEN
            ViscosityConditionValid := TRUE;
        END_IF;
    END_IF;
END_IF;

// VFD run permissive
VFD_RUN := PASTE_E_STOP_NC AND ViscosityConditionValid;

// Accumulate runtime, skipping the first scan after pump start
IF VFD_RUN AND NOT LastVFD_RUN THEN
    // Rising edge, do not accumulate this cycle
ELSIF VFD_RUN THEN
    RuntimeAccumulator := RuntimeAccumulator + TO_LTIME(CycleTime);
END_IF;

LastVFD_RUN := VFD_RUN;

PUMP_RUNTIME_ACC := RuntimeAccumulator;
PUMP_MAINT_DUE := RuntimeAccumulator >= MaintenanceThreshold;

END_FUNCTION_BLOCK