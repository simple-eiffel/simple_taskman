note
	description: "[
		What an action on a process did: done, or refused with the reason in
		words. A priority or efficiency change keeps the prior priority class,
		so it can be undone exactly (v2 I-004, restraint with a receipt).
	]"
	author: "Larry Rix"

class
	TM_ACTION_RESULT

create
	make_done,
	make_refused

feature {NONE} -- Initialization

	make_done (a_action: READABLE_STRING_32; a_prior_priority: INTEGER)
			-- `a_action' happened; `a_prior_priority' is the class before it, or 0 when it did not change one.
		require
			action_named: not a_action.is_empty
			prior_known_or_none: a_prior_priority = 0 or else (create {TM_PRIORITY}).is_known (a_prior_priority)
		do
			create action.make_from_string (a_action)
			create reason.make_empty
			prior_priority := a_prior_priority
			succeeded := True
		ensure
			done: succeeded and reason.is_empty
			kept: action.same_string (a_action) and prior_priority = a_prior_priority
		end

	make_refused (a_action, a_reason: READABLE_STRING_32)
			-- `a_action' did not happen, because `a_reason'.
		require
			action_named: not a_action.is_empty
			reason_given: not a_reason.is_empty
		do
			create action.make_from_string (a_action)
			create reason.make_from_string (a_reason)
		ensure
			refused: not succeeded and reason.same_string (a_reason)
			no_receipt: prior_priority = 0
		end

feature -- Access

	action: STRING_32
			-- What was asked, in words ("End process", "Set priority to Low").

	reason: STRING_32
			-- Why it was refused; empty when done.

	prior_priority: INTEGER
			-- Priority class before the action, for undo; 0 when none was changed.

	summary: STRING_32
			-- One line for the status bar.
		do
			if succeeded then
				Result := action + {STRING_32} ": done"
			else
				Result := action + {STRING_32} ": refused, " + reason
			end
		end

feature -- Status report

	succeeded: BOOLEAN
			-- Did the action happen?

invariant
	reason_iff_refused: succeeded = reason.is_empty
	action_named: not action.is_empty

end
