note
	description: "One Windows service as the Services tab lists it: name, display name, process, state, start type."
	author: "Larry Rix"

class
	TM_SERVICE

create
	make

feature {NONE} -- Initialization

	make (a_name, a_display_name: READABLE_STRING_32; a_pid: INTEGER_64; a_state, a_start_type: INTEGER)
			-- Service `a_name' in `a_state' (SERVICE_* state) started `a_start_type' (SERVICE_*_START, or -1 unknown).
		require
			named: not a_name.is_empty
			pid_non_negative: a_pid >= 0
		do
			create name.make_from_string (a_name)
			create display_name.make_from_string (a_display_name)
			pid := a_pid
			state := a_state
			start_type := a_start_type
		ensure
			kept: name.same_string (a_name) and pid = a_pid and state = a_state and start_type = a_start_type
		end

feature -- Access

	name: STRING_32
	display_name: STRING_32
	pid: INTEGER_64
			-- 0 when not running.
	state: INTEGER
	start_type: INTEGER

	pid_text: STRING_32
			-- The process id, or empty when not running.
		do
			if pid > 0 then
				Result := pid.out.to_string_32
			else
				create Result.make_empty
			end
		end

	name_key: STRING_32
		do
			Result := name.as_lower
		end

	display_key: STRING_32
		do
			Result := display_name.as_lower
		end

	state_key: STRING_32
		do
			Result := state_text.as_lower
		end

	start_key: STRING_32
		do
			Result := start_type_text.as_lower
		end

	state_text: STRING_32
			-- Task Manager's word for `state'.
		do
			inspect state
			when 1 then Result := {STRING_32} "Stopped"
			when 2 then Result := {STRING_32} "Starting"
			when 3 then Result := {STRING_32} "Stopping"
			when 4 then Result := {STRING_32} "Running"
			when 5 then Result := {STRING_32} "Continuing"
			when 6 then Result := {STRING_32} "Pausing"
			when 7 then Result := {STRING_32} "Paused"
			else Result := {STRING_32} "Unknown"
			end
		end

	start_type_text: STRING_32
		do
			inspect start_type
			when 0 then Result := {STRING_32} "Boot"
			when 1 then Result := {STRING_32} "System"
			when 2 then Result := {STRING_32} "Automatic"
			when 3 then Result := {STRING_32} "Manual"
			when 4 then Result := {STRING_32} "Disabled"
			else Result := {STRING_32} "?"
			end
		end

feature -- Status report

	is_running: BOOLEAN
		do
			Result := state = 4
		end

	is_stopped: BOOLEAN
		do
			Result := state = 1
		end

invariant
	named: not name.is_empty
	pid_only_when_running: pid > 0 implies state /= 1

end
