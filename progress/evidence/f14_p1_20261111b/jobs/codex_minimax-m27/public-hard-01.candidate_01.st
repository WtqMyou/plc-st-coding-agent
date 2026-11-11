// Material Proportioning Process Control - ST Implementation
// Supports Manual and Automatic modes with Emergency Stop

// ============================================================================
// Variable Declarations
// ============================================================================
VAR
    // System Inputs
    estop            : BOOL;   // Emergency Stop Signal (FALSE = triggered)
    opeMode          : BOOL;   // Operation Mode (FALSE = Manual, TRUE = Auto)
    valveAStart      : BOOL;   // Valve A Start Button
    valveBStart      : BOOL;   // Valve B Start Button
    valveCStart      : BOOL;   // Valve C Start Button
    valveDStart      : BOOL;   // Valve D Start Button
    mixMotorStart    : BOOL;   // Mixing Motor Start Button
    autoStart        : BOOL;   // Automatic Start Button
    processMode      : BOOL;   // Process Mode (FALSE = Basic, TRUE = Extended)
    levelSensor      : INT;    // Liquid Level Sensor (unit: cm)
    mixMotorComplete : BOOL;   // Mixing Complete Signal
    
    // System Outputs
    valveARun  : BOOL;   // Valve A Run Command
    valveBRun  : BOOL;   // Valve B Run Command
    valveCRun  : BOOL;   // Valve C Run Command
    valveDRun  : BOOL;   // Valve D Run Command
    mixMotorRun: BOOL;   // Mixing Motor Run Command
    
    // Internal Variables
    prevValveAStart   : BOOL;   // Previous state for edge detection
    prevValveBStart   : BOOL;
    prevValveCStart   : BOOL;
    prevValveDStart   : BOOL;
    prevMixMotorStart : BOOL;
    prevAutoStart     : BOOL;
    
    // Automatic Mode State Machine
    autoState : INT;     // 0=IDLE, 1=FILL_A, 2=FILL_B, 3=MIX_BASIC, 
                         // 4=FILL_C, 5=MIX_EXT, 6=DRAIN
END_VAR

// ============================================================================
// Constants for State Machine
// ============================================================================
VAR CONSTANT
    STATE_IDLE      : INT := 0;
    STATE_FILL_A    : INT := 1;
    STATE_FILL_B    : INT := 2;
    STATE_MIX_BASIC : INT := 3;
    STATE_FILL_C    : INT := 4;
    STATE_MIX_EXT   : INT := 5;
    STATE_DRAIN     : INT := 6;
END_VAR

// ============================================================================
// Main Control Logic
// ============================================================================

// ---------------------------------------------------------------------------
// Emergency Stop Logic
// When estop=FALSE, all equipment stops immediately
// ---------------------------------------------------------------------------
IF NOT estop THEN
    // Emergency stop: immediate shutdown of all outputs
    valveARun  := FALSE;
    valveBRun  := FALSE;
    valveCRun  := FALSE;
    valveDRun  := FALSE;
    mixMotorRun:= FALSE;
    autoState  := STATE_IDLE;
    
    // Reset edge detection flags to prevent spurious triggers after estop release
    prevValveAStart   := FALSE;
    prevValveBStart   := FALSE;
    prevValveCStart   := FALSE;
    prevValveDStart   := FALSE;
    prevMixMotorStart := FALSE;
    prevAutoStart     := FALSE;
    RETURN;  // Skip remaining logic when emergency stop is active
END_IF

// ---------------------------------------------------------------------------
// Mode Selection: Manual vs Automatic
// ---------------------------------------------------------------------------
IF NOT opeMode THEN
    // ============================
    // MANUAL OPERATION MODE
    // Toggle each device on rising edge of corresponding button
    // ============================
    
    // Valve A Toggle Control
    IF valveAStart AND NOT prevValveAStart THEN
        valveARun := NOT valveARun;
    END_IF
    prevValveAStart := valveAStart;
    
    // Valve B Toggle Control
    IF valveBStart AND NOT prevValveBStart THEN
        valveBRun := NOT valveBRun;
    END_IF
    prevValveBStart := valveBStart;
    
    // Valve C Toggle Control
    IF valveCStart AND NOT prevValveCStart THEN
        valveCRun := NOT valveCRun;
    END_IF
    prevValveCStart := valveCStart;
    
    // Valve D Toggle Control
    IF valveDStart AND NOT prevValveDStart THEN
        valveDRun := NOT valveDRun;
    END_IF
    prevValveDStart := valveDStart;
    
    // Mixing Motor Toggle Control
    IF mixMotorStart AND NOT prevMixMotorStart THEN
        mixMotorRun := NOT mixMotorRun;
    END_IF
    prevMixMotorStart := mixMotorStart;

ELSE
    // ============================
    // AUTOMATIC OPERATION MODE
    // Sequential process control based on state machine
    // ============================
    
    // Reset manual control outputs when switching to auto mode
    valveARun  := FALSE;
    valveBRun  := FALSE;
    valveCRun  := FALSE;
    valveDRun  := FALSE;
    mixMotorRun:= FALSE;
    
    // Start automatic process on rising edge of autoStart button
    IF autoStart AND NOT prevAutoStart THEN
        IF autoState = STATE_IDLE THEN
            autoState := STATE_FILL_A;  // Begin the automatic sequence
        END_IF
    END_IF
    prevAutoStart := autoStart;
    
    // ---------------------------------------------------------------------------
    // Automatic Mode State Machine
    // ---------------------------------------------------------------------------
    CASE autoState OF
        
        STATE_IDLE:
            // Wait for autoStart button press
            valveARun  := FALSE;
            valveBRun  := FALSE;
            valveCRun  := FALSE;
            valveDRun  := FALSE;
            mixMotorRun:= FALSE;
        
        STATE_FILL_A:
            // Open Valve A to fill tank
            valveARun := TRUE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            
            // When level reaches 50cm, close Valve A and proceed to Valve B
            IF levelSensor >= 50 THEN
                valveARun := FALSE;
                autoState := STATE_FILL_B;
            END_IF
        
        STATE_FILL_B:
            // Open Valve B to continue filling
            valveARun := FALSE;
            valveBRun := TRUE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            
            // When level reaches 80cm, close Valve B
            IF levelSensor >= 80 THEN
                valveBRun := FALSE;
                
                // Branch based on processMode
                IF NOT processMode THEN
                    // Basic Mode: Start mixing directly
                    autoState := STATE_MIX_BASIC;
                ELSE
                    // Extended Mode: Open Valve C for additional fill
                    autoState := STATE_FILL_C;
                END_IF
            END_IF
        
        STATE_MIX_BASIC:
            // Basic Mode: Start mixing motor
            valveARun  := FALSE;
            valveBRun  := FALSE;
            valveCRun  := FALSE;
            valveDRun  := FALSE;
            mixMotorRun := TRUE;
            
            // When mixing complete, stop motor and open drain valve
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                autoState := STATE_DRAIN;
            END_IF
        
        STATE_FILL_C:
            // Extended Mode: Open Valve C for additional material
            valveARun  := FALSE;
            valveBRun  := FALSE;
            valveCRun  := TRUE;
            valveDRun  := FALSE;
            mixMotorRun := FALSE;
            
            // When level reaches 100cm, close Valve C and start mixing
            IF levelSensor >= 100 THEN
                valveCRun := FALSE;
                autoState := STATE_MIX_EXT;
            END_IF
        
        STATE_MIX_EXT:
            // Extended Mode: Start mixing motor
            valveARun  := FALSE;
            valveBRun  := FALSE;
            valveCRun  := FALSE;
            valveDRun  := FALSE;
            mixMotorRun := TRUE;
            
            // When mixing complete, stop motor and open drain valve
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                autoState := STATE_DRAIN;
            END_IF
        
        STATE_DRAIN:
            // Open Valve D to drain tank (deliver to next process)
            valveARun  := FALSE;
            valveBRun  := FALSE;
            valveCRun  := FALSE;
            valveDRun  := TRUE;
            mixMotorRun := FALSE;
            
            // Return to idle when tank is empty (level < 10cm)
            IF levelSensor < 10 THEN
                valveDRun := FALSE;
                autoState := STATE_IDLE;  // Process complete, ready for next cycle
            END_IF
    
    END_CASE

END_IF