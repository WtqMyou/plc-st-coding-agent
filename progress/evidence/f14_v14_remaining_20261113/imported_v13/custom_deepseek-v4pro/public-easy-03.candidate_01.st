(* ENGINEERING_CONTRACT
   [PUB001-PUB004] hiAlarm/loAlarm are retained hysteresis states.
   hiAlarm activates on Value>hiLevel when off; resets only on Value<hiLevel-hystWindow when on.
   loAlarm activates on Value<loLevel when off; resets only on Value>loLevel+hystWindow when on.
   Strict comparisons are used; equality causes no state change.
   Alarm outputs are not updated during configuration error; they keep their last written values.
   On first invocation alarm states default to FALSE.
   [PUB005] If loLevel>=hiLevel then error=TRUE, status=16#8001 and RETURN. This check has priority over PUB006.
   [PUB006] Else if hystWindow>=(hiLevel-loLevel) then error=TRUE, status=16#8002 and RETURN.
   Normal scan: error=FALSE, status=0, then both hysteresis states are evaluated from current Value.
   Units: REAL thresholds/hysteresis, WORD status; no timers or pulse logic.
*)
(* CONTRACT_RULES [] *)
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
    local_hiAlarmState : BOOL := FALSE;
    local_loAlarmState : BOOL := FALSE;
END_VAR

IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    RETURN;
END_IF;

IF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := 16#8002;
    RETURN;
END_IF;

error := FALSE;
status := 0;

IF local_hiAlarmState THEN
    IF Value < (hiLevel - hystWindow) THEN
        local_hiAlarmState := FALSE;
    END_IF;
ELSE
    IF Value > hiLevel THEN
        local_hiAlarmState := TRUE;
    END_IF;
END_IF;

hiAlarm := local_hiAlarmState;

IF local_loAlarmState THEN
    IF Value > (loLevel + hystWindow) THEN
        local_loAlarmState := FALSE;
    END_IF;
ELSE
    IF Value < loLevel THEN
        local_loAlarmState := TRUE;
    END_IF;
END_IF;

loAlarm := local_loAlarmState;

END_FUNCTION_BLOCK