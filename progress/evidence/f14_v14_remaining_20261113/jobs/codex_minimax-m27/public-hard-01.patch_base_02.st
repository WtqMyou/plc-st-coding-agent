FUNCTION_BLOCK MaterialProportioning
VAR_INPUT
    estop           : BOOL;          // Emergency stop signal (FALSE = stopped)
    opeMode         : BOOL;          // Operation mode (FALSE = manual, TRUE = automatic)
    valveAStart     : BOOL;          // Valve A start button
    valveBStart     : BOOL;          // Valve B start button
    valveCStart     : BOOL;          // Valve C start button
    valveDStart     : BOOL;          // Valve D start button
    mixMotorStart   : BOOL;          // Mixing motor start button
    autoStart       : BOOL;          // Automatic start button
    processMode     : BOOL;          // Process mode (FALSE = simple, TRUE = with C)
    levelSensor     : INT;           // Liquid level sensor (cm)
    mixMotorComplete: BOOL;          // Mixing complete signal
END_VAR
VAR_OUTPUT
    valveARun       : BOOL;          // Valve A run command
    valveBRun       : BOOL;          // Valve B run command
    valveCRun       : BOOL;          // Valve C run command
    valveDRun       : BOOL;          // Valve D run command
    mixMotorRun     : BOOL;          // Mixing motor run command
END_VAR
VAR
    // Rising edge detection for manual toggle buttons
    tmp_autoStart rising  : R_TRIG;
    tmp_valveAStart rising: R_TRIG;
    tmp_valveBStart rising: R_TRIG;
    tmp_valveCStart rising: R_TRIG;
    tmp_valveDStart rising: R_TRIG;
    tmp_mixMotorStart rising: R_TRIG;
    
    // Automatic mode state machine
    tmp_autoState   : INT;           // 0=idle, 1=fillA, 2=fillB, 3=fillC, 4=mix, 5=drain, 6=done
    
    // Manual mode toggle states
    tmp_manualValveA    : BOOL;
    tmp_manualValveB    : BOOL;
    tmp_manualValveC    : BOOL;
    tmp_manualValveD    : BOOL;
    tmp_manualMixMotor  : BOOL;
    
    // Process complete flag for automatic mode
    tmp_autoComplete    : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
================================================================================
Output          | Activation                  | Retention      | Reset
----------------|------------------------------|----------------|-------------------------
valveARun       | Manual: rising valveAStart   | Hold toggle    | estop, opeMode, auto step
                | Auto: state=1, level<50      |                |
PUB001, PUB002, PUB003, PUB004, PUB005, PUB006, PUB007, PUB008
----------------|------------------------------|----------------|-------------------------
valveBRun       | Auto: state=2, level<80      | Hold until 80cm| estop, opeMode, auto step
                |                              |                |
PUB003, PUB004, PUB006, PUB007, PUB008
----------------|------------------------------|----------------|-------------------------
valveCRun       | Auto: state=3, level<100     | Hold until 100cm| estop, opeMode, auto step
                | (processMode=true only)      |                |
PUB003, PUB004, PUB006, PUB007, PUB008
----------------|------------------------------|----------------|-------------------------
valveDRun       | Auto: mixMotorComplete       | Hold until reset| estop, opeMode, autoStart
                |                              |                |
PUB007, PUB008, PUB011, PUB012, PUB013, PUB014, PUB015
----------------|------------------------------|----------------|-------------------------
mixMotorRun     | Auto: state=4                | Hold until complete| estop, opeMode, autoStart
                | Manual: rising mixMotorStart |                |
PUB007, PUB008, PUB011, PUB012, PUB013, PUB014, PUB015
================================================================================
Priority: estop > manual/automatic mode switch > same-scan state updates
Boundary: levelSensor thresholds at 50cm, 80cm, 100cm (>= comparisons)
================================================================================
*)

(* CONTRACT_RULES [] *)

// Detect rising edges for toggle buttons
rising(autoStart);
rising(valveAStart);
rising(valveBStart);
rising(valveCStart);
rising(valveDStart);
rising(mixMotorStart);

// Emergency stop: all equipment OFF immediately
IF NOT estop THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;
    tmp_autoState := 0;
    tmp_autoComplete := FALSE;
    tmp_manualValveA := FALSE;
    tmp_manualValveB := FALSE;
    tmp_manualValveC := FALSE;
    tmp_manualValveD := FALSE;
    tmp_manualMixMotor := FALSE;
    RETURN;
END_IF;

// Mode selection
IF opeMode THEN
    // AUTOMATIC MODE
    // Rising edge of autoStart initiates process
    IF rising.Q AND tmp_autoState = 0 THEN
        tmp_autoState := 1;
        tmp_autoComplete := FALSE;
    END_IF;
    
    // State machine execution
    CASE tmp_autoState OF
        0:  // Idle - all off
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
        
        1:  // Fill with valve A until level >= 50cm
            valveARun := TRUE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 50 THEN
                valveARun := FALSE;
                tmp_autoState := 2;
            END_IF;
        
        2:  // Fill with valve B until level >= 80cm
            valveARun := FALSE;
            valveBRun := TRUE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 80 THEN
                valveBRun := FALSE;
                // Check processMode to determine next state
                IF processMode THEN
                    tmp_autoState := 3;  // Go to valve C
                ELSE
                    tmp_autoState := 4;  // Go directly to mixing
                END_IF;
            END_IF;
        
        3:  // Fill with valve C (processMode=true) until level >= 100cm
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := TRUE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 100 THEN
                valveCRun := FALSE;
                tmp_autoState := 4;
            END_IF;
        
        4:  // Mixing until mixMotorComplete signal
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := TRUE;
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                tmp_autoState := 5;
            END_IF;
        
        5:  // Open valve D to drain
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := TRUE;
            mixMotorRun := FALSE;
            tmp_autoComplete := TRUE;
            tmp_autoState := 6;
        
        6:  // Process complete - valve D remains open until reset
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := TRUE;
            mixMotorRun := FALSE;
            // Wait for autoStart to reset
            IF rising.Q THEN
                tmp_autoState := 0;
                tmp_autoComplete := FALSE;
            END_IF;
    END_CASE;

ELSE
    // MANUAL MODE
    // Reset automatic state when switching to manual
    tmp_autoState := 0;
    tmp_autoComplete := FALSE;
    
    // Toggle valve A
    IF rising(valveAStart) THEN
        tmp_manualValveA := NOT tmp_manualValveA;
    END_IF;
    
    // Toggle valve B
    IF rising(valveBStart) THEN
        tmp_manualValveB := NOT tmp_manualValveB;
    END_IF;
    
    // Toggle valve C
    IF rising(valveCStart) THEN
        tmp_manualValveC := NOT tmp_manualValveC;
    END_IF;
    
    // Toggle valve D
    IF rising(valveDStart) THEN
        tmp_manualValveD := NOT tmp_manualValveD;
    END_IF;
    
    // Toggle mixing motor
    IF rising(mixMotorStart) THEN
        tmp_manualMixMotor := NOT tmp_manualMixMotor;
    END_IF;
    
    // Assign manual toggle states to outputs
    valveARun := tmp_manualValveA;
    valveBRun := tmp_manualValveB;
    valveCRun := tmp_manualValveC;
    valveDRun := tmp_manualValveD;
    mixMotorRun := tmp_manualMixMotor;
END_IF;

END_FUNCTION_BLOCK