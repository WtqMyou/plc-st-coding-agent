(* Numeric millisecond variant of the jam-pump task. DebounceMs and CycleMs
   are in 1..3600000. No native TIME arithmetic is assumed. *)
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
    validMs : DINT;
END_VAR

IF VISCOSITY_OK AND PASTE_E_STOP_NC THEN
    validMs := validMs + CycleMs;
    (* Durations beyond the largest permitted threshold are indistinguishable. *)
    IF validMs > 3600000 THEN
        validMs := 3600000;
    END_IF;
ELSE
    validMs := 0;
END_IF;
VFD_RUN := VISCOSITY_OK AND PASTE_E_STOP_NC AND validMs >= DebounceMs;
IF VFD_RUN THEN
    PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleMs;
END_IF;
PUMP_MAINT_DUE := PUMP_RUNTIME_ACC >= 1800000000;
END_FUNCTION_BLOCK
