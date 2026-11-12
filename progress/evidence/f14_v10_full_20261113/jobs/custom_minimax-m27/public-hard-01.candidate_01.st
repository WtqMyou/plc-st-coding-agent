FUNCTION_BLOCK MaterialProportioningControl
VAR_INPUT
    estop           : BOOL;          // Emergency Stop Signal (FALSE=triggered, TRUE=ok)
    opeMode         : BOOL;          // Operation Mode (FALSE=Manual, TRUE=Auto)
    valveAStart     : BOOL;          // Valve A Start Button
    valveBStart     : BOOL;          // Valve B Start Button
    valveCStart     : BOOL;          // Valve C Start Button
    valveDStart     : BOOL;          // Valve D Start Button
    mixMotorStart   : BOOL;          // Mixing Motor Start Button
    autoStart       : BOOL;          // Automatic Start Button
    processMode     : BOOL;          // Process Mode (FALSE=direct mix, TRUE=add C)
    levelSensor     : INT;           // Liquid Level Sensor (cm)
    mixMotorComplete: BOOL;          // Mixing Complete Signal
END_VAR
VAR_OUTPUT
    valveARun       : BOOL;          // Valve A Run Command
    valveBRun       : BOOL;          // Valve B Run Command
    valveCRun       : BOOL;          // Valve C Run Command
    valveDRun       : BOOL;          // Valve D Run Command
    mixMotorRun     : BOOL;          // Mixing Motor Run Command
END_VAR
VAR
    // Rising edge detectors for manual toggle buttons
    Rtrig_valveAStart    : R_TRIG;
    Rtrig_valveBStart    : R_TRIG;
    Rtrig_valveCStart    : R_TRIG;
    Rtrig_valveDStart    : R_TRIG;
    Rtrig_mixMotorStart  : R_TRIG;
    Rtrig_autoStart      : R_TRIG;

    // Auto sequence state machine
    autoState : INT;  // 0=IDLE, 1=FILL_A, 2=FILL_B, 3=FILL_C, 4=MIXING, 5=FINISH
END_VAR
VAR CONSTANT
    STATE_IDLE    : INT := 0;
    STATE_FILL_A  : INT := 1;
    STATE_FILL_B  : INT := 2;
    STATE_FILL_C  : INT := 3;
    STATE_MIXING  : INT := 4;
    STATE_FINISH  : INT := 5;
END_VAR

// ENGINEERING_CONTRACT
// ---------------------------------------------------------------------------
// Output State Table:
// | Output       | Activation            | Retention           | Reset/Deactivation              | Priority
// |--------------|----------------------|---------------------|----------------------------------|------------
// | valveARun    | estop AND rising edge | Manual: hold toggle | estop OR auto sequence close     | estop=high
// | valveBRun    | estop AND rising edge | Manual: hold toggle | estop OR auto sequence close     | estop=high
// | valveCRun    | estop AND rising edge | Manual: hold toggle | estop OR auto sequence close     | estop=high
// | valveDRun    | estop AND rising edge | Manual: hold toggle | estop OR next autoStart rising   | estop=high
// | mixMotorRun  | estop AND rising edge | Manual: hold toggle | estop OR mixMotorComplete signal | estop=high
// ---------------------------------------------------------------------------
// Auto Sequence State Machine (processMode=FALSE: A->B->Mix->D):
//   STATE_IDLE --(rising autoStart)--> STATE_FILL_A
//   STATE_FILL_A --(level>=50)--> STATE_FILL_B
//   STATE_FILL_B --(level>=80 AND processMode=FALSE)--> STATE_MIXING
//   STATE_FILL_B --(level>=80 AND processMode=TRUE)--> STATE_FILL_C
//   STATE_FILL_C --(level>=100)--> STATE_MIXING
//   STATE_MIXING --(mixMotorComplete)--> STATE_FINISH
//   STATE_FINISH --(rising autoStart)--> STATE_FILL_A (restart)
// ---------------------------------------------------------------------------
// Boundary Conditions:
// - Level thresholds: 50cm (A->B), 80cm (B->C/idle), 100cm (C->Mix)
// - Strict >= comparisons per PUB006/PUB008/PUB009
// - No timer delays; sequence driven by levelSensor and mixMotorComplete
// - First scan: all outputs FALSE, autoState=IDLE
// - mixMotorComplete is edge-triggered signal (pulsed, not level)
// ---------------------------------------------------------------------------
// CONTRACT_RULES
// []
// ---------------------------------------------------------------------------

// Rising edge detection for all button inputs
Rtrig_valveAStart(CLK := valveAStart);
Rtrig_valveBStart(CLK := valveBStart);
Rtrig_valveCStart(CLK := valveCStart);
Rtrig_valveDStart(CLK := valveDStart);
Rtrig_mixMotorStart(CLK := mixMotorStart);
Rtrig_autoStart(CLK := autoStart);

// PUB001: Emergency Stop - highest priority, immediate stop all equipment
IF NOT estop THEN
    valveARun  := FALSE;
    valveBRun  := FALSE;
    valveCRun  := FALSE;
    valveDRun  := FALSE;
    mixMotorRun := FALSE;
    autoState   := STATE_IDLE;
    RETURN;
END_IF;

// PUB002: Manual Mode (opeMode=FALSE)
IF NOT opeMode THEN
    // PUB003: Valve A toggle on rising edge of valveAStart
    IF Rtrig_valveAStart.Q THEN
        valveARun := NOT valveARun;
    END_IF;

    // PUB004: Valve B toggle on rising edge of valveBStart
    IF Rtrig_valveBStart.Q THEN
        valveBRun := NOT valveBRun;
    END_IF;

    // PUB005: Valve C toggle on rising edge of valveCStart
    IF Rtrig_valveCStart.Q THEN
        valveCRun := NOT valveCRun;
    END_IF;

    // PUB010: Valve D toggle on rising edge of valveDStart
    IF Rtrig_valveDStart.Q THEN
        valveDRun := NOT valveDRun;
    END_IF;

    // PUB011: Mixing motor toggle on rising edge of mixMotorStart
    IF Rtrig_mixMotorStart.Q THEN
        mixMotorRun := NOT mixMotorRun;
    END_IF;

    RETURN;
END_IF;

// PUB006: Automatic Mode (opeMode=TRUE)
// Auto sequence state machine implementation
CASE autoState OF

    STATE_IDLE:
        // Initialize all outputs off
        valveARun  := FALSE;
        valveBRun  := FALSE;
        valveCRun  := FALSE;
        valveDRun  := FALSE;
        mixMotorRun := FALSE;

        // PUB007: Start auto sequence on rising edge of autoStart
        IF Rtrig_autoStart.Q THEN
            autoState  := STATE_FILL_A;
            valveARun := TRUE;
        END_IF;

    STATE_FILL_A:
        // PUB008: Level >= 50cm triggers transition to FILL_B
        IF levelSensor >= 50 THEN
            valveARun := FALSE;
            valveBRun := TRUE;
            autoState := STATE_FILL_B;
        END_IF;

    STATE_FILL_B:
        // PUB009: Level >= 80cm triggers transition based on processMode
        IF levelSensor >= 80 THEN
            valveBRun := FALSE;
            IF NOT processMode THEN
                // PUB012: processMode=FALSE, go directly to mixing
                mixMotorRun := TRUE;
                autoState   := STATE_MIXING;
            ELSE
                // PUB013: processMode=TRUE, open valve C
                valveCRun := TRUE;
                autoState := STATE_FILL_C;
            END_IF;
        END_IF;

    STATE_FILL_C:
        // PUB014: Level >= 100cm triggers transition to mixing
        IF levelSensor >= 100 THEN
            valveCRun  := FALSE;
            mixMotorRun := TRUE;
            autoState   := STATE_MIXING;
        END_IF;

    STATE_MIXING:
        // PUB015: mixMotorComplete signal stops motor and opens valve D
        IF mixMotorComplete THEN
            mixMotorRun := FALSE;
            valveDRun  := TRUE;
            autoState  := STATE_FINISH;
        END_IF;

    STATE_FINISH:
        // Hold valve D open until next autoStart rising edge (restart)
        IF Rtrig_autoStart.Q THEN
            valveDRun := FALSE;
            valveARun := TRUE;
            autoState := STATE_FILL_A;
        END_IF;

END_CASE;

END_FUNCTION_BLOCK