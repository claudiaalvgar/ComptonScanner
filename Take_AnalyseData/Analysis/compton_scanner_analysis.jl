using LegendHDF5IO
using Plots
using Unitful

det, cam = lh5open("/local/scratch/Measurements/ComptonScanner/conv_data/R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-20250523T132022Z-filtered.h5") do h
       h["ICPC"][:], h["czt"][:]
       end

#det will print the table detector: evt_no  chid  evt_t DAQ_energy  samples
#cam will print the camera table
#Plot the fadc recorded energy deposited in the detector (after MWD in the fadc)
stephist(det.DAQ_energy)

stephist(det.DAQ_energy, bins = 0:1e3:1e6)
vline!([6.06e5])

#Quick fadc to energy calibration
stephist(det.DAQ_energy ./ 6.06e5 * 661.66, bins = 0:1:1000)


E_det = det.DAQ_energy ./ 6.06e5 * 661.66u"keV"

#Sum all the energy deposited in the camera per event
cam = cam[1:length(det)]
Ecam = sum.(cam.hit_edep)

#Plot the events with some energy deposited in the detector and some energy deposited in the camera
#histogram2d(E_det, uconvert.(u"keV", Ecam), bins =(0:1:700,0:1:700))
histogram2d(E_det, uconvert.(u"keV", Ecam), bins =(0:1:700,0:1:700), ratio = 1)
#plot!([0,661.66],[661.66,0])