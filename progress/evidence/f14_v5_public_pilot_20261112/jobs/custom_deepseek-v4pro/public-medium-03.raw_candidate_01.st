(*
ENGINEERING_CONTRACT
Activation: add sample each scan if cyclicExecution=TRUE; otherwise only on rising edge of trigger (PUB002, PUB003).
Reset priority: reset=TRUE clears history, average:=0, windowSizeReached:=FALSE before validation/add (PUB004).
Window validation: windowSize outside [1..100] sets error:=TRUE, status:=16#8200, windowSizeReached:=FALSE, and freezes calculation; average holds last valid output (PUB004/PUB007).
Same-scan: reset evaluated first, then window validation, then add; cyclicExecution suppresses trigger add but trigger edge is tracked for later cycles.
Retention: average/windowSizeReached hold between enabled samples; windowSizeReached becomes TRUE when stored count reaches windowSize.
Units/bounds: windowSize integer [1..100]; average LREAL; status WORD codes 16#0000 success, 16#8200 invalid window.
Unspecified: valid windowSize changes trim oldest stored samples to the new window without a separate reset.
*)
FUNCTION_BLOCK FB
VAR
    history : ARRAY[0..99] OF LREAL;
    count : INT := 0;
    oldestIdx : INT := 0;
    lastTrigger : BOOL := FALSE;
    i : INT;
    idx : INT;
    sum : LREAL;
    needAdd : BOOL;
    wsValid : BOOL;
END_VAR

IF reset THEN
    count := 0;
    oldestIdx := 0;
    average := 0.0;
    windowSizeReached := FALSE;
END_IF;

wsValid := (windowSize >= 1) AND (windowSize <= 100);

IF NOT wsValid THEN
    error := TRUE;
    status := 16#8200;
    windowSizeReached := FALSE;
ELSE
    error := FALSE;
    status := 16#0000;
    IF NOT reset THEN
        IF cyclicExecution THEN
            needAdd := TRUE;
        ELSE
            needAdd := trigger AND NOT lastTrigger;
        END_IF;
        IF needAdd THEN
            idx := (oldestIdx + count) MOD 100;
            history[idx] := value;
            IF count < 100 THEN
                count := count + 1;
            ELSE
                oldestIdx := (oldestIdx + 1) MOD 100;
            END_IF;
            WHILE count > windowSize DO
                oldestIdx := (oldestIdx + 1) MOD 100;
                count := count - 1;
            END_WHILE;
            IF count > 0 THEN
                sum := 0.0;
                FOR i := 0 TO count - 1 DO
                    idx := (oldestIdx + i) MOD 100;
                    sum := sum + history[idx];
                END_FOR;
                average := sum / INT_TO_LREAL(count);
            ELSE
                average := 0.0;
            END_IF;
            windowSizeReached := (count >= windowSize);
        END_IF;
    END_IF;
END_IF;

lastTrigger := trigger;
END_FUNCTION_BLOCK