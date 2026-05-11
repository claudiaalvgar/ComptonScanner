JA Main

Main:
    CSUB ConfigureStallGuard
    CSUB SmallMove
STOP


ConfigureStallGuard:

    SAP 174,0,7
    SAP 174,1,7
    SAP 174,2,7

    SAP 181,0,1000
    SAP 181,1,1000
    SAP 181,2,1000

RSUB


SmallMove:

    SCO 0,0,100000
    SCO 0,1,100000
    SCO 0,2,100000

    MVP COORD,0,0
    MVP COORD,1,0
    MVP COORD,2,0

    WAIT TICKS,0,200

    JA MonitorMove


// ======================================================
// SIMPLE DETERMINISTIC SAFETY LOOP
// ======================================================
MonitorMove:

// ----------------------
// AXIS 0
// ----------------------
    GAP 8,0
    COMP 1
    JC EQ, Check1

    GAP 206,0
    COMP 60
    JC LE, EmergencyStop


// ----------------------
// AXIS 1
// ----------------------
    Check1:

    GAP 8,1
    COMP 1
    JC EQ, Check2

    GAP 206,1
    COMP 60
    JC LE, EmergencyStop


// ----------------------
// AXIS 2
// ----------------------
Check2:

    GAP 8,2
    COMP 1
    JC EQ, Continue

    GAP 206,2
    COMP 60
    JC LE, EmergencyStop


// ----------------------
// CONTINUE LOOP
// ----------------------
Continue:

    WAIT TICKS,0,1
    JA MonitorMove


// ======================================================
// STOP ALL AXES
// ======================================================
EmergencyStop:

    MST 0
    MST 1
    MST 2

    STOP
