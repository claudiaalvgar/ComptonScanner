using LegendHDF5IO
using ArraysOfArrays
using Unitful
using Plots

cam_fn = "/home/gelab/Measurements/ComptonScanner/raw_data/R_3.0mm_-CZT.h5"
cam = lh5open(cam_fn) do h5
    h5["data_raw"][:]
end

# x-z-crosssection (looking from top)
histogram2d(ArraysOfArrays.flatview(cam.hit_x), ArraysOfArrays.flatview(cam.hit_z), ratio = 1)

# x-y-crosssection (looking from the side, where the detector is)
histogram2d(ArraysOfArrays.flatview(cam.hit_x), ArraysOfArrays.flatview(cam.hit_y), ratio = 1, bins = (-22000:500:22000, -22000:500:22000))

# plot the timestamps of:
# 1. ALL events
stephist(uconvert.(u"s", cam.evt_t .- first(cam.evt_t)))
# stephist(uconvert.(u"s", cam.evt_t .- first(cam.evt_t)), bins = 0:0.5:28) # with binning

# 2. JUST the sync pulses
stephist(uconvert.(u"s", cam.evt_t[findall(cam.evt_issync)] .- first(cam.evt_t)))

# => If the sync pulses are not within the physics data timestamp range,
# you might need to restart the camera (just by a power cycle)
# and check if the timestamps are back where they belong


# If you want to select events that happend within 47 and 49 seconds of the measurement
cam_selection = cam[findall(47u"s".< cam.evt_t .- first(cam.evt_t) .< 49u"s")]

# Plot event distirbutions (spatially)
x = ArraysOfArrays.flatview(cam.hit_x)
y = ArraysOfArrays.flatview(cam.hit_y)
z = ArraysOfArrays.flatview(cam.hit_z)
scatter(x,y,z, fmt = :png)

# This is to plot the camera IN ITS OWN (!!) COORDINATE SYSTEM
for Δx in (-11u"mm", 11u"mm"), Δy in (-11u"mm", 11u"mm"), Δz in (0u"mm" , 10u"mm")
    plot!([-10u"mm", 10u"mm", 10u"mm", -10u"mm", -10u"mm"] .+ Δx, [-10u"mm", -10u"mm", 10u"mm", 10u"mm", -10u"mm"] .+ Δy, [0u"mm" for _ in 1:5] .+ Δz, color = :black, lw=2, label ="")
end
plot!(xlims =(-30u"mm", 30u"mm"), ylims = (-30u"mm", 30u"mm"), zlims = (-25u"mm", 35u"mm"), camera = (0,90))

