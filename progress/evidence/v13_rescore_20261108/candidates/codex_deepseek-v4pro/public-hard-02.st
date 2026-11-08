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
    dstStation : USINT := 0;
    idx : USINT := 0;
    startEdge : BOOL;
    station2Edge : BOOL;
    station3Edge : BOOL;
    station4Edge : BOOL;
    compEdge : BOOL;
    lastStation1Start : BOOL;
    lastStation2Complete : BOOL;
    lastStation3Complete : BOOL;
    lastStation4Complete : BOOL;
END_VAR

startEdge := station1Start AND NOT lastStation1Start;
station2Edge := station2Complete AND NOT lastStation2Complete;
station3Edge := station3Complete AND NOT lastStation3Complete;
station4Edge := station4Complete AND NOT lastStation4Complete;

compEdge := FALSE;
IF phase = 2 THEN
    IF curStation = 2 THEN
        compEdge := station2Edge;
    ELSIF curStation = 3 THEN
        compEdge := station3Edge;
    ELSIF curStation = 4 THEN
        compEdge := station4Edge;
    END_IF;
END_IF;

IF phase = 0 THEN
    IF startEdge AND sensor1 THEN
        IF processLength >= 1 AND processLength <= 8 THEN
            idx := 1;
            dstStation := processSequence[1];
            phase := 1;
        END_IF;
    END_IF;
ELSIF phase = 1 THEN
    IF dstStation = 2 AND sensor2 THEN
        curStation := 2;
        phase := 2;
    ELSIF dstStation = 3 AND sensor3 THEN
        curStation := 3;
        phase := 2;
    ELSIF dstStation = 4 AND sensor4 THEN
        curStation := 4;
        phase := 2;
    ELSIF dstStation = 5 AND sensor5 THEN
        curStation := 5;
        phase := 0;
    END_IF;
ELSIF phase = 2 THEN
    IF compEdge THEN
        idx := idx + 1;
        IF idx <= processLength THEN
            dstStation := processSequence[idx];
            IF dstStation = curStation THEN
                phase := 2;
            ELSE
                phase := 1;
            END_IF;
        ELSE
            phase := 0;
        END_IF;
    END_IF;
END_IF;

conveyorLeft := FALSE;
conveyorRight := FALSE;
IF phase = 1 THEN
    IF dstStation > curStation THEN
        conveyorRight := TRUE;
    ELSIF dstStation < curStation THEN
        conveyorLeft := TRUE;
    END_IF;
END_IF;

lastStation1Start := station1Start;
lastStation2Complete := station2Complete;
lastStation3Complete := station3Complete;
lastStation4Complete := station4Complete;

END_FUNCTION_BLOCK