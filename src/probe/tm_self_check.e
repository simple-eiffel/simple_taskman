note
	description: "[
		The result of the native table's layout self-check: whether it ran,
		whether it passed, and when it failed, which field and the three
		bracketing values (documented before, native, documented after).
		Each check is decided once.
	]"
	author: "Larry Rix"

class
	TM_SELF_CHECK

create
	make_not_run

feature {NONE} -- Initialization

	make_not_run
			-- No check yet.
		do
			create failure.make_empty
			create failing_field.make_empty
		ensure
			not_run: not has_run and not passed
		end

feature -- Access

	failure: STRING_32
			-- Why the check failed; empty otherwise.

	failing_field: STRING_8
			-- Name of the field that failed; empty unless a field failed.

	value_before, value_native, value_after: INTEGER_64
			-- Bracketing values of `failing_field'.

feature -- Status report

	has_run: BOOLEAN
			-- Was the check decided?

	passed: BOOLEAN
			-- Did every field agree with the documented calls?

feature -- Element change

	pass
			-- Every field agreed.
		require
			not_decided: not has_run
		do
			has_run := True
			passed := True
		ensure
			passed: has_run and passed
			no_failure: failure.is_empty
		end

	fail (a_reason: READABLE_STRING_32)
			-- The check could not pass, for `a_reason'.
		require
			not_decided: not has_run
			reason_given: not a_reason.is_empty
		do
			has_run := True
			create failure.make_from_string (a_reason)
		ensure
			failed: has_run and not passed
			reason_kept: failure.same_string (a_reason)
		end

	fail_field (a_field: READABLE_STRING_8; a_before, a_native, a_after: INTEGER_64)
			-- Field `a_field' read `a_native' natively, outside [`a_before', `a_after'] and its slack.
		require
			not_decided: not has_run
			field_given: not a_field.is_empty
		do
			has_run := True
			create failing_field.make_from_string (a_field)
			value_before := a_before
			value_native := a_native
			value_after := a_after
			create failure.make_from_string ({STRING_32} "native field ")
			failure.append_string_general (a_field)
			failure.append_string_general (" read ")
			failure.append_string_general (a_native.out)
			failure.append_string_general (", documented reads were ")
			failure.append_string_general (a_before.out)
			failure.append_string_general (" and ")
			failure.append_string_general (a_after.out)
		ensure
			failed: has_run and not passed
			field_kept: failing_field.same_string (a_field)
			values_kept: value_before = a_before and value_native = a_native and value_after = a_after
			explained: not failure.is_empty
		end

invariant
	passed_has_run: passed implies has_run
	passed_has_no_failure: passed implies failure.is_empty
	failure_explained: (has_run and not passed) implies not failure.is_empty
	not_run_is_blank: not has_run implies failure.is_empty

end
