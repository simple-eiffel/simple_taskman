note
	description: "[
		Test and replay fake for system readings. Support is declared before
		the first refresh, as a real source decides it at creation; each
		refresh then answers with the next scripted round. Undeclared metrics
		are not supported. Supported metrics with no scripted value, or after
		the script runs out, read unavailable.
	]"
	author: "Larry Rix"

class
	TM_SCRIPTED_SYSTEM_SOURCE

inherit
	TM_SYSTEM_SOURCE

create
	make

feature {NONE} -- Initialization

	make (a_logical_processors: INTEGER)
			-- Script for a machine of `a_logical_processors'; nothing supported yet.
		require
			processors: a_logical_processors > 0
		do
			scripted_processors := a_logical_processors
			create support.make (metrics.count)
			create reasons.make (metrics.count)
			create rounds.make (8)
			create pending.make (8)
			create last_readings.make
			last_readings.seal
			next_round := 1
		ensure
			processors_kept: logical_processors = a_logical_processors
			not_refreshed: not has_refreshed
			open: not is_closed
		end

feature -- Access

	support_of (a_code: INTEGER): INTEGER
			-- As declared; not supported otherwise.
		do
			if support.has (a_code) then
				Result := support [a_code]
			else
				Result := {TM_READING_STATUS}.Not_supported
			end
		end

	support_reason (a_code: INTEGER): STRING_32
			-- As declared.
		do
			if attached reasons.item (a_code) as al_reason then
				Result := al_reason.twin
			elseif support_of (a_code) = {TM_READING_STATUS}.Available then
				create Result.make_empty
			else
				create Result.make_from_string ({STRING_32} "not scripted")
			end
		end

	logical_processors: INTEGER
			-- As scripted.
		do
			Result := scripted_processors
		end

	rounds_remaining: INTEGER
			-- Scripted refreshes not yet consumed.
		do
			Result := rounds.count - next_round + 1
		end

feature -- Status report

	has_refreshed: BOOLEAN
			-- Has `refresh' run? Support is fixed from then on.

feature -- Element change

	declare_support (a_code: INTEGER; a_status: INTEGER; a_reason: READABLE_STRING_32)
			-- Declare `a_code' supported (`a_status' Available, `a_reason' empty) or not, and why.
		require
			before_first_refresh: not has_refreshed
			known_metric: metrics.has_code (a_code)
			known_status: a_status >= {TM_READING_STATUS}.Available and a_status <= {TM_READING_STATUS}.Invalid
			reason_iff_unsupported: (a_status = {TM_READING_STATUS}.Available) = a_reason.is_empty
		do
			support.force (a_status, a_code)
			if a_reason.is_empty then
				reasons.remove (a_code)
			else
				reasons.force (create {STRING_32}.make_from_string (a_reason), a_code)
			end
		ensure
			declared: support_of (a_code) = a_status
		end

	script_reading (a_code: INTEGER; a_instance: READABLE_STRING_32; a_reading: TM_READING)
			-- Add `a_reading' for `a_code' and `a_instance' to the round being scripted.
		require
			known_metric: metrics.has_code (a_code)
			supported: support_of (a_code) = {TM_READING_STATUS}.Available
			instance_rule: metrics.metric (a_code).is_instanced = not a_instance.is_empty
		do
			pending.extend ([a_code, create {STRING_32}.make_from_string (a_instance), a_reading])
		ensure
			pending_grew: pending_count = old pending_count + 1
		end

	end_round
			-- Close the round being scripted; the next `refresh' may consume it.
		do
			rounds.extend (pending)
			create pending.make (8)
		ensure
			one_more: rounds_remaining = old rounds_remaining + 1
			pending_empty: pending_count = 0
		end

	pending_count: INTEGER
			-- Entries in the round being scripted.
		do
			Result := pending.count
		end

feature -- Basic operations

	refresh
			-- Answer with the next scripted round.
		local
			l_readings: TM_READINGS
		do
			has_refreshed := True
			create l_readings.make
			across metrics.codes as ic loop
				if not metrics.metric (ic).is_instanced then
					if support_of (ic) = {TM_READING_STATUS}.Available then
						l_readings.put (ic, {STRING_32} "", create {TM_READING}.make_unavailable)
					elseif support_of (ic) /= {TM_READING_STATUS}.Not_supported then
						l_readings.put (ic, {STRING_32} "", status_reading (support_of (ic)))
					end
						-- Not supported is left absent: an absent reading reads exactly that,
						-- and the frame builder owns the self.* readings.
				end
			end
			if next_round <= rounds.count then
				across rounds [next_round] as ic loop
					l_readings.put (ic.code, ic.instance, ic.reading)
				end
				next_round := next_round + 1
			end
			l_readings.seal
			last_readings := l_readings
		ensure then
			refreshed: has_refreshed
			consumed: old rounds_remaining > 0 implies rounds_remaining = old rounds_remaining - 1
		end

	close
			-- Nothing to release.
		do
			is_closed := True
		end

feature {NONE} -- Implementation

	scripted_processors: INTEGER

	support: HASH_TABLE [INTEGER, INTEGER]
			-- Declared support by code.

	reasons: HASH_TABLE [STRING_32, INTEGER]
			-- Declared reasons by code.

	rounds: ARRAYED_LIST [ARRAYED_LIST [TUPLE [code: INTEGER; instance: STRING_32; reading: TM_READING]]]
			-- Closed rounds, in order.

	pending: ARRAYED_LIST [TUPLE [code: INTEGER; instance: STRING_32; reading: TM_READING]]
			-- The round being scripted.

	next_round: INTEGER
			-- Index of the next round to consume.

invariant
	processors: scripted_processors > 0
	next_in_range: next_round >= 1 and next_round <= rounds.count + 1

end
