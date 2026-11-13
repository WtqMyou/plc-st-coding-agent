(* ENGINEERING_CONTRACT *)
(*
1. State Machine: IDLE | MOVING | PROCESSING | DONE
   - IDLE: Wait for sensor1 + station1Start to begin sequence
   - MOVING: Conveyor active, track position until sensor confirms arrival
   - PROCESSING: At processing station (2-4), wait for completion signal
   - DONE: At station 5, reset to IDLE next scan

2. Output Behavior:
   - conveyorLeft: Activated when targetStation < currentPosition (left movement)
   - conveyorRight: Activated when targetStation > currentPosition (right movement)
   - Both outputs OFF in IDLE, PROCESSING, and DONE states
   - Mutually exclusive per physical-direction rule (PUB001)

3. Retention:
   - currentPosition: Retains value between scans (product location)
   - sequenceIndex: Retains value between scans; resets to 1 on IDLE entry
   - Outputs: Default to FALSE on first scan

4. First Scan:
   - currentPosition := 1, sequenceIndex := 1
   - No conveyor movement until start conditions met

5. Explicit Reset:
   - DONE state: sequenceIndex := processLength + 1
   - Returns to IDLE next scan; sequenceIndex reset to 1 on new start

6. Same-Scan Priority:
   - Position update and conveyor enable use same-scan sensor values
   - Target station check confirms via sensor before stopping conveyor
   - No additional scan delay introduced

7. Units/Boundaries:
   - processLength: 1..8
   - currentPosition: 1..5 (station numbers)
   - sequenceIndex: 1..processLength+1
   - Stations: 1=loading, 2-4=processing, 5=output/storage
   - Station 5 has no completion signal (PUB003)
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FlexibleProcessingControl
VAR_INPUT
    processLength : USINT := 8;
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
    state : (IDLE, MOVING, PROCESSING, DONE) := IDLE;
    currentPosition : USINT := 1;
    sequenceIndex : USINT := 1;
    targetStation : USINT;
END_VAR

// Reset outputs by default
conveyorLeft := FALSE;
conveyorRight := FALSE;

// State machine implementation
CASE state OF
    IDLE:
        // Wait for material at station 1 and start button
        IF sensor1 AND station1Start THEN
            sequenceIndex := 1;
            targetStation := processSequence[sequenceIndex];
            sequenceIndex := sequenceIndex + 1;
            state := MOVING;
        END_IF;
    
    MOVING:
        // Determine conveyor direction and move toward target
        IF targetStation > currentPosition THEN
            currentPosition := currentPosition + 1;
            conveyorRight := TRUE;
            conveyorLeft := FALSE;
        ELSIF targetStation < currentPosition THEN
            currentPosition := currentPosition - 1;
            conveyorLeft := TRUE;
            conveyorRight := FALSE;
        END_IF;
        
        // Check if product reached target station via sensor confirmation
        IF currentPosition = targetStation THEN
            // Verify arrival with appropriate sensor
            IF (currentPosition = 1 AND sensor1) OR
               (currentPosition = 2 AND sensor2) OR
               (currentPosition = 3 AND sensor3) OR
               (currentPosition = 4 AND sensor4) OR
               (currentPosition = 5 AND sensor5) THEN
                conveyorLeft := FALSE;
                conveyorRight := FALSE;
                
                // Station 5 is output/storage - no completion signal
                IF currentPosition = 5 THEN
                    state := DONE;
                ELSE
                    state := PROCESSING;
                END_IF;
            END_IF;
        END_IF;
    
    PROCESSING:
        // Wait for processing completion at stations 2-4
        IF (currentPosition = 2 AND station2Complete) OR
           (currentPosition = 3 AND station3Complete) OR
           (currentPosition = 4 AND station4Complete) THEN
            // Check if next target is station 5 (final output)
            IF targetStation = 5 THEN
                state := DONE;
            ELSIF sequenceIndex <= processLength THEN
                targetStation := processSequence[sequenceIndex];
                sequenceIndex := sequenceIndex + 1;
                state := MOVING;
            ELSE
                // Sequence complete, product should be at station 5
                state := DONE;
            END_IF;
        END_IF;
    
    DONE:
        // Product reached station 5, prepare for next cycle
        sequenceIndex := processLength + 1;
        state := IDLE;
END_CASE;
END_FUNCTION_BLOCK