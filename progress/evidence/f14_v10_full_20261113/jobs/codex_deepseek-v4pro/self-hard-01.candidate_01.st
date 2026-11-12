(*
ENGINEERING_CONTRACT
alarmActive: set when flowLow is TRUE (PUB001); holds when flowLow clears unacknowledged (PUB002); clears on current rising ack with flowLow FALSE, or automatically after already acknowledged condition loss (PUB003, S6).
alarmAcked: cleared for an active unacknowledged condition; set by rising ack while flowLow remains TRUE, or when unacknowledged flowLow clears; cleared together with alarmActive on pending-clear ack (PUB002-PUB003, S7).
highHigh: equals NOT sensorOK every scan; no latch and no cross-suppression of alarmActive/alarmAcked (PUB004, S3, S5).
Same-scan priority: rising ack uses current ackBtn sample; flowLow/ack/sensorOK effects are independent; no hidden reset, timer, or extra edge trigger is added.
Units/bounds: all public values are BOOL per scan.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    flowLow : BOOL;
    ackBtn : BOOL;
    sensorOK : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked : BOOL;
    highHigh : BOOL;
END_VAR
VAR
    local_prevAckBtn : BOOL := FALSE;
    local_prevFlowLow : BOOL := FALSE;
    local_prevAlarmActive : BOOL := FALSE;
    local_prevAlarmAcked : BOOL := FALSE;
    local_risingAck : BOOL;
    local_prevFlowAckedTerm : BOOL;
    local_prevRetainAckTerm : BOOL;
END_VAR

local_risingAck := ackBtn AND NOT local_prevAckBtn;

highHigh := NOT sensorOK;

local_prevFlowAckedTerm := local_prevFlowLow AND local_prevAlarmAcked;
alarmActive := flowLow OR (local_prevAlarmActive AND NOT local_risingAck AND NOT local_prevFlowAckedTerm);

local_prevRetainAckTerm := local_prevFlowLow AND local_prevAlarmActive AND local_prevAlarmAcked;
alarmAcked := alarmActive AND (NOT flowLow OR local_risingAck OR local_prevRetainAckTerm);

local_prevAckBtn := ackBtn;
local_prevFlowLow := flowLow;
local_prevAlarmActive := alarmActive;
local_prevAlarmAcked := alarmAcked;