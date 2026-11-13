(*
ENGINEERING_CONTRACT
- conveyorLeft | activation: ST_MOVING and target<current | hold: while ST_MOVING | reset: target sensor arrival or non-moving state | same-scan: final settled state/target controls write | PUB001,PUB005.
- conveyorRight | activation: ST_MOVING and target>current | hold: while ST_MOVING | reset: target sensor arrival or non-moving state | same-scan: final settled state/target controls write | PUB001,PUB005.
- local_state | activation: ST_IDLE+start -> ST_MOVING; ST_MOVING+sensor -> ST_WAIT_COMPLETION/ST_DONE/next ST_MOVING; ST_WAIT_COMPLETION+completion -> ST_MOVING/ST_DONE | hold: retained every scan | reset/deactivation: above transitions | same-scan: one transition per scan based on current public inputs | units: seq index 1..processLength, stations 1..5 | PUB001-PUB005.
- local_step_index/current/target | update: start, sensor, completion | hold: otherwise | bounds: step 1..8, current/target 1..5 | PUB002,PUB005.
- Direction rule: one target per step yields exactly one direction output; equal/unknown target de-energizes both.
- Unspecified: completion signals treated as levels; ST_DONE restarts on sensor1 AND station1Start.
*)
(* CONTRACT_RULES [] *)

TYPE CONTROL_STATE :
(
    ST_IDLE,
    ST_MOVING,
    ST_WAIT_COMPLETION,
    ST_DONE
);
END_TYPE;

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
    local_state : CONTROL_STATE := ST_IDLE;
    local_step_index : USINT := 0;
    local_current_station : USINT := 1;
    local_target_station : USINT := 0;
    local_completion_active : BOOL := FALSE;
    local_target_sensor_active : BOOL := FALSE;
END_VAR

    local_completion_active := FALSE;
    IF local_target_station = 2 THEN
        local_completion_active := station2Complete;
    ELSIF local_target_station = 3 THEN
        local_completion_active := station3Complete;
    ELSIF local_target_station = 4 THEN
        local_completion_active := station4Complete;
    END_IF;

    local_target_sensor_active := FALSE;
    IF local_target_station = 2 THEN
        local_target_sensor_active := sensor2;
    ELSIF local_target_station = 3 THEN
        local_target_sensor_active := sensor3;
    ELSIF local_target_station = 4 THEN
        local_target_sensor_active := sensor4;
    ELSIF local_target_station = 5 THEN
        local_target_sensor_active := sensor5;
    END_IF;

    CASE local_state OF
        ST_IDLE:
            IF sensor1 AND station1Start THEN
                local_step_index := 1;
                local_current_station := 1;
                local_target_station := processSequence[1];
                local_state := ST_MOVING;
            END_IF;

        ST_MOVING:
            IF local_target_sensor_active THEN
                local_current_station := local_target_station;

                IF local_target_station = 5 THEN
                    local_state := ST_DONE;
                ELSIF local_completion_active THEN
                    IF local_step_index < processLength THEN
                        local_step_index := local_step_index + 1;
                        local_target_station := processSequence[local_step_index];
                        local_state := ST_MOVING;
                    ELSE
                        local_state := ST_DONE;
                    END_IF;
                ELSE
                    local_state := ST_WAIT_COMPLETION;
                END_IF;
            END_IF;

        ST_WAIT_COMPLETION:
            IF local_completion_active THEN
                IF local_step_index < processLength THEN
                    local_step_index := local_step_index + 1;
                    local_target_station := processSequence[local_step_index];
                    local_state := ST_MOVING;
                ELSE
                    local_state := ST_DONE;
                END_IF;
            END_IF;

        ST_DONE:
            IF sensor1 AND station1Start THEN
                local_step_index := 1;
                local_current_station := 1;
                local_target_station := processSequence[1];
                local_state := ST_MOVING;
            END_IF;
    END_CASE;

IF local_state = ST_MOVING THEN
    IF local_target_station > local_current_station THEN
        conveyorLeft := FALSE;
        conveyorRight := TRUE;
    ELSIF local_target_station < local_current_station THEN
        conveyorLeft := TRUE;
        conveyorRight := FALSE;
    ELSE
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
    END_IF;
ELSE
    conveyorLeft := FALSE;
    conveyorRight := FALSE;
END_IF;

END_FUNCTION_BLOCK