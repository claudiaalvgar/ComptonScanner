JA Main
Main:
    CSUB PowerOn
    CSUB StartInit
    CSUB DisableClosedLoop
    CSUB EnableClosedLoop
    // homing here
    // CSUB SmallMove
STOP

PowerOn:

    SAP 210,0,2000
    SAP 210,1,2000
    SAP 210,2,2000

    SAP 4,0,51200
    SAP 4,1,51200
    SAP 4,2,51200

    SAP 5,0,51200
    SAP 5,1,51200
    SAP 5,2,51200

    SAP 17,0,51200
    SAP 17,1,51200
    SAP 17,2,51200

    SAP 6,0,25
    SAP 6,1,25
    SAP 6,2,25

    SAP 7,0,8
    SAP 7,1,8
    SAP 7,2,8

    WAIT TICKS,0,10

    SAP 209,0,0
    SAP 209,1,0
    SAP 209,2,0

    GAP 209,0
    AAP 1,0

    GAP 209,1
    AAP 1,1

    GAP 209,2
    AAP 1,2

    GAP 209,0
    AAP 0,0

    GAP 209,1
    AAP 0,1

    GAP 209,2
    AAP 0,2

    WAIT TICKS,0,10
    RSUB

StartInit:

    SAP 108,0,300000
    SAP 108,1,300000
    SAP 108,2,300000

    SAP 109,0,600000
    SAP 109,1,600000
    SAP 109,2,600000

    SAP 110,0,255
    SAP 110,1,255
    SAP 110,2,255

    SAP 111,0,255
    SAP 111,1,255
    SAP 111,2,255

    SAP 113,0,50
    SAP 113,1,50
    SAP 113,2,50

    SAP 114,0,240
    SAP 114,1,240
    SAP 114,2,240

    SAP 126,0,25
    SAP 126,1,25
    SAP 126,2,25

    SAP 125,0,100
    SAP 125,1,100
    SAP 125,2,100

    SAP 134,0,100
    SAP 134,1,100
    SAP 134,2,100

    SAP 120,0,1000
    SAP 120,1,1000
    SAP 120,2,1000

    SAP 121,0,10000
    SAP 121,1,10000
    SAP 121,2,10000

    SAP 115,0,3000
    SAP 115,1,3000
    SAP 115,2,3000

    SAP 116,0,20
    SAP 116,1,20
    SAP 116,2,20

    SAP 117,0,10
    SAP 117,1,10
    SAP 117,2,10

    SAP 118,0,0
    SAP 118,1,0
    SAP 118,2,0

    SAP 119,0,100000
    SAP 119,1,100000
    SAP 119,2,100000

    SAP 124,0,65536
    SAP 124,1,65536
    SAP 124,2,65536

    SAP 212,0,1000
    SAP 212,1,1000
    SAP 212,2,1000

    SAP 213,0,30000
    SAP 213,1,30000
    SAP 213,2,30000

    RSUB

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

EnableClosedLoop:

    SAP 129,0,1
    SAP 129,1,1
    SAP 129,2,1

    WaitEnableClosedLoop:

    WAIT TICKS,0,1
    GAP 133,0
    COMP 1
    JC NE, WaitEnableClosedLoop

    WAIT TICKS,0,1
    GAP 133,1
    COMP 1
    JC NE, WaitEnableClosedLoop

    WAIT TICKS,0,1
    GAP 133,2
    COMP 1
    JC NE, WaitEnableClosedLoop

    WAIT TICKS,0,10

    SAP 209,0,0
    GAP 209,0
    AAP 1,0
    GAP 209,0
    AAP 0,0

    SAP 209,1,0
    GAP 209,1
    AAP 1,1
    GAP 209,1
    AAP 0,1

    SAP 209,2,0
    GAP 209,2
    AAP 1,2
    GAP 209,2
    AAP 0,2

    WAIT TICKS,0,10
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
