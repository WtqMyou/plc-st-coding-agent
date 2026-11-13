FUNCTION_BLOCK AerationBlowerDelayedStart
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN : BOOL := FALSE;
    AERATION_BLOWER_CYCLE_COUNT : UINT := 0;
END_VAR
VAR
    tmp_Demand : BOOL;
    tmp_StartDelay : TON;
    tmp_RunRising : R_TRIG;
END_VAR

(* ENGINEERING_CONTRACT
- Activation: BLOWER_RUN becomes TRUE only after DO_LOW AND AERATION_E_STOP_NC remain TRUE for T#5S [PUB001].
- Retention/hold: BLOWER_RUN remains TRUE while the demand condition stays satisfied; it is not latched [PUB001].
- Reset/deactivation: DO_LOW FALSE or active emergency stop immediately sets BLOWER_RUN FALSE and resets the TON [PUB002].
- Same-scan priority: condition FALSE terminates timing and clears BLOWER_RUN before cycle-edge evaluation [PUB001, PUB002].
- Cycle count: increments once on each FALSE-to-TRUE BLOWER_RUN edge, holds otherwise, and starts at zero [PUB003, PUB004].
- Units/boundaries: 5 seconds, UINT cycle count, BOOL enable only with no speed ramp [PUB001, PUB003, PUB004].
*)

(* CONTRACT_RULES [] *)

tmp_Demand := DO_LOW AND AERATION_E_STOP_NC;

tmp_StartDelay(IN := tmp_Demand, PT := T#5S);
BLOWER_RUN := tmp_StartDelay.Q;

tmp_RunRising(CLK := BLOWER_RUN);
IF tmp_RunRising.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

END_FUNCTION_BLOCK