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
			l_details_scroll, l_machine_scroll: SW_SCROLL_AREA
		do
			read_arguments
			create settings.make
			load_settings
			create codec.make
			create format
			create clock.make
			create self.make
			create soak.make
			create theme.make_dark
			create window.make ("simple_taskman 0.2.0", 80, 60, 1280, 820, theme)
			create process_view.make (self.id)
			create core_view.make (machine_topology)
			create cpu_tile.make ("CPU")
			create memory_tile.make ("Memory commit")
			create disk_tile.make ("Busiest disk")
			create power_tile.make ("CPU package")
			create capability_view.make
			create inspector.make
			create control.make (inspector)
			create windows.make
			create details_view.make
			create actions_bar.make
			create machine.make
			create performance_view.make (machine, Main_page_height)
			create settings_view.make (settings, <<{STRING_32} "Processes", {STRING_32} "Performance", {STRING_32} "Services", {STRING_32} "Startup", {STRING_32} "Users">>)
			create services_view.make (Main_page_height)
			create startup_view.make (Main_page_height)
			create users_view.make (Main_page_height)
			create recorder_control
			create elevation
			create diagnostician.make
			create trend_book.make
			create live_frames.make (Verdict_frames)
			create verdict_label.make ("Watching: the first verdict comes after ten seconds of frames.", {SW_PAINTER}.Role_ui, 15.0, True)
			create ahead_label.make_ui ("Look ahead: watching")
			create main_tabs.make
			create side_tabs.make
			create l_details_scroll.make (Side_page_height)
			l_details_scroll.set_child (details_view.group)
			create l_machine_scroll.make (Side_page_height)
			l_machine_scroll.set_child (capability_view.group)
			side_tabs.add_page ("Selected process", l_details_scroll)
			side_tabs.add_page ("This machine", l_machine_scroll)
			side_tabs.select_tab (2)
			store_path := trace_path
			create status_bar.make
			status_bar.set_left ("Starting...")
			create l_slot.make
			slot := l_slot
			create scrub_view.make
			scrub_view.set_handlers (agent on_scrub, agent on_live)
			settings_view.set_on_change (agent on_settings_changed)
			services_view.set_reporter (agent report_action)
			startup_view.set_reporter (agent report_action)
			users_view.set_reporter (agent report_action)
			settings_view.set_admin_actions (agent on_restart_elevated, agent on_ctrl_shift_esc)
			settings_view.set_admin_state (elevation.is_elevated, elevation.is_ctrl_shift_esc_ours)
			actions_bar.set_actions (agent on_action)
			process_view.set_status_source (agent status_text)
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
			l_side, l_main: SW_COLUMN
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
			l_side.put (side_tabs)
			create l_main.make
			l_main := l_main.with_gap (6.0)
			l_main.put (actions_bar.toolbar)
			l_main.put (process_view.grid)
			create l_split.make (l_main, l_side)
			l_split.set_ratio (0.66)
			l_split.set_grow (1.0)
			main_tabs.add_page ("Processes", l_split)
			main_tabs.add_page ("Performance", performance_view.page)
			main_tabs.add_page ("Services", services_view.column)
			main_tabs.add_page ("Startup", startup_view.column)
			main_tabs.add_page ("Users", users_view.column)
			main_tabs.add_page ("Settings", settings_view.column)
			main_tabs.set_grow (1.0)
			if attached start_page as al_page then
				open_page (al_page)
			else
				open_page (settings.start_page)
			end
			create Result.make
			Result := Result.with_padding (10.0).with_gap (8.0)
			Result.put (l_tiles)
			Result.put (verdict_label)
			Result.put (ahead_label)
			Result.put (scrub_view.row)
			Result.put (main_tabs)
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
				create l_worker.make (settings.update_ms, store_path)
				if tier0_seconds > 0 then
					set_worker_tier0 (l_worker, tier0_seconds)
				end
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
			l_frame_ms, l_selection_ms, l_history_ms, l_mark, l_total_ms: INTEGER_64
		do
			if not top_applied then
				top_applied := True
				if settings.is_always_on_top then
					c_set_topmost (True).do_nothing
				end
			end
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
					if codec.has_frame and settings.is_paused then
						status_bar.set_left ({STRING_32} "Paused: the display is frozen; recording goes on. Settings, Update speed resumes.")
					elseif codec.has_frame then
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
			l_mark := clock.monotonic_ticks
			l_frame_ms := (l_mark - tick_start) // 10_000
			actions_bar.disarm_if_late
			if replay_path.is_empty then
				follow_selection
			end
			l_selection_ms := (clock.monotonic_ticks - l_mark) // 10_000
			l_mark := clock.monotonic_ticks
			follow_pages
			ticks_since_refresh := ticks_since_refresh + 1
			if ticks_since_refresh >= Refresh_ticks then
				ticks_since_refresh := 0
				refresh_history
			end
			l_history_ms := (clock.monotonic_ticks - l_mark) // 10_000
			l_total_ms := (clock.monotonic_ticks - tick_start) // 10_000
			if l_total_ms >= Stall_ms then
				soak.note_stall (l_total_ms.to_integer_32, {STRING_32} "frame " + l_frame_ms.out.to_string_32
					+ {STRING_32} " ms, windows and selection " + l_selection_ms.out.to_string_32
					+ {STRING_32} " ms, history " + l_history_ms.out.to_string_32 + {STRING_32} " ms")
			end
			soak.note_tick (l_total_ms.to_integer_32)
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
			if replay_path.is_empty then
				performance_view.show (a_frame)
			end
			follow_verdict (a_frame)
			if not scrub_view.is_scrubbing then
				process_view.show (a_frame)
				core_view.show (a_frame.readings)
				if select_pid > 0 and then a_frame.activities.there_exists (agent (a: TM_PROCESS_ACTIVITY): BOOLEAN do Result := a.id.pid = select_pid end) then
					process_view.select_pid (select_pid)
					select_pid := 0
				end
			end
			cpu_tile.show (reading (a_frame, Cpu_headline), metrics.metric (Cpu_headline), {STRING_32} "")
			memory_tile.show (reading (a_frame, {TM_METRICS}.Mem_commit_pct), metrics.metric ({TM_METRICS}.Mem_commit_pct), {STRING_32} "")
			show_busiest_disk (a_frame)
			power_tile.show (reading (a_frame, {TM_METRICS}.Cpu_package_watts), metrics.metric ({TM_METRICS}.Cpu_package_watts), {STRING_32} "")
			if replay_path.is_empty then
				l_left := {STRING_32} "Sampling every " + speed_text
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
			if not scrub_view.is_scrubbing and clock.monotonic_ticks > action_message_until then
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
			if replay_path.is_empty and not no_record and settings.records and l_paths.has_root then
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
				show_verdict (diagnostician.diagnose (al_reader.window (al_frame.end_ticks - Verdict_window_ticks, al_frame.end_ticks)),
					{STRING_32} "At " + scrub_view.clock_time (al_frame.start_ticks) + {STRING_32} ": ")
				status_bar.set_left ({STRING_32} "History " + scrub_view.clock_time (al_frame.start_ticks) + {STRING_32} " | " + l_note
					+ {STRING_32} " | press Live to return")
			elseif attached reader as al_reader and then not al_reader.last_error.is_empty then
				status_bar.set_left ({STRING_32} "History: " + al_reader.last_error)
			end
		end

	on_live
			-- Back to the live views.
		do
			shown_selection := Void
			show_verdict (diagnostician.diagnose (live_window), {STRING_32} "")
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


feature {NONE} -- Verdict and look-ahead (Phases 4 and 5)

	diagnostician: TM_DIAGNOSTICIAN
	trend_book: TM_TREND_BOOK
	live_frames: ARRAYED_LIST [TM_FRAME]
	verdict_label: SW_LABEL
	ahead_label: SW_LABEL
	frames_since_ahead: INTEGER
	last_flash: INTEGER_64

	Verdict_frames: INTEGER = 30
			-- Live frames the verdict looks at.

	Verdict_window_ticks: INTEGER_64 = 300_000_000
			-- Thirty seconds of a recording, for a verdict at a past moment.

	follow_verdict (a_frame: TM_FRAME)
			-- Diagnose the newest live frames and refresh the look-ahead line.
		do
			if a_frame.is_discontinuity then
				live_frames.wipe_out
			end
			live_frames.extend (a_frame)
			if live_frames.count > Verdict_frames then
				live_frames.start
				live_frames.remove
			end
			if not scrub_view.is_scrubbing then
				show_verdict (diagnostician.diagnose (live_window), {STRING_32} "")
			end
			trend_book.add (a_frame)
			frames_since_ahead := frames_since_ahead + 1
			if frames_since_ahead >= 5 then
				frames_since_ahead := 0
				ahead_label.set_text (trend_book.summary)
				if trend_book.is_alarming then
					ahead_label.set_color (theme.danger)
					if clock.monotonic_ticks - last_flash > 3_000_000_000 then
						last_flash := clock.monotonic_ticks
						c_flash.do_nothing
					end
				else
					ahead_label.set_color (theme.ink_muted)
				end
			end
		end

	live_window: TM_WINDOW
			-- The newest live frames as a window.
		do
			create Result.make
			across live_frames as ic loop
				if Result.is_empty or else ic.start_ticks >= Result.end_ticks then
					Result.extend (ic)
				end
			end
		end

	show_verdict (a_verdict: TM_VERDICT; a_prefix: READABLE_STRING_32)
			-- Put `a_verdict' on the banner, coloured by what it found.
		do
			verdict_label.set_text (a_prefix + a_verdict.full_text)
			if a_verdict.is_found then
				verdict_label.set_color (theme.danger)
			elseif a_verdict.kind = {TM_VERDICT}.None then
				verdict_label.set_color (theme.success)
			else
				verdict_label.set_color (theme.ink_muted)
			end
		end

	c_flash: BOOLEAN
			-- Flash this window's taskbar button until it is brought forward.
		external
			"C inline use <windows.h>"
		alias
			"[
				HWND l_window = GetTopWindow (NULL);
				DWORD l_pid = 0;
				while (l_window != NULL) {
					GetWindowThreadProcessId (l_window, &l_pid);
					if (l_pid == GetCurrentProcessId () && IsWindowVisible (l_window) && GetWindow (l_window, GW_OWNER) == NULL) {
						FLASHWINFO l_info;
						ZeroMemory (&l_info, sizeof (l_info));
						l_info.cbSize = sizeof (l_info);
						l_info.hwnd = l_window;
						l_info.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
						return (EIF_BOOLEAN) FlashWindowEx (&l_info);
					}
					l_window = GetWindow (l_window, GW_HWNDNEXT);
				}
				return EIF_FALSE;
			]"
		end

feature {NONE} -- Pages refreshed while showing (Phase 3)

	services_view: TM_SERVICES_VIEW

	page_ticks: INTEGER
			-- GUI ticks since the showing page was last refreshed.

	shown_page: INTEGER
			-- Main tab refreshed last.

	Page_refresh_ticks: INTEGER = 20
			-- Five seconds at the 250 ms tick.

	follow_pages
			-- Refresh the showing page on arrival and every five seconds.
		do
			page_ticks := page_ticks + 1
			if main_tabs.selected_index /= shown_page or page_ticks >= Page_refresh_ticks then
				if main_tabs.selected_index >= 1 and main_tabs.selected_index <= main_tabs.labels.count then
					if main_tabs.labels [main_tabs.selected_index].same_string ({STRING_32} "Services") then
						services_view.refresh
					elseif main_tabs.labels [main_tabs.selected_index].same_string ({STRING_32} "Users") then
						users_view.refresh (last_live_frame)
					elseif main_tabs.labels [main_tabs.selected_index].same_string ({STRING_32} "Startup")
							and main_tabs.selected_index /= shown_page then
						startup_view.refresh (boot_window)
					end
				end
				shown_page := main_tabs.selected_index
				page_ticks := 0
			end
		end

	startup_view: TM_STARTUP_VIEW
	users_view: TM_USERS_VIEW
	recorder_control: TM_RECORDER_CONTROL

	boot_window: detachable TM_WINDOW
			-- The recorded frames of the three minutes after Windows started; Void when nothing is readable.
		local
			l_boot: INTEGER_64
		do
			if attached reader as al_reader and then al_reader.is_open and then not al_reader.is_empty then
				l_boot := clock.utc_ticks - machine.uptime_seconds * {TM_CLOCK}.Ticks_per_second
				if l_boot > 0 and l_boot + Boot_window_ticks > l_boot then
					Result := al_reader.window (l_boot, l_boot + Boot_window_ticks)
				end
			end
		end

	Boot_window_ticks: INTEGER_64 = 1_800_000_000
			-- Three minutes.

	apply_logon_recording
			-- Make the logon registration and the running recorder match the setting.
		local
			l_result: TM_ACTION_RESULT
		do
			if settings.records_at_logon then
				if not recorder_control.is_installed then
					settings_view.set_note ({STRING_32} "The background recorder (taskman_recorder.exe) is not installed beside taskman.exe.")
				else
					if not recorder_control.is_registered then
						l_result := recorder_control.register
						report_action (l_result.summary)
					end
					if not recorder_control.is_running then
						l_result := recorder_control.start
						report_action (l_result.summary)
					end
				end
			elseif recorder_control.is_registered or recorder_control.is_running then
				l_result := recorder_control.unregister
				recorder_control.request_stop
				report_action (l_result.summary + {STRING_32} "; the background recorder was asked to stop")
			end
		end

	elevation: TM_ELEVATION

	on_restart_elevated
			-- Start again with administrator rights, then close this window.
		local
			l_result: TM_ACTION_RESULT
		do
			if elevation.is_elevated then
				report_action ({STRING_32} "Already running as administrator")
			else
				l_result := elevation.restart_elevated ({STRING_32} "--page " + main_tabs.labels [main_tabs.selected_index.max (1)].as_lower)
				report_action (l_result.summary)
				if l_result.succeeded then
					window.close
				end
			end
		end

	on_ctrl_shift_esc (a_on: BOOLEAN)
			-- Point Ctrl+Shift+Esc at this program, or back at Task Manager.
		local
			l_result: TM_ACTION_RESULT
		do
			l_result := elevation.set_ctrl_shift_esc (a_on, elevation.program_path)
			report_action (l_result.summary)
			settings_view.set_note (l_result.summary)
			settings_view.set_admin_state (elevation.is_elevated, elevation.is_ctrl_shift_esc_ours)
		end

	report_action (a_text: READABLE_STRING_32)
			-- Show an action's outcome on the status bar for a while.
		do
			status_bar.set_left (a_text)
			action_message_until := clock.monotonic_ticks + 60_000_000
		end

feature {NONE} -- Settings (Phase 3)

	settings: TM_SETTINGS
	settings_view: TM_SETTINGS_VIEW
	top_applied: BOOLEAN

	load_settings
			-- Read the owner's settings, when there is a profile folder.
		local
			l_paths: TM_PATHS
		do
			create l_paths.make
			if l_paths.has_root then
				settings.load (l_paths.settings_path)
			end
		end

	on_settings_changed
			-- Apply and save a change made on the Settings page.
		local
			l_paths: TM_PATHS
		do
			create l_paths.make
			if l_paths.has_root then
				settings.save (l_paths.settings_path)
			end
			if attached slot as al_slot and not settings.is_paused then
				request_interval (al_slot, settings.update_ms)
			end
			c_set_topmost (settings.is_always_on_top).do_nothing
			apply_logon_recording
			if settings.last_error.is_empty then
				settings_view.set_note ({STRING_32} "Saved. " + speed_text)
			else
				settings_view.set_note (settings.last_error)
			end
		end

	speed_text: STRING_32
		do
			if settings.is_paused then
				Result := {STRING_32} "paused"
			elseif settings.update_ms < 1000 then
				Result := {STRING_32} "0.5 s"
			else
				Result := (settings.update_ms // 1000).out.to_string_32 + {STRING_32} " s"
			end
		end

	open_page (a_page: READABLE_STRING_32)
			-- Select the main tab labelled `a_page' (any case).
		do
			across main_tabs.labels as ic loop
				if ic.as_lower.same_string (a_page.as_lower) then
					main_tabs.select_tab (@ic.cursor_index)
				end
			end
		end

	request_interval (a_slot: separate TM_FRAME_SLOT; a_ms: INTEGER)
		require
			sane: a_ms >= 250 and a_ms <= 60_000
		do
			a_slot.request_interval (a_ms)
		end

	c_set_topmost (a_on: BOOLEAN): BOOLEAN
			-- Put this process's visible top-level window on top of others, or not.
		external
			"C inline use <windows.h>"
		alias
			"[
				HWND l_window = GetTopWindow (NULL);
				DWORD l_pid = 0;
				while (l_window != NULL) {
					GetWindowThreadProcessId (l_window, &l_pid);
					if (l_pid == GetCurrentProcessId () && IsWindowVisible (l_window) && GetWindow (l_window, GW_OWNER) == NULL) {
						return (EIF_BOOLEAN) (SetWindowPos (l_window, $a_on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
							SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE) != 0);
					}
					l_window = GetWindow (l_window, GW_HWNDNEXT);
				}
				return EIF_FALSE;
			]"
		end

feature {NONE} -- Process actions (Phase 3)

	inspector: TM_PROCESS_INSPECTOR
	control: TM_PROCESS_CONTROL
	windows: TM_WINDOW_INDEX
	details_view: TM_DETAILS_VIEW
	actions_bar: TM_ACTIONS_BAR
	side_tabs: SW_TABS

	main_tabs: SW_TABS
			-- Processes, Performance, and the other Task Manager pages.

	machine: TM_MACHINE_INFO
			-- Facts about this machine (Performance tab).

	performance_view: TM_PERFORMANCE_VIEW

	Main_page_height: REAL_64 = 455.0
			-- Height of a full-width page under the main tabs in an 820-pixel window.

	shown_selection: detachable TM_PROCESS_ID
			-- Identity the details panel shows.

	shown_details: detachable TM_PROCESS_DETAILS
			-- What the panel shows.

	receipt: detachable TUPLE [id: TM_PROCESS_ID; outcome: TM_ACTION_RESULT; efficiency_on: BOOLEAN]
			-- The last priority or efficiency change, for Undo.

	ticks_since_windows: INTEGER

	Side_page_height: REAL_64 = 185.0
			-- Viewport of each side tab: the heatmap, the tabs, and the status bar fit an 820-pixel window.

	Windows_ticks: INTEGER = 8
			-- GUI ticks (250 ms) between window-list and details refreshes.

	follow_selection
			-- Keep the window list, the details panel, and the tools in step with the selection.
		do
			ticks_since_windows := ticks_since_windows + 1
			if ticks_since_windows >= Windows_ticks then
				ticks_since_windows := 0
				windows.refresh
				shown_selection := Void
			end
			if attached process_view.selected_id as al_id and then not scrub_view.is_scrubbing then
				if not (attached shown_selection as al_shown and then al_shown ~ al_id) then
					shown_selection := al_id
					shown_details := inspector.details (al_id)
					if attached shown_details as al_details then
						details_view.show (selected_name (al_id), al_details, windows)
					end
					if side_tabs.selected_index /= 1 then
						side_tabs.select_tab (1)
					end
				end
				actions_bar.enable (True, attached receipt)
			else
				if shown_selection /= Void then
					shown_selection := Void
					shown_details := Void
					details_view.clear
				end
				actions_bar.enable (False, attached receipt and not scrub_view.is_scrubbing)
			end
		end

	status_text (a_pid: INTEGER_64): STRING_32
			-- "Not responding", "App", or empty, from the window list.
		do
			if windows.is_hung (a_pid) then
				Result := {STRING_32} "Not responding"
			elseif windows.has_window (a_pid) then
				Result := {STRING_32} "App"
			else
				create Result.make_empty
			end
		end

	selected_name (a_id: TM_PROCESS_ID): STRING_32
			-- Name of `a_id' in the newest live frame.
		do
			if attached last_live_frame as al_frame and then al_frame.has_activity (a_id) then
				Result := al_frame.activity (a_id).name
			else
				Result := {STRING_32} "process " + a_id.pid.out.to_string_32
			end
		end

	on_action (a_tool: INTEGER)
			-- Run toolbar tool `a_tool' on the selected process and say what happened.
		local
			l_result: detachable TM_ACTION_RESULT
			l_priority: TM_PRIORITY
			l_classes: ARRAY [INTEGER]
			l_index, i: INTEGER
		do
			create l_priority
			if a_tool = 7 then
				if attached receipt as al_receipt then
					if al_receipt.efficiency_on then
						l_result := control.set_efficiency_mode (al_receipt.id, selected_name (al_receipt.id), False, al_receipt.outcome.prior_priority)
					elseif l_priority.is_settable (al_receipt.outcome.prior_priority) then
						l_result := control.set_priority (al_receipt.id, selected_name (al_receipt.id), al_receipt.outcome.prior_priority)
					end
					receipt := Void
				end
			elseif attached process_view.selected_id as al_id and then not scrub_view.is_scrubbing then
				inspect a_tool
				when 1 then
					l_result := control.end_task (al_id, selected_name (al_id), windows)
				when 2 then
					l_result := control.end_process (al_id, selected_name (al_id))
				when 3 then
					if attached last_live_frame as al_frame then
						l_result := control.end_tree (al_id, selected_name (al_id), al_frame)
					end
				when 4 then
					if attached shown_details as al_details and then al_details.is_efficiency_mode then
						l_result := control.set_efficiency_mode (al_id, selected_name (al_id), False, 0)
					else
						l_result := control.set_efficiency_mode (al_id, selected_name (al_id), True, 0)
						if l_result.succeeded then
							receipt := [al_id, l_result, True]
						end
					end
				else
					if attached shown_details as al_details and then al_details.priority_status = {TM_READING_STATUS}.Available then
						l_classes := l_priority.settable_classes
						from i := l_classes.lower until i > l_classes.upper loop
							if l_classes [i] = al_details.priority_class then
								l_index := i
							end
							i := i + 1
						end
						if a_tool = 5 and l_index > l_classes.lower then
							l_result := control.set_priority (al_id, selected_name (al_id), l_classes [l_index - 1])
						elseif a_tool = 6 and l_index > 0 and l_index < l_classes.upper then
							l_result := control.set_priority (al_id, selected_name (al_id), l_classes [l_index + 1])
						else
							create l_result.make_refused ({STRING_32} "Change priority", {STRING_32} "already at the end of the range")
						end
						if l_result.succeeded then
							receipt := [al_id, l_result, False]
						end
					else
						create l_result.make_refused ({STRING_32} "Change priority", {STRING_32} "its priority could not be read")
					end
				end
			end
			if attached l_result as al_result then
				status_bar.set_left (al_result.summary)
				action_message_until := clock.monotonic_ticks + 60_000_000
			end
			shown_selection := Void
			ticks_since_windows := Windows_ticks
		end

	action_message_until: INTEGER_64
			-- The status bar keeps an action's result until this tick.

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

	set_worker_tier0 (a_worker: separate TM_SAMPLING_WORKER; a_seconds: INTEGER)
		require
			sane: a_seconds >= 10 and a_seconds <= 86_400
		do
			a_worker.set_tier0_seconds (a_seconds)
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
				elseif argument (i).same_string ({STRING_32} "--page") and i < argument_count then
					start_page := argument (i + 1).as_lower
				elseif argument (i).same_string ({STRING_32} "--tier0-seconds") and i < argument_count and then argument (i + 1).is_integer then
					tier0_seconds := argument (i + 1).to_integer.max (10).min (86_400)
				elseif argument (i).same_string ({STRING_32} "--select") and i < argument_count and then argument (i + 1).is_integer_64 then
					select_pid := argument (i + 1).to_integer_64
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

	start_page: detachable STRING_32
			-- `--page NAME': open on that main tab (processes, performance, ...).

	tier0_seconds: INTEGER
			-- `--tier0-seconds N' (measurement aid): 1 s frames merge after N seconds; 0 for an hour.

	select_pid: INTEGER_64
			-- `--select PID': select that process once it is listed; 0 for none.

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

	Stall_ms: INTEGER = 500
			-- A tick this long is logged with its parts (soak runs).
			-- Sampling interval.

	Cpu_headline: INTEGER
			-- Metric of the CPU tile: "% Processor Utility", the counter Task
			-- Manager shows (Larry, 2026-10-06). It is scaled by clock frequency,
			-- so under turbo it can read above 100%, where Task Manager stops at 100.
		once
			Result := {TM_METRICS}.Cpu_utility_pct
		end

end
