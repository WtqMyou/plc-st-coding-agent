FUNCTION_BLOCK FB
VAR_INPUT
    runRequest  : BOOL;
    flameOK     : BOOL;
    o2Valid     : BOOL;
    o2PV        : REAL;
    baseAir     : REAL;
    resetBtn    : BOOL;
END_VAR
VAR_OUTPUT
    fuelPermit  : BOOL;
    trimEnable  : BOOL;
    airTrim     : REAL;
    airCommand  : REAL;
    tripLatched : BOOL;
    o2Fault     : BOOL;
END_VAR
VAR
    prev_resetBtn : BOOL := FALSE;
END_VAR

// ENGINEERING_CONTRACT
// [S1]  PUB003   tripLatched: ACTIVE when runRequest & !flameOK (same scan, no delay)
// [S2]  PUB008   tripLatched: HOLD until rising(resetBtn) & !runRequest & !flameOK
// [S3]  PUB008   tripLatched: inhibit fuelPermit while held (same scan)
// [S4]  PUB004   fuelPermit: ACTIVE when runRequest & flameOK & !tripLatched
// [S5]  PUB010   airCommand: FORCE 0.0 when !fuelPermit (same scan)
// [S6]  PUB010   airCommand: CLAMP [0.0, 100.0] always
// [S7]  PUB005   airTrim: CLAMP [-10.0, 10.0] always
// [S8]  PUB008   trimEnable: ACTIVE when fuelPermit & !o2Fault
// [S9]  PUB007   o2Fault: ACTIVE when !o2Valid | o2PV<0 | o2PV>21
// [S10] PUB008   airTrim: FORCE 0.0 when !trimEnable (no residual)
// [S11-S12] PUB006 airTrim: =2*(2-o2PV) raw, -10 limit only when o2PV>7
// [S13-S14] PUB010 airCommand: CLAMP [0,100] after baseAir+airTrim sum
// Reset: PUB023 edge-triggered, not level. Same-scan priority per S1/S3.

LOCAL_EDGE_TRIG_RISE := resetBtn AND NOT prev_resetBtn;
o2Fault := NOT o2Valid OR o2PV < 0.0 OR o2PV > 21.0;
tripLatched := tripLatched OR (runRequest AND NOT flameOK);
IF LOCAL_EDGE_TRIG_RISE AND NOT runRequest AND NOT flameOK THEN
    tripLatched := FALSE;
END_IF;
fuelPermit := runRequest AND flameOK AND NOT tripLatched;
trimEnable := fuelPermit AND NOT o2Fault;
IF trimEnable THEN
    airTrim := LIMIT(-10.0, 2.0 * (2.0 - o2PV), 10.0);
ELSE
    airTrim := 0.0;
END_IF;
IF fuelPermit THEN
    airCommand := LIMIT(0.0, baseAir + airTrim, 100.0);
ELSE
    airCommand := 0.0;
END_IF;
prev_resetBtn := resetBtn;
END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)