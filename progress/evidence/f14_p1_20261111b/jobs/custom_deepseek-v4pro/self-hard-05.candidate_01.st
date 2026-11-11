FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    flameOK : BOOL;
    o2Valid : BOOL;
    o2PV : REAL;
    baseAir : REAL;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit : BOOL;
    trimEnable : BOOL;
    airTrim : REAL;
    airCommand : REAL;
    tripLatched : BOOL;
    o2Fault : BOOL;
END_VAR
VAR
    tripState : BOOL := FALSE;   (* 内部跳闸记忆 *)
    prevReset : BOOL := FALSE;   (* 上一周期复位按钮状态 *)
    resetRising : BOOL;          (* 复位上升沿标志 *)
    rawTrim : REAL;              (* 未限幅的氧量修正 *)
BEGIN
    (* 1. 分析仪故障判断 *)
    o2Fault := (NOT o2Valid) OR (o2PV < 0.0) OR (o2PV > 21.0);

    (* 2. 检测复位按钮上升沿 *)
    resetRising := resetBtn AND (NOT prevReset);

    (* 3. 跳闸状态更新（当拍置位与自保持清除） *)
    IF (runRequest AND (NOT flameOK)) THEN
        tripState := TRUE;
    ELSIF (tripState AND resetRising AND (NOT runRequest) AND (NOT flameOK)) THEN
        tripState := FALSE;
    END_IF;

    (* 4. 输出跳闸状态 *)
    tripLatched := tripState;

    (* 5. 燃料许可 *)
    fuelPermit := runRequest AND flameOK AND (NOT tripLatched);

    (* 6. 氧量修正投入 *)
    trimEnable := fuelPermit AND (NOT o2Fault);

    (* 7. 氧量修正偏置计算 *)
    IF trimEnable THEN
        rawTrim := 2.0 * (2.0 - o2PV);
        (* 钳位到 [-10, 10] *)
        IF rawTrim < -10.0 THEN
            airTrim := -10.0;
        ELSIF rawTrim > 10.0 THEN
            airTrim := 10.0;
        ELSE
            airTrim := rawTrim;
        END_IF;
    ELSE
        airTrim := 0.0;
    END_IF;

    (* 8. 风门命令计算 *)
    IF fuelPermit THEN
        airCommand := baseAir + airTrim;
        (* 钳位到 [0, 100] *)
        IF airCommand < 0.0 THEN
            airCommand := 0.0;
        ELSIF airCommand > 100.0 THEN
            airCommand := 100.0;
        END_IF;
    ELSE
        airCommand := 0.0;
    END_IF;

    (* 9. 保存复位按钮状态供下一周期边沿检测 *)
    prevReset := resetBtn;
END_FUNCTION_BLOCK