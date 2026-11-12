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
    accT            : REAL;
    accF            : REAL;
    firstScan       : BOOL;
    modeChanged     : BOOL;
END_VAR

    modeChanged := (mode <> prevMode);
    fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

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
        RETURN;
    END_IF;

    IF resetBtn AND NOT prevResetBtn THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        accT := 0.0;
        accF := 0.0;
        normalMode := FALSE;
        prevMode := mode;
        prevResetBtn := resetBtn;
        prevFlowSP := flowSP;
        prevValveCmd := valveCommand;
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
        prevFlowSP := flowSP;
        prevValveCmd := valveCommand;
        RETURN;
    END_IF;

    IF modeChanged THEN
        IF mode = 2 THEN
            flowSP := prevFlowSP;
            valveCommand := prevValveCmd;
        ELSIF mode = 0 THEN
            flowSP := manualFlowSP;
            valveCommand := manualValve;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := prevValveCmd;
        END_IF;
        normalMode := FALSE;
        prevMode := mode;
        prevResetBtn := resetBtn;
        prevFlowSP := flowSP;
        prevValveCmd := valveCommand;
        RETURN;
    END_IF;

    normalMode := TRUE;

    IF mode = 2 THEN
        accT := accT + 0.2 * (tempSP - tempPV) * scanSeconds;
        flowSP := 1.0 * (tempSP - tempPV) + accT;
        flowSP := LIMIT(0.0, flowSP, 50.0);
        accT := flowSP - 1.0 * (tempSP - tempPV);
        accF := accF + 0.5 * (flowSP - flowPV) * scanSeconds;
        valveCommand := 2.0 * (flowSP - flowPV) + accF;
        valveCommand := LIMIT(0.0, valveCommand, 100.0);
        accF := valveCommand - 2.0 * (flowSP - flowPV);
    ELSIF mode = 1 THEN
        flowSP := manualFlowSP;
        accF := accF + 0.5 * (flowSP - flowPV) * scanSeconds;
        valveCommand := 2.0 * (flowSP - flowPV) + accF;
        valveCommand := LIMIT(0.0, valveCommand, 100.0);
        accF := valveCommand - 2.0 * (flowSP - flowPV);
    ELSE
        flowSP := manualFlowSP;
        valveCommand := manualValve;
    END_IF;

    prevMode := mode;
    prevResetBtn := resetBtn;
    prevFlowSP := flowSP;
    prevValveCmd := valveCommand;

END_FUNCTION_BLOCK