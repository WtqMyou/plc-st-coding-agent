FUNCTION_BLOCK FB
VAR_INPUT
    mode : INT;
    resetBtn : BOOL;
    scanSeconds : REAL;
    tempSP : REAL;
    tempPV : REAL;
    flowPV : REAL;
    manualFlowSP : REAL;
    manualValve : REAL;
END_VAR

VAR_OUTPUT
    flowSP : REAL;
    valveCommand : REAL;
    fault : BOOL;
    normalMode : BOOL;
END_VAR

VAR
    firstScan : BOOL := TRUE;
    prevMode : INT := 0;
    prevResetBtn : BOOL := FALSE;
    prevFlowSP : REAL := 0.0;
    prevValveCommand : REAL := 0.0;
    prevET : REAL := 0.0;
    prevEF : REAL := 0.0;
    resetRising : BOOL;
    modeChanged : BOOL;
    eT : REAL;
    eF : REAL;
END_VAR

    fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
    resetRising := resetBtn AND NOT prevResetBtn;
    modeChanged := (NOT firstScan) AND (mode <> prevMode);
    normalMode := (NOT firstScan) AND (mode = prevMode) AND (NOT fault) AND (NOT resetRising);

    eT := tempSP - tempPV;

    IF fault THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
    ELSIF firstScan THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
    ELSIF resetRising THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
    ELSIF modeChanged THEN
        IF mode = 2 THEN
            flowSP := prevFlowSP;
            valveCommand := prevValveCommand;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := prevValveCommand;
        END_IF;
    ELSE
        CASE mode OF
            0:
                flowSP := manualFlowSP;
                valveCommand := manualValve;

            1:
                flowSP := manualFlowSP;
                eF := flowSP - flowPV;
                valveCommand := LIMIT(0.0,
                    2.0 * eF + ((prevValveCommand - 2.0 * prevEF) + 0.5 * eF * scanSeconds),
                    100.0);

            2:
                flowSP := LIMIT(0.0,
                    1.0 * eT + ((prevFlowSP - 1.0 * prevET) + 0.2 * eT * scanSeconds),
                    50.0);
                eF := flowSP - flowPV;
                valveCommand := LIMIT(0.0,
                    2.0 * eF + ((prevValveCommand - 2.0 * prevEF) + 0.5 * eF * scanSeconds),
                    100.0);

            ELSE
                flowSP := manualFlowSP;
                valveCommand := manualValve;
        END_CASE;
    END_IF;

    prevResetBtn := resetBtn;
    prevMode := mode;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
    prevET := eT;
    prevEF := flowSP - flowPV;
    firstScan := FALSE;
END_FUNCTION_BLOCK