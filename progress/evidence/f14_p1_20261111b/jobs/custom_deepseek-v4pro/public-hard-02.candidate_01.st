```structured text
FUNCTION_BLOCK FlexibleProcessingControl
VAR_INPUT
    processLength : USINT;
    sensor1 : BOOL;
    sensor2 : BOOL;
    sensor3 : BOOL;
    sensor4 : BOOL;
    sensor5 : BOOL;
    station1Start : BOOL;
    station2Complete : BOOL;
    station3Complete : BOOL;
    station4Complete : BOOL;
    processSequence : ARRAY[1..8] OF USINT;
END_VAR
VAR_OUTPUT
    conveyorLeft : BOOL;
    conveyorRight : BOOL;
END_VAR
VAR
    state : INT := 0;                    (* 0=idle, 1=moving, 2=wait_complete, 3=done *)
    stepIndex : USINT := 1;              (* current position in processSequence *)
    currentStation : USINT := 1;         (* station where product is currently located *)
    targetStation : USINT := 5;          (* destination station for current movement *)

    lastStation2Complete : BOOL := FALSE;
    lastStation3Complete : BOOL := FALSE;
    lastStation4Complete : BOOL := FALSE;

    start2 : BOOL := FALSE;              (* rising edge of station2Complete *)
    start3 : BOOL := FALSE;              (* rising edge of station3Complete *)
    start4 : BOOL := FALSE;              (* rising edge of station4Complete *)
END_VAR

(* ----- Edge detection for completion signals ----- *)
start2 := station2Complete AND NOT lastStation2Complete;
start3 := station3Complete AND NOT lastStation3Complete;
start4 := station4Complete AND NOT lastStation4Complete;

lastStation2Complete := station2Complete;
lastStation3Complete := station3Complete;
lastStation4Complete := station4Complete;

(* ----- Main control state machine ----- *)
CASE state OF
  0: (* IDLE: wait for start at station 1 *)
    conveyorLeft := FALSE;
    conveyorRight := FALSE;
    IF sensor1 AND station1Start AND processLength >= 1 THEN
        stepIndex := 1;
        currentStation := 1;
        state := 1;  (* start moving *)
    END_IF;

  1: (* MOVING: move product from current station to target station *)
    IF stepIndex <= processLength THEN
        targetStation := processSequence[stepIndex];

        (* Set conveyor direction *)
        IF targetStation > currentStation THEN
            conveyorRight := TRUE;
            conveyorLeft := FALSE;
        ELSIF targetStation < currentStation THEN
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        ELSE
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
        END_IF;

        (* Check arrival at target station *)
        IF (targetStation = 2 AND sensor2) OR
           (targetStation = 3 AND sensor3) OR
           (targetStation = 4 AND sensor4) OR
           (targetStation = 5 AND sensor5) THEN
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
            currentStation := targetStation;

            IF targetStation = 5 THEN
                state := 3;  (* product delivered to output station 5 *)
            ELSE
                state := 2;  (* wait for processing completion *)
            END_IF;
        END_IF;
    ELSE
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
        state := 3;  (* invalid sequence length, stop *)
    END_IF;

  2: (* WAIT_COMPLETION: wait for processing completion signal at current station *)
    conveyorLeft := FALSE;
    conveyorRight := FALSE;

    IF currentStation = 2 AND start2 THEN
        stepIndex := stepIndex + 1;
        state := 1;
    ELSIF currentStation = 3 AND start3 THEN
        stepIndex := stepIndex + 1;
        state := 1;
    ELSIF currentStation = 4 AND start4 THEN
        stepIndex := stepIndex + 1;
        state := 1;
    END_IF;

  3: (* DONE: product delivered to station 5, waiting for next cycle *)
    conveyorLeft := FALSE;
    conveyorRight := FALSE;

    (* Reset for next product when start button is released and sensor1 is clear *)
    IF NOT sensor1 AND NOT station1Start THEN
        state := 0;
    END_IF;
END_CASE;
```