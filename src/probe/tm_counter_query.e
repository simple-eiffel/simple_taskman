note
	description: "[
		One PDH query: add counters by their English path (so the tool works
		on any display language), collect, and read each counter's instances.
		The query handle is a POINTER attribute of this object; no header
		statics (C-007). Close it explicitly.
	]"
	author: "Larry Rix"

class
	TM_COUNTER_QUERY

create
	make

feature {NONE} -- Initialization

	make
			-- Open an empty query (PdhOpenQueryW).
		local
			l_out: MANAGED_POINTER
		do
			create counters.make (16)
			create formats.make (16)
			create l_out.make (Pointer_bytes)
			last_status := c_open (l_out.item)
			if last_status = Pdh_ok then
				handle := l_out.read_pointer (0)
			end
		ensure
			empty: counter_count = 0 and collections = 0
			open: not is_closed
		end

feature -- Access

	counter_count: INTEGER
			-- Counters added so far.

	collections: INTEGER
			-- Times `collect' has run.

	last_status: INTEGER
			-- PDH status of the last call; `Pdh_ok' on success.

	values (a_counter: INTEGER): ARRAYED_LIST [TM_COUNTER_VALUE]
			-- Every instance of counter `a_counter' from the last collection; a fresh list.
			-- Empty when PDH has nothing to give (for example a rate after one collection).
		require
			valid_counter: a_counter >= 1 and a_counter <= counter_count
			collected: collections >= 1
		local
			l_sizes: MANAGED_POINTER
			l_buffer: MANAGED_POINTER
			l_status, i, l_count: INTEGER
		do
			create Result.make (0)
			create l_sizes.make (8)
			l_status := c_array (counters [a_counter], formats [a_counter], l_sizes.item, default_pointer)
			if l_status = Pdh_more_data and then l_sizes.read_natural_32 (0) > 0 then
				create l_buffer.make (l_sizes.read_natural_32 (0).to_integer_32)
				l_status := c_array (counters [a_counter], formats [a_counter], l_sizes.item, l_buffer.item)
				if l_status = Pdh_ok then
					l_count := l_sizes.read_natural_32 (4).to_integer_32
					create Result.make (l_count)
					from
						i := 0
					until
						i = l_count
					loop
						Result.extend (create {TM_COUNTER_VALUE}.make (instance_name (c_item_name (l_buffer.item, i)),
							c_item_value (l_buffer.item, i), c_item_status (l_buffer.item, i)))
						i := i + 1
					end
				end
			end
		ensure
			fresh: Result /= values (a_counter)
		end

feature -- Status report

	is_closed: BOOLEAN
			-- Was the query closed?

feature -- Element change

	add_english (a_path: READABLE_STRING_GENERAL): INTEGER
			-- Add counter `a_path' (PdhAddEnglishCounterW). Its index, or 0 when refused.
			-- CQS exception: the index is the handle to what was added, like a creation result.
		require
			open: not is_closed
			path_given: not a_path.is_empty
		do
			add_counter (a_path, Pdh_fmt_double)
			Result := last_added
		ensure
			added_or_zero: (Result > 0) = (last_status = Pdh_ok)
			counted: Result > 0 implies (counter_count = old counter_count + 1 and Result = counter_count)
			unchanged_on_refusal: Result = 0 implies counter_count = old counter_count
		end

	add_english_uncapped (a_path: READABLE_STRING_GENERAL): INTEGER
			-- As `add_english', but values may exceed 100 (PDH_FMT_NOCAP100), for
			-- frequency-aware counters such as "% Processor Utility".
		require
			open: not is_closed
			path_given: not a_path.is_empty
		do
			add_counter (a_path, Pdh_fmt_double | Pdh_fmt_nocap100)
			Result := last_added
		ensure
			added_or_zero: (Result > 0) = (last_status = Pdh_ok)
			counted: Result > 0 implies (counter_count = old counter_count + 1 and Result = counter_count)
			unchanged_on_refusal: Result = 0 implies counter_count = old counter_count
		end

feature -- Basic operations

	collect
			-- Take one collection of every counter (PdhCollectQueryData). Blocking (C-015).
		require
			open: not is_closed
			has_counters: counter_count > 0
		do
			last_status := c_collect (handle)
			collections := collections + 1
		ensure
			collected: collections = old collections + 1
		end

	close
			-- Release the query (PdhCloseQuery).
		do
			if handle /= default_pointer then
				c_close (handle).do_nothing
				handle := default_pointer
			end
			is_closed := True
		ensure
			closed: is_closed
			handle_released: handle = default_pointer
		end

feature -- Constants

	Pdh_ok: INTEGER = 0
			-- ERROR_SUCCESS.

	Pdh_not_opened: INTEGER = -1
			-- Our own marker: the query was never opened.

	Pdh_more_data: INTEGER = -2147481646
			-- PDH_MORE_DATA (0x800007D2) as a signed 32-bit value.

	Pdh_fmt_double: INTEGER = 0x200
	Pdh_fmt_nocap100: INTEGER = 0x8000

feature {NONE} -- Implementation

	handle: POINTER
			-- PDH_HQUERY; null until opened.

	counters: ARRAYED_LIST [POINTER]
			-- PDH_HCOUNTER per added counter, by index.

	formats: ARRAYED_LIST [INTEGER]
			-- Format flags per added counter.

	last_added: INTEGER
			-- Index given by the last `add_counter', or 0 when it was refused.

	add_counter (a_path: READABLE_STRING_GENERAL; a_format: INTEGER)
			-- Add `a_path' with `a_format'; leave its index, or 0, in `last_added'.
		local
			l_path: NATIVE_STRING
			l_out: MANAGED_POINTER
		do
			last_added := 0
			create l_path.make (a_path)
			create l_out.make (Pointer_bytes)
			last_status := c_add (handle, l_path.item, l_out.item)
			if last_status = Pdh_ok then
				counters.extend (l_out.read_pointer (0))
				formats.extend (a_format)
				counter_count := counter_count + 1
				last_added := counter_count
			end
		ensure
			index_or_zero: (last_added > 0) = (last_status = Pdh_ok)
		end

	instance_name (a_name: POINTER): STRING_32
			-- The UTF-16 instance name at `a_name', or empty.
		do
			if a_name = default_pointer then
				create Result.make_empty
			else
				Result := (create {NATIVE_STRING}.make_from_pointer (a_name)).string
			end
		end

	Pointer_bytes: INTEGER = 8

feature {NONE} -- Externals

	c_open (a_out: POINTER): INTEGER
		external
			"C inline use <windows.h>, <pdh.h>"
		alias
			"return (EIF_INTEGER) PdhOpenQueryW (NULL, 0, (PDH_HQUERY *) $a_out);"
		end

	c_add (a_query, a_path, a_out: POINTER): INTEGER
		external
			"C inline use <windows.h>, <pdh.h>"
		alias
			"[
				#if _WIN32_WINNT < 0x0602
				#error "simple_taskman needs _WIN32_WINNT >= 0x0602 (Windows 8 API): keep the external_cflag of simple_taskman.ecf"
				#endif
				return (EIF_INTEGER) PdhAddEnglishCounterW ((PDH_HQUERY) $a_query, (LPCWSTR) $a_path, 0, (PDH_HCOUNTER *) $a_out);
			]"
		end

	c_collect (a_query: POINTER): INTEGER
			-- Blocking: PDH may wait on providers (C-015).
		external
			"C blocking inline use <windows.h>, <pdh.h>"
		alias
			"return (EIF_INTEGER) PdhCollectQueryData ((PDH_HQUERY) $a_query);"
		end

	c_close (a_query: POINTER): INTEGER
		external
			"C inline use <windows.h>, <pdh.h>"
		alias
			"return (EIF_INTEGER) PdhCloseQuery ((PDH_HQUERY) $a_query);"
		end

	c_array (a_counter: POINTER; a_format: INTEGER; a_sizes, a_buffer: POINTER): INTEGER
			-- PdhGetFormattedCounterArrayW; `a_sizes' holds the byte size (in/out) then the item count.
		external
			"C inline use <windows.h>, <pdh.h>"
		alias
			"[
				DWORD *l_sizes = (DWORD *) $a_sizes;
				if ($a_buffer == NULL) { l_sizes [0] = 0; l_sizes [1] = 0; }
				return (EIF_INTEGER) PdhGetFormattedCounterArrayW ((PDH_HCOUNTER) $a_counter, (DWORD) $a_format,
					&l_sizes [0], &l_sizes [1], (PPDH_FMT_COUNTERVALUE_ITEM_W) $a_buffer);
			]"
		end

	c_item_name (a_buffer: POINTER; a_index: INTEGER): POINTER
		external
			"C inline use <windows.h>, <pdh.h>"
		alias
			"return (EIF_POINTER) ((PPDH_FMT_COUNTERVALUE_ITEM_W) $a_buffer) [$a_index].szName;"
		end

	c_item_status (a_buffer: POINTER; a_index: INTEGER): INTEGER
		external
			"C inline use <windows.h>, <pdh.h>"
		alias
			"return (EIF_INTEGER) ((PPDH_FMT_COUNTERVALUE_ITEM_W) $a_buffer) [$a_index].FmtValue.CStatus;"
		end

	c_item_value (a_buffer: POINTER; a_index: INTEGER): REAL_64
		external
			"C inline use <windows.h>, <pdh.h>"
		alias
			"return (EIF_REAL_64) ((PPDH_FMT_COUNTERVALUE_ITEM_W) $a_buffer) [$a_index].FmtValue.doubleValue;"
		end

invariant
	counts_non_negative: counter_count >= 0 and collections >= 0

end
