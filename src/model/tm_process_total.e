note
	description: "[
		One identity's total use of one resource over a window: core-seconds
		for CPU, peak private bytes for memory, bytes for IO.
	]"
	author: "Larry Rix"

class
	TM_PROCESS_TOTAL

create
	make

feature {NONE} -- Initialization

	make (a_id: TM_PROCESS_ID; a_name: READABLE_STRING_32; a_resource: INTEGER; a_total: REAL_64; a_frames_seen: INTEGER)
			-- Total `a_total' of `a_resource' used by `a_id' across `a_frames_seen' frames.
		require
			known_resource: a_resource >= {TM_RESOURCE}.Cpu and a_resource <= {TM_RESOURCE}.Io_total
			total_non_negative: a_total >= 0.0
			seen: a_frames_seen > 0
		do
			id := a_id
			create name.make_from_string (a_name)
			resource := a_resource
			total := a_total
			frames_seen := a_frames_seen
		ensure
			kept: id ~ a_id and name.same_string (a_name) and resource = a_resource
				and total = a_total and frames_seen = a_frames_seen
		end

feature -- Access

	id: TM_PROCESS_ID
			-- Identity.

	name: STRING_32
			-- Image name.

	resource: INTEGER
			-- A {TM_RESOURCE} code.

	total: REAL_64
			-- Amount used over the window.

	frames_seen: INTEGER
			-- Frames in which this identity had the resource measured.

invariant
	known_resource: resource >= {TM_RESOURCE}.Cpu and resource <= {TM_RESOURCE}.Io_total
	total_non_negative: total >= 0.0
	seen: frames_seen > 0

end
