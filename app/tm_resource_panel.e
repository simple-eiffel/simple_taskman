note
	description: "[
		One entry of the Performance tab: its title, a one-line summary for
		the list, the last minute of each of its series, and the fact lines
		shown beside its chart. A value that is not available adds no point:
		the line stops rather than dropping to 0 (A-105).
	]"
	author: "Larry Rix"

class
	TM_RESOURCE_PANEL

create
	make

feature {NONE} -- Initialization

	make (a_key, a_title: READABLE_STRING_32; a_series: ARRAY [STRING_32])
			-- Panel `a_key' titled `a_title' with one line per name in `a_series'.
		require
			key_given: not a_key.is_empty
			has_series: not a_series.is_empty
		do
			create key.make_from_string (a_key)
			create title.make_from_string (a_title)
			create summary.make_from_string ({STRING_32} "...")
			create series_names.make_from_array (a_series)
			create histories.make (a_series.count)
			across a_series as ic loop
				histories.extend (create {ARRAYED_LIST [REAL_64]}.make (Capacity))
			end
			create facts.make (12)
		ensure
			kept: key.same_string (a_key) and title.same_string (a_title)
			one_history_each: histories.count = series_names.count
		end

feature -- Access

	key: STRING_32
	title: STRING_32
	summary: STRING_32
	series_names: ARRAYED_LIST [STRING_32]
	histories: ARRAYED_LIST [ARRAYED_LIST [REAL_64]]
	facts: ARRAYED_LIST [STRING_32]

	Capacity: INTEGER = 60
			-- Points kept per series: a minute at the normal speed.

feature -- Element change

	set_summary (a_text: READABLE_STRING_32)
		do
			create summary.make_from_string (a_text)
		end

	add_point (a_series: INTEGER; a_value: REAL_64)
			-- Append `a_value' to series `a_series', dropping the oldest past `Capacity'.
		require
			valid_series: a_series >= 1 and a_series <= histories.count
		do
			histories [a_series].extend (a_value)
			if histories [a_series].count > Capacity then
				histories [a_series].start
				histories [a_series].remove
			end
		ensure
			bounded: histories [a_series].count <= Capacity
		end

	set_facts (a_lines: ARRAY [STRING_32])
		do
			create facts.make_from_array (a_lines)
		end

invariant
	one_history_each: histories.count = series_names.count

end
