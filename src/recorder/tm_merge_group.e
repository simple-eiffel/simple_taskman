note
	description: "[
		Frames a retention pass turns into one frame of the next tier. A group
		of one is only moved to the next tier (a gap frame, or a bucket that
		held a single frame); a larger group is merged.
	]"
	author: "Larry Rix"

class
	TM_MERGE_GROUP

create
	make

feature {NONE} -- Initialization

	make (a_target_tier: INTEGER)
			-- Empty group bound for `a_target_tier'.
		require
			coarser_tier: a_target_tier >= 1 and a_target_tier < {TM_RETENTION_POLICY}.Tier_count
		do
			target_tier := a_target_tier
			create ids.make (16)
		ensure
			tier_kept: target_tier = a_target_tier
			empty: ids.is_empty
		end

feature -- Access

	target_tier: INTEGER
			-- Tier the result goes to.

	ids: ARRAYED_LIST [INTEGER_64]
			-- Row ids, oldest first.

feature -- Status report

	is_move_only: BOOLEAN
			-- One frame, moved to the next tier without merging?
		do
			Result := ids.count = 1
		end

feature -- Element change

	extend (a_id: INTEGER_64)
			-- Add row `a_id' as the newest member.
		require
			id_positive: a_id > 0
			new_member: not ids.has (a_id)
		do
			ids.extend (a_id)
		ensure
			added: ids.count = old ids.count + 1 and ids.last = a_id
		end

invariant
	coarser_tier: target_tier >= 1 and target_tier < {TM_RETENTION_POLICY}.Tier_count

end
