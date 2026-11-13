FUNCTION_BLOCK WeldGapAlarm
(* ENGINEERING_CONTRACT
   =================================================================
   States & Retention (outputs per PUB001-PUB006):
   -----------------------------------------------------------------
   State: POWER_UP_INHIBIT (5s after power-up, no E-stop)
   - Weld_Soft_Start_Active := TRUE (activation: power-up entry)
   - Operator_Alert := FALSE (held, no alarm during inhibit)
   - Gap debounce does NOT accumulate (timer gated OFF)
   - Retention: held until 5s elapsed OR E-stop asserted
   -----------------------------------------------------------------
   State: NORMAL_MONITORING (after 5s inhibit, no E-stop)
   - Weld_Soft_Start_Active := FALSE (deactivated, no reset input)
   - Operator_Alert := TRUE only when DebounceTimer.Q = TRUE
     (activation: Gap_Exceeded TRUE for DebounceTime; retention:
      held until Gap_Exceeded FALSE OR E-stop asserted)
   - DebounceTimer enabled when Gap_Exceeded = TRUE; cleared when
     Gap_Exceeded = FALSE; no same-scan priority issue (TON called
     once with final enable state)
   - Reset: E-stop immediate reset, then return to POWER_UP_INHIBIT
   -----------------------------------------------------------------
   E-STOP PRIORITY (Weld_E_Stop_NC = FALSE):
   - Operator_Alert immediately FALSE (explicit reset per PUB004)
   - Incomplete debounce timing cleared (TON.ET reset via re-call
     with IN=FALSE when E-stop detected)
   - Weld_Soft_Start_Active := FALSE (inhibition cancelled)
   - Same-scan: evaluated before state logic; no race condition
   -----------------------------------------------------------------
   Units/Boundaries:
   - Power-up inhibit: 5s (T#5s), LTIME resolution
   - DebounceTime: caller-supplied TIME, must be positive (PUB003)
   - TON.Q activates at ET >= PT; ET saturates at PT
   - Direction conflicts: not applicable (no axis outputs)
   =================================================================
*)
VAR
    // Power-up initialization timer: 5-second inhibit period
    PowerUpTimer: TON;
    // Gap signal debounce timer during normal monitoring
    DebounceTimer: TON;
END_VAR

// E-STOP PRIORITY: Immediate deactivation per PUB004
// Evaluated first to ensure same-scan priority over state transitions
IF NOT Weld_E_Stop_NC THEN
    // Operator_Alert immediately FALSE
    Operator_Alert := FALSE;
    // Clear any incomplete debounce timing (re-call with IN=FALSE clears ET)
    DebounceTimer(IN := FALSE, PT := DebounceTime);
    // Cancel power-up inhibition (soft start no longer valid)
    Weld_Soft_Start_Active := FALSE;
    // Restart power-up timer on next rising edge of E-stop release
    PowerUpTimer(IN := FALSE, PT := T#5s);
ELSE
    // E-stop inactive (Weld_E_Stop_NC = TRUE): normal/state logic
    
    // Power-up timer: runs for 5s, gated by E-stop (already TRUE here)
    PowerUpTimer(IN := NOT PowerUpTimer.Q, PT := T#5s);
    
    // Determine current operating phase
    IF NOT PowerUpTimer.Q THEN
        // POWER_UP_INHIBIT state: 5-second initialization period
        // PUB001: Operator_Alert = FALSE during inhibit
        Operator_Alert := FALSE;
        // PUB002: Weld_Soft_Start_Active = TRUE during inhibit
        Weld_Soft_Start_Active := TRUE;
        // PUB003: Gap debounce time does NOT accumulate during inhibit
        // Timer not called, so no timing accumulation
    ELSE
        // NORMAL_MONITORING state: after 5-second inhibit completes
        // PUB002: Weld_Soft_Start_Active = FALSE after inhibit
        Weld_Soft_Start_Active := FALSE;
        
        // Debounce logic: accumulate time only when Gap_Exceeded = TRUE
        // When Gap_Exceeded = FALSE, timer resets (IN=FALSE clears ET)
        DebounceTimer(
            IN := Gap_Exceeded,
            PT := DebounceTime
        );
        
        // Operator_Alert activated after debounce completes (PUB003)
        // Retention: remains TRUE until Gap_Exceeded FALSE OR E-stop
        Operator_Alert := DebounceTimer.Q;
    END_IF;
END_IF;
END_FUNCTION_BLOCK