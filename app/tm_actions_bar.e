note
	description: "[
		The process actions toolbar. End process and End tree need a second
		click within `Confirm_ms' (the label asks "Confirm ...?"), so one
		stray click never ends anything. Each tool calls the action given to
		`set_actions'; enabling follows the selection.
	]"
	author: "Larry Rix"

class
	TM_ACTIONS_BAR

create
	make

feature {NONE} -- Initialization

	make
			-- Toolbar with every tool disabled until a process is selected.
		do
			create toolbar.make
			create clock.make
			toolbar.add_tool (End_task_label, "Ask the app's windows to close", False, agent fire (1))
			toolbar.add_tool (End_process_label, "End the process now (click twice)", False, agent fire (2))
			toolbar.add_tool (End_tree_label, "End the process and its children (click twice)", False, agent fire (3))
			toolbar.add_tool ("Efficiency", "Efficiency mode on or off (EcoQoS and low priority)", False, agent fire (4))
			toolbar.add_tool ("Lower priority", "One priority class down", False, agent fire (5))
			toolbar.add_tool ("Raise priority", "One priority class up (never realtime)", False, agent fire (6))
			toolbar.add_tool ("Undo", "Put the last priority or efficiency change back", False, agent fire (7))
		end

feature -- Access

	toolbar: SW_TOOLBAR
			-- The widget.

	Confirm_ms: INTEGER = 4000

feature -- Element change

	set_actions (a_actions: PROCEDURE [INTEGER])
			-- Call `a_actions' with the tool number (1 end task .. 7 undo) when a tool is used.
		do
			actions := a_actions
		end

	enable (a_selected, a_can_undo: BOOLEAN)
			-- Tools on when a process is selected; Undo when a receipt is held.
		local
			i: INTEGER
		do
			from i := 1 until i > 6 loop
				toolbar.items [i].enabled := a_selected
				i := i + 1
			end
			toolbar.items [7].enabled := a_can_undo
		end

	disarm_if_late
			-- Put an unconfirmed label back after `Confirm_ms'.
		do
			if armed /= 0 and then clock.monotonic_ticks - armed_at > Confirm_ms.to_integer_64 * 10_000 then
				disarm
			end
		end

feature {NONE} -- Implementation

	clock: TM_SYSTEM_CLOCK
	actions: detachable PROCEDURE [INTEGER]

	armed: INTEGER
			-- Tool waiting for its confirming click; 0 when none.

	armed_at: INTEGER_64

	End_task_label: STRING_32 = "End task"
	End_process_label: STRING_32 = "End process"
	End_tree_label: STRING_32 = "End tree"

	fire (a_tool: INTEGER)
			-- Tool `a_tool' was clicked.
		do
			if a_tool = 2 or a_tool = 3 then
				if armed = a_tool then
					disarm
					call (a_tool)
				else
					disarm
					armed := a_tool
					armed_at := clock.monotonic_ticks
					toolbar.items [a_tool].label := {STRING_32} "Confirm " + toolbar.items [a_tool].label.as_lower + {STRING_32} "?"
				end
			else
				disarm
				call (a_tool)
			end
		end

	disarm
			-- No tool waits for confirmation.
		do
			toolbar.items [2].label := End_process_label.twin
			toolbar.items [3].label := End_tree_label.twin
			armed := 0
		ensure
			disarmed: armed = 0
		end

	call (a_tool: INTEGER)
		do
			if attached actions as al_actions then
				al_actions.call ([a_tool])
			end
		end

end
