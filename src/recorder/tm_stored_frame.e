note
	description: "A frame held by TM_MEMORY_TRACE_STORE, with its row id, tier, and pin."
	author: "Larry Rix"

class
	TM_STORED_FRAME

create
	make

feature {NONE} -- Initialization

	make (a_id: INTEGER_64; a_frame: TM_FRAME; a_tier: INTEGER)
			-- Frame `a_frame' stored as row `a_id' in tier `a_tier', not pinned.
		require
			id_positive: a_id > 0
			valid_tier: a_tier >= 0 and a_tier < {TM_RETENTION_POLICY}.Tier_count
		do
			id := a_id
			frame := a_frame
			tier := a_tier
		ensure
			kept: id = a_id and frame = a_frame and tier = a_tier
			unpinned: not is_pinned
		end

feature -- Access

	id: INTEGER_64
	frame: TM_FRAME
	tier: INTEGER

	entry: TM_TRACE_ENTRY
			-- Bookkeeping for this frame.
		do
			create Result.make (id, frame.start_ticks, frame.end_ticks, tier, is_pinned, frame.is_discontinuity)
		ensure
			same_id: Result.id = id and Result.tier = tier and Result.is_pinned = is_pinned
		end

feature -- Status report

	is_pinned: BOOLEAN

feature -- Element change

	set_pinned
			-- Never merge or delete this frame.
		do
			is_pinned := True
		ensure
			pinned: is_pinned
		end

	set_tier (a_tier: INTEGER)
			-- Move to tier `a_tier'.
		require
			valid_tier: a_tier >= 0 and a_tier < {TM_RETENTION_POLICY}.Tier_count
		do
			tier := a_tier
		ensure
			moved: tier = a_tier
		end

invariant
	id_positive: id > 0
	valid_tier: tier >= 0 and tier < {TM_RETENTION_POLICY}.Tier_count

end
