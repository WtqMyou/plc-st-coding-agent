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
    prevResetBtn        : BOOL := FALSE;
    prevMode            : INT := 999;
    firstCycle          : BOOL := TRUE;
    initialized         : BOOL := FALSE;
    accT                : REAL := 0.0;
    accF                : REAL := 0.0;
    prevTempSP          : REAL := 0.0;
    prevTempPV          : REAL := 0.0;
    prevFlowSP          : REAL := 0.0;
    prevValveCommand    : REAL := 0.0;
END_VAR

VAR
    eT      : REAL;
    eF      : REAL;
    trial   : REAL;
END_VAR

eT := tempSP - tempPV;
eF := flowSP - flowPV;

IF firstCycle THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    firstCycle := FALSE;
    initialized := TRUE;
    normalMode := FALSE;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevTempSP := tempSP;
    prevTempPV := tempPV;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    RETURN;
END_IF;

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF resetBtn AND NOT prevResetBtn THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevTempSP := tempSP;
    prevTempPV := tempPV;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    RETURN;
END_IF;

IF fault THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevTempSP := tempSP;
    prevTempPV := tempPV;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    RETURN;
END_IF;

IF mode <> prevMode THEN
    IF mode = 2 THEN
        flowSP := prevFlowSP;
        valveCommand := prevValveCommand;
    ELSE
        flowSP := manualFlowSP;
    END_IF;
    normalMode := FALSE;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevTempSP := tempSP;
    prevTempPV := tempPV;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    RETURN;
END_IF;

normalMode := TRUE;

trial := accT + 0.2 * eT * scanSeconds;
flowSP := LIMIT(0.0, 1.0 * eT + trial, 50.0);
accT := flowSP - 1.0 * eT;

trial := accF + 0.5 * eF * scanSeconds;
valveCommand := LIMIT(0.0, 2.0 * eF + trial, 100.0);
accF := valveCommand - 2.0 * eF;

prevTempSP := tempSP;
prevTempPV := tempPV;
prevFlowSP := flowSP;
prevValveCommand := valveCommand;
prevResetBtn := resetBtn;
prevMode := mode;
END_FUNCTION_BLOCK