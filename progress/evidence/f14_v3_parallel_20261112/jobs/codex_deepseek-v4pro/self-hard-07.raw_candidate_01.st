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
    initDone : BOOL := FALSE;
    prevMode : INT := 0;
    prevReset : BOOL := FALSE;
    prevFlowSP : REAL := 0.0;
    prevValveCommand : REAL := 0.0;
    accT : REAL := 0.0;
    accF : REAL := 0.0;
    tempError : REAL;
    flowError : REAL;
    trialT : REAL;
    trialF : REAL;
    rawFlow : REAL;
    rawValve : REAL;
    modeChanged : BOOL;
    resetRise : BOOL;
END_VAR

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
resetRise := resetBtn AND NOT prevReset;
normalMode := FALSE;

IF NOT initDone THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    tempError := tempSP - tempPV;
    accT := flowSP - 1.0 * tempError;
    flowError := flowSP - flowPV;
    accF := valveCommand - 2.0 * flowError;
ELSE
    modeChanged := mode <> prevMode;

    IF resetRise THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        tempError := tempSP - tempPV;
        accT := flowSP - 1.0 * tempError;
        flowError := flowSP - flowPV;
        accF := valveCommand - 2.0 * flowError;
    ELSIF fault THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        tempError := tempSP - tempPV;
        accT := flowSP - 1.0 * tempError;
        flowError := flowSP - flowPV;
        accF := valveCommand - 2.0 * flowError;
    ELSIF modeChanged THEN
        IF mode = 2 THEN
            flowSP := prevFlowSP;
            valveCommand := prevValveCommand;
            tempError := tempSP - tempPV;
            accT := flowSP - 1.0 * tempError;
            flowError := flowSP - flowPV;
            accF := valveCommand - 2.0 * flowError;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := prevValveCommand;
            tempError := tempSP - tempPV;
            accT := flowSP - 1.0 * tempError;
            flowError := flowSP - flowPV;
            accF := valveCommand - 2.0 * flowError;
        END_IF
    ELSE
        normalMode := TRUE;
        IF mode = 0 THEN
            flowSP := manualFlowSP;
            valveCommand := manualValve;
            tempError := tempSP - tempPV;
            accT := flowSP - 1.0 * tempError;
            flowError := flowSP - flowPV;
            accF := valveCommand - 2.0 * flowError;
        ELSIF mode = 1 THEN
            flowSP := manualFlowSP;
            flowError := flowSP - flowPV;
            trialF := accF + 0.5 * flowError * scanSeconds;
            rawValve := 2.0 * flowError + trialF;
            IF rawValve < 0.0 THEN
                valveCommand := 0.0;
            ELSIF rawValve > 100.0 THEN
                valveCommand := 100.0;
            ELSE
                valveCommand := rawValve;
            END_IF
            accF := valveCommand - 2.0 * flowError;
            tempError := tempSP - tempPV;
            accT := flowSP - 1.0 * tempError;
        ELSE
            tempError := tempSP - tempPV;
            trialT := accT + 0.2 * tempError * scanSeconds;
            rawFlow := 1.0 * tempError + trialT;
            IF rawFlow < 0.0 THEN
                flowSP := 0.0;
            ELSIF rawFlow > 50.0 THEN
                flowSP := 50.0;
            ELSE
                flowSP := rawFlow;
            END_IF
            accT := flowSP - 1.0 * tempError;

            flowError := flowSP - flowPV;
            trialF := accF + 0.5 * flowError * scanSeconds;
            rawValve := 2.0 * flowError + trialF;
            IF rawValve < 0.0 THEN
                valveCommand := 0.0;
            ELSIF rawValve > 100.0 THEN
                valveCommand := 100.0;
            ELSE
                valveCommand := rawValve;
            END_IF
            accF := valveCommand - 2.0 * flowError;
        END_IF
    END_IF
END_IF

prevMode := mode;
prevReset := resetBtn;
prevFlowSP := flowSP;
prevValveCommand := valveCommand;
initDone := TRUE;
END_FUNCTION_BLOCK