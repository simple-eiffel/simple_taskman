note
	description: "[
		How much an app cost during the first minutes after Windows started,
		measured from the recording (never estimated): CPU core-seconds and
		disk bytes of the processes with its file name, over the recorded
		frames of that window. Recordings keep only significant processes,
		so a quiet app may read as less than it was ("at least"). Without
		frames there is no measurement, and the words say so.
		Task Manager's bands: High is over 1 s of CPU or 3 MB of disk, Medium
		over 300 ms or 300 KB.
	]"
	author: "Larry Rix"

class
	TM_STARTUP_IMPACT

create
	make

feature {NONE} -- Initialization

	make (a_window: TM_WINDOW; a_image_name: READABLE_STRING_32)
			-- Cost of processes named `a_image_name' (any case) across `a_window'.
		require
			named: not a_image_name.is_empty
		local
			i: INTEGER
			l_seconds: REAL_64
		do
			is_measured := not a_window.is_empty
			from i := 1 until i > a_window.count loop
				l_seconds := a_window.frame (i).duration.to_double / {TM_CLOCK}.Ticks_per_second.to_double
				across a_window.frame (i).activities as ic loop
					if ic.name.is_case_insensitive_equal (a_image_name) then
						if ic.has_resource ({TM_RESOURCE}.Cpu) then
							cpu_seconds := cpu_seconds + ic.cpu_cores * l_seconds
						end
						if ic.has_resource ({TM_RESOURCE}.Io_total) then
							disk_bytes := disk_bytes + ic.amount_of ({TM_RESOURCE}.Io_total) * l_seconds
						end
					end
				end
				i := i + 1
			end
		ensure
			measured_when_recorded: is_measured = not a_window.is_empty
			nothing_without_frames: not is_measured implies (cpu_seconds = 0.0 and disk_bytes = 0.0)
		end

feature -- Access

	cpu_seconds: REAL_64
	disk_bytes: REAL_64

	band: STRING_32
			-- "High", "Medium", "Low", or "Not measured".
		do
			if not is_measured then
				Result := {STRING_32} "Not measured"
			elseif cpu_seconds > 1.0 or disk_bytes > 3_000_000.0 then
				Result := {STRING_32} "High"
			elseif cpu_seconds > 0.3 or disk_bytes > 300_000.0 then
				Result := {STRING_32} "Medium"
			else
				Result := {STRING_32} "Low"
			end
		end

	summary: STRING_32
			-- Band with the measured amounts.
		local
			l_format: TM_FORMAT
		do
			create l_format
			if is_measured then
				Result := band + {STRING_32} " (" + l_format.one_decimal (cpu_seconds) + {STRING_32} " s CPU, "
					+ l_format.bytes (disk_bytes.truncated_to_integer_64) + {STRING_32} " disk)"
			else
				Result := band
			end
		end

feature -- Status report

	is_measured: BOOLEAN
			-- Did the recording hold frames from that time?

invariant
	non_negative: cpu_seconds >= 0.0 and disk_bytes >= 0.0

end
