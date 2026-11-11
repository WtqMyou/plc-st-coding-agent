FUNCTION_BLOCK FB
VAR_INPUT
    runRequest        : BOOL;
    pressure          : REAL;
    pressureValid     : BOOL;
    fuelFlow          : REAL;
    steamFlow         : REAL;
    outletCmd         : INT;
    outletFeedback    : INT;
    resetBtn          : BOOL;
END_VAR
VAR_OUTPUT
    tripLatched       : BOOL;
    fuelPermit        : BOOL;
    currentCauseMask  : WORD;
    latchedCauseMask  : WORD;
    diagnosticActive  : BOOL;
END_VAR
VAR
    stuckCount   : INT  := 0;      (* consecutive cycles for valve‑stuck detection *)
    prevResetBtn : BOOL := FALSE;   (* previous state of reset button *)
END_VAR

(* ------------------------------------------------------------------
   1. Valve‑stuck consecutive‑cycle detection
   ------------------------------------------------------------------ *)
IF runRequest AND pressureValid AND (pressure >= 4500.0)
   AND (outletCmd >= 50) AND (outletFeedback <= 10) THEN
    IF stuckCount < 3 THEN
        stuckCount := stuckCount + 1;
    END_IF;
ELSE
    stuckCount := 0;
END_IF;

(* ------------------------------------------------------------------
   2. Current cause mask (bits 0…3)
   ------------------------------------------------------------------ *)
IF NOT runRequest THEN
    currentCauseMask := 0;                     (* S5 *)

ELSIF NOT pressureValid THEN
    currentCauseMask := 1;                     (* bit0 – transmitter failure, S12 *)

ELSE
    (* pressureValid = TRUE *)
    IF pressure >= 4500.0 THEN
        (* Over‑pressure – evaluate bit1 (valve stuck) and bit2 (combustion excess) *)
        currentCauseMask := 0;

        IF stuckCount >= 3 THEN
            currentCauseMask := 2;             (* bit1 *)
        END_IF;

        IF (fuelFlow >= 4.0) AND (steamFlow <= 10.0) THEN
            currentCauseMask := currentCauseMask OR 4;  (* bit2 *)
        END_IF;

        (* If neither cause is identified, set bit3 (unlocated) *)
        IF currentCauseMask = 0 THEN
            currentCauseMask := 8;             (* bit3 *)
        END_IF;
    ELSE
        currentCauseMask := 0;                 (* S6 *)
    END_IF;
END_IF;

(* ------------------------------------------------------------------
   3. Trip condition
   ------------------------------------------------------------------ *)
(*  runRequest  AND ( pressureValid = FALSE  OR  pressure >= 4500.0 ) *)
tripLatched := tripLatched OR (runRequest AND (NOT pressureValid OR (pressure >= 4500.0)));

(* ------------------------------------------------------------------
   4. Reset on rising edge of reset button when conditions are met
   ------------------------------------------------------------------ *)
IF resetBtn AND NOT prevResetBtn AND NOT runRequest AND pressureValid AND (pressure <= 4200.0) THEN
    tripLatched := FALSE;
END_IF;
prevResetBtn := resetBtn;

(* ------------------------------------------------------------------
   5. Fuel permit
   ------------------------------------------------------------------ *)
fuelPermit := runRequest AND NOT tripLatched;   (* S3, N10‑S16 *)

(* ------------------------------------------------------------------
   6. Diagnostic active flag
   ------------------------------------------------------------------ *)
diagnosticActive := (currentCauseMask <> 0);    (* S7 *)

(* ------------------------------------------------------------------
   7. Accumulate cause mask while trip is latched
   ------------------------------------------------------------------ *)
IF tripLatched THEN
    latchedCauseMask := latchedCauseMask OR currentCauseMask;
ELSE
    latchedCauseMask := 0;                      (* N10‑S18 *)
END_IF;

END_FUNCTION_BLOCK