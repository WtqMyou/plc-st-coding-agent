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
    state        : INT;  // 0=IDLE, 1=OPENING, 2=CLOSING, 3=FAULT
    prev_openBtn  : BOOL := FALSE;
    prev_closeBtn : BOOL := FALSE;
END_VAR
VAR_TEMP
    openRising  : BOOL;
    closeRising : BOOL;
    dualRising  : BOOL;
END_VAR
(*
ENGINEERING_CONTRACT
================================================================================
State retention: IDLE/OPENING/CLOSING/FAULT held in state VAR.
Output motorUp: activation on OPENING entry (PUB010), hold until openLimit or
                obstacle or FAULT entry (PUB003/PUB004/PUB012). No reset
                command de-asserts motorUp; only limit/obstacle/FAULT.
Output motorDown: symmetric to motorUp for CLOSING (PUB011).
Output errorFlag: latched hold_until_reset per CONTRACT_RULES, cleared only
                  by dualRising edge with !obstacle (PUB026/PUB036).
Reset priority: obstacle immediate (PUB012), then dualRising reset
                (PUB036), then limit switches (PUB003/PUB004), then idle
                continuation (PUB003). All same-scan; no added delays.
Physical direction rule: motorUp AND motorDown never both TRUE (PUB007).
Units: BOOL scan-synchronous, no timers. Boundary conditions per formal props.
================================================================================
*)
openRising  := openBtn AND NOT prev_openBtn;
closeRising := closeBtn AND NOT prev_closeBtn;
dualRising  := openRising AND closeRising;

motorUp   := FALSE;
motorDown := FALSE;

IF obstacle THEN
    errorFlag := TRUE;
    state     := 3;
    RETURN;
END_IF;

CASE state OF
    0: // IDLE
        IF openRising AND NOT closeBtn AND NOT openLimit THEN
            state := 1;
            motorUp := TRUE;
        ELSIF closeRising AND NOT openBtn AND NOT closeLimit THEN
            state := 2;
            motorDown := TRUE;
        END_IF;

    1: // OPENING
        IF openLimit THEN
            state := 0;
        END_IF;

    2: // CLOSING
        IF closeLimit THEN
            state := 0;
        END_IF;

    3: // FAULT
        IF NOT obstacle AND dualRising THEN
            errorFlag := FALSE;
            state     := 0;
        ELSE
            errorFlag := TRUE;
        END_IF;
END_CASE;

prev_openBtn  := openBtn;
prev_closeBtn := closeBtn;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [{"kind": "hold_until_reset", "output": "errorFlag", "set_input": "obstacle", "reset_input": "rising(openBtn AND closeBtn)"}] *)