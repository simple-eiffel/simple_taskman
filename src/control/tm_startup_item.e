note
	description: "One app Windows starts at logon, as the Startup apps tab lists it."
	author: "Larry Rix"

class
	TM_STARTUP_ITEM

create
	make

feature {NONE} -- Initialization

	make (a_name, a_command, a_image_path, a_where: READABLE_STRING_32; a_root, a_kind: INTEGER; a_enabled: BOOLEAN)
			-- Entry `a_name' launching `a_command' (file `a_image_path'), found `a_where'; StartupApproved
			-- root `a_root' (1 you, 2 all users) and kind `a_kind' (1 Run, 2 Run32, 3 StartupFolder).
		require
			named: not a_name.is_empty
			root_known: a_root = 1 or a_root = 2
			kind_known: a_kind >= 1 and a_kind <= 3
		do
			create name.make_from_string (a_name)
			create command.make_from_string (a_command)
			create image_path.make_from_string (a_image_path)
			create where.make_from_string (a_where)
			root := a_root
			kind := a_kind
			is_enabled := a_enabled
			create publisher.make_empty
			create impact.make_from_string ({STRING_32} "Not measured")
		ensure
			kept: name.same_string (a_name) and root = a_root and kind = a_kind and is_enabled = a_enabled
		end

feature -- Access

	name, command, image_path, where, publisher, impact: STRING_32
	root, kind: INTEGER

	status_text: STRING_32
		do
			if is_enabled then
				Result := {STRING_32} "Enabled"
			else
				Result := {STRING_32} "Disabled"
			end
		end

	image_name: STRING_32
			-- File name part of `image_path', lower case (matches process names).
		local
			l_cut: INTEGER
		do
			l_cut := image_path.last_index_of ({CHARACTER_32} '\', image_path.count)
			Result := image_path.substring (l_cut + 1, image_path.count).as_lower
		end

	name_key: STRING_32
		do
			Result := name.as_lower
		end

	publisher_key: STRING_32
		do
			Result := publisher.as_lower
		end

	impact_key: STRING_32
		do
			Result := impact.as_lower
		end

feature -- Status report

	is_enabled: BOOLEAN

	is_machine_wide: BOOLEAN
			-- Changing it needs administrator rights?
		do
			Result := root = 2
		end

feature -- Element change

	set_publisher (a_text: READABLE_STRING_32)
		do
			create publisher.make_from_string (a_text)
		end

	set_impact (a_text: READABLE_STRING_32)
		require
			worded: not a_text.is_empty
		do
			create impact.make_from_string (a_text)
		end

invariant
	named: not name.is_empty
	root_known: root = 1 or root = 2
	kind_known: kind >= 1 and kind <= 3

end
