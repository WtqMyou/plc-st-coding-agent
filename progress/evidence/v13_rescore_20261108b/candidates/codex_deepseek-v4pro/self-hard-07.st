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
    initialized : BOOL;
    prevMode : INT;
    prevReset : BOOL;
    prevFlowSP : REAL;
    prevValveCommand : REAL;

    resetRising : BOOL;
    modeChanged : BOOL;
    outerIntegral : REAL;
    innerIntegral : REAL;
    tempError : REAL;
    flowError : REAL;
    rawOutput : REAL;
END_VAR

fault := (mode < 0) OR (mode > 2)
         OR (scanSeconds <= 0.0)
         OR (scanSeconds > 10.0);

resetRising := resetBtn AND (NOT prevReset);

IF NOT initialized THEN
    normalMode := FALSE;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    outerIntegral := flowSP - 1.0 * (tempSP - tempPV);
    innerIntegral := valveCommand - 2.0 * (flowSP - flowPV);
ELSIF fault THEN
    normalMode := FALSE;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    outerIntegral := flowSP - 1.0 * (tempSP - tempPV);
    innerIntegral := valveCommand - 2.0 * (flowSP - flowPV);
ELSIF resetRising THEN
    normalMode := FALSE;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    outerIntegral := flowSP - 1.0 * (tempSP - tempPV);
    innerIntegral := valveCommand - 2.0 * (flowSP - flowPV);
ELSE
    modeChanged := mode <> prevMode;

    IF modeChanged THEN
        normalMode := FALSE;
        valveCommand := prevValveCommand;

        IF mode = 2 THEN
            flowSP := prevFlowSP;
        ELSE
            flowSP := manualFlowSP;
        END_IF;

        outerIntegral := flowSP - 1.0 * (tempSP - tempPV);
        innerIntegral := valveCommand - 2.0 * (flowSP - flowPV);
    ELSE
        normalMode := TRUE;

        IF mode = 0 THEN
            flowSP := manualFlowSP;
            valveCommand := manualValve;
            outerIntegral := flowSP - 1.0 * (tempSP - tempPV);
            innerIntegral := valveCommand - 2.0 * (flowSP - flowPV);
        ELSIF mode = 1 THEN
            flowSP := manualFlowSP;
            outerIntegral := flowSP - 1.0 * (tempSP - tempPV);

            flowError := flowSP - flowPV;
            innerIntegral := innerIntegral + 0.5 * flowError * scanSeconds;
            rawOutput := 2.0 * flowError + innerIntegral;

            IF rawOutput < 0.0 THEN
                valveCommand := 0.0;
            ELSIF rawOutput > 100.0 THEN
                valveCommand := 100.0;
            ELSE
                valveCommand := rawOutput;
            END_IF;

            innerIntegral := valveCommand - 2.0 * flowError;
        ELSE
            tempError := tempSP - tempPV;
            outerIntegral := outerIntegral + 0.2 * tempError * scanSeconds;
            rawOutput := 1.0 * tempError + outerIntegral;

            IF rawOutput < 0.0 THEN
                flowSP := 0.0;
            ELSIF rawOutput > 50.0 THEN
                flowSP := 50.0;
            ELSE
                flowSP := rawOutput;
            END_IF;

            outerIntegral := flowSP - 1.0 * tempError;

            flowError := flowSP - flowPV;
            innerIntegral := innerIntegral + 0.5 * flowError * scanSeconds;
            rawOutput := 2.0 * flowError + innerIntegral;

            IF rawOutput < 0.0 THEN
                valveCommand := 0.0;
            ELSIF rawOutput > 100.0 THEN
                valveCommand := 100.0;
            ELSE
                valveCommand := rawOutput;
            END_IF;

            innerIntegral := valveCommand - 2.0 * flowError;
        END_IF;
    END_IF;
END_IF;

prevFlowSP := flowSP;
prevValveCommand := valveCommand;
prevMode := mode;
prevReset := resetBtn;
initialized := TRUE;

END_FUNCTION_BLOCK