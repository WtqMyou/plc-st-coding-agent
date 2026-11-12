FUNCTION_BLOCK FB
VAR_OUTPUT
    leadPump : INT := 0;
    lagPump : INT := 0;
    runningCount : INT := 0;
END_VAR
VAR_INPUT
    demand : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated : BOOL;
END_VAR
VAR
    prevLeadPump : INT := 0;
    prevLagPump : INT := 0;
    prevRunningCount : INT := 0;
    tmpLead : INT;
    tmpLag : INT;
    tmpCount : INT;
    minHours : LINT;
    minPump : INT;
    i : INT;
END_VAR
VAR_TEMP
    local_i : INT;
END_VAR
(*
ENGINEERING_CONTRACT:
| State Group         | Activation           | Retention/Hold           | Explicit Reset         | Same-Scan Priority | Units/Boundaries         |
|---------------------|----------------------|--------------------------|------------------------|--------------------|--------------------------|
| runningCount [S1]   | demand>0             | hold value               | demand<=0→0            | same-scan assign   | 0..5 (clipped from demand)|
| leadPump [S2,S3]    | demand>0, prevLead=0 | hold during positive dem | demand<=0→0            | initial selection first | 0 or 1..5                |
| leadPump rotation   | rotated=TRUE AND >50h diff | hold until next valid trigger | demand<=0→0 | rotation evaluated after initial | 1..5 only               |
| lagPump [S2,S8,S9]  | demand>=2 AND (initial/change/rise) | hold when unchanged | demand<=1→0           | evaluated after lead | 0 or 1..5, ≠leadPump     |
PUB clauses: PUB001(s0), PUB002(demand), PUB003(clipped), PUB004(ascending), PUB005(different), PUB006(0→pos), PUB007(hysteresis50h), PUB008(level-rotated), PUB009(no req→no change), PUB010(demand=0→clr), PUB011(lag selection moments), PUB012(no reselection), PUB013(index 1..5)
*)
(* CONTRACT_RULES [] *)

tmpLead := prevLeadPump;
tmpLag := prevLagPump;
tmpCount := prevRunningCount;

tmpCount := demand;
IF demand < 0 THEN
    tmpCount := 0;
END_IF
IF demand > 5 THEN
    tmpCount := 5;
END_IF

IF demand <= 0 THEN
    tmpLead := 0;
    tmpLag := 0;
ELSIF tmpLead = 0 THEN
    minHours := runHours[1];
    minPump := 1;
    FOR local_i := 2 TO 5 DO
        IF runHours[local_i] < minHours OR (runHours[local_i] = minHours AND local_i < minPump) THEN
            minHours := runHours[local_i];
            minPump := local_i;
        END_IF
    END_FOR
    tmpLead := minPump;
    IF tmpCount >= 2 THEN
        minHours := LINT#16#7FFFFFFFFFFFFFFF;
        minPump := 0;
        FOR local_i := 1 TO 5 DO
            IF local_i <> tmpLead THEN
                IF runHours[local_i] < minHours OR (runHours[local_i] = minHours AND local_i < minPump) THEN
                    minHours := runHours[local_i];
                    minPump := local_i;
                END_IF
            END_IF
        END_FOR
        tmpLag := minPump;
    ELSE
        tmpLag := 0;
    END_IF
ELSE
    IF rotated THEN
        minHours := runHours[1];
        minPump := 1;
        FOR local_i := 2 TO 5 DO
            IF runHours[local_i] < minHours OR (runHours[local_i] = minHours AND local_i < minPump) THEN
                minHours := runHours[local_i];
                minPump := local_i;
            END_IF
        END_FOR
        IF runHours[tmpLead] > minHours + LINT#50 THEN
            tmpLead := minPump;
        END_IF
    END_IF
    IF tmpCount >= 2 THEN
        IF tmpLead <> prevLeadPump OR tmpCount > prevRunningCount THEN
            minHours := LINT#16#7FFFFFFFFFFFFFFF;
            minPump := 0;
            FOR local_i := 1 TO 5 DO
                IF local_i <> tmpLead THEN
                    IF runHours[local_i] < minHours OR (runHours[local_i] = minHours AND local_i < minPump) THEN
                        minHours := runHours[local_i];
                        minPump := local_i;
                    END_IF
                END_IF
            END_FOR
            tmpLag := minPump;
        END_IF
    ELSE
        tmpLag := 0;
    END_IF
END_IF

leadPump := tmpLead;
lagPump := tmpLag;
runningCount := tmpCount;
prevLeadPump := tmpLead;
prevLagPump := tmpLag;
prevRunningCount := tmpCount;
END_FUNCTION_BLOCK