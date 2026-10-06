note
	description: "[
		`taskman_cli trace': what the recording holds, and what the machine was
		doing at a chosen moment. Opens the recording read-only, so it works
		while a window records; a reader sees frames up to the writer's last
		commit (at most 30 frames behind).

		    taskman_cli trace                    span, tiers, size, the newest moment
		    taskman_cli trace --ago 300          the moment five minutes back
		    taskman_cli trace --file PATH --top 5
	]"
	author: "Larry Rix"

class
	TM_TRACE_COMMAND

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make (a_path: READABLE_STRING_32; a_seconds_ago, a_top: INTEGER)
			-- Report on the recording at `a_path', at `a_seconds_ago' before its newest frame, listing `a_top' processes.
		require
			path_given: not a_path.is_empty
			not_negative: a_seconds_ago >= 0
			top_sane: a_top >= 1 and a_top <= 500
		do
			create path.make_from_string (a_path)
			seconds_ago := a_seconds_ago
			top := a_top
			create output.make_empty
		ensure
			kept: path.same_string (a_path) and seconds_ago = a_seconds_ago and top = a_top
		end

feature -- Access

	path: STRING_32
	seconds_ago: INTEGER
	top: INTEGER

	output: STRING_32
			-- The report.

	exit_code: INTEGER
			-- 0, or 3 when there is no readable recording.

feature -- Execution

	execute
			-- Read the recording and describe it.
		local
			l_store: TM_SQLITE_TRACE_STORE
			l_tiers: ARRAY [INTEGER]
			l_time: TM_LOCAL_TIME
			l_format: TM_FORMAT
		do
			create output.make (2048)
			create l_time
			create l_format
			create l_store.make_reader (path)
			if not l_store.is_open then
				output.append ({STRING_32} "no recording: " + l_store.last_error + {STRING_32} "%N")
				exit_code := 3
			elseif l_store.is_empty then
				output.append ({STRING_32} "recording " + path + {STRING_32} " holds no frames yet%N")
				l_store.close
			else
				l_tiers := <<0, 0, 0>>
				l_tiers.rebase (0)
				across l_store.entries as ic loop
					l_tiers [ic.tier] := l_tiers [ic.tier] + 1
				end
				output.append ({STRING_32} "recording  " + path + {STRING_32} "%N")
				output.append ({STRING_32} "span       " + l_time.text (l_store.earliest_ticks) + {STRING_32} " to "
					+ l_time.text (l_store.latest_ticks) + {STRING_32} "%N")
				output.append ({STRING_32} "frames     " + l_store.frame_count.out.to_string_32 + {STRING_32} " (1 s: "
					+ l_tiers [0].out.to_string_32 + {STRING_32} ", 10 s: " + l_tiers [1].out.to_string_32
					+ {STRING_32} ", 60 s: " + l_tiers [2].out.to_string_32 + {STRING_32} ")%N")
				output.append ({STRING_32} "size       " + l_format.bytes (l_store.size_bytes) + {STRING_32} "%N")
				if attached l_store.frame_nearest (l_store.latest_ticks - seconds_ago.to_integer_64 * {TM_CLOCK}.Ticks_per_second) as al_frame then
					describe (al_frame)
				else
					output.append ({STRING_32} "no frame readable: " + l_store.last_error + {STRING_32} "%N")
					exit_code := 3
				end
				l_store.close
			end
		ensure
			reported: not output.is_empty
		end

feature {NONE} -- Implementation

	describe (a_frame: TM_FRAME)
			-- The frame's headline readings and its busiest recorded processes.
		local
			l_time: TM_LOCAL_TIME
			l_format: TM_FORMAT
			l_line: STRING_32
		do
			create l_time
			create l_format
			output.append ({STRING_32} "%Nmoment     " + l_time.text (a_frame.start_ticks) + {STRING_32} " ("
				+ ((a_frame.duration + {TM_CLOCK}.Ticks_per_second // 2) // {TM_CLOCK}.Ticks_per_second).out.to_string_32
				+ {STRING_32} " s)")
			if a_frame.is_discontinuity then
				output.append ({STRING_32} " gap: the machine was not measured")
			end
			output.append ({STRING_32} "%N")
			across <<{TM_METRICS}.Cpu_utility_pct, {TM_METRICS}.Cpu_busy_pct, {TM_METRICS}.Mem_commit_pct, {TM_METRICS}.Cpu_package_watts>> as ic loop
				output.append (metrics.metric (ic).name.to_string_32 + {STRING_32} "  "
					+ l_format.reading_text (a_frame.readings.reading (ic, {STRING_32} ""), metrics.metric (ic)) + {STRING_32} "%N")
			end
			output.append ({STRING_32} "processes  " + a_frame.activity_count.out.to_string_32 + {STRING_32} " recorded, "
				+ a_frame.omitted_processes.out.to_string_32 + {STRING_32} " quiet ones not recorded%N%N")
			output.append ({STRING_32} "PID     CPU      PRIVATE     NAME%N")
			across a_frame.top_by ({TM_RESOURCE}.Cpu, top) as ic loop
				create l_line.make (80)
				l_line.append (padded (ic.id.pid.out.to_string_32, 8))
				if ic.has_resource ({TM_RESOURCE}.Cpu) then
					l_line.append (padded (l_format.percent (ic.cpu_percent), 9))
				else
					l_line.append (padded (l_format.status_word (ic.cpu_status), 9))
				end
				if ic.has_resource ({TM_RESOURCE}.Memory) then
					l_line.append (padded (l_format.bytes (ic.private_bytes), 12))
				else
					l_line.append (padded (l_format.status_word (ic.memory_status), 12))
				end
				l_line.append (ic.name)
				output.append (l_line + {STRING_32} "%N")
			end
		end

	padded (a_text: READABLE_STRING_32; a_width: INTEGER): STRING_32
			-- `a_text' followed by spaces up to `a_width', and at least one space.
		do
			create Result.make_from_string (a_text)
			from until Result.count >= a_width - 1 loop
				Result.append_character (' ')
			end
			Result.append_character (' ')
		end

end
