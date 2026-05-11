JA Main
Main:
    CSUB ConfigureStallGuard
    CSUB SmallMove
STOP

ConfigureStallGuard:

    SAP 174,0,7
    SAP 174,1,7
    SAP 174,2,7

    SAP 181,0,0
    SAP 181,1,0
    SAP 181,2,0

RSUB

SmallMove:

    SCO 0,0,100000
    SCO 0,1,100000
    SCO 0,2,100000

    MVP COORD,0,0
    MVP COORD,1,0
    MVP COORD,2,0

    // allow motion to stabilize
    WAIT TICKS,0,50

    JA MonitorMove

MonitorMove:
    GAP 8,0
    COMP 1
    JC NE, CheckAxis0

    GAP 8,1
    COMP 1
    JC NE, CheckAxis0

    GAP 8,2
    COMP 1
    JC NE, CheckAxis0

    // all axes reached target
    RSUB
// --------------------------------------------------
// AXIS 0 CHECK
// --------------------------------------------------
CheckAxis0:

    // ==================================================
    // Only monitor axis if target NOT reached
    // ==================================================
    GAP 8,0
    COMP 0
    JC NE, CheckAxis1

    GAP 206,0
    COMP 60
    JC LE, Axis0_Stopped

    JA CheckAxis1
Axis0_Stopped:

    GAP 206,1
    COMP 60
    JC GT, EmergencyStop

    GAP 206,2
    COMP 60
    JC GT, EmergencyStop

    JA CheckAxis1

// --------------------------------------------------
// AXIS 1 CHECK
// --------------------------------------------------
CheckAxis1:

    // ==================================================
    // Only monitor axis if target NOT reached
    // ==================================================
    GAP 8,1
    COMP 0
    JC NE, CheckAxis2

    GAP 206,1
    COMP 60
    JC LE, Axis1_Stopped

    JA CheckAxis2


Axis1_Stopped:

    GAP 206,0
    COMP 60
    JC GT, EmergencyStop

    GAP 206,2
    COMP 60
    JC GT, EmergencyStop

    JA CheckAxis2

// --------------------------------------------------
// AXIS 2 CHECK
// --------------------------------------------------
CheckAxis2:

    // ==================================================
    // Only monitor axis if target NOT reached
    // ==================================================
    GAP 8,2
    COMP 0
    JC NE, ContinueLoop

    GAP 206,2
    COMP 60
    JC LE, Axis2_Stopped

    JA ContinueLoop


Axis2_Stopped:

    GAP 206,0
    COMP 60
    JC GT, EmergencyStop

    GAP 206,1
    COMP 60
    JC GT, EmergencyStop

    JA ContinueLoop

// --------------------------------------------------
// CONTINUE LOOP
// --------------------------------------------------
ContinueLoop:

    WAIT TICKS,0,1
    JA MonitorMove

// ======================================================
// EMERGENCY STOP
// ======================================================
EmergencyStop:

    MST 0
    MST 1
    MST 2

    WAIT TICKS,0,20

STOP    
