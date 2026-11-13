(* ENGINEERING_CONTRACT
===================
PUB001: Start demand = DO_LOW AND AERATION_E_STOP_NC (both TRUE required)
PUB002: 5-second PT TON delay; timer enabled while demand active; no edge trigger
PUB003: Immediate BLOWER_RUN disable on demand loss; full 5s delay on re-demand
PUB004: Rising-edge BLOWER_RUN (R_TRIG) increments AERATION_BLOWER_CYCLE_COUNT
PUB005: Power-up initialization: BLOWER_RUN=FALSE, count=0, timer reset

Output state:
- BLOWER_RUN: activation (TON.Q), retention (none - demand-gated), 
  explicit reset (demand loss), same-scan priority (timer evaluated each call)
- AERATION_BLOWER_CYCLE_COUNT: increment on BLOWER_RUN rising edge only
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK AerationBlowerControl
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR

VAR_OUTPUT
    BLOWER_RUN : BOOL;
    AERATION_BLOWER_CYCLE_COUNT : UINT;
END_VAR

VAR
    StartTimer : TON;
    RunRisingEdge : R_TRIG;
    tmp_DemandActive : BOOL;
END_VAR

// Combine start conditions: DO sufficient AND E-stop inactive
tmp_DemandActive := DO_LOW AND AERATION_E_STOP_NC;

// Rising edge detection for cycle counting
RunRisingEdge(CLK := BLOWER_RUN);

// Increment cycle count on rising edge of BLOWER_RUN
IF RunRisingEdge.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + UINT#1;
END_IF;

// Timer enabled while demand active
StartTimer(IN := tmp_DemandActive, PT := T#5S);

// Blower control: demand active AND timer elapsed
IF tmp_DemandActive AND StartTimer.Q THEN
    BLOWER_RUN := TRUE;
ELSE
    BLOWER_RUN := FALSE;
END_IF;

END_FUNCTION_BLOCK