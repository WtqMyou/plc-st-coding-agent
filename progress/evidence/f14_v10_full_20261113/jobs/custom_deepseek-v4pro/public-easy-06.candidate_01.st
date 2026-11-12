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
    startTimer : TON;
    startEdge : R_TRIG;
END_VAR

(*
ENGINEERING_CONTRACT
Output BLOWER_RUN:
  activation: startTimer.Q after DO_LOW AND AERATION_E_STOP_NC true for T#5S (PUB001).
  hold: remains TRUE while both inputs stay TRUE (PUB001).
  reset/deactivation: DO_LOW=FALSE or AERATION_E_STOP_NC=FALSE disables same scan and resets timer (PUB002).
  units/boundaries: BOOL.
Output AERATION_BLOWER_CYCLE_COUNT:
  activation: increment on R_TRIG false->true of BLOWER_RUN (PUB003).
  hold: retains value during operation; stop does not reset count.
  reset: only power-up/cold init to 0 (PUB004).
  units/boundaries: UINT starts; saturates at 65535 (unspecified).
*)

(* CONTRACT_RULES [] *)

startTimer(IN := DO_LOW AND AERATION_E_STOP_NC, PT := T#5S);
BLOWER_RUN := startTimer.Q;

startEdge(CLK := BLOWER_RUN);
IF startEdge.Q THEN
    IF AERATION_BLOWER_CYCLE_COUNT < UINT#65535 THEN
        AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + UINT#1;
    END_IF;
END_IF;

END_FUNCTION_BLOCK