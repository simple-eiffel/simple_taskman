note
	description: "[
		The process grid. Rows are rebuilt from each frame; the selection
		follows the process identity across refreshes (FR-NEW-007), and when
		the selected process exits the view says so once.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_self: detachable TM_PROCESS_ID)
			-- Empty grid; `a_self' is this tool, marked in its row.
		do
			self_id := a_self
			create format
			create rows.make (512)
			create notice.make_empty
			create grid.make (410.0)
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("Name", 176.0, agent {TM_PROCESS_ROW}.name_text)).with_key (agent {TM_PROCESS_ROW}.name_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("Status", 96.0, agent {TM_PROCESS_ROW}.status_text)).with_key (agent {TM_PROCESS_ROW}.status_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("PID", 62.0, agent {TM_PROCESS_ROW}.pid_text)).with_key (agent {TM_PROCESS_ROW}.pid_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("CPU", 66.0, agent {TM_PROCESS_ROW}.cpu_text)).with_key (agent {TM_PROCESS_ROW}.cpu_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("Private", 90.0, agent {TM_PROCESS_ROW}.private_text)).with_key (agent {TM_PROCESS_ROW}.private_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("Working set", 92.0, agent {TM_PROCESS_ROW}.working_set_text)).with_key (agent {TM_PROCESS_ROW}.working_set_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("Read/s", 88.0, agent {TM_PROCESS_ROW}.read_text)).with_key (agent {TM_PROCESS_ROW}.read_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("Write/s", 88.0, agent {TM_PROCESS_ROW}.write_text)).with_key (agent {TM_PROCESS_ROW}.write_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_PROCESS_ROW]}.make ("Threads", 62.0, agent {TM_PROCESS_ROW}.threads_text)).with_key (agent {TM_PROCESS_ROW}.threads_key))
			grid.sort_by (4, True)
			grid.set_on_select (agent on_select)
		ensure
			empty: row_count = 0
		end

feature -- Access

	grid: SW_DATA_GRID [TM_PROCESS_ROW]
			-- The widget.

	row_count: INTEGER
			-- Rows shown.
		do
			Result := rows.count
		end

	selected_id: detachable TM_PROCESS_ID
			-- Identity the user selected.

	notice: STRING_32
			-- One-line notice for the status bar from the last `show'; empty when none.

feature -- Element change

	show (a_frame: TM_FRAME)
			-- Rows for every activity of `a_frame'; keep the selection on the same identity.
		local
			l_index, i: INTEGER
		do
			create notice.make_empty
			rows.wipe_out
			across a_frame.activities as ic loop
				rows.extend (create {TM_PROCESS_ROW}.make (ic, format, attached self_id as al_self and then ic.id ~ al_self, status_of (ic.id.pid)))
			end
			grid.set_rows (rows)
			if attached selected_id as al_selected then
				from i := 1 until i > rows.count or l_index > 0 loop
					if rows [i].id ~ al_selected then
						l_index := i
					end
					i := i + 1
				end
				if l_index > 0 then
					reselecting := True
					grid.select_model_row (l_index)
					reselecting := False
				else
					notice := {STRING_32} "selected process " + al_selected.pid.out.to_string_32 + {STRING_32} " has exited"
					selected_id := Void
				end
			end
		ensure
			one_row_per_activity: row_count = a_frame.activity_count
		end

	select_pid (a_pid: INTEGER_64)
			-- Select the row of process `a_pid', if one is shown.
		local
			i: INTEGER
		do
			from i := 1 until i > rows.count loop
				if rows [i].id.pid = a_pid then
					selected_id := rows [i].id
					reselecting := True
					grid.select_model_row (i)
					reselecting := False
				end
				i := i + 1
			end
		end

	set_status_source (a_source: FUNCTION [INTEGER_64, STRING_32])
			-- Ask `a_source' for each row's status ("App", "Not responding", or empty).
		do
			status_source := a_source
		end

feature {NONE} -- Implementation

	status_source: detachable FUNCTION [INTEGER_64, STRING_32]

	status_of (a_pid: INTEGER_64): STRING_32
			-- Status text for `a_pid'; empty without a source.
		do
			if attached status_source as al_source then
				Result := al_source.item ([a_pid])
			else
				create Result.make_empty
			end
		end

	rows: ARRAYED_LIST [TM_PROCESS_ROW]
	format: TM_FORMAT
	self_id: detachable TM_PROCESS_ID
	reselecting: BOOLEAN

	on_select (a_model: INTEGER)
			-- Remember the identity under the user's selection.
		do
			if not reselecting and a_model >= 1 and a_model <= rows.count then
				selected_id := rows [a_model].id
			end
		end

end
