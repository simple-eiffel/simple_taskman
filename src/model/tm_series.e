note
	description: "[
		Compact history of one metric, for drawing a trend: a bounded ring of
		timestamp, value, and status. Deliberately not generic: it stores a
		REAL_64 and a status byte per entry, which is the whole point (D-006).
		Gaps stay gaps; an entry whose status is not available has no value.
	]"
	author: "Larry Rix"

class
	TM_SERIES

create
	make

feature {NONE} -- Initialization

	make (a_capacity: INTEGER)
			-- Empty series keeping at most `a_capacity' entries.
		require
			positive: a_capacity > 0
		do
			capacity := a_capacity
			create ticks.make_filled (0, a_capacity)
			create values.make_filled (0.0, a_capacity)
			create statuses.make_filled ({INTEGER_8} 0, a_capacity)
		ensure
			empty: count = 0
			capacity_kept: capacity = a_capacity
		end

feature -- Access

	capacity: INTEGER
			-- Most entries kept.

	count: INTEGER
			-- Entries held.

	ticks_at (i: INTEGER): INTEGER_64
			-- Timestamp of entry `i' (1 is oldest).
		require
			in_range: i >= 1 and i <= count
		do
			Result := ticks [physical (i)]
		end

	status_at (i: INTEGER): INTEGER
			-- Status of entry `i'.
		require
			in_range: i >= 1 and i <= count
		do
			Result := statuses [physical (i)].to_integer_32
		ensure
			known: Result >= {TM_READING_STATUS}.Available and Result <= {TM_READING_STATUS}.Invalid
		end

	value_at (i: INTEGER): REAL_64
			-- Value of entry `i'.
		require
			in_range: i >= 1 and i <= count
			available: is_available_at (i)
		do
			Result := values [physical (i)]
		end

	last_ticks: INTEGER_64
			-- Timestamp of the newest entry.
		require
			not_empty: count > 0
		do
			Result := ticks_at (count)
		end

feature -- Status report

	is_available_at (i: INTEGER): BOOLEAN
			-- Does entry `i' carry a value?
		require
			in_range: i >= 1 and i <= count
		do
			Result := status_at (i) = {TM_READING_STATUS}.Available
		end

feature -- Element change

	extend (a_ticks: INTEGER_64; a_reading: TM_READING)
			-- Append `a_reading' taken at `a_ticks'; drop the oldest entry when full.
		require
			in_order: count > 0 implies a_ticks > last_ticks
		local
			l_slot: INTEGER
		do
			if count < capacity then
				l_slot := (first + count) \\ capacity
				count := count + 1
			else
				l_slot := first
				first := (first + 1) \\ capacity
			end
			ticks [l_slot] := a_ticks
			statuses [l_slot] := a_reading.status.to_integer_8
			if a_reading.is_available then
				values [l_slot] := a_reading.value
			else
				values [l_slot] := 0.0
			end
		ensure
			bounded: count = (old count + 1).min (capacity)
			newest_ticks: ticks_at (count) = a_ticks
			newest_status: status_at (count) = a_reading.status
			newest_value: a_reading.is_available implies value_at (count) = a_reading.value
			history_kept: old count < capacity implies
				across 1 |..| (old count) as ic all status_at (ic) = (old statuses_list).i_th (ic) end
			oldest_dropped: old count = capacity implies
				across 1 |..| (count - 1) as ic all status_at (ic) = (old statuses_list).i_th (ic + 1) end
		end

feature -- Model

	statuses_model: MML_SEQUENCE [INTEGER]
			-- Statuses, oldest first.
		local
			i: INTEGER
		do
			create Result
			from
				i := 1
			until
				i > count
			loop
				Result := Result & status_at (i)
				i := i + 1
			end
		ensure
			same_count: Result.count = count
		end

	statuses_list: ARRAYED_LIST [INTEGER]
			-- Statuses, oldest first; a fresh list. O(n), for frame conditions.
		local
			i: INTEGER
		do
			create Result.make (count)
			from
				i := 1
			until
				i > count
			loop
				Result.extend (status_at (i))
				i := i + 1
			end
		ensure
			same_count: Result.count = count
		end

feature {NONE} -- Implementation

	ticks: SPECIAL [INTEGER_64]
	values: SPECIAL [REAL_64]
	statuses: SPECIAL [INTEGER_8]
			-- Ring storage, all of length `capacity'.

	first: INTEGER
			-- Physical index (0-based) of the oldest entry.

	physical (i: INTEGER): INTEGER
			-- Physical index of logical entry `i'.
		require
			in_range: i >= 1 and i <= count
		do
			Result := (first + i - 1) \\ capacity
		ensure
			inside: Result >= 0 and Result < capacity
		end

invariant
	positive_capacity: capacity > 0
	non_negative: count >= 0
	bounded: count <= capacity
	first_inside: first >= 0 and first < capacity
	storage_sized: ticks.count = capacity and values.count = capacity and statuses.count = capacity

end
