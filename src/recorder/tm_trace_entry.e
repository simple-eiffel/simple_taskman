note
	description: "[
		Bookkeeping for one stored frame: its row id, span, tier, and flags,
		without the payload. Retention plans over entries, never over frames.
	]"
	author: "Larry Rix"

class
	TM_TRACE_ENTRY

create
	make

feature {NONE} -- Initialization

	make (a_id, a_start, a_end: INTEGER_64; a_tier: INTEGER; a_pinned, a_discontinuity: BOOLEAN)
			-- Entry for stored frame `a_id'.
		require
			id_positive: a_id > 0
			ordered: a_end > a_start
			valid_tier: a_tier >= 0 and a_tier < {TM_RETENTION_POLICY}.Tier_count
		do
			id := a_id
			start_ticks := a_start
			end_ticks := a_end
			tier := a_tier
			is_pinned := a_pinned
			is_discontinuity := a_discontinuity
		ensure
			kept: id = a_id and start_ticks = a_start and end_ticks = a_end and tier = a_tier
				and is_pinned = a_pinned and is_discontinuity = a_discontinuity
		end

feature -- Access

	id: INTEGER_64
			-- Row id in the store.

	start_ticks, end_ticks: INTEGER_64
			-- Span on the recording's timeline.

	tier: INTEGER
			-- 0, 1, or 2.

feature -- Status report

	is_pinned: BOOLEAN
			-- Never merged or deleted?

	is_discontinuity: BOOLEAN
			-- A gap frame (sleep, stall)?

invariant
	id_positive: id > 0
	ordered: end_ticks > start_ticks
	valid_tier: tier >= 0 and tier < {TM_RETENTION_POLICY}.Tier_count

end
