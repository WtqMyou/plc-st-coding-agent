(* ENGINEERING_CONTRACT *)
(*
  | Output/State Group       | Activation                                  | Retention                    | Reset/Deactivation            | Same-Scan Priority | Units/Boundaries |
  |--------------------------|---------------------------------------------|------------------------------|-------------------------------|--------------------|------------------|
  | MotorForward (Auto)      | State=B OR State=D_transit                  | Hold via tmp_MotorRunning    | State=C/DONE OR Mode=0         | Same-scan          | PUB006           |
  | MotorReverse (Manual)    | ReverseButton AND Mode=0 AND !ForwardButton | Hold until condition false   | !ReverseButton OR Mode=1       | Same-scan          | PUB004,PUB002    |
  | CompletionLight          | State=DONE AND SensorC AND Mode             | Hold while SensorC           | SensorC=0 OR Mode=0            | Same-scan          | PUB008           |
  | State transitions        | Per clause PUB003                           | Until next trigger           | Mode=0 → IDLE                  | Same-scan          | PUB003           |
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK ProductionLineControl
VAR_INPUT
    Mode : BOOL;
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorA : BOOL;
    SensorB : BOOL;
    SensorC : BOOL;
    ButtonA : BOOL;
    ButtonB : BOOL;
    ButtonC : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward : BOOL;
    MotorReverse : BOOL;
    CompletionLight : BOOL;
END_VAR
VAR
    State : INT;
    IDLE : INT := 0;
    StateA : INT := 1;
    StateB : INT := 2;
    StateC : INT := 3;
    StateD_transit : INT := 4;
    DONE : INT := 5;
    tmp_MotorRunning : BOOL;
END_VAR
    tmp_MotorRunning := (State = StateB) OR (State = StateD_transit);
    MotorForward := tmp_MotorRunning AND Mode;
    MotorReverse := ReverseButton AND (NOT Mode) AND (NOT ForwardButton);
    CompletionLight := (State = DONE) AND SensorC AND Mode;
    IF Mode = FALSE THEN
        State := IDLE;
    ELSIF Mode = TRUE THEN
        IF State = IDLE AND SensorA THEN
            State := StateA;
        ELSIF State = StateA AND ButtonA THEN
            State := StateB;
            tmp_MotorRunning := TRUE;
        ELSIF State = StateB AND SensorB THEN
            State := StateC;
        ELSIF State = StateC AND ButtonC THEN
            State := StateD_transit;
            tmp_MotorRunning := TRUE;
        ELSIF State = StateD_transit AND SensorC THEN
            State := DONE;
        ELSIF State = DONE AND NOT SensorC THEN
            State := IDLE;
        END_IF;
    END_IF;
END_FUNCTION_BLOCK