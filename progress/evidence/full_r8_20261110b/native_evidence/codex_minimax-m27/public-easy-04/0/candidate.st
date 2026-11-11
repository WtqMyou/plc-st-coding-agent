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
    valid_duration : DINT;
    prev_viscosity_ok : BOOL;
    prev_paste_e_stop_nc : BOOL;
    prev_vfd_run : BOOL;
END_VAR

    IF NOT (PASTE_E_STOP_NC AND VISCOSITY_OK) THEN
        VFD_RUN := FALSE;
        valid_duration := 0;
    ELSE
        IF NOT prev_viscosity_ok OR NOT prev_paste_e_stop_nc THEN
            valid_duration := CycleMs;
            VFD_RUN := (CycleMs >= DebounceMs);
        ELSE
            valid_duration := valid_duration + CycleMs;
            IF valid_duration >= DebounceMs THEN
                VFD_RUN := TRUE;
            END_IF
        END_IF
    END_IF

    IF VFD_RUN THEN
        PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleMs;
    END_IF

    PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= 1800000000);

    prev_viscosity_ok := VISCOSITY_OK;
    prev_paste_e_stop_nc := PASTE_E_STOP_NC;
    prev_vfd_run := VFD_RUN;
END_FUNCTION_BLOCK