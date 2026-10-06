note
	description: "[
		The answer to "why is it slow?" for one window of frames: a kind
		(none, memory pressure, disk saturation, CPU saturation, or can't
		tell), one plain sentence, the culprit when there is one, the
		evidence behind it, and lower-ranked findings (spec 04, Diagnosis).
	]"
	author: "Larry Rix"

class
	TM_VERDICT

create
	make

feature {NONE} -- Initialization

	make (a_kind: INTEGER; a_sentence: READABLE_STRING_32)
			-- Verdict of `a_kind' saying `a_sentence'.
		require
			known_kind: a_kind >= None and a_kind <= Inconclusive
			worded: not a_sentence.is_empty
		do
			kind := a_kind
			create sentence.make_from_string (a_sentence)
			create culprit.make_empty
			create evidence.make (4)
			create also.make (2)
		ensure
			kept: kind = a_kind and sentence.same_string (a_sentence)
		end

feature -- Access

	kind: INTEGER
	sentence: STRING_32
	culprit: STRING_32
			-- Process name blamed; empty when none.
	evidence: ARRAYED_LIST [STRING_32]
			-- Readings behind the sentence, each from inside the window.
	also: ARRAYED_LIST [STRING_32]
			-- Lower-precedence findings ("also: disk 1 D: busy 92%").

	None: INTEGER = 0
	Memory_pressure: INTEGER = 1
	Disk_saturation: INTEGER = 2
	Cpu_saturation: INTEGER = 3
	Inconclusive: INTEGER = 4

	full_text: STRING_32
			-- Sentence, then "also" findings.
		do
			Result := sentence.twin
			across also as ic loop
				Result.append ({STRING_32} "  Also: " + ic)
			end
		end

feature -- Status report

	is_found: BOOLEAN
			-- Did a rule name a bottleneck?
		do
			Result := kind = Memory_pressure or kind = Disk_saturation or kind = Cpu_saturation
		end

feature -- Element change

	set_culprit (a_name: READABLE_STRING_32)
		do
			create culprit.make_from_string (a_name)
		end

	add_evidence (a_line: READABLE_STRING_32)
		require
			worded: not a_line.is_empty
		do
			evidence.extend (create {STRING_32}.make_from_string (a_line))
		end

	add_also (a_line: READABLE_STRING_32)
		require
			worded: not a_line.is_empty
		do
			also.extend (create {STRING_32}.make_from_string (a_line))
		end

invariant
	known_kind: kind >= None and kind <= Inconclusive
	worded: not sentence.is_empty

end
