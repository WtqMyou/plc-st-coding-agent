(*
ENGINEERING_CONTRACT
- State machine: 0=IDLE, 1=MOVING, 2=WAIT_COMPLETE, 3=DONE.
- IDLE->MOVING on rising edge of station1Start while sensor1; loads first active entry (PUB001).
- MOVING drives conveyor direction from targetStation-currentStation; stops same scan target sensor TRUE (PUB002/PUB005).
- Arrival at stations 2..4 enters WAIT_COMPLETE; arrival at 5 enters DONE (PUB003).
- WAIT_COMPLETE waits for the matching stationXComplete rising edge, then loads next entry; final 5 ends DONE (PUB003).
- Conveyor outputs are state/direction combinational and are not retained once movement stops; opposite directions cannot overlap (PUB004, V12.1).
- No unstated reset or new-cycle restart after DONE.
- Inputs are assumed valid: processLength 1..8, entries 2..5, final 5.
*)
(* CONTRACT_RULES [] *)
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
    state : INT := 0; (* 0 IDLE, 1 MOVING, 2 WAIT_COMPLETE, 3 DONE *)
    idx : USINT := 1;
    currentStation : USINT := 1;
    targetStation : USINT := 5;
    directionRight : BOOL := TRUE;
    targetArrived : BOOL := FALSE;
    completionQ : BOOL := FALSE;
    startTrig : R_TRIG;
    comp2Trig : R_TRIG;
    comp3Trig : R_TRIG;
    comp4Trig : R_TRIG;
END_VAR

startTrig(CLK := station1Start);
comp2Trig(CLK := station2Complete);
comp3Trig(CLK := station3Complete);
comp4Trig(CLK := station4Complete);

CASE targetStation OF
    2: targetArrived := sensor2;
    3: targetArrived := sensor3;
    4: targetArrived := sensor4;
    5: targetArrived := sensor5;
ELSE
    targetArrived := FALSE;
END_CASE;

IF processLength = 0 OR processLength > 8 THEN
    state := 3;
ELSE
    CASE state OF
        0: (* IDLE *)
            IF startTrig.Q AND sensor1 THEN
                idx := 1;
                currentStation := 1;
                targetStation := processSequence[idx];
                IF targetStation >= 2 AND targetStation <= 5 THEN
                    directionRight := targetStation > currentStation;
                    CASE targetStation OF
                        2: targetArrived := sensor2;
                        3: targetArrived := sensor3;
                        4: targetArrived := sensor4;
                        5: targetArrived := sensor5;
                    END_CASE;
                    IF targetArrived THEN
                        currentStation := targetStation;
                        IF targetStation = 5 THEN
                            state := 3;
                        ELSE
                            state := 2;
                        END_IF;
                    ELSE
                        state := 1;
                    END_IF;
                ELSE
                    state := 3;
                END_IF;
            END_IF;

        1: (* MOVING *)
            IF targetArrived THEN
                currentStation := targetStation;
                IF targetStation = 5 THEN
                    state := 3;
                ELSE
                    state := 2;
                END_IF;
            END_IF;

        2: (* WAIT_COMPLETE *)
            completionQ := FALSE;
            CASE currentStation OF
                2: completionQ := comp2Trig.Q;
                3: completionQ := comp3Trig.Q;
                4: completionQ := comp4Trig.Q;
            ELSE
                state := 3;
            END_CASE;
            IF completionQ THEN
                idx := idx + 1;
                IF idx > processLength THEN
                    state := 3;
                ELSE
                    targetStation := processSequence[idx];
                    IF targetStation >= 2 AND targetStation <= 5 THEN
                        directionRight := targetStation > currentStation;
                        CASE targetStation OF
                            2: targetArrived := sensor2;
                            3: targetArrived := sensor3;
                            4: targetArrived := sensor4;
                            5: targetArrived := sensor5;
                        END_CASE;
                        IF targetArrived THEN
                            currentStation := targetStation;
                            IF targetStation = 5 THEN
                                state := 3;
                            ELSE
                                state := 2;
                            END_IF;
                        ELSE
                            state := 1;
                        END_IF;
                    ELSE
                        state := 3;
                    END_IF;
                END_IF;
            END_IF;

        3: (* DONE *)
            (* no action *)
    END_CASE;
END_IF;

IF state = 1 THEN
    IF directionRight THEN
        conveyorRight := TRUE;
        conveyorLeft := FALSE;
    ELSE
        conveyorLeft := TRUE;
        conveyorRight := FALSE;
    END_IF;
ELSE
    conveyorLeft := FALSE;
    conveyorRight := FALSE;
END_IF;

END_FUNCTION_BLOCK