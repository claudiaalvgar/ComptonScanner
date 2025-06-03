#In command line: launch GUI first and set default settings#
#ping gelab						   #
#sis3316-test-gui					   #
############################################################

#Julia Script
using GeDetK2Control

#we can pass the adc ip adress
#adc = "192.168.2.178"
#This is default in gelab/Measurements/ComptonScanner/sis3316_capture_chunking.jl
#adc = "gelab-fadc10"

cd("/home/gelab/Measurements/ComptonScanner/Data/newData_temp")
include("/home/gelab/Measurements/ComptonScanner/sis3316_capture_chunking.jl")

motor = k2.mymotor()

#Calibrate : horizontal, vertical and rotational
# Calibrate_Hor(motor)
# Calibrate_Vert(motor)
# Calibrate(motor)

#Choose a position (pos in mm, )
# HorAbsMM(0,motor)
# VertAbsMM(10,motor)
# RotAbsDeg(0,motor)

#Print current position
Pos(motor)

#Take data: take_data_hpge_onlyj(time, temp, motor, voltage, time_chunks=seconds of data per file, Lan: enable_jumbo_frames=false glass fiber: enable_jumbo_frames=true)
# Only detector (valid for CS and BEGe detector)
# take_data_hpge_onlyj(30, 80, motor, HV = 3200, enable_jumbo_frames=false)
# take_data_hpge_onlyj(30, 80, motor, adc = adc, HV = 3200, enable_jumbo_frames=false)

# Data from detector + cameras (only valid for CS)
# take_data_hpge_plus_2cztj(100, 80, motor, time_chunks=300, enable_jumbo_frames=false)

#If taking data only from the source in the cameras do (if no name of camera is passes I think it takes in both) (name, time, namefile)
# using H3DDetectorSystems
# cam01 = PolarisDetector("gelab-polaris01")
# H3DDetectorSystems.get_czr_data("gelab-polaris01", 60, "R_3.0mm_")


@info "Finished data taken, generated files in: /home/gelab/Measurements/ComptonScanner/Data/newData_temp"
