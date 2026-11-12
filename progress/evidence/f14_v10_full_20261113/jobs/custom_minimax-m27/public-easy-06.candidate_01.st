FUNCTION_BLOCK AerationBlowerControl
VAR_INPUT
    DO_LOW            : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN                  : BOOL := FALSE;
    AERATION_BLOWER_CYCLE_COUNT : UINT := 0;
END_VAR
VAR
    startTimer  : TON;
    runRising   : R_TRIG;
    tmpCondMet  : BOOL;
END_VAR
// -----------------------------------------------------------------------------
// ENGINEERING_CONTRACT
// PubReq PUB001 §3.2: BLOWER_RUN activation - gated enable after PT=5s of
//   satisfied preconditions (DO_LOW AND AERATION_E_STOP_NC both TRUE).
//   TON.Q becomes TRUE at elapsed >= PT; no continuous ramp required.
// PubReq PUB002 §3.2: Explicit reset - any precondition failure
//   (DO_LOW=FALSE OR AERATION_E_STOP_NC=FALSE) immediately deactivates
//   BLOWER_RUN and resets the start timer via TON(PT:=0) or IN:=FALSE.
//   New demand requires the full PT again; no shortcut or resume.
// PubReq PUB003 §3.3: Cycle counting - R_TRIG on BLOWER_RUN rising edge;
//   AERATION_BLOWER_CYCLE_COUNT increments once per start transition,
//   not during continuous TRUE run.
// PubReq PUB004 §3.4: Power-up initialization - BLOWER_RUN:=FALSE and
//   AERATION_BLOWER_CYCLE_COUNT:=0 via VAR_INIT (output defaults).
// Units: TON PT = T#5s (5000 ms, LTIME-based internally).
// Same-scan: startTimer(IN:=tmpCondMet) called once per cycle after
//   tmpCondMet is settled; TON.Q and TON.ET reflect that single evaluation.
// -----------------------------------------------------------------------------

tmpCondMet := DO_LOW AND AERATION_E_STOP_NC;

// Start delay timer: IN asserted while preconditions met; reset on loss
startTimer(IN := tmpCondMet, PT := T#5s);

// BLOWER_RUN follows timer output when conditions are met; forced FALSE on loss
IF tmpCondMet THEN
    BLOWER_RUN := startTimer.Q;
ELSE
    BLOWER_RUN := FALSE;
END_IF;

// Rising-edge detection on BLOWER_RUN for cycle count
runRising(CLK := BLOWER_RUN);
IF runRising.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

END_FUNCTION_BLOCK