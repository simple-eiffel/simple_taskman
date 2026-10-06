note
	description: "[
		Resources a process can be ranked by. A classification such as "is
		this a known resource" is written as a range test on these constants,
		because a non-object call is only allowed on a constant (VUNO).
	]"
	author: "Larry Rix"

class
	TM_RESOURCE

feature -- Codes

	Cpu: INTEGER = 1
			-- CPU cores used.

	Memory: INTEGER = 2
			-- Private bytes.

	Io_read: INTEGER = 3
			-- Bytes read per second.

	Io_write: INTEGER = 4
			-- Bytes written per second.

	Io_total: INTEGER = 5
			-- Bytes read and written per second.

end
