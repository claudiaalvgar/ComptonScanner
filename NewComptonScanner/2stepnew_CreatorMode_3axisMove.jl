xJA Main

Main:
    CSUB ConfigureStallGuard
    CSUB SmallMove
STOP


// ======================================================
// STALLGUARD CONFIG
// ======================================================
ConfigureStallGuard:

    SAP 174,0,7
    SAP 174,1,7
    SAP 174,2,7

    SAP 181,0,2500
    SAP 181,1,2500
    SAP 181,2,2500

RSUB

// ======================================================
// START MOTION
// ======================================================
SmallMove:

    SCO 0,0,-500000
    SCO 0,1,-500000
    SCO 0,2,-500000

    MVP COORD,0,0
    MVP COORD,1,0
    MVP COORD,2,0

JA MonitorMove


// ======================================================
// SAFETY MONITOR LOOP
// ======================================================
MonitorMove:

// --------------------------------------------------
// Snapshot current positions
// --------------------------------------------------
    GAP 1,0

    GAP 1,1

    GAP 1,2

    WAIT TICKS,0,5


// ======================================================
// AXIS 0 MOVEMENT CHECK
// ======================================================
    GAP 1,0
    GGP 0
    COMP 0
    JC EQ, Axis0Stopped

    JA CheckAxis1


Axis0Stopped:

    // if axis 0 stopped, check others still moving
    GAP 1,1
    GGP 1
    COMP 0
    JC NE, ConfirmAxis0Fault

    GAP 1,2
    GGP 2
    COMP 0
    JC NE, ConfirmAxis0Fault

    JA CheckAxis1


ConfirmAxis0Fault:
    WAIT TICKS,0,5

    GAP 1,0
    GGP 0
    COMP 0
    JC EQ, EmergencyStop

    JA CheckAxis1


// ======================================================
// AXIS 1 CHECK
// ======================================================
CheckAxis1:

    GAP 1,1
    GGP 1
    COMP 0
        JC EQ, Axis1Stopped

        JA CheckAxis2


Axis1Stopped:

    GAP 1,0
    GGP 0
    COMP 0
    JC NE, ConfirmAxis1Fault

    GAP 1,2
    GGP 2
    COMP 0
    JC NE, ConfirmAxis1Fault

    JA CheckAxis2


ConfirmAxis1Fault:
    WAIT TICKS,0,5

    GAP 1,1
    GGP 1
    COMP 0
    JC EQ, EmergencyStop

    JA CheckAxis2

        // ======================================================
// AXIS 2 CHECK
// ======================================================
CheckAxis2:

    GAP 1,2
    GGP 2
    COMP 0
    JC EQ, Axis2Stopped

    JA Continue


Axis2Stopped:

    GAP 1,0
    GGP 0
    COMP 0
    JC NE, ConfirmAxis2Fault

    GAP 1,1
    GGP 1
    COMP 0
    JC NE, ConfirmAxis2Fault

    JA Continue

ConfirmAxis2Fault:
    WAIT TICKS,0,5

    GAP 1,2
    GGP 2
    COMP 0
    JC EQ, EmergencyStop

    JA Continue


// ======================================================
// CONTINUE LOOP
// ======================================================
Continue:
    WAIT TICKS,0,1
    JA MonitorMove


// ======================================================
// EMERGENCY STOP ALL AXES
// ======================================================
EmergencyStop:

    MST 0
    MST 1
    MST 2

    WAIT TICKS,0,20

STOP
