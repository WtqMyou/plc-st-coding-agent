// Material Proportioning Process Control - ST Implementation
FUNCTION_BLOCK MaterialProportioning
VAR_INPUT
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
END_VAR

VAR_OUTPUT
    valveARun  : BOOL;   // Valve A Run Command
    valveBRun  : BOOL;   // Valve B Run Command
    valveCRun  : BOOL;   // Valve C Run Command
    valveDRun  : BOOL;   // Valve D Run Command
    mixMotorRun: BOOL;   // Mixing Motor Run Command
END_VAR

VAR
    prevValveAStart   : BOOL;   // Previous state for edge detection
    prevValveBStart   : BOOL;
    prevValveCStart   : BOOL;
    prevValveDStart   : BOOL;
    prevMixMotorStart : BOOL;
    prevAutoStart     : BOOL;
    autoState : INT;     // 0=IDLE, 1=FILL_A, 2=FILL_B, 3=MIX_BASIC, 
                         // 4=FILL_C, 5=MIX_EXT, 6=DRAIN
END_VAR

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
    valveARun  := FALSE;
    valveBRun  := FALSE;
    valveCRun  := FALSE;
    valveDRun  := FALSE;
    mixMotorRun:= FALSE;
    autoState  := STATE_IDLE;
    
    prevValveAStart   := FALSE;
    prevValveBStart   := FALSE;
    prevValveCStart   := FALSE;
    prevValveDStart   := FALSE;
    prevMixMotorStart := FALSE;
    prevAutoStart     := FALSE;
    RETURN;
END_IF

// ---------------------------------------------------------------------------
// Mode Selection: Manual vs Automatic
// ---------------------------------------------------------------------------
IF NOT opeMode THEN
    // MANUAL OPERATION MODE
    // Toggle each device on rising edge of corresponding button
    
    IF valveAStart AND NOT prevValveAStart THEN
        valveARun := NOT valveARun;
    END_IF;
    prevValveAStart := valveAStart;
    
    IF valveBStart AND NOT prevValveBStart THEN
        valveBRun := NOT valveBRun;
    END_IF;
    prevValveBStart := valveBStart;
    
    IF valveCStart AND NOT prevValveCStart THEN
        valveCRun := NOT valveCRun;
    END_IF;
    prevValveCStart := valveCStart;
    
    IF valveDStart AND NOT prevValveDStart THEN
        valveDRun := NOT valveDRun;
    END_IF;
    prevValveDStart := valveDStart;
    
    IF mixMotorStart AND NOT prevMixMotorStart THEN
        mixMotorRun := NOT mixMotorRun;
    END_IF;
    prevMixMotorStart := mixMotorStart;

ELSE
    // AUTOMATIC OPERATION MODE
    
    valveARun  := FALSE;
    valveBRun  := FALSE;
    valveCRun  := FALSE;
    valveDRun  := FALSE;
    mixMotorRun:= FALSE;
    
    IF autoStart AND NOT prevAutoStart THEN
        IF autoState = STATE_IDLE THEN
            autoState := STATE_FILL_A;
        END_IF;
    END_IF;
    prevAutoStart := autoStart;
    
    CASE autoState OF
        
        STATE_IDLE:
            valveARun  := FALSE;
            valveBRun  := FALSE;
            valveCRun  := FALSE;
            valveDRun  := FALSE;
            mixMotorRun:= FALSE;
        
        STATE_FILL_A:
            valveARun := TRUE;
            IF levelSensor >= 50 THEN
                valveARun := FALSE;
                autoState := STATE_FILL_B;
            END_IF;
        
        STATE_FILL_B:
            valveBRun := TRUE;
            IF levelSensor >= 80 THEN
                valveBRun := FALSE;
                IF NOT processMode THEN
                    autoState := STATE_MIX_BASIC;
                ELSE
                    autoState := STATE_FILL_C;
                END_IF;
            END_IF;
        
        STATE_MIX_BASIC:
            mixMotorRun := TRUE;
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                autoState := STATE_DRAIN;
            END_IF;
        
        STATE_FILL_C:
            valveCRun := TRUE;
            IF levelSensor >= 100 THEN
                valveCRun := FALSE;
                autoState := STATE_MIX_EXT;
            END_IF;
        
        STATE_MIX_EXT:
            mixMotorRun := TRUE;
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                autoState := STATE_DRAIN;
            END_IF;
        
        STATE_DRAIN:
            valveDRun := TRUE;
            IF levelSensor < 10 THEN
                valveDRun := FALSE;
                autoState := STATE_IDLE;
            END_IF;
    
    END_CASE;

END_IF;

END_FUNCTION_BLOCK

PROGRAM PLC_PRG
VAR
    inst : MaterialProportioning;
END_VAR

inst(
    estop            := estop,
    opeMode          := opeMode,
    valveAStart      := valveAStart,
    valveBStart      := valveBStart,
    valveCStart      := valveCStart,
    valveDStart      := valveDStart,
    mixMotorStart    := mixMotorStart,
    autoStart        := autoStart,
    processMode      := processMode,
    levelSensor      := levelSensor,
    mixMotorComplete := mixMotorComplete,
    valveARun        => valveARun,
    valveBRun        => valveBRun,
    valveCRun        => valveCRun,
    valveDRun        => valveDRun,
    mixMotorRun      => mixMotorRun
);
END_PROGRAM