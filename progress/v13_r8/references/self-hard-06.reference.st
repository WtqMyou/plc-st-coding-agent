FUNCTION_BLOCK FB
VAR_INPUT
 runRequest : BOOL;
 pressure : REAL;
 pressureValid : BOOL;
 fuelFlow : REAL;
 steamFlow : REAL;
 outletCmd : INT;
 outletFeedback : INT;
 resetBtn : BOOL;
END_VAR
VAR_OUTPUT
 tripLatched : BOOL;
 fuelPermit : BOOL;
 currentCauseMask : WORD;
 latchedCauseMask : WORD;
 diagnosticActive : BOOL;
END_VAR
VAR
 prevReset : BOOL;
 tripMem : BOOL;
 latMem : WORD;
 valveCnt : INT;
END_VAR
currentCauseMask := 0;
IF resetBtn AND NOT prevReset AND NOT runRequest AND pressureValid
 AND (pressure <= 4200.0) THEN
 tripMem := FALSE;
 latMem := 0;
 valveCnt := 0;
END_IF;
prevReset := resetBtn;
IF NOT runRequest THEN
 valveCnt := 0;
ELSIF NOT pressureValid THEN
 currentCauseMask := 16#0001;
 valveCnt := 0;
 tripMem := TRUE;
ELSIF pressureValid AND (pressure >= 4500.0) THEN
 IF (outletCmd >= 50) AND (outletFeedback <= 10) THEN
  valveCnt := valveCnt + 1;
  IF valveCnt > 3 THEN valveCnt := 3; END_IF;
 ELSE
  valveCnt := 0;
 END_IF;
 IF valveCnt >= 3 THEN
  currentCauseMask := currentCauseMask OR 16#0002;
 END_IF;
 IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
  currentCauseMask := currentCauseMask OR 16#0004;
 END_IF;
 IF currentCauseMask = 0 THEN
  currentCauseMask := 16#0008;
 END_IF;
 tripMem := TRUE;
ELSE
 valveCnt := 0;
END_IF;
IF tripMem THEN
 latMem := latMem OR currentCauseMask;
END_IF;
tripLatched := tripMem;
latchedCauseMask := latMem;
diagnosticActive := (currentCauseMask <> 0);
fuelPermit := runRequest AND NOT tripMem;
END_FUNCTION_BLOCK
