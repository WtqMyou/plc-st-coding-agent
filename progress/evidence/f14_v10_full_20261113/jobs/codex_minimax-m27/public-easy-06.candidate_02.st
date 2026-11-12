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
 *   - Timer reset (TON.IN := FALSE, TON.ET := 0)
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

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK AerationBlowerDelayedStart
VAR_INPUT
    DO_LOW                : BOOL;
    AERATION_E_STOP_NC    : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN                    : BOOL := FALSE;
    AERATION_BLOWER_CYCLE_COUNT   : UINT := 0;
END_VAR
VAR
    StartDelayTimer       : TON;
    BlowerStartRTrig      : R_TRIG;
    tmp_conditions_met    : BOOL;
END_VAR

tmp_conditions_met := DO_LOW AND AERATION_E_STOP_NC;

StartDelayTimer(IN := tmp_conditions_met, PT := T#5s);

BLOWER_RUN := StartDelayTimer.Q;

BlowerStartRTrig(CLK := BLOWER_RUN);
IF BlowerStartRTrig.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

END_FUNCTION_BLOCK