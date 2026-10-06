note
	description: "[
		The Performance tab, laid out as Task Manager's: a list of resources
		on the left (CPU, memory, each disk, each network adapter once it has
		carried traffic, the GPU), each with a live one-line summary; on the
		right the selected resource's last minute as a chart and its facts.
		Fed every live frame whether or not the tab is showing, so switching
		to it finds a full minute of history.
	]"
	author: "Larry Rix"

class
	TM_PERFORMANCE_VIEW

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make (a_machine: TM_MACHINE_INFO; a_height: REAL_64)
			-- Page describing `a_machine', `a_height' pixels tall.
		local
			l_left, l_right: SW_COLUMN
			l_fact: SW_ROW
		do
			machine := a_machine
			create format
			create panels.make (8)
			create list.make (a_height)
			list := list.with_min_size (List_width, 0.0).with_max_size (List_width, 0.0)
			list.set_row_height (54.0)
			create chart.make
			chart := chart.with_max_size (0.0, Chart_height)
			create heading.make ("", {SW_PAINTER}.Role_ui, 20.0, True)
			create fact_names.make (Fact_count)
			create fact_values.make (Fact_count)
			create facts_column.make
			facts_column := facts_column.with_gap (24.0)
			create l_left.make
			create l_right.make
			from until fact_names.count = Fact_count loop
				fact_names.extend ((create {SW_LABEL}.make_ui ("")).with_min_size (Name_width, 0.0).with_max_size (Name_width, 0.0))
				fact_values.extend (create {SW_LABEL}.make_ui (""))
				create l_fact.make
				l_fact.put (fact_names.last)
				l_fact.put (fact_values.last)
				if fact_names.count <= Fact_count // 2 then
					l_left.put (l_fact)
				else
					l_right.put (l_fact)
				end
			end
			l_left.set_grow (1.0)
			l_right.set_grow (1.0)
			facts_column.put (l_left)
			facts_column.put (l_right)
			create detail.make
			detail := detail.with_gap (8.0)
			detail.put (heading)
			detail.put (chart)
			detail.put (facts_column)
			detail.set_grow (1.0)
			create page.make
			page := page.with_gap (12.0)
			page.put (list)
			page.put (detail)
			list.set_row_renderer (agent draw_row)
			list.set_on_select (agent on_select)
			add_panel (create {TM_RESOURCE_PANEL}.make ({STRING_32} "cpu", {STRING_32} "CPU", <<{STRING_32} "Utility %%", {STRING_32} "Kernel %%">>))
			add_panel (create {TM_RESOURCE_PANEL}.make ({STRING_32} "memory", {STRING_32} "Memory", <<{STRING_32} "In use %%">>))
			selected := 1
		end

feature -- Access

	page: SW_ROW
			-- The tab's widget.

	panels: ARRAYED_LIST [TM_RESOURCE_PANEL]

	selected: INTEGER
			-- Index of the panel on the right.

feature -- Element change

	show (a_frame: TM_FRAME)
			-- Take every resource's readings from `a_frame'.
		local
			l_r: TM_READINGS
		do
			l_r := a_frame.readings
			update_cpu (l_r)
			update_memory (l_r)
			across l_r.instances ({TM_METRICS}.Disk_busy_pct) as ic loop
				update_disk (l_r, ic)
			end
			across l_r.instances ({TM_METRICS}.Net_send_bps) as ic loop
				update_network (l_r, ic)
			end
			update_gpu (l_r)
			list.set_row_count (panels.count)
			show_selected
		end

feature {NONE} -- Resources

	update_cpu (a_r: TM_READINGS)
		local
			l_panel: TM_RESOURCE_PANEL
			l_utility, l_speed: STRING_32
		do
			l_panel := panels [1]
			push (l_panel, 1, a_r.reading ({TM_METRICS}.Cpu_utility_pct, {STRING_32} ""))
			push (l_panel, 2, a_r.reading ({TM_METRICS}.Cpu_kernel_pct, {STRING_32} ""))
			l_utility := text_of (a_r, {TM_METRICS}.Cpu_utility_pct)
			if machine.base_mhz > 0 and then a_r.reading ({TM_METRICS}.Cpu_performance_pct, {STRING_32} "").is_available then
				l_speed := ghz (machine.base_mhz * a_r.reading ({TM_METRICS}.Cpu_performance_pct, {STRING_32} "").value / 100.0)
			else
				l_speed := {STRING_32} "speed not measured"
			end
			l_panel.set_summary (l_utility + {STRING_32} "  " + l_speed)
			l_panel.set_facts (<<
				{STRING_32} "Utilization      " + l_utility,
				{STRING_32} "Kernel time      " + text_of (a_r, {TM_METRICS}.Cpu_kernel_pct),
				{STRING_32} "Speed            " + l_speed,
				{STRING_32} "Base speed       " + ghz (machine.base_mhz.to_double),
				{STRING_32} "Processes        " + text_of (a_r, {TM_METRICS}.Sys_processes),
				{STRING_32} "Threads          " + text_of (a_r, {TM_METRICS}.Sys_threads),
				{STRING_32} "Handles          " + text_of (a_r, {TM_METRICS}.Sys_handles),
				{STRING_32} "Up time          " + machine.uptime_text,
				{STRING_32} "Sockets          " + machine.sockets.out.to_string_32,
				{STRING_32} "Cores            " + machine.cores.out.to_string_32,
				{STRING_32} "Logical          " + machine.logical_processors.out.to_string_32,
				{STRING_32} "Virtualization   " + enabled (machine.is_virtualization_enabled),
				{STRING_32} "L1 / L2 / L3     " + format.bytes (machine.l1_bytes) + {STRING_32} " / " + format.bytes (machine.l2_bytes)
					+ {STRING_32} " / " + format.bytes (machine.l3_bytes),
				machine.processor_name>>)
		end

	update_memory (a_r: TM_READINGS)
		local
			l_panel: TM_RESOURCE_PANEL
			l_used, l_available: TM_READING
			l_pct: REAL_64
			l_total_text: STRING_32
		do
			l_panel := panels [2]
			l_used := a_r.reading ({TM_METRICS}.Mem_used_bytes, {STRING_32} "")
			l_available := a_r.reading ({TM_METRICS}.Mem_available_bytes, {STRING_32} "")
			if l_used.is_available and l_available.is_available and then l_used.value + l_available.value > 0.0 then
				l_pct := l_used.value * 100.0 / (l_used.value + l_available.value)
				l_panel.add_point (1, l_pct)
				l_total_text := format.bytes ((l_used.value + l_available.value).truncated_to_integer_64)
				l_panel.set_summary (format.bytes (l_used.value.truncated_to_integer_64) + {STRING_32} " / " + l_total_text
					+ {STRING_32} " (" + format.percent (l_pct) + {STRING_32} ")")
			else
				l_total_text := {STRING_32} "unknown"
				l_panel.set_summary ({STRING_32} "not measured")
			end
			l_panel.set_facts (<<
				{STRING_32} "In use           " + text_of (a_r, {TM_METRICS}.Mem_used_bytes),
				{STRING_32} "Available        " + text_of (a_r, {TM_METRICS}.Mem_available_bytes),
				{STRING_32} "Usable           " + l_total_text,
				{STRING_32} "Installed        " + installed_text,
				{STRING_32} "Committed        " + text_of (a_r, {TM_METRICS}.Mem_commit_bytes) + {STRING_32} " of "
					+ text_of (a_r, {TM_METRICS}.Mem_commit_limit_bytes) + {STRING_32} " (" + text_of (a_r, {TM_METRICS}.Mem_commit_pct) + {STRING_32} ")",
				{STRING_32} "Cached           " + text_of (a_r, {TM_METRICS}.Mem_cached_bytes),
				{STRING_32} "Paged pool       " + text_of (a_r, {TM_METRICS}.Mem_paged_pool_bytes),
				{STRING_32} "Non-paged pool   " + text_of (a_r, {TM_METRICS}.Mem_nonpaged_pool_bytes),
				{STRING_32} "Hard faults      " + text_of (a_r, {TM_METRICS}.Mem_hard_faults_per_s)>>)
		end

	update_disk (a_r: TM_READINGS; a_instance: STRING_32)
		local
			l_panel: TM_RESOURCE_PANEL
		do
			l_panel := panel_for ({STRING_32} "disk " + a_instance, {STRING_32} "Disk " + a_instance, <<{STRING_32} "Active time %%">>)
			push (l_panel, 1, a_r.reading ({TM_METRICS}.Disk_busy_pct, a_instance))
			l_panel.set_summary (instance_text (a_r, {TM_METRICS}.Disk_busy_pct, a_instance) + {STRING_32} " active")
			l_panel.set_facts (<<
				{STRING_32} "Active time      " + instance_text (a_r, {TM_METRICS}.Disk_busy_pct, a_instance),
				{STRING_32} "Response time    " + instance_text (a_r, {TM_METRICS}.Disk_response_ms, a_instance),
				{STRING_32} "Read speed       " + instance_text (a_r, {TM_METRICS}.Disk_read_bps, a_instance),
				{STRING_32} "Write speed      " + instance_text (a_r, {TM_METRICS}.Disk_write_bps, a_instance),
				{STRING_32} "",
				{STRING_32} "Busy with little moving means a stalled drive, not a hard-working one.">>)
		end

	update_network (a_r: TM_READINGS; a_instance: STRING_32)
			-- An adapter joins the list once it has carried traffic.
		local
			l_panel: TM_RESOURCE_PANEL
			l_send, l_receive: TM_READING
			l_key: STRING_32
		do
			l_key := {STRING_32} "net " + a_instance
			l_send := a_r.reading ({TM_METRICS}.Net_send_bps, a_instance)
			if a_r.has ({TM_METRICS}.Net_receive_bps, a_instance) then
				l_receive := a_r.reading ({TM_METRICS}.Net_receive_bps, a_instance)
			else
				create l_receive.make_unavailable
			end
			if has_panel (l_key) or else (l_send.is_available and then l_send.value > 0.0)
					or else (l_receive.is_available and then l_receive.value > 0.0) then
				l_panel := panel_for (l_key, a_instance, <<{STRING_32} "Send", {STRING_32} "Receive">>)
				push (l_panel, 1, l_send)
				push (l_panel, 2, l_receive)
				l_panel.set_summary ({STRING_32} "S " + format.reading_text (l_send, metrics.metric ({TM_METRICS}.Net_send_bps))
					+ {STRING_32} "  R " + format.reading_text (l_receive, metrics.metric ({TM_METRICS}.Net_receive_bps)))
				l_panel.set_facts (<<
					{STRING_32} "Send             " + format.reading_text (l_send, metrics.metric ({TM_METRICS}.Net_send_bps)),
					{STRING_32} "Receive          " + format.reading_text (l_receive, metrics.metric ({TM_METRICS}.Net_receive_bps)),
					{STRING_32} "",
					{STRING_32} "Adapter          " + a_instance>>)
			end
		end

	update_gpu (a_r: TM_READINGS)
			-- One panel for the GPU: a line per engine type, memory per adapter.
		local
			l_panel: TM_RESOURCE_PANEL
			l_engines: ARRAYED_LIST [STRING_32]
			l_names: ARRAY [STRING_32]
			l_facts: ARRAYED_LIST [STRING_32]
			l_peak: REAL_64
			l_any: BOOLEAN
			i: INTEGER
			l_name: STRING_32
		do
			l_engines := a_r.instances ({TM_METRICS}.Gpu_busy_pct)
			if not l_engines.is_empty then
				if not has_panel ({STRING_32} "gpu") then
					create l_names.make_filled ({STRING_32} "", 1, l_engines.count.min (4))
					from i := 1 until i > l_names.count loop
						l_names [i] := l_engines [i] + {STRING_32} " %%"
						i := i + 1
					end
					if machine.display_adapters.is_empty then
						l_name := {STRING_32} "GPU"
					else
						l_name := {STRING_32} "GPU  " + machine.display_adapters.first
					end
					add_panel (create {TM_RESOURCE_PANEL}.make ({STRING_32} "gpu", l_name, l_names))
				end
				l_panel := panel_for ({STRING_32} "gpu", {STRING_32} "GPU", <<{STRING_32} "3D %%">>)
				create l_facts.make (12)
				from i := 1 until i > l_engines.count loop
					if i <= l_panel.series_names.count then
						push (l_panel, i, a_r.reading ({TM_METRICS}.Gpu_busy_pct, l_engines [i]))
					end
					if a_r.reading ({TM_METRICS}.Gpu_busy_pct, l_engines [i]).is_available then
						l_peak := l_peak.max (a_r.reading ({TM_METRICS}.Gpu_busy_pct, l_engines [i]).value)
						l_any := True
					end
					l_facts.extend (padded (l_engines [i]) + instance_text (a_r, {TM_METRICS}.Gpu_busy_pct, l_engines [i]))
					i := i + 1
				end
				across a_r.instances ({TM_METRICS}.Gpu_dedicated_bytes) as ic loop
					l_facts.extend (padded (ic + {STRING_32} " dedicated") + instance_text (a_r, {TM_METRICS}.Gpu_dedicated_bytes, ic))
				end
				across a_r.instances ({TM_METRICS}.Gpu_shared_bytes) as ic loop
					l_facts.extend (padded (ic + {STRING_32} " shared") + instance_text (a_r, {TM_METRICS}.Gpu_shared_bytes, ic))
				end
				across machine.display_adapters as ic loop
					l_facts.extend (ic)
				end
				if l_any then
					l_panel.set_summary (format.percent (l_peak) + {STRING_32} " busiest engine")
				else
					l_panel.set_summary ({STRING_32} "not measured")
				end
				l_panel.set_facts (l_facts.to_array)
			end
		end

feature {NONE} -- Drawing

	draw_row (a_p: SW_PAINTER; a_row: INTEGER; a_x, a_y, a_w, a_h: REAL_64)
			-- Title over summary for panel `a_row'.
		do
			if a_row >= 1 and a_row <= panels.count then
				a_p.font ({SW_PAINTER}.Role_ui, 14.0, True)
				a_p.set_color (a_p.theme.ink)
				a_p.text (a_x + 10.0, a_y + 22.0, panels [a_row].title)
				a_p.font ({SW_PAINTER}.Role_ui, 12.0, False)
				a_p.set_color (a_p.theme.ink_muted)
				a_p.text (a_x + 10.0, a_y + 42.0, panels [a_row].summary)
			end
		end

	on_select (a_row: INTEGER)
			-- The user picked panel `a_row'.
		do
			if a_row >= 1 and a_row <= panels.count then
				selected := a_row
				show_selected
			end
		end

	show_selected
			-- The selected panel on the right: heading, chart, facts.
		local
			l_panel: TM_RESOURCE_PANEL
			i, l_cut: INTEGER
			l_value: STRING_32
		do
			if selected >= 1 and selected <= panels.count then
				l_panel := panels [selected]
				heading.set_text (l_panel.title)
				chart.series.wipe_out
				from i := 1 until i > l_panel.series_names.count loop
					chart.add_series (l_panel.series_names [i])
					across l_panel.histories [i] as ic loop
						chart.add_point (@ic.cursor_index.to_double, ic)
					end
					i := i + 1
				end
				from i := 1 until i > fact_names.count loop
					if i <= l_panel.facts.count then
						l_cut := l_panel.facts [i].substring_index ({STRING_32} "  ", 1)
						if l_cut > 0 then
							fact_names [i].set_text (l_panel.facts [i].substring (1, l_cut - 1))
							l_value := l_panel.facts [i].substring (l_cut, l_panel.facts [i].count)
							l_value.left_adjust
							fact_values [i].set_text (l_value)
						else
							fact_names [i].set_text ("")
							fact_values [i].set_text (l_panel.facts [i])
						end
					else
						fact_names [i].set_text ("")
						fact_values [i].set_text ("")
					end
					i := i + 1
				end
			end
		end

feature {NONE} -- Implementation

	machine: TM_MACHINE_INFO
	format: TM_FORMAT
	list: SW_LIST
	chart: SW_LINE_CHART
	heading: SW_LABEL
	fact_names, fact_values: ARRAYED_LIST [SW_LABEL]
	facts_column: SW_ROW

	Fact_count: INTEGER = 14
	List_width: REAL_64 = 270.0
	Name_width: REAL_64 = 130.0
	Chart_height: REAL_64 = 210.0
	detail: SW_COLUMN

	add_panel (a_panel: TM_RESOURCE_PANEL)
		do
			panels.extend (a_panel)
		end

	has_panel (a_key: READABLE_STRING_32): BOOLEAN
		do
			Result := across panels as ic some ic.key.same_string (a_key) end
		end

	panel_for (a_key, a_title: READABLE_STRING_32; a_series: ARRAY [STRING_32]): TM_RESOURCE_PANEL
			-- The panel with `a_key', made on first sight.
		require
			key_given: not a_key.is_empty
			has_series: not a_series.is_empty
		local
			l_found: detachable TM_RESOURCE_PANEL
		do
			across panels as ic loop
				if ic.key.same_string (a_key) then
					l_found := ic
				end
			end
			if attached l_found as al_found then
				Result := al_found
			else
				create Result.make (a_key, a_title, a_series)
				add_panel (Result)
			end
		ensure
			present: has_panel (a_key)
		end

	push (a_panel: TM_RESOURCE_PANEL; a_series: INTEGER; a_reading: TM_READING)
			-- Add `a_reading' when it is available; nothing otherwise.
		require
			valid_series: a_series >= 1 and a_series <= a_panel.histories.count
		do
			if a_reading.is_available then
				a_panel.add_point (a_series, a_reading.value)
			end
		end

	text_of (a_r: TM_READINGS; a_code: INTEGER): STRING_32
			-- System-wide `a_code' as text, or why not.
		require
			system_wide: not metrics.metric (a_code).is_instanced
		do
			Result := format.reading_text (a_r.reading (a_code, {STRING_32} ""), metrics.metric (a_code))
		end

	instance_text (a_r: TM_READINGS; a_code: INTEGER; a_instance: READABLE_STRING_32): STRING_32
			-- `a_code' at `a_instance' as text, or why not.
		require
			instanced: metrics.metric (a_code).is_instanced
			named: not a_instance.is_empty
		do
			Result := format.reading_text (a_r.reading (a_code, a_instance), metrics.metric (a_code))
		end

	ghz (a_mhz: REAL_64): STRING_32
		do
			if a_mhz > 0.0 then
				Result := format.one_decimal (a_mhz / 1000.0) + {STRING_32} " GHz"
			else
				Result := {STRING_32} "unknown"
			end
		end

	installed_text: STRING_32
		do
			if machine.installed_memory_bytes > 0 then
				Result := format.bytes (machine.installed_memory_bytes)
			else
				Result := {STRING_32} "unknown"
			end
		end

	enabled (a_flag: BOOLEAN): STRING_32
		do
			if a_flag then
				Result := {STRING_32} "enabled"
			else
				Result := {STRING_32} "disabled"
			end
		end

	padded (a_label: READABLE_STRING_32): STRING_32
			-- `a_label' padded to the fact column.
		do
			create Result.make_from_string (a_label)
			from until Result.count >= 17 loop
				Result.append_character (' ')
			end
		end

end
