FUNCTION_BLOCK FB
VAR_INPUT
    enable       : BOOL;
    resetBtn     : BOOL;
    scanSeconds  : LREAL;  // renamed from dt, unit: s
    steamFlow    : LREAL;  // kg/s, valid range [0, 90]
    fuelFlow     : LREAL;  // kg/s, valid range [0, 6]
    steamTemp    : LREAL;  // °C, qualified [447, 453]
    steamPressure: LREAL;  // kPa, qualified [3750, 3850]
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

// Detect rising edge of resetBtn (edge-triggered, not level-triggered)
VAR_TEMP
    risingReset : BOOL;
END_VAR

risingReset := resetBtn AND NOT prevResetBtn;

// Data fault: invalid scan time or out-of-range flow values
dataFault := (scanSeconds <= 0.0 OR scanSeconds > 10.0 OR
              steamFlow < 0.0 OR steamFlow > 90.0 OR
              fuelFlow < 0.0 OR fuelFlow > 6.0);

// Qualified: closed interval [447, 453] °C and [3750, 3850] kPa
qualified := (steamTemp >= 447.0 AND steamTemp <= 453.0) AND
             (steamPressure >= 3750.0 AND steamPressure <= 3850.0);

// Accumulation with priority: reset > enable/fault-free
IF risingReset THEN
    // Reset takes priority; fault flag still reports but accumulators clear
    qualifiedTon := 0.0;
    fuelTon := 0.0;
ELSIF enable AND NOT dataFault THEN
    // Fuel: always accumulate when enabled and data valid
    fuelTon := fuelTon + fuelFlow * scanSeconds / 1000.0;
    // Qualified steam: only when qualified
    IF qualified THEN
        qualifiedTon := qualifiedTon + steamFlow * scanSeconds / 1000.0;
    END_IF;
END_IF;
// When disabled or faulted (without reset), accumulators hold previous values

// Financial calculations (update every scan regardless of accumulation)
revenue   := qualifiedTon * 280.0;  // yuan/t steam
cost      := fuelTon * 1500.0;      // yuan/t fuel
netProfit := revenue - cost;        // may be negative

// Update edge-detection state for next cycle
prevResetBtn := resetBtn;

END_FUNCTION_BLOCK