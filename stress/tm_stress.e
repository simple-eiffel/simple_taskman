note
	description: "[
		taskman_stress: known loads for the diagnosis acceptance runs.

		    taskman_stress cpu    --threads N --seconds S
		    taskman_stress memory --mb M      --seconds S [--step-mb K]
		    taskman_stress disk   --mb M      --seconds S --path DIR

		The first line printed is always this process's identity
		(pid=... creation=...), so a verdict's culprit can be checked against
		it (FR-031). Every mode stops at S seconds and says what it did.
		Exit code 0 on success, 2 for bad arguments, 3 if the load failed.
	]"
	author: "Larry Rix"

class
	TM_STRESS

create
	make

feature {NONE} -- Initialization

	make
			-- Print the identity, parse, run one load.
		local
			l_cli: SIMPLE_CLI
			l_self: TM_SELF_PROCESS
		do
			create l_self.make
			say ("pid=" + l_self.id.pid.out + " creation=" + l_self.id.creation_ticks.out)
			create l_cli.make
			l_cli.set_app_info ("taskman_stress", "Known loads for simple_taskman", "0.3.0")
			l_cli.add_option_with_default ("t|threads", "Spinning processors (cpu)", "N", "1")
			l_cli.add_option_with_default ("s|seconds", "How long to hold the load (1-3600)", "S", "30")
			l_cli.add_option_with_default ("m|mb", "Megabytes (memory, disk)", "M", "512")
			l_cli.add_option_with_default ("k|step-mb", "Growth step (memory)", "K", "64")
			l_cli.option_def ("p|path", "Folder for the scratch file (disk)", "DIR")
			l_cli.parse
			if l_cli.help_requested then
				io.put_string (l_cli.help_text + Usage)
			elseif l_cli.version_requested then
				io.put_string (l_cli.version_text + "%N")
			elseif not l_cli.is_successful then
				if l_cli.errors.is_empty then
					fail ("the arguments could not be read")
				else
					fail (l_cli.errors.first)
				end
			elseif not (1 <= seconds (l_cli) and seconds (l_cli) <= 3_600) then
				fail ("--seconds must be 1 to 3600")
			elseif attached l_cli.command as al_command and then al_command.same_string ("cpu") then
				run_cpu (l_cli.integer_option_or_default ("threads", 1), seconds (l_cli))
			elseif attached l_cli.command as al_command and then al_command.same_string ("memory") then
				run_memory (l_cli.integer_option_or_default ("mb", 512), l_cli.integer_option_or_default ("step-mb", 64), seconds (l_cli))
			elseif attached l_cli.command as al_command and then al_command.same_string ("disk") then
				if attached l_cli.value_of ("path") as al_path then
					run_disk (al_path.to_string_32, l_cli.integer_option_or_default ("mb", 512), seconds (l_cli))
				else
					fail ("disk needs --path DIR")
				end
			else
				fail ("expected a mode: cpu, memory, or disk")
			end
		end

feature {NONE} -- Loads

	run_cpu (a_threads, a_seconds: INTEGER)
			-- Spin `a_threads' processors for `a_seconds'.
		local
			l_spinners: ARRAYED_LIST [separate TM_SPINNER]
			l_spinner: separate TM_SPINNER
			l_total: INTEGER_64
			i: INTEGER
		do
			if a_threads < 1 or a_threads > 1_024 then
				fail ("--threads must be 1 to 1024")
			else
				say ("cpu: " + a_threads.out + " spinning processors for " + a_seconds.out + " s")
				create l_spinners.make (a_threads)
				from i := 1 until i > a_threads loop
					create l_spinner.make
					l_spinners.extend (l_spinner)
					launch (l_spinner, a_seconds * 1000)
					i := i + 1
				end
					-- A query on a busy spinner waits for its spin to finish: this joins them all.
				across l_spinners as ic loop
					l_total := l_total + iterations_of (ic)
				end
				say ("cpu: done, " + l_total.out + " rounds of 100,000 operations")
			end
		end

	run_memory (a_mb, a_step_mb, a_seconds: INTEGER)
			-- Grow to `a_mb' MB in `a_step_mb' steps, touching every page, and hold.
		local
			l_chunks: ARRAYED_LIST [MANAGED_POINTER]
			l_chunk: MANAGED_POINTER
			l_clock: TM_SYSTEM_CLOCK
			l_deadline: INTEGER_64
			l_held, l_offset: INTEGER
		do
			if a_mb < 1 or a_mb > 65_536 then
				fail ("--mb must be 1 to 65536")
			elseif a_step_mb < 1 or a_step_mb > a_mb then
				fail ("--step-mb must be 1 to --mb")
			else
				create l_clock.make
				l_deadline := l_clock.monotonic_ticks + a_seconds.to_integer_64 * 10_000_000
				create l_chunks.make (a_mb // a_step_mb + 1)
				from
				until
					l_held >= a_mb or l_clock.monotonic_ticks >= l_deadline
				loop
					create l_chunk.make (a_step_mb.min (a_mb - l_held) * Megabyte)
					from l_offset := 0 until l_offset >= l_chunk.count loop
						l_chunk.put_natural_8 ((l_offset // Page \\ 251).to_natural_8, l_offset)
						l_offset := l_offset + Page
					end
					l_chunks.extend (l_chunk)
					l_held := l_held + a_step_mb.min (a_mb - l_held)
					say ("memory: holding " + l_held.out + " MB")
					l_clock.sleep_ms (500)
				end
				from until l_clock.monotonic_ticks >= l_deadline loop
					l_clock.sleep_ms (200)
				end
				say ("memory: done, held " + l_held.out + " MB")
				l_chunks.wipe_out
			end
		end

	run_disk (a_folder: STRING_32; a_mb, a_seconds: INTEGER)
			-- Write and reread an uncached `a_mb' MB file in `a_folder' for `a_seconds'.
		local
			l_load: TM_DISK_LOAD
			l_folder: DIRECTORY
			l_utf: UTF_CONVERTER
		do
			create l_folder.make_with_name (a_folder)
			if a_mb < 1 or a_mb > 65_536 then
				fail ("--mb must be 1 to 65536")
			elseif not l_folder.exists then
				fail ("--path must be an existing folder")
			else
				say ("disk: " + a_mb.out + " MB uncached, write-through, for " + a_seconds.out + " s")
				create l_load.make (a_folder, a_mb)
				l_load.run (a_seconds)
				if l_load.last_error.is_empty then
					say ("disk: done, " + l_load.passes.out + " passes, " + (l_load.bytes_written // Megabyte).out
						+ " MB written, " + (l_load.bytes_read // Megabyte).out + " MB read")
				else
					say ("disk: stopped: " + l_utf.string_32_to_utf_8_string_8 (l_load.last_error))
					finish (3)
				end
			end
		end

feature {NONE} -- Separate calls

	launch (a_spinner: separate TM_SPINNER; a_ms: INTEGER)
		do
			a_spinner.spin (a_ms)
		end

	iterations_of (a_spinner: separate TM_SPINNER): INTEGER_64
		do
			Result := a_spinner.iterations
		end

feature {NONE} -- Implementation

	seconds (a_cli: SIMPLE_CLI): INTEGER
		do
			Result := a_cli.integer_option_or_default ("seconds", 30)
		end

	say (a_line: READABLE_STRING_8)
		do
			io.put_string (a_line + "%N")
			io.output.flush
		end

	fail (a_message: READABLE_STRING_8)
		do
			io.error.put_string ("taskman_stress: " + a_message + "%N" + Usage)
			finish (2)
		end

	finish (a_code: INTEGER)
		do
			(create {EXCEPTIONS}).die (a_code)
		end

	Megabyte: INTEGER = 1_048_576
	Page: INTEGER = 4_096

	Usage: STRING = "[
		usage:
		  taskman_stress cpu    --threads N --seconds S
		  taskman_stress memory --mb M --seconds S [--step-mb K]
		  taskman_stress disk   --mb M --seconds S --path DIR

	]"

end
