note
	description: "[
		Pure planner for one retention step of one tier. Given stored entries
		oldest first, it groups the unpinned frames of tier T that ended at or
		before the cutoff by their tier T+1 bucket. A run breaks at a bucket
		boundary, at a pinned frame, at a frame of another tier, and at a gap
		frame, which moves on alone. Each call advances frames one tier;
		repeated passes catch up after a long absence.
	]"
	author: "Larry Rix"

class
	TM_RETENTION_PLANNER

create
	make

feature {NONE} -- Initialization

	make (a_policy: TM_RETENTION_POLICY)
			-- Planner using `a_policy' buckets.
		do
			policy := a_policy
		ensure
			policy_kept: policy = a_policy
		end

feature -- Access

	policy: TM_RETENTION_POLICY

	groups (a_entries: ARRAYED_LIST [TM_TRACE_ENTRY]; a_tier: INTEGER; a_cutoff: INTEGER_64): ARRAYED_LIST [TM_MERGE_GROUP]
			-- Groups that move tier `a_tier' frames ending at or before `a_cutoff' into tier `a_tier' + 1.
		require
			mergeable_tier: a_tier >= 0 and a_tier < policy.Tier_count - 1
			ordered: across 2 |..| a_entries.count as ic all a_entries [ic].start_ticks >= a_entries [ic - 1].end_ticks end
			not_before_epoch: across a_entries as ic all ic.start_ticks >= 0 end
		local
			l_run: detachable TM_MERGE_GROUP
			l_group: TM_MERGE_GROUP
			l_bucket, l_run_bucket: INTEGER_64
		do
			create Result.make (8)
			across a_entries as e loop
				if not qualifies (e, a_tier, a_cutoff) then
					l_run := Void
				elseif e.is_discontinuity then
					create l_group.make (a_tier + 1)
					l_group.extend (e.id)
					Result.extend (l_group)
					l_run := Void
				else
					l_bucket := policy.bucket_of (e.start_ticks, a_tier + 1)
					if attached l_run as al_run and then l_bucket = l_run_bucket then
						al_run.extend (e.id)
					else
						create l_group.make (a_tier + 1)
						l_group.extend (e.id)
						Result.extend (l_group)
						l_run := l_group
						l_run_bucket := l_bucket
					end
				end
			end
		ensure
			target: across Result as g all g.target_tier = a_tier + 1 end
			not_empty: across Result as g all not g.ids.is_empty end
			members_qualify: across Result as g all across g.ids as id all qualifies (entry_with (a_entries, id), a_tier, a_cutoff) end end
			gaps_alone: across Result as g all
				(g.ids.count > 1 implies across g.ids as id all not entry_with (a_entries, id).is_discontinuity end) end
			one_bucket: across Result as g all across g.ids as id all
				policy.bucket_of (entry_with (a_entries, id).start_ticks, a_tier + 1) = policy.bucket_of (entry_with (a_entries, g.ids.first).start_ticks, a_tier + 1) end end
			every_qualifier_once: across a_entries as e all qualifies (e, a_tier, a_cutoff) implies membership_count (Result, e.id) = 1 end
		end

feature -- Contract support

	qualifies (a_entry: TM_TRACE_ENTRY; a_tier: INTEGER; a_cutoff: INTEGER_64): BOOLEAN
			-- Is `a_entry' an unpinned tier `a_tier' frame that ended by `a_cutoff'?
		do
			Result := a_entry.tier = a_tier and not a_entry.is_pinned and a_entry.end_ticks <= a_cutoff
		end

	entry_with (a_entries: ARRAYED_LIST [TM_TRACE_ENTRY]; a_id: INTEGER_64): TM_TRACE_ENTRY
			-- The entry with id `a_id'.
		require
			present: across a_entries as ic some ic.id = a_id end
		do
			Result := a_entries.first
			across a_entries as ic loop
				if ic.id = a_id then
					Result := ic
				end
			end
		ensure
			found: Result.id = a_id
		end

	membership_count (a_groups: ARRAYED_LIST [TM_MERGE_GROUP]; a_id: INTEGER_64): INTEGER
			-- In how many groups does `a_id' appear?
		do
			across a_groups as g loop
				if g.ids.has (a_id) then
					Result := Result + 1
				end
			end
		end

end
