note
	description: "[
		Test and replay fake: answers each `read_all' with the next scripted
		round of samples, or with a scripted failure. Needs no Windows call,
		so the sampler, the frame builder, and the rules can be tested on
		known inputs. When the script runs out, reads fail and say so.
	]"
	author: "Larry Rix"

class
	TM_SCRIPTED_PROCESS_SOURCE

inherit
	TM_PROCESS_SOURCE

create
	make,
	make_native_like

feature {NONE} -- Initialization

	make
			-- Empty script; not native-like.
		do
			create last_error.make_empty
			create samples.make (0)
			create rounds.make (8)
			create failures.make (8)
			next_round := 1
		ensure
			empty: rounds_remaining = 0
			open: not is_closed
		end

	make_native_like
			-- Empty script that claims to be native, so it must list the idle pseudo-process.
		do
			make
			is_native := True
		ensure
			empty: rounds_remaining = 0
			native: is_native
		end

feature -- Access

	kind_name: STRING_8
			-- "scripted".
		once
			Result := "scripted"
		end

	rounds_remaining: INTEGER
			-- Scripted reads not yet consumed.
		do
			Result := rounds.count - next_round + 1
		end

feature -- Status report

	is_trusted: BOOLEAN = True
			-- A script is trusted.

	is_native: BOOLEAN
			-- Does this script claim to be the native table?

feature -- Element change

	add_round (a_samples: ITERABLE [TM_PROCESS_SAMPLE])
			-- Script one successful read returning `a_samples'.
		require
			idle_when_native: is_native implies across a_samples as ic some ic.id.is_idle_pseudo_process end
		local
			l_round: ARRAYED_LIST [TM_PROCESS_SAMPLE]
		do
			create l_round.make (16)
			across a_samples as ic loop
				l_round.extend (ic)
			end
			rounds.extend (l_round)
			failures.extend ({STRING_32} "")
		ensure
			one_more: rounds_remaining = old rounds_remaining + 1
		end

	add_failure (a_reason: READABLE_STRING_32)
			-- Script one failed read, for `a_reason'.
		require
			reason_given: not a_reason.is_empty
		do
			rounds.extend (create {ARRAYED_LIST [TM_PROCESS_SAMPLE]}.make (0))
			failures.extend (create {STRING_32}.make_from_string (a_reason))
		ensure
			one_more: rounds_remaining = old rounds_remaining + 1
		end

feature -- Basic operations

	read_all
			-- Consume the next scripted round.
		do
			if next_round > rounds.count then
				last_read_succeeded := False
				create last_error.make_from_string ({STRING_32} "script exhausted")
			elseif not failures [next_round].is_empty then
				last_read_succeeded := False
				last_error := failures [next_round].twin
				next_round := next_round + 1
			else
				last_read_succeeded := True
				create last_error.make_empty
				samples := rounds [next_round].twin
				next_round := next_round + 1
			end
		ensure then
			consumed: old rounds_remaining > 0 implies rounds_remaining = old rounds_remaining - 1
		end

	close
			-- Nothing to release.
		do
			is_closed := True
		end

feature {NONE} -- Implementation

	rounds: ARRAYED_LIST [ARRAYED_LIST [TM_PROCESS_SAMPLE]]
			-- Scripted reads in order.

	failures: ARRAYED_LIST [STRING_32]
			-- Failure reason per round; empty for a successful round.

	next_round: INTEGER
			-- Index of the next round to consume.

invariant
	parallel_script: rounds.count = failures.count
	next_in_range: next_round >= 1 and next_round <= rounds.count + 1

end
