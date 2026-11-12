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
    tripInternal : BOOL := FALSE;
END_VAR

// 氧量故障判定
o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;

// 熄火跳闸逻辑：运行中失去火焰当拍置位；安全停机态下复位上升沿清除
IF runRequest AND NOT flameOK THEN
    tripInternal := TRUE;
ELSIF NOT runRequest AND NOT flameOK AND resetBtn AND NOT prevResetBtn THEN
    tripInternal := FALSE;
END_IF;

// 燃料许可：运行请求、火焰正常、未跳闸三者同时成立
fuelPermit := runRequest AND flameOK AND NOT tripInternal;

// 氧量修正：投入需燃料许可且分析仪无故障
IF fuelPermit AND NOT o2Fault THEN
    trimEnable := TRUE;
    airTrim := LIMIT(-10.0, 2.0 * (2.0 - o2PV), 10.0);
ELSE
    trimEnable := FALSE;
    airTrim := 0.0;
END_IF;

// 风门命令：基础开度叠加修正，偏置切除时自动归零
IF fuelPermit THEN
    airCommand := LIMIT(0.0, baseAir + airTrim, 100.0);
ELSE
    airCommand := 0.0;
END_IF;

// 输出跳闸状态
tripLatched := tripInternal;

// 边沿检测：保存复位按钮上一拍状态
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK