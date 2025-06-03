using ProgressMeter
using Plots
using StatsBase
using LsqFit

using RadiationDetectorDSP
using LegendDSP
using LegendHDF5IO

#file = "/remote/ceph/user/a/alvarez/ComptonScanner/Ba_Data/raw_data/133Ba_Compton_R_0.0mm_Z_-0.0mm_Phi_138.7deg_T_80.0K_measuretime_300sec-ICPC-20250522T144857Z.lh5"

file = "/remote/ceph/user/a/alvarez/ComptonScanner/Cs_Data/raw_data/R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T132022Z.lh5"

#file = "/remote/ceph/user/a/alvarez/ComptonScanner/Cs_Data/raw_data/R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T133133Z.lh5"

dt = 4 #ns
key = "1"

t = lh5open(file) do h
 Dict(key => h[key][:] for key in keys(h))
end

samples = t[key].samples[findall(t[key].channel .== 1)]
println("Number of adc values in 1st waveform of key 1 in channel 1: $(length(samples[1]))")

println("Number of waveforms in key 1 in channel 1: $(length(samples))")

plot(0:dt:1200*dt-dt, samples[1:10], xlabel = "Time in ns", ylabel = "Signal in ADC units", fmt = :png, size = (600,400), legend = false, title = "Raw waveforms")

#savefig("RawPulses_Cs.png")


for i in 1:10
    plot(collect(0:dt:(length(samples[i])-1)*dt), samples[i], xlabel = "Time [ns]", ylabel = "ADC Counts")
    savefig("Cs_waveform[$(key)]-$(i).png")
end





#=

t = lh5open(file) do h
    h["1"][:]
end

samples = t.samples[findall(t.channel .== 1)]
println("Number of adc values in 1st waveform of key 1 in channel 1: $(length(samples[1]))")

data = lh5open(file) do h
     keys(h) 
end


for i in 1:10
    plot(collect(0:dt:(length(samples[i])-1)*dt), samples[i], xlabel = "Time [ns]", ylabel = "ADC Counts")
    #savefig("waveform[2]-$(i).png")
end

#plot 10 raw waveform and pass mean value from previous studies

#plot(0:dt:1200*dt-dt, t.samples[findall(t.channel .== 1)][1:10], xlabel = "Time in ns", ylabel = "Signal in ADC units", fmt = :png, size = (600,400), legend = false, title = "Raw waveforms")
=#