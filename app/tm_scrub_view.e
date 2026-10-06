note
	description: "[
		The DVR strip (Phase 2): a slider over the recorded time, the moment
		under it in local clock time, and a Live button. Dragging calls
		`on_scrub' with a timeline instant; Live calls `on_live'. While
		scrubbing, a growing recording does not move the chosen moment.
	]"
	author: "Larry Rix"

class
	TM_SCRUB_VIEW

create
	make

feature {NONE} -- Initialization

	make
			-- Strip with no handlers yet (see `set_handlers').
		do
			create title.make_ui ("History")
			create slider.make (1.0, Void)
			slider.set_grow (1.0)
			create position.make_mono ("no recording yet")
			create live_button.make ("Live", Void)
			create row.make
			row := row.with_gap (10.0)
			row.put (title)
			row.put (slider)
			row.put (position)
			row.put (live_button)
			slider.set_on_change (agent moved)
			live_button.set_on_click (agent go_live)
		ensure
			live: not is_scrubbing
		end

feature -- Access

	row: SW_ROW
			-- The strip widget.

	earliest_ticks, latest_ticks: INTEGER_64
			-- Recorded span the slider covers.

	scrub_ticks: INTEGER_64
			-- The chosen moment while scrubbing.

	clock_time (a_ticks: INTEGER_64): STRING_32
			-- `a_ticks' (UTC, 100 ns since 1601) as local "MM/DD HH:MM:SS".
		do
			Result := (create {TM_LOCAL_TIME}).text (a_ticks)
		end

feature -- Status report

	is_scrubbing: BOOLEAN
			-- Is a recorded moment chosen instead of live?

feature -- Element change

	set_handlers (a_on_scrub: PROCEDURE [INTEGER_64]; a_on_live: PROCEDURE)
			-- Report scrubbing to `a_on_scrub' and the Live button to `a_on_live'.
		do
			on_scrub := a_on_scrub
			on_live := a_on_live
		ensure
			kept: on_scrub = a_on_scrub and on_live = a_on_live
		end

	set_span (a_earliest, a_latest: INTEGER_64; a_note: READABLE_STRING_32)
			-- The recording now covers [`a_earliest', `a_latest']; `a_note' describes it while live.
		require
			ordered: a_latest >= a_earliest
		do
			earliest_ticks := a_earliest
			latest_ticks := a_latest
			if is_scrubbing then
				if a_latest > a_earliest then
					slider.set_fraction (((scrub_ticks - a_earliest).to_double / (a_latest - a_earliest).to_double).max (0.0).min (1.0))
				end
			else
				slider.set_fraction (1.0)
				position.set_text (a_note)
			end
		ensure
			kept: earliest_ticks = a_earliest and latest_ticks = a_latest
		end

	scrub_to (a_ticks: INTEGER_64)
			-- Choose the moment `a_ticks' as if the slider had been dragged there.
		require
			recorded: latest_ticks > earliest_ticks
		do
			is_scrubbing := True
			scrub_ticks := a_ticks.max (earliest_ticks).min (latest_ticks)
			slider.set_fraction (((scrub_ticks - earliest_ticks).to_double / (latest_ticks - earliest_ticks).to_double).max (0.0).min (1.0))
			if attached on_scrub as al_action then
				al_action.call ([scrub_ticks])
			end
		ensure
			scrubbing: is_scrubbing
		end

	show_moment (a_ticks: INTEGER_64; a_note: READABLE_STRING_32)
			-- Label the chosen moment.
		do
			position.set_text (clock_time (a_ticks) + {STRING_32} "  " + a_note)
		end

feature {NONE} -- Widgets

	title: SW_LABEL
	slider: SW_SLIDER
	position: SW_LABEL
	live_button: SW_BUTTON

	on_scrub: detachable PROCEDURE [INTEGER_64]
	on_live: detachable PROCEDURE

feature {NONE} -- Actions

	moved (a_fraction: REAL_64)
			-- The slider moved to `a_fraction'.
		do
			if latest_ticks > earliest_ticks then
				is_scrubbing := True
				scrub_ticks := earliest_ticks + ((latest_ticks - earliest_ticks).to_double * a_fraction).truncated_to_integer_64
				if attached on_scrub as al_action then
					al_action.call ([scrub_ticks])
				end
			end
		end

	go_live
			-- The Live button.
		do
			is_scrubbing := False
			slider.set_fraction (1.0)
			if attached on_live as al_action then
				al_action.call (Void)
			end
		ensure
			live: not is_scrubbing
		end

end
