note
	description: "[
		Codes for why a reading has, or has no, value.

		Zero is available, so a stored status reads naturally in the
		recorder's CHECK clauses. Reached by qualified access only
		({TM_READING_STATUS}.Available); no class inherits it just to see a
		constant.
	]"
	author: "Larry Rix"

class
	TM_READING_STATUS

feature -- Codes

	Available: INTEGER = 0
			-- Measured, finite, and inside the metric's valid range.

	Unavailable: INTEGER = 1
			-- The source exists but gave nothing this time.

	Not_supported: INTEGER = 2
			-- This machine has no such source.

	Access_denied: INTEGER = 3
			-- The source exists; our rights do not reach it.

	Invalid: INTEGER = 4
			-- The source answered with a value that cannot be true.

end
