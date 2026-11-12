FUNCTION_BLOCK FB
VAR_INPUT
    enable        : BOOL;
    resetBtn      : BOOL;
    scanSeconds   : LREAL;
    steamFlow     : LREAL;
    fuelFlow      : LREAL;
    steamTemp     : LREAL;
    steamPressure : LREAL;
END_VAR

VAR_OUTPUT
    qualified    : BOOL;
    dataFault    : BOOL;
    qualifiedTon : LREAL;
    fuelTon      : LREAL;
    revenue      : LREAL;
    cost         : LREAL;
    netProfit    : LREAL;
END_VAR

VAR
    prevResetBtn : BOOL := FALSE;
END_VAR

// Data fault: scanSeconds not in (0,10] or flows out of range
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0) OR
             (steamFlow < 0.0) OR (steamFlow > 90.0) OR
             (fuelFlow < 0.0) OR (fuelFlow > 6.0);

// Qualified: steamTemp in [446,453] AND steamPressure in [3750,3850]
qualified := (steamTemp >= 446.0) AND (steamTemp <= 453.0) AND
             (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

// Reset rising edge takes priority - clear and skip accumulation
IF resetBtn AND NOT prevResetBtn THEN
    qualifiedTon := 0.0;
    fuelTon := 0.0;
ELSIF enable AND NOT dataFault THEN
    // Fuel accumulates whenever enabled and no fault
    fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
    // Qualified steam accumulates only when qualified
    IF qualified THEN
        qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
    END_IF;
END_IF;

// Store reset state for edge detection
prevResetBtn := resetBtn;

// Revenue, cost, netProfit updated every scan
revenue := qualifiedTon * 280.0;
cost := fuelTon * 1500.0;
netProfit := revenue - cost;

END_FUNCTION_BLOCK