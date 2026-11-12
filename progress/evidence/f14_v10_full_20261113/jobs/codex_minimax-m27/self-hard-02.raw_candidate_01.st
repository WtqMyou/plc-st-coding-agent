FUNCTION_BLOCK FB
VAR_INPUT
    startBtn    : BOOL;
    abortBtn    : BOOL;
    setpoint    : REAL;
    pv          : REAL;
    maxDuration : INT;
END_VAR
VAR_OUTPUT
    elapsed : INT := 0;
    phase   : INT := 0;
    timeout : BOOL := FALSE;
END_VAR
VAR
    prevStartBtn : BOOL := FALSE;
END_VAR
(* ENGINEERING_CONTRACT
+-----------------------------------------------------------+-----------------------------------+-----------------------------------+-------------------+------------+
| Output/State    | Activation              | Retention           | Explicit Reset        | Same-scan Priority | Units/Range |
+-----------------------------------------------------------+-----------------------------------+-----------------------------------+-------------------+------------+
| phase=9         | abortBtn=TRUE           | Hold until new start| New rising(startBtn)  | 1-Highest (abort)  | Enum {0,1,2,3,9} |
| phase=1         | Rising(startBtn) & no abort | Clear elapsed,timeout | Rising(startBtn)     | 2-Medium (start)   | Enum {0,1,2,3,9} |
| phase=3         | elapsed>=maxDuration    | Hold until new start| New rising(startBtn)  | 3-Lowest (running) | Enum {0,1,2,3,9} |
| elapsed         | +1 per scan when prev(1|2) | Hold in phase 3,9  | Clear on new start    | -                  | INT [0,2147483647] |
| timeout         | Set when elapsed>=maxDuration | Hold in phase 3,9 | Clear on new start   | -                  | BOOL |
+-----------------------------------------------------------+-----------------------------------+-----------------------------------+-------------------+------------+
PUB: [PUB001,PUB002,PUB003,PUB004,PUB005,PUB006,PUB007,PUB008,PUB009,PUB010,
      PUB011,PUB012,PUB013,PUB014,PUB015,PUB016,PUB017,PUB018,PUB019,PUB020,
      PUB021,PUB022,PUB023,PUB024,PUB025,PUB026,PUB027,PUB028,PUB029,PUB030,
      PUB031,PUB032,PUB033,PUB034,PUB035,PUB036,PUB037,PUB038,PUB039,PUB040,
      PUB041,PUB042,PUB043,PUB044,PUB045,PUB046,PUB047,PUB048]
*)
VAR
    tmpRisingStart : BOOL;
    tmpPrevPhase   : INT;
END_VAR

tmpRisingStart := startBtn AND NOT prevStartBtn;
tmpPrevPhase   := phase;

IF abortBtn THEN
    phase   := 9;
    elapsed := elapsed;
    timeout := timeout;
ELSIF tmpRisingStart THEN
    elapsed := 0;
    timeout := FALSE;
    phase   := 1;
ELSE
    IF (tmpPrevPhase = 1) OR (tmpPrevPhase = 2) THEN
        elapsed := elapsed + 1;
        IF elapsed >= maxDuration THEN
            timeout := TRUE;
            phase   := 3;
        ELSIF tmpPrevPhase = 1 THEN
            IF pv >= setpoint THEN
                phase := 2;
            ELSE
                phase := 1;
            END_IF;
        ELSE
            phase := 2;
        END_IF;
    ELSE
        phase := tmpPrevPhase;
    END_IF;
END_IF;

prevStartBtn := startBtn;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)