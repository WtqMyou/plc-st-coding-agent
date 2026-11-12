FUNCTION_BLOCK FB
VAR_INPUT
    mode            : INT;
    resetBtn        : BOOL;
    scanSeconds     : REAL;
    tempSP          : REAL;
    tempPV          : REAL;
    flowPV          : REAL;
    manualFlowSP    : REAL;
    manualValve     : REAL;
END_VAR

VAR_OUTPUT
    flowSP          : REAL;
    valveCommand    : REAL;
    fault           : BOOL;
    normalMode      : BOOL;
END_VAR

VAR
    prevMode            : INT := -1;
    prevResetBtn        : BOOL := FALSE;
    firstScan           : BOOL := TRUE;
    prevFlowSP          : REAL := 0.0;
    prevValveCommand    : REAL := 0.0;
    prevTempSP          : REAL := 0.0;
    prevFlowSP_inner    : REAL := 0.0;
    accT                : REAL := 0.0;
    accF                : REAL := 0.0;
    tmpModeSwitch       : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
================================================================================
OUTPUT STATE TABLE (per scan, evaluated in priority order):
--------------------------------------------------------------------------------
| State          | Activation        | Retention    | Reset/Deactivation      |
|----------------|-------------------|--------------|-------------------------|
| fault=TRUE     | mode∉{0,1,2} OR   | Hold (latch) | mode returns to 0/1/2   |
|                | scanSeconds≤0 OR  |              | AND scanSeconds valid   |
|                | scanSeconds>10    |              |                         |
| normalMode=TRUE| Mode stable, no   | Same-scan    | Any mode change, fault, |
|                | fault, no reset   | priority     | or reset rising edge    |
| flowSP         | PI output/bumpless| Hold in most | Reset/fault: manualFlowSP|
|                | transfer per mode | modes        | Switch to 0/1: manualSP |
| valveCommand   | PI output/manual  | Hold on      | Reset/fault: manualValve|
|                | per mode          | switch 0/1/2 | Switch 0/1: prev value  |
--------------------------------------------------------------------------------
CONTROLLER GAINS (per PUB003/PUB004):
  Outer loop (temp→flow): KpT=1.0 (t/h)/℃, KiT=0.2 (t/h)/(℃·s)
  Inner loop (flow→valve): KpF=2.0 %/(t/h), KiF=0.5 %/((t/h)·s)
UNITS/BOUNDARIES (PUB001/PUB002):
  flowSP: 0..50 t/h; valveCommand: 0..100 %
ANTI-WINDUP (PUB006): Back-calculation from clamped output
FIRST-SCAN (PUB049): Outputs preset to manual values, normalMode=FALSE
RESET PRIORITY (PUB051/PUB052/PUB053): Outputs/integrators preset; fault still
  reported based on current mode/scanSeconds
FAULT PRIORITY (PUB051/PUB052/PUB053): Immediate manual-follow, no integration;
  fault reported based on current mode/scanSeconds
================================================================================
*)

(* CONTRACT_RULES [] *)

tmpModeSwitch := (prevMode <> mode) AND NOT firstScan;

IF firstScan THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    prevMode := mode;
    firstScan := FALSE;
END_IF;

// PUB050: Fault detection - mode out of range or scanSeconds invalid
fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

// PUB051/PUB052/PUB053: Reset rising edge takes priority for outputs/integrators
IF resetBtn AND NOT prevResetBtn THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    prevResetBtn := TRUE;
    prevMode := mode;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    prevTempSP := tempSP;
    prevFlowSP_inner := flowSP;
    RETURN;
END_IF;
prevResetBtn := resetBtn;

// PUB052: Fault action - immediate manual-follow, integrator preset
IF fault THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
    prevMode := mode;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    prevTempSP := tempSP;
    prevFlowSP_inner := flowSP;
    RETURN;
END_IF;

// PUB054/PUB055/PUB056/PUB057/PUB058: Bumpless transfer on mode switch
IF tmpModeSwitch THEN
    normalMode := FALSE;
    // PUB054/PUB055: Switch to manual(0) or auto(1)
    IF (mode = 0) OR (mode = 1) THEN
        flowSP := manualFlowSP;
        // PUB057: Valve holds previous value
        valveCommand := prevValveCommand;
    // PUB056/PUB058: Switch to cascade(2)
    ELSIF mode = 2 THEN
        // PUB058: Both outputs hold previous values
        flowSP := prevFlowSP;
        valveCommand := prevValveCommand;
    END_IF;
ELSE
    // Normal operation - PI execution
    normalMode := TRUE;
    
    CASE mode OF
        0: // PUB059: Manual - both outputs follow manual
            flowSP := manualFlowSP;
            valveCommand := manualValve;
            
        1: // PUB059: Auto - flow manual, inner PI active
            flowSP := manualFlowSP;
            // Inner loop PI with anti-windup back-calculation
            accF := prevValveCommand - 2.0 * (prevFlowSP_inner - flowPV);
            valveCommand := LIMIT(0.0, 2.0 * (flowSP - flowPV) + accF + 0.5 * (flowSP - flowPV) * scanSeconds, 100.0);
            accF := valveCommand - 2.0 * (flowSP - flowPV);
            
        2: // PUB059: Cascade - both PI loops active
            // Outer loop PI (temperature → flow)
            accT := prevFlowSP - 1.0 * prevTempSP;
            flowSP := LIMIT(0.0, 1.0 * (tempSP - tempPV) + accT + 0.2 * (tempSP - tempPV) * scanSeconds, 50.0);
            accT := flowSP - 1.0 * (tempSP - tempPV);
            
            // Inner loop PI (flow → valve) using current flowSP
            accF := prevValveCommand - 2.0 * (prevFlowSP_inner - flowPV);
            valveCommand := LIMIT(0.0, 2.0 * (flowSP - flowPV) + accF + 0.5 * (flowSP - flowPV) * scanSeconds, 100.0);
            accF := valveCommand - 2.0 * (flowSP - flowPV);
    END_CASE;
END_IF;

// Update state for next scan
prevMode := mode;
prevFlowSP := flowSP;
prevValveCommand := valveCommand;
prevTempSP := tempSP;
prevFlowSP_inner := flowSP;

END_FUNCTION_BLOCK