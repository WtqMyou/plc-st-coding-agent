(* ENGINEERING_CONTRACT
- MotorForward/MotorReverse: manual direct from buttons, both inhibited when both are requested or Mode=1; automatic uses forward motion states only (PUB001, PUB002).
- Automatic motion: enabled by feed/cleaning/weighing/firing completion and held until the destination sensor is active; same-scan arrival has priority over completion (PUB003-PUB008).
- kick: set when weighing completes with weight<100.0 or weight>200.0; held while rejected until SensorWeight clears or Mode=0 (PUB009).
- firingTemp: updated only on a qualified weighing, REAL degrees, linear 100..200 -> 500..550; held through firing/output until unqualified, next feed, or Mode=0 (PUB009, PUB010).
- CompletionLight: active while SensorOutput in automatic output state; cleared when the product is removed or Mode=0 (PUB008).
- Weight boundary test is inclusive: qualified is 100.0 <= weight <= 200.0 (PUB009).
*)
(* CONTRACT_RULES [] *)

TYPE E_ProductionState :
(
    ST_IDLE := 0,
    ST_MOVE_TO_WASH := 1,
    ST_AT_WASH := 2,
    ST_MOVE_TO_WEIGHT := 3,
    ST_AT_WEIGHT := 4,
    ST_MOVE_TO_FIRING := 5,
    ST_AT_FIRING := 6,
    ST_MOVE_TO_OUTPUT := 7,
    ST_AT_OUTPUT := 8,
    ST_REJECTED := 9
);
END_TYPE;

FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode : BOOL;
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorFeed : BOOL;
    SensorWash : BOOL;
    SensorWeight : BOOL;
    SensorFiring : BOOL;
    SensorOutput : BOOL;
    washComplete : BOOL;
    weightComplete : BOOL;
    weight : REAL;
    firingComplete : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward : BOOL;
    MotorReverse : BOOL;
    kick : BOOL;
    CompletionLight : BOOL;
    firingTemp : REAL;
END_VAR
VAR
    tmp_LocalState : E_ProductionState := ST_IDLE;
    tmp_Qualified : BOOL;
    tmp_TempLatched : REAL := 0.0;
END_VAR

IF NOT Mode THEN
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    kick := FALSE;
    CompletionLight := FALSE;
    tmp_TempLatched := 0.0;
    firingTemp := 0.0;
ELSE
    MotorReverse := FALSE;

    IF tmp_LocalState = ST_IDLE THEN
        tmp_TempLatched := 0.0;
        IF SensorFeed THEN
            tmp_LocalState := ST_MOVE_TO_WASH;
        END_IF;
    ELSIF tmp_LocalState = ST_MOVE_TO_WASH THEN
        IF SensorWash THEN
            tmp_LocalState := ST_AT_WASH;
        END_IF;
    ELSIF tmp_LocalState = ST_AT_WASH THEN
        IF SensorWeight THEN
            tmp_LocalState := ST_AT_WEIGHT;
        ELSIF washComplete THEN
            tmp_LocalState := ST_MOVE_TO_WEIGHT;
        END_IF;
    ELSIF tmp_LocalState = ST_MOVE_TO_WEIGHT THEN
        IF SensorWeight THEN
            tmp_LocalState := ST_AT_WEIGHT;
        END_IF;
    ELSIF tmp_LocalState = ST_AT_WEIGHT THEN
        IF SensorFiring THEN
            tmp_LocalState := ST_AT_FIRING;
        ELSIF weightComplete THEN
            tmp_Qualified := (weight >= 100.0) AND (weight <= 200.0);
            IF tmp_Qualified THEN
                tmp_TempLatched := 500.0 + ((weight - 100.0) * 50.0) / 100.0;
                tmp_LocalState := ST_MOVE_TO_FIRING;
            ELSE
                tmp_TempLatched := 0.0;
                tmp_LocalState := ST_REJECTED;
            END_IF;
        END_IF;
    ELSIF tmp_LocalState = ST_REJECTED THEN
        IF NOT SensorWeight THEN
            tmp_TempLatched := 0.0;
            tmp_LocalState := ST_IDLE;
        END_IF;
    ELSIF tmp_LocalState = ST_MOVE_TO_FIRING THEN
        IF SensorFiring THEN
            tmp_LocalState := ST_AT_FIRING;
        END_IF;
    ELSIF tmp_LocalState = ST_AT_FIRING THEN
        IF SensorOutput THEN
            tmp_LocalState := ST_AT_OUTPUT;
        ELSIF firingComplete THEN
            tmp_LocalState := ST_MOVE_TO_OUTPUT;
        END_IF;
    ELSIF tmp_LocalState = ST_MOVE_TO_OUTPUT THEN
        IF SensorOutput THEN
            tmp_LocalState := ST_AT_OUTPUT;
        END_IF;
    ELSIF tmp_LocalState = ST_AT_OUTPUT THEN
        IF NOT SensorOutput THEN
            tmp_TempLatched := 0.0;
            tmp_LocalState := ST_IDLE;
        END_IF;
    END_IF;

    CASE tmp_LocalState OF
        ST_MOVE_TO_WASH,
        ST_MOVE_TO_WEIGHT,
        ST_MOVE_TO_FIRING,
        ST_MOVE_TO_OUTPUT:
            MotorForward := TRUE;
    ELSE
            MotorForward := FALSE;
    END_CASE;

    kick := (tmp_LocalState = ST_REJECTED);
    CompletionLight := (tmp_LocalState = ST_AT_OUTPUT) AND SensorOutput;
    firingTemp := tmp_TempLatched;
END_IF;
END_FUNCTION_BLOCK