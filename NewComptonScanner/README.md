Scripts for just a 1 run:

• 1st step run: 1step_CreatorMode_3axisMove.tmc to set up the closed loop and initial variables

• 2nd: CalibrationMode_HitPlatform.tmc

-> StartCalibration with positive values (i.e. : SCO 0,0,1000000) will move the sleds down until one of them hits the bottom platform and they will all stop

-> ReferenceZero will set this position to 0

-> StartCalibration with negative values (i.e. : SCO 0,0,-500000) will move the sleds upwards for initialise the movement

• 3rd: Laststep_CreatorMode_3axisPowerOff.tmc will power off the 3 motors

Script meant to be looping in the tmcm board waiting for julia inputs (not tested yet)

TMCMCode_newversion.tmc