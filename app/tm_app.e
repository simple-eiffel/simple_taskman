note
	description: "[
		taskman: the window. Live by default; `--replay FILE' feeds frames from
		a TMF1 file instead (R-2); `--echo PNG' writes each rendered frame to a
		PNG (screenshots for the phase gates); `--soak SECONDS' records render times,
		dropped frames, sampling cost, and the tool's own CPU and memory to
		%LOCALAPPDATA%\simple_taskman\logs\taskman-gui.log, then closes itself
		(the spike O-2 measurement).

		The sampling worker (or the replayer) runs on its own processor and
		talks to the window only through the frame slot; every slot access
		here is one short call on the 250 ms tick. This program never prints:
		a GUI-subsystem process that writes to the console gets a console.
	]"
	author: "Larry Rix"

class
	TM_APP

inherit
	ARGUMENTS_32

	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make
			-- Build the window once, start the frame source, run until closed.
		local
			l_slot: separate TM_FRAME_SLOT
		do
			read_arguments
			create codec.make
			create format
			create clock.make
			create self.make
			create soak.make
			create theme.make_dark
			create window.make ("simple_taskman", 80, 60, 1280, 820, theme)
			create process_view.make (self.id)
			create core_view.make (machine_topology)
			create cpu_tile.make ("CPU")
			create memory_tile.make ("Memory commit")
			create disk_tile.make ("Busiest disk")
			create power_tile.make ("CPU package")
			create capability_view.make
			store_path := trace_path
			create status_bar.make
			status_bar.set_left ("Starting...")
			create l_slot.make
			slot := l_slot
			create scrub_view.make
			scrub_view.set_handlers (agent on_scrub, agent on_live)
			window.set_root (layout)
			window.set_on_tick (agent on_tick)
			if not echo_path.is_empty then
				window.set_frame_echo (echo_path)
			end
			start_source (l_slot)
			started := clock.monotonic_ticks
			window.run
			request_stop (l_slot)
			if attached reader as al_reader and then al_reader.is_open then
				al_reader.close
			end
			if soak_seconds > 0 then
				soak.finish (window.last_render_ms)
			end
		end

feature {NONE} -- Layout

	layout: SW_COLUMN
			-- Tiles across the top, processes beside cores, the status bar at the foot.
		local
			l_tiles: SW_ROW
			l_side: SW_COLUMN
			l_split: SW_SPLITTER
		do
			create l_tiles.make
			l_tiles := l_tiles.with_gap (12.0)
			l_tiles.put (cpu_tile.column)
			l_tiles.put (memory_tile.column)
			l_tiles.put (disk_tile.column)
			l_tiles.put (power_tile.column)
			create l_side.make
			l_side := l_side.with_gap (10.0)
			l_side.put (core_view.heatmap)
			l_side.put (capability_view.group)
			create l_split.make (process_view.grid, l_side)
			l_split.set_ratio (0.66)
			l_split.set_grow (1.0)
			create Result.make
			Result := Result.with_padding (10.0).with_gap (8.0)
			Result.put (l_tiles)
			Result.put (scrub_view.row)
			Result.put (l_split)
			Result.put (status_bar)
		end

feature {NONE} -- Frame source

	start_source (a_slot: separate TM_FRAME_SLOT)
			-- The live sampling worker, or the replayer when `--replay' was given.
		local
			l_worker: separate TM_SAMPLING_WORKER
			l_replayer: separate TM_FRAME_FILE_REPLAYER
		do
			if replay_path.is_empty then
				create l_worker.make (Interval_ms, store_path)
				attach_worker (l_worker, a_slot)
				launch_worker (l_worker)
				if soak_seconds > 0 then
					soak.start ("live", core_view.rows * core_view.columns)
				end
			else
				capability_view.show_replay (replay_path)
				create l_replayer.make (replay_path, Interval_ms)
				attach_replayer (l_replayer, a_slot)
				launch_replayer (l_replayer)
				if soak_seconds > 0 then
					soak.start ({STRING_32} "replay " + replay_path, core_view.rows * core_view.columns)
				end
			end
		end

feature {NONE} -- Tick

	on_tick
			-- Take the newest frame, if any, and show it; end a soak run on time.
		local
			l_text: detachable STRING_8
		do
			soak.note_render (window.last_render_ms)
			if window.last_render_ms > 0 then
				last_render := window.last_render_ms
			end
			tick_start := clock.monotonic_ticks
			if attached slot as al_slot then
				if not capabilities_shown then
					l_text := collect_capabilities (al_slot)
					if attached l_text as al_caps then
						codec.decode_capabilities (al_caps)
						if codec.has_capabilities then
							capability_view.show (codec.last_capabilities)
							process_source_kind := codec.last_capabilities.process_source_kind.to_string_32
							soak.note_source (process_source_kind)
						end
						capabilities_shown := True
					end
				end
				l_text := collect_frame (al_slot)
				if attached l_text as al_frame then
					codec.decode (al_frame)
					if codec.has_frame then
						soak.note_slot (slot_deposited (al_slot), slot_dropped (al_slot))
						show_frame (codec.last_frame, slot_dropped (al_slot))
					else
						window.log_line ({STRING_32} "frame not decoded: " + codec.last_error)
					end
				end
				if attached slot_failure (al_slot) as al_failure then
					status_bar.set_left ({STRING_32} "Sampling stopped: " + al_failure)
				end
			end
			ticks_since_refresh := ticks_since_refresh + 1
			if ticks_since_refresh >= Refresh_ticks then
				ticks_since_refresh := 0
				refresh_history
			end
			soak.note_tick (((clock.monotonic_ticks - tick_start) // 10_000).to_integer_32)
			if soak_seconds > 0 and then clock.monotonic_ticks - started >= soak_seconds.to_integer_64 * 10_000_000 then
				soak_seconds := 0
				if attached slot as al_slot then
					soak.note_slot (slot_deposited (al_slot), slot_dropped (al_slot))
				end
				soak.finish (window.last_render_ms)
				window.close
			end
		end

	show_frame (a_frame: TM_FRAME; a_dropped: INTEGER)
			-- Every view from `a_frame'.
		local
			l_left, l_right: STRING_32
		do
			last_live_frame := a_frame
			if not scrub_view.is_scrubbing then
				process_view.show (a_frame)
				core_view.show (a_frame.readings)
			end
			cpu_tile.show (reading (a_frame, Cpu_headline), metrics.metric (Cpu_headline), {STRING_32} "")
			memory_tile.show (reading (a_frame, {TM_METRICS}.Mem_commit_pct), metrics.metric ({TM_METRICS}.Mem_commit_pct), {STRING_32} "")
			show_busiest_disk (a_frame)
			power_tile.show (reading (a_frame, {TM_METRICS}.Cpu_package_watts), metrics.metric ({TM_METRICS}.Cpu_package_watts), {STRING_32} "")
			if replay_path.is_empty then
				l_left := {STRING_32} "Sampling every " + (Interval_ms // 1000).out.to_string_32 + {STRING_32} " s"
			else
				frames_replayed := frames_replayed + 1
				l_left := {STRING_32} "Replay, frame " + frames_replayed.out.to_string_32
			end
			if not process_source_kind.is_empty then
				l_left.append ({STRING_32} " | " + process_source_kind + {STRING_32} " table")
			end
			l_left.append ({STRING_32} " | " + a_frame.activity_count.out.to_string_32 + {STRING_32} " processes")
			if a_frame.is_discontinuity then
				l_left.append ({STRING_32} " | gap: the machine was not measured")
			end
			if a_frame.is_clock_adjusted then
				l_left.append ({STRING_32} " | wall clock changed")
			end
			if a_dropped > 0 then
				l_left.append ({STRING_32} " | display fell behind (" + a_dropped.out.to_string_32 + {STRING_32} ")")
			end
			if not process_view.notice.is_empty then
				l_left.append ({STRING_32} " | " + process_view.notice)
			end
			if not scrub_view.is_scrubbing then
				status_bar.set_left (l_left)
			end
			if replay_path.is_empty then
				l_right := {STRING_32} "taskman: "
					+ format.reading_text (reading (a_frame, {TM_METRICS}.Self_cpu_pct), metrics.metric ({TM_METRICS}.Self_cpu_pct))
					+ {STRING_32} " CPU, "
					+ format.reading_text (reading (a_frame, {TM_METRICS}.Self_private_bytes), metrics.metric ({TM_METRICS}.Self_private_bytes))
					+ {STRING_32} " | sample "
					+ format.reading_text (reading (a_frame, {TM_METRICS}.Sample_cost_ms), metrics.metric ({TM_METRICS}.Sample_cost_ms))
			else
				l_right := {STRING_32} "recorded frames: no live overhead"
			end
			l_right.append ({STRING_32} " | render " + last_render.out.to_string_32 + {STRING_32} " ms")
			status_bar.set_right (l_right)
			soak.note_frame (a_frame)
		end

	show_busiest_disk (a_frame: TM_FRAME)
			-- The physical disk with the highest busy reading, named.
		local
			l_best: detachable TM_READING
			l_name: STRING_32
			l_reading: TM_READING
		do
			create l_name.make_empty
			across a_frame.readings.instances ({TM_METRICS}.Disk_busy_pct) as ic loop
				l_reading := a_frame.readings.reading ({TM_METRICS}.Disk_busy_pct, ic)
				if l_reading.is_available and then (not attached l_best as al_best or else l_reading.value > al_best.value) then
					l_best := l_reading
					l_name := ic
				end
			end
			if attached l_best as al_best then
				disk_tile.show (al_best, metrics.metric ({TM_METRICS}.Disk_busy_pct), {STRING_32} "  disk " + l_name)
			else
				disk_tile.show (create {TM_READING}.make_unavailable, metrics.metric ({TM_METRICS}.Disk_busy_pct), {STRING_32} "")
			end
		end

	busiest_disk (a_frame: TM_FRAME): TM_READING
			-- The highest available disk busy reading of `a_frame'; unavailable when none.
		local
			l_reading: TM_READING
		do
			create Result.make_unavailable
			across a_frame.readings.instances ({TM_METRICS}.Disk_busy_pct) as ic loop
				l_reading := a_frame.readings.reading ({TM_METRICS}.Disk_busy_pct, ic)
				if l_reading.is_available and then (not Result.is_available or else l_reading.value > Result.value) then
					Result := l_reading
				end
			end
		end

feature {NONE} -- History (Phase 2 DVR)

	trace_path: STRING_32
			-- The per-user recording, unless `--no-record' or a replay; empty for none.
		local
			l_paths: TM_PATHS
		do
			create l_paths.make
			if replay_path.is_empty and not no_record and l_paths.has_root then
				Result := l_paths.trace_path
			else
				create Result.make_empty
			end
		end

	refresh_history
			-- Open the recording for reading once it exists, then follow its span.
		local
			l_reader: TM_SQLITE_TRACE_STORE
			l_note: STRING_32
		do
			if not store_path.is_empty then
				if reader = Void and then (create {RAW_FILE}.make_with_name (store_path)).exists then
					create l_reader.make_reader (store_path)
					if l_reader.is_open then
						reader := l_reader
					end
				elseif attached reader as al_reader and then al_reader.is_open then
					al_reader.refresh
				end
				if attached reader as al_reader and then al_reader.is_open and then al_reader.frame_count > 0 then
					l_note := {STRING_32} "recorded since " + scrub_view.clock_time (al_reader.earliest_ticks)
						+ {STRING_32} ", " + al_reader.frame_count.out.to_string_32 + {STRING_32} " frames, "
						+ format.bytes (al_reader.size_bytes)
					scrub_view.set_span (al_reader.earliest_ticks, al_reader.latest_ticks, l_note)
					if history_seconds > 0 and al_reader.latest_ticks > al_reader.earliest_ticks then
						scrub_view.scrub_to (al_reader.latest_ticks - history_seconds.to_integer_64 * 10_000_000)
						history_seconds := 0
					end
				end
			end
		end

	on_scrub (a_ticks: INTEGER_64)
			-- Show the recorded moment nearest `a_ticks' in every view.
		local
			l_before: TM_WINDOW
			l_note: STRING_32
		do
			if attached reader as al_reader and then al_reader.is_open and then attached al_reader.frame_nearest (a_ticks) as al_frame then
				process_view.show (al_frame)
				core_view.show (al_frame.readings)
				l_before := al_reader.window (al_frame.end_ticks - History_span, al_frame.end_ticks)
				cpu_tile.show_history (reading (al_frame, Cpu_headline), metrics.metric (Cpu_headline), {STRING_32} "",
					history_values (l_before, Cpu_headline))
				memory_tile.show_history (reading (al_frame, {TM_METRICS}.Mem_commit_pct), metrics.metric ({TM_METRICS}.Mem_commit_pct),
					{STRING_32} "", history_values (l_before, {TM_METRICS}.Mem_commit_pct))
				disk_tile.show_history (busiest_disk (al_frame), metrics.metric ({TM_METRICS}.Disk_busy_pct), {STRING_32} "",
					disk_history (l_before))
				power_tile.show_history (reading (al_frame, {TM_METRICS}.Cpu_package_watts), metrics.metric ({TM_METRICS}.Cpu_package_watts),
					{STRING_32} "", history_values (l_before, {TM_METRICS}.Cpu_package_watts))
				if al_frame.is_discontinuity then
					l_note := {STRING_32} "gap: the machine was not measured"
				else
					l_note := al_frame.activity_count.out.to_string_32 + {STRING_32} " recorded processes, "
						+ al_frame.omitted_processes.out.to_string_32 + {STRING_32} " quiet ones not recorded"
				end
				scrub_view.show_moment (al_frame.start_ticks, {STRING_32} "")
				status_bar.set_left ({STRING_32} "History " + scrub_view.clock_time (al_frame.start_ticks) + {STRING_32} " | " + l_note
					+ {STRING_32} " | press Live to return")
			elseif attached reader as al_reader and then not al_reader.last_error.is_empty then
				status_bar.set_left ({STRING_32} "History: " + al_reader.last_error)
			end
		end

	on_live
			-- Back to the live views.
		do
			cpu_tile.show_live
			memory_tile.show_live
			disk_tile.show_live
			power_tile.show_live
			if attached last_live_frame as al_frame then
				process_view.show (al_frame)
				core_view.show (al_frame.readings)
			end
			refresh_history
		end

	history_values (a_window: TM_WINDOW; a_code: INTEGER): ARRAYED_LIST [REAL_64]
			-- Available values of system-wide metric `a_code' across `a_window', oldest first.
		require
			system_wide: not metrics.metric (a_code).is_instanced
		local
			i: INTEGER
		do
			create Result.make (a_window.count)
			from i := 1 until i > a_window.count loop
				if reading (a_window.frame (i), a_code).is_available then
					Result.extend (reading (a_window.frame (i), a_code).value)
				end
				i := i + 1
			end
		end

	disk_history (a_window: TM_WINDOW): ARRAYED_LIST [REAL_64]
			-- Busiest-disk values across `a_window', oldest first.
		local
			i: INTEGER
		do
			create Result.make (a_window.count)
			from i := 1 until i > a_window.count loop
				if busiest_disk (a_window.frame (i)).is_available then
					Result.extend (busiest_disk (a_window.frame (i)).value)
				end
				i := i + 1
			end
		end

	History_span: INTEGER_64 = 600_000_000
			-- One minute of ticks: the line drawn before a recorded moment.

	Refresh_ticks: INTEGER = 20
			-- GUI ticks (250 ms) between looks at the recording.

	reader: detachable TM_SQLITE_TRACE_STORE
			-- The recording, opened for reading on this processor.

	scrub_view: TM_SCRUB_VIEW

	store_path: STRING_32
			-- The recording the worker writes; empty for none.

	last_live_frame: detachable TM_FRAME
			-- Newest live frame, shown again on Live.

	ticks_since_refresh: INTEGER


	reading (a_frame: TM_FRAME; a_code: INTEGER): TM_READING
			-- System-wide reading `a_code' of `a_frame'.
		require
			system_wide: not metrics.metric (a_code).is_instanced
		do
			Result := a_frame.readings.reading (a_code, {STRING_32} "")
		end

feature {NONE} -- Separate calls: one short call each

	attach_worker (a_worker: separate TM_SAMPLING_WORKER; a_slot: separate TM_FRAME_SLOT)
		do
			a_worker.attach_slot (a_slot)
		end

	launch_worker (a_worker: separate TM_SAMPLING_WORKER)
			-- Asynchronous: returns at once.
		do
			a_worker.run
		end

	attach_replayer (a_replayer: separate TM_FRAME_FILE_REPLAYER; a_slot: separate TM_FRAME_SLOT)
		do
			a_replayer.attach_slot (a_slot)
		end

	launch_replayer (a_replayer: separate TM_FRAME_FILE_REPLAYER)
		do
			a_replayer.run
		end

	collect_frame (a_slot: separate TM_FRAME_SLOT): detachable STRING_8
		do
			if a_slot.has_frame then
				create Result.make_from_separate (a_slot.frame_text)
				a_slot.clear
			end
		end

	collect_capabilities (a_slot: separate TM_FRAME_SLOT): detachable STRING_8
		do
			if a_slot.has_capabilities then
				create Result.make_from_separate (a_slot.capabilities_text)
			end
		end

	slot_failure (a_slot: separate TM_FRAME_SLOT): detachable STRING_32
		do
			if a_slot.has_failure then
				create Result.make_from_separate (a_slot.failure_text)
			end
		end

	slot_dropped (a_slot: separate TM_FRAME_SLOT): INTEGER
		do
			Result := a_slot.dropped
		end

	slot_deposited (a_slot: separate TM_FRAME_SLOT): INTEGER
		do
			Result := a_slot.deposited
		end

	request_stop (a_slot: separate TM_FRAME_SLOT)
		do
			a_slot.request_stop
		end

feature {NONE} -- Arguments

	read_arguments
			-- `--replay FILE' and `--soak SECONDS'.
		local
			i: INTEGER
		do
			create replay_path.make_empty
			create echo_path.make_empty
			from i := 1 until i > argument_count loop
				if argument (i).same_string ({STRING_32} "--replay") and i < argument_count then
					replay_path := argument (i + 1).twin
					i := i + 1
				elseif argument (i).same_string ({STRING_32} "--no-record") then
					no_record := True
				elseif argument (i).same_string ({STRING_32} "--history") and i < argument_count and then argument (i + 1).is_integer then
					history_seconds := argument (i + 1).to_integer.max (1)
				elseif argument (i).same_string ({STRING_32} "--echo") and i < argument_count then
					echo_path := argument (i + 1).twin
					i := i + 1
				elseif argument (i).same_string ({STRING_32} "--soak") and i < argument_count and then argument (i + 1).is_integer then
					soak_seconds := argument (i + 1).to_integer.max (1).min (86_400)
					i := i + 1
				end
				i := i + 1
			end
		end

	machine_topology: TM_CPU_TOPOLOGY
			-- This machine's processors; for a replay, the recording's processor count.
		local
			l_codec: TM_FRAME_CODEC
			l_file: PLAIN_TEXT_FILE
			l_count: INTEGER
			l_sizes, l_classes: ARRAY [INTEGER]
		do
			if not replay_path.is_empty then
				create l_file.make_with_name (replay_path)
				if l_file.exists and then l_file.is_readable then
					l_file.open_read
					l_file.read_stream (l_file.count.min (4_000_000))
					create l_codec.make
					across l_codec.frame_texts_in (l_file.last_string) as ic until l_count > 0 loop
						l_codec.decode (ic)
						if l_codec.has_frame then
							l_count := l_codec.last_frame.logical_processors.min (1_024)
						end
					end
					l_file.close
				end
			end
			if l_count > 0 then
				create l_sizes.make_filled ({TM_CPU_TOPOLOGY}.Maximum_per_group, 1, (l_count + 63) // 64)
				l_sizes [l_sizes.upper] := l_count - (l_sizes.count - 1) * 64
				create l_classes.make_filled (0, 1, l_count)
				create Result.make_from_groups (l_sizes, l_classes)
			else
				create Result.make
			end
		end

feature {NONE} -- Implementation

	theme: SW_THEME
	window: SW_WINDOW
	codec: TM_FRAME_CODEC
	format: TM_FORMAT
	clock: TM_SYSTEM_CLOCK
	self: TM_SELF_PROCESS
	soak: TM_SOAK_LOG
	process_view: TM_PROCESS_VIEW
	core_view: TM_CORE_VIEW
	cpu_tile, memory_tile, disk_tile, power_tile: TM_TREND_VIEW
	capability_view: TM_CAPABILITY_VIEW
	status_bar: SW_STATUS_BAR
	slot: detachable separate TM_FRAME_SLOT
	replay_path: STRING_32
	echo_path: STRING_32
	soak_seconds: INTEGER

	no_record: BOOLEAN
			-- `--no-record': sample without recording.

	history_seconds: INTEGER
			-- `--history N': open scrubbed back N seconds once the recording is readable; 0 for live.
	started: INTEGER_64
	tick_start: INTEGER_64
	last_render: INTEGER
			-- Last measured render, in ms.
	frames_replayed: INTEGER
	capabilities_shown: BOOLEAN
	process_source_kind: STRING_32
		attribute
			create Result.make_empty
		end

	Interval_ms: INTEGER = 1000
			-- Sampling interval.

	Cpu_headline: INTEGER
			-- Metric of the CPU tile: "% Processor Utility", the counter Task
			-- Manager shows (Larry, 2026-10-06). It is scaled by clock frequency,
			-- so under turbo it can read above 100%, where Task Manager stops at 100.
		once
			Result := {TM_METRICS}.Cpu_utility_pct
		end

end
