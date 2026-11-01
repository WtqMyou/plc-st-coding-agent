FUNCTION_BLOCK Bad
VAR_INPUT
    Start : BOOL;
END_VAR
VAR_OUTPUT
    Count : INT;
END_VAR
VAR
    Edge : BOOL;
END_VAR

IF Start THEN
    Count := Count + 1;
    Start := FALSE;
END_IF
IF Count > 100 THEN
    Edge := TRUE
END_IF;
IF Edge THEN
    Count := lalala + 1;
END_IF;
END_FUNCTION_BLOCK
