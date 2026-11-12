FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    resetBtn : BOOL;
    sensorValid : BOOL;
    setpoint : REAL;
    temperature : REAL;
    scanSeconds : REAL;
    bias : REAL;
END_VAR
VAR_OUTPUT
    power : REAL;
    correction : REAL;
    fault : BOOL;
END_VAR
VAR
    ePrev : REAL := 0.0;
    historyValid : BOOL := FALSE;
    local_prevReset : BOOL := FALSE;
    local_risingReset : BOOL;
    local_e : REAL;
    local_de : REAL;
    local_x : REAL;
    local_y : REAL;
END_VAR

(* ENGINEERING_CONTRACT
- power : computed via 20x+10y then clamped to [0,100]; zero when disabled/fault/reset rising. PUB001/PUB005/S1/S10/S11.
- correction : computed via 20x+10y, range [-30,30]; zero when disabled/fault/reset rising. PUB002/PUB004/S2.
- fault : combinational = NOT sensorValid OR scanSeconds<=0 OR scanSeconds>10; no retention. PUB003/S4/S5.
- historyValid/ePrev : cleared on disable/fault/reset rising; set after normal calculation; first/recovery scan uses de=0. PUB006/S7/S8/S12/S13.
- resetBtn edge : only rising edge triggers zero/clear; level hold does not keep zero. PUB009/S9.
- priority : fault/!enable/reset rising override normal calculation on same scan. PUB010/S3/S10.
- unspecified : NaN input behavior not specified; standard REAL LIMIT semantics used for clamps.
*)

(* CONTRACT_RULES [] *)

fault := (NOT sensorValid) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
local_risingReset := resetBtn AND NOT local_prevReset;

IF (NOT enable) OR fault OR local_risingReset THEN
    power := 0.0;
    correction := 0.0;
    ePrev := 0.0;
    historyValid := FALSE;
ELSE
    local_e := setpoint - temperature;

    IF NOT historyValid THEN
        local_de := 0.0;
    ELSE
        local_de := (local_e - ePrev) / scanSeconds;
    END_IF;

    local_x := LIMIT(-1.0, local_e / 10.0, 1.0);
    local_y := LIMIT(-1.0, local_de / 2.0, 1.0);

    correction := 20.0 * local_x + 10.0 * local_y;
    power := LIMIT(0.0, bias + correction, 100.0);

    ePrev := local_e;
    historyValid := TRUE;
END_IF;

local_prevReset := resetBtn;
END_FUNCTION_BLOCK