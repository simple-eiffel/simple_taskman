note
	description: "[
		The Services tab: every Windows service with its process, state, and
		start type; Start, Stop, Restart, and Open Services for the selected
		one; its description below. Refreshed only while the tab is showing.
	]"
	author: "Larry Rix"

class
	TM_SERVICES_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_height: REAL_64)
			-- Page `a_height' pixels tall.
		do
			create table.make
			create rows.make (300)
			create grid.make (a_height - 90.0)
			grid.add_column ((create {SW_GRID_COLUMN [TM_SERVICE]}.make ("Name", 200.0, agent {TM_SERVICE}.name)).with_key (agent {TM_SERVICE}.name_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SERVICE]}.make ("PID", 70.0, agent {TM_SERVICE}.pid_text)).with_key (agent {TM_SERVICE}.pid))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SERVICE]}.make ("Description", 380.0, agent {TM_SERVICE}.display_name)).growing.with_key (agent {TM_SERVICE}.display_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SERVICE]}.make ("Status", 100.0, agent {TM_SERVICE}.state_text)).with_key (agent {TM_SERVICE}.state_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_SERVICE]}.make ("Start type", 100.0, agent {TM_SERVICE}.start_type_text)).with_key (agent {TM_SERVICE}.start_key))
			grid.sort_by (1, False)
			create toolbar.make
			create description.make_ui ("Select a service to see what it does.")
			create column.make
			column := column.with_gap (6.0)
			column.put (toolbar)
			column.put (grid)
			grid.set_grow (1.0)
			column.put (description)
			toolbar.add_tool ("Start", "Start the selected service", True, agent act (1))
			toolbar.add_tool ("Stop", "Stop the selected service", True, agent act (2))
			toolbar.add_tool ("Restart", "Stop, then start again once stopped", True, agent act (3))
			toolbar.add_tool ("Open Services", "Windows' own Services window", True, agent act (4))
			grid.set_on_select (agent on_select)
		end

feature -- Access

	column: SW_COLUMN
			-- The page widget.

	table: TM_SERVICE_TABLE

feature -- Element change

	refresh
			-- Read the services again and show them.
		do
			table.refresh
			rows.wipe_out
			across table.services as ic loop
				rows.extend (ic)
			end
			grid.set_rows (rows)
			if attached selected_name as al_name then
				reselect (al_name)
			end
			if not table.last_error.is_empty then
				description.set_text (table.last_error)
			end
		end

	set_reporter (a_report: PROCEDURE [READABLE_STRING_32])
			-- Send each action's outcome to `a_report'.
		do
			reporter := a_report
		end

feature {NONE} -- Implementation

	grid: SW_DATA_GRID [TM_SERVICE]
	rows: ARRAYED_LIST [TM_SERVICE]
	toolbar: SW_TOOLBAR
	description: SW_LABEL
	selected_name: detachable STRING_32
	reporter: detachable PROCEDURE [READABLE_STRING_32]

	on_select (a_model: INTEGER)
		do
			if a_model >= 1 and a_model <= rows.count then
				selected_name := rows [a_model].name
				description.set_text (rows [a_model].display_name + {STRING_32} ": " + describe (rows [a_model].name))
			end
		end

	describe (a_name: STRING_32): STRING_32
		do
			Result := table.description (a_name)
			if Result.is_empty then
				Result := {STRING_32} "(no description)"
			end
		end

	reselect (a_name: STRING_32)
		local
			i: INTEGER
		do
			from i := 1 until i > rows.count loop
				if rows [i].name.same_string (a_name) then
					grid.select_model_row (i)
				end
				i := i + 1
			end
		end

	act (a_tool: INTEGER)
			-- Run toolbar tool `a_tool'.
		local
			l_result: detachable TM_ACTION_RESULT
		do
			if a_tool = 4 then
				open_services
			elseif attached selected_name as al_name then
				inspect a_tool
				when 1 then
					l_result := table.start (al_name)
				when 2 then
					l_result := table.stop (al_name)
				else
					l_result := table.restart (al_name)
				end
				if attached l_result as al_result and attached reporter as al_report then
					al_report.call ([al_result.summary])
				end
				refresh
			elseif attached reporter as al_report then
				al_report.call ([{STRING_32} "Select a service first"])
			end
		end

	open_services
			-- Windows' Services console.
		local
			l_target: NATIVE_STRING
		do
			create l_target.make ({STRING_32} "services.msc")
			c_open (l_target.item)
		end

	c_open (a_target: POINTER)
		external
			"C inline use <windows.h>, <shellapi.h>"
		alias
			"ShellExecuteW (NULL, L%"open%", (LPCWSTR) $a_target, NULL, NULL, SW_SHOWNORMAL);"
		end

end
