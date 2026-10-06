note
	description: "[
		taskman_cli: the headless front end.

		    taskman_cli snapshot [--top N] [--self] [--interval MS] [--save-frames N --file PATH]
		    taskman_cli capabilities
		    taskman_cli synthetic [--processes N] --save-frames N --file PATH
		    taskman_cli clockwatch [--seconds S]
		    taskman_cli trace [--ago SECONDS] [--top N] [--file PATH]

		Exit code 0 on success, 2 for bad arguments, 3 if the machine could not
		be read. Parsing only; the work is in the command classes.
	]"
	author: "Larry Rix"

class
	TM_CLI

create
	make

feature {NONE} -- Initialization

	make
			-- Parse, run one command, print, and exit with its code.
		local
			l_cli: SIMPLE_CLI
		do
			create l_cli.make
			l_cli.set_app_info ("taskman_cli", "Diagnostic task manager, headless", "0.3.0")
			l_cli.add_option_with_default ("t|top", "Busiest processes to list (1-500)", "N", "10")
			l_cli.add_option_with_default ("i|interval", "Milliseconds between the two samples (250-60000)", "MS", "1000")
			l_cli.flag ("s|self", "Also show this tool's own CPU and memory")
			l_cli.add_option_with_default ("n|save-frames", "Frames to save for replay", "N", "0")
			l_cli.option_def ("f|file", "File for --save-frames", "PATH")
			l_cli.add_option_with_default ("p|processes", "Processes in synthetic frames (1-50000)", "N", "5000")
			l_cli.add_option_with_default ("c|seconds", "How long clockwatch watches (2-86400)", "S", "180")
			l_cli.add_option_with_default ("a|ago", "trace: seconds before the newest recorded frame", "SECONDS", "0")
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
			elseif attached l_cli.command as al_command and then al_command.same_string ("snapshot") then
				run_snapshot (l_cli)
			elseif attached l_cli.command as al_command and then al_command.same_string ("capabilities") then
				run_capabilities
			elseif attached l_cli.command as al_command and then al_command.same_string ("synthetic") then
				run_synthetic (l_cli)
			elseif attached l_cli.command as al_command and then al_command.same_string ("clockwatch") then
				run_clock_watch (l_cli.integer_option_or_default ("seconds", 180))
			elseif attached l_cli.command as al_command and then al_command.same_string ("trace") then
				run_trace (l_cli)
			else
				fail ("expected a command: snapshot, capabilities, synthetic, clockwatch, or trace")
			end
		end

feature {NONE} -- Commands

	run_snapshot (a_cli: SIMPLE_CLI)
			-- Validate the options, then run `snapshot'.
		local
			l_top, l_interval, l_count: INTEGER
			l_command: TM_SNAPSHOT_COMMAND
		do
			l_top := a_cli.integer_option_or_default ("top", 10)
			l_interval := a_cli.integer_option_or_default ("interval", 1000)
			l_count := a_cli.integer_option_or_default ("save-frames", 0)
			if l_top < 1 or l_top > {TM_SNAPSHOT_COMMAND}.Maximum_top then
				fail ("--top must be 1 to 500")
			elseif l_interval < 250 or l_interval > 60_000 then
				fail ("--interval must be 250 to 60000 milliseconds")
			elseif l_count < 0 or l_count > 86_400 then
				fail ("--save-frames must be 0 to 86400")
			elseif l_count > 0 and not attached a_cli.value_of ("file") then
				fail ("--save-frames needs --file PATH")
			else
				create l_command.make (l_top, l_interval, a_cli.has_flag ("self"))
				if l_count > 0 and then attached a_cli.value_of ("file") as al_path and then not al_path.is_empty then
					l_command.set_save (l_count, al_path.to_string_32)
				end
				l_command.execute
				put_output (l_command.output)
				finish (l_command.exit_code)
			end
		end

	run_synthetic (a_cli: SIMPLE_CLI)
			-- Validate the options, then write a synthetic replay file.
		local
			l_processes, l_frames: INTEGER
			l_command: TM_SYNTHETIC_COMMAND
		do
			l_processes := a_cli.integer_option_or_default ("processes", 5000)
			l_frames := a_cli.integer_option_or_default ("save-frames", 0)
			if l_processes < 1 or l_processes > 50_000 then
				fail ("--processes must be 1 to 50000")
			elseif l_frames < 1 or l_frames > 3_600 then
				fail ("synthetic needs --save-frames 1 to 3600")
			elseif attached a_cli.value_of ("file") as al_path and then not al_path.is_empty then
				create l_command.make (l_processes, l_frames, al_path.to_string_32)
				l_command.execute
				put_output (l_command.output)
				finish (l_command.exit_code)
			else
				fail ("synthetic needs --file PATH")
			end
		end

	run_clock_watch (a_seconds: INTEGER)
			-- Watch the clocks across a sleep.
		local
			l_command: TM_CLOCK_WATCH_COMMAND
		do
			if a_seconds < 2 or a_seconds > 86_400 then
				fail ("--seconds must be 2 to 86400")
			else
				io.put_string ("watching wall and monotonic time for " + a_seconds.out + " s; put the machine to sleep for a minute, then wake it%N")
				create l_command.make (a_seconds)
				l_command.execute
				put_output (l_command.output)
				finish (l_command.exit_code)
			end
		end

	run_trace (a_cli: SIMPLE_CLI)
			-- Describe the recording: the per-user one, or --file.
		local
			l_command: TM_TRACE_COMMAND
			l_paths: TM_PATHS
			l_path: STRING_32
			l_ago, l_top: INTEGER
		do
			l_ago := a_cli.integer_option_or_default ("ago", 0)
			l_top := a_cli.integer_option_or_default ("top", 10)
			if attached a_cli.option_value ("file") as al_file then
				l_path := al_file.to_string_32
			else
				create l_paths.make
				if l_paths.has_root then
					l_path := l_paths.trace_path
				else
					create l_path.make_empty
				end
			end
			if l_path.is_empty then
				fail ("no recording path: LOCALAPPDATA is not set; give --file PATH")
			elseif l_ago < 0 or l_ago > 2_592_000 then
				fail ("--ago must be 0 to 2592000")
			elseif l_top < 1 or l_top > 500 then
				fail ("--top must be 1 to 500")
			else
				create l_command.make (l_path, l_ago, l_top)
				l_command.execute
				put_output (l_command.output)
				finish (l_command.exit_code)
			end
		end

	run_capabilities
			-- Run `capabilities'.
		local
			l_command: TM_CAPABILITIES_COMMAND
		do
			create l_command.make
			l_command.execute
			put_output (l_command.output)
			finish (l_command.exit_code)
		end

feature {NONE} -- Implementation

	fail (a_message: READABLE_STRING_8)
			-- Report a usage error and exit with 2.
		do
			io.error.put_string ("taskman_cli: " + a_message + "%N" + Usage)
			finish (2)
		end

	put_output (a_text: READABLE_STRING_32)
			-- Print `a_text' as UTF-8.
		local
			l_utf: UTF_CONVERTER
		do
			io.put_string (l_utf.string_32_to_utf_8_string_8 (a_text))
		end

	finish (a_code: INTEGER)
			-- Exit with `a_code' (0 needs no call).
		do
			if a_code /= 0 then
				(create {EXCEPTIONS}).die (a_code)
			end
		end

	Usage: STRING = "[
		usage:
		  taskman_cli snapshot [--top N] [--self] [--interval MS] [--save-frames N --file PATH]
		  taskman_cli capabilities
		  taskman_cli synthetic [--processes N] --save-frames N --file PATH
		  taskman_cli clockwatch [--seconds S]
		  taskman_cli trace [--ago SECONDS] [--top N] [--file PATH]

	]"

end
