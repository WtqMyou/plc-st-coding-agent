TYPE ST_Recipe : STRUCT
    recipeID    : INT;
    totalRatio  : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    recipe     : ARRAY[1..8] OF ST_Recipe;
    selSlot    : INT;
    loadCmd    : BOOL;
    running    : BOOL;
END_VAR
VAR_OUTPUT
    valid      : BOOL;
    loadedID   : INT;
END_VAR
VAR
    prev_loadCmd  : BOOL := FALSE;
    prev_running  : BOOL := FALSE;
    prev_valid    : BOOL := FALSE;
    prev_loadedID : INT  := 0;
    tmp_risingEdge: BOOL;
    tmp_loadOK    : BOOL;
    tmp_recipeValid: BOOL;
END_VAR
VAR_TEMP
    tmp_slotIdx : INT;
END_VAR
// ----------------------------------------------------------------------
// ENGINEERING_CONTRACT
// Outputs & scan-lifetime behavior (cite PUB IDs):
//   valid    : combinational output; activation on rising loadCmd when NOT running;
//              retention (no recalc) while running; no explicit reset.
//   loadedID : stored on successful load (PUB006); retained while running (PUB016);
//              explicit reset to 0 on invalid load or out-of-bounds slot (PUB005).
// Same-scan priority: running > slot-bounds > recipe validation > ratio > temperature.
// Units: ratio in % (99.0..101.0), temperature in °C (30.0..180.0).
// ----------------------------------------------------------------------

// Rising-edge detection for loadCmd
tmp_risingEdge := loadCmd AND NOT prev_loadCmd;

// Slot index captured once per scan to avoid repeated evaluation
tmp_slotIdx := selSlot;

// Compute load-OK guard: rising edge, not running, slot in [1..8]
// Prevents out-of-bounds array access (PUB002, PUB004, PUB005)
tmp_loadOK := tmp_risingEdge AND (NOT running)
              AND (tmp_slotIdx >= 1) AND (tmp_slotIdx <= 8);

IF tmp_loadOK THEN
    // Combine all three validation conditions (PUB003, PUB006, PUB007)
    // recipeID <> 0  -> slot non-empty
    // totalRatio in [99.0, 101.0]
    // temperature in [30.0, 180.0]
    tmp_recipeValid := (recipe[tmp_slotIdx].recipeID <> 0)
                       AND (recipe[tmp_slotIdx].totalRatio >= 99.0)
                       AND (recipe[tmp_slotIdx].totalRatio <= 101.0)
                       AND (recipe[tmp_slotIdx].temperature >= 30.0)
                       AND (recipe[tmp_slotIdx].temperature <= 180.0);

    IF tmp_recipeValid THEN
        loadedID := recipe[tmp_slotIdx].recipeID;
        valid    := TRUE;
    ELSE
        loadedID := 0;
        valid    := FALSE;
    END_IF;
ELSE
    // running=TRUE: ignore load command, hold previous loadedID (PUB016)
    // no rising edge: hold previous outputs (N10-S9)
    loadedID := prev_loadedID;
    valid    := prev_valid;
END_IF;

// Update state for next scan
prev_loadCmd  := loadCmd;
prev_running  := running;
prev_valid    := valid;
prev_loadedID := loadedID;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"loadedID","set_input":"loadCmd","reset_input":null}] *)