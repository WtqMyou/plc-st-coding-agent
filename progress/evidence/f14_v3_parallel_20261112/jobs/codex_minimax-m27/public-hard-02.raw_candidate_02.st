TYPE
    ProcessState : INT (
        IDLE          := 0,
        LOADING       := 1,
        MOVING        := 2,
        WAIT_PROCESS  := 3,
        CHECK_SEQUENCE:= 4
    );
END_TYPE

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
    internalState     : ProcessState;
    currentStation    : USINT;
    sequenceIndex     : USINT;
    targetStation     : USINT;
    prevSensor1       : BOOL;
    prevSensor2       : BOOL;
    prevSensor3       : BOOL;
    prevSensor4       : BOOL;
    prevSensor5       : BOOL;
    waitComplete      : BOOL;
END_VAR

CASE internalState OF
    IDLE:
        conveyorLeft  := FALSE;
        conveyorRight := FALSE;
        IF sensor1 AND station1Start THEN
            sequenceIndex  := 1;
            targetStation := processSequence[1];
            currentStation := 1;
            internalState := LOADING;
        END_IF;

    LOADING:
        conveyorLeft  := FALSE;
        conveyorRight := FALSE;
        sequenceIndex := 1;
        targetStation := processSequence[1];
        currentStation := 1;
        internalState := MOVING;

    MOVING:
        IF sensor1 AND NOT prevSensor1 THEN
            currentStation := 1;
        END_IF;
        IF sensor2 AND NOT prevSensor2 THEN
            currentStation := 2;
        END_IF;
        IF sensor3 AND NOT prevSensor3 THEN
            currentStation := 3;
        END_IF;
        IF sensor4 AND NOT prevSensor4 THEN
            currentStation := 4;
        END_IF;
        IF sensor5 AND NOT prevSensor5 THEN
            currentStation := 5;
        END_IF;

        IF targetStation > currentStation THEN
            conveyorRight := TRUE;
            conveyorLeft  := FALSE;
        ELSIF targetStation < currentStation THEN
            conveyorLeft  := TRUE;
            conveyorRight := FALSE;
        ELSE
            conveyorLeft  := FALSE;
            conveyorRight := FALSE;
        END_IF;

        IF currentStation = targetStation THEN
            conveyorLeft  := FALSE;
            conveyorRight := FALSE;
            internalState := WAIT_PROCESS;
            waitComplete := FALSE;
        END_IF;

    WAIT_PROCESS:
        IF NOT waitComplete THEN
            waitComplete := TRUE;
        END_IF;

        IF waitComplete THEN
            IF targetStation = 2 AND station2Complete THEN
                sequenceIndex := sequenceIndex + 1;
                internalState := CHECK_SEQUENCE;
            ELSIF targetStation = 3 AND station3Complete THEN
                sequenceIndex := sequenceIndex + 1;
                internalState := CHECK_SEQUENCE;
            ELSIF targetStation = 4 AND station4Complete THEN
                sequenceIndex := sequenceIndex + 1;
                internalState := CHECK_SEQUENCE;
            ELSIF targetStation = 5 THEN
                sequenceIndex := sequenceIndex + 1;
                internalState := CHECK_SEQUENCE;
            END_IF;
        END_IF;

    CHECK_SEQUENCE:
        IF sequenceIndex > processLength THEN
            internalState := IDLE;
        ELSE
            targetStation := processSequence[sequenceIndex];
            internalState := MOVING;
        END_IF;
END_CASE;

prevSensor1 := sensor1;
prevSensor2 := sensor2;
prevSensor3 := sensor3;
prevSensor4 := sensor4;
prevSensor5 := sensor5;

END_FUNCTION_BLOCK