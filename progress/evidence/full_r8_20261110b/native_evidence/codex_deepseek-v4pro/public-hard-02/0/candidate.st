FUNCTION_BLOCK FB
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
    idx : USINT := 0;
    currentStation : USINT := 1;
    running : BOOL := FALSE;
    waiting : BOOL := FALSE;
    target : USINT := 0;
    tgtSensor : BOOL := FALSE;
    completionEdge : BOOL := FALSE;
    lastComp2 : BOOL := FALSE;
    lastComp3 : BOOL := FALSE;
    lastComp4 : BOOL := FALSE;
    validLength : BOOL := FALSE;
END_VAR

validLength := (processLength >= 1) AND (processLength <= 8);

IF NOT validLength THEN
    conveyorLeft := FALSE;
    conveyorRight := FALSE;
    running := FALSE;
    waiting := FALSE;
ELSE
    IF NOT running THEN
        waiting := FALSE;
        IF sensor1 AND station1Start THEN
            idx := 1;
            currentStation := 1;
            running := TRUE;
        END_IF
    ELSE
        IF waiting THEN
            completionEdge := FALSE;
            IF target = 2 THEN
                completionEdge := station2Complete AND NOT lastComp2;
            ELSIF target = 3 THEN
                completionEdge := station3Complete AND NOT lastComp3;
            ELSIF target = 4 THEN
                completionEdge := station4Complete AND NOT lastComp4;
            END_IF
            IF completionEdge THEN
                waiting := FALSE;
                idx := idx + 1;
                IF idx > processLength THEN
                    running := FALSE;
                    idx := 0;
                    currentStation := 5;
                END_IF
            END_IF
        ELSE
            target := processSequence[idx];
            tgtSensor := FALSE;
            IF target = 2 THEN
                tgtSensor := sensor2;
            ELSIF target = 3 THEN
                tgtSensor := sensor3;
            ELSIF target = 4 THEN
                tgtSensor := sensor4;
            ELSIF target = 5 THEN
                tgtSensor := sensor5;
            END_IF
            IF tgtSensor THEN
                currentStation := target;
                IF target = 5 THEN
                    running := FALSE;
                    idx := 0;
                    waiting := FALSE;
                ELSE
                    waiting := TRUE;
                END_IF
            END_IF
        END_IF
    END_IF

    conveyorLeft := FALSE;
    conveyorRight := FALSE;
    IF running AND NOT waiting THEN
        target := processSequence[idx];
        IF target > currentStation THEN
            conveyorRight := TRUE;
        ELSIF target < currentStation THEN
            conveyorLeft := TRUE;
        END_IF
    END_IF
END_IF

lastComp2 := station2Complete;
lastComp3 := station3Complete;
lastComp4 := station4Complete;

END_FUNCTION_BLOCK