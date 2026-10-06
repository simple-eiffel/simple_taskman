note
	description: "[
		Everything read from the machine at one instant: every process sample
		by identity, and the system readings. Two snapshots make one frame.
	]"
	author: "Larry Rix"

class
	TM_SNAPSHOT

create
	make

feature {NONE} -- Initialization

	make (a_utc_ticks, a_monotonic_ticks: INTEGER_64; a_samples: ITERABLE [TM_PROCESS_SAMPLE]; a_readings: TM_READINGS)
			-- Snapshot taken at `a_utc_ticks' (wall clock) and `a_monotonic_ticks'.
			-- A later sample with an identity already seen replaces the earlier one.
		require
			utc_positive: a_utc_ticks > 0
			monotonic_non_negative: a_monotonic_ticks >= 0
			readings_sealed: a_readings.is_sealed
		do
			utc_ticks := a_utc_ticks
			monotonic_ticks := a_monotonic_ticks
			readings := a_readings
			create samples_table.make (512)
			across a_samples as ic loop
				samples_table.force (ic, ic.id)
			end
		ensure
			times_kept: utc_ticks = a_utc_ticks and monotonic_ticks = a_monotonic_ticks
			readings_kept: readings = a_readings
			every_identity: across a_samples as ic all has (ic.id) end
		end

feature -- Access

	utc_ticks: INTEGER_64
			-- Wall-clock time of the read, UTC ticks since 1601.

	monotonic_ticks: INTEGER_64
			-- Monotonic time of the read; only differences mean anything.

	readings: TM_READINGS
			-- System readings at this instant; sealed.

	sample (a_id: TM_PROCESS_ID): TM_PROCESS_SAMPLE
			-- The sample of `a_id'.
		require
			present: has (a_id)
		do
			check attached samples_table.item (a_id) as al_sample then
					-- `has' guarantees presence.
				Result := al_sample
			end
		ensure
			matches: Result.id ~ a_id
		end

	samples: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			-- Every sample in arbitrary order; a fresh list each call.
		do
			create Result.make (count)
			across samples_table as ic loop
				Result.extend (ic)
			end
		ensure
			fresh_each_call: Result /= samples
			complete: Result.count = count
		end

	count: INTEGER
			-- Number of distinct identities.
		do
			Result := samples_table.count
		end

feature -- Status report

	has (a_id: TM_PROCESS_ID): BOOLEAN
			-- Was `a_id' running at this instant?
		do
			Result := samples_table.has (a_id)
		end

feature -- Model

	identities_model: MML_SET [TM_PROCESS_ID]
			-- Every identity in this snapshot.
		do
			create Result
			across samples_table as ic loop
				Result := Result & @ic.key
			end
		ensure
			same_count: Result.count = count
		end

feature {NONE} -- Implementation

	samples_table: HASH_TABLE [TM_PROCESS_SAMPLE, TM_PROCESS_ID]
			-- Samples by identity.

invariant
	utc_positive: utc_ticks > 0
	monotonic_non_negative: monotonic_ticks >= 0
	readings_sealed: readings.is_sealed

end
