JA Main
Main:
 CSUB PowerOn
 CSUB StartInit
 CSUB DisableClosedLoop
 CSUB EnableClosedLoop
 //homing here
 CSUB SmallMove
STOP

PowerOn:
    SAP 210, 1, 2000
    SAP 4,1,51200
    SAP 5,1,51200
    SAP 17,1,51200
    SAP 6, 1, 25
    SAP 7, 1, 8
    WAIT TICKS, 0, 10 // Sync encoder → target position
    SAP 209,1,0
    GAP 209,1     // encoder position -> accumulator
    AAP 1,1       // set actual position = encoder
    GAP 209,1
    AAP 0,1       // set target position = encoder
    WAIT TICKS, 0, 10
    RSUB
StartInit:
    SAP 108,1,300000
    SAP 109,1,600000
    SAP 110,1,255
    SAP 111,1,255
    SAP 113,1,50
    SAP 114,1,240
    SAP 126,1,25
    SAP 125,1,100
    SAP 134,1,100
    SAP 120,1,1000
    SAP 121,1,10000
    SAP 115,1,3000
    SAP 116,1,20
    SAP 117,1,10
    SAP 118,1,0
    SAP 119,1,100000
    SAP 124,1,65536
    SAP 212,1,1000
    SAP 213,1,30000
    RSUB
DisableClosedLoop:
    SAP 129,1,0
    WaitDisableClosedLoop:
      WAIT TICKS,0,1
      GAP 133,1 
      COMP 0
      JC NE, WaitDisableClosedLoop
    RSUB
EnableClosedLoop:
    SAP 129,1,1
    WaitEnableClosedLoop:
       WAIT TICKS,0,1
       GAP 133,1 
       COMP 1
       JC NE, WaitEnableClosedLoop
    WAIT TICKS, 0, 10 // Sync encoder → target position
    SAP 209,1,0
    GAP 209,1     // encoder position -> accumulator
    AAP 1,1       // set actual position = encoder
    GAP 209,1
    AAP 0,1       // set target position = encoder
    WAIT TICKS,0,10
    RSUB
SmallMove:
    SCO 0,1,100000
    MVP COORD,1,0
    WAIT POS,1,0
    WAIT TICKS, 0, 10
    RSUB
