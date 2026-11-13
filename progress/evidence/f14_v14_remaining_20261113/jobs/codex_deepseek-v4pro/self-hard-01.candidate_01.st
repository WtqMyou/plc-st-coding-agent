(*
ENGINEERING_CONTRACT
 alarmActive: set=flowLow (PUB005); hold while unacknowledged despite flow loss (PUB006);
 clear=rising ack with flowLow=FALSE, or condition loss after confirmed-active state (PUB007/S6);
 evaluates current flowLow and rising ack in the same scan.
 alarmAcked: set=flow loss while active-unacknowledged (PUB006), rising ack with flowLow (PUB007),
 or sustained confirmation (LTL S7); clear when alarmActive becomes FALSE.
 highHigh: set/reset=!sensorOK in the same scan (PUB008-PUB009); independent of low outputs.
 Priority/units: highHigh and low-alarm outputs may be TRUE simultaneously; BOOL states; one-scan ack edge.
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
    local_PrevAckBtn : BOOL := FALSE;
    local_PrevFlowLow : BOOL := FALSE;
    local_PrevAlarmActive : BOOL := FALSE;
    local_PrevAlarmAcked : BOOL := FALSE;
    local_RisingAckBtn : BOOL := FALSE;
END_VAR

local_RisingAckBtn := ackBtn AND NOT local_PrevAckBtn;

alarmActive := flowLow OR
               (local_PrevAlarmActive AND
                NOT local_RisingAckBtn AND
                NOT (local_PrevFlowLow AND local_PrevAlarmAcked));

alarmAcked := alarmActive AND
              (NOT flowLow OR
               local_RisingAckBtn OR
               (local_PrevFlowLow AND local_PrevAlarmActive AND local_PrevAlarmAcked));

highHigh := NOT sensorOK;

local_PrevAckBtn := ackBtn;
local_PrevFlowLow := flowLow;
local_PrevAlarmActive := alarmActive;
local_PrevAlarmAcked := alarmAcked;

END_FUNCTION_BLOCK