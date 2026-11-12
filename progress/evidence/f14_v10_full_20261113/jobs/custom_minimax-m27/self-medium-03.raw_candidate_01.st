(* ENGINEERING_CONTRACT *)
(*
  Gate FSM: 4 states (IDLE/OPENING/CLOSING/FAULT), obstacle safety interlock.
  
  PUB001: IDLE at power-on, initial button values FALSE.
  PUB003: Rising edge of openBtn (closeBtn=FALSE, openLimit=FALSE) starts opening.
          Rising edge of closeBtn (openBtn=FALSE, closeLimit=FALSE) starts closing.
          Both buttons simultaneous → no start. Commands issued same scan.
  PUB004: Buttons ignored during OPENING/CLOSING.
  PUB005: At own-direction limit → stop that direction, return IDLE.
          Opposite limit does not affect current motion.
  PUB006: MotorUp and motorDown always mutually exclusive.
  PUB007: Obstacle at any time → stop both motors, enter FAULT, errorFlag:=TRUE immediately.
          Obstacle priority > limit/motion/reset.
  PUB008: FAULT latches errorFlag, stops motors.
  PUB009: Clear fault only when: no obstacle AND both buttons new rising edge from
          not-both-pressed state to both-pressed state. Holding both with obstacle
          present does NOT clear on obstacle-clear scan. Reset→IDLE, both motors stop
          that scan, then normal PUB003 rules apply.
*)
TYPE GateState :
(
    IDLE    := 0,
    OPENING := 1,
    CLOSING := 2,
    FAULT   := 3
);
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    openBtn    : BOOL;
    closeBtn   : BOOL;
    openLimit  : BOOL;
    closeLimit : BOOL;
    obstacle   : BOOL;
END_VAR

VAR_OUTPUT
    motorUp    : BOOL;
    motorDown  : BOOL;
    errorFlag  : BOOL;
END_VAR

VAR
    state        : GateState := IDLE;
    prevOpenBtn  : BOOL := FALSE;
    prevCloseBtn : BOOL := FALSE;
    prevObstacle : BOOL := FALSE;
    prevMotorUp  : BOOL := FALSE;
    prevMotorDown: BOOL := FALSE;
    prevErrorFlag: BOOL := FALSE;
END_VAR

VAR
    risingOpen  : BOOL;
    risingClose : BOOL;
    risingBoth  : BOOL;
END_VAR
(* ENGINEERING_CONTRACT *)
(*
  Gate FSM: 4 states (IDLE/OPENING/CLOSING/FAULT), obstacle safety interlock.
  
  PUB001: IDLE at power-on, initial button values FALSE.
  PUB003: Rising edge of openBtn (closeBtn=FALSE, openLimit=FALSE) starts opening.
          Rising edge of closeBtn (openBtn=FALSE, closeLimit=FALSE) starts closing.
          Both buttons simultaneous → no start. Commands issued same scan.
  PUB004: Buttons ignored during OPENING/CLOSING.
  PUB005: At own-direction limit → stop that direction, return IDLE.
          Opposite limit does not affect current motion.
  PUB006: MotorUp and motorDown always mutually exclusive.
  PUB007: Obstacle at any time → stop both motors, enter FAULT, errorFlag:=TRUE immediately.
          Obstacle priority > limit/motion/reset.
  PUB008: FAULT latches errorFlag, stops motors.
  PUB009: Clear fault only when: no obstacle AND both buttons new rising edge from
          not-both-pressed state to both-pressed state. Holding both with obstacle
          present does NOT clear on obstacle-clear scan. Reset→IDLE, both motors stop
          that scan, then normal PUB003 rules apply.
*)

risingOpen  := openBtn  AND NOT prevOpenBtn;
risingClose := closeBtn AND NOT prevCloseBtn;
risingBoth  := risingOpen AND risingClose;

IF obstacle THEN
    errorFlag  := TRUE;
    motorUp    := FALSE;
    motorDown  := FALSE;
    state      := FAULT;
    GOTO update_state;
END_IF

IF state = FAULT THEN
    motorUp   := FALSE;
    motorDown := FALSE;
    IF risingBoth THEN
        errorFlag := FALSE;
        state     := IDLE;
    END_IF
    GOTO update_state;
END_IF

IF state = IDLE THEN
    IF risingOpen AND NOT closeBtn AND NOT openLimit THEN
        state := OPENING;
    ELSIF risingClose AND NOT openBtn AND NOT closeLimit THEN
        state := CLOSING;
    END_IF;
END_IF;

IF state = OPENING THEN
    motorUp   := TRUE;
    motorDown := FALSE;
    IF openLimit THEN
        motorUp := FALSE;
        state   := IDLE;
    END_IF;
END_IF;

IF state = CLOSING THEN
    motorUp   := FALSE;
    motorDown := TRUE;
    IF closeLimit THEN
        motorDown := FALSE;
        state     := IDLE;
    END_IF;
END_IF;

update_state:
prevOpenBtn   := openBtn;
prevCloseBtn  := closeBtn;
prevObstacle  := obstacle;
prevMotorUp   := motorUp;
prevMotorDown := motorDown;
prevErrorFlag := errorFlag;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)