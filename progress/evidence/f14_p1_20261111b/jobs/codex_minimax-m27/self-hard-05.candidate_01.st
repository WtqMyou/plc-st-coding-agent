FUNCTION_BLOCK FB
VAR_INPUT
    runRequest : BOOL;
    flameOK    : BOOL;
    o2Valid    : BOOL;
    o2PV       : REAL;
    baseAir    : REAL;
    resetBtn   : BOOL;
END_VAR

VAR_OUTPUT
    fuelPermit : BOOL;
    trimEnable : BOOL;
    airTrim    : REAL;
    airCommand : REAL;
    tripLatched: BOOL;
    o2Fault    : BOOL;
END_VAR

VAR
    prevResetBtn : BOOL := FALSE;
END_VAR

// ── 熄火跳闸（当拍置位，检测优先于复位）───────────────────────
IF runRequest AND NOT flameOK THEN
    tripLatched := TRUE;
ELSIF resetBtn AND NOT prevResetBtn AND NOT runRequest AND NOT flameOK THEN
    tripLatched := FALSE;
ELSE
    tripLatched := tripLatched;
END_IF

// ── 燃料许可 ───────────────────────────────────────────────────
fuelPermit := runRequest AND flameOK AND NOT tripLatched;

// ── 氧量分析仪故障检测 ─────────────────────────────────────────
o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

// ── 氧量修正投入 ───────────────────────────────────────────────
trimEnable := fuelPermit AND NOT o2Fault;

// ── 氧量修正偏置（钳位 ±10，故障时归零）────────────────────────
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

// ── 风门命令（燃料许可时叠加修正并钳位 0..100，否则归零）────────
IF fuelPermit THEN
    airCommand := baseAir + airTrim;
    IF airCommand > 100.0 THEN
        airCommand := 100.0;
    ELSIF airCommand < 0.0 THEN
        airCommand := 0.0;
    END_IF;
ELSE
    airCommand := 0.0;
END_IF;

// ── 保存本拍复位按钮状态，供下拍边沿检测 ───────────────────────
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK