note
	description: "[
		`taskman_cli snapshot': sample the machine twice, `interval_ms' apart,
		and describe the system readings and the busiest processes. With a
		save count it keeps sampling and writes that many frames, encoded as
		TMF1, to a file the window can replay (R-2). Builds text only; the
		caller prints it, so tests can drive the command directly.
	]"
	author: "Larry Rix"

class
	TM_SNAPSHOT_COMMAND

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make (a_top, a_interval_ms: INTEGER; a_show_self: BOOLEAN)
			-- Show the `a_top' busiest processes over `a_interval_ms'; `a_show_self' adds this tool's cost.
		require
			top_sane: a_top >= 1 and a_top <= Maximum_top
			interval_sane: a_interval_ms >= 250 and a_interval_ms <= 60_000
		do
			top := a_top
			interval_ms := a_interval_ms
			show_self := a_show_self
			create output.make_empty
			create save_path.make_empty
		ensure
			kept: top = a_top and interval_ms = a_interval_ms and show_self = a_show_self
			not_saving: save_count = 0
			not_run: not has_run
		end

feature -- Access

	top: INTEGER
	interval_ms: INTEGER
	show_self: BOOLEAN
	save_count: INTEGER
			-- Frames to write to `save_path'; 0 for none.
	save_path: STRING_32

	output: STRING_32
			-- What `execute' produced, ready to print.

	exit_code: INTEGER
			-- 0 success, 3 when the machine could not be read.

	frames_saved: INTEGER
			-- Frames written by the last `execute'.

feature -- Status report

	has_run: BOOLEAN
			-- Has `execute' run?

feature -- Element change

	set_save (a_count: INTEGER; a_path: READABLE_STRING_32)
			-- Also write `a_count' frames to `a_path' for replay.
		require
			count_sane: a_count >= 1 and a_count <= 86_400
			path_given: not a_path.is_empty
		do
			save_count := a_count
			create save_path.make_from_string (a_path)
		ensure
			kept: save_count = a_count and save_path.same_string (a_path)
		end

feature -- Execution

	execute
			-- Sample, describe, and save.
		local
			l_tm: SIMPLE_TASKMAN
			l_clock: TM_SYSTEM_CLOCK
			l_codec: TM_FRAME_CODEC
			l_frames: STRING_8
			i: INTEGER
		do
			create output.make (4096)
			create l_clock.make
			create l_codec.make
			create l_frames.make (0)
			frames_saved := 0
			create l_tm.make
			l_tm.set_nominal_interval (interval_ms).do_nothing
			l_tm.sample
			from
				i := 0
			until
				i >= save_count.max (1)
			loop
				l_clock.sleep_ms (interval_ms)
				l_tm.sample
				if l_tm.has_frame and save_count > 0 then
					l_frames.append (l_codec.encode (l_tm.last_frame))
					frames_saved := frames_saved + 1
				end
				i := i + 1
			end
			if l_tm.has_frame then
				describe (l_tm)
				if save_count > 0 then
					write_frames (l_frames)
				end
				exit_code := 0
			else
				output.append ({STRING_32} "could not read the machine%N")
				exit_code := 3
			end
			l_tm.close
			has_run := True
		ensure
			ran: has_run
			said_something: not output.is_empty
			known_exit: exit_code = 0 or exit_code = 3
			saved_when_asked: (exit_code = 0 and save_count > 0) implies frames_saved = save_count
		end

feature -- Constants

	Maximum_top: INTEGER = 500

feature {NONE} -- Implementation

	describe (a_tm: SIMPLE_TASKMAN)
			-- Append the readings, the busiest processes, and optionally this tool's cost.
		require
			has_frame: a_tm.has_frame
		local
			l_format: TM_FORMAT
			l_frame: TM_FRAME
			l_reading: TM_READING
		do
			create l_format
			l_frame := a_tm.last_frame
			output.append ({STRING_32} "process table: " + a_tm.process_source_kind.to_string_32 + {STRING_32} "%N")
			across <<{TM_METRICS}.Cpu_busy_pct, {TM_METRICS}.Cpu_utility_pct, {TM_METRICS}.Cpu_package_watts,
					{TM_METRICS}.Mem_used_bytes, {TM_METRICS}.Mem_available_bytes, {TM_METRICS}.Mem_commit_pct,
					{TM_METRICS}.Mem_hard_faults_per_s>> as ic loop
				l_reading := l_frame.readings.reading (ic, {STRING_32} "")
				output.append (padded (metrics.metric (ic).name.to_string_32, 24) + l_format.reading_text (l_reading, metrics.metric (ic)) + {STRING_32} "%N")
			end
			across l_frame.readings.instances ({TM_METRICS}.Disk_busy_pct) as ic loop
				output.append (padded ({STRING_32} "disk.busy_pct " + ic, 24)
					+ l_format.reading_text (l_frame.readings.reading ({TM_METRICS}.Disk_busy_pct, ic), metrics.metric ({TM_METRICS}.Disk_busy_pct))
					+ {STRING_32} "%N")
			end
			output.append ({STRING_32} "%N" + padded ({STRING_32} "PID", 8) + padded ({STRING_32} "CPU", 9)
				+ padded ({STRING_32} "PRIVATE", 11) + padded ({STRING_32} "READ/S", 12) + padded ({STRING_32} "WRITE/S", 12)
				+ {STRING_32} "NAME%N")
			across l_frame.top_by ({TM_RESOURCE}.Cpu, top) as ic loop
				output.append (process_line (ic, l_format))
			end
			if show_self then
				output.append ({STRING_32} "%Nthis tool: "
					+ l_format.reading_text (l_frame.readings.reading ({TM_METRICS}.Self_cpu_pct, {STRING_32} ""), metrics.metric ({TM_METRICS}.Self_cpu_pct))
					+ {STRING_32} " of one processor, "
					+ l_format.reading_text (l_frame.readings.reading ({TM_METRICS}.Self_private_bytes, {STRING_32} ""), metrics.metric ({TM_METRICS}.Self_private_bytes))
					+ {STRING_32} " private%N")
			end
		end

	process_line (a_activity: TM_PROCESS_ACTIVITY; a_format: TM_FORMAT): STRING_32
			-- One table row; a group that is not available shows its status word.
		do
			Result := padded (a_activity.id.pid.out.to_string_32, 8)
			if a_activity.cpu_status = {TM_READING_STATUS}.Available then
				Result.append (padded (a_format.percent (a_activity.cpu_percent), 9))
			else
				Result.append (padded (a_format.status_word (a_activity.cpu_status), 9))
			end
			if a_activity.memory_status = {TM_READING_STATUS}.Available then
				Result.append (padded (a_format.bytes (a_activity.private_bytes), 11))
			else
				Result.append (padded (a_format.status_word (a_activity.memory_status), 11))
			end
			if a_activity.io_status = {TM_READING_STATUS}.Available then
				Result.append (padded (a_format.bytes_per_second (a_activity.io_read_bps), 12))
				Result.append (padded (a_format.bytes_per_second (a_activity.io_write_bps), 12))
			else
				Result.append (padded (a_format.status_word (a_activity.io_status), 12))
				Result.append (padded (a_format.status_word (a_activity.io_status), 12))
			end
			Result.append (a_activity.name)
			Result.append ({STRING_32} "%N")
		end

	padded (a_text: READABLE_STRING_32; a_width: INTEGER): STRING_32
			-- `a_text' followed by spaces to `a_width', and at least one space.
		do
			create Result.make_from_string (a_text)
			from
			until
				Result.count >= a_width - 1
			loop
				Result.append_character (' ')
			end
			Result.append_character (' ')
		end

	write_frames (a_text: STRING_8)
			-- Replace `save_path' with `a_text'.
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (save_path)
			l_file.open_write
			l_file.put_string (a_text)
			l_file.close
			output.append ({STRING_32} "%Nsaved " + frames_saved.out.to_string_32 + {STRING_32} " frames to " + save_path + {STRING_32} "%N")
		end

invariant
	top_sane: top >= 1 and top <= Maximum_top
	interval_sane: interval_ms >= 250 and interval_ms <= 60_000
	saving_has_path: save_count > 0 implies not save_path.is_empty

end
