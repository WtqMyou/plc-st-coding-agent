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

// S2: 跳闸置位与清除（清除需复位上升沿且 flameOK=FALSE 且 runRequest=FALSE）
IF prevResetBtn AND NOT resetBtn AND NOT runRequest AND NOT flameOK THEN
    tripLatched := FALSE;
ELSIF runRequest AND NOT flameOK THEN
    tripLatched := TRUE;
END_IF;

// 记录复位按钮上一状态（边沿检测）
prevResetBtn := resetBtn;

// o2Fault：独立于 tripLatched，只切除修正不切除燃料
o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

// fuelPermit：runRequest AND flameOK AND NOT tripLatched
fuelPermit := runRequest AND flameOK AND NOT tripLatched;

// trimEnable：fuelPermit AND NOT o2Fault
trimEnable := fuelPermit AND NOT o2Fault;

// airTrim 钳位 ±10；trimEnable=FALSE 时强制为 0.0
IF trimEnable THEN
    airTrim := 2.0 * (2.0 - o2PV);
    IF airTrim > 10.0 THEN
        airTrim := 10.0;
    ELSIF airTrim < -10.0 THEN
        airTrim := -10.0;
    END_IF;
ELSE
    airTrim := 0.0;
END_IF;

// airCommand：fuelPermit=FALSE 时强制为 0.0；否则钳位 0..100
IF NOT fuelPermit THEN
    airCommand := 0.0;
ELSE
    airCommand := baseAir + airTrim;
    IF airCommand > 100.0 THEN
        airCommand := 100.0;
    ELSIF airCommand < 0.0 THEN
        airCommand := 0.0;
    END_IF;
END_IF;
END_FUNCTION_BLOCK