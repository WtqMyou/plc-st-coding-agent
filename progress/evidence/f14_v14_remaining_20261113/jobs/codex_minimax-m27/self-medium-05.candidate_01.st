(*
ENGINEERING_CONTRACT
================================================================================
| Output/State    | Activation          | Retention        | Reset/Deactivation | Units        |
|-----------------|---------------------|------------------|---------------------|--------------|
| qualified       | Temp∈[447,453]∧Pres∈[3750,3850] | N/A (combinational) | N/A               | Boolean      |
| dataFault       | scanSeconds∉(0,10]∨Flow∉[0,90/6] | N/A (combinational) | N/A               | Boolean      |
| qualifiedTon    | enable∧qualified∧¬fault | Hold on fault/¬enable | resetBtn rising edge | tonnes (t)   |
| fuelTon         | enable∧¬fault        | Hold on fault/¬enable | resetBtn rising edge | tonnes (t)   |
| revenue         | = qualifiedTon*280  | Derived every scan  | resetBtn rising edge | yuan (元)     |
| cost            | = fuelTon*1500      | Derived every scan  | resetBtn rising edge | yuan (元)     |
| netProfit       | = revenue-cost      | Derived every scan  | N/A (may be <0)     | yuan (元)     |
--------------------------------------------------------------------------------
Priority: resetBtn rising edge > fault freeze (same-scan: reset clears accumulators)
Interval: scanSeconds ∈ (0,10] (inclusive upper bound 10.0; >10.0 is fault)
================================================================================
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    enable       : BOOL;
    resetBtn     : BOOL;
    scanSeconds  : LREAL;
    steamFlow    : LREAL;
    fuelFlow     : LREAL;
    steamTemp    : LREAL;
    steamPressure: LREAL;
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
    tmp_PrevResetBtn   : BOOL := FALSE;
    tmp_ResetRising    : BOOL;
    local_QualifiedTon : LREAL := 0.0;
    local_FuelTon      : LREAL := 0.0;
END_VAR

// Detect rising edge of resetBtn
tmp_ResetRising := resetBtn AND NOT tmp_PrevResetBtn;

// Data fault detection: scanSeconds not in (0,10] OR flows out of range
dataFault := (scanSeconds <= 0.0) OR (scanSeconds > 10.0)
             OR (steamFlow < 0.0) OR (steamFlow > 90.0)
             OR (fuelFlow < 0.0) OR (fuelFlow > 6.0);

// Qualified detection: closed interval [447,453] for temp and [3750,3850] for pressure
qualified := (steamTemp >= 447.0) AND (steamTemp <= 453.0)
             AND (steamPressure >= 3750.0) AND (steamPressure <= 3850.0);

// Reset: rising edge of resetBtn takes priority; clear accumulators and skip accumulation
IF tmp_ResetRising THEN
    local_QualifiedTon := 0.0;
    local_FuelTon      := 0.0;
ELSE
    // Accumulate qualified steam: only when qualified, enabled, and no fault
    IF qualified AND enable AND NOT dataFault THEN
        local_QualifiedTon := local_QualifiedTon + (steamFlow * scanSeconds / 1000.0);
    END_IF;
    
    // Accumulate fuel: whenever enabled and no fault (regardless of qualified status)
    IF enable AND NOT dataFault THEN
        local_FuelTon := local_FuelTon + (fuelFlow * scanSeconds / 1000.0);
    END_IF;
END_IF;

// Update outputs
qualifiedTon := local_QualifiedTon;
fuelTon      := local_FuelTon;
revenue      := qualifiedTon * 280.0;
cost         := fuelTon * 1500.0;
netProfit    := revenue - cost;

// Update previous state for next scan edge detection
tmp_PrevResetBtn := resetBtn;

END_FUNCTION_BLOCK