FUNCTION_BLOCK FB
VAR_INPUT
    mode            : INT;
    resetBtn        : BOOL;
    scanSeconds     : REAL;
    tempSP          : REAL;
    tempPV          : REAL;
    flowPV          : REAL;
    manualFlowSP    : REAL;
    manualValve     : REAL;
END_VAR
VAR_OUTPUT
    flowSP          : REAL;
    valveCommand    : REAL;
    fault           : BOOL;
    normalMode      : BOOL;
END_VAR
VAR
    accT            : REAL := 0.0;
    accF            : REAL := 0.0;
    prevFlowSP      : REAL := 0.0;
    prevValveCmd    : REAL := 0.0;
    firstScan       : BOOL := TRUE;
    prevMode        : INT  := 0;
    prevResetBtn    : BOOL := FALSE;
END_VAR

VAR
    resetRising : BOOL;
    modeChanged : BOOL;
    modeValid   : BOOL;
    scanValid   : BOOL;
    eT          : REAL;
    eF          : REAL;
    trialT      : REAL;
    trialF      : REAL;
END_VAR

    (* ---- 边沿检测 ---- *)
    resetRising := resetBtn AND NOT prevResetBtn;

    (* ---- 故障判定（模式越界或时基越界） ---- *)
    modeValid := (mode >= 0) AND (mode <= 2);
    scanValid := (scanSeconds > 0.0) AND (scanSeconds <= 10.0);
    fault := NOT modeValid OR NOT scanValid;

    (* ---- 首次扫描：输出初始化 ---- *)
    IF firstScan THEN
        flowSP       := manualFlowSP;
        valveCommand := manualValve;
        normalMode   := FALSE;
        accT         := manualFlowSP;
        accF         := manualValve;
        prevFlowSP   := manualFlowSP;
        prevValveCmd := manualValve;
        firstScan    := FALSE;

    (* ---- 复位上升沿优先：回到初值 ---- *)
    ELSIF resetRising THEN
        flowSP       := manualFlowSP;
        valveCommand := manualValve;
        normalMode   := FALSE;
        accT         := manualFlowSP;
        accF         := manualValve;
        prevFlowSP   := manualFlowSP;
        prevValveCmd := manualValve;

    (* ---- 故障：输出跟手动值，不积分 ---- *)
    ELSIF fault THEN
        normalMode := FALSE;
        (* outputs already held at previous values *)

    (* ---- 模式切换无扰判定 ---- *)
    ELSIF mode <> prevMode THEN
        normalMode   := FALSE;
        modeChanged  := TRUE;

        (* 切换到串级：两输出保持上一拍 *)
        IF mode = 2 THEN
            flowSP       := prevFlowSP;
            valveCommand := prevValveCmd;

        (* 切换到自动/手动：流量跟手操，阀位保持 *)
        ELSE
            flowSP       := manualFlowSP;
            valveCommand := prevValveCmd;
        END_IF

    (* ---- 正常稳态运算 ---- *)
    ELSE
        normalMode  := TRUE;
        modeChanged := FALSE;

        (* 串级模式：外环 PI → 流量设定，内环 PI → 阀位 *)
        IF mode = 2 THEN
            (* 外环：温度偏差 → 流量设定 *)
            eT     := tempSP - tempPV;
            trialT := accT + 0.2 * eT * scanSeconds;
            flowSP := LIMIT(0.0, 1.0 * eT + trialT, 50.0);
            accT   := trialT + (flowSP - 1.0 * eT) * scanSeconds;

            (* 内环：流量偏差 → 阀位（使用本拍 flowSP） *)
            eF     := flowSP - flowPV;
            trialF := accF + 0.5 * eF * scanSeconds;
            valveCommand := LIMIT(0.0, 2.0 * eF + trialF, 100.0);
            accF   := trialF + (valveCommand - 2.0 * eF) * scanSeconds;

        (* 自动模式：流量设定跟手操，内环 PI → 阀位 *)
        ELSIF mode = 1 THEN
            flowSP := manualFlowSP;

            (* 内环：流量偏差 → 阀位（使用本拍 flowSP） *)
            eF     := flowSP - flowPV;
            trialF := accF + 0.5 * eF * scanSeconds;
            valveCommand := LIMIT(0.0, 2.0 * eF + trialF, 100.0);
            accF   := trialF + (valveCommand - 2.0 * eF) * scanSeconds;

        (* 手动模式：两输出均跟手操值 ---- *)
        ELSE
            flowSP       := manualFlowSP;
            valveCommand := manualValve;
        END_IF
    END_IF

    (* ---- 历史状态更新 ---- *)
    prevMode     := mode;
    prevResetBtn := resetBtn;
    IF NOT fault AND NOT resetRising AND NOT firstScan THEN
        prevFlowSP   := flowSP;
        prevValveCmd := valveCommand;
    END_IF
END_FUNCTION_BLOCK