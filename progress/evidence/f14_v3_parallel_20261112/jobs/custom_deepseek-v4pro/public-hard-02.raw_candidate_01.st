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
    state : USINT := 0; (* 0: Idle, 1: Moving, 2: Processing *)
    seqIndex : USINT := 1;
    currentStation : USINT := 1;
    moveTarget : USINT := 1;
    
    lastStart : BOOL := FALSE;
    lastComp2 : BOOL := FALSE;
    lastComp3 : BOOL := FALSE;
    lastComp4 : BOOL := FALSE;
    
    startRise : BOOL := FALSE;
    comp2Rise : BOOL := FALSE;
    comp3Rise : BOOL := FALSE;
    comp4Rise : BOOL := FALSE;
    
    arrived : BOOL := FALSE;
    completion : BOOL := FALSE;
END_VAR

(* Input edge detection *)
startRise := station1Start AND NOT lastStart;
lastStart := station1Start;

comp2Rise := station2Complete AND NOT lastComp2;
lastComp2 := station2Complete;

comp3Rise := station3Complete AND NOT lastComp3;
lastComp3 := station3Complete;

comp4Rise := station4Complete AND NOT lastComp4;
lastComp4 := station4Complete;

(* Default outputs *)
conveyorLeft := FALSE;
conveyorRight := FALSE;

CASE state OF
    0: (* Idle *)
        IF sensor1 AND startRise THEN
            IF processLength >= 1 THEN
                seqIndex := 1;
                currentStation := 1;
                moveTarget := processSequence[1];
                state := 1;
            END_IF
        END_IF

    1: (* Moving *)
        IF moveTarget > currentStation THEN
            conveyorRight := TRUE;
            conveyorLeft := FALSE;
        ELSIF moveTarget < currentStation THEN
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        ELSE
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
        END_IF

        CASE moveTarget OF
            1: arrived := sensor1;
            2: arrived := sensor2;
            3: arrived := sensor3;
            4: arrived := sensor4;
            5: arrived := sensor5;
        ELSE
            arrived := FALSE;
        END_CASE

        IF arrived THEN
            conveyorLeft := FALSE;
            conveyorRight := FALSE;
            currentStation := moveTarget;

            IF moveTarget = 5 THEN
                state := 0; (* Finished: delivered to output station *)
            ELSE
                state := 2; (* Wait for processing completion *)
            END_IF
        END_IF

    2: (* Processing *)
        conveyorLeft := FALSE;
        conveyorRight := FALSE;

        CASE currentStation OF
            2: completion := comp2Rise;
            3: completion := comp3Rise;
            4: completion := comp4Rise;
        ELSE
            completion := FALSE;
        END_CASE

        IF completion THEN
            IF seqIndex < processLength THEN
                seqIndex := seqIndex + 1;
                moveTarget := processSequence[seqIndex];

                IF moveTarget = currentStation THEN
                    state := 2; (* Same station: wait for next completion *)
                ELSE
                    state := 1; (* Move to next station *)
                END_IF
            ELSE
                state := 0; (* Safety: no further sequence entry available *)
            END_IF
        END_IF
END_CASE

END_FUNCTION_BLOCK