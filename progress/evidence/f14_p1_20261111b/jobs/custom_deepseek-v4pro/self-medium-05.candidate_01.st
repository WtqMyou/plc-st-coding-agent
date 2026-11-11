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
    prevReset : BOOL := FALSE;
    qAcc : LREAL := 0.0;
    fAcc : LREAL := 0.0;
END_VAR

qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0) AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0) OR (steamFlow < 0.0) OR (steamFlow > 90.0) OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

IF resetBtn AND NOT prevReset THEN
    qAcc := 0.0;
    fAcc := 0.0;
ELSE
    IF enable AND NOT dataFault THEN
        fAcc := fAcc + (fuelFlow * scanSeconds / 1000.0);
        IF qualified THEN
            qAcc := qAcc + (steamFlow * scanSeconds / 1000.0);
        END_IF;
    END_IF;
END_IF;

qualifiedTon := qAcc;
fuelTon := fAcc;
revenue := qAcc * 280.0;
cost := fAcc * 1500.0;
netProfit := revenue - cost;

prevReset := resetBtn;
END_FUNCTION_BLOCK