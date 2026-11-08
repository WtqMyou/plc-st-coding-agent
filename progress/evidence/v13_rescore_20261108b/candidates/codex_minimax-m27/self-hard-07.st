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
    prevFlowSP          : REAL := 0.0;
    prevValveCommand    : REAL := 0.0;
    iT                  : REAL := 0.0;
    iF                  : REAL := 0.0;
END_VAR

VAR_TEMP
    eT : REAL;
    eF : REAL;
END_VAR

    // Fault detection
    fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

    // Rising edge detection for reset
    IF resetBtn AND NOT prevResetBtn THEN
        // Initialization on rising edge of reset
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        iT := flowSP - 1.0 * (tempSP - tempPV);
        iF := valveCommand - 2.0 * (manualFlowSP - flowPV);
        normalMode := FALSE;
        
    ELSIF fault THEN
        // Fault handling: flowSP follows manual, valve follows manual
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        iT := flowSP - 1.0 * (tempSP - tempPV);
        iF := valveCommand - 2.0 * (manualFlowSP - flowPV);
        normalMode := FALSE;
        
    ELSIF prevMode = 999 THEN
        // First cycle after power-up (initialization)
        flowSP := manualFlowSP;
        valveCommand := manualValve;
        iT := flowSP - 1.0 * (tempSP - tempPV);
        iF := valveCommand - 2.0 * (manualFlowSP - flowPV);
        normalMode := FALSE;
        
    ELSIF prevMode <> mode THEN
        // Mode switch: hold valve, keep flowSP for mode=2, recalculate integrals
        valveCommand := prevValveCommand;
        
        IF mode = 2 THEN
            flowSP := prevFlowSP;
        ELSE
            flowSP := manualFlowSP;
        END_IF
        
        iT := flowSP - 1.0 * (tempSP - tempPV);
        iF := valveCommand - 2.0 * (manualFlowSP - flowPV);
        normalMode := FALSE;
        
    ELSE
        // Normal computation cycle
        normalMode := TRUE;
        
        IF mode = 0 THEN
            flowSP := manualFlowSP;
            valveCommand := manualValve;
            iT := flowSP - 1.0 * (tempSP - tempPV);
            iF := valveCommand - 2.0 * (manualFlowSP - flowPV);
            
        ELSIF mode = 1 THEN
            flowSP := manualFlowSP;
            eF := flowSP - flowPV;
            iF := iF + 0.5 * eF * scanSeconds;
            valveCommand := clamp(2.0 * eF + iF, 0.0, 100.0);
            iF := valveCommand - 2.0 * eF;
            
        ELSIF mode = 2 THEN
            eT := tempSP - tempPV;
            iT := iT + 0.2 * eT * scanSeconds;
            flowSP := clamp(1.0 * eT + iT, 0.0, 50.0);
            iT := flowSP - 1.0 * eT;
            
            eF := flowSP - flowPV;
            iF := iF + 0.5 * eF * scanSeconds;
            valveCommand := clamp(2.0 * eF + iF, 0.0, 100.0);
            iF := valveCommand - 2.0 * eF;
        END_IF
    END_IF
    
    prevMode := mode;
    prevResetBtn := resetBtn;
    prevFlowSP := flowSP;
    prevValveCommand := valveCommand;
END_FUNCTION_BLOCK