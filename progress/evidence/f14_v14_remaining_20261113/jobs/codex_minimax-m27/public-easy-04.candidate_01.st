FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR

VAR_OUTPUT
    VFD_RUN          : BOOL := FALSE;
    PUMP_MAINT_DUE   : BOOL := FALSE;
    PUMP_RUNTIME_ACC : LTIME := LTIME#0s;
END_VAR

VAR
    viscosityTimer : TON;
    viscosityValid : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
 * =============================================================================
 * Output: VFD_RUN
 *   - Activation:   PASTE_E_STOP_NC = TRUE AND viscosityValid = TRUE (PUB001, PUB002)
 *   - Retention:    Held TRUE while both permissive conditions remain TRUE
 *   - Reset:        Immediate on PASTE_E_STOP_NC = FALSE (E-stop) OR viscosityValid = FALSE
 *   - Same-scan:    E-stop has highest priority; cleared first scan of E-stop event
 *   - Units:        Boolean command, no time units
 * ----------------------------------------------------------------------------
 * Output: PUMP_RUNTIME_ACC
 *   - Activation:   VFD_RUN = TRUE (PUB003)
 *   - Retention:    Preserved while VFD_RUN = FALSE; never cleared by E-stop
 *   - Reset:        None (informational only)
 *   - Same-scan:    Accumulates once per invocation using CycleTime value
 *   - Units:        LTIME nanoseconds; 500h = 1,800,000,000,000 ns (PUB004)
 * ----------------------------------------------------------------------------
 * Output: PUMP_MAINT_DUE
 *   - Activation:   PUMP_RUNTIME_ACC >= 500 hours (PUB004)
 *   - Retention:    Held TRUE once threshold reached (no explicit reset required)
 *   - Reset:        None stated; informational only
 *   - Same-scan:    Evaluated every invocation
 *   - Units:        Boolean indication, does not affect VFD_RUN or safety permissive
 * ----------------------------------------------------------------------------
 * Internal: viscosityValid
 *   - Activation:   VISCOSITY_OK = TRUE continuously for DebounceTime (PUB001)
 *   - Retention:    Held TRUE while VISCOSITY_OK remains TRUE
 *   - Reset:        Immediate on VISCOSITY_OK = FALSE OR PASTE_E_STOP_NC = FALSE (PUB002)
 *   - Same-scan:    Timer PT uses DebounceTime; TON.Q is elapsed >= PT
 *   - Units:        TIME (DebounceTime); TON.ET saturates at PT
 * =============================================================================
 *)
(* CONTRACT_RULES [] *)

    // E-stop immediately clears VFD_RUN and any incomplete debounce state
    IF NOT PASTE_E_STOP_NC THEN
        viscosityValid := FALSE;
        viscosityTimer(IN := FALSE);
        VFD_RUN := FALSE;
    ELSE
        // VISCOSITY_OK must be TRUE for DebounceTime before considered valid
        IF VISCOSITY_OK THEN
            viscosityTimer(IN := TRUE, PT := DebounceTime);
            viscosityValid := viscosityTimer.Q;
        ELSE
            // Immediately invalidate when input becomes FALSE
            viscosityTimer(IN := FALSE);
            viscosityValid := FALSE;
        END_IF;

        // VFD_RUN permitted only when E-stop is safe and viscosity condition is valid
        VFD_RUN := viscosityValid;
    END_IF;

    // Accumulate runtime while VFD_RUN is TRUE
    IF VFD_RUN THEN
        PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + TO_LTIME(CycleTime);
    END_IF;

    // Set maintenance indication when threshold reached (informational only)
    IF PUMP_RUNTIME_ACC >= LTIME#500h THEN
        PUMP_MAINT_DUE := TRUE;
    END_IF;

END_FUNCTION_BLOCK