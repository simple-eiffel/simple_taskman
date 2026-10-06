note
	description: "[
		One headline tile: a statistic over a sparkline. While the metric is
		not available the tile shows the status words and the line stops
		moving (A-105): simple_widgets has no gap in a sparkline yet (W-1),
		and drawing a 0 would be the lie this tool exists to avoid.

		History mode (Phase 2 DVR): `show_history' paints a recorded moment
		and the minute before it; live values keep arriving through `show'
		and are kept aside, and `show_live' puts them back.
	]"
	author: "Larry Rix"

class
	TM_TREND_VIEW

create
	make

feature {NONE} -- Initialization

	make (a_label: READABLE_STRING_GENERAL)
			-- Tile titled `a_label'.
		do
			create statistic.make (a_label, "...")
			create sparkline.make
			sparkline.set_capacity (Capacity)
			create live_values.make (Capacity)
			create live_text.make_from_string ({STRING_32} "...")
			create column.make
			column.put (statistic)
			column.put (sparkline)
			column.set_grow (1.0)
			create format
		end

feature -- Access

	column: SW_COLUMN
			-- The tile widget.

	statistic: SW_STATISTIC
	sparkline: SW_SPARKLINE

	Capacity: INTEGER = 60
			-- Points on the line.

feature -- Status report

	is_showing_history: BOOLEAN
			-- Is a recorded moment on the tile instead of the live value?

feature -- Element change

	show (a_reading: TM_READING; a_metric: TM_METRIC; a_suffix: READABLE_STRING_32)
			-- Live `a_reading' of `a_metric', with `a_suffix' after the value (an instance name, say).
			-- In history mode it is kept for `show_live' and not painted.
		do
			live_text := format.reading_text (a_reading, a_metric) + a_suffix
			if a_reading.is_available then
				live_values.extend (a_reading.value)
				if live_values.count > Capacity then
					live_values.start
					live_values.remove
				end
			end
			if not is_showing_history then
				statistic.set_value (live_text)
				if a_reading.is_available then
					sparkline.add_value (a_reading.value)
				end
			end
		ensure
			bounded: live_values.count <= Capacity
		end

	show_history (a_reading: TM_READING; a_metric: TM_METRIC; a_suffix: READABLE_STRING_32; a_before: ITERABLE [REAL_64])
			-- Recorded `a_reading' with the available values of the minute before it, oldest first.
		do
			is_showing_history := True
			statistic.set_value (format.reading_text (a_reading, a_metric) + a_suffix)
			sparkline.values.wipe_out
			across a_before as ic loop
				sparkline.add_value (ic)
			end
		ensure
			history: is_showing_history
		end

	show_live
			-- Back to the live value and the live line.
		do
			is_showing_history := False
			statistic.set_value (live_text)
			sparkline.values.wipe_out
			across live_values as ic loop
				sparkline.add_value (ic)
			end
		ensure
			live: not is_showing_history
		end

feature {NONE} -- Implementation

	format: TM_FORMAT

	live_values: ARRAYED_LIST [REAL_64]
			-- The live line, kept while history is shown.

	live_text: STRING_32
			-- The live statistic, kept while history is shown.

invariant
	bounded: live_values.count <= Capacity

end
