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
 prevReset : BOOL;
 initDone : BOOL;
 lastMode : INT;
 accT : REAL;
 accF : REAL;
 oFlow : REAL;
 oValve : REAL;
 eTemp : REAL;
 eFlow : REAL;
 trial : REAL;
 normalMem : BOOL;
END_VAR
fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
normalMem := FALSE;
IF (NOT initDone) OR (resetBtn AND NOT prevReset) OR fault THEN
 oFlow := manualFlowSP;
 oValve := manualValve;
 accT := oFlow - 1.0 * (tempSP - tempPV);
 accF := oValve - 2.0 * (oFlow - flowPV);
 lastMode := mode;
 initDone := TRUE;
ELSIF lastMode <> mode THEN
 IF mode <> 2 THEN
  oFlow := manualFlowSP;
 END_IF;
 accT := oFlow - 1.0 * (tempSP - tempPV);
 accF := oValve - 2.0 * (oFlow - flowPV);
 lastMode := mode;
ELSE
 normalMem := TRUE;
 IF mode = 0 THEN
  oFlow := manualFlowSP;
  oValve := manualValve;
  accT := oFlow - 1.0 * (tempSP - tempPV);
  accF := oValve - 2.0 * (oFlow - flowPV);
 ELSIF mode = 1 THEN
  oFlow := manualFlowSP;
  accT := oFlow - 1.0 * (tempSP - tempPV);
  eFlow := oFlow - flowPV;
  trial := accF + 0.5 * eFlow * scanSeconds;
  oValve := 2.0 * eFlow + trial;
  IF oValve > 100.0 THEN oValve := 100.0; END_IF;
  IF oValve < 0.0 THEN oValve := 0.0; END_IF;
  accF := oValve - 2.0 * eFlow;
 ELSE
  eTemp := tempSP - tempPV;
  trial := accT + 0.2 * eTemp * scanSeconds;
  oFlow := 1.0 * eTemp + trial;
  IF oFlow > 50.0 THEN oFlow := 50.0; END_IF;
  IF oFlow < 0.0 THEN oFlow := 0.0; END_IF;
  accT := oFlow - 1.0 * eTemp;
  eFlow := oFlow - flowPV;
  trial := accF + 0.5 * eFlow * scanSeconds;
  oValve := 2.0 * eFlow + trial;
  IF oValve > 100.0 THEN oValve := 100.0; END_IF;
  IF oValve < 0.0 THEN oValve := 0.0; END_IF;
  accF := oValve - 2.0 * eFlow;
 END_IF;
END_IF;
prevReset := resetBtn;
flowSP := oFlow;
valveCommand := oValve;
normalMode := normalMem;
END_FUNCTION_BLOCK
