note
	description: "[
		Phase 5, looking ahead: light series kept from live frames, and the
		forecasts fitted to them (least squares, simple_statistics):

		  memory runway   commit over the last 15 minutes: when it rises
		                  steadily, the minutes until it reaches the limit
		  disk full       each volume's free space over the last 24 hours
		                  (a point a minute): days until it reaches zero
		  leak suspects   each process's private bytes over the last hour
		                  (a point every 30 s): steady growth over 50 MB/h

		A forecast needs enough points and a good fit (R squared) before it
		says anything; until then it says it is still watching. The fit is
		shown with each forecast, so its confidence is never hidden.
	]"
	author: "Larry Rix"

class
	TM_TREND_BOOK

create
	make

feature {NONE} -- Initialization

	make
		do
			create commit_times.make (1000)
			create commit_values.make (1000)
			create volume_series.make (8)
			create process_series.make (256)
			create process_names.make (256)
			create statistics.make
			create format
		ensure
			empty: commit_times.is_empty
		end

feature -- Constants

	Commit_window_seconds: REAL_64 = 900.0
	Volume_window_seconds: REAL_64 = 86_400.0
	Process_window_seconds: REAL_64 = 3_600.0
	Volume_every_seconds: REAL_64 = 60.0
	Process_every_seconds: REAL_64 = 30.0
	Minimum_fit: REAL_64 = 0.6
	Leak_fit: REAL_64 = 0.8
	Leak_bytes_per_hour: REAL_64 = 52_428_800.0
			-- 50 MB an hour.
	Alarm_minutes: REAL_64 = 15.0

feature -- Element change

	add (a_frame: TM_FRAME)
			-- Take `a_frame''s commit, volume space, and process memory into the series.
		local
			l_time: REAL_64
			l_commit, l_limit: TM_READING
		do
			l_time := a_frame.end_ticks.to_double / {TM_CLOCK}.Ticks_per_second.to_double
			if not a_frame.is_discontinuity then
				l_commit := a_frame.readings.reading ({TM_METRICS}.Mem_commit_bytes, {STRING_32} "")
				l_limit := a_frame.readings.reading ({TM_METRICS}.Mem_commit_limit_bytes, {STRING_32} "")
				if l_commit.is_available and l_limit.is_available then
					commit_times.extend (l_time)
					commit_values.extend (l_commit.value)
					commit_limit := l_limit.value
					trim (commit_times, commit_values, l_time - Commit_window_seconds)
				end
				if l_time - last_volume_time >= Volume_every_seconds then
					last_volume_time := l_time
					across a_frame.readings.instances ({TM_METRICS}.Volume_free_bytes) as ic loop
						if a_frame.readings.reading ({TM_METRICS}.Volume_free_bytes, ic).is_available then
							add_point (volume_series, ic, l_time, a_frame.readings.reading ({TM_METRICS}.Volume_free_bytes, ic).value, Volume_window_seconds)
						end
					end
				end
				if l_time - last_process_time >= Process_every_seconds then
					last_process_time := l_time
					across a_frame.activities as ic loop
						if ic.has_resource ({TM_RESOURCE}.Memory) then
							add_point (process_series, key_of (ic.id), l_time, ic.private_bytes.to_double, Process_window_seconds)
							process_names.force (ic.name, key_of (ic.id))
						end
					end
					forget_gone (l_time)
				end
			end
		end

feature -- Forecasts

	memory_text: STRING_32
			-- Memory runway in words.
		local
			l_fit: TUPLE [slope, r2, span: REAL_64]
			l_minutes: REAL_64
		do
			if commit_times.count < 30 then
				Result := {STRING_32} "memory: watching"
			else
				l_fit := fit (commit_times, commit_values)
				if l_fit.span < 120.0 then
					Result := {STRING_32} "memory: watching"
				elseif l_fit.slope > 16_667.0 and l_fit.r2 >= Minimum_fit and commit_limit > commit_values.last then
					l_minutes := (commit_limit - commit_values.last) / l_fit.slope / 60.0
					if l_minutes <= 240.0 then
						Result := {STRING_32} "memory runs out in about " + l_minutes.rounded.out.to_string_32 + {STRING_32} " min (commit +"
							+ format.bytes ((l_fit.slope * 60.0).truncated_to_integer_64) + {STRING_32} "/min, fit " + two_places (l_fit.r2) + {STRING_32} ")"
					else
						Result := {STRING_32} "memory: rising slowly"
					end
				else
					Result := {STRING_32} "memory: steady"
				end
			end
		end

	runway_minutes: REAL_64
			-- Minutes until commit reaches the limit; -1 when no steady rise is seen.
		local
			l_fit: TUPLE [slope, r2, span: REAL_64]
		do
			Result := -1.0
			if commit_times.count >= 30 then
				l_fit := fit (commit_times, commit_values)
				if l_fit.span >= 120.0 and l_fit.slope > 16_667.0 and l_fit.r2 >= Minimum_fit and commit_limit > commit_values.last then
					Result := (commit_limit - commit_values.last) / l_fit.slope / 60.0
				end
			end
		end

	disk_texts: ARRAYED_LIST [STRING_32]
			-- One phrase per volume that is filling steadily.
		local
			l_fit: TUPLE [slope, r2, span: REAL_64]
			l_days: REAL_64
		do
			create Result.make (2)
			across volume_series as ic loop
				if ic.times.count >= 30 then
					l_fit := fit (ic.times, ic.values)
					if l_fit.span >= 3_600.0 and l_fit.slope < 0.0 and l_fit.r2 >= Minimum_fit then
						l_days := ic.values.last / (- l_fit.slope) / 86_400.0
						if l_days <= 90.0 then
							Result.extend (@ic.key + {STRING_32} " full in about " + l_days.rounded.out.to_string_32 + {STRING_32} " days (fit "
								+ two_places (l_fit.r2) + {STRING_32} ")")
						end
					end
				end
			end
		end

	leak_texts: ARRAYED_LIST [STRING_32]
			-- Processes whose private memory grows steadily, steepest first (at most three).
		local
			l_found: ARRAYED_LIST [TUPLE [slope: REAL_64; text: STRING_32]]
			l_fit: TUPLE [slope, r2, span: REAL_64]
			l_per_hour: REAL_64
			i, j: INTEGER
			l_swap: TUPLE [slope: REAL_64; text: STRING_32]
		do
			create l_found.make (4)
			across process_series as ic loop
				if ic.times.count >= 20 then
					l_fit := fit (ic.times, ic.values)
					l_per_hour := l_fit.slope * 3_600.0
					if l_fit.span >= 600.0 and l_per_hour >= Leak_bytes_per_hour and l_fit.r2 >= Leak_fit then
						l_found.extend ([l_per_hour, name_of (@ic.key) + {STRING_32} " +" + format.bytes (l_per_hour.truncated_to_integer_64)
							+ {STRING_32} "/h (fit " + two_places (l_fit.r2) + {STRING_32} ")"])
					end
				end
			end
			from i := 1 until i > l_found.count loop
				from j := i + 1 until j > l_found.count loop
					if l_found [j].slope > l_found [i].slope then
						l_swap := l_found [i]
						l_found [i] := l_found [j]
						l_found [j] := l_swap
					end
					j := j + 1
				end
				i := i + 1
			end
			create Result.make (3)
			across l_found as ic until Result.count = 3 loop
				Result.extend (ic.text)
			end
		end

	summary: STRING_32
			-- "Look ahead: ..." for the strip under the verdict.
		local
			l_disks, l_leaks: ARRAYED_LIST [STRING_32]
		do
			Result := {STRING_32} "Look ahead: " + memory_text
			l_disks := disk_texts
			across l_disks as ic loop
				Result.append ({STRING_32} " | " + ic)
			end
			if l_disks.is_empty then
				Result.append ({STRING_32} " | disks: steady or watching")
			end
			l_leaks := leak_texts
			if l_leaks.is_empty then
				Result.append ({STRING_32} " | no leak suspects")
			else
				Result.append ({STRING_32} " | leak suspects: ")
				across l_leaks as ic loop
					if @ic.cursor_index > 1 then
						Result.append ({STRING_32} ", ")
					end
					Result.append (ic)
				end
			end
		end

feature -- Status report

	is_alarming: BOOLEAN
			-- Is memory forecast to run out within `Alarm_minutes'?
		local
			l_minutes: REAL_64
		do
			l_minutes := runway_minutes
			Result := l_minutes >= 0.0 and l_minutes <= Alarm_minutes
		end

feature {NONE} -- Series

	commit_times, commit_values: ARRAYED_LIST [REAL_64]
	commit_limit: REAL_64
	volume_series: HASH_TABLE [TUPLE [times, values: ARRAYED_LIST [REAL_64]], STRING_32]
	process_series: HASH_TABLE [TUPLE [times, values: ARRAYED_LIST [REAL_64]], STRING_32]
	process_names: HASH_TABLE [STRING_32, STRING_32]
	last_volume_time, last_process_time: REAL_64
	statistics: STATISTICS
	format: TM_FORMAT

	name_of (a_key: STRING_32): STRING_32
			-- Process name kept for `a_key'.
		do
			if attached process_names.item (a_key) as al_name then
				Result := al_name
			else
				Result := {STRING_32} "process " + a_key
			end
		end

	key_of (a_id: TM_PROCESS_ID): STRING_32
		do
			Result := a_id.pid.out.to_string_32 + {STRING_32} ":" + a_id.creation_ticks.out.to_string_32
		end

	add_point (a_book: HASH_TABLE [TUPLE [times, values: ARRAYED_LIST [REAL_64]], STRING_32]; a_key: STRING_32; a_time, a_value, a_keep: REAL_64)
		local
			l_entry: TUPLE [times, values: ARRAYED_LIST [REAL_64]]
		do
			if attached a_book.item (a_key) as al_entry then
				l_entry := al_entry
			else
				l_entry := [create {ARRAYED_LIST [REAL_64]}.make (64), create {ARRAYED_LIST [REAL_64]}.make (64)]
				a_book.force (l_entry, a_key)
			end
			l_entry.times.extend (a_time)
			l_entry.values.extend (a_value)
			trim (l_entry.times, l_entry.values, a_time - a_keep)
		end

	trim (a_times, a_values: ARRAYED_LIST [REAL_64]; a_oldest: REAL_64)
			-- Drop points older than `a_oldest'.
		require
			paired: a_times.count = a_values.count
		do
			from until a_times.is_empty or else a_times.first >= a_oldest loop
				a_times.start
				a_times.remove
				a_values.start
				a_values.remove
			end
		ensure
			paired: a_times.count = a_values.count
		end

	forget_gone (a_now: REAL_64)
			-- Drop processes not seen for ten minutes.
		local
			l_gone: ARRAYED_LIST [STRING_32]
		do
			create l_gone.make (8)
			across process_series as ic loop
				if ic.times.is_empty or else a_now - ic.times.last > 600.0 then
					l_gone.extend (@ic.key)
				end
			end
			across l_gone as ic loop
				process_series.remove (ic)
				process_names.remove (ic)
			end
		end

	fit (a_times, a_values: ARRAYED_LIST [REAL_64]): TUPLE [slope, r2, span: REAL_64]
			-- Least-squares slope per second, R squared, and time span of the points.
		require
			paired: a_times.count = a_values.count
			enough: a_times.count >= 3
		local
			l_x, l_y: ARRAY [REAL_64]
			l_flat: BOOLEAN
			i: INTEGER
			l_regression: REGRESSION_RESULT
		do
			create l_x.make_filled (0.0, 1, a_times.count)
			create l_y.make_filled (0.0, 1, a_values.count)
			l_flat := True
			from i := 1 until i > a_times.count loop
				l_x [i] := a_times [i] - a_times.first
				l_y [i] := a_values [i]
				if a_values [i] /= a_values.first then
					l_flat := False
				end
				i := i + 1
			end
			if l_flat or a_times.last <= a_times.first then
				Result := [0.0, 0.0, a_times.last - a_times.first]
			else
				l_regression := statistics.linear_regression (l_x, l_y)
				Result := [l_regression.slope, l_regression.r_squared.max (0.0).min (1.0), a_times.last - a_times.first]
			end
		end

	two_places (a_value: REAL_64): STRING_32
		do
			Result := ((a_value * 100.0).rounded / 100.0).out.to_string_32
		end

invariant
	commit_paired: commit_times.count = commit_values.count

end
