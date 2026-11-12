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
| alarmActive [BOOL]  | flowLow rising edge | Until explicit | rising(ackBtn) + !flowLow + tmp_unacked_wait; | Same-scan | 0..1 |
|                     |                     | deactivation   | tmp_unacked_wait := TRUE on flowLow falling  |               |                   |
|                     |                     |                | while !alarmAcked                         |               |                   |
| alarmAcked [BOOL]   | rising(ackBtn) with | Cleared on new | rising(ackBtn) + !flowLow + tmp_unacked_wait | Same-scan | 0..1 |
|                     | flowLow present;    | flowLow rise;  |                                             |               |                   |
|                     | flowLow fall while  | retained during|                                             |               |                   |
|                     | !alarmAcked         | waiting state  |                                             |               |                   |
| highHigh [BOOL]     | !sensorOK (PUB027)  | Retained while | sensorOK TRUE (PUB035)                     | Same-scan | 0..1 |
|                     |                     | !sensorOK      |                                             |               |                   |
| tmp_unacked_wait    | flowLow falling     | Until rising   | rising(ackBtn) + !flowLow                  | Internal  | Named boolean     |
| [BOOL, local]       | while !alarmAcked   | (ackBtn)       |                                             |           |                   |
================================================================================
PUB IDs: alarmActive→PUB001/PUB002/PUB003/PUB004/PUB005/PUB006; alarmAcked→PUB007/PUB008/PUB009/PUB010/PUB011/PUB012; highHigh→PUB027/PUB035

CONTRACT_RULES: []
================================================================================
*)

tmp_flowRising := flowLow AND NOT prev_flowLow;
tmp_ackRising  := ackBtn  AND NOT prev_ackBtn;

alarmActive := alarmActive;
alarmAcked  := alarmAcked;

IF tmp_flowRising THEN
    alarmActive := TRUE;
    alarmAcked  := FALSE;
ELSIF alarmActive AND tmp_ackRising THEN
    IF NOT flowLow THEN
        alarmActive := FALSE;
        alarmAcked  := FALSE;
    ELSE
        alarmAcked  := TRUE;
    END_IF;
ELSIF alarmActive AND NOT flowLow AND NOT alarmAcked THEN
    alarmAcked := TRUE;
ELSIF alarmActive AND flowLow AND alarmAcked AND tmp_flowRising THEN
    alarmAcked := FALSE;
END_IF;

highHigh := NOT sensorOK;

prev_flowLow := flowLow;
prev_ackBtn  := ackBtn;

END_FUNCTION_BLOCK