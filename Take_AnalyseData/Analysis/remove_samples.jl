#can be applied to the result of the alignment measurements, because there we don’t really need the waveforms - filesize/event rate might be fine. So this just frees disk space
#
using HDF5, LegendHDF5IO
include("/mnt/scratch/p-type_segBEGe_in_K2/ComptonScanner/filter.jl")

try
while true
	starttime = time()
	pausetime = 60
for f in filter!(f -> endswith(f, "Z.lh5") && occursin("ICPC", f), readdir())
	newf = replace(f, "ICPC" => "segBEGe_no_samples")
	if isfile(newf)
		@warn "File was already converted... skipping!"
		continue
	end
	@info "Converting $(f)"
	t = read_data_from_julia(f, ch = 1:5)
	h5open(newf, "cw") do h5f LegendHDF5IO.writedata(h5f, "segBEGe", t) end
	rm(f)
	mv(newf, "../conv_data/" * newf)
	@info "Done!"
end
	GC.gc()
	sleep(max(pausetime - (time() - starttime), 0))
end
catch e
	if e isa InterruptException
		@info "Terminated by user"
	else
		rethrow(err)
	end
end



