(* ENGINEERING_CONTRACT
====================
PUB001: 76-318

State Retention:
- tmp_previous_value: RETAINED across scans (stores last cycle's DWORD value)
- All outputs: COMBINATIONAL (derived fresh each scan from current inputs + retained state)

Edge Detection Logic:
- Rising edge:  (current = 1) AND (previous = 0)  → risingBits = value & NOT previous
- Falling edge: (current = 0) AND (previous = 1)  → fallingBits = NOT value & previous
- Changed:      value <> previous

Counting:
- Count 1-bits in risingBits  → noOfRisingBits  (0-32)
- Count 1-bits in fallingBits → noOfFallingBits (0-32)

Priority:
- All outputs derived combinatorially in same scan
- No edge-only triggers or state machines

Units:
- risingBits/fallingBits: dimensionless bit patterns (DWORD)
- noOfRisingBits/noOfFallingBits: unsigned count (USINT, 0-32)
*)
FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
    value : DWORD;
END_VAR
VAR
    tmp_previous_value : DWORD := 0;
    i                  : INT;
    tmp_bit            : DWORD;
END_VAR
VAR_OUTPUT
    hasChanged      : BOOL;
    hasRisingEdges  : BOOL;
    risingBits      : DWORD;
    noOfRisingBits  : USINT;
    hasFallingEdges : BOOL;
    fallingBits     : DWORD;
    noOfFallingBits : USINT;
END_VAR

risingBits  := value AND NOT tmp_previous_value;
fallingBits := (NOT value) AND tmp_previous_value;

hasChanged      := (value <> tmp_previous_value);
hasRisingEdges  := (risingBits <> 0);
hasFallingEdges := (fallingBits <> 0);

noOfRisingBits := 0;
FOR i := 0 TO 31 DO
    tmp_bit := SHR(risingBits, i);
    IF TO_BOOL(tmp_bit AND 1) THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
END_FOR;

noOfFallingBits := 0;
FOR i := 0 TO 31 DO
    tmp_bit := SHR(fallingBits, i);
    IF TO_BOOL(tmp_bit AND 1) THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

tmp_previous_value := value;
END_FUNCTION_BLOCK