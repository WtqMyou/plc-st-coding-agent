FUNCTION_BLOCK FB
VAR_INPUT
    runRequest  : BOOL;
    flameOK     : BOOL;
    o2Valid     : BOOL;
    o2PV        : REAL;
    baseAir     : REAL;
    resetBtn    : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit  : BOOL;
    trimEnable  : BOOL;
    airTrim     : REAL;
    airCommand  : REAL;
    tripLatched : BOOL;
    o2Fault     : BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
END_VAR

    // 熄火跳闸逻辑
    IF runRequest AND NOT flameOK THEN
        tripLatched := TRUE;
    END_IF

    // 复位逻辑：上升沿清除（仅当runRequest=FALSE且flameOK=FALSE时有效）
    IF resetBtn AND NOT prevResetBtn THEN
        IF NOT runRequest AND NOT flameOK THEN
            tripLatched := FALSE;
        END_IF
    END_IF

    // 保存复位按钮边沿
    prevResetBtn := resetBtn;

    // 燃料许可
    fuelPermit := runRequest AND flameOK AND NOT tripLatched;

    // 氧量故障检测
    o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

    // 氧量修正使能与偏置计算
    trimEnable := fuelPermit AND NOT o2Fault;
    IF trimEnable THEN
        airTrim := 2.0 * (2.0 - o2PV);
        // 钳位到[-10, +10]
        IF airTrim > 10.0 THEN
            airTrim := 10.0;
        ELSIF airTrim < -10.0 THEN
            airTrim := -10.0;
        END_IF
    ELSE
        airTrim := 0.0;
    END_IF

    // 风门命令计算
    IF fuelPermit THEN
        airCommand := baseAir + airTrim;
        // 钳位到[0, 100]
        IF airCommand > 100.0 THEN
            airCommand := 100.0;
        ELSIF airCommand < 0.0 THEN
            airCommand := 0.0;
        END_IF
    ELSE
        airCommand := 0.0;
    END_IF

END_FUNCTION_BLOCK