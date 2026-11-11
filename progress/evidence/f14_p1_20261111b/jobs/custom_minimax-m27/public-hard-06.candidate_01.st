(*----------------------------------------------------------------------------------
  Production Line Controller – Hard Version
  Mode 0 = Manual, Mode 1 = Automatic
  Automatic sequence: Feed → Wash → Weigh → Fire → Output
  Manual mode: forward / reverse with interlock
----------------------------------------------------------------------------------*)

(*----------- Type definitions ----------------------------------------------------*)
TYPE E_State :
(
    IDLE             := 0,
    MOVING_TO_WASH   := 1,
    AT_WASH          := 2,
    MOVING_TO_WEIGH  := 3,
    AT_WEIGH         := 4,
    MOVING_TO_FIRING := 5,
    AT_FIRING        := 6,
    MOVING_TO_OUTPUT := 7,
    AT_OUTPUT        := 8,
    REJECT           := 9
);
END_TYPE

(*----------- Program declaration -------------------------------------------------*)
PROGRAM ProductionControl
VAR_INPUT
    Mode            : BOOL;          (* 0 = Manual, 1 = Automatic *)
    ForwardButton   : BOOL;          (* Manual forward command *)
    ReverseButton   : BOOL;          (* Manual reverse command *)
    SensorFeed      : BOOL;          (* Material at loading station *)
    SensorWash      : BOOL;          (* Material at cleaning station *)
    SensorWeight    : BOOL;          (* Material at weighing station *)
    SensorFiring    : BOOL;          (* Product at firing station *)
    SensorOutput    : BOOL;          (* Product at finished‑product station *)
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

(*----------- Internal variables -------------------------------------------------*)
VAR
    curState        : E_State := IDLE;   (* Current automatic state *)

    (* Edge detection memories *)
    lastSensorFeed    : BOOL := FALSE;
    lastSensorWash    : BOOL := FALSE;
    lastSensorWeight  : BOOL := FALSE;
    lastSensorFiring  : BOOL := FALSE;
    lastSensorOutput  : BOOL := FALSE;
    lastWashComplete  : BOOL := FALSE;
    lastWeightComplete: BOOL := FALSE;
    lastFiringComplete: BOOL := FALSE;

    (* Edge flags *)
    sensorFeedRising    : BOOL;
    sensorWashRising    : BOOL;
    sensorWeightRising  : BOOL;
    sensorFiringRising  : BOOL;
    sensorOutputRising  : BOOL;
    sensorOutputFalling : BOOL;
    washCompleteRising  : BOOL;
    weightCompleteRising: BOOL;
    firingCompleteRising: BOOL;

    (* One‑shot flags for completion signals *)
    washProcessed   : BOOL := FALSE;
    weightProcessed : BOOL := FALSE;
    firingProcessed : BOOL := FALSE;
END_VAR

(*----------- Edge detection ----------------------------------------------------*)
sensorFeedRising     := SensorFeed     AND NOT lastSensorFeed;
sensorWashRising     := SensorWash     AND NOT lastSensorWash;
sensorWeightRising   := SensorWeight   AND NOT lastSensorWeight;
sensorFiringRising   := SensorFiring   AND NOT lastSensorFiring;
sensorOutputRising   := SensorOutput   AND NOT lastSensorOutput;
sensorOutputFalling  := NOT SensorOutput AND lastSensorOutput;

washCompleteRising   := washComplete   AND NOT lastWashComplete;
weightCompleteRising := weightComplete AND NOT lastWeightComplete;
firingCompleteRising := firingComplete AND NOT lastFiringComplete;

(* Update memories *)
lastSensorFeed    := SensorFeed;
lastSensorWash    := SensorWash;
lastSensorWeight  := SensorWeight;
lastSensorFiring  := SensorFiring;
lastSensorOutput  := SensorOutput;
lastWashComplete  := washComplete;
lastWeightComplete:= weightComplete;
lastFiringComplete:= firingComplete;

(*----------- Mode handling ------------------------------------------------------*)
IF Mode = FALSE THEN                (* Manual Mode *)
    (* Reset automatic control outputs *)
    MotorForward    := FALSE;
    MotorReverse    := FALSE;
    kick            := FALSE;
    CompletionLight := FALSE;
    firingTemp      := 0.0;
    curState        := IDLE;
    washProcessed   := FALSE;
    weightProcessed := FALSE;
    firingProcessed := FALSE;

    (* Interlocked forward / reverse *)
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

ELSE                                 (* Automatic Mode *)
    MotorReverse := FALSE;          (* Reverse never used in auto *)

    CASE curState OF

        (*--------------------------------------------------------------
         IDLE – waiting for a new material at the loading station
        --------------------------------------------------------------*)
        IDLE:
            IF sensorFeedRising THEN
                curState     := MOVING_TO_WASH;
                MotorForward := TRUE;
            ELSE
                MotorForward    := FALSE;
                kick            := FALSE;
                CompletionLight := FALSE;
                firingTemp      := 0.0;
            END_IF

        (*--------------------------------------------------------------
         MOVING_TO_WASH – motor conveys material to cleaning station
        --------------------------------------------------------------*)
        MOVING_TO_WASH:
            IF sensorWashRising THEN
                MotorForward := FALSE;
                curState     := AT_WASH;
                washProcessed := FALSE;
            END_IF

        (*--------------------------------------------------------------
         AT_WASH – cleaning in progress, waiting for washComplete
        --------------------------------------------------------------*)
        AT_WASH:
            IF washCompleteRising AND NOT washProcessed THEN
                MotorForward := TRUE;
                curState      := MOVING_TO_WEIGH;
                washProcessed := TRUE;
            END_IF

        (*--------------------------------------------------------------
         MOVING_TO_WEIGH – material moves to weighing station
        --------------------------------------------------------------*)
        MOVING_TO_WEIGH:
            IF sensorWeightRising THEN
                MotorForward   := FALSE;
                curState       := AT_WEIGH;
                weightProcessed := FALSE;
            END_IF

        (*--------------------------------------------------------------
         AT_WEIGH – weight measurement, quality check and temperature calc.
        --------------------------------------------------------------*)
        AT_WEIGH:
            IF weightCompleteRising AND NOT weightProcessed THEN
                weightProcessed := TRUE;
                IF weight >= 100.0 AND weight <= 200.0 THEN
                    (* Qualified – compute firing temperature *)
                    firingTemp  := 500.0 + ((weight - 100.0) / 100.0) * 50.0;
                    MotorForward := TRUE;
                    curState     := MOVING_TO_FIRING;
                ELSE
                    (* Unqualified – reject *)
                    kick         := TRUE;
                    MotorForward := FALSE;
                    curState     := REJECT;
                END_IF
            END_IF

        (*--------------------------------------------------------------
         MOVING_TO_FIRING – material moves to firing station
        --------------------------------------------------------------*)
        MOVING_TO_FIRING:
            IF sensorFiringRising THEN
                MotorForward   := FALSE;
                curState       := AT_FIRING;
                firingProcessed := FALSE;
            END_IF

        (*--------------------------------------------------------------
         AT_FIRING – firing in progress, waiting for firingComplete
        --------------------------------------------------------------*)
        AT_FIRING:
            IF firingCompleteRising AND NOT firingProcessed THEN
                MotorForward   := TRUE;
                curState        := MOVING_TO_OUTPUT;
                firingProcessed := TRUE;
            END_IF

        (*--------------------------------------------------------------
         MOVING_TO_OUTPUT – product moves to finished‑product station
        --------------------------------------------------------------*)
        MOVING_TO_OUTPUT:
            IF sensorOutputRising THEN
                MotorForward    := FALSE;
                CompletionLight := TRUE;
                curState        := AT_OUTPUT;
            END_IF

        (*--------------------------------------------------------------
         AT_OUTPUT – product waiting to be taken away
        --------------------------------------------------------------*)
        AT_OUTPUT:
            CompletionLight := SensorOutput;   (* Light on while product present *)
            IF sensorOutputFalling THEN
                CompletionLight := FALSE;
                curState        := IDLE;
                firingTemp      := 0.0;
                kick            := FALSE;
            END_IF

        (*--------------------------------------------------------------
         REJECT – unqualified material at weighing station
        --------------------------------------------------------------*)
        REJECT:
            kick         := TRUE;
            MotorForward := FALSE;
            (* Assume the material is removed manually; when weight sensor clears → reset *)
            IF NOT SensorWeight THEN
                kick     := FALSE;
                curState := IDLE;
            END_IF

    END_CASE
END_IF

END_PROGRAM