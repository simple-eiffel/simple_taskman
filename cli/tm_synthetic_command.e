note
	description: "[
		`taskman_cli synthetic': write a replay file of frames made from
		scripted sources, for shapes this machine cannot produce (R-4): many
		processes with varied load and churn, 32 cores, a disk, package
		power. The frames go through the real sampler and frame builder, so
		they are what the window would see from such a machine.
	]"
	author: "Larry Rix"

class
	TM_SYNTHETIC_COMMAND

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make (a_processes, a_frames: INTEGER; a_path: READABLE_STRING_32)
			-- `a_frames' frames of `a_processes' processes, to `a_path'.
		require
			processes_sane: a_processes >= 1 and a_processes <= 50_000
			frames_sane: a_frames >= 1 and a_frames <= 3_600
			path_given: not a_path.is_empty
		do
			processes := a_processes
			frames := a_frames
			create path.make_from_string (a_path)
			create output.make_empty
		ensure
			kept: processes = a_processes and frames = a_frames and path.same_string (a_path)
		end

feature -- Access

	processes, frames: INTEGER
	path: STRING_32
	output: STRING_32
	exit_code: INTEGER
	frames_written: INTEGER

feature -- Execution

	execute
			-- Script, sample, encode, write.
		local
			l_processes: TM_SCRIPTED_PROCESS_SOURCE
			l_system: TM_SCRIPTED_SYSTEM_SOURCE
			l_clock: TM_MANUAL_CLOCK
			l_tm: SIMPLE_TASKMAN
			l_codec: TM_FRAME_CODEC
			l_text: STRING_8
			l_file: RAW_FILE
			t, c: INTEGER
		do
			create l_processes.make
			create l_system.make (Cores)
			across <<{TM_METRICS}.Cpu_busy_pct, {TM_METRICS}.Cpu_core_busy_pct, {TM_METRICS}.Mem_commit_pct,
					{TM_METRICS}.Cpu_package_watts, {TM_METRICS}.Disk_busy_pct>> as ic loop
				l_system.declare_support (ic, {TM_READING_STATUS}.Available, {STRING_32} "")
			end
			from t := 0 until t > frames loop
				l_processes.add_round (round (t))
				l_system.script_reading ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, 40.0 + (t \\ 30)))
				l_system.script_reading ({TM_METRICS}.Mem_commit_pct, {STRING_32} "", measured ({TM_METRICS}.Mem_commit_pct, 60.0 + (t \\ 20)))
				l_system.script_reading ({TM_METRICS}.Cpu_package_watts, {STRING_32} "", measured ({TM_METRICS}.Cpu_package_watts, 80.0 + (t \\ 40)))
				l_system.script_reading ({TM_METRICS}.Disk_busy_pct, {STRING_32} "0 C:", measured ({TM_METRICS}.Disk_busy_pct, (t * 7) \\ 100))
				from c := 0 until c = Cores loop
					l_system.script_reading ({TM_METRICS}.Cpu_core_busy_pct, c.out.to_string_32,
						measured ({TM_METRICS}.Cpu_core_busy_pct, ((c * 13 + t * 5) \\ 100).to_double))
					c := c + 1
				end
				l_system.end_round
				t := t + 1
			end
			create l_clock.make (Base_utc, 0)
			create l_tm.make_with_sources (l_processes, l_system, l_clock)
			create l_codec.make
			create l_text.make (frames * processes * 120)
			l_tm.sample
			from t := 1 until t > frames loop
				l_clock.advance (10_000_000)
				l_tm.sample
				l_text.append (l_codec.encode (l_tm.last_frame))
				frames_written := frames_written + 1
				t := t + 1
			end
			l_tm.close
			create l_file.make_with_name (path)
			l_file.open_write
			l_file.put_string (l_text)
			l_file.close
			output := {STRING_32} "wrote " + frames_written.out.to_string_32 + {STRING_32} " frames of "
				+ processes.out.to_string_32 + {STRING_32} " processes (" + (l_text.count // 1024).out.to_string_32
				+ {STRING_32} " KB) to " + path + {STRING_32} "%N"
			exit_code := 0
		ensure
			all_written: frames_written = frames
		end

feature {NONE} -- Implementation

	Cores: INTEGER = 32
	Base_utc: INTEGER_64 = 133_700_000_000_000_000

	round (a_tick: INTEGER): ARRAYED_LIST [TM_PROCESS_SAMPLE]
			-- The processes at tick `a_tick': one in fifty is replaced every ten ticks
			-- (churn); CPU grows at a per-process rate, so a few are busy and most idle.
		local
			p, l_pid, l_generation: INTEGER
			l_sample: TM_PROCESS_SAMPLE
		do
			create Result.make (processes)
			from p := 1 until p > processes loop
				if p \\ 50 = 0 then
					l_generation := a_tick // 10
				else
					l_generation := 0
				end
				l_pid := p * 4 + l_generation * 1_000_000
				create l_sample.make (create {TM_PROCESS_ID}.make (l_pid, Base_utc - p * 1000 + l_generation),
					name_of (p), 4, 1, 1 + p \\ 40)
				l_sample.set_cpu ((a_tick * rate_of (p)).to_integer_64 * 1_000, 0)
				l_sample.set_memory (((p \\ 300) + 1) * 1_048_576, ((p \\ 500) + 1) * 1_048_576, 50 + p \\ 400)
				l_sample.set_io (a_tick.to_integer_64 * (p \\ 17) * 4_096, a_tick.to_integer_64 * (p \\ 11) * 4_096)
				Result.extend (l_sample)
				p := p + 1
			end
		end

	rate_of (a_process: INTEGER): INTEGER
			-- Thousands of CPU ticks per second: a long tail, a few heavy processes.
		do
			if a_process \\ 997 = 0 then
				Result := 8_000
			elseif a_process \\ 101 = 0 then
				Result := 1_500
			else
				Result := a_process \\ 7
			end
		end

	name_of (a_process: INTEGER): STRING_32
		do
			Result := {STRING_32} "synthetic-" + (a_process \\ 260).out.to_string_32 + {STRING_32} ".exe"
		end

	measured (a_code: INTEGER; a_value: REAL_64): TM_READING
		do
			create Result.make_measured (a_value, metrics.metric (a_code))
		end

end
