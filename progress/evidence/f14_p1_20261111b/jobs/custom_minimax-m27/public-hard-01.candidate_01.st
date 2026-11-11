(* Material Proportioning Process Control *)
(* PLC Program in Structured Text (ST) *)

TYPE ProcessState :
    (
        IDLE        := 0,
        FILL_A      := 1,
        FILL_B      := 2,
        FILL_C      := 3,
        MIXING      := 4,
        DISCHARGE   := 5
    );
END_TYPE

VAR
    (* Internal state variables *)
    autoState         : ProcessState := IDLE;
    prevAutoStart     : BOOL := FALSE;
    prevValveAStart   : BOOL := FALSE;
    prevValveBStart   : BOOL := FALSE;
    prevValveCStart   : BOOL := FALSE;
    prevValveDStart   : BOOL := FALSE;
    prevMixMotorStart : BOOL := FALSE;
END_VAR

(* Emergency Stop - Highest Priority *)
IF NOT estop THEN
    valveARun    := FALSE;
    valveBRun    := FALSE;
    valveCRun    := FALSE;
    valveDRun    := FALSE;
    mixMotorRun  := FALSE;
    autoState    := IDLE;
    RETURN;
END_IF

(* Rising edge detection for buttons *)
IF autoStart AND NOT prevAutoStart THEN
    (* Rising edge detected for autoStart *)
END_IF

IF valveAStart AND NOT prevValveAStart THEN
    valveARun := NOT valveARun;
END_IF;

IF valveBStart AND NOT prevValveBStart THEN
    valveBRun := NOT valveBRun;
END_IF;

IF valveCStart AND NOT prevValveCStart THEN
    valveCRun := NOT valveCRun;
END_IF;

IF valveDStart AND NOT prevValveDStart THEN
    valveDRun := NOT valveDRun;
END_IF;

IF mixMotorStart AND NOT prevMixMotorStart THEN
    mixMotorRun := NOT mixMotorRun;
END_IF;

(* Update previous button states *)
prevAutoStart     := autoStart;
prevValveAStart   := valveAStart;
prevValveBStart   := valveBStart;
prevValveCStart   := valveCStart;
prevValveDStart   := valveDStart;
prevMixMotorStart := mixMotorStart;

(* Mode Selection *)
IF opeMode THEN
    (* ========== AUTOMATIC MODE ========== *)
    
    (* Initialize outputs to FALSE *)
    valveARun   := FALSE;
    valveBRun   := FALSE;
    valveCRun   := FALSE;
    valveDRun   := FALSE;
    mixMotorRun := FALSE;
    
    (* Start automatic process on rising edge of autoStart *)
    IF autoStart AND NOT prevAutoStart THEN
        IF autoState = IDLE THEN
            autoState := FILL_A;
            valveARun := TRUE;
        END_IF
    END_IF
    
    (* State Machine - Sequential Control *)
    IF autoState = FILL_A THEN
        valveARun := TRUE;
        (* When level reaches 50cm, close valve A and open valve B *)
        IF levelSensor >= 50 THEN
            autoState  := FILL_B;
            valveARun  := FALSE;
            valveBRun  := TRUE;
        END_IF
        
    ELSIF autoState = FILL_B THEN
        valveBRun := TRUE;
        (* When level reaches 80cm, close valve B *)
        IF levelSensor >= 80 THEN
            valveBRun := FALSE;
            
            (* Check processMode for next step *)
            IF NOT processMode THEN
                (* processMode=false: Direct to mixing *)
                autoState  := MIXING;
                mixMotorRun := TRUE;
            ELSE
                (* processMode=true: Fill material C first *)
                autoState := FILL_C;
            END_IF
        END_IF
        
    ELSIF autoState = FILL_C THEN
        valveCRun := TRUE;
        (* When level reaches 100cm, close valve C and start mixing *)
        IF levelSensor >= 100 THEN
            autoState  := MIXING;
            valveCRun  := FALSE;
            mixMotorRun := TRUE;
        END_IF
        
    ELSIF autoState = MIXING THEN
        mixMotorRun := TRUE;
        (* When mixing complete signal received, stop motor *)
        IF mixMotorComplete THEN
            autoState  := DISCHARGE;
            mixMotorRun := FALSE;
        END_IF
        
    ELSIF autoState = DISCHARGE THEN
        valveDRun := TRUE;
        (* After discharge, return to idle - process complete *)
        autoState := IDLE;
        
    END_IF
    
ELSE
    (* ========== MANUAL MODE ========== *)
    (* In manual mode, automatic state machine is reset *)
    autoState := IDLE;
    
END_IF