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
    prevCalled : BOOL := FALSE;
    prevResetBtn : BOOL := FALSE;
    prevMode : INT := 0;
    prevFlowSP : REAL := 0.0;
    prevValveCommand : REAL := 0.0;
    prevTempError : REAL := 0.0;
    prevInnerError : REAL := 0.0;
    risingReset : BOOL;
    calcFlowSP : REAL;
    calcValve : REAL;
END_VAR

risingReset := resetBtn AND NOT prevResetBtn;

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

normalMode := prevCalled AND (mode = prevMode) AND NOT fault AND NOT risingReset;

IF risingReset THEN
    calcFlowSP := manualFlowSP;
    calcValve := manualValve;
ELSIF fault THEN
    calcFlowSP := manualFlowSP;
    calcValve := manualValve;
ELSIF NOT prevCalled THEN
    calcFlowSP := manualFlowSP;
    calcValve := manualValve;
ELSIF mode <> prevMode THEN
    IF mode = 2 THEN
        calcFlowSP := prevFlowSP;
        calcValve := prevValveCommand;
    ELSE
        calcFlowSP := manualFlowSP;
        calcValve := prevValveCommand;
    END_IF
ELSE
    IF mode = 0 THEN
        calcFlowSP := manualFlowSP;
        calcValve := manualValve;
    ELSIF mode = 1 THEN
        calcFlowSP := manualFlowSP;
        calcValve := LIMIT(0.0,
            2.0 * (calcFlowSP - flowPV)
            + (prevValveCommand - 2.0 * prevInnerError)
            + 0.5 * (calcFlowSP - flowPV) * scanSeconds,
            100.0);
    ELSE
        calcFlowSP := LIMIT(0.0,
            1.0 * (tempSP - tempPV)
            + (prevFlowSP - 1.0 * prevTempError)
            + 0.2 * (tempSP - tempPV) * scanSeconds,
            50.0);
        calcValve := LIMIT(0.0,
            2.0 * (calcFlowSP - flowPV)
            + (prevValveCommand - 2.0 * prevInnerError)
            + 0.5 * (calcFlowSP - flowPV) * scanSeconds,
            100.0);
    END_IF
END_IF

flowSP := calcFlowSP;
valveCommand := calcValve;

prevCalled := TRUE;
prevResetBtn := resetBtn;
prevMode := mode;
prevFlowSP := calcFlowSP;
prevValveCommand := calcValve;
prevTempError := tempSP - tempPV;
prevInnerError := calcFlowSP - flowPV;
END_FUNCTION_BLOCK