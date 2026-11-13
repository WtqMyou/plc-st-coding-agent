(* ENGINEERING_CONTRACT:
1. VFD_RUN: Activation=debounced_viscosity AND PASTE_E_STOP_NC; Retention=held continuously while both inputs valid; Reset=immediate on E_STOP_NC=FALSE or viscosity invalid; Same-scan priority=evaluate after debounce state is finalized.
2. Viscosity debounce (TON): Activation=starts when VISCOSITY_OK=TRUE; Condition=VISCOSITY_OK must remain TRUE for DebounceTime; Reset=immediately when VISCOSITY_OK=FALSE or E_STOP_NC=FALSE (clears incomplete timing).
3. PUMP_RUNTIME_ACC: Activation=accumulates CycleTime each scan when VFD_RUN=TRUE; Retention=preserved when VFD_RUN=FALSE; Reset=none except power-up to 0 LTIME; Units=LTIME nanoseconds.
4. PUMP_MAINT_DUE: Activation=acc >= 500 hours (1,800,000,000 ms as LTIME); Retention=latched TRUE until power cycle; Reset=power cycle only; No effect on VFD_RUN or safety permissive.
5. Power-up: VFD_RUN=FALSE, PUMP_RUNTIME_ACC=0 LTIME, PUMP_MAINT_DUE=FALSE.
*)

(* CONTRACT_RULES: [{"kind": "hold_until_reset", "output": "PUMP_MAINT_DUE", "set_input": null, "reset_input": null}] *)

FUNCTION_BLOCK JamPumpControl
VAR_OUTPUT
    VFD_RUN            : BOOL  := FALSE;
    PUMP_MAINT_DUE     : BOOL  := FALSE;
    PUMP_RUNTIME_ACC   : LTIME := LTIME#0s;
END_VAR
VAR_INPUT
    VISCOSITY_OK       : BOOL;
    PASTE_E_STOP_NC    : BOOL;
    DebounceTime       : TIME;
    CycleTime          : TIME;
END_VAR
VAR
    tmp_debounce_ok    : BOOL := FALSE;
    debounce_timer     : TON;
END_VAR

    // Clear debounce timer immediately when emergency stop is released
    IF NOT PASTE_E_STOP_NC THEN
        debounce_timer(IN := FALSE, PT := DebounceTime);
        tmp_debounce_ok := FALSE;
    ELSE
        // Invalidate debounce immediately when viscosity signal drops
        IF NOT VISCOSITY_OK THEN
            debounce_timer(IN := FALSE, PT := DebounceTime);
            tmp_debounce_ok := FALSE;
        ELSE
            // Start or continue debounce timing while viscosity is valid
            debounce_timer(IN := TRUE, PT := DebounceTime);
            tmp_debounce_ok := debounce_timer.Q;
        END_IF;
    END_IF;

    // Set maintenance flag when runtime reaches 500 hours (latching)
    IF PUMP_RUNTIME_ACC >= LTIME#500h THEN
        PUMP_MAINT_DUE := TRUE;
    END_IF;

    // VFD run command: requires valid debounced viscosity AND no emergency stop
    VFD_RUN := tmp_debounce_ok AND PASTE_E_STOP_NC;

    // Accumulate runtime only while pump is running
    IF VFD_RUN THEN
        PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime);
    END_IF;

END_FUNCTION_BLOCK