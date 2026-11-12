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
    tmp_target     : USINT;
    tmp_arrived    : BOOL;
    tmp_complete   : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   State machine: IDLE(0), MOVING(1), PROCESSING(2), DONE(3).
   - PUB001 §1: 5 workstations, 1#=load, 2-4#=process, 5#=output.
   - PUB005 §3: Start requires sensor1 AND station1Start same scan.
   - PUB005 §3: Query processSequence[1], start conveyor to target.
   - PUB005 §4: Stop conveyor when target station sensor detects product.
   - PUB005 §5: Wait for station2Complete/station3Complete/station4Complete.
   - PUB005 §6: After completion, query next processSequence element.
   - PUB005 §7: Repeat until target is station 5.
   - PUB005 §2: processLength 1..8; final entry=5, others=2..4.
   - No explicit reset; cycle completes at station 5.
   - conveyorLeft/Right active only during MOVING to target.
   - Direction: target > current → Right; target < current → Left.
   - currentStation tracks physical position; updates on arrival only.
*)
(* CONTRACT_RULES [] *)

CASE currentState OF
    0: (* IDLE *)
        IF sensor1 AND station1Start THEN
            currentStep := 1;
            currentState := 1;
        END_IF;

    1: (* MOVING *)
        tmp_target := processSequence[currentStep];

        IF tmp_target > currentStation THEN
            conveyorRight := TRUE;
            conveyorLeft := FALSE;
        ELSIF tmp_target < currentStation THEN
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        ELSE
            conveyorRight := FALSE;
            conveyorLeft := FALSE;
        END_IF;

        tmp_arrived :=
            (tmp_target = 2 AND sensor2) OR
            (tmp_target = 3 AND sensor3) OR
            (tmp_target = 4 AND sensor4) OR
            (tmp_target = 5 AND sensor5);

        IF tmp_arrived THEN
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
            currentStation := tmp_target;

            IF tmp_target = 5 THEN
                currentState := 3;
            ELSE
                currentState := 2;
            END_IF;
        END_IF;

    2: (* PROCESSING *)
        tmp_complete := FALSE;
        IF currentStation = 2 THEN
            tmp_complete := station2Complete;
        ELSIF currentStation = 3 THEN
            tmp_complete := station3Complete;
        ELSIF currentStation = 4 THEN
            tmp_complete := station4Complete;
        END_IF;

        IF tmp_complete THEN
            currentStep := currentStep + 1;
            currentState := 1;
        END_IF;

    3: (* DONE *)

END_CASE;

END_FUNCTION_BLOCK