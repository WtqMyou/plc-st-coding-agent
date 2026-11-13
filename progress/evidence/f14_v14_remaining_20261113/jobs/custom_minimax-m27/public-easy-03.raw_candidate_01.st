FUNCTION_BLOCK AlarmHysteresis
VAR_INPUT
    Value      : REAL;
    hiLevel    : REAL;
    loLevel    : REAL;
    hystWindow : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL;
    loAlarm : BOOL;
    error   : BOOL;
    status  : WORD;
END_VAR
VAR
    tmp_range : REAL;
END_VAR

(* ENGINEERING_CONTRACT
| Output   | Activation                          | Retention        | Reset/Deactivation                  | Same-scan | Units/Bounds           |
|----------|-------------------------------------|------------------|-------------------------------------|-----------|------------------------|
| hiAlarm  | Value > hiLevel                     | hold             | Value < hiLevel - hystWindow        | -         | PUB001, hysteresis     |
| loAlarm  | Value < loLevel                     | hold             | Value > loLevel + hystWindow        | -         | PUB001, hysteresis     |
| error    | loLevel >= hiLevel                  | hold_until_reset | -                                   | priority  | PUB002, 16#8001        |
| error    | hystWindow >= (hiLevel - loLevel)   | hold_until_reset | -                                   | priority  | PUB003, 16#8002        |
| status   | set on error                        | retain           | -                                   | -         | PUB002/PUB003, WORD    |

Priority: Error checks execute before alarm logic; on error, status is set and block exits early.
Retention: hiAlarm/loAlarm are latching (PUB001); error is latching until explicit reset (not specified).
Boundary: Strict > and < comparisons; hystWindow is REAL; range = hiLevel - loLevel.
*)

(* CONTRACT_RULES [] *)

tmp_range := hiLevel - loLevel;

error := FALSE;
status := 16#0000;

IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    RETURN;
END_IF

IF hystWindow >= tmp_range THEN
    error := TRUE;
    status := 16#8002;
    RETURN;
END_IF

IF Value > hiLevel THEN
    hiAlarm := TRUE;
ELSIF Value < (hiLevel - hystWindow) THEN
    hiAlarm := FALSE;
END_IF

IF Value < loLevel THEN
    loAlarm := TRUE;
ELSIF Value > (loLevel + hystWindow) THEN
    loAlarm := FALSE;
END_IF

END_FUNCTION_BLOCK