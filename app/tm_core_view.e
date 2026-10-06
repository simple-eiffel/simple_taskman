note
	description: "[
		Per-core busy as a heatmap, shaped as the most nearly square grid of
		the logical processor count (32 gives 4 x 8; R-4). Rows are labelled
		P-core or E-core on a hybrid machine. A core with no reading this
		frame keeps its last colour; the title says how many were read.
	]"
	author: "Larry Rix"

class
	TM_CORE_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_topology: TM_CPU_TOPOLOGY)
			-- Heatmap for `a_topology'.
		local
			l_labels: ARRAYED_LIST [STRING_32]
			r, c: INTEGER
		do
			topology := a_topology
			rows := a_topology.heatmap_rows
			columns := a_topology.heatmap_columns
			create heatmap.make (rows, columns)
			create l_labels.make (rows)
			from r := 0 until r = rows loop
				l_labels.extend (row_label (r))
				r := r + 1
			end
			heatmap.set_row_labels (l_labels)
			create l_labels.make (columns)
			from c := 0 until c = columns loop
				l_labels.extend (c.out.to_string_32)
				c := c + 1
			end
			heatmap.set_col_labels (l_labels)
			heatmap.with_title ("Cores (" + a_topology.logical_processor_count.out + ")").do_nothing
		end

feature -- Access

	heatmap: SW_HEATMAP
	rows, columns: INTEGER
	cores_read: INTEGER
			-- Cores with a reading in the last frame.

feature -- Element change

	show (a_readings: TM_READINGS)
			-- Colour each core from its busy reading.
		local
			l_index: INTEGER
			l_reading: TM_READING
		do
			cores_read := 0
			across a_readings.instances ({TM_METRICS}.Cpu_core_busy_pct) as ic loop
				if ic.is_integer then
					l_index := ic.to_integer
					l_reading := a_readings.reading ({TM_METRICS}.Cpu_core_busy_pct, ic)
					if l_index >= 0 and l_index < rows * columns and l_reading.is_available then
						heatmap.set_cell (l_index // columns + 1, l_index \\ columns + 1, l_reading.value)
						cores_read := cores_read + 1
					end
				end
			end
		end

feature {NONE} -- Implementation

	topology: TM_CPU_TOPOLOGY

	row_label (a_row: INTEGER): STRING_32
			-- "0-7", or "P 0-7" / "E 8-15" on a hybrid machine.
		local
			l_first, l_last: INTEGER
		do
			l_first := a_row * columns
			l_last := (l_first + columns - 1).min (topology.logical_processor_count - 1)
			create Result.make (12)
			if topology.is_hybrid and l_first < topology.logical_processor_count then
				if topology.efficiency_class (l_first) > 0 then
					Result.append ({STRING_32} "P ")
				else
					Result.append ({STRING_32} "E ")
				end
			end
			Result.append (l_first.out.to_string_32 + {STRING_32} "-" + l_last.out.to_string_32)
		end

end
