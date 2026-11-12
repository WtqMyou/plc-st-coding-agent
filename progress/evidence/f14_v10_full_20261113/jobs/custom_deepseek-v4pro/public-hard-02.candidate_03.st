(* ENGINEERING_CONTRACT
- Outputs conveyorLeft/deactivate in IDLE, PROCESSING and DONE; active only in MOVING state; no latch. PUB005.
- State machine: 0=IDLE waits sensor1 AND station1Start with valid length; 1=MOVING waits arrival at target sensor; 2=PROCESSING waits completion at current station 2..4; 3=DONE after station 5 arrival. PUB001/PUB002/PUB005.
- Movement direction: target station > current -> conveyorRight; target < current -> conveyorLeft; target == current stays at station for repeated processing step. PUB005.
- Completion signals are level-sensitive; on receiving completion, step advances, next sequence entry is queried, and movement restarts toward that station. PUB002.
- Final active sequence entry is station 5; arrival at 5 stops conveyor and enters DONE. A new start is permitted from DONE when the start condition is true. PUB003/PUB006.
- processLength validated 1..8; dynamic array indexing bounded by processLength; sequence values assumed to satisfy contract (2..4 processing, final 5). PUB004.
- Unspecified: exact restart behavior after DONE is level-sensitive on sensor1 and station1Start. No explicit reset input is used.
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
    local_state : USINT := 0; (* 0 = idle, 1 = moving, 2 = processing, 3 = done *)
    local_step : USINT := 0;
    local_target : USINT := 0;
    local_currentStation : USINT := 1;
    local_moveLeft : BOOL := FALSE;
    local_moveRight : BOOL := FALSE;
    local_arrival : BOOL := FALSE;
    local_complete : BOOL := FALSE;
END_VAR

(* Default outputs deactivated unless set by MOVING state *)
conveyorLeft := FALSE;
conveyorRight := FALSE;

CASE local_state OF
0: (* IDLE: wait for raw material at station 1 and start button *)
    IF processLength >= 1 AND processLength <= 8 AND sensor1 AND station1Start THEN
        local_step := 1;
        local_target := processSequence[1];
        local_currentStation := 1;
        IF local_target > local_currentStation THEN
            local_moveLeft := FALSE;
            local_moveRight := TRUE;
            local_state := 1;
        ELSIF local_target < local_currentStation THEN
            local_moveLeft := TRUE;
            local_moveRight := FALSE;
            local_state := 1;
        END_IF;
    END_IF;

1: (* MOVING: drive conveyor in chosen direction until target sensor detects arrival *)
    conveyorLeft := local_moveLeft;
    conveyorRight := local_moveRight;

    local_arrival := FALSE;
    IF local_target = 1 AND sensor1 THEN
        local_arrival := TRUE;
    ELSIF local_target = 2 AND sensor2 THEN
        local_arrival := TRUE;
    ELSIF local_target = 3 AND sensor3 THEN
        local_arrival := TRUE;
    ELSIF local_target = 4 AND sensor4 THEN
        local_arrival := TRUE;
    ELSIF local_target = 5 AND sensor5 THEN
        local_arrival := TRUE;
    END_IF;

    IF local_arrival THEN
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
        local_moveLeft := FALSE;
        local_moveRight := FALSE;
        local_currentStation := local_target;

        IF local_currentStation = 5 THEN
            local_state := 3; (* final output station reached *)
        ELSE
            local_state := 2; (* processing station reached *)
        END_IF;
    END_IF;

2: (* PROCESSING: wait for completion signal at current processing station *)
    local_complete := FALSE;
    IF local_currentStation = 2 THEN
        local_complete := station2Complete;
    ELSIF local_currentStation = 3 THEN
        local_complete := station3Complete;
    ELSIF local_currentStation = 4 THEN
        local_complete := station4Complete;
    END_IF;

    IF local_complete THEN
        IF local_step < processLength THEN
            local_step := local_step + 1;
            local_target := processSequence[local_step];

            IF local_target > local_currentStation THEN
                local_moveLeft := FALSE;
                local_moveRight := TRUE;
                local_state := 1;
            ELSIF local_target < local_currentStation THEN
                local_moveLeft := TRUE;
                local_moveRight := FALSE;
                local_state := 1;
            ELSE
                (* Same station: remain in processing for the next sequence entry *)
                local_state := 2;
            END_IF;
        ELSE
            (* Invalid sequence: current processing station is not followed by final station 5 *)
            local_state := 3;
        END_IF;
    END_IF;

3: (* DONE: product delivered to station 5; optionally wait for next start *)
    IF processLength >= 1 AND processLength <= 8 AND sensor1 AND station1Start THEN
        local_step := 1;
        local_target := processSequence[1];
        local_currentStation := 1;
        IF local_target > local_currentStation THEN
            local_moveLeft := FALSE;
            local_moveRight := TRUE;
            local_state := 1;
        ELSIF local_target < local_currentStation THEN
            local_moveLeft := TRUE;
            local_moveRight := FALSE;
            local_state := 1;
        END_IF;
    END_IF;
END_CASE;

END_FUNCTION_BLOCK