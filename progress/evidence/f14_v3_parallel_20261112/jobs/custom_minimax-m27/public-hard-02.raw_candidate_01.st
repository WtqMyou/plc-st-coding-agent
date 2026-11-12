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
    state          : (STATE_IDLE, STATE_MOVING);
    currentStep    : USINT;
    targetStation  : USINT;
    currentPosition: USINT;
END_VAR

CASE state OF
STATE_IDLE:
    conveyorLeft  := FALSE;
    conveyorRight := FALSE;
    IF sensor1 AND station1Start AND processLength >= 1 THEN
        currentStep := 1;
        targetStation := processSequence[1];
        state := STATE_MOVING;
    END_IF

STATE_MOVING:
    IF targetStation > currentPosition THEN
        conveyorRight := TRUE;
        conveyorLeft := FALSE;
        IF sensor2 AND targetStation = 2 THEN
            currentPosition := 2;
        ELSIF sensor3 AND targetStation = 3 THEN
            currentPosition := 3;
        ELSIF sensor4 AND targetStation = 4 THEN
            currentPosition := 4;
        ELSIF sensor5 AND targetStation = 5 THEN
            currentPosition := 5;
        END_IF
    ELSIF targetStation < currentPosition THEN
        conveyorLeft  := TRUE;
        conveyorRight := FALSE;
        IF sensor4 AND targetStation = 4 THEN
            currentPosition := 4;
        ELSIF sensor3 AND targetStation = 3 THEN
            currentPosition := 3;
        ELSIF sensor2 AND targetStation = 2 THEN
            currentPosition := 2;
        ELSIF sensor1 AND targetStation = 1 THEN
            currentPosition := 1;
        END_IF
    END_IF
    IF currentPosition = targetStation THEN
        conveyorLeft  := FALSE;
        conveyorRight := FALSE;
        IF targetStation = 5 THEN
            state := STATE_IDLE;
        ELSE
            IF station2Complete AND targetStation = 2 THEN
                currentStep := currentStep + 1;
                IF currentStep <= processLength THEN
                    targetStation := processSequence[currentStep];
                    state := STATE_MOVING;
                ELSE
                    state := STATE_IDLE;
                END_IF;
            ELSIF station3Complete AND targetStation = 3 THEN
                currentStep := currentStep + 1;
                IF currentStep <= processLength THEN
                    targetStation := processSequence[currentStep];
                    state := STATE_MOVING;
                ELSE
                    state := STATE_IDLE;
                END_IF;
            ELSIF station4Complete AND targetStation = 4 THEN
                currentStep := currentStep + 1;
                IF currentStep <= processLength THEN
                    targetStation := processSequence[currentStep];
                    state := STATE_MOVING;
                ELSE
                    state := STATE_IDLE;
                END_IF;
            END_IF;
        END_IF;
    END_IF;
END_CASE;
END_FUNCTION_BLOCK