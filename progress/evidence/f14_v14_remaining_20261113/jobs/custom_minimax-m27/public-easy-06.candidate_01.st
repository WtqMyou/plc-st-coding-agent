FUNCTION_BLOCK AerationBlowerDelayedStart
(*
    ENGINEERING_CONTRACT
    PUB001: BLOWER_RUN activates only after DO_LOW AND AERATION_E_STOP_NC are TRUE continuously for 5 seconds.
    PUB002: BLOWER_RUN and timer reset immediately when DO_LOW=FALSE OR AERATION_E_STOP_NC=FALSE (no partial credit).
    PUB003: AERATION_BLOWER_CYCLE_COUNT increments on FALSE-to-TRUE (rising) edge of BLOWER_RUN; no repeat during sustained TRUE.
    PUB004: Power-up initializes BLOWER_RUN=FALSE and AERATION_BLOWER_CYCLE_COUNT=0; no prior state retained.
    Activation: BLOWER_RUN = TON.Q (PT=5000ms, IN=DO_LOW AND AERATION_E_STOP_NC).
    Retention: BLOWER_RUN held TRUE while start conditions remain satisfied without stop event.
    Reset/Deactivation: Timer.IN:=FALSE forces TON.Q:=FALSE on same scan as condition loss.
    Same-scan priority: Final condition state determines timer enable before TON call; output assigned after.
    Units/Boundaries: TON PT=TIME#5s (5000ms); threshold is >= PT (TON.Q true when ET >= PT).
*)

VAR_INPUT
    DO_LOW              : BOOL;  (* Dissolved oxygen below threshold; aeration demand *)
    AERATION_E_STOP_NC  : BOOL;  (* TRUE=inactive, FALSE=emergency stop active *)
END_VAR

VAR_OUTPUT
    BLOWER_RUN                  : BOOL;  (* Blower motor run command *)
    AERATION_BLOWER_CYCLE_COUNT : UINT;  (* Count of blower start cycles *)
END_VAR

VAR
    tmp_Rise : R_TRIG;  (* Rising-edge detector for cycle counting *)
    tmp_Ton  : TON;     (* 5-second start delay timer *)
END_VAR

(* Cycle counter rising-edge detector *)
tmp_Rise(CLK := BLOWER_RUN);
IF tmp_Rise.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + UINT#1;
END_IF;

(* Start-delay timer: IN is TRUE only when both demand present and E-stop inactive *)
tmp_Ton.IN  := DO_LOW AND AERATION_E_STOP_NC;
tmp_Ton.PT  := T#5S;
tmp_Ton();

(* Blower command follows timer completion; both IN and Q go FALSE on same scan when conditions drop *)
BLOWER_RUN := tmp_Ton.Q;

END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)