TYPE ProcessControl_State : (PC_IDLE, PC_MOVING, PC_WAITING); END_TYPE;

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
    state : ProcessControl_State := PC_IDLE;
    currentStation : USINT := 1;
    currentIndex : USINT := 1;
    targetStation : USINT := 0;
    targetSensor : BOOL := FALSE;
    local_rt_start : R_TRIG;
    local_rt_st2 : R_TRIG;
    local_rt_st3 : R_TRIG;
    local_rt_st4 : R_TRIG;
END_VAR

(*
ENGINEERING_CONTRACT
  conveyorLeft / conveyorRight activation: PC_MOVING state and target direction >/< currentStation (PUB001-PUB002).
  Retention/hold: outputs stay on each scan while PC_MOVING until target sensor TRUE (PUB002).
  Explicit reset/deactivation: sensor at target station stops motion and sets both outputs FALSE; next start new product.
  Same-scan priority: start request processed only in PC_IDLE; arrival stop and completion advancement are mutually exclusive by state.
  Units/boundaries: processLength 1..8; processSequence index 1..8; currentStation 1..5; final active entry 5 (PUB003).
  Direction: target > current -> conveyorRight; target < current -> conveyorLeft; target == current -> no movement, treated as arrived.
  Completion edge: rising edge of station2Complete/3/4Complete triggers next step.
  Unspecified: equal consecutive station entries skip movement and wait for completion; simultaneous completion inputs while WAITING use current station only.
*)

(* CONTRACT_RULES [] *)

local_rt_start(CLK := station1Start);
local_rt_st2(CLK := station2Complete);
local_rt_st3(CLK := station3Complete);
local_rt_st4(CLK := station4Complete);

CASE state OF
    PC_IDLE:
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
        IF local_rt_start.Q AND sensor1 THEN
            currentIndex := 1;
            currentStation := 1;
            targetStation := processSequence[currentIndex];
            IF targetStation = currentStation THEN
                IF targetStation = 5 THEN
                    state := PC_IDLE;
                ELSE
                    state := PC_WAITING;
                END_IF;
            ELSE
                state := PC_MOVING;
            END_IF;
        END_IF;

    PC_MOVING:
        targetSensor := FALSE;
        CASE targetStation OF
            2: targetSensor := sensor2;
            3: targetSensor := sensor3;
            4: targetSensor := sensor4;
            5: targetSensor := sensor5;
        END_CASE;

        IF targetStation > currentStation THEN
            conveyorLeft := FALSE;
            conveyorRight := TRUE;
        ELSIF targetStation < currentStation THEN
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        ELSE
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
        END_IF;

        IF targetSensor THEN
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
            currentStation := targetStation;
            IF targetStation = 5 THEN
                state := PC_IDLE;
            ELSE
                state := PC_WAITING;
            END_IF;
        END_IF;

    PC_WAITING:
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
        IF (currentStation = 2 AND local_rt_st2.Q) OR
           (currentStation = 3 AND local_rt_st3.Q) OR
           (currentStation = 4 AND local_rt_st4.Q) THEN
            IF currentIndex < processLength THEN
                currentIndex := currentIndex + 1;
                targetStation := processSequence[currentIndex];
                IF targetStation = currentStation THEN
                    IF targetStation = 5 THEN
                        state := PC_IDLE;
                    ELSE
                        state := PC_WAITING;
                    END_IF;
                ELSE
                    state := PC_MOVING;
                END_IF;
            ELSE
                state := PC_IDLE;
            END_IF;
        END_IF;
END_CASE;