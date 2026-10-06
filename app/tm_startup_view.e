note
	description: "[
		The Startup apps tab: what Windows starts at logon, its publisher,
		enabled or disabled, and its startup impact measured from the
		recording of the minutes after the last boot (or "Not measured" when
		nothing was recording then). Enable, Disable, and Open file location
		for the selected app. Refreshed when the tab is shown.
	]"
	author: "Larry Rix"

class
	TM_STARTUP_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_height: REAL_64)
			-- Page `a_height' pixels tall.
		do
			create list.make
			create rows.make (32)
			create grid.make (a_height - 90.0)
			grid.add_column ((create {SW_GRID_COLUMN [TM_STARTUP_ITEM]}.make ("Name", 220.0, agent {TM_STARTUP_ITEM}.name)).growing.with_key (agent {TM_STARTUP_ITEM}.name_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_STARTUP_ITEM]}.make ("Publisher", 200.0, agent {TM_STARTUP_ITEM}.publisher)).with_key (agent {TM_STARTUP_ITEM}.publisher_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_STARTUP_ITEM]}.make ("Status", 90.0, agent {TM_STARTUP_ITEM}.status_text)).with_key (agent {TM_STARTUP_ITEM}.status_text))
			grid.add_column ((create {SW_GRID_COLUMN [TM_STARTUP_ITEM]}.make ("Startup impact (measured)", 260.0, agent {TM_STARTUP_ITEM}.impact)).with_key (agent {TM_STARTUP_ITEM}.impact_key))
			grid.add_column ((create {SW_GRID_COLUMN [TM_STARTUP_ITEM]}.make ("Where", 200.0, agent {TM_STARTUP_ITEM}.where)).growing.with_key (agent {TM_STARTUP_ITEM}.where))
			grid.sort_by (1, False)
			create toolbar.make
			create detail.make_ui ("Startup impact is measured from the recording of the three minutes after Windows started; turn on Record from logon (Settings) to measure the next boot.")
			create column.make
			column := column.with_gap (6.0)
			column.put (toolbar)
			column.put (grid)
			grid.set_grow (1.0)
			column.put (detail)
			toolbar.add_tool ("Enable", "Start this app at logon", True, agent act (1))
			toolbar.add_tool ("Disable", "Do not start this app at logon (it stays installed)", True, agent act (2))
			toolbar.add_tool ("Open file location", "Show the file in Explorer", True, agent act (3))
			grid.set_on_select (agent on_select)
		end

feature -- Access

	column: SW_COLUMN
			-- The page widget.

	list: TM_STARTUP_LIST

feature -- Element change

	refresh (a_boot_window: detachable TM_WINDOW)
			-- Read the startup apps again; measure each against `a_boot_window' (Void: nothing recorded then).
		do
			last_boot_window := a_boot_window
			list.refresh
			rows.wipe_out
			across list.items as ic loop
				if attached a_boot_window as al_window and then not al_window.is_empty and then not ic.image_name.is_empty then
					ic.set_impact ((create {TM_STARTUP_IMPACT}.make (al_window, ic.image_name)).summary)
				else
					ic.set_impact ({STRING_32} "Not measured")
				end
				rows.extend (ic)
			end
			grid.set_rows (rows)
		end

	set_reporter (a_report: PROCEDURE [READABLE_STRING_32])
		do
			reporter := a_report
		end

feature {NONE} -- Implementation

	grid: SW_DATA_GRID [TM_STARTUP_ITEM]
	rows: ARRAYED_LIST [TM_STARTUP_ITEM]
	toolbar: SW_TOOLBAR
	detail: SW_LABEL
	selected: detachable TM_STARTUP_ITEM
	reporter: detachable PROCEDURE [READABLE_STRING_32]
	last_boot_window: detachable TM_WINDOW

	on_select (a_model: INTEGER)
		do
			if a_model >= 1 and a_model <= rows.count then
				selected := rows [a_model]
				detail.set_text (rows [a_model].command)
			end
		end

	act (a_tool: INTEGER)
		local
			l_result: detachable TM_ACTION_RESULT
			l_target: NATIVE_STRING
		do
			if attached selected as al_item then
				inspect a_tool
				when 1 then
					l_result := list.set_enabled (al_item, True)
				when 2 then
					l_result := list.set_enabled (al_item, False)
				else
					create l_target.make ({STRING_32} "/select,%"" + al_item.image_path + {STRING_32} "%"")
					c_explore (l_target.item)
				end
				if attached l_result as al_result and attached reporter as al_report then
					al_report.call ([al_result.summary])
				end
				if a_tool /= 3 then
					refresh (last_boot_window)
				end
			elseif attached reporter as al_report then
				al_report.call ([{STRING_32} "Select an app first"])
			end
		end

	c_explore (a_arguments: POINTER)
		external
			"C inline use <windows.h>, <shellapi.h>"
		alias
			"ShellExecuteW (NULL, L%"open%", L%"explorer.exe%", (LPCWSTR) $a_arguments, NULL, SW_SHOWNORMAL);"
		end

end
