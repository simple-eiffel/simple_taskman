note
	description: "[
		Where process samples come from. A source that is not trusted must not
		be read: the native table is trusted only after its layout self-check
		passes. A failed read is not an exception; it says why in `last_error'.
	]"
	author: "Larry Rix"

deferred class
	TM_PROCESS_SOURCE

feature -- Basic operations

	read_all
			-- Read every process now.
		require
			trusted: is_trusted
			open: not is_closed
		deferred
		ensure
			succeeded_or_said_why: last_read_succeeded xor not last_error.is_empty
			idle_present_when_native: (last_read_succeeded and is_native) implies has_idle_entry
			unique_identities: last_read_succeeded implies has_unique_identities
		end

	close
			-- Release native resources.
		deferred
		ensure
			closed: is_closed
		end

feature -- Access

	last_samples: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			-- Samples from the last successful read; a fresh list each call.
		require
			read: last_read_succeeded
		do
			create Result.make (samples.count)
			across samples as ic loop
				Result.extend (ic)
			end
		ensure
			fresh: Result /= last_samples
			complete: Result.count = samples.count
		end

	last_error: STRING_32
			-- Why the last read failed; empty after a success.

	kind_name: STRING_8
			-- "native", "documented", or "scripted".
		deferred
		ensure
			named: not Result.is_empty
		end

feature -- Status report

	is_trusted: BOOLEAN
			-- May this source be read?
		deferred
		end

	is_native: BOOLEAN
			-- Is this the native process table, which always lists the idle pseudo-process?
		deferred
		end

	last_read_succeeded: BOOLEAN
			-- Did the last `read_all' succeed?

	is_closed: BOOLEAN
			-- Have native resources been released?

	has_idle_entry: BOOLEAN
			-- Did the last read include the idle pseudo-process?
		require
			read: last_read_succeeded
		do
			Result := across samples as ic some ic.id.is_idle_pseudo_process end
		end

	has_sample (a_id: TM_PROCESS_ID): BOOLEAN
			-- Did the last read include `a_id'? O(n).
		require
			read: last_read_succeeded
		do
			Result := across samples as ic some ic.id ~ a_id end
		end

	has_unique_identities: BOOLEAN
			-- Does every sample of the last read carry a distinct identity? O(n) through a hash table.
		local
			l_seen: HASH_TABLE [BOOLEAN, TM_PROCESS_ID]
		do
			create l_seen.make (samples.count)
			Result := True
			across samples as ic until not Result loop
				if l_seen.has (ic.id) then
					Result := False
				else
					l_seen.put (True, ic.id)
				end
			end
		end

feature -- Model

	samples_model: MML_SET [TM_PROCESS_ID]
			-- Distinct identities in the last read. Cubic to build with contracts on:
			-- for tests on small scripts only, never in a postcondition (review issue 1).
		do
			create Result
			across samples as ic loop
				Result := Result & ic.id
			end
		end

feature {NONE} -- Implementation

	samples: ARRAYED_LIST [TM_PROCESS_SAMPLE]
			-- Samples of the last successful read.

end
