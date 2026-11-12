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
    prevResetBtn     : BOOL := FALSE;
    prevQualifiedTon : LREAL := 0.0;
    prevFuelTon      : LREAL := 0.0;
END_VAR

// Determine qualified status (closed interval)
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0) AND
             (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

// Determine data fault status
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0) OR
             (steamFlow < 0.0) OR (steamFlow > 90.0) OR
             (fuelFlow < 0.0) OR (fuelFlow > 6.0);

// Store previous cycle values for formula verification
prevQualifiedTon := qualifiedTon;
prevFuelTon := fuelTon;

// Reset rising edge takes priority over fault freeze
IF resetBtn AND NOT prevResetBtn THEN
    qualifiedTon := 0.0;
    fuelTon := 0.0;
ELSIF enable AND NOT dataFault THEN
    qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
    fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
ELSE
    qualifiedTon := qualifiedTon;
    fuelTon := fuelTon;
END_IF;

// Update previous reset state for next cycle edge detection
prevResetBtn := resetBtn;

// Revenue, cost, and net profit updated every scan
revenue := qualifiedTon * 280.0;
cost := fuelTon * 1500.0;
netProfit := revenue - cost;

END_FUNCTION_BLOCK