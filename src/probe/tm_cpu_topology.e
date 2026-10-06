note
	description: "[
		Logical processors across every processor group, and each one's
		efficiency class (P-core or E-core on a hybrid machine). Beyond 64
		logical processors Windows uses groups and PDH names instances
		"group,number"; `flat_index' maps those to one index (R-4). Also the
		heatmap shape: the most nearly square grid for the count.
	]"
	author: "Larry Rix"

class
	TM_CPU_TOPOLOGY

create
	make,
	make_from_groups

feature {NONE} -- Initialization

	make
			-- Read this machine (GetActiveProcessorGroupCount, GetActiveProcessorCount,
			-- GetLogicalProcessorInformationEx).
		local
			l_groups: INTEGER
			l_sizes, l_classes: ARRAY [INTEGER]
			l_offsets, l_class_buffer: MANAGED_POINTER
			g, l_total, i: INTEGER
		do
			l_groups := c_group_count.max (1).min (Maximum_groups)
			create l_sizes.make_filled (0, 1, l_groups)
			create l_offsets.make (l_groups * 4)
			from
				g := 0
			until
				g = l_groups
			loop
				l_offsets.put_integer_32 (l_total, g * 4)
				l_sizes [g + 1] := c_group_size (g).max (1).min (Maximum_per_group)
				l_total := l_total + l_sizes [g + 1]
				g := g + 1
			end
			create l_class_buffer.make (l_total * 4)
			if c_fill_efficiency_classes (l_class_buffer.item, l_offsets.item, l_groups, l_total) then
				create l_classes.make_filled (0, 1, l_total)
				from
					i := 0
				until
					i = l_total
				loop
					l_classes [i + 1] := l_class_buffer.read_integer_32 (i * 4).max (0)
					i := i + 1
				end
			else
				create l_classes.make_filled (0, 1, l_total)
			end
			make_from_groups (l_sizes, l_classes)
		ensure
			some_processor: logical_processor_count > 0
		end

	make_from_groups (a_group_sizes: ARRAY [INTEGER]; a_efficiency_classes: ARRAY [INTEGER])
			-- Topology with `a_group_sizes' [g] processors in group g - 1, and
			-- `a_efficiency_classes' [i] the class of flat processor i - 1.
		require
			some_group: a_group_sizes.count > 0
			groups_bounded: a_group_sizes.count <= Maximum_groups
			sizes_valid: across a_group_sizes as ic all ic > 0 and ic <= Maximum_per_group end
			one_class_each: a_efficiency_classes.count = sum_of (a_group_sizes)
			classes_non_negative: across a_efficiency_classes as ic all ic >= 0 end
		do
			group_sizes := a_group_sizes.twin
			group_sizes.rebase (1)
			efficiency_classes := a_efficiency_classes.twin
			efficiency_classes.rebase (1)
			logical_processor_count := sum_of (a_group_sizes)
		ensure
			counted: logical_processor_count = sum_of (a_group_sizes)
			groups_kept: group_count = a_group_sizes.count
		end

feature -- Access

	logical_processor_count: INTEGER
			-- Logical processors in all groups.

	group_count: INTEGER
			-- Processor groups.
		do
			Result := group_sizes.count
		end

	group_size (a_group: INTEGER): INTEGER
			-- Processors in group `a_group' (0-based).
		require
			valid_group: a_group >= 0 and a_group < group_count
		do
			Result := group_sizes [a_group + 1]
		end

	efficiency_class (a_index: INTEGER): INTEGER
			-- Efficiency class of flat processor `a_index' (0-based); higher is faster.
		require
			valid_index: a_index >= 0 and a_index < logical_processor_count
		do
			Result := efficiency_classes [a_index + 1]
		end

	flat_index (a_group, a_number: INTEGER): INTEGER
			-- Flat 0-based index of processor `a_number' in group `a_group'.
		require
			valid_group: a_group >= 0 and a_group < group_count
			valid_number: a_number >= 0 and a_number < group_size (a_group)
		local
			g: INTEGER
		do
			from
				g := 0
			until
				g = a_group
			loop
				Result := Result + group_size (g)
				g := g + 1
			end
			Result := Result + a_number
		ensure
			inside: Result >= 0 and Result < logical_processor_count
		end

	heatmap_columns: INTEGER
			-- Columns of the most nearly square grid holding every processor (32 gives 8).
		do
			Result := (logical_processor_count + shape_rows - 1) // shape_rows
		ensure
			positive: Result > 0
			holds_all: Result * heatmap_rows >= logical_processor_count
			nearly_square: Result >= heatmap_rows
		end

	heatmap_rows: INTEGER
			-- Rows of that grid (32 gives 4).
		local
			l_columns: INTEGER
		do
			l_columns := heatmap_columns
			Result := (logical_processor_count + l_columns - 1) // l_columns
		ensure
			positive: Result > 0
			no_empty_row: (Result - 1) * heatmap_columns < logical_processor_count
		end

feature -- Status report

	is_hybrid: BOOLEAN
			-- Do processors differ in efficiency class?
		do
			Result := across efficiency_classes as ic some ic /= efficiency_classes [1] end
		end

feature -- Constants

	Maximum_groups: INTEGER = 16
			-- 16 groups of 64: 1,024 logical processors (R-4).

	Maximum_per_group: INTEGER = 64

feature -- Contract support

	sum_of (a_values: ARRAY [INTEGER]): INTEGER
			-- Sum of `a_values'.
		do
			across a_values as ic loop
				Result := Result + ic
			end
		end

feature {NONE} -- Implementation

	shape_rows: INTEGER
			-- Rows of the heatmap: the largest divisor of the count at or below its square
			-- root, when that gives at most two columns per row (32: 4 x 8); otherwise the
			-- rows of a near-square grid with one short row (31: 6 x 6).
		local
			r, c: INTEGER
		do
			from
				r := 1
			until
				(r + 1) * (r + 1) > logical_processor_count
			loop
				r := r + 1
			end
				-- r = floor of the square root
			Result := r
			from
			until
				logical_processor_count \\ Result = 0
			loop
				Result := Result - 1
			end
			if logical_processor_count // Result > 2 * Result then
				c := r
				if c * c < logical_processor_count then
					c := c + 1
				end
				Result := (logical_processor_count + c - 1) // c
			end
		ensure
			positive: Result > 0
		end

	group_sizes: ARRAY [INTEGER]
	efficiency_classes: ARRAY [INTEGER]
			-- Both 1-based.

feature {NONE} -- Externals

	c_group_count: INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				return (EIF_INTEGER) GetActiveProcessorGroupCount ();
			]"
		end

	c_group_size (a_group: INTEGER): INTEGER
		external
			"C inline use <windows.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				return (EIF_INTEGER) GetActiveProcessorCount ((WORD) $a_group);
			]"
		end

	c_fill_efficiency_classes (a_classes, a_offsets: POINTER; a_groups, a_count: INTEGER): BOOLEAN
			-- Write each logical processor's EfficiencyClass into `a_classes' (one 32-bit
			-- value per flat index; group g starts at `a_offsets' [g]). False when Windows
			-- will not describe its cores.
		external
			"C inline use <windows.h>, <stdlib.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				DWORD l_length = 0;
				char *l_buffer, *l_at;
				int *l_classes = (int *) $a_classes;
				int *l_offsets = (int *) $a_offsets;
				int i;
				for (i = 0; i < (int) $a_count; i++) l_classes [i] = 0;
				GetLogicalProcessorInformationEx (RelationProcessorCore, NULL, &l_length);
				if (GetLastError () != ERROR_INSUFFICIENT_BUFFER || l_length == 0) return EIF_FALSE;
				l_buffer = (char *) malloc (l_length);
				if (l_buffer == NULL) return EIF_FALSE;
				if (!GetLogicalProcessorInformationEx (RelationProcessorCore,
						(PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) l_buffer, &l_length)) {
					free (l_buffer);
					return EIF_FALSE;
				}
				for (l_at = l_buffer; l_at < l_buffer + l_length;
						l_at += ((PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) l_at)->Size) {
					PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX l_info = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX) l_at;
					if (l_info->Relationship == RelationProcessorCore) {
						WORD g;
						for (g = 0; g < l_info->Processor.GroupCount; g++) {
							GROUP_AFFINITY *l_mask = &l_info->Processor.GroupMask [g];
							int l_bit;
							if ((int) l_mask->Group >= (int) $a_groups) continue;
							for (l_bit = 0; l_bit < 64; l_bit++) {
								if (l_mask->Mask & (((KAFFINITY) 1) << l_bit)) {
									int l_index = l_offsets [l_mask->Group] + l_bit;
									if (l_index < (int) $a_count) l_classes [l_index] = (int) l_info->Processor.EfficiencyClass;
								}
							}
						}
					}
				}
				free (l_buffer);
				return EIF_TRUE;
			]"
		end

invariant
	some_processor: logical_processor_count > 0
	bounded: logical_processor_count <= Maximum_groups * Maximum_per_group
	one_class_each: efficiency_classes.count = logical_processor_count

end
