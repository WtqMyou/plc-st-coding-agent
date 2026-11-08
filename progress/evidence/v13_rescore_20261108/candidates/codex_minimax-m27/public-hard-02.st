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
    curStation : USINT := 0;
    dstStation : USINT := 0;
    idx : USINT := 1;
    prevStart : BOOL := FALSE;
    prevComp2 : BOOL := FALSE;
    prevComp3 : BOOL := FALSE;
    prevComp4 : BOOL := FALSE;
END_VAR

VAR
    startEdge : BOOL;
    compEdge : BOOL;
END_VAR

startEdge := station1Start AND NOT prevStart;
compEdge := (station2Complete AND NOT prevComp2) OR
            (station3Complete AND NOT prevComp3) OR
            (station4Complete AND NOT prevComp4);

prevStart := station1Start;
prevComp2 := station2Complete;
prevComp3 := station3Complete;
prevComp4 := station4Complete;

IF sensor1 AND startEdge THEN
    phase := 0;
    idx := 1;
    curStation := 1;
END_IF

CASE phase OF
    0:
        conveyorLeft := FALSE;
        conveyorRight := FALSE;
        IF sensor1 AND startEdge THEN
            curStation := 1;
            idx := 1;
            dstStation := processSequence[idx];
            phase := 1;
        END_IF

    1:
        IF dstStation > curStation THEN
            conveyorRight := TRUE;
            conveyorLeft := FALSE;
        ELSIF dstStation < curStation THEN
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        END_IF

        IF (dstStation = 2 AND sensor2) OR
           (dstStation = 3 AND sensor3) OR
           (dstStation = 4 AND sensor4) OR
           (dstStation = 5 AND sensor5) THEN
            curStation := dstStation;
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
            phase := 2;
        END_IF

    2:
        conveyorLeft := FALSE;
        conveyorRight := FALSE;

        IF compEdge THEN
            IF curStation = 2 THEN
                idx := idx + 1;
                IF idx <= processLength THEN
                    dstStation := processSequence[idx];
                    phase := 1;
                END_IF
            ELSIF curStation = 3 THEN
                idx := idx + 1;
                IF idx <= processLength THEN
                    dstStation := processSequence[idx];
                    phase := 1;
                END_IF
            ELSIF curStation = 4 THEN
                idx := idx + 1;
                IF idx <= processLength THEN
                    dstStation := processSequence[idx];
                    phase := 1;
                END_IF
            END_IF
        END_IF

        IF curStation = 5 THEN
            phase := 0;
        END_IF
END_CASE
END_FUNCTION_BLOCK