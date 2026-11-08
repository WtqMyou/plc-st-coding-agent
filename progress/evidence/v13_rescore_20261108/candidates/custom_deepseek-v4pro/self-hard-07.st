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
    prevResetBtn : BOOL := FALSE;
    lastMode : INT := 0;
    lastFlowSP : REAL := 0.0;
    lastValveCommand : REAL := 0.0;
    iT : REAL := 0.0;
    iF : REAL := 0.0;
    eT : REAL := 0.0;
    eF : REAL := 0.0;
END_VAR

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF firstScan THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    iT := flowSP - 1.0 * (tempSP - tempPV);
    iF := valveCommand - 2.0 * (flowSP - flowPV);
    lastMode := mode;
    lastFlowSP := flowSP;
    lastValveCommand := valveCommand;
    normalMode := FALSE;
    firstScan := FALSE;
ELSIF resetBtn AND NOT prevResetBtn THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    iT := flowSP - 1.0 * (tempSP - tempPV);
    iF := valveCommand - 2.0 * (flowSP - flowPV);
    lastMode := mode;
    lastFlowSP := flowSP;
    lastValveCommand := valveCommand;
    normalMode := FALSE;
ELSIF fault THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    iT := flowSP - 1.0 * (tempSP - tempPV);
    iF := valveCommand - 2.0 * (flowSP - flowPV);
    lastMode := mode;
    lastFlowSP := flowSP;
    lastValveCommand := valveCommand;
    normalMode := FALSE;
ELSE
    IF mode <> lastMode THEN
        (* 模式切换拍：阀位保持，流量设定按目标模式处理 *)
        valveCommand := lastValveCommand;
        IF mode = 2 THEN
            flowSP := lastFlowSP;
        ELSE
            flowSP := manualFlowSP;
        END_IF
        iT := flowSP - 1.0 * (tempSP - tempPV);
        iF := valveCommand - 2.0 * (flowSP - flowPV);
        normalMode := FALSE;
        lastMode := mode;
        lastFlowSP := flowSP;
        lastValveCommand := valveCommand;
    ELSE
        (* 正常运算拍 *)
        normalMode := TRUE;
        CASE mode OF
            0:
                flowSP := manualFlowSP;
                valveCommand := manualValve;
                iT := flowSP - 1.0 * (tempSP - tempPV);
                iF := valveCommand - 2.0 * (flowSP - flowPV);
            1:
                flowSP := manualFlowSP;
                iT := flowSP - 1.0 * (tempSP - tempPV);
                eF := flowSP - flowPV;
                iF := iF + 0.5 * eF * scanSeconds;
                valveCommand := LIMIT(0.0, 2.0 * eF + iF, 100.0);
                iF := valveCommand - 2.0 * eF;
            2:
                eT := tempSP - tempPV;
                iT := iT + 0.2 * eT * scanSeconds;
                flowSP := LIMIT(0.0, 1.0 * eT + iT, 50.0);
                iT := flowSP - 1.0 * eT;
                eF := flowSP - flowPV;
                iF := iF + 0.5 * eF * scanSeconds;
                valveCommand := LIMIT(0.0, 2.0 * eF + iF, 100.0);
                iF := valveCommand - 2.0 * eF;
        END_CASE
        lastMode := mode;
        lastFlowSP := flowSP;
        lastValveCommand := valveCommand;
    END_IF
END_IF

prevResetBtn := resetBtn;

END_FUNCTION_BLOCK