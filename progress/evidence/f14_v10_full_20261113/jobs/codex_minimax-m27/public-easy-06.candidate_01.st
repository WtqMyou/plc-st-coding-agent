(* ENGINEERING_CONTRACT
 * ============================================================
 * PUB001 (81-237): Start delay timing
 *   - Activation: Start TON when DO_LOW AND AERATION_E_STOP_NC both TRUE
 *   - Timer PT: 5 seconds (LTIME, T#5s)
 *   - BLOWER_RUN := TON.Q when timer elapsed
 *   - Retention: BLOWER_RUN held TRUE while conditions remain; no autonomous off
 *
 * PUB002 (239-409): Immediate disable and timer reset
 *   - Deactivation: If DO_LOW = FALSE OR AERATION_E_STOP_NC = FALSE
 *   - BLOWER_RUN := FALSE immediately
 *   - Timer reset (TON.TP.IN := FALSE, TON.ET := 0)
 *   - Must re-wait full 5 seconds on next demand
 *
 * PUB003 (410-614): Cycle count on rising edge
 *   - Set input: BLOWER_RUN rising edge (FALSE->TRUE)
 *   - Increment AERATION_BLOWER_CYCLE_COUNT by 1
 *   - No count during continuous TRUE
 *
 * PUB004 (615-761): Power-up initialization
 *   - BLOWER_RUN := FALSE
 *   - AERATION_BLOWER_CYCLE_COUNT := 0
 *   - Timer state cleared
 *
 * PUB005 (762-910): BOOL enable gate, no speed ramp
 *   - BLOWER_RUN is a simple BOOL command
 *   - No ramp, no intermediate states
 * ============================================================
 *)

(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"BLOWER_RUN","set_input":"internal_timer_done","reset_input":"DO_LOW_OR_ESTOP"}] *)

FUNCTION_BLOCK AerationBlowerDelayedStart
VAR_OUTPUT
    BLOWER_RUN                  : BOOL := FALSE;
    AERATION_BLOWER_CYCLE_COUNT : UINT := 0;
END_VAR
VAR
    StartDelayTimer             : TON;
    BlowerStartRTrig            : R_TRIG;
    ConditionsMet               : BOOL;
    BlowerWasRunning            : BOOL;
END_VAR

// Combine start conditions: DO_LOW AND emergency stop NOT active
ConditionsMet := DO_LOW AND AERATION_E_STOP_NC;

// Start delay timer: enable when conditions met, reset when not
StartDelayTimer(IN := ConditionsMet, PT := T#5s);

// BLOWER_RUN follows timer completion while conditions remain
BLOWER_RUN := StartDelayTimer.Q;

// Rising edge detection on BLOWER_RUN for cycle counting
BlowerStartRTrig(CLK := BLOWER_RUN);
IF BlowerStartRTrig.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

END_FUNCTION_BLOCK