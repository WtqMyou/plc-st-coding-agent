FUNCTION_BLOCK FB
VAR_INPUT
    demand : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated : BOOL;
END_VAR
VAR_OUTPUT
    leadPump : INT;
    lagPump : INT;
    runningCount : INT;
END_VAR
VAR
    prevLead : INT := 0;
    prevLag : INT := 0;
    prevRunCount : INT := 0;
    clipped : INT;
    newLead : INT;
    newLag : INT;
    newRunningCount : INT;
    minP : INT;
    minH : LINT;
    i : INT;
END_VAR

(* 裁剪需求到 0..5 *)
IF demand < 0 THEN
    clipped := 0;
ELSIF demand > 5 THEN
    clipped := 5;
ELSE
    clipped := demand;
END_IF;

newRunningCount := clipped;

IF clipped <= 0 THEN
    newLead := 0;
    newLag := 0;
ELSE
    (* 主泵选择 *)
    IF prevLead = 0 THEN
        (* 初选：全场（工时，泵号）最小 *)
        minP := 1;
        minH := runHours[1];
        FOR i := 2 TO 5 DO
            IF (runHours[i] < minH) OR ((runHours[i] = minH) AND (i < minP)) THEN
                minP := i;
                minH := runHours[i];
            END_IF;
        END_FOR;
        newLead := minP;
    ELSE
        (* 正需求期间按迟滞逻辑 *)
        IF rotated THEN
            minP := 1;
            minH := runHours[1];
            FOR i := 2 TO 5 DO
                IF (runHours[i] < minH) OR ((runHours[i] = minH) AND (i < minP)) THEN
                    minP := i;
                    minH := runHours[i];
                END_IF;
            END_FOR;
            IF (runHours[prevLead] - runHours[minP] > 50) THEN
                newLead := minP;
            ELSE
                newLead := prevLead;
            END_IF;
        ELSE
            newLead := prevLead;
        END_IF;
    END_IF;

    (* 备泵选择 *)
    IF clipped < 2 THEN
        newLag := 0;
    ELSE
        (* 初选/换主或需求台数上升时重选 *)
        IF (newLead <> prevLead) OR (newRunningCount > prevRunCount) THEN
            minP := 0;
            minH := 0;
            FOR i := 1 TO 5 DO
                IF i <> newLead THEN
                    IF minP = 0 THEN
                        minP := i;
                        minH := runHours[i];
                    ELSE
                        IF (runHours[i] < minH) OR ((runHours[i] = minH) AND (i < minP)) THEN
                            minP := i;
                            minH := runHours[i];
                        END_IF;
                    END_IF;
                END_IF;
            END_FOR;
            newLag := minP;
        ELSE
            newLag := prevLag;
        END_IF;
    END_IF;
END_IF;

leadPump := newLead;
lagPump := newLag;
runningCount := newRunningCount;

prevLead := newLead;
prevLag := newLag;
prevRunCount := newRunningCount;

END_FUNCTION_BLOCK