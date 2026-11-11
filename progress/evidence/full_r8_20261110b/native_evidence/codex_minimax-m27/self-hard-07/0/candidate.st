FUNCTION_BLOCK FB
VAR_INPUT
    mode            : INT;          // 0=手动 1=自动 2=串级
    resetBtn        : BOOL;         // 复位上升沿
    scanSeconds     : REAL;         // 本次扫描周期(秒)
    tempSP          : REAL;         // 温度设定值(℃)
    tempPV          : REAL;         // 温度测量值(℃)
    flowPV          : REAL;         // 流量测量值(t/h)
    manualFlowSP    : REAL;         // 手动流量设定值(t/h)
    manualValve     : REAL;         // 手动阀门开度(%)
END_VAR
VAR_OUTPUT
    flowSP          : REAL;         // 流量设定值(t/h, 限幅0..50)
    valveCommand    : REAL;         // 阀门开度指令(%, 限幅0..100)
    fault           : BOOL;         // 故障标志
    normalMode      : BOOL;         // 正常运算拍
END_VAR
VAR
    prevResetBtn    : BOOL := FALSE;
    prevMode        : INT := -1;    // -1表示首次
    prevFlowSP      : REAL := 0.0;
    prevValveCommand: REAL := 0.0;
    prevNormalMode  : BOOL := FALSE;
    accT            : REAL := 0.0;  // 外环积分累加器(t/h)
    accF            : REAL := 0.0;  // 内环积分累加器(%)
    isFirstScan     : BOOL := TRUE;
END_VAR

VAR_TEMP
    eT              : REAL;         // 温度偏差
    eF              : REAL;         // 流量偏差
    trialT          : REAL;         // 外环临时变量
    trialF          : REAL;         // 内环临时变量
    resetRising     : BOOL;         // 复位上升沿检测
    modeChanged     : BOOL;         // 模式是否变化
    isFaultCondition: BOOL;         // 故障条件
END_VAR

// 计算偏差
eT := tempSP - tempPV;
eF := flowSP - flowPV;

// 检测复位上升沿
resetRising := resetBtn AND NOT prevResetBtn;

// 检测模式变化(首次除外)
modeChanged := (prevMode <> -1) AND (mode <> prevMode);

// 故障条件判断
isFaultCondition := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

// 更新故障标志
fault := isFaultCondition;

// 判断是否正常运算拍
// 条件：非首次、非故障、非复位上升沿、非模式切换
normalMode := NOT isFirstScan AND NOT isFaultCondition AND NOT resetRising AND NOT modeChanged AND prevNormalMode;

// 首次执行
IF isFirstScan THEN
    // 首拍按手动值预置输出
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    isFirstScan := FALSE;
    
// 复位上升沿(优先于故障)
ELSIF resetRising THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    
// 故障状态
ELSIF isFaultCondition THEN
    // 故障时输出跟手动值，允许突变
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    // 预置积分器
    accT := 0.0;
    accF := 0.0;
    
// 模式切换拍
ELSIF modeChanged THEN
    // 本拍不积分，保持输出
    IF mode = 2 THEN
        // 切换到串级：两输出均保持上一拍值
        flowSP := prevFlowSP;
        valveCommand := prevValveCommand;
    ELSE
        // 切换到自动或手动：流量跟手动，阀位保持
        flowSP := manualFlowSP;
        valveCommand := prevValveCommand;
    END_IF
    
// 正常运算拍
ELSIF normalMode THEN
    // 外环PI计算
    trialT := accT + 0.2 * eT * scanSeconds;
    flowSP := 1.0 * eT + trialT;
    
    // 外环限幅
    IF flowSP > 50.0 THEN
        flowSP := 50.0;
    ELSIF flowSP < 0.0 THEN
        flowSP := 0.0;
    END_IF;
    
    // 抗积分饱和回算
    accT := flowSP - 1.0 * eT;
    
    // 更新eF(因为flowSP已变)
    eF := flowSP - flowPV;
    
    // 内环PI计算(mode=1或mode=2)
    IF mode = 1 OR mode = 2 THEN
        trialF := accF + 0.5 * eF * scanSeconds;
        valveCommand := 2.0 * eF + trialF;
        
        // 内环限幅
        IF valveCommand > 100.0 THEN
            valveCommand := 100.0;
        ELSIF valveCommand < 0.0 THEN
            valveCommand := 0.0;
        END_IF;
        
        // 抗积分饱和回算
        accF := valveCommand - 2.0 * eF;
    END_IF;
    
    // mode=0时手动控制
    IF mode = 0 THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
    END_IF;
    
    // mode=1时流量设定跟随手动
    IF mode = 1 THEN
        flowSP := manualFlowSP;
    END_IF;
    
ELSE
    // prevNormalMode=FALSE时保持输出不变(用于normalMode计算)
    flowSP := prevFlowSP;
    valveCommand := prevValveCommand;
END_IF;

// 更新历史状态
prevResetBtn := resetBtn;
prevMode := mode;
prevFlowSP := flowSP;
prevValveCommand := valveCommand;
prevNormalMode := normalMode;

END_FUNCTION_BLOCK