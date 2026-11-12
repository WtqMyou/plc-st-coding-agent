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
    prevResetBtn : BOOL;
    resetRising : BOOL;
    tonAccQualified : LREAL;
    tonAccFuel : LREAL;
END_VAR

resetRising := resetBtn AND NOT prevResetBtn;

qualified := steamTemp >= 447.0 AND steamTemp <= 453.0 AND steamPressure >= 3750.0 AND steamPressure <= 3850.0;

dataFault := scanSeconds <= 0.0 OR scanSeconds > 10.0 OR steamFlow < 0.0 OR steamFlow > 90.0 OR fuelFlow < 0.0 OR fuelFlow > 6.0;

IF resetRising THEN
    tonAccQualified := 0.0;
    tonAccFuel := 0.0;
ELSIF enable AND NOT dataFault THEN
    tonAccFuel := tonAccFuel + fuelFlow * scanSeconds / 1000.0;
    IF qualified THEN
        tonAccQualified := tonAccQualified + steamFlow * scanSeconds / 1000.0;
    END_IF
END_IF

qualifiedTon := tonAccQualified;
fuelTon := tonAccFuel;
revenue := tonAccQualified * 280.0;
cost := tonAccFuel * 1500.0;
netProfit := revenue - cost;

prevResetBtn := resetBtn;

END_FUNCTION_BLOCK