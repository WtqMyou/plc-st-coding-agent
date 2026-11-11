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
    risingReset : BOOL;
    prevResetBtn : BOOL := FALSE;
END_VAR

qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0) AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
             OR (steamFlow < 0.0) OR (steamFlow > 90.0)
             OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

risingReset := resetBtn AND NOT prevResetBtn;

IF risingReset THEN
    qualifiedTon := 0.0;
    fuelTon := 0.0;
ELSIF enable AND NOT dataFault THEN
    fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
    IF qualified THEN
        qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
    END_IF;
END_IF;

revenue := qualifiedTon * 280.0;
cost := fuelTon * 1500.0;
netProfit := revenue - cost;

prevResetBtn := resetBtn;

END_FUNCTION_BLOCK