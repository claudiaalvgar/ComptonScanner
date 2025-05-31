include("filter_and_combine.jl")

function filter_loop(; ch = [1], nCZTs = 2)
	@assert(isdir("../conv_data/"),"../conv_data/ does not exist")
	@assert(isdir("../raw_data/"),"../raw_data/ does not exist")
        @assert(isdir("../err_data/"),"../err_data/ does not exist")
	@info "Filtering Loop Initialized. Terminate safely with ctrl-c."
	f_s = [0,0]
	try
		open("filtering_fails.txt", "w") do io
			write(io, "-1\t-1\n");
		end
		while true
			isactive, delete_src_files = true, false
			if isactive
				starttime = time()
				pausetime = 60

				# try
					#change to filter file one by one with timeout feature
					if nCZTs == 1
						filter_and_combine_data_1j("./","./", detname = "Baltec", ch = ch, delete_src_files=delete_src_files, f_s = f_s)
					elseif nCZTs == 2
						filter_and_combine_data_2j("./","./", detname = "Baltec", ch = ch, delete_src_files=delete_src_files, f_s = f_s)
					end
					GC.gc()
					sleep(max(time() - starttime - pausetime,0))
				# catch err
					# @warn err
					files = sort(filter(x -> endswith(x, "Z.lh5"), readdir("./")), by = x -> match(r"T\d{6}Z", x).match[2:end-1])
					if length(files) > 0 
						filename00 = files[1]
						@warn "File not filtered. Moving file and associated CZT file to ../err_data"
						filename01 = replace(filename00, "ICPC" => "CZT1")
						filename01 = replace(filename01, ".lh5" => ".h5")
						filename02 = replace(filename00, "ICPC" => "CZT2")
						filename02 = replace(filename02, ".lh5" => ".h5")
						mv(filename00, "../err_data/"*filename00)
						if filename01 in readdir("./")
							mv(filename01, "../err_data/"*filename01)
						end
						if filename02 in readdir("./")
							mv(filename02, "../err_data/"*filename02)
						end
						open("../err_data/filter_logs.txt", "a") do io
							write(io, "$(now())\t$filename00\t$err\n");
						end
						f_s[1] = f_s[1] + 1
						pausetime = 1
					else
						@info "No files found"
					end
				# end
				
				for file in filter(x -> endswith(x, "filtered.h5"), readdir("./"))
					mv(file, "../conv_data/"*file)
				end

				open("filtering_fails.txt", "w") do io
					write(io, "$(f_s[1])\t$(f_s[2])\n");
				end

				# pause so that everything is updated only every minute maximum
				took = time() - starttime
				if took < pausetime
					sleep(pausetime - took)
				end
			else
				f_s = [0,0]
				open("filtering_fails.txt", "w") do io
					write(io, "-1\t-1\n");
				end
				sleep(300)
			end
		end
	catch err
		if err isa InterruptException
			# cleanup
			rm("filtering_fails.txt", force = true)
			@info "Filtering terminated by user"
		 else
			# cleanup
			rm("filtering_fails.txt", force = true)
			rethrow(err)
		 end
	end
end

function filter_loop_2czt()
	@info "Filtering Loop Initialized. Terminate safely with ctrl-c."
	f_s = [0,0]
	try
		# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
		# 	write(io, "-1\t-1\n");
		# end
		while true
			isactive, delete_src_files = true, false #get_filter_settings()
			if isactive
				starttime = time()
				pausetime = 60

				try
					filter_and_combine_data_2j("./","./",delete_src_files=delete_src_files, f_s = f_s)
				catch err
					@warn err
					files = sort(filter(x -> endswith(x, "Z.lh5"), readdir("./")), by = x -> match(r"T\d{6}Z", x).match[2:end-1])
					if length(files) > 0 
						filename00 = files[1]
						@info "File not filtered. Moving file and associated CZT files to ../raw_data"
						filename01 = replace(filename00, "ICPC" => "CZT1")
						filename01 = replace(filename01, ".lh5" => ".h5")
						filename02 = replace(filename00, "ICPC" => "CZT2")
						filename02 = replace(filename02, ".lh5" => ".h5")
						mv(filename00, "../raw_data/"*filename00)
						mv(filename01, "../raw_data/"*filename01)
						mv(filename02, "../raw_data/"*filename02)
						f_s[1] = f_s[1] + 1
						pausetime = 1
					else
						@info "No files found"
					end
				end
				if !delete_src_files
					files = sort(filter(x -> endswith(x, "Z.lh5"), readdir("./")), by = x -> match(r"T\d{6}Z", x).match[2:end-1])
					for filename00 in files
						filename01 = replace(filename00, "ICPC" => "CZT1")
						filename01 = replace(filename01, ".lh5" => ".h5")
						filename02 = replace(filename00, "ICPC" => "CZT2")
						filename02 = replace(filename02, ".lh5" => ".h5")
						mv(filename00, "../raw_data/"*filename00)
						mv(filename01, "../raw_data/"*filename01)
						mv(filename02, "../raw_data/"*filename02)
					end
				end
				for file in filter(x -> endswith(x, "filtered.h5"), readdir("./"))
					mv(file, "../conv_data/"*file)
				end

				# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
				# 	write(io, "$(f_s[1])\t$(f_s[2])\n");
				# end

				#=
				# copy and compress HPGe background data
				for bkg in filter(x -> startswith(x, "bkg_") && endswith(x, ".lh5"), readdir())
				if occursin("ICPC", bkg)
					println(bkg)
					cbkg = replace(bkg, ".lh5" => ".h5")
					h5open(cbkg, "w") do h5f writedata(h5f, "bkg", read_all_from_julia(bkg)) end
					rm(bkg)
					rm(replace(replace(bkg, "ICPC" => "CZT1"), ".lh5" => ".h5"))
					rm(replace(replace(bkg, "ICPC" => "CZT2"), ".lh5" => ".h5"))
					chmod(cbkg, 0o774)
					mv(cbkg, "raw_data/"*cbkg)
				end
				end
				=#


				# pause so that everything is updated only every minute maximum
				took = time() - starttime
				if took < pausetime
					sleep(pausetime - took)
				end
			else
				f_s = [0,0]
				# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
				# 	write(io, "-1\t-1\n");
				# end
				sleep(300)
			end
		end
	catch err
		if err isa InterruptException
			# cleanup
			# rm("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", force = true)
			@info "Filtering terminated by user"
		 else
			# cleanup
			# rm("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", force = true)
			rethrow(err)
		 end
	end
end

function filter_loop_1czt()
	@assert(isdir("../conv_data/"),"../conv_data/ does not exist")
	@assert(isdir("../raw_data/"),"../raw_data/ does not exist")
    @assert(isdir("../err_data/"),"../err_data/ does not exist")
	@info "Filtering Loop Initialized. Terminate safely with ctrl-c."
	f_s = [0,0]
	try
		# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
		# 	write(io, "-1\t-1\n");
		# end
		while true
			isactive, delete_src_files = true, false # get_filter_settings()
			if isactive
				starttime = time()
				pausetime = 60

				try
					#change to filter file one by one with timeout feature
					filter_and_combine_data_1j("./","./",delete_src_files=delete_src_files, f_s = f_s)
				catch err
					@warn err
					files = sort(filter(x -> endswith(x, "Z.lh5"), readdir("./")), by = x -> match(r"T\d{6}Z", x).match[2:end-1])
					if length(files) > 0 
						filename00 = files[1]
						@warn "File not filtered. Moving file and associated CZT file to ../err_data"
						filename01 = replace(filename00, "ICPC" => "CZT1")
						filename01 = replace(filename01, ".lh5" => ".h5")
						mv(filename00, "../err_data/"*filename00)
						if filename01 in readdir("./")
							mv(filename01, "../err_data/"*filename01)
						end
						open("../err_data/filter_logs.txt", "a") do io
							write(io, "$(now())\t$filename00\t$err\n");
						end
						f_s[1] = f_s[1] + 1
						pausetime = 1
					else
						@info "No files found"
					end
				end
				
				for file in filter(x -> endswith(x, "filtered.h5"), readdir("./"))
					mv(file, "../conv_data/"*file)
				end

				# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
				# 	write(io, "$(f_s[1])\t$(f_s[2])\n");
				# end

				# pause so that everything is updated only every minute maximum
				took = time() - starttime
				if took < pausetime
					sleep(pausetime - took)
				end
			else
				f_s = [0,0]
				# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
				# 	write(io, "-1\t-1\n");
				# end
				sleep(300)
			end
		end
	catch err
		if err isa InterruptException
			# cleanup
			# rm("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", force = true)
			@info "Filtering terminated by user"
		 else
			# cleanup
			# rm("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", force = true)
			rethrow(err)
		 end
	end
end

function filter_loop_1czt_offline(; delete_src_files = false)
	@assert(isdir("../conv_data/"),"../conv_data/ does not exist")
	@assert(isdir("../raw_data/"),"../raw_data/ does not exist")
    @assert(isdir("../err_data/"),"../err_data/ does not exist")
	@info "Filtering Loop Initialized. Terminate safely with ctrl-c."
	try
		while true
			starttime = time()
			pausetime = 60
			try
				#change to filter file one by one with timeout feature
				filter_and_combine_data_1j("./","./",delete_src_files=delete_src_files)
			catch err
				@warn err
				files = sort(filter(x -> endswith(x, "Z.lh5"), readdir("./")), by = x -> match(r"T\d{6}Z", x).match[2:end-1])
				if length(files) > 0 
					filename00 = files[1]
					@warn "File not filtered. Moving file and associated CZT file to ../err_data"
					filename01 = replace(filename00, "ICPC" => "CZT1")
					filename01 = replace(filename01, ".lh5" => ".h5")
					mv(filename00, "../err_data/"*filename00)
					if filename01 in readdir("./")
						mv(filename01, "../err_data/"*filename01)
					end
					open("../err_data/filter_logs.txt", "a") do io
						write(io, "$(now())\t$filename00\t$err\n");
					end
					pausetime = 1
				else
					@info "No files found"
				end
			end
			
			for file in filter(x -> endswith(x, "filtered.h5"), readdir("./"))
				mv(file, "../conv_data/"*file)
			end

			# pause so that everything is updated only every minute maximum
			took = time() - starttime
			if took < pausetime
				sleep(pausetime - took)
			end
		end
	catch err
		if err isa InterruptException
			# cleanup
			@info "Filtering terminated by user"
		 else
			# cleanup
			rethrow(err)
		 end
	end
end

function filter_loop_1czt_new(;timeout = 600)
	@info "Filtering Loop Initialized. Terminate safely with ctrl-c."
	f_s = [0,0]
	try
		# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
		# 	write(io, "-1\t-1\n");
		# end
		while true
			isactive, delete_src_files = get_filter_settings()
			if isactive
				starttime = time()
				pausetime = 60
				files = sort(filter(x -> endswith(x, "Z.lh5"), readdir("./")), by = x -> match(r"T\d{6}Z", x).match[2:end-1])
				for filename00 in files
					try
						t0 = time()
   						t = 0.0
						task = @async filter_and_combine_data_1czt(filename00,delete_src_files=delete_src_files)
						while t < timeout
							if task.state == :done break end
							t = time()-t0
							sleep(0.1)
						end
						if t ≥ timeout
							@warn "Timeout. File not filtered."
							@warn "Moving file and associated CZT file to ../raw_data"
							try
								filename01 = replace(filename00, "ICPC" => "CZT1")
								filename01 = replace(filename01, ".lh5" => ".h5")
								mv(filename00, "../raw_data/"*filename00)
								mv(filename01, "../raw_data/"*filename01)
								f_s[1] = f_s[1] + 1
							catch err
								@warn err
							end
						end	
					catch err
						@warn err
						@warn "Moving file and associated CZT file to ../raw_data"
						try
							filename01 = replace(filename00, "ICPC" => "CZT1")
							filename01 = replace(filename01, ".lh5" => ".h5")
							mv(filename00, "../raw_data/"*filename00)
							mv(filename01, "../raw_data/"*filename01)
							f_s[1] = f_s[1] + 1
						catch err
							@warn err
						end
					end
					if !delete_src_files
						try
							filename01 = replace(filename00, "ICPC" => "CZT1")
							filename01 = replace(filename01, ".lh5" => ".h5")
							mv(filename00, "../raw_data/"*filename00)
							mv(filename01, "../raw_data/"*filename01)
						catch err
							@warn err
						end
					end
				end
				
				for file in filter(x -> endswith(x, "filtered.h5"), readdir("./"))
					try
						mv(file, "../conv_data/"*file)
					catch err
						@warn err
					end
				end

				# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
				# 	write(io, "$(f_s[1])\t$(f_s[2])\n");
				# end

				# pause so that everything is updated only every minute maximum
				took = time() - starttime
				if took < pausetime
					sleep(pausetime - took)
				end
			else
				f_s = [0,0]
				# open("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", "w") do io
				# 	write(io, "-1\t-1\n");
				# end
				sleep(300)
			end
		end
	catch err
		if err isa InterruptException
			# cleanup
			# rm("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", force = true)
			@info "Filtering terminated by user"
		 else
			# cleanup
			# rm("/remote/ceph2/user/g/gelab/home/ICPC_scripts/daq/filtering_fails.txt", force = true)
			rethrow(err)
		 end
	end
end

function filter_loop_1czt_minimal(;timeout = 600, delete_src_files = false)
	@info "Filtering Loop Initialized. Terminate safely with ctrl-c."
	starttime = time()
	pausetime = 60
	files = sort(filter(x -> endswith(x, "Z.lh5"), readdir("./")), by = x -> match(r"T\d{6}Z", x).match[2:end-1])
	for filename00 in files[1:1]
		#filename00 = "bkg_" * filename00
		t0 = time()
		t = 0.0
		task = @async filter_and_combine_data_1czt(filename00,delete_src_files=delete_src_files)
		while t < timeout ##works very well except for what it was designed for. When filtering a file actually hangs, julia becomes unresponsive as a whole. ctrl-c works though??
			if task.state == :done || task.state == :failed break end
			t = time()-t0
			sleep(0.1)
		end
		if t ≥ timeout || task.state == :failed
			if t ≥ timeout
				@warn "Timeout. File not filtered."
				@async Base.throwto(task, InterruptException())
			elseif task.state == :failed
				@warn task.result
			end
			@warn "Moving file and associated CZT file to ../raw_data"
		end	
	end
end
