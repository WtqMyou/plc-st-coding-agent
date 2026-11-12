FUNCTION_BLOCK FlexibleProcessingControl
VAR_INPUT
    processLength    : USINT;
    sensor1          : BOOL;
    sensor2          : BOOL;
    sensor3          : BOOL;
    sensor4          : BOOL;
    sensor5          : BOOL;
    station1Start    : BOOL;
    station2Complete : BOOL;
    station3Complete : BOOL;
    station4Complete : BOOL;
    processSequence  : ARRAY[1..8] OF USINT;
END_VAR
VAR_OUTPUT
    conveyorLeft  : BOOL;
    conveyorRight : BOOL;
END_VAR
VAR
    currentState   : UINT := 0;
    currentStation : USINT := 1;
    currentStep    : USINT := 0;
    targetStation  : USINT;
    arrivedAtTarget : BOOL;
    tmpComplete    : BOOL;
END_VAR
VAR_CONSTANT
    STATE_IDLE       : UINT := 0;
    STATE_MOVING     : UINT := 1;
    STATE_PROCESSING : UINT := 2;
    STATE_DONE       : UINT := 3;
END_VAR

(* ENGINEERING_CONTRACT
   State machine with 4 states: IDLE, MOVING, PROCESSING, DONE.
   - PUB001 §3: Start trigger requires sensor1 AND station1Start asserted same scan.
   - PUB002 §3: Conveyor moves to processSequence[currentStep] target station.
   - PUB002 §4: Conveyor stops when target station sensor detects product same scan.
   - PUB003 §5: After arrival, wait for station2Complete/station3Complete/station4Complete.
   - PUB003 §6: Query next sequence element after processing complete same scan.
   - PUB003 §7: Repeat until target is station 5.
   - PUB005 §2: processLength 1..8; processSequence[1..processLength] active.
   - PUB005 §2: Final active entry is station 5; others are stations 2..4.
   - No explicit reset/deactivation required; cycle completes at station 5.
   - No retention of outputs beyond their active state; conveyorLeft/Right only active during MOVING.
   - Direction: targetStation > currentStation → conveyorRight; targetStation < currentStation → conveyorLeft.
   - First movement: from station 1 to processSequence[1].
*)
(* CONTRACT_RULES [] *)

CASE currentState OF
    STATE_IDLE:
        IF sensor1 AND station1Start THEN
            currentStep := 1;
            currentState := STATE_MOVING;
        END_IF;

    STATE_MOVING:
        targetStation := processSequence[currentStep];

        IF targetStation > currentStation THEN
            conveyorRight := TRUE;
            conveyorLeft := FALSE;
        ELSIF targetStation < currentStation THEN
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        END_IF;

        arrivedAtTarget :=
            (targetStation = 2 AND sensor2) OR
            (targetStation = 3 AND sensor3) OR
            (targetStation = 4 AND sensor4) OR
            (targetStation = 5 AND sensor5);

        IF arrivedAtTarget THEN
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
            currentStation := targetStation;

            IF targetStation = 5 THEN
                currentState := STATE_DONE;
            ELSE
                currentState := STATE_PROCESSING;
            END_IF;
        END_IF;

    STATE_PROCESSING:
        tmpComplete := FALSE;
        IF currentStation = 2 THEN
            tmpComplete := station2Complete;
        ELSIF currentStation = 3 THEN
            tmpComplete := station3Complete;
        ELSIF currentStation = 4 THEN
            tmpComplete := station4Complete;
        END_IF;

        IF tmpComplete THEN
            currentStep := currentStep + 1;
            currentState := STATE_MOVING;
        END_IF;

    STATE_DONE:

END_CASE;

END_FUNCTION_BLOCK