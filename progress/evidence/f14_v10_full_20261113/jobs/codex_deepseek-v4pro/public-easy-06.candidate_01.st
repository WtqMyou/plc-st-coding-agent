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
    tmp_StartDelay : TON;
    tmp_PrevRun : BOOL := FALSE;
END_VAR

(*
ENGINEERING_CONTRACT
- BLOWER_RUN activation: only when DO_LOW and AERATION_E_STOP_NC have both been TRUE for T#5s (PUB001).
- BLOWER_RUN retention/hold: remains TRUE only while both enabling conditions remain TRUE; no separate latch is used.
- BLOWER_RUN explicit reset/deactivation: any FALSE of DO_LOW or AERATION_E_STOP_NC clears timer IN immediately, so output and timing reset (PUB002).
- AERATION_BLOWER_CYCLE_COUNT activation: increments once on each BLOWER_RUN FALSE->TRUE transition; not repeated during continuous run (PUB003).
- AERATION_BLOWER_CYCLE_COUNT reset: initialized to zero at power-up; no task-specified runtime reset is implemented (PUB004).
- Same-scan priority: current DO_LOW/E_STOP condition directly gates TON.IN before timer Q and edge counting are evaluated.
- Units/boundaries: delay is 5 000 ms (T#5s); cycle count is UINT and unspecified at maximum rollover.
*)
(* CONTRACT_RULES [] *)

tmp_StartDelay(IN := DO_LOW AND AERATION_E_STOP_NC, PT := T#5S);

BLOWER_RUN := tmp_StartDelay.Q;

IF BLOWER_RUN AND NOT tmp_PrevRun THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

tmp_PrevRun := BLOWER_RUN;

END_FUNCTION_BLOCK