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
    prevFlowSP      : REAL;
    prevValveCommand: REAL;
    prevResetBtn    : BOOL;
    firstScanDone   : BOOL;
    accT            : REAL;
    accF            : REAL;
END_VAR

VAR_TEMP
    isResetRising   : BOOL;
    isModeChange    : BOOL;
    eT              : REAL;
    eF              : REAL;
    trialT          : REAL;
    trialF          : REAL;
    flowSPLimit     : REAL;
    valveLimit      : REAL;
END_VAR

    isResetRising := resetBtn AND NOT prevResetBtn;
    isModeChange := firstScanDone AND (mode <> prevMode);

    fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

    IF isResetRising THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        accT := manualFlowSP - 1.0 * (tempSP - tempPV);
        accF := manualValve - 2.0 * (manualFlowSP - flowPV);
        normalMode := FALSE;
    ELSIF NOT firstScanDone THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        accT := manualFlowSP - 1.0 * (tempSP - tempPV);
        accF := manualValve - 2.0 * (manualFlowSP - flowPV);
        normalMode := FALSE;
    ELSIF fault THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        accT := manualFlowSP - 1.0 * (tempSP - tempPV);
        accF := manualValve - 2.0 * (manualFlowSP - flowPV);
        normalMode := FALSE;
    ELSIF isModeChange THEN
        IF mode = 2 THEN
            flowSP := prevFlowSP;
            valveCommand := prevValveCommand;
            eT := tempSP - tempPV;
            accT := flowSP - 1.0 * eT;
            eF := flowSP - flowPV;
            accF := valveCommand - 2.0 * eF;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := prevValveCommand;
            eT := tempSP - tempPV;
            accT := flowSP - 1.0 * eT;
            eF := flowSP - flowPV;
            accF := valveCommand - 2.0 * eF;
        END_IF;
        normalMode := FALSE;
    ELSE
        normalMode := TRUE;
        eT := tempSP - tempPV;
        eF := flowSP - flowPV;
        IF mode = 2 THEN
            trialT := accT + 0.2 * eT * scanSeconds;
            flowSPLimit := LIMIT(0.0, 1.0 * eT + trialT, 50.0);
            flowSP := flowSPLimit;
            accT := flowSP - 1.0 * eT;
            eF := flowSP - flowPV;
            trialF := accF + 0.5 * eF * scanSeconds;
            valveLimit := LIMIT(0.0, 2.0 * eF + trialF, 100.0);
            valveCommand := valveLimit;
            accF := valveCommand - 2.0 * eF;
        ELSIF mode = 1 THEN
            flowSP := manualFlowSP;
            eF := flowSP - flowPV;
            trialF := accF + 0.5 * eF * scanSeconds;
            valveLimit := LIMIT(0.0, 2.0 * eF + trialF, 100.0);
            valveCommand := valveLimit;
            accF := valveCommand - 2.0 * eF;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := manualValve;
            accF := valveCommand - 2.0 * eF;
        END_IF;
    END_IF;

    prevResetBtn := resetBtn;
    prevMode := mode;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    firstScanDone := TRUE;
END_FUNCTION_BLOCK