FUNCTION_BLOCK FB
VAR_INPUT
    enable         : BOOL;
    resetBtn       : BOOL;
    scanSeconds    : LREAL;
    steamFlow      : LREAL;
    fuelFlow       : LREAL;
    steamTemp      : LREAL;
    steamPressure  : LREAL;
END_VAR
VAR_OUTPUT
    qualified      : BOOL;
    dataFault      : BOOL;
    qualifiedTon   : LREAL;
    fuelTon        : LREAL;
    revenue        : LREAL;
    cost           : LREAL;
    netProfit      : LREAL;
END_VAR
VAR
    prevResetBtn   : BOOL := FALSE;
END_VAR

// Detect rising edge of reset button
IF resetBtn AND NOT prevResetBtn THEN
    qualifiedTon := 0.0;
    fuelTon      := 0.0;
END_IF

// Check qualified criteria (closed interval)
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0) AND
             (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

// Check data fault criteria
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0) OR
             (steamFlow < 0.0) OR (steamFlow > 90.0) OR
             (fuelFlow < 0.0) OR (fuelFlow > 6.0);

// Accumulation logic (only when not rising edge, enabled, and no fault)
IF enable AND NOT dataFault AND NOT (resetBtn AND NOT prevResetBtn) THEN
    // Fuel accumulation (always when enabled and no fault)
    fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
    
    // Qualified steam accumulation (only when qualified)
    IF qualified THEN
        qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
    END_IF
END_IF;

// Revenue, cost, and net profit update every scan
revenue   := qualifiedTon * 280.0;
cost      := fuelTon * 1500.0;
netProfit := revenue - cost;

// Update previous reset button state for next scan
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK