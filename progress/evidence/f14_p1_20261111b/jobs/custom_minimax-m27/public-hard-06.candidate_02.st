FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode            : BOOL;          (* 0 = Manual, 1 = Automatic *)
    ForwardButton   : BOOL;          (* Manual forward command *)
    ReverseButton   : BOOL;          (* Manual reverse command *)
    SensorFeed      : BOOL;          (* Material at loading station *)
    SensorWash      : BOOL;          (* Material at cleaning station *)
    SensorWeight    : BOOL;          (* Material at weighing station *)
    SensorFiring    : BOOL;          (* Product at firing station *)
    SensorOutput    : BOOL;          (* Product at finished-product station *)
    washComplete    : BOOL;          (* Cleaning finished *)
    weightComplete  : BOOL;          (* Weighing finished *)
    weight          : REAL;          (* Measured weight *)
    firingComplete  : BOOL;          (* Firing finished *)
END_VAR

VAR_OUTPUT
    MotorForward    : BOOL;          (* Motor forward rotation *)
    MotorReverse    : BOOL;          (* Motor reverse rotation *)
    kick            : BOOL;          (* Rejection command *)
    CompletionLight : BOOL;          (* Product ready light *)
    firingTemp      : REAL;          (* Calculated firing temperature *)
END_VAR

VAR
    curState        : INT := 0;      (* Current automatic state *)
    lastSensorFeed    : BOOL := FALSE;
    lastSensorWash    : BOOL := FALSE;
    lastSensorWeight  : BOOL := FALSE;
    lastSensorFiring  : BOOL := FALSE;
    lastSensorOutput  : BOOL := FALSE;
    lastWashComplete  : BOOL := FALSE;
    lastWeightComplete: BOOL := FALSE;
    lastFiringComplete: BOOL := FALSE;
    sensorFeedRising    : BOOL;
    sensorWashRising    : BOOL;
    sensorWeightRising  : BOOL;
    sensorFiringRising  : BOOL;
    sensorOutputRising  : BOOL;
    sensorOutputFalling : BOOL;
    washCompleteRising  : BOOL;
    weightCompleteRising: BOOL;
    firingCompleteRising: BOOL;
    washProcessed   : BOOL := FALSE;
    weightProcessed : BOOL := FALSE;
    firingProcessed : BOOL := FALSE;
END_VAR

(* Edge detection *)
sensorFeedRising     := SensorFeed     AND NOT lastSensorFeed;
sensorWashRising     := SensorWash     AND NOT lastSensorWash;
sensorWeightRising   := SensorWeight   AND NOT lastSensorWeight;
sensorFiringRising   := SensorFiring   AND NOT lastSensorFiring;
sensorOutputRising   := SensorOutput   AND NOT lastSensorOutput;
sensorOutputFalling  := NOT SensorOutput AND lastSensorOutput;
washCompleteRising   := washComplete   AND NOT lastWashComplete;
weightCompleteRising := weightComplete AND NOT lastWeightComplete;
firingCompleteRising := firingComplete AND NOT lastFiringComplete;

lastSensorFeed     := SensorFeed;
lastSensorWash     := SensorWash;
lastSensorWeight   := SensorWeight;
lastSensorFiring   := SensorFiring;
lastSensorOutput   := SensorOutput;
lastWashComplete   := washComplete;
lastWeightComplete := weightComplete;
lastFiringComplete := firingComplete;

(* Mode handling *)
IF Mode = FALSE THEN
    MotorForward    := FALSE;
    MotorReverse    := FALSE;
    kick            := FALSE;
    CompletionLight := FALSE;
    firingTemp      := 0.0;
    curState        := 0;
    washProcessed   := FALSE;
    weightProcessed := FALSE;
    firingProcessed := FALSE;

    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    ELSE
        MotorForward := FALSE;
    END_IF

    IF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    ELSE
        MotorReverse := FALSE;
    END_IF
ELSE
    MotorReverse := FALSE;

    CASE curState OF
        0: (* IDLE *)
            IF sensorFeedRising THEN
                curState     := 1;
                MotorForward := TRUE;
            ELSE
                MotorForward    := FALSE;
                kick            := FALSE;
                CompletionLight := FALSE;
                firingTemp      := 0.0;
            END_IF

        1: (* MOVING_TO_WASH *)
            IF sensorWashRising THEN
                MotorForward := FALSE;
                curState     := 2;
                washProcessed := FALSE;
            END_IF

        2: (* AT_WASH *)
            IF washCompleteRising AND NOT washProcessed THEN
                MotorForward := TRUE;
                curState      := 3;
                washProcessed := TRUE;
            END_IF

        3: (* MOVING_TO_WEIGH *)
            IF sensorWeightRising THEN
                MotorForward    := FALSE;
                curState        := 4;
                weightProcessed := FALSE;
            END_IF

        4: (* AT_WEIGH *)
            IF weightCompleteRising AND NOT weightProcessed THEN
                weightProcessed := TRUE;
                IF weight >= 100.0 AND weight <= 200.0 THEN
                    firingTemp  := 500.0 + ((weight - 100.0) / 100.0) * 50.0;
                    MotorForward := TRUE;
                    curState     := 5;
                ELSE
                    kick         := TRUE;
                    MotorForward := FALSE;
                    curState     := 9;
                END_IF
            END_IF

        5: (* MOVING_TO_FIRING *)
            IF sensorFiringRising THEN
                MotorForward    := FALSE;
                curState        := 6;
                firingProcessed := FALSE;
            END_IF

        6: (* AT_FIRING *)
            IF firingCompleteRising AND NOT firingProcessed THEN
                MotorForward    := TRUE;
                curState         := 7;
                firingProcessed  := TRUE;
            END_IF

        7: (* MOVING_TO_OUTPUT *)
            IF sensorOutputRising THEN
                MotorForward    := FALSE;
                CompletionLight := TRUE;
                curState        := 8;
            END_IF

        8: (* AT_OUTPUT *)
            CompletionLight := SensorOutput;
            IF sensorOutputFalling THEN
                CompletionLight := FALSE;
                curState        := 0;
                firingTemp      := 0.0;
                kick            := FALSE;
            END_IF

        9: (* REJECT *)
            kick         := TRUE;
            MotorForward := FALSE;
            IF NOT SensorWeight THEN
                kick     := FALSE;
                curState := 0;
            END_IF

    END_CASE
END_IF

END_FUNCTION_BLOCK