(* -------------------------------------------------------------
   Jam Pump Debouncing and Runtime Maintenance
   -------------------------------------------------------------
   Inputs
      VISCOSITY_OK    : Raw viscosity‑OK signal (TRUE = within range)
      PASTE_E_STOP_NC : Emergency‑stop circuit, normally closed
      DebounceTime    : Required ON‑time for the viscosity signal
      CycleTime       : Actual invocation interval (must be >0)

   Outputs
      VFD_RUN         : VFD run command (TRUE = allowed)
      PUMP_MAINT_DUE  : Maintenance‑due flag (TRUE after 500 h run)
      PUMP_RUNTIME_ACC: Accumulated run time (LTIME)

   Internal variables
      viscosity_valid : Viscosity condition accepted after debounce
      DebounceTimer   : TON used for debouncing
      prevEStop       : Previous state of PASTE_E_STOP_NC (edge detection)
      init            : Power‑up initialisation flag
   ------------------------------------------------------------- *)
FUNCTION_BLOCK JamPumpControl
VAR_INPUT
    VISCOSITY_OK    : BOOL;
    PASTE_E_STOP_NC : BOOL;
    DebounceTime    : TIME;
    CycleTime       : TIME;
END_VAR
VAR_OUTPUT
    VFD_RUN         : BOOL;
    PUMP_MAINT_DUE  : BOOL;
    PUMP_RUNTIME_ACC: LTIME;
END_VAR
VAR
    viscosity_valid : BOOL := FALSE;
    DebounceTimer   : TON;
    prevEStop       : BOOL := TRUE;   // assume not in emergency stop at start‑up
    init            : BOOL := TRUE;   // power‑up initialization flag
END_VAR

// -------------------------------------------------------------------
// Power‑up initialisation
// -------------------------------------------------------------------
IF init THEN
    VFD_RUN          := FALSE;            // run output OFF
    PUMP_RUNTIME_ACC := LTIME#0h;        // accumulated time = 0
    PUMP_MAINT_DUE   := FALSE;           // maintenance flag cleared
    viscosity_valid  := FALSE;           // no valid viscosity yet
    DebounceTimer(IN := FALSE, PT := DebounceTime); // timer reset
    // Initialise previous E‑Stop state to current value so that a
    // spurious falling‑edge is not generated on the first scan.
    prevEStop := PASTE_E_STOP_NC;
    init := FALSE;

// -------------------------------------------------------------------
// Normal (cyclic) processing
// -------------------------------------------------------------------
ELSE

    // ---- Emergency‑stop edge detection --------------------------------
    // If the emergency‑stop circuit opens (falling edge) the viscosity
    // permissive must be cleared and any in‑progress debounce aborted.
    IF (NOT PASTE_E_STOP_NC) AND prevEStop THEN
        viscosity_valid      := FALSE;
        DebounceTimer(IN := FALSE);   // abort timer
    END_IF
    prevEStop := PASTE_E_STOP_NC;

    // ---- Viscosity signal – immediate invalidation --------------------
    IF NOT VISCOSITY_OK THEN
        viscosity_valid := FALSE;   // loss of signal → invalid immediately
    END_IF

    // ---- Debounce timer ------------------------------------------------
    // Start timing only when:
    //   • raw signal is TRUE,
    //   • we do not yet have a valid reading,
    //   • emergency‑stop circuit is closed.
    DebounceTimer(
        IN := VISCOSITY_OK AND NOT viscosity_valid AND PASTE_E_STOP_NC,
        PT := DebounceTime
    );
    DebounceTimer();   // execute the TON block

    // When the timer finishes, the viscosity condition becomes valid.
    IF DebounceTimer.Q THEN
        viscosity_valid := TRUE;
    END_IF

    // ---- Run permissive ------------------------------------------------
    // VFD may run only when the emergency‑stop is closed AND the
    // viscosity condition has been accepted after debounce.
    VFD_RUN := PASTE_E_STOP_NC AND viscosity_valid;

    // ---- Runtime accumulation -----------------------------------------
    // Accumulate time only while the pump is actually running.
    // TIME values implicitly convert to LTIME in expressions.
    IF VFD_RUN THEN
        PUMP_RUNTIME_ACC := PUMP_RUNTIME_ACC + CycleTime;
    END_IF

    // ---- Maintenance‑due indication ------------------------------------
    // Informational flag – does not affect safety or operation.
    PUMP_MAINT_DUE := (PUMP_RUNTIME_ACC >= LTIME#500h);

END_IF

END_FUNCTION_BLOCK