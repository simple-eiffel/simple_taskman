note
	description: "[
		What this machine can and cannot measure, and why; and which process
		table is in use. Labels are made once and only their text changes (A-108).
	]"
	author: "Larry Rix"

class
	TM_CAPABILITY_VIEW

inherit
	TM_SHARED_METRICS

create
	make

feature {NONE} -- Initialization

	make
			-- Panel with a line per hardware metric, all pending.
		do
			create group.make_titled ("This machine measures")
			create lines.make (Shown_codes.count + 1)
			across Shown_codes as ic loop
				lines.extend (create {SW_LABEL}.make_ui (metrics.metric (ic).label + {STRING_32} ": ..."))
				group.put (lines.last)
			end
			lines.extend (create {SW_LABEL}.make_ui ("Process table: ..."))
			group.put (lines.last)
		end

feature -- Access

	group: SW_GROUP
			-- The panel widget.

feature -- Element change

	show (a_capabilities: TM_CAPABILITIES)
			-- One line per shown metric: a tick and the label, or a cross and the reason.
		do
			across Shown_codes as ic loop
				if a_capabilities.has (ic) then
					if a_capabilities.is_supported (ic) then
						lines [@ic.cursor_index].set_text (Tick + {STRING_32} " " + metrics.metric (ic).label)
						lines [@ic.cursor_index].set_muted (False)
					else
						lines [@ic.cursor_index].set_text (Cross + {STRING_32} " " + metrics.metric (ic).label
							+ {STRING_32} ": " + a_capabilities.reason_of (ic))
						lines [@ic.cursor_index].set_muted (True)
					end
				end
			end
			if a_capabilities.fallback_reason.is_empty then
				lines.last.set_text ({STRING_32} "Process table: " + a_capabilities.process_source_kind.to_string_32
					+ {STRING_32} ", self-check passed")
			else
				lines.last.set_text ({STRING_32} "Process table: " + a_capabilities.process_source_kind.to_string_32
					+ {STRING_32} " (native refused: " + a_capabilities.fallback_reason + {STRING_32} ")")
			end
		end

	show_replay (a_path: READABLE_STRING_32)
			-- Replay mode: no live machine behind the frames, so no capability report.
		do
			across Shown_codes as ic loop
				lines [@ic.cursor_index].set_text (metrics.metric (ic).label + {STRING_32} ": as recorded")
				lines [@ic.cursor_index].set_muted (True)
			end
			lines.last.set_text ({STRING_32} "Replaying " + a_path)
		end

feature {NONE} -- Implementation

	lines: ARRAYED_LIST [SW_LABEL]

	Shown_codes: ARRAY [INTEGER]
			-- Hardware metrics the panel lists; the self.* metrics belong to the status bar.
		once
			Result := <<{TM_METRICS}.Cpu_core_busy_pct, {TM_METRICS}.Cpu_utility_pct, {TM_METRICS}.Mem_commit_pct,
				{TM_METRICS}.Mem_hard_faults_per_s, {TM_METRICS}.Disk_busy_pct, {TM_METRICS}.Volume_free_bytes,
				{TM_METRICS}.Cpu_package_watts, {TM_METRICS}.Gpu_busy_pct, {TM_METRICS}.Temperature_c, {TM_METRICS}.Battery_pct>>
		end

	Tick: STRING_32 = "+"
			-- Measured. Plain ASCII: the UI font has no check-mark glyph (seen as an empty box).

	Cross: STRING_32 = "x"
			-- Not measured; the reason follows.

end
