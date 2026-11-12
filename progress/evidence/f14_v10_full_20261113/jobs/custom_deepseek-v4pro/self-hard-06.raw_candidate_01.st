(* ENGINEERING_CONTRACT
   - tripLatched: set same scan by run & (!valid | P>=4500) PUB002/PUB006; holds until legal reset edge.
     Legal reset: rising reset & !run & valid & P<=4200 PUB003. Illegal reset does not clear PUB012/PUB013.
   - currentCauseMask: recomputed each scan; allowed 0/1/2/4/6/8 PUB008,N10-S15.
     bit0=invalid; bit1 requires 3 consecutive full stuck scans PUB010,N10-S11; bit2 inclusive flow; bit3=8 when no located bit under overpressure.
   - latchedCauseMask: OR-accumulates currentCauseMask while tripLatched true; cleared when not tripped or legal reset PUB011,N10-S18.
   - fuelPermit = run & !trip; diagnosticActive = current<>0 PUB007.
   - stuck counter zeroes on any non-full scan: !run, !valid, P<4500, or valve condition false PUB010.
   - units: kPa, t/h, %; boundaries inclusive. Same-scan trip and cause are emitted together.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
VAR_INPUT
    runRequest: BOOL;
    pressure: REAL;
    pressureValid: BOOL;
    fuelFlow: REAL;
    steamFlow: REAL;
    outletCmd: INT;
    outletFeedback: INT;
    resetBtn: BOOL;
END_VAR
VAR_OUTPUT
    tripLatched: BOOL;
    fuelPermit: BOOL;
    currentCauseMask: WORD;
    latchedCauseMask: WORD;
    diagnosticActive: BOOL;
END_VAR
VAR
    prev_reset_btn: BOOL := FALSE;
    prev_trip_state: BOOL := FALSE;
    stuck_count: INT := 0;
    latched_state: WORD := WORD#16#0000;
    tmp_rising_reset: BOOL;
    tmp_legal_reset: BOOL;
    tmp_stuck_condition: BOOL;
    tmp_bit1: BOOL;
    tmp_bit2: BOOL;
    tmp_trip_condition: BOOL;
    tmp_trip_state: BOOL;
END_VAR

(* Update stuck-valve consecutive-scan counter *)
tmp_stuck_condition := runRequest AND pressureValid AND (pressure >= 4500.0)
                       AND (outletCmd >= 50) AND (outletFeedback <= 10);

IF tmp_stuck_condition THEN
    IF stuck_count < 3 THEN
        stuck_count := stuck_count + 1;
    END_IF;
ELSE
    stuck_count := 0;
END_IF;

(* Compute current cause mask *)
currentCauseMask := WORD#16#0000;

IF NOT runRequest THEN
    currentCauseMask := WORD#16#0000;
ELSIF NOT pressureValid THEN
    currentCauseMask := WORD#16#0001; (* bit0: transmitter invalid *)
ELSE
    IF pressure >= 4500.0 THEN
        tmp_bit1 := stuck_count >= 3;
        tmp_bit2 := (fuelFlow >= 4.0) AND (steamFlow <= 10.0);

        IF tmp_bit1 THEN
            currentCauseMask := currentCauseMask OR WORD#16#0002; (* bit1: valve stuck *)
        END_IF;
        IF tmp_bit2 THEN
            currentCauseMask := currentCauseMask OR WORD#16#0004; (* bit2: combustion excess *)
        END_IF;
        IF currentCauseMask = WORD#16#0000 THEN
            currentCauseMask := WORD#16#0008; (* bit3: not located *)
        END_IF;
    ELSE
        currentCauseMask := WORD#16#0000;
    END_IF;
END_IF;

(* Trip latch state *)
tmp_rising_reset := resetBtn AND NOT prev_reset_btn;
tmp_legal_reset := tmp_rising_reset AND (NOT runRequest) AND pressureValid AND (pressure <= 4200.0);

tmp_trip_condition := runRequest AND ((NOT pressureValid) OR (pressureValid AND (pressure >= 4500.0)));
tmp_trip_state := tmp_trip_condition OR (prev_trip_state AND NOT tmp_legal_reset);
tripLatched := tmp_trip_state;

(* Latched footprint accumulation / clear *)
IF tmp_trip_state THEN
    latched_state := (latched_state OR currentCauseMask) AND WORD#16#000F;
ELSE
    latched_state := WORD#16#0000;
END_IF;
latchedCauseMask := latched_state;

(* Derived outputs *)
fuelPermit := runRequest AND NOT tripLatched;
diagnosticActive := currentCauseMask <> WORD#16#0000;

(* Remember previous-scan values for next call *)
prev_reset_btn := resetBtn;
prev_trip_state := tmp_trip_state;

END_FUNCTION_BLOCK