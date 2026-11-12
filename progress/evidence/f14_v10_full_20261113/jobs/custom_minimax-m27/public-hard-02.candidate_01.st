(* ENGINEERING_CONTRACT
   +------------------------------------------------------------------+
   | State Machine: 3 states (IDLE/MOVING/PROCESSING), 1-indexed steps |
   | Output: conveyorLeft, conveyorRight - momentary while MOVING     |
   | Reset: implicit on rising edge of (sensor1 AND station1Start)    |
   | Same-scan: targetStation latched before state transition         |
   | PUB002: station1Start and sensor1 together start sequence         |
   | PUB003: conveyor direction by station number comparison           |
   | PUB005: processSequence[1..processLength] defines step targets    |
   | PUB006: final entry must be station 5; sensor5 = arrival = done  |
   +------------------------------------------------------------------+
   
   CONTRACT_RULES []
*)
FUNCTION_BLOCK FlexibleProcessingControl
VAR_INPUT
    processLength     : USINT;          (* 1..8, final entry is 5 *)
    sensor1           : BOOL;           (* Station 1 sensor *)
    sensor2           : BOOL;           (* Station 2 sensor *)
    sensor3           : BOOL;           (* Station 3 sensor *)
    sensor4           : BOOL;           (* Station 4 sensor *)
    sensor5           : BOOL;           (* Station 5 sensor *)
    station1Start     : BOOL;           (* Start button at station 1 *)
    station2Complete  : BOOL;           (* Station 2 processing done *)
    station3Complete  : BOOL;           (* Station 3 processing done *)
    station4Complete  : BOOL;           (* Station 4 processing done *)
    processSequence   : ARRAY[1..8] OF USINT;
END_VAR
VAR_OUTPUT
    conveyorLeft      : BOOL;
    conveyorRight     : BOOL;
END_VAR
VAR
    State : (IDLE, MOVING, PROCESSING);
    currentStepIndex : USINT := 0;
    targetStation    : USINT := 1;
END_VAR

    CASE State OF
        IDLE:
            conveyorLeft  := FALSE;
            conveyorRight := FALSE;
            (* PUB002: Start when raw material at station 1 AND start pressed *)
            IF sensor1 AND station1Start THEN
                currentStepIndex := 1;
                targetStation    := processSequence[currentStepIndex];
                State := MOVING;
            END_IF;

        MOVING:
            (* Determine conveyor direction based on station positions *)
            IF targetStation > 1 THEN
                conveyorRight := TRUE;
                conveyorLeft  := FALSE;
            ELSE
                conveyorLeft  := TRUE;
                conveyorRight := FALSE;
            END_IF;

            (* Check arrival at target station *)
            IF     (targetStation = 1 AND sensor1)
                OR (targetStation = 2 AND sensor2)
                OR (targetStation = 3 AND sensor3)
                OR (targetStation = 4 AND sensor4)
                OR (targetStation = 5 AND sensor5) THEN
                conveyorLeft  := FALSE;
                conveyorRight := FALSE;
                (* PUB006: Station 5 is final output; arrival = completion *)
                IF targetStation = 5 THEN
                    currentStepIndex := 0;
                    targetStation    := 1;
                    State := IDLE;
                ELSE
                    State := PROCESSING;
                END_IF;
            END_IF;

        PROCESSING:
            conveyorLeft  := FALSE;
            conveyorRight := FALSE;
            (* Wait for processing completion at current station *)
            IF     (targetStation = 2 AND station2Complete)
                OR (targetStation = 3 AND station3Complete)
                OR (targetStation = 4 AND station4Complete) THEN
                (* Advance to next sequence step *)
                currentStepIndex := currentStepIndex + 1;
                IF currentStepIndex <= processLength THEN
                    targetStation := processSequence[currentStepIndex];
                    State := MOVING;
                ELSE
                    currentStepIndex := 0;
                    targetStation    := 1;
                    State := IDLE;
                END_IF;
            END_IF;
    END_CASE;
END_FUNCTION_BLOCK