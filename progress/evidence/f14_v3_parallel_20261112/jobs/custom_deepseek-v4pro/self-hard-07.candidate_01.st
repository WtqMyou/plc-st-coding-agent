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
    hasPrev : BOOL := FALSE;
    prevMode : INT := 0;
    prevReset : BOOL := FALSE;
    prevFlowSP : REAL := 0.0;
    prevValveCommand : REAL := 0.0;
    prevET : REAL := 0.0;
    prevEF : REAL := 0.0;
    resetRising : BOOL;
    eT : REAL;
    eF : REAL;
    flowRaw : REAL;
    valveRaw : REAL;
    trialT : REAL;
    trialF : REAL;
END_VAR

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
resetRising := resetBtn AND NOT prevReset;

IF NOT hasPrev THEN
    normalMode := FALSE;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF resetRising THEN
    normalMode := FALSE;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF fault THEN
    normalMode := FALSE;
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF mode <> prevMode THEN
    normalMode := FALSE;
    IF mode = 2 THEN
        flowSP := prevFlowSP;
        valveCommand := prevValveCommand;
    ELSE
        flowSP := manualFlowSP;
        valveCommand := prevValveCommand;
    END_IF;
ELSE
    normalMode := TRUE;
    IF mode = 0 THEN
        flowSP := manualFlowSP;
        valveCommand := manualValve;
    ELSIF mode = 1 THEN
        flowSP := manualFlowSP;
        eF := flowSP - flowPV;
        trialF := prevValveCommand - 2.0 * prevEF + 0.5 * eF * scanSeconds;
        valveRaw := 2.0 * eF + trialF;
        valveCommand := LIMIT(0.0, valveRaw, 100.0);
    ELSIF mode = 2 THEN
        eT := tempSP - tempPV;
        trialT := prevFlowSP - 1.0 * prevET + 0.2 * eT * scanSeconds;
        flowRaw := 1.0 * eT + trialT;
        flowSP := LIMIT(0.0, flowRaw, 50.0);
        eF := flowSP - flowPV;
        trialF := prevValveCommand - 2.0 * prevEF + 0.5 * eF * scanSeconds;
        valveRaw := 2.0 * eF + trialF;
        valveCommand := LIMIT(0.0, valveRaw, 100.0);
    END_IF;
END_IF;

prevFlowSP := flowSP;
prevValveCommand := valveCommand;
prevET := tempSP - tempPV;
prevEF := flowSP - flowPV;
prevMode := mode;
prevReset := resetBtn;
hasPrev := TRUE;

END_FUNCTION_BLOCK