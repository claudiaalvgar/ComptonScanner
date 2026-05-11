JA Main
Main:
    CSUB PowerOff
STOP

DisableClosedLoop:

    SAP 129,0,0
    SAP 129,1,0
    SAP 129,2,0

    WaitDisableClosedLoop:

    WAIT TICKS,0,1
    GAP 133,0
    COMP 0
    JC NE, WaitDisableClosedLoop

    WAIT TICKS,0,1
    GAP 133,1
    COMP 0
    JC NE, WaitDisableClosedLoop

    WAIT TICKS,0,1
    GAP 133,2
    COMP 0
    JC NE, WaitDisableClosedLoop

    RSUB

PowerOff:
    MST 0                   // Motor STop Axis 0
    MST 1                   // Motor STop Axis 1
    MST 2                   // Motor STop Axis 2
    WAIT TICKS,0,10
    CSUB DisableClosedLoop
    SAP 6, 0, 0
    SAP 6, 1, 0
    SAP 6, 2, 0
    SAP 7, 0, 0
    SAP 7, 1, 0
    SAP 7, 2, 0
RSUB
