note
	description: "[
		Spike O-2 measurement: what one run of the window cost. Written to
		%LOCALAPPDATA%\simple_taskman\logs\taskman-gui.log through
		SIMPLE_LOGGER.make_to_file (R-3: a window target never uses the
		console logger). A line a minute, and a summary at the end.
	]"
	author: "Larry Rix"

class
	TM_SOAK_LOG

create
	make

feature {NONE} -- Initialization

	make
			-- Not started.
		do
			create mode.make_empty
			create source.make_empty
			create clock.make
			create slowest.make (6)
		end

feature -- Access

	frames_shown: INTEGER
	render_max_ms: INTEGER
	render_total_ms: INTEGER_64
	renders: INTEGER
	cost_max_ms: REAL_64
	self_cpu_total: REAL_64
	self_cpu_samples: INTEGER
	self_cpu_max: REAL_64
	first_private, last_private: REAL_64
	deposited, dropped: INTEGER
	processes_max: INTEGER
	cost_total_ms: REAL_64
	cost_samples: INTEGER
	cost_over_budget: INTEGER
			-- Ticks whose sampling cost exceeded 1% of the 1 s interval (10 ms).
	slowest: ARRAYED_LIST [REAL_64]
			-- The five largest sampling costs, largest first.
	tick_max_ms: INTEGER
	tick_total_ms: INTEGER_64
	ticks: INTEGER
	private_samples: INTEGER

feature -- Element change

	start (a_mode: READABLE_STRING_32; a_cores: INTEGER)
			-- Begin a run.
		do
			create mode.make_from_string (a_mode)
			started := clock.monotonic_ticks
			last_minute := started
			open_log
			write ({STRING_32} "start: " + mode + {STRING_32} ", heatmap cells " + a_cores.out.to_string_32)
		end

	note_source (a_kind: READABLE_STRING_32)
		do
			create source.make_from_string (a_kind)
			write ({STRING_32} "process table: " + source)
		end

	note_render (a_ms: INTEGER)
			-- The last frame took `a_ms' to draw.
		do
			if a_ms > 0 then
				renders := renders + 1
				render_total_ms := render_total_ms + a_ms
				render_max_ms := render_max_ms.max (a_ms)
			end
		end

	note_tick (a_ms: INTEGER)
			-- The window's tick handler (collect, decode, rebuild the views) took `a_ms'.
		do
			ticks := ticks + 1
			tick_total_ms := tick_total_ms + a_ms
			tick_max_ms := tick_max_ms.max (a_ms)
		end

	note_frame (a_frame: TM_FRAME)
			-- A frame was shown.
		local
			l_reading: TM_READING
		do
			frames_shown := frames_shown + 1
			processes_max := processes_max.max (a_frame.activity_count)
			l_reading := a_frame.readings.reading ({TM_METRICS}.Sample_cost_ms, {STRING_32} "")
			if l_reading.is_available then
				cost_max_ms := cost_max_ms.max (l_reading.value)
				cost_total_ms := cost_total_ms + l_reading.value
				cost_samples := cost_samples + 1
				if l_reading.value > Budget_ms then
					cost_over_budget := cost_over_budget + 1
				end
				keep_slowest (l_reading.value)
			end
			l_reading := a_frame.readings.reading ({TM_METRICS}.Self_cpu_pct, {STRING_32} "")
			if l_reading.is_available then
				self_cpu_total := self_cpu_total + l_reading.value
				self_cpu_samples := self_cpu_samples + 1
				self_cpu_max := self_cpu_max.max (l_reading.value)
			end
			l_reading := a_frame.readings.reading ({TM_METRICS}.Self_private_bytes, {STRING_32} "")
			if l_reading.is_available then
				if private_samples = 0 then
					first_private := l_reading.value
				end
				private_samples := private_samples + 1
				last_private := l_reading.value
			end
			if clock.monotonic_ticks - last_minute >= 60 * Tps then
				last_minute := clock.monotonic_ticks
				write (summary_line ({STRING_32} "minute"))
			end
		end

	note_slot (a_deposited, a_dropped: INTEGER)
		do
			deposited := a_deposited
			dropped := a_dropped
		end

	finish (a_last_render_ms: INTEGER)
			-- Write the summary.
		do
			note_render (a_last_render_ms)
			write (summary_line ({STRING_32} "summary"))
		end

feature {NONE} -- Implementation

	mode, source: STRING_32
	clock: TM_SYSTEM_CLOCK
	started, last_minute: INTEGER_64
	logger: detachable SIMPLE_LOGGER

	Tps: INTEGER_64 = 10_000_000

	summary_line (a_kind: READABLE_STRING_32): STRING_32
		local
			l_format: TM_FORMAT
		do
			create l_format
			Result := a_kind + {STRING_32} ": " + ((clock.monotonic_ticks - started) // Tps).out.to_string_32 + {STRING_32} " s"
				+ {STRING_32} ", frames shown " + frames_shown.out.to_string_32
				+ {STRING_32} ", deposited " + deposited.out.to_string_32 + {STRING_32} ", dropped " + dropped.out.to_string_32
				+ {STRING_32} ", processes max " + processes_max.out.to_string_32
				+ {STRING_32} ", render avg " + average (render_total_ms.to_double, renders) + {STRING_32} " ms max " + render_max_ms.out.to_string_32 + {STRING_32} " ms"
				+ {STRING_32} ", tick avg " + average (tick_total_ms.to_double, ticks) + {STRING_32} " ms max " + tick_max_ms.out.to_string_32 + {STRING_32} " ms"
				+ {STRING_32} ", sample cost avg " + average (cost_total_ms, cost_samples) + {STRING_32} " ms ("
				+ average (cost_total_ms / 10.0, cost_samples) + {STRING_32} "%% of the interval) max " + l_format.one_decimal (cost_max_ms)
				+ {STRING_32} " ms, over 10 ms " + cost_over_budget.out.to_string_32 + {STRING_32} " of " + cost_samples.out.to_string_32
				+ {STRING_32} ", slowest " + slowest_text (l_format)
				+ {STRING_32} ", own CPU " + own_cpu_text (l_format)
				+ {STRING_32} ", private " + private_text (l_format)
		end

	Budget_ms: REAL_64 = 10.0
			-- NFR-001 at a 1 s interval: 1% of one logical processor.

	keep_slowest (a_ms: REAL_64)
			-- Remember `a_ms' if it is among the five largest.
		local
			i: INTEGER
		do
			from i := 1 until i > slowest.count or else slowest [i] < a_ms loop
				i := i + 1
			end
			if i <= 5 then
				slowest.go_i_th (i)
				if i > slowest.count then
					slowest.extend (a_ms)
				else
					slowest.put_left (a_ms)
				end
				if slowest.count > 5 then
					slowest.finish
					slowest.remove
				end
			end
		end

	slowest_text (a_format: TM_FORMAT): STRING_32
		do
			create Result.make (40)
			across slowest as ic loop
				if not Result.is_empty then
					Result.append ({STRING_32} "/")
				end
				Result.append (a_format.one_decimal (ic))
			end
			if Result.is_empty then
				Result := {STRING_32} "n/a"
			end
		end

	own_cpu_text (a_format: TM_FORMAT): STRING_32
			-- Own CPU, or n/a when no frame carried it (a replay has no tool row).
		do
			if self_cpu_samples > 0 then
				Result := {STRING_32} "avg " + average (self_cpu_total, self_cpu_samples) + {STRING_32} "%% max " + a_format.one_decimal (self_cpu_max) + {STRING_32} "%%"
			else
				Result := {STRING_32} "n/a"
			end
		end

	private_text (a_format: TM_FORMAT): STRING_32
			-- Private bytes first and last, or n/a: never a number for a missing value.
		do
			if private_samples > 0 then
				Result := a_format.bytes (first_private.truncated_to_integer_64) + {STRING_32} " -> " + a_format.bytes (last_private.truncated_to_integer_64)
			else
				Result := {STRING_32} "n/a"
			end
		end

	average (a_total: REAL_64; a_count: INTEGER): STRING_32
		local
			l_format: TM_FORMAT
		do
			create l_format
			if a_count > 0 then
				Result := l_format.one_decimal (a_total / a_count)
			else
				Result := {STRING_32} "n/a"
			end
		end

	open_log
			-- The per-processor log file of the window (R-3).
		local
			l_paths: TM_PATHS
			l_folder: DIRECTORY
			l_utf: UTF_CONVERTER
		do
			create l_paths.make
			if l_paths.has_root then
				create l_folder.make_with_name (l_paths.logs_folder)
				if not l_folder.exists then
					l_folder.recursive_create_dir
				end
				create logger.make_to_file (l_utf.string_32_to_utf_8_string_8 (l_paths.log_path ({STRING_32} "taskman", {STRING_32} "gui")))
			end
		end

	write (a_line: READABLE_STRING_32)
		do
			if attached logger as al_logger then
				al_logger.info (a_line)
			end
		end

end
