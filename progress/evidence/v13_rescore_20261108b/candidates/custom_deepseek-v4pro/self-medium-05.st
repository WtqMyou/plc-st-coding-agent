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
    accQualifiedTon : LREAL := 0.0;
    accFuelTon : LREAL := 0.0;
    resetEdge : BOOL;
    canAccumulate : BOOL;
END_VAR

qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0) AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0) OR (steamFlow < 0.0) OR (steamFlow > 90.0) OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

resetEdge := resetBtn AND (NOT prevReset);
prevReset := resetBtn;

IF resetEdge THEN
    accQualifiedTon := 0.0;
    accFuelTon := 0.0;
ELSE
    canAccumulate := enable AND (NOT dataFault);
    IF canAccumulate THEN
        accFuelTon := accFuelTon + (fuelFlow * scanSeconds / 1000.0);
        IF qualified THEN
            accQualifiedTon := accQualifiedTon + (steamFlow * scanSeconds / 1000.0);
        END_IF
    END_IF
END_IF

qualifiedTon := accQualifiedTon;
fuelTon := accFuelTon;
revenue := accQualifiedTon * 280.0;
cost := accFuelTon * 1500.0;
netProfit := revenue - cost;
END_FUNCTION_BLOCK