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
    phase : USINT := 0;
    curStation : USINT := 1;
    idx : USINT := 1;
    dstStation : USINT := 0;
    station1StartPrev : BOOL := FALSE;
    station2CompletePrev : BOOL := FALSE;
    station3CompletePrev : BOOL := FALSE;
    station4CompletePrev : BOOL := FALSE;
    sensor2Prev : BOOL := FALSE;
    sensor3Prev : BOOL := FALSE;
    sensor4Prev : BOOL := FALSE;
    sensor5Prev : BOOL := FALSE;
    station1StartRising : BOOL;
    station2CompleteRising : BOOL;
    station3CompleteRising : BOOL;
    station4CompleteRising : BOOL;
    sensor2Rising : BOOL;
    sensor3Rising : BOOL;
    sensor4Rising : BOOL;
    sensor5Rising : BOOL;
END_VAR

    station1StartRising := station1Start AND NOT station1StartPrev;
    station2CompleteRising := station2Complete AND NOT station2CompletePrev;
    station3CompleteRising := station3Complete AND NOT station3CompletePrev;
    station4CompleteRising := station4Complete AND NOT station4CompletePrev;
    sensor2Rising := sensor2 AND NOT sensor2Prev;
    sensor3Rising := sensor3 AND NOT sensor3Prev;
    sensor4Rising := sensor4 AND NOT sensor4Prev;
    sensor5Rising := sensor5 AND NOT sensor5Prev;

    IF phase = 0 THEN
        IF station1StartRising AND sensor1 THEN
            curStation := 1;
            idx := 1;
            dstStation := processSequence[idx];
            phase := 1;
        END_IF;
    ELSIF phase = 1 THEN
        IF (dstStation = 2 AND sensor2Rising) OR
           (dstStation = 3 AND sensor3Rising) OR
           (dstStation = 4 AND sensor4Rising) OR
           (dstStation = 5 AND sensor5Rising) THEN
            curStation := dstStation;
            IF dstStation = 5 THEN
                phase := 0;
                idx := 0;
            ELSE
                phase := 2;
            END_IF;
        END_IF;
    ELSIF phase = 2 THEN
        IF (curStation = 2 AND station2CompleteRising) OR
           (curStation = 3 AND station3CompleteRising) OR
           (curStation = 4 AND station4CompleteRising) THEN
            idx := idx + 1;
            dstStation := processSequence[idx];
            phase := 1;
        END_IF;
    ELSE
        phase := 0;
    END_IF;

    IF phase = 1 THEN
        IF dstStation > curStation THEN
            conveyorRight := TRUE;
            conveyorLeft := FALSE;
        ELSIF dstStation < curStation THEN
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

    station1StartPrev := station1Start;
    station2CompletePrev := station2Complete;
    station3CompletePrev := station3Complete;
    station4CompletePrev := station4Complete;
    sensor2Prev := sensor2;
    sensor3Prev := sensor3;
    sensor4Prev := sensor4;
    sensor5Prev := sensor5;

END_FUNCTION_BLOCK