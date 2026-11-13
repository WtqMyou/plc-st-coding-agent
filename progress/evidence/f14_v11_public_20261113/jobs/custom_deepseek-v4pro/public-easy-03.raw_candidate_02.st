FUNCTION_BLOCK AlarmHandling
VAR_INPUT
    Value : REAL;
    hiLevel : REAL;
    loLevel : REAL;
    hystWindow : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL;
    loAlarm : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
END_VAR

(* ENGINEERING_CONTRACT
   hiAlarm: retained latch. Activation when Value > hiLevel (PUB001/PUB004).
   Hold until Value < hiLevel - hystWindow (PUB001/PUB004). No external reset.
   loAlarm: retained latch. Activation when Value < loLevel (PUB002/PUB005).
   Hold until Value > loLevel + hystWindow (PUB002/PUB005). No external reset.
   error/status: scan-combinational. Priority loLevel >= hiLevel ->
   error=TRUE, status=16#8001, RETURN (PUB003/PUB006). Else
   hystWindow >= hiLevel - loLevel -> error=TRUE, status=16#8002, RETURN
   (PUB003/PUB007). Else error=FALSE, status=16#0000.
   Error paths exit before alarm evaluation; latched alarm outputs retain
   last values. Unspecified error alarm reset behavior kept as retention.
   Boundaries are strict as stated. *)
(* CONTRACT_RULES [] *)

IF loLevel >= hiLevel THEN
    error := TRUE;
    status := WORD#16#8001;
    RETURN;
END_IF;

IF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := WORD#16#8002;
    RETURN;
END_IF;

error := FALSE;
status := WORD#16#0000;

IF hiAlarm THEN
    IF Value < (hiLevel - hystWindow) THEN
        hiAlarm := FALSE;
    END_IF;
ELSE
    IF Value > hiLevel THEN
        hiAlarm := TRUE;
    END_IF;
END_IF;

IF loAlarm THEN
    IF Value > (loLevel + hystWindow) THEN
        loAlarm := FALSE;
    END_IF;
ELSE
    IF Value < loLevel THEN
        loAlarm := TRUE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK