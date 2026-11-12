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
    state : USINT := 0;
    currentIndex : INT := 1;
    currentStation : USINT := 1;
    targetStation : USINT := 0;
END_VAR

IF sensor1 AND station1Start THEN
    currentIndex := 1;
    currentStation := 1;
    targetStation := processSequence[currentIndex];
    state := 1;
END_IF;

IF state = 1 THEN
    CASE targetStation OF
        2:
            IF sensor2 THEN
                currentStation := 2;
                state := 2;
            END_IF;
        3:
            IF sensor3 THEN
                currentStation := 3;
                state := 2;
            END_IF;
        4:
            IF sensor4 THEN
                currentStation := 4;
                state := 2;
            END_IF;
        5:
            IF sensor5 THEN
                currentStation := 5;
                state := 3;
            END_IF;
    END_CASE;
END_IF;

IF state = 2 THEN
    CASE currentStation OF
        2:
            IF station2Complete THEN
                currentIndex := currentIndex + 1;
                targetStation := processSequence[currentIndex];
                state := 1;
            END_IF;
        3:
            IF station3Complete THEN
                currentIndex := currentIndex + 1;
                targetStation := processSequence[currentIndex];
                state := 1;
            END_IF;
        4:
            IF station4Complete THEN
                currentIndex := currentIndex + 1;
                targetStation := processSequence[currentIndex];
                state := 1;
            END_IF;
    END_CASE;
END_IF;

IF (state = 1) AND (targetStation > currentStation) THEN
    conveyorRight := TRUE;
    conveyorLeft := FALSE;
ELSIF (state = 1) AND (targetStation < currentStation) THEN
    conveyorLeft := TRUE;
    conveyorRight := FALSE;
ELSE
    conveyorLeft := FALSE;
    conveyorRight := FALSE;
END_IF;

END_FUNCTION_BLOCK