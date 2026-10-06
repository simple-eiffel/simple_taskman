note
	description: "[
		One headline tile: a statistic over a sparkline. While the metric is
		not available the tile shows the status words and the line stops
		moving (A-105): simple_widgets has no gap in a sparkline yet (W-1),
		and drawing a 0 would be the lie this tool exists to avoid.
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
			sparkline.set_capacity (60)
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

feature -- Element change

	show (a_reading: TM_READING; a_metric: TM_METRIC; a_suffix: READABLE_STRING_32)
			-- Show `a_reading' of `a_metric', with `a_suffix' after the value (an instance name, say).
		do
			statistic.set_value (format.reading_text (a_reading, a_metric) + a_suffix)
			if a_reading.is_available then
				sparkline.add_value (a_reading.value)
			end
		end

feature {NONE} -- Implementation

	format: TM_FORMAT

end
