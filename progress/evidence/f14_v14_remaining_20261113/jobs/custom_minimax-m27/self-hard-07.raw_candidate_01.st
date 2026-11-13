FUNCTION_BLOCK FB
VAR_INPUT
    mode            : INT;           (* 0=Manual 1=Auto 2=Cascade *)
    resetBtn        : BOOL;          (* Rising edge: reset to initial state *)
    scanSeconds     : REAL;          (* Scan period in seconds *)
    tempSP          : REAL;          (* Temperature setpoint, degC *)
    tempPV          : REAL;          (* Temperature process value, degC *)
    flowPV          : REAL;          (* Flow process value, t/h *)
    manualFlowSP    : REAL;          (* Manual flow setpoint, t/h *)
    manualValve     : REAL;          (* Manual valve position, % *)
END_VAR
VAR_OUTPUT
    flowSP          : REAL;          (* Flow setpoint output, t/h, clamped 0..50 *)
    valveCommand    : REAL;          (* Valve command output, %, clamped 0..100 *)
    fault           : BOOL;          (* Fault: invalid mode or scanSeconds *)
    normalMode      : BOOL;          (* This scan is normal operation (not reset/fault/switch/first) *)
END_VAR
VAR
    prevResetBtn    : BOOL    := FALSE;
    prevMode        : INT     := 0;
    accT            : REAL    := 0.0;    (* Integral state outer loop, unit t/h *)
    accF            : REAL    := 0.0;    (* Integral state inner loop, unit % *)
    firstScan       : BOOL    := TRUE;
END_VAR
VAR_TEMP
    tmpModeChanged  : BOOL;
    tmpET           : REAL;
    tmpEF           : REAL;
    tmpTrial        : REAL;
END_VAR
(*
ENGINEERING_CONTRACT:
  Modes: 0=Manual (both follow manual), 1=Auto (flow=manual, PI valve), 2=Cascade (PI flow then PI valve)
  Outputs: flowSP [0..50] t/h, valveCommand [0..100] %; retention per mode contract
  Activation: PI execution on normalMode=TRUE; bumpless transfer on mode switch (outputs hold/follow per spec)
  Reset/Deactivation: resetBtn rising edge → init to manual values, no PI on that scan
  Fault: mode∉{0,1,2} or scanSeconds∉(0,10] → fault, follow manual, no PI
  Priority: reset>fault (both reported), first-scan treated as switch (normalMode=FALSE)
  Units: KiT=0.2 (t/h)/(degC·s), KpT=1.0 (t/h)/degC; KiF=0.5 %/((t/h)·s), KpF=2.0 %/(t/h)
  Anti-windup: back-calculation from clamped output to accumulator
*)
BEGIN
    (* --- First scan: initialize outputs and accumulators --- *)
    IF firstScan THEN
        flowSP      := manualFlowSP;
        valveCommand := manualValve;
        accT        := 0.0;
        accF        := 0.0;
        fault       := FALSE;
        normalMode  := FALSE;
        firstScan   := FALSE;
        prevResetBtn := resetBtn;
        prevMode    := mode;
        RETURN;
    END_IF

    (* --- Detect state changes --- *)
    tmpModeChanged := (mode <> prevMode);

    (* --- Reset rising edge: immediate fallback to manual, no PI this scan --- *)
    IF resetBtn AND NOT prevResetBtn THEN
        flowSP       := manualFlowSP;
        valveCommand := manualValve;
        accT         := 0.0;
        accF         := 0.0;
        fault        := FALSE;
        normalMode   := FALSE;
        prevResetBtn := resetBtn;
        prevMode     := mode;
        RETURN;
    END_IF

    (* --- Fault condition: invalid mode or scanSeconds --- *)
    fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

    (* --- Fault fallback: follow manual immediately, no integral update --- *)
    IF fault THEN
        flowSP       := manualFlowSP;
        valveCommand := manualValve;
        accT         := 0.0;
        accF         := 0.0;
        normalMode   := FALSE;
        prevResetBtn := resetBtn;
        prevMode     := mode;
        RETURN;
    END_IF

    (* --- Normal operation or mode-transition scan --- *)
    IF mode = 0 THEN
        (* Manual: both outputs follow manual values; recalc accumulators for bumpless re-entry *)
        flowSP       := manualFlowSP;
        valveCommand := manualValve;
        tmpET := tempSP - tempPV;
        tmpEF := flowSP - flowPV;
        accT := flowSP - 1.0 * tmpET;
        accF := valveCommand - 2.0 * tmpEF;

    ELSIF mode = 2 THEN
        (* Cascade: outer loop PI → flowSP; inner loop PI → valveCommand *)
        IF tmpModeChanged THEN
            (* Mode switch: hold outputs, recalc accumulators for bumpless transfer *)
            flowSP       := flowSP;
            valveCommand := valveCommand;
            tmpET := tempSP - tempPV;
            tmpEF := flowSP - flowPV;
            accT := flowSP - 1.0 * tmpET;
            accF := valveCommand - 2.0 * tmpEF;
        ELSE
            (* Normal PI execution with anti-windup back-calculation *)
            tmpET := tempSP - tempPV;
            tmpEF := flowSP - flowPV;
            (* Outer loop *)
            tmpTrial := accT + 0.2 * tmpET * scanSeconds;
            flowSP   := LIMIT(0.0, 1.0 * tmpET + tmpTrial, 50.0);
            accT     := flowSP - 1.0 * tmpET;
            (* Inner loop uses current flowSP *)
            tmpEF    := flowSP - flowPV;
            tmpTrial := accF + 0.5 * tmpEF * scanSeconds;
            valveCommand := LIMIT(0.0, 2.0 * tmpEF + tmpTrial, 100.0);
            accF     := valveCommand - 2.0 * tmpEF;
        END_IF

    ELSIF mode = 1 THEN
        (* Auto: flowSP = manualFlowSP; inner loop PI → valveCommand *)
        IF tmpModeChanged THEN
            (* Mode switch: flowSP follows manual, valve holds; recalc accumulators *)
            flowSP       := manualFlowSP;
            valveCommand := valveCommand;
            tmpET := tempSP - tempPV;
            tmpEF := flowSP - flowPV;
            accT := flowSP - 1.0 * tmpET;
            accF := valveCommand - 2.0 * tmpEF;
        ELSE
            (* Normal PI execution *)
            flowSP       := manualFlowSP;
            tmpET        := tempSP - tempPV;
            accT         := flowSP - 1.0 * tmpET;
            tmpEF        := flowSP - flowPV;
            tmpTrial     := accF + 0.5 * tmpEF * scanSeconds;
            valveCommand := LIMIT(0.0, 2.0 * tmpEF + tmpTrial, 100.0);
            accF         := valveCommand - 2.0 * tmpEF;
        END_IF;
    END_IF;

    (* --- Update previous-state tracking --- *)
    prevResetBtn := resetBtn;
    prevMode     := mode;

    (* --- normalMode: second-or-later scan, stable mode, no fault, no reset rising edge --- *)
    normalMode := NOT firstScan AND (mode = prevMode) AND NOT fault AND NOT (resetBtn AND NOT prevResetBtn);
END_FUNCTION_BLOCK