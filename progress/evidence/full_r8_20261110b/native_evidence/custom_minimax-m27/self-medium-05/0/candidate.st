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
    risingReset    : BOOL;
END_VAR

// Detect rising edge of reset button
risingReset := resetBtn AND NOT prevResetBtn;

// Determine if steam is qualified (closed interval)
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0) AND
             (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

// Determine data fault condition
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0) OR
             (steamFlow < 0.0) OR (steamFlow > 90.0) OR
             (fuelFlow < 0.0) OR (fuelFlow > 6.0);

// Reset action: clear accumulators and suppress accumulation for this scan
IF risingReset THEN
    qualifiedTon := 0.0;
    fuelTon      := 0.0;
ELSE
    // Fuel consumption accumulation (if enabled and no fault)
    IF enable AND NOT dataFault THEN
        fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
    END_IF

    // Qualified steam production accumulation (if enabled, no fault, and qualified)
    IF enable AND NOT dataFault AND qualified THEN
        qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
    END_IF
END_IF

// Update monetary values each scan
revenue   := qualifiedTon * 280.0;
cost      := fuelTon * 1500.0;
netProfit := revenue - cost;

// Store reset button state for next scan edge detection
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK