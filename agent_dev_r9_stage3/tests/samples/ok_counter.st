FUNCTION_BLOCK Counter
VAR_INPUT
    Start : BOOL;
    Reset : BOOL;
END_VAR
VAR_OUTPUT
    Count : INT;
    Running : BOOL;
END_VAR
VAR
    prev : BOOL := FALSE;
END_VAR

IF Reset THEN
    Count := 0;
    Running := FALSE;
ELSIF Start AND NOT prev THEN
    Count := Count + 1;
    Running := TRUE;
END_IF;
prev := Start;
END_FUNCTION_BLOCK
