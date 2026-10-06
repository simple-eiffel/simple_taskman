note
	description: "[
		Trace store held in memory, for tests and for replay. Frames are kept
		decoded; retention uses the same planner and merger as the SQLite
		store. The size cap does not apply here: there is no file.
	]"
	author: "Larry Rix"

class
	TM_MEMORY_TRACE_STORE

inherit
	TM_TRACE_STORE

create
	make

feature {NONE} -- Initialization

	make (a_policy: TM_RETENTION_POLICY)
			-- Empty, writable store using `a_policy'.
		do
			policy := a_policy
			create merger.make (a_policy)
			create planner.make (a_policy)
			create last_error.make_empty
			create stored.make (64)
			is_open := True
			is_writable := True
		ensure
			policy_kept: policy = a_policy
			empty: is_empty
			writable: is_writable
		end

feature -- Access

	window (a_from, a_to: INTEGER_64): TM_WINDOW
		do
			create Result.make
			across stored as ic loop
				if ic.frame.start_ticks >= a_from and ic.frame.end_ticks <= a_to then
					Result.extend (ic.frame)
				end
			end
		end

	frame_nearest (a_ticks: INTEGER_64): detachable TM_FRAME
		local
			l_best: INTEGER_64
			l_distance: INTEGER_64
			l_holds: BOOLEAN
		do
			across stored as ic until l_holds loop
				if ic.frame.start_ticks <= a_ticks and ic.frame.end_ticks > a_ticks then
					Result := ic.frame
					l_holds := True
				else
					l_distance := (ic.frame.start_ticks - a_ticks).abs.min ((ic.frame.end_ticks - a_ticks).abs)
					if Result = Void or else l_distance < l_best then
						Result := ic.frame
						l_best := l_distance
					end
				end
			end
		end

	entries: ARRAYED_LIST [TM_TRACE_ENTRY]
		do
			create Result.make (stored.count)
			across stored as ic loop
				Result.extend (ic.entry)
			end
		end

	tier_of (a_index: INTEGER): INTEGER
			-- Tier of the `a_index'-th stored frame, oldest first.
		require
			in_range: a_index >= 1 and a_index <= frame_count
		do
			Result := stored [a_index].tier
		ensure
			valid: policy.is_valid_tier (Result)
		end

feature -- Element change

	append (a_frame: TM_FRAME)
		do
			next_id := next_id + 1
			stored.extend (create {TM_STORED_FRAME}.make (next_id, a_frame, 0))
			if stored.count = 1 then
				earliest_ticks := a_frame.start_ticks
			end
			latest_ticks := a_frame.end_ticks
			frame_count := stored.count
			appended := appended + 1
		end

	flush
		do
		end

	apply_retention
		local
			l_now: INTEGER_64
			l_tier: INTEGER
		do
			if not stored.is_empty then
				l_now := latest_ticks
				from l_tier := 0 until l_tier = policy.Tier_count - 1 loop
					apply_groups (planner.groups (entries, l_tier, l_now - policy.age_limit_ticks (l_tier)))
					l_tier := l_tier + 1
				end
				delete_expired (l_now - policy.age_limit_ticks (policy.Tier_count - 1))
				frame_count := stored.count
				if stored.is_empty then
					earliest_ticks := 0
					latest_ticks := 0
				else
					earliest_ticks := stored.first.frame.start_ticks
				end
			end
		end

	pin (a_from, a_to: INTEGER_64)
		do
			across stored as ic loop
				if ic.frame.start_ticks < a_to and ic.frame.end_ticks > a_from then
					ic.set_pinned
				end
			end
		end

	close
		do
			is_open := False
			is_writable := False
		end

feature {NONE} -- Implementation

	stored: ARRAYED_LIST [TM_STORED_FRAME]
			-- Frames with their bookkeeping, oldest first.

	merger: TM_FRAME_MERGER
	planner: TM_RETENTION_PLANNER

	next_id: INTEGER_64
			-- Last row id handed out.

	apply_groups (a_groups: ARRAYED_LIST [TM_MERGE_GROUP])
			-- Move or merge each group into its target tier, keeping the order.
		local
			l_rebuilt: ARRAYED_LIST [TM_STORED_FRAME]
			l_first_of: HASH_TABLE [TM_MERGE_GROUP, INTEGER_64]
			l_member: HASH_TABLE [BOOLEAN, INTEGER_64]
			l_frames: ARRAYED_LIST [TM_FRAME]
		do
			if not a_groups.is_empty then
				create l_first_of.make (a_groups.count)
				create l_member.make (a_groups.count * 10)
				across a_groups as g loop
					l_first_of.force (g, g.ids.first)
					across g.ids as id loop
						l_member.force (True, id)
					end
				end
				create l_rebuilt.make (stored.count)
				across stored as ic loop
					if attached l_first_of.item (ic.id) as al_group then
						if al_group.is_move_only then
							ic.set_tier (al_group.target_tier)
							l_rebuilt.extend (ic)
						else
							l_frames := frames_with (al_group.ids)
							next_id := next_id + 1
							l_rebuilt.extend (create {TM_STORED_FRAME}.make (next_id, merger.merged (l_frames), al_group.target_tier))
						end
					elseif not l_member.has (ic.id) then
						l_rebuilt.extend (ic)
					end
				end
				stored := l_rebuilt
				frame_count := stored.count
			end
		ensure
			counted: frame_count = stored.count
		end

	frames_with (a_ids: ARRAYED_LIST [INTEGER_64]): ARRAYED_LIST [TM_FRAME]
			-- The stored frames with these ids, oldest first.
		do
			create Result.make (a_ids.count)
			across stored as ic loop
				if a_ids.has (ic.id) then
					Result.extend (ic.frame)
				end
			end
		ensure
			all_found: Result.count = a_ids.count
		end

	delete_expired (a_cutoff: INTEGER_64)
			-- Remove unpinned tier 2 frames that ended by `a_cutoff', never the newest frame.
		local
			l_kept: ARRAYED_LIST [TM_STORED_FRAME]
		do
			create l_kept.make (stored.count)
			across stored as ic loop
				if ic.tier = policy.Tier_count - 1 and not ic.is_pinned and ic.frame.end_ticks <= a_cutoff
						and ic.frame.end_ticks < latest_ticks then
					-- expired
				else
					l_kept.extend (ic)
				end
			end
			stored := l_kept
			frame_count := stored.count
		ensure
			counted: frame_count = stored.count
		end

invariant
	counted: frame_count = stored.count

end
