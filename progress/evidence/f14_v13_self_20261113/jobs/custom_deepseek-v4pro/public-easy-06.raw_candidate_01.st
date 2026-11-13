FUNCTION_BLOCK AerationBlowerDelayedStart
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN : BOOL;
    AERATION_BLOWER_CYCLE_COUNT : UINT;
END_VAR
VAR
    startTimer : TON;
    blowerRising : R_TRIG;
    tmp_initDone : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
   BLOWER_RUN: combinational enable derived from TON.Q. Activate when DO_LOW AND AERATION_E_STOP_NC
   remain TRUE for 5 s (PUB001). Deactivate immediately when either input becomes FALSE; TON IN false resets
   the timer in the same scan (PUB002). No latch or hold_until_reset.
   AERATION_BLOWER_CYCLE_COUNT: retained UINT output, initialized to 0 on first scan (PUB004).
   Increment exactly once on each FALSE->TRUE edge of BLOWER_RUN (PUB003). Unit: starts; range 0..65535.
   First-scan initialization forces BLOWER_RUN FALSE and count 0 (PUB004). No speed ramp (PUB004).
*)

(* CONTRACT_RULES [] *)

IF NOT tmp_initDone THEN
    BLOWER_RUN := FALSE;
    AERATION_BLOWER_CYCLE_COUNT := 0;
    tmp_initDone := TRUE;
END_IF;

startTimer(IN := DO_LOW AND AERATION_E_STOP_NC, PT := T#5S);
BLOWER_RUN := startTimer.Q;

blowerRising(CLK := BLOWER_RUN);
IF blowerRising.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

END_FUNCTION_BLOCK