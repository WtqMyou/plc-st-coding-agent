FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    resetBtn : BOOL;
    scanSeconds : LREAL;
    steamFlow : LREAL;
    fuelFlow : LREAL;
    steamTemp : LREAL;
    steamPressure : LREAL;
END_VAR
VAR_OUTPUT
    qualified : BOOL;
    dataFault : BOOL;
    qualifiedTon : LREAL;
    fuelTon : LREAL;
    revenue : LREAL;
    cost : LREAL;
    netProfit : LREAL;
END_VAR
VAR
    lastResetBtn : BOOL;
    resetRising : BOOL;
END_VAR

// 合格判据：闭区间
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
             AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

// 数据故障判据
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
             OR (steamFlow < 0.0) OR (steamFlow > 90.0)
             OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

// 上升沿检测
resetRising := resetBtn AND NOT lastResetBtn;

// 复位优先：当拍清零且不累计
IF resetRising THEN
    qualifiedTon := 0.0;
    fuelTon := 0.0;
ELSE
    // 无复位沿时，仅在使能且无故障时累计
    IF enable AND NOT dataFault THEN
        IF qualified THEN
            qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
        END_IF
        fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
    END_IF
END_IF

// 金额计算（每拍更新）
revenue := qualifiedTon * 280.0;
cost := fuelTon * 1500.0;
netProfit := revenue - cost;

// 更新历史复位状态
lastResetBtn := resetBtn;

END_FUNCTION_BLOCK