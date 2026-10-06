note
	description: "[
		The Users tab: each session, its user and state, and the totals of
		its processes from the newest live frame. Disconnect and Sign out
		need a second click within four seconds.
	]"
	author: "Larry Rix"

class
	TM_USERS_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_height: REAL_64)
		do
			create list.make
			create rows.make (4)
			create clock.make
			create grid.make (a_height - 90.0)
			grid.add_column ((create {SW_GRID_COLUMN [TM_SESSION]}.make ("User", 260.0, agent {TM_SESSION}.user_text)).growing.with_key (agent {TM_SESSION}.user_text))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SESSION]}.make ("Session", 80.0, agent {TM_SESSION}.id_text)).with_key (agent {TM_SESSION}.id))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SESSION]}.make ("Status", 120.0, agent {TM_SESSION}.state_text)).with_key (agent {TM_SESSION}.state_text))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SESSION]}.make ("Processes", 90.0, agent {TM_SESSION}.processes_text)).with_key (agent {TM_SESSION}.process_count))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SESSION]}.make ("CPU", 80.0, agent {TM_SESSION}.cpu_text)).with_key (agent {TM_SESSION}.cpu_percent))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SESSION]}.make ("Memory", 110.0, agent {TM_SESSION}.memory_text)).with_key (agent {TM_SESSION}.private_bytes))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SESSION]}.make ("Disk", 110.0, agent {TM_SESSION}.disk_text)).with_key (agent {TM_SESSION}.disk_bps))
			create toolbar.make
			create note_label.make_ui ("Totals of every process in each session, from the newest frame.")
			create column.make
			column := column.with_gap (6.0)
			column.put (toolbar)
			column.put (grid)
			grid.set_grow (1.0)
			column.put (note_label)
			toolbar.add_tool (Disconnect_label, "Disconnect the selected session (click twice)", True, agent act (1))
			toolbar.add_tool (Sign_out_label, "Sign the selected user out (click twice)", True, agent act (2))
			grid.set_on_select (agent on_select)
		end

feature -- Access

	column: SW_COLUMN
	list: TM_SESSION_LIST

feature -- Element change

	refresh (a_frame: detachable TM_FRAME)
		do
			list.refresh (a_frame)
			rows.wipe_out
			across list.sessions as ic loop
				rows.extend (ic)
			end
			grid.set_rows (rows)
			if armed /= 0 and then clock.monotonic_ticks - armed_at > 40_000_000 then
				disarm
			end
		end

	set_reporter (a_report: PROCEDURE [READABLE_STRING_32])
		do
			reporter := a_report
		end

feature {NONE} -- Implementation

	grid: SW_DATA_GRID [TM_SESSION]
	rows: ARRAYED_LIST [TM_SESSION]
	toolbar: SW_TOOLBAR
	note_label: SW_LABEL
	clock: TM_SYSTEM_CLOCK
	selected: detachable TM_SESSION
	reporter: detachable PROCEDURE [READABLE_STRING_32]
	armed: INTEGER
	armed_at: INTEGER_64

	Disconnect_label: STRING_32 = "Disconnect"
	Sign_out_label: STRING_32 = "Sign out"

	on_select (a_model: INTEGER)
		do
			if a_model >= 1 and a_model <= rows.count then
				selected := rows [a_model]
			end
		end

	act (a_tool: INTEGER)
		local
			l_result: TM_ACTION_RESULT
		do
			if attached selected as al_session then
				if armed = a_tool and then clock.monotonic_ticks - armed_at <= 40_000_000 then
					disarm
					if a_tool = 1 then
						l_result := list.disconnect (al_session)
					else
						l_result := list.sign_out (al_session)
					end
					report (l_result.summary)
				else
					disarm
					armed := a_tool
					armed_at := clock.monotonic_ticks
					toolbar.items [a_tool].label := {STRING_32} "Confirm " + toolbar.items [a_tool].label.as_lower + {STRING_32} " " + al_session.user_text + {STRING_32} "?"
				end
			else
				report ({STRING_32} "Select a session first")
			end
		end

	disarm
		do
			toolbar.items [1].label := Disconnect_label.twin
			toolbar.items [2].label := Sign_out_label.twin
			armed := 0
		end

	report (a_text: READABLE_STRING_32)
		do
			if attached reporter as al_report then
				al_report.call ([a_text])
			end
		end

end
