FUNCTION_BLOCK FB
VAR_INPUT
    flowLow   : BOOL;
    ackBtn    : BOOL;
    sensorOK  : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked  : BOOL;
    highHigh    : BOOL;
END_VAR
VAR
    prev_flowLow : BOOL := FALSE;
    prev_ackBtn  : BOOL := FALSE;
    tmp_flowRising : BOOL;
    tmp_ackRising  : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT:
================================================================================
| Output/State        | Activation          | Retention      | Reset/Deact         | Scan Priority | Units/Range       |
|---------------------|---------------------|----------------|---------------------|---------------|-------------------|
| alarmActive [BOOL]  | flowLow rising edge | Until explicit | rising(ackBtn)+!flowLow; or flowLow | Same-scan | 0..1 |
|                     | (PUB001)            | deactivation   | rises while alarmAcked=TRUE (new occ) |          |                   |
| alarmAcked [BOOL]   | rising(ackBtn) with | Cleared on new | rising(ackBtn)+!flowLow (PUB009/PUB010) | Same-scan | 0..1 |
|                     | flowLow present     | flowLow rise   |                                         |               |                   |
|                     | (PUB008/PUB011);    | (new occ)      |                                         |               |                   |
|                     | flowLow falling     | Retained while |                                         |               |                   |
|                     | while !alarmAcked   | waiting clear  |                                         |               |                   |
|                     | (PUB006: pending)   | (PUB006)       |                                         |               |                   |
| highHigh [BOOL]     | !sensorOK (PUB027)  | Retained while | sensorOK TRUE (PUB035)                  | Same-scan | 0..1 |
|                     |                     | !sensorOK      |                                         |               |                   |
================================================================================
PUB IDs: alarmActive→PUB001/PUB002/PUB003/PUB004/PUB005/PUB006;
         alarmAcked→PUB006/PUB007/PUB008/PUB009/PUB010/PUB011/PUB012;
         highHigh→PUB027/PUB035

CONTRACT_RULES: []
================================================================================
*)

tmp_flowRising := flowLow AND NOT prev_flowLow;
tmp_ackRising  := ackBtn  AND NOT prev_ackBtn;

IF tmp_flowRising THEN
    alarmActive := TRUE;
    alarmAcked  := FALSE;
ELSIF alarmActive AND tmp_ackRising AND (flowLow OR alarmAcked) THEN
    alarmAcked := TRUE;
ELSIF alarmActive AND NOT flowLow AND NOT alarmAcked THEN
    alarmAcked := TRUE;
ELSIF alarmActive AND NOT flowLow THEN
    alarmActive := FALSE;
    alarmAcked  := FALSE;
END_IF;

highHigh := NOT sensorOK;

prev_flowLow := flowLow;
prev_ackBtn  := ackBtn;

END_FUNCTION_BLOCK