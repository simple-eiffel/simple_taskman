note
	description: "One signed-in session and its totals from a frame (Users tab)."
	author: "Larry Rix"

class
	TM_SESSION

create
	make

feature {NONE} -- Initialization

	make (a_id, a_state: INTEGER; a_user: READABLE_STRING_32)
			-- Session `a_id' in WTS state `a_state' for `a_user' (DOMAIN\user, or empty).
		do
			id := a_id
			state := a_state
			create user.make_from_string (a_user)
		ensure
			kept: id = a_id and state = a_state and user.same_string (a_user)
		end

feature -- Access

	id: INTEGER
	state: INTEGER
	user: STRING_32
	process_count: INTEGER
	cpu_percent: REAL_64
			-- Sum of the measured processes' CPU, percent of the whole machine.
	private_bytes: INTEGER_64
	disk_bps: REAL_64

	state_text: STRING_32
		do
			inspect state
			when 0 then Result := {STRING_32} "Active"
			when 1 then Result := {STRING_32} "Connected"
			when 4 then Result := {STRING_32} "Disconnected"
			when 2 then Result := {STRING_32} "Connect query"
			when 3 then Result := {STRING_32} "Shadow"
			when 5 then Result := {STRING_32} "Idle"
			when 6 then Result := {STRING_32} "Listening"
			when 7 then Result := {STRING_32} "Resetting"
			when 8 then Result := {STRING_32} "Down"
			when 9 then Result := {STRING_32} "Initializing"
			else Result := {STRING_32} "Unknown"
			end
		end

	user_text: STRING_32
		do
			if user.is_empty then
				Result := {STRING_32} "(system, session " + id.out.to_string_32 + {STRING_32} ")"
			else
				Result := user
			end
		end

	id_text: STRING_32
		do
			Result := id.out.to_string_32
		end

	processes_text: STRING_32
		do
			Result := process_count.out.to_string_32
		end

	cpu_text: STRING_32
		do
			Result := (create {TM_FORMAT}).percent (cpu_percent)
		end

	memory_text: STRING_32
		do
			Result := (create {TM_FORMAT}).bytes (private_bytes)
		end

	disk_text: STRING_32
		do
			Result := (create {TM_FORMAT}).bytes_per_second (disk_bps)
		end

feature -- Element change

	add_activity (a_activity: TM_PROCESS_ACTIVITY)
			-- Count `a_activity' into this session's totals.
		require
			same_session: a_activity.session = id
		do
			process_count := process_count + 1
			if a_activity.has_resource ({TM_RESOURCE}.Cpu) then
				cpu_percent := cpu_percent + a_activity.cpu_percent
			end
			if a_activity.has_resource ({TM_RESOURCE}.Memory) then
				private_bytes := private_bytes + a_activity.private_bytes
			end
			if a_activity.has_resource ({TM_RESOURCE}.Io_total) then
				disk_bps := disk_bps + a_activity.amount_of ({TM_RESOURCE}.Io_total)
			end
		ensure
			counted: process_count = old process_count + 1
		end

invariant
	non_negative: process_count >= 0 and cpu_percent >= 0.0 and private_bytes >= 0 and disk_bps >= 0.0

end
