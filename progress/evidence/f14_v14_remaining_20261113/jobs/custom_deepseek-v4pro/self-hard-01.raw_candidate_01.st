(*
ENGINEERING_CONTRACT
alarmActive: next = flowLow OR (prevActive AND !risingAck AND !(prevFlowLow AND prevAcked)).
  Retain on unacked condition loss; clear only when active-acked and flowLow drops, or ack rising while flowLow false.
alarmAcked: next = nextActive AND (!flowLow OR risingAck OR (prevFlowLow AND prevActive AND prevAcked)).
  True for active/acked or pending-clear; false when inactive or new flowLow after pending-clear.
highHigh = NOT sensorOK (combinational; no latch; auto clears same scan as sensorOK).
Memory: prevFlowLow/prevActive/prevAcked/prevAckBtn retained in VAR; update after output assignment.
Same-scan: risingAck computed before outputs; formulas use previous-cycle stored state; high priority independent.
Units: BOOL; no timers. See PUB001-PUB038.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    flowLow: BOOL;
    ackBtn: BOOL;
    sensorOK: BOOL;
END_VAR
VAR_OUTPUT
    alarmActive: BOOL;
    alarmAcked: BOOL;
    highHigh: BOOL;
END_VAR
VAR
    prevFlowLow: BOOL;
    prevAlarmActive: BOOL;
    prevAlarmAcked: BOOL;
    prevAckBtn: BOOL;
    risingAck: BOOL;
    nextActive: BOOL;
    nextAcked: BOOL;
    prevFlowLowAndAcked: BOOL;
    prevFlowLowActiveAcked: BOOL;
END_VAR

risingAck := ackBtn AND NOT prevAckBtn;

prevFlowLowAndAcked := prevFlowLow AND prevAlarmAcked;
prevFlowLowActiveAcked := prevFlowLow AND prevAlarmActive AND prevAlarmAcked;

nextActive := flowLow OR (prevAlarmActive AND NOT risingAck AND (NOT prevFlowLowAndAcked));
nextAcked := nextActive AND (NOT flowLow OR risingAck OR prevFlowLowActiveAcked);

alarmActive := nextActive;
alarmAcked := nextAcked;
highHigh := NOT sensorOK;

prevFlowLow := flowLow;
prevAlarmActive := nextActive;
prevAlarmAcked := nextAcked;
prevAckBtn := ackBtn;

END_FUNCTION_BLOCK