note
	description: "[
		Readings for one interval, keyed by metric and instance. Open while it
		is filled; once sealed it is immutable, which is how a frame handed to
		a view cannot be edited.

		Absent entries read as not supported. A discontinuity frame therefore
		stores explicit unavailable readings (see TM_FRAME.make_discontinuity).
	]"
	author: "Larry Rix"

class
	TM_READINGS

inherit
	TM_SHARED_METRICS

create
	make,
	make_from

feature {NONE} -- Initialization

	make
			-- Empty and open.
		do
			create table.make (64)
			create instance_lists.make (16)
		ensure
			empty: count = 0
			open: not is_sealed
		end

	make_from (a_other: TM_READINGS)
			-- Open copy of `a_other', for adding entries to readings that are already sealed.
		do
			create table.make (a_other.count.max (64))
			create instance_lists.make (16)
			across a_other.table as ic loop
				table.force (ic, @ic.key)
			end
			across a_other.instance_lists as ic loop
				instance_lists.force (ic.twin, @ic.key)
			end
		ensure
			same_entries: readings_model |=| a_other.readings_model
			open: not is_sealed
		end

feature -- Access

	reading (a_code: INTEGER; a_instance: READABLE_STRING_32): TM_READING
			-- The stored reading, or a not-supported one when nothing was stored.
		require
			known_metric: metrics.has_code (a_code)
			instance_rule: metrics.metric (a_code).is_instanced = not a_instance.is_empty
		do
			if attached table.item (key (a_code, a_instance)) as al_reading then
				Result := al_reading
			else
				create Result.make_not_supported
			end
		ensure
			stored_if_present: has (a_code, a_instance) implies Result = table.item (key (a_code, a_instance))
			not_supported_if_absent: not has (a_code, a_instance) implies Result.is_not_supported
		end

	instances (a_code: INTEGER): ARRAYED_LIST [STRING_32]
			-- Instance names stored for `a_code', in insertion order; a fresh list.
		require
			known_metric: metrics.has_code (a_code)
			instanced: metrics.metric (a_code).is_instanced
		do
			if attached instance_lists.item (a_code) as al_list then
				create Result.make (al_list.count)
				across al_list as ic loop
					Result.extend (ic.twin)
				end
			else
				create Result.make (0)
			end
		ensure
			each_present: across Result as ic all has (a_code, ic) end
		end

	count: INTEGER
			-- Number of stored readings.
		do
			Result := table.count
		end

feature -- Status report

	has (a_code: INTEGER; a_instance: READABLE_STRING_32): BOOLEAN
			-- Is a reading stored for `a_code' and `a_instance'?
		do
			Result := table.has (key (a_code, a_instance))
		end

	is_sealed: BOOLEAN
			-- Is this collection immutable now?

feature -- Element change

	put (a_code: INTEGER; a_instance: READABLE_STRING_32; a_reading: TM_READING)
			-- Store `a_reading' for `a_code' and `a_instance', replacing any earlier one.
		require
			open: not is_sealed
			known_metric: metrics.has_code (a_code)
			instance_rule: metrics.metric (a_code).is_instanced = not a_instance.is_empty
			fits_metric: a_reading.is_available implies metrics.metric (a_code).accepts (a_reading.value)
		local
			l_key: STRING_8
			l_list: ARRAYED_LIST [STRING_32]
		do
			l_key := key (a_code, a_instance)
			if not table.has (l_key) and then not a_instance.is_empty then
				if attached instance_lists.item (a_code) as al_list then
					l_list := al_list
				else
					create l_list.make (8)
					instance_lists.force (l_list, a_code)
				end
				l_list.extend (create {STRING_32}.make_from_string (a_instance))
			end
			table.force (a_reading, l_key)
		ensure
			stored: reading (a_code, a_instance) = a_reading
			added_if_new: not old has (a_code, a_instance) implies count = old count + 1
			replaced_if_present: old has (a_code, a_instance) implies count = old count
			others_unchanged: agrees_except (old table.twin, key (a_code, a_instance))
				-- O(n) through the hash table; the MML form is checked in a test (review issues 1, 9).
		end

	seal
			-- Make this collection immutable.
		do
			is_sealed := True
		ensure
			sealed: is_sealed
			unchanged: readings_model |=| old readings_model
		end

feature -- Comparison

	includes (a_other: TM_READINGS): BOOLEAN
			-- Does this collection hold every entry of `a_other', the same reading object under the same key?
		do
			Result := across a_other.table as ic all table.item (@ic.key) = ic end
		ensure
			at_least_as_large: Result implies count >= a_other.count
		end

feature -- Model

	readings_model: MML_MAP [STRING_8, TM_READING]
			-- Every stored reading by key.
		do
			create Result
			across table as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = count
		end

	key (a_code: INTEGER; a_instance: READABLE_STRING_32): STRING_8
			-- "code|instance" with the instance in UTF-8. The only place this format is decided.
		local
			l_utf: UTF_CONVERTER
		do
			Result := a_code.out + "|" + l_utf.string_32_to_utf_8_string_8 (a_instance)
		ensure
			starts_with_code: Result.starts_with (a_code.out + "|")
		end

feature {TM_READINGS} -- Implementation

	agrees_except (a_old: HASH_TABLE [TM_READING, STRING_8]; a_key: STRING_8): BOOLEAN
			-- Does every entry of `a_old' other than `a_key' still hold the same reading?
		do
			Result := across a_old as ic all @ic.key ~ a_key or else table.item (@ic.key) = ic end
		end

	table: HASH_TABLE [TM_READING, STRING_8]
			-- Readings by `key'.

	instance_lists: HASH_TABLE [ARRAYED_LIST [STRING_32], INTEGER]
			-- Instance names by metric code, in insertion order.

invariant
	count_matches_table: count = table.count

end
