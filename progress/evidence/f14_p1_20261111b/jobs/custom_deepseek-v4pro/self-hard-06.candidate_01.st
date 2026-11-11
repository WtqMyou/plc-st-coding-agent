FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    pressure : REAL;
    pressureValid : BOOL;
    fuelFlow : REAL;
    steamFlow : REAL;
    outletCmd : INT;
    outletFeedback : INT;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched : BOOL;
    fuelPermit : BOOL;
    currentCauseMask : WORD;
    latchedCauseMask : WORD;
    diagnosticActive : BOOL;
END_VAR
VAR
    stallCount : INT := 0;          (* 连续卡滞计数 *)
    prevResetBtn : BOOL := FALSE;   (* 上一周期复位按钮 *)
    risingReset : BOOL;
    condStall : BOOL;
    newTripLatched : BOOL;
END_VAR

(* 复位按钮上升沿检测 *)
risingReset := resetBtn AND NOT prevResetBtn;

(* 计算本拍诊断线索 currentCauseMask *)
currentCauseMask := 0;

IF NOT runRequest THEN
    currentCauseMask := 0;
    stallCount := 0;
ELSIF NOT pressureValid THEN
    currentCauseMask := 1;          (* bit0: 变送器失效 *)
    stallCount := 0;
ELSE
    (* runRequest AND pressureValid *)
    IF pressure < 4500.0 THEN
        currentCauseMask := 0;
        stallCount := 0;
    ELSE
        (* 超压工况: pressure >= 4500.0 *)
        condStall := (outletCmd >= 50) AND (outletFeedback <= 10);
        IF condStall THEN
            stallCount := stallCount + 1;
        ELSE
            stallCount := 0;
        END_IF

        (* bit1: 减温减压阀卡滞，连续3拍 *)
        IF stallCount >= 3 THEN
            currentCauseMask := currentCauseMask OR 16#0002;
        END_IF

        (* bit2: 燃烧过剩 *)
        IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
            currentCauseMask := currentCauseMask OR 16#0004;
        END_IF

        (* bit3: 未定位 *)
        IF currentCauseMask = 0 THEN
            currentCauseMask := 16#0008;
        END_IF
    END_IF
END_IF

(* 计算新的跳闸锁存状态 *)
newTripLatched := (runRequest AND (NOT pressureValid OR pressure >= 4500.0))
                  OR (tripLatched AND NOT (risingReset AND NOT runRequest AND pressureValid AND pressure <= 4200.0));

(* 更新跳闸期间线索累积足迹 *)
IF newTripLatched THEN
    latchedCauseMask := (latchedCauseMask OR currentCauseMask) AND 16#000F;
ELSE
    latchedCauseMask := 0;
END_IF

(* 输出更新 *)
tripLatched := newTripLatched;
fuelPermit := runRequest AND NOT newTripLatched;
diagnosticActive := (currentCauseMask <> 0);

(* 保存本拍 resetBtn 供下周期上升沿检测 *)
prevResetBtn := resetBtn;