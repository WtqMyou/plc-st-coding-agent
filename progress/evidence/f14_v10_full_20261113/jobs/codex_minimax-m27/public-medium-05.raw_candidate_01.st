(* ENGINEERING_CONTRACT *)
(*
  | Output/State Group       | Activation                                  | Retention                    | Reset/Deactivation            | Same-Scan Priority | Units/Boundaries |
  |--------------------------|---------------------------------------------|------------------------------|-------------------------------|--------------------|------------------|
  | MotorForward (Auto)      | State<>IDLE AND Mode=1                      | Hold until State=IDLE        | State=IDLE OR Mode=0          | Same-scan          | PUB001,PUB007    |
  | MotorReverse (Manual)    | ForwardButton=1 AND Mode=0 AND ReverseButton=0 | Hold until condition false | ForwardButton=0 OR Mode=1   | Same-scan          | PUB006,PUB002    |
  | CompletionLight          | State=DONE AND SensorC=1 AND Mode=1         | Hold while SensorC=1         | SensorC=0 OR Mode=0           | Same-scan          | PUB004,PUB008    |
  | State: IDLE→A            | SensorA=1 AND Mode=1 AND State=IDLE         | Until next transition        | SensorC=0 (product removed)   | Same-scan          | PUB003           |
  | State: A→B               | ButtonA=1 AND State=A                       | Until next transition        | SensorC=0                      | Same-scan          | PUB003           |
  | State: B→C               | SensorB=1 AND State=B                       | Until next transition        | SensorC=0                      | Same-scan          | PUB003           |
  | State: C→DONE            | ButtonC=1 AND State=C                       | Until SensorC=0              | SensorC=0                      | Same-scan          | PUB003           |
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
    StateD : INT := 4;
END_VAR
    IF Mode = FALSE THEN
        State := IDLE;
    ELSIF Mode = TRUE THEN
        IF State = IDLE AND SensorA THEN
            State := StateA;
        ELSIF State = StateA AND ButtonA THEN
            State := StateB;
        ELSIF State = StateB AND SensorB THEN
            State := StateC;
        ELSIF State = StateC AND ButtonC THEN
            State := StateD;
        END_IF;
    END_IF;
    MotorForward := ((State <> IDLE) AND Mode) OR (ForwardButton AND (NOT Mode) AND (NOT ReverseButton));
    MotorReverse := ReverseButton AND (NOT Mode) AND (NOT ForwardButton);
    CompletionLight := (State = StateD) AND SensorC AND Mode;
END_FUNCTION_BLOCK