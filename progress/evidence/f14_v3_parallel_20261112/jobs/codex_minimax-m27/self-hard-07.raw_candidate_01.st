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
    prevMode        : INT;
    prevResetBtn    : BOOL;
    prevFlowSP      : REAL;
    prevValveCmd    : REAL;
    prevTempSP      : REAL;
    accT            : REAL;
    accF            : REAL;
    firstScan       : BOOL;
END_VAR

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF resetBtn AND NOT prevResetBtn THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
    firstScan := FALSE;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevFlowSP := flowSP;
    prevValveCmd := valveCommand;
    prevTempSP := tempSP;
    RETURN;
END_IF

IF mode <> prevMode THEN
    IF mode = 2 THEN
        flowSP := prevFlowSP;
        valveCommand := prevValveCmd;
    ELSE
        flowSP := manualFlowSP;
        valveCommand := prevValveCmd;
    END_IF
    normalMode := FALSE;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevFlowSP := flowSP;
    prevValveCmd := valveCommand;
    prevTempSP := tempSP;
    RETURN;
END_IF

IF firstScan THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    accT := 0.0;
    accF := 0.0;
    normalMode := FALSE;
    firstScan := FALSE;
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevFlowSP := flowSP;
    prevValveCmd := valveCommand;
    prevTempSP := tempSP;
    RETURN;
END_IF

normalMode := TRUE;

IF mode = 2 THEN
    VAR eF AT%Q* : REAL; END_VAR
    eF := flowSP - flowPV;
    accF := accF + 0.5 * eF * scanSeconds;
    valveCommand := 2.0 * eF + accF;
    valveCommand := LIMIT(0.0, valveCommand, 100.0);
    accF := valveCommand - 2.0 * eF;

    VAR eT AT%Q* : REAL; END_VAR
    eT := tempSP - tempPV;
    accT := accT + 0.2 * eT * scanSeconds;
    flowSP := 1.0 * eT + accT;
    flowSP := LIMIT(0.0, flowSP, 50.0);
    accT := flowSP - 1.0 * eT;
ELSIF mode = 1 THEN
    VAR eF AT%Q* : REAL; END_VAR
    eF := flowSP - flowPV;
    accF := accF + 0.5 * eF * scanSeconds;
    valveCommand := 2.0 * eF + accF;
    valveCommand := LIMIT(0.0, valveCommand, 100.0);
    accF := valveCommand - 2.0 * eF;
ELSE
    flowSP := manualFlowSP;
    valveCommand := manualValve;
END_IF;

prevMode := mode;
prevResetBtn := resetBtn;
prevFlowSP := flowSP;
prevValveCmd := valveCommand;
prevTempSP := tempSP;

END_FUNCTION_BLOCK