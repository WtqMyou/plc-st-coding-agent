FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel   : REAL;
    outletFlow  : REAL;
    inletPermit : BOOL;
    resetBtn    : BOOL;
END_VAR

VAR_OUTPUT
    pumpRun         : BOOL;
    alarmHigh       : BOOL;
    alarmLow        : BOOL;
    outletValveOpen : BOOL;
END_VAR

VAR
    prevResetBtn  : BOOL := FALSE;
    prevAlarmHigh : BOOL := FALSE;
    prevAlarmLow  : BOOL := FALSE;

    risingReset : BOOL;
    highHazard  : BOOL;
    lowHazard   : BOOL;
END_VAR

(* 检測複位按鍵上升沿 *)
risingReset := resetBtn AND NOT prevResetBtn;

(* 危險條件 *)
highHazard := (tankLevel >= 85.0);
lowHazard  := (tankLevel <= 15.0);

(* 報警鎖存：危險條件成立時立即置位，否則跟隨上一拍狀態（若未出現復位上升沿） *)
alarmHigh := highHazard OR (prevAlarmHigh AND NOT risingReset);
alarmLow  := lowHazard  OR (prevAlarmLow  AND NOT risingReset);

(* 輸出 *)
pumpRun         := inletPermit AND NOT alarmHigh AND NOT alarmLow;
outletValveOpen := NOT alarmLow;

(* 為下一掃描保存狀態 *)
prevResetBtn  := resetBtn;
prevAlarmHigh := alarmHigh;
prevAlarmLow  := alarmLow;

END_FUNCTION_BLOCK