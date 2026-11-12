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
    currentStep : USINT := 0;
    currentIndex : INT := 1;
    currentStation : USINT := 1;
    targetStation : USINT := 0;
END_VAR

CASE currentStep OF
    0:
        IF sensor1 AND station1Start THEN
            currentIndex := 1;
            currentStation := 1;
            targetStation := processSequence[currentIndex];
            currentStep := 1;
        END_IF;

    1:
        IF targetStation = 2 AND sensor2 THEN
            currentStation := 2;
            currentStep := 2;
        ELSIF targetStation = 3 AND sensor3 THEN
            currentStation := 3;
            currentStep := 2;
        ELSIF targetStation = 4 AND sensor4 THEN
            currentStation := 4;
            currentStep := 2;
        ELSIF targetStation = 5 AND sensor5 THEN
            currentStation := 5;
            currentStep := 3;
        END_IF;

    2:
        IF currentStation = 2 AND station2Complete THEN
            currentIndex := currentIndex + 1;
            targetStation := processSequence[currentIndex];
            currentStep := 1;
        ELSIF currentStation = 3 AND station3Complete THEN
            currentIndex := currentIndex + 1;
            targetStation := processSequence[currentIndex];
            currentStep := 1;
        ELSIF currentStation = 4 AND station4Complete THEN
            currentIndex := currentIndex + 1;
            targetStation := processSequence[currentIndex];
            currentStep := 1;
        END_IF;
END_CASE;

IF currentStep = 1 AND targetStation > currentStation THEN
    conveyorLeft := FALSE;
    conveyorRight := TRUE;
ELSIF currentStep = 1 AND targetStation < currentStation THEN
    conveyorLeft := TRUE;
    conveyorRight := FALSE;
ELSE
    conveyorLeft := FALSE;
    conveyorRight := FALSE;
END_IF;

END_FUNCTION_BLOCK