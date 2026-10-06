note
	description: "[
		Windows priority classes (SetPriorityClass values) and their names.
		Realtime exists but is never set by simple_taskman: one runaway
		realtime process can starve the whole machine, input included.
	]"
	author: "Larry Rix"

class
	TM_PRIORITY

feature -- Constants

	Idle: INTEGER = 0x40
	Below_normal: INTEGER = 0x4000
	Normal: INTEGER = 0x20
	Above_normal: INTEGER = 0x8000
	High: INTEGER = 0x80
	Realtime: INTEGER = 0x100

feature -- Status report

	is_known (a_class: INTEGER): BOOLEAN
			-- Is `a_class' one of the Windows priority classes?
		do
			Result := a_class = Idle or a_class = Below_normal or a_class = Normal
				or a_class = Above_normal or a_class = High or a_class = Realtime
		end

	is_settable (a_class: INTEGER): BOOLEAN
			-- May simple_taskman set `a_class'? Every known class but realtime.
		do
			Result := is_known (a_class) and a_class /= Realtime
		ensure
			never_realtime: Result implies a_class /= Realtime
		end

feature -- Access

	name (a_class: INTEGER): STRING_32
			-- Task Manager's word for `a_class'.
		require
			known: is_known (a_class)
		do
			inspect a_class
			when Idle then
				Result := {STRING_32} "Low"
			when Below_normal then
				Result := {STRING_32} "Below normal"
			when Normal then
				Result := {STRING_32} "Normal"
			when Above_normal then
				Result := {STRING_32} "Above normal"
			when High then
				Result := {STRING_32} "High"
			else
				Result := {STRING_32} "Realtime"
			end
		ensure
			named: not Result.is_empty
		end

	settable_classes: ARRAY [INTEGER]
			-- The classes offered to the owner, lowest first.
		do
			Result := <<Idle, Below_normal, Normal, Above_normal, High>>
		ensure
			all_settable: across Result as ic all is_settable (ic) end
		end

end
