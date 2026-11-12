FUNCTION_BLOCK FlexibleProcessingControl
(* ENGINEERING_CONTRACT
   conveyorLeft  : active while moving to a lower-numbered station; deactivates when the destination sensor is detected or when final delivery to station 5 is complete. No separate reset input is specified. Same-scan arrival clears both conveyors (PUB002/PUB003/PUB005).
   conveyorRight : active while moving to a higher-numbered station; deactivates when the destination sensor is detected or when final delivery to station 5 is complete. No separate reset input is specified. Same-scan arrival clears both conveyors (PUB002/PUB003/PUB005).
   Processing wait: retained in phase after arrival at station 2, 3, or 4. The matching completion input starts the next sequence movement in the same scan it is detected (PUB002/PUB003).
   Start condition: sensor1 AND station1Start initiates processing from processSequence[1]; after transition, START is not re-evaluated until the current product cycle is finished (PUB001/PUB006).
   Boundaries: processLength is active in the range 1..8; active sequence positions are processSequence[1] through processSequence[processLength]. Stations are compared as USINT values 1..5 (PUB004/PUB006).
*)
(* CONTRACT_RULES [] *)
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
    tmp_phase : USINT := 0;
    tmp_seqIndex : USINT := 1;
    tmp_currentStation : USINT := 1;
    tmp_targetStation : USINT := 0;
    tmp_destSensor : BOOL := FALSE;
    tmp_completeSignal : BOOL := FALSE;
    tmp_activeLength : USINT := 1;
END_VAR

tmp_activeLength := processLength;
IF tmp_activeLength > 8 THEN
    tmp_activeLength := 8;
END_IF;
IF tmp_activeLength < 1 THEN
    tmp_activeLength := 1;
END_IF;

conveyorLeft := FALSE;
conveyorRight := FALSE;

IF tmp_phase = 0 THEN
    IF sensor1 AND station1Start THEN
        tmp_seqIndex := 1;
        IF tmp_seqIndex <= tmp_activeLength THEN
            tmp_targetStation := processSequence[tmp_seqIndex];
            tmp_phase := 1;
        END_IF;
    END_IF;
END_IF;

IF tmp_phase = 2 THEN
    tmp_completeSignal := FALSE;
    CASE tmp_currentStation OF
        2:
            tmp_completeSignal := station2Complete;
        3:
            tmp_completeSignal := station3Complete;
        4:
            tmp_completeSignal := station4Complete;
    ELSE
        tmp_completeSignal := FALSE;
    END_CASE;

    IF tmp_completeSignal THEN
        IF tmp_seqIndex < tmp_activeLength THEN
            tmp_seqIndex := tmp_seqIndex + 1;
            IF tmp_seqIndex <= tmp_activeLength THEN
                tmp_targetStation := processSequence[tmp_seqIndex];
                tmp_phase := 1;
            END_IF;
        END_IF;
    END_IF;
END_IF;

IF tmp_phase = 1 THEN
    IF tmp_targetStation > tmp_currentStation THEN
        conveyorRight := TRUE;
    ELSIF tmp_targetStation < tmp_currentStation THEN
        conveyorLeft := TRUE;
    END_IF;

    tmp_destSensor := FALSE;
    CASE tmp_targetStation OF
        2:
            tmp_destSensor := sensor2;
        3:
            tmp_destSensor := sensor3;
        4:
            tmp_destSensor := sensor4;
        5:
            tmp_destSensor := sensor5;
    ELSE
        tmp_destSensor := FALSE;
    END_CASE;

    IF tmp_destSensor THEN
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
        tmp_currentStation := tmp_targetStation;

        IF tmp_currentStation = 5 THEN
            tmp_phase := 3;
        ELSE
            tmp_phase := 2;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK