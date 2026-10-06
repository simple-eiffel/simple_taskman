note
	description: "[
		Shared fixtures for simple_taskman tests: metrics, fully measured
		samples, snapshots, and `raises' for asserting that a contract fires.
		Assertions go through TEST_SET_BASE, never `check', because finalized
		`check' clauses are vacuous.
	]"
	author: "Larry Rix"

deferred class
	TM_TEST_SET

inherit
	TEST_SET_BASE

	TM_SHARED_METRICS
		undefine
			default_create
		end

feature {NONE} -- Fixtures

	metric (a_code: INTEGER): TM_METRIC
			-- Registered metric `a_code'.
		do
			Result := metrics.metric (a_code)
		end

	measured (a_code: INTEGER; a_value: REAL_64): TM_READING
			-- `a_value' measured for metric `a_code'.
		do
			create Result.make_measured (a_value, metric (a_code))
		end

	id (a_pid, a_creation: INTEGER_64): TM_PROCESS_ID
			-- Identity `a_pid' created at `a_creation'.
		do
			create Result.make (a_pid, a_creation)
		end

	sample (a_pid, a_creation: INTEGER_64; a_name: STRING_32; a_cpu_ticks, a_private, a_read: INTEGER_64): TM_PROCESS_SAMPLE
			-- Fully measured sample: `a_cpu_ticks' of user time, `a_private' bytes, `a_read' bytes read.
		do
			create Result.make (id (a_pid, a_creation), a_name, 4, 1, 8)
			Result.set_cpu (a_cpu_ticks, 0)
			Result.set_memory (a_private, a_private, 100)
			Result.set_io (a_read, 0)
		end

	idle_sample (a_idle_ticks: INTEGER_64): TM_PROCESS_SAMPLE
			-- The idle pseudo-process with `a_idle_ticks' of "CPU" time.
		do
			create Result.make (id (0, 0), {STRING_32} "System Idle Process", 0, 0, 32)
			Result.set_cpu (0, a_idle_ticks)
		end

	no_samples: ARRAY [TM_PROCESS_SAMPLE]
			-- An empty process list.
		do
			create Result.make_empty
		end

	sealed_readings: TM_READINGS
			-- Empty and sealed.
		do
			create Result.make
			Result.seal
		end

	snapshot (a_utc, a_monotonic: INTEGER_64; a_samples: ARRAY [TM_PROCESS_SAMPLE]): TM_SNAPSHOT
			-- Snapshot at the given times with `a_samples' and no system readings.
		do
			create Result.make (a_utc, a_monotonic, a_samples, sealed_readings)
		end

	Base_utc: INTEGER_64 = 133_700_000_000_000_000
			-- A plausible 2024 UTC tick value.

	One_second: INTEGER_64 = 10_000_000
			-- Ticks in one second.

	empty_frame (a_start: INTEGER_64; a_seconds: INTEGER): TM_FRAME
			-- Live frame of `a_seconds' with no activities.
		do
			create Result.make (a_start, a_start + a_seconds * One_second, a_seconds * One_second, 4, False,
				create {TM_READINGS}.make,
				create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

	frame_with_cpu (a_start: INTEGER_64; a_seconds: INTEGER; a_busy_pct: REAL_64): TM_FRAME
			-- Live frame of `a_seconds' whose cpu.busy_pct reads `a_busy_pct'.
		local
			l_readings: TM_READINGS
		do
			create l_readings.make
			l_readings.put ({TM_METRICS}.Cpu_busy_pct, {STRING_32} "", measured ({TM_METRICS}.Cpu_busy_pct, a_busy_pct))
			create Result.make (a_start, a_start + a_seconds * One_second, a_seconds * One_second, 4, False,
				l_readings,
				create {ARRAYED_LIST [TM_PROCESS_ACTIVITY]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_ID]}.make (0),
				create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
		end

	built (a_before, a_after: TM_SNAPSHOT; a_adjusted: BOOLEAN): TM_FRAME
			-- Frame the builder makes between two snapshots, spanning their UTC times.
		do
			Result := (create {TM_FRAME_BUILDER}).build (a_before, a_after, a_before.utc_ticks, a_after.utc_ticks,
				a_adjusted, 4, Void, 0)
		end

	scratch_path (a_name: STRING_32): STRING_32
			-- `a_name' in the user's temporary folder.
		local
			l_env: SIMPLE_ENV
		do
			create l_env
			if attached l_env.item ("TEMP") as al_temp then
				Result := al_temp + {STRING_32} "\" + a_name
			else
				Result := a_name.twin
			end
		end

	file_text (a_path: STRING_32): STRING_8
			-- Contents of `a_path', or empty.
		local
			l_file: PLAIN_TEXT_FILE
		do
			create Result.make_empty
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.open_read
				l_file.read_stream (l_file.count)
				Result := l_file.last_string.twin
				l_file.close
			end
		end

	write_file (a_path: STRING_32; a_text: STRING_8)
			-- Replace `a_path' with `a_text'.
		local
			l_file: PLAIN_TEXT_FILE
		do
			create l_file.make_with_name (a_path)
			l_file.open_write
			l_file.put_string (a_text)
			l_file.close
		end

	delete_file (a_path: STRING_32)
			-- Remove `a_path' if it exists.
		local
			l_file: PLAIN_TEXT_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.delete
			end
		end

feature {NONE} -- Contract checks

	raises (a_action: ROUTINE): BOOLEAN
			-- Does calling `a_action' raise (a contract violation, here)?
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_action.call (Void)
			end
		rescue
			l_retried := True
			Result := True
			retry
		end

end
