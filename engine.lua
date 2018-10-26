  -- Stuff defined in this file:
  --  . the data structures that store the configuration of
  --    the stack of panels
  --  . the main game routine
  --    (rising, timers, falling, cursor movement, swapping, landing)
  --  . the matches-checking routine
  
local min, pairs, deepcpy = math.min, pairs, deepcpy
local max = math.max
local garbage_bounce_time = #garbage_bounce_table
local GARBAGE_DELAY = 52
local clone_pool = {}

  -- Stack of panels
Stack = class(function(self, which, mode, speed, difficulty, player_number)
	assert(which, "Which param nil") 
	assert(mode, "Mode must exists") 
	self.character = uniformly(characters)
	assert(self.character, "There are no characters")
	self.max_health = 1
	self.mode = mode or "endless"
	assert(self.mode, "Game mode is not selected") 

	if mode ~= "puzzle" then
		self.do_first_row = true
	else
		-- nothing to do --t23
	end

	if self.mode == "endless" then
		self.NCOLORS = difficulty_to_ncolors_endless[difficulty]
		assert(self.NCOLORS, "NCOLORS can't be nil") 
	elseif self.mode == "time" then  --t21
		self.NCOLORS = difficulty_to_ncolors_1Ptime[difficulty]
		assert(self.NCOLORS, "NCOLORS can't be nil") 
	elseif self.mode == "2ptime" or self.mode == "vs" then --t21
		local level = speed or 5
		assert(level, "Level can't be nil") 
		self.character = (type(difficulty) == "string") and difficulty or self.character
		self.level = level
		speed = level_to_starting_speed[level]
		-- difficulty = level_to_difficulty[level]
		self.speed_times = {
			15*60,
			idx=1,
			delta=15*60
		} --t01
		self.max_health = assert(level_to_hang_time[level], "max_health can't be nil") 
		self.FRAMECOUNT_HOVER  = assert(level_to_hover[self.level], "FRAMECOUNT_HOVER can't be nil") 
		self.FRAMECOUNT_FLASH  = assert(level_to_flash[self.level],  "FRAMECOUNT_FLASH can't be nil") 
		self.FRAMECOUNT_FACE   = assert(level_to_face[self.level], "FRAMECOUNT_FACE can't be nil") 
		self.FRAMECOUNT_POP    = assert(level_to_pop[self.level], "FRAMECOUNT_POP can't be nil") 
		self.combo_constant    = assert(level_to_combo_constant[self.level], "combo_constant can't be nil") 
		self.combo_coefficient = assert(level_to_combo_coefficient[self.level], "combo_coefficient can't be nil") 
		self.chain_constant    = assert(level_to_chain_constant[self.level], "chain_constant can't be nil") 
		self.chain_coefficient = assert(level_to_chain_coefficient[self.level], "chain_coefficient can't be nil") 
		if self.mode == "2ptime" then
			self.NCOLORS = level_to_ncolors_time[level]
		else
			self.NCOLORS = level_to_ncolors_vs[level]
		end
		assert(self.NCOLORS, "NCOLORS can't be nil")
	else
		-- nothing to do --t23
	end
	self.health = self.max_health
	
	self.garbage_cols = {
		{1,2,3,4,5,6,idx=1},
		{1,3,5,idx=1},
		{1,4,idx=1},
		{1,2,3,idx=1},
		{1,2,idx=1},
		{1,idx=1}
	} --t01
	self.later_garbage = {}
	self.garbage_q = Queue()
	-- garbage_to_send[frame] is an array of garbage to send at frame.
	-- garbage_to_send.chain is an array of garbage to send when the chain ends.
	self.garbage_to_send = {}
	self.pos_x = 4 -- Position of the play area on the screen
	self.pos_y = 4
	self.score_x = 315
	self.panel_buffer = ""
	self.gpanel_buffer = ""
	self.input_buffer = ""
	self.panels = {}
	self.width = 6
	self.height = 12
	for i=0,self.height do
		self.panels[i] = {}
		for j=1,self.width do
			self.panels[i][j] = Panel()
		end
	end
	
	self.CLOCK = 0
	
	self.max_runs_per_frame = 3
	
	self.displacement = 16
	-- This variable indicates how far below the top of the play
	-- area the top row of panels actually is.
	-- This variable being decremented causes the stack to rise.
	-- During the automatic rising routine, if this variable is 0,
	-- it's reset to 15, all the panels are moved up one row,
	-- and a new row is generated at the bottom.
	-- Only when the displacement is 0 are all 12 rows "in play."
	
	self.danger_col = {false,false,false,false,false,false}
	-- set true if this column is near the top
	self.danger_timer = 0 -- decides bounce frame when in danger
	
	self.difficulty = assert(difficulty or 2) 

	self.speed = assert(speed or 1, "speed must exists") -- The player's speed level decides the amount of time
	-- the stack takes to rise automatically
	if self.speed_times == nil then
		self.panels_to_speedup = panels_to_next_speed[self.speed]
	else
		-- nothing to do --t23
	end

	self.rise_timer = 1 -- When this value reaches 0, the stack will rise a pixel
	self.rise_lock = false -- If the stack is rise locked, it won't rise until it is
	-- unlocked.
	self.has_risen = false -- set once the stack rises once during the game
	
	self.stop_time = 0
	self.pre_stop_time = 0
	
	self.NCOLORS = self.NCOLORS or 5
	self.score = 0 -- der skore
	self.chain_counter = 0 -- how high is the current chain?
	
	self.panels_in_top_row = false -- boolean, for losing the game
	self.danger = self.danger or false -- boolean, panels in the top row (danger)
	self.danger_music = self.danger_music or false -- changes music state
	
	self.n_active_panels = 0
	self.prev_active_panels = 0
	self.n_chain_panels= 0
	
	-- These change depending on the difficulty and speed levels:
	self.FRAMECOUNT_HOVER = assert(self.FRAMECOUNT_HOVER or FC_HOVER[self.difficulty]) 
	self.FRAMECOUNT_FLASH = assert(self.FRAMECOUNT_FLASH or FC_FLASH[self.difficulty]) 
	self.FRAMECOUNT_FACE  = assert(self.FRAMECOUNT_FACE or FC_FACE[self.difficulty]) 
	self.FRAMECOUNT_POP   = assert(self.FRAMECOUNT_POP or FC_POP[self.difficulty]) 
	self.FRAMECOUNT_MATCH = assert(self.FRAMECOUNT_FACE + self.FRAMECOUNT_FLASH) 
	self.FRAMECOUNT_RISE  = assert(speed_to_rise_time[self.speed]) 
	assert(self.FRAMECOUNT_RISE > 0) 
	self.rise_timer = assert(self.FRAMECOUNT_RISE) 
	assert(self.rise_timer > 0) 
	
	-- Player input stuff:
	self.manual_raise = false -- set until raising is completed
	self.manual_raise_yet = false -- if not set, no actual raising's been done yet
	-- since manual raise button was pressed
	self.prevent_manual_raise = false
	self.swap_1 = false -- attempt to initiate a swap on this frame
	self.swap_2 = false
	
	self.cur_wait_time = 25 -- number of ticks to wait before the cursor begins
	-- to move quickly... it's based on P1CurSensitivity
	self.cur_timer = 0 -- number of ticks for which a new direction's been pressed
	self.cur_dir = nil -- the direction pressed
	self.cur_row = 7 -- the row the cursor's on
	self.cur_col = 3 -- the column the left half of the cursor's on
	self.top_cur_row = self.height + (self.mode == "puzzle" and 0 or -1)
	
	self.move_sound = false -- this is set if the cursor movement sound should be played
	self.poppedPanelIndex = assert(self.poppedPanelIndex or 1) 
	self.panels_cleared = assert(self.panels_cleared or 0) 
	self.metal_panels_queued = assert(self.metal_panels_queued or 0)
	self.lastPopLevelPlayed = assert(self.lastPopLevelPlayed or 1) 
	self.lastPopIndexPlayed = assert(self.lastPopIndexPlayed or 1) 
	self.game_over = false
	
	self.card_q = Queue()
	
	self.which = assert(which or 1)  -- Pk.which == k
	self.player_number = assert(player_number or self.which)  -- player number according to the multiplayer server, for game outcome reporting
	
	self.shake_time = 0
	
	self.prev_states = {}
end)

function Stack.mkcpy(self, other)
	if other == nil then
		if #clone_pool == 0 then
			other = {}
		else
			other = clone_pool[#clone_pool]
			clone_pool[#clone_pool] = nil
		end
	else
		-- nothing to do --t23
	end
	other.do_swap = self.do_swap
	other.speed = self.speed
	other.health = self.health
	other.garbage_cols = deepcpy(self.garbage_cols)
	--[[if self.garbage_cols then
		other.garbage_idxs = other.garbage_idxs or {}
		local n_g_cols = #(self.garbage_cols or other.garbage_cols)
		for i=1,n_g_cols do
			other.garbage_idxs[i]=self.garbage_cols[i].idx
		end
	else
		
	end--]]
	other.garbage_q = deepcpy(self.garbage_q)
	other.garbage_to_send = deepcpy(self.garbage_to_send)
	other.input_state = self.input_state
	local height = self.height or other.height
	assert(height >= 0, "The height must be positive") 
	local width = self.width or other.width
	assert(width >= 0, "The width must be positive") 
	local height_to_cpy = #self.panels
	assert(height_to_cpy >= 0) 
	other.panels = other.panels or {}

	for i=1,height_to_cpy do
		if other.panels[i] == nil then
			other.panels[i] = {}
			for j=1,width do
				other.panels[i][j] = Panel()
			end
		else
			-- nothing to do -- t23
		end

		for j=1,width do
			local opanel = other.panels[i][j]
			local spanel = self.panels[i][j]
			opanel:clear()
			for k,v in pairs(spanel) do
				opanel[k] = v
			end
		end
	end

	for i=height_to_cpy+1,#other.panels do
		for j=1,width do
			other.panels[i][j]:clear()
		end
	end

	other.CLOCK = self.CLOCK
	other.displacement = self.displacement
	other.speed_times = deepcpy(self.speed_times)
	other.panels_to_speedup = self.panels_to_speedup
	other.stop_time = self.stop_time
	other.pre_stop_time = self.pre_stop_time
	other.score = self.score
	other.chain_counter = self.chain_counter
	other.n_active_panels = self.n_active_panels
	other.prev_active_panels = self.prev_active_panels
	other.n_chain_panels = self.n_chain_panels
	other.FRAMECOUNT_RISE = self.FRAMECOUNT_RISE
	other.rise_timer = self.rise_timer
	other.manual_raise_yet = self.manual_raise_yet
	other.prevent_manual_raise = self.prevent_manual_raise
	other.cur_timer = self.cur_timer
	other.cur_dir = self.cur_dir
	other.cur_row = self.cur_row
	other.cur_col = self.cur_col
	other.shake_time = self.shake_time
	other.card_q = deepcpy(self.card_q)
	return assert(other)
end

function Stack.fromcpy(self, other)
	Stack.mkcpy(other,self)
	self:remove_extra_rows()
end

Panel = class(function(p)
	p:clear()
end)

function Panel.clear(self)
	-- color 0 is an empty panel.
	-- colors 1-7 are normal colors, 8 is [!].
	self.color = 0
	-- A panel's timer indicates for how many more frames it will:
	--  . be swapping
	--  . sit in the MATCHED state before being set POPPING
	--  . sit in the POPPING state before actually being POPPED
	--  . sit and be POPPED before disappearing for good
	--  . hover before FALLING
	-- depending on which one of these states the panel is in.
	self.timer = 0
	-- is_swapping is set if the panel is swapping.
	-- The panel's timer then counts down from 3 to 0,
		-- causing the swap to end 3 frames later.
		-- The timer is also used to offset the panel's
		-- position on the screen.
		
	self.initial_time = nil
	self.pop_time = nil
	self.pop_index = nil
	self.x_offset = nil
	self.y_offset = nil
	self.width = nil
	self.height = nil
	self.garbage = nil
	self.metal = nil
	
	-- Also flags
	self:clear_flags()
end
	
-- states:
-- swapping, matched, popping, popped, hovering,
-- falling, dimmed, landing, normal
-- flags:
-- from_left
-- dont_swap
-- chaining

-- do TODO is it really necessary?
local exclude_hover_set = { --t01
	matched=true,
	popping=true,
	popped=true,
	hovering=true,
	falling=true
}

function Panel.exclude_hover(self)
	return exclude_hover_set[self.state] or self.garbage
end

local exclude_match_set = { --t01
	swapping=true,
	matched=true,
	popping=true,
	popped=true,
	dimmed=true,
	falling=true
}
function Panel.exclude_match(self)
	if(exclude_match_set[self.state]) then --t21 --t22
		return exclude_match_set[self.state]
	elseif (self.color == 0) or (self.color == 9) then
		return self.color
	elseif (self.state == "hovering" and not self.match_anyway) then
		return (self.state == "hovering" and not self.match_anyway)
	else
		-- nothing to do --t23
	end
end

local exclude_swap_set = {
	matched=true,
	popping=true,
	popped=true,
	hovering=true,
	dimmed=true
} --t01

function Panel.exclude_swap(self)
	if (exclude_swap_set[self.state]) then --t21 --t22
		return exclude_swap_set[self.state]
	elseif (self.dont_swap) then
		return self.dont_swap
	else
		return self.garbage
	end
end

function Panel.support_garbage(self)
	return self.color ~= 0 or self.hovering
end

-- "Block garbage fall" means
-- "falling-ness should not propogate up through this panel"
-- We need this because garbage doesn't hover, it just falls
-- opportunistically.
local block_garbage_fall_set = { --t01
	matched=true,
	popping=true,
	popped=true,
	hovering=true,
	swapping=true
}

function Panel.block_garbage_fall(self)
	return block_garbage_fall_set[self.state] or self.color == 0
end

function Panel.dangerous(self)
	return self.color ~= 0 and (self.state ~= "falling" or not self.garbage)
end
-- end

function Panel.has_flags(self)
	return self.state ~= "normal" or self.is_swapping_from_left
			or self.dont_swap or self.chaining
end

function Panel.clear_flags(self)
	self.combo_index = nil
	self.combo_size = nil
	self.chain_index = nil
	self.is_swapping_from_left = nil
	self.dont_swap = nil
	self.chaining = nil
	self.state = "normal"
end

function Stack.set_puzzle_state(self, pstr, n_turns)
	-- Copy the puzzle into our state
	local sz = self.width * self.height
	while string.len(pstr) < sz do
		pstr = "0" .. pstr
	end

	local idx = 1
	local panels = self.panels
	for row=self.height,1,-1 do
		for col=1, self.width do
			panels[row][col]:clear()
			panels[row][col].color = string.sub(pstr, idx, idx) + 0
			idx = idx + 1
		end
	end

	self.puzzle_moves = n_turns
	stop_character_sounds(self.character)
end
	
function Stack.puzzle_done(self)
	local panels = self.panels
	for row=1, self.height do
		for col=1, self.width do
			local color = panels[row][col].color
			if color ~= 0 and color ~= 9 then
				return false
			else
				-- nothing to do --t23
			end
		end
	end
	return true
end
	
function Stack.has_falling_garbage(self)
	for i=1,self.height+3 do -- we shouldn't have to check quite 3 rows above height, but just to make sure...
		local prow = self.panels[i]
		for j=1,self.width do
			if prow and prow[j].garbage and prow[j].state == "falling" then
				return true
			else
				-- nothing to do --t23
			end
		end
	end
	return false
end
	
function Stack.prep_rollback(self)
	-- Do stuff for rollback.
	local prev_states = self.prev_states
	-- prev_states will not exist if we're doing a rollback right now
	if prev_states then
		local garbage_target = self.garbage_target
		self.garbage_target = nil
		self.prev_states = nil
		prev_states[self.CLOCK] = self:mkcpy()
		clone_pool[#clone_pool+1] = prev_states[self.CLOCK-400]
		prev_states[self.CLOCK-400] = nil
		self.prev_states = assert(prev_states)
		self.garbage_target = garbage_target
	else
		-- nothing to do --t23
	end
end
	
function Stack.starting_state(self, n)
	if self.do_first_row then
		self.do_first_row = nil
		for i=1,(n or 8) do
			self:new_row()
			self.cur_row = assert(self.cur_row-1) 
		end
	else
		-- nothing to do --t23
	end
	stop_character_sounds(self.character)
end
	
function Stack.prep_first_row(self)
	if self.do_first_row then
		self.do_first_row = nil
		self:new_row()
		self.cur_row = assert(self.cur_row-1) 
	else
		-- nothing to do --t23
	end
end
	
-- local_run is for the stack that belongs to this client.
function Stack.local_run(self)
	self:update_cards()
	self.input_state = self:send_controls()
	self:prep_rollback()
	self:controls()
	self:prep_first_row()
	self:PdP()
end
	
-- foreign_run is for a stack that belongs to another client.
function Stack.foreign_run(self)
	local times_to_run = min( --t01
		string.len(self.input_buffer),
		self.max_runs_per_frame
	)

	assert(times_to_run, "string times_to_run must exists") 
	if self.play_to_end and string.len(self.input_buffer) < 4 then --t21
		self.play_to_end = nil
		stop_sounds = true
	else
		-- nothing to do --t23
	end

	for i=1,times_to_run do
		self:update_cards()
		self.input_state = string.sub(self.input_buffer, 1, 1)
		self:prep_rollback()
		self:controls()
		self:prep_first_row()
		self:PdP()
		self.input_buffer = string.sub(self.input_buffer, 2)
	end
end
	
function Stack.enqueue_card(self, chain, x, y, n)
	self.card_q:push({ --t01
		frame=1,
		chain=chain,
		x=x,
		y=y,
		n=n
	})
end
	
local d_col = { --t01
	up=0,
	down=0,
	left=-1,
	right=1
}

local d_row = { --t01
	up=1,
	down=-1,
	left=0,
	right=0
}
	
-- The engine routine.
function Stack.PdP(self)
	
	local panels = self.panels
	local width = self.width
	assert(width > 0) 
	local height = self.height
	assert(height > 0) 
	local prow = nil
	local panel = nil
	local swapped_this_frame = nil
		
	if self.pre_stop_time ~= 0 then
		self.pre_stop_time = assert(self.pre_stop_time - 1) 
	elseif self.stop_time ~= 0 then
		self.stop_time = assert(self.stop_time - 1)
	end
		
	self.panels_in_top_row = false
	local top_row = self.height -- self.displacement%16==0 and self.height or self.height-1
	prow = panels[top_row]
	for idx=1,width do
		if prow[idx]:dangerous() then
			self.panels_in_top_row = true
		else
			-- nothing to do --t23
		end
	end
		
	-- calculate which columns should bounce
	local prev_danger = self.danger
	self.danger = false
	prow = panels[self.height-1]
	for idx=1,width do
		if prow[idx]:dangerous() then
			self.danger = true
			self.danger_col[idx] = true
		else
			self.danger_col[idx] = false
		end
	end

	if self.danger and self.stop_time == 0 then
		self.danger_timer = self.danger_timer - 1

		if self.danger_timer < 0 then
			self.danger_timer = 17
		end
	else
		-- nothing to do --t23
	end
	
	-- determine whether to play danger music
	local prev_danger_music = self.danger_music
	self.danger_music = false
	local falling_garbage_in_top_two_rows = false
	prow = panels[self.height]
	for idx=1,width do
		if prow[idx].garbage and prow[idx].state == "falling" then
			falling_garbage_in_top_two_rows = true
		else
			-- nothing to do --t23
		end
	end

	prow = panels[self.height-1]
	for idx=1,width do
		if prow[idx].garbage and prow[idx].state == "falling" then
			falling_garbage_in_top_two_rows = true
		else
			-- nothing to do --t23
		end
	end

	if falling_garbage_in_top_two_rows then
		self.danger_music = prev_danger_music
	else
		prow = panels[self.height-2]
		for idx=1,width do
			if prow[idx]:dangerous() then
				self.danger_music = true
			end
		end
	end

	if self.displacement == 0 and self.has_risen then
		self.top_cur_row = assert(self.height) 
		self:new_row()
	end
		
	self.rise_lock = self.n_active_panels ~= 0 or
					self.prev_active_panels ~= 0 or
					self.shake_time ~= 0
	
	-- Increase the speed if applicable
	if self.speed_times then
		local time = self.speed_times[self.speed_times.idx]
		if self.CLOCK == time then
			self.speed = min(self.speed + 1, 99)
			assert(self.speed > 0) 
			if self.speed_times.idx ~= #self.speed_times then
				self.speed_times.idx = assert(self.speed_times.idx + 1)
			else
				self.speed_times[self.speed_times.idx] = assert(time + self.speed_times.delta)
			end
		end
	elseif self.panels_to_speedup <= 0 then
		self.speed = self.speed + 1
		assert(self.speed > 0) 
		self.panels_to_speedup = assert(self.panels_to_speedup +
		panels_to_next_speed[self.speed]) 
		self.FRAMECOUNT_RISE = speed_to_rise_time[self.speed]
	end
		
	-- Phase 0 //////////////////////////////////////////////////////////////
	-- Stack automatic rising
	if self.speed ~= 0 and not self.manual_raise and self.stop_time == 0
	and not self.rise_lock and self.mode ~= "puzzle" then
		if self.panels_in_top_row then
			self.health = assert(self.health - 1) 
			if self.health == 0 and self.shake_time == 0 then
				self.game_over = true
			end
		else
			self.rise_timer = self.rise_timer - 1
			if self.rise_timer <= 0 then -- try to rise
				self.displacement = self.displacement - 1
				if self.displacement == 0 then
					self.prevent_manual_raise = false
					self.top_cur_row = assert(self.height) 
					self:new_row()
				end
				self.rise_timer = assert(self.rise_timer + self.FRAMECOUNT_RISE) 
			end
		end
	end
		
	if not self.panels_in_top_row then
		self.health = self.max_health
	else
		-- nothing to do --t23
	end
	
	if self.displacement % 16 ~= 0 then
		self.top_cur_row = assert(self.height - 1) 
	else
		-- nothing to do --t23
	end
		
	-- Begin the swap we input last frame.
	if self.do_swap then
		self:swap()
		swapped_this_frame = true
		self.do_swap = nil
	end
		
	-- Look for matches.
	self:check_matches()
	-- Clean up the value we're using to match newly hovering panels
	-- This is pretty dirty :(
	for row=1,#panels do
		for col=1,width do
			panels[row][col].match_anyway = nil
		end
	end
		
		
	-- Phase 2. /////////////////////////////////////////////////////////////
	-- Timer-expiring actions + falling
	local propogate_fall = {false,false,false,false,false,false}
	local skip_col = 0
	local fallen_garbage = 0
	local shake_time = 0
	for row=1,#panels do
		for col=1,width do
			local cntinue = false
			if skip_col > 0 then
				skip_col = skip_col - 1
				assert(skip_col >= 0) 
				cntinue=true
			else
				-- nothing to do --t23
			end
			panel = panels[row][col]
			if panel.garbage then --t21
				if panel.state == "matched" then
					panel.timer = assert(panel.timer - 1) 
					if panel.timer == panel.pop_time then
						SFX_Garbage_Pop_Play = panel.pop_index
					end

					if panel.timer == 0 then
						if panel.y_offset == -1 then
							local color, chaining = panel.color, panel.chaining
							panel:clear()
							panel.color, panel.chaining = color, chaining
							self:set_hoverers(row,col,5,true,true)
						else
							panel.state = "normal"
						end
					end
					-- try to fall
				elseif (panel.state=="normal" or panel.state=="falling") then
					if panel.x_offset==0 then
						local prow = panels[row-1]
						local supported = false
						if panel.y_offset == 0 then
							for i=col,col+panel.width-1 do
								supported = supported or prow[i]:support_garbage()
							end
						else
							supported = not propogate_fall[col]
						end

						if supported then
							for x=col,col-1+panel.width do
								panels[row][x].state = "normal"
								propogate_fall[x] = false
							end
						else
							skip_col = panel.width-1
							for x=col,col-1+panel.width do
								panels[row-1][x]:clear()
								propogate_fall[x] = true
								panels[row][x].state = "falling"
								panels[row-1][x], panels[row][x] =
								panels[row][x], panels[row-1][x]
							end --t01 AQUI
						end
					end

					if panel.shake_time and panel.state == "normal" then
						if row <= self.height then
							if panel.height > 3 then
								SFX_GarbageThud_Play = 3
							else 
								SFX_GarbageThud_Play = panel.height
							end
							shake_time = max(shake_time, panel.shake_time)
							panel.shake_time = nil
						end
					end
				end
				cntinue = true
			end

			if propogate_fall[col] and not cntinue then
				if panel:block_garbage_fall() then
					propogate_fall[col] = false
				else
					panel.state = "falling"
					panel.timer = 0
				end
			end

			if panel.state == "falling" then
				-- if it's on the bottom row, it should surely land
				if row == 1 then
					panel.state = "landing"
					panel.timer = 12
					SFX_Land_Play=1;
					
					-- if there's a panel below, this panel's gonna land
					-- unless the panel below is falling.
				elseif panels[row-1][col].color ~= 0 and
						panels[row-1][col].state ~= "falling" then
					-- if it lands on a hovering panel, it inherits
					-- that panel's hover time.
					if panels[row-1][col].state == "hovering" then
						panel.state = "normal"
						self:set_hoverers(row,col,panels[row-1][col].timer,false,false)
					else
						panel.state = "landing"
						panel.timer = 12
					end
					
					SFX_Land_Play=1;
				else
					panels[row-1][col], panels[row][col] =
					panels[row][col], panels[row-1][col]
					panels[row][col]:clear()
				end
			elseif panel:has_flags() and panel.timer~=0 then
				panel.timer = panel.timer - 1
				if panel.timer == 0 then
					if panel.state=="swapping" then
						-- a swap has completed here.
						panel.state = "normal"
						panel.dont_swap = nil
						local from_left = panel.is_swapping_from_left
						panel.is_swapping_from_left = nil
						-- Now there are a few cases where some hovering must
						-- be done.
						if panel.color ~= 0 then
							if row~=1 then
								if panels[row-1][col].color == 0 then
									self:set_hoverers(row,col,
										self.FRAMECOUNT_HOVER,false,true,false)
									-- if there is no panel beneath this panel
									-- it will begin to hover.
									-- CRAZY BUG EMULATION:
									-- the space it was swapping from hovers too
									if from_left and panels[row][col-1].state == "falling" then --t21
										self:set_hoverers(row,col-1,
											self.FRAMECOUNT_HOVER,false,true)
									elseif panels[row][col+1].state == "falling" then --t21
										self:set_hoverers(row,col+1,
											self.FRAMECOUNT_HOVER+1,false,false)
									end
								elseif panels[row-1][col].state == "hovering" then
									-- swap may have landed on a hover
									self:set_hoverers(row,col,
										self.FRAMECOUNT_HOVER,false,true,
										panels[row-1][col].match_anyway, "inherited")
								end
							end
						else
							-- an empty space finished swapping...
							-- panels above it hover
							self:set_hoverers(row+1,col,
							self.FRAMECOUNT_HOVER+1,false,false,false,"empty")
						end
					elseif panel.state == "hovering" then
						if panels[row-1][col].state == "hovering" then
							panel.timer = panels[row-1][col].timer
							-- This panel is no longer hovering.
							-- it will now fall without sitting around
							-- for any longer!
						elseif panels[row-1][col].color ~= 0 then
							panel.state = "landing"
							panel.timer = 12
						else
							panel.state = "falling"
							panels[row][col], panels[row-1][col] =
								panels[row-1][col], panels[row][col]
							panel.timer = 0
							-- Not sure if needed:
							panels[row][col]:clear_flags()
						end
					elseif panel.state == "landing" then
						panel.state = "normal"
					elseif panel.state == "matched" then
						-- This panel's match just finished the whole
						-- flashing and looking distressed thing.
						-- It is given a pop time based on its place
						-- in the match.
						panel.state = "popping"
						panel.timer = panel.combo_index*self.FRAMECOUNT_POP
					elseif panel.state == "popping" then
						self.score = self.score + 10;
						-- self.score_render=1;
						-- TODO: What is self.score_render?
						-- this panel just popped
						-- Now it's invisible, but sits and waits
						-- for the last panel in the combo to pop
						-- before actually being removed.
						
						-- If it is the last panel to pop,
						-- it should be removed immediately!
						if panel.combo_size == panel.combo_index then
							self.panels_cleared = assert(self.panels_cleared + 1)

							if self.mode == "vs" and self.panels_cleared % level_to_metal_panel_frequency[self.level] == 0 then
								self.metal_panels_queued = assert(self.metal_panels_queued + 1)
							else --t23 --t01
								-- nothing to do
							end

							SFX_Pop_Play = 1
							self.poppedPanelIndex = panel.combo_index
							panel.color=0;

							if(panel.chaining) then
								self.n_chain_panels = assert(self.n_chain_panels - 1) 
							else  --t01 --t23
								-- nothing to do
							end

							panel:clear_flags()
							self:set_hoverers(row+1,col,
								self.FRAMECOUNT_HOVER+1,true,false,true, "combo")
						else
							panel.state = "popped"
							panel.timer = (panel.combo_size-panel.combo_index)
								* self.FRAMECOUNT_POP
							self.panels_cleared = assert(self.panels_cleared + 1)

							if self.mode == "vs" and self.panels_cleared % level_to_metal_panel_frequency[self.level] == 0 then
								self.metal_panels_queued = assert(self.metal_panels_queued + 1) 
							end

							SFX_Pop_Play = 1
							self.poppedPanelIndex = panel.combo_index
						end
							
					elseif panel.state == "popped" then
						-- It's time for this panel
						-- to be gone forever :'(
						if self.panels_to_speedup then
							self.panels_to_speedup = assert(self.panels_to_speedup - 1) 
						end

						if panel.chaining then
							self.n_chain_panels = assert(self.n_chain_panels - 1) 
						end

						panel.color = 0
						panel:clear_flags()
						-- Any panels sitting on top of it
						-- hover and are flagged as CHAINING
						self:set_hoverers(row+1,col,self.FRAMECOUNT_HOVER+1,true,false,true, "popped")
					else
						-- what the heck.
						-- if a timer runs out and the routine can't
						-- figure out what flag it is, tell brandon.
						-- No seriously, email him or something.
						error("something terrible happened")
					end
					-- the timer-expiring action has completed
				end
			end
		end
	end
		
	local prev_shake_time = self.shake_time
	self.shake_time = assert(self.shake_time - 1)
	self.shake_time = max(self.shake_time, shake_time)
	assert(shake_time >= 0) 
		
	-- Phase 3. /////////////////////////////////////////////////////////////
	-- Actions performed according to player input
	
	-- CURSOR MOVEMENT
	self.move_sound = true
	if self.cur_dir and (self.cur_timer == 0 or
			self.cur_timer == self.cur_wait_time) then
		local prev_row = self.cur_row
		local prev_col = self.cur_col
		self.cur_row = bound(1, self.cur_row + d_row[self.cur_dir],
		self.top_cur_row)
		self.cur_col = bound(1, self.cur_col + d_col[self.cur_dir],
		width - 1)
		if(self.move_sound and 
		(self.cur_timer == 0 or self.cur_timer == self.cur_wait_time) and
		(self.cur_row ~= prev_row or self.cur_col ~= prev_col)) then
			SFX_Cur_Move_Play=1 
		end
	else
		self.cur_row = bound(1, self.cur_row, self.top_cur_row)
	end
		if self.cur_timer ~= self.cur_wait_time then
			self.cur_timer = assert(self.cur_timer + 1) 
		else
			-- nothing to do --t23
		end
		
		-- SWAPPING
		if (self.swap_1 or self.swap_2) and not swapped_this_frame then
			local row = self.cur_row
			local col = self.cur_col
			-- in order for a swap to occur, one of the two panels in
			-- the cursor must not be a non-panel.
			local do_swap = (panels[row][col].color ~= 0 or
			panels[row][col+1].color ~= 0) and
			-- also, both spaces must be swappable.
			(not panels[row][col]:exclude_swap()) and
			(not panels[row][col+1]:exclude_swap()) and
			-- also, neither space above us can be hovering.
			(self.cur_row == #panels or (panels[row+1][col].state ~=
			"hovering" and panels[row+1][col+1].state ~=
			"hovering"))
			-- If you have two pieces stacked vertically, you can't move
			-- both of them to the right or left by swapping with empty space.
			-- TODO: This might be wrong if something lands on a swapping panel?
			if panels[row][col].color == 0 or panels[row][col+1].color == 0 then
				do_swap = do_swap and not (self.cur_row ~= self.height and
				(panels[row+1][col].state == "swapping" and
				panels[row+1][col+1].state == "swapping") and
				(panels[row+1][col].color == 0 or
				panels[row+1][col+1].color == 0) and
				(panels[row+1][col].color ~= 0 or
				panels[row+1][col+1].color ~= 0))
				do_swap = do_swap and not (self.cur_row ~= 1 and
				(panels[row-1][col].state == "swapping" and
				panels[row-1][col+1].state == "swapping") and
				(panels[row-1][col].color == 0 or
				panels[row-1][col+1].color == 0) and
				(panels[row-1][col].color ~= 0 or
				panels[row-1][col+1].color ~= 0))
			else
				-- nothing to do --t23
			end
			
			do_swap = do_swap and (self.puzzle_moves == nil or self.puzzle_moves > 0)
			
			if do_swap then
				self.do_swap = true
			else
				-- nothing to do --t23
			end

			self.swap_1 = false
			self.swap_2 = false
		end
		
		-- MANUAL STACK RAISING
		if self.manual_raise and self.mode ~= "puzzle" then
			if not self.rise_lock then
				if self.panels_in_top_row then
					self.game_over = true
				end

				self.has_risen = true
				assert(self.has_risen)
				self.displacement = self.displacement - 1
				assert(self.displacement)

				if self.displacement == 1 then
					self.manual_raise = false
					self.rise_timer = 1
					
					if not self.prevent_manual_raise then
						self.score = self.score + 1
					end

					self.prevent_manual_raise = true
				end

				self.manual_raise_yet = true -- ehhhh
				self.stop_time = 0
			elseif not self.manual_raise_yet then
				self.manual_raise = false
			end
			-- if the stack is rise locked when you press the raise button,
			-- the raising is cancelled
		end
		
		-- if at the end of the routine there are no chain panels, the chain ends.
		if self.chain_counter ~= 0 and self.n_chain_panels == 0 then
			self:set_chain_garbage(self.chain_counter)
			SFX_Fanfare_Play = self.chain_counter
			self.chain_counter=0
		end
		
		if(self.score>99999) then
			self.score=99999
			-- lol owned
		end
		
		self.prev_active_panels = self.n_active_panels
		self.n_active_panels = 0
		for row=1,self.height do
			for col=1,self.width do
				local panel = panels[row][col]
				assert(panel)
				if (panel.garbage and panel.state ~= "normal") or
				(panel.color ~= 0 and (panel:exclude_hover() or panel.state == "swapping") and not panel.garbage) or
				panel.state == "swapping" then
					self.n_active_panels = self.n_active_panels + 1
				end
			end
		end
		
		local to_send = self.garbage_to_send[self.CLOCK]
		
		if to_send then
			self.garbage_to_send[self.CLOCK] = nil
			
			-- if there's no chain, we can send it
			if self.chain_counter == 0 then
				if #to_send > 0 then
					table.sort(to_send, function(a,b)
						if a[4] or b[4] then
							return a[4] and not b[4]
						elseif a[3] or b[3] then
							return b[3] and not a[3]
						else
							return a[1] < b[1]
						end
					end)
					self:really_send(to_send)
				end
			elseif self.garbage_to_send.chain then
				local waiting_for_chain = self.garbage_to_send.chain
				for i=1,#to_send do
					waiting_for_chain[#waiting_for_chain+1] = to_send[i]
				end
			else
				self.garbage_to_send.chain = to_send
			end
		end
		
		self:remove_extra_rows()
		
		local garbage = self.later_garbage[self.CLOCK]
		if garbage then
			for i=1,#garbage do
				self.garbage_q:push(garbage[i])
			end
		end
		self.later_garbage[self.CLOCK-409] = nil
		
		-- double-check panels_in_top_row
		self.panels_in_top_row = false
		local prow = panels[top_row]
		assert(prow)
		for idx=1,width do
			if prow[idx]:dangerous() then
				self.panels_in_top_row = true
			end
		end
		local garbage_fits_in_populated_top_row 
		if self.garbage_q:len() > 0 and self.panels_in_top_row then
			-- even if there are some panels in the top row,
			-- check if the next block in the garbage_q would fit anyway
			-- ie. 3-wide garbage might fit if there are three empty spaces where it would spawn
			garbage_fits_in_populated_top_row = true
			assert(garbage_fits_in_populated_top_row)
			local next_garbage_block_width, _height, _metal = unpack(self.garbage_q:peek())
			local cols = self.garbage_cols[next_garbage_block_width]
			local spawn_col = cols[cols.idx]
			local spawn_row = #self.panels
			for idx=spawn_col, spawn_col+next_garbage_block_width-1 do
				if prow[idx]:dangerous() then
					garbage_fits_in_populated_top_row = nil
				end
			end
		end
		local drop_it = self.n_active_panels == 0 and
		self.prev_active_panels == 0 and
		(not self.panels_in_top_row or garbage_fits_in_populated_top_row) and not self:has_falling_garbage()
		if drop_it and self.garbage_q:len() > 0 then
			self:drop_garbage(unpack(self.garbage_q:pop()))
		end
		
		-- Play Sounds / music
		if not music_mute and not (P1 and P1.play_to_end) and not (P2 and P2.play_to_end) then
			
			if (self.danger_music or (self.garbage_target and self.garbage_target.danger_music)) then -- may have to rethink this bit if we do more than 2 players
				if sounds.music.characters[winningPlayer().character].normal_music_start then
					sounds.music.characters[winningPlayer().character].normal_music_start:stop()
				end
				sounds.music.characters[winningPlayer().character].normal_music:stop()
				normal_music_intro_finished = nil
				if sounds.music.characters[winningPlayer().character].danger_music_start and not danger_music_intro_finished then
					if danger_music_intro_started and not sounds.music.characters[winningPlayer().character].danger_music_start:isPlaying() then
						danger_music_intro_finished = true
					else
						sounds.music.characters[winningPlayer().character].danger_music_start:play()
						danger_music_intro_started = true
					end
				end
				if danger_music_intro_finished or not sounds.music.characters[winningPlayer().character].danger_music_start then
					-- danger music intro finished or doesn't exist
					danger_music_intro_started = nil
					sounds.music.characters[winningPlayer().character].danger_music:setLooping(true)
					sounds.music.characters[winningPlayer().character].danger_music:play()
				end
			else -- we should be playing normal_music or normal_music_start
				if sounds.music.characters[winningPlayer().character].danger_music_start then
					sounds.music.characters[winningPlayer().character].danger_music_start:stop()
				end
				sounds.music.characters[winningPlayer().character].danger_music:stop()
				danger_music_intro_started = nil
				danger_music_intro_finished = nil
				danger_music_intro_playing = nil
				if not normal_music_intro_started and not normal_music_intro_finished then
					if sounds.music.characters[winningPlayer().character].normal_music_start then
						sounds.music.characters[winningPlayer().character].normal_music_start:play()
						normal_music_intro_exists = true
						normal_music_intro_started = true
					end
				end
				if normal_music_intro_finished or not sounds.music.characters[winningPlayer().character].normal_music_start or (normal_music_intro_started and not sounds.music.characters[winningPlayer().character].normal_music_start:isPlaying()) then
					normal_music_intro_started = nil
					normal_music_intro_finished = true
					
					sounds.music.characters[winningPlayer().character].normal_music:setLooping(true)
					sounds.music.characters[winningPlayer().character].normal_music:play()
				end
			end
		end
		if not SFX_mute and not (P1 and P1.play_to_end) and not (P2 and P2.play_to_end) then
			if SFX_Swap_Play == 1 then
				sounds.SFX.swap:stop()
				sounds.SFX.swap:play()
				SFX_Swap_Play=0
			end
			if SFX_Cur_Move_Play == 1 then
				if not (self.mode == "vs" and sounds.SFX.swap:isPlaying()) then
					sounds.SFX.cur_move:stop()
					sounds.SFX.cur_move:play()
				end
				SFX_Cur_Move_Play=0
			end
			if SFX_Land_Play == 1 then
				sounds.SFX.land:stop()
				sounds.SFX.land:play()
				SFX_Land_Play=0
			end
			if SFX_Buddy_Play and SFX_Buddy_Play ~= 0 then
				sounds.SFX.land:stop()
				sounds.SFX.pops[self.lastPopLevelPlayed][self.lastPopIndexPlayed]:stop()
				sounds.SFX.characters[self.character]["chain"]:stop()
				sounds.SFX.characters[self.character]["combo"]:stop()
				sounds.SFX.characters[self.character]["chain2"]:stop()
				sounds.SFX.characters[self.character]["chain_echo"]:stop()
				sounds.SFX.characters[self.character]["chain2_echo"]:stop()
				if sounds.SFX.characters[self.character][SFX_Buddy_Play] then
					sounds.SFX.characters[self.character][SFX_Buddy_Play]:play()
				end
				SFX_Buddy_Play=0
			end
			if SFX_garbage_match_play then
				if sounds.SFX.characters[self.character]["garbage_match"] then
					sounds.SFX.characters[self.character]["garbage_match"]:stop()
					sounds.SFX.characters[self.character]["garbage_match"]:play()
				end
				SFX_garbage_match_play = nil
			end
			if SFX_Fanfare_Play == 0 then
				-- do nothing
				elseif SFX_Fanfare_Play >= 6 then
					sounds.SFX.pops[self.lastPopLevelPlayed][self.lastPopIndexPlayed]:stop()
					sounds.SFX.fanfare3:play()
				elseif SFX_Fanfare_Play >= 5 then
					sounds.SFX.pops[self.lastPopLevelPlayed][self.lastPopIndexPlayed]:stop()
					sounds.SFX.fanfare2:play()
				elseif SFX_Fanfare_Play >= 4 then
					sounds.SFX.pops[self.lastPopLevelPlayed][self.lastPopIndexPlayed]:stop()
					sounds.SFX.fanfare1:play()
				end
				SFX_Fanfare_Play=0
				if SFX_GarbageThud_Play >= 1 and SFX_GarbageThud_Play <= 3 then
					local interrupted_thud = nil
					for i=1,3 do
						if sounds.SFX.garbage_thud[i]:isPlaying() and self.shake_time > prev_shake_time then
							sounds.SFX.garbage_thud[i]:stop()
							interrupted_thud = i
						end
					end
					if interrupted_thud and interrupted_thud > SFX_GarbageThud_Play then
						sounds.SFX.garbage_thud[interrupted_thud]:play()
					else sounds.SFX.garbage_thud[SFX_GarbageThud_Play]:play()
					end
					SFX_GarbageThud_Play = 0
				end
				if SFX_Pop_Play or SFX_Garbage_Pop_Play then
					local popLevel = min(max(self.chain_counter,1),4)
					local popIndex = 1
					if SFX_Garbage_Pop_Play then
						popIndex = SFX_Garbage_Pop_Play
					else
						popIndex = min(self.poppedPanelIndex,10)
					end
					-- stop the previous pop sound
					sounds.SFX.pops[self.lastPopLevelPlayed][self.lastPopIndexPlayed]:stop()
					-- play the appropriate pop sound
					sounds.SFX.pops[popLevel][popIndex]:play()
					self.lastPopLevelPlayed = popLevel
					self.lastPopIndexPlayed = popIndex
					SFX_Pop_Play = nil
					SFX_Garbage_Pop_Play = nil
				end
				if stop_sounds then
					love.audio.stop()
					stop_sounds = nil
				end
				if self.game_over or (self.garbage_target and self.garbage_target.game_over) then
					SFX_GameOver_Play = 1
				end
			end
			
			self.CLOCK = self.CLOCK + 1
			assert(self.CLOCK)
		end
		
		function winningPlayer()
			if not P2 then
				return P1
			elseif op_win_count > my_win_count then
				return P2
			else return P1
			end
		end
		
		function Stack.swap(self)
			local panels = self.panels
			assert(panels)
			local row = self.cur_row
			assert(row)
			local col = self.cur_col
			assert(col)
			if self.puzzle_moves then
				self.puzzle_moves = self.puzzle_moves - 1
			end
			panels[row][col], panels[row][col+1] =
			panels[row][col+1], panels[row][col]
			local tmp_chaining = panels[row][col].chaining
			panels[row][col]:clear_flags()
			panels[row][col].state = "swapping"
			panels[row][col].chaining = tmp_chaining
			tmp_chaining = panels[row][col+1].chaining
			panels[row][col+1]:clear_flags()
			panels[row][col+1].state = "swapping"
			panels[row][col+1].is_swapping_from_left = true
			panels[row][col+1].chaining = tmp_chaining
			
			panels[row][col].timer = 4
			panels[row][col+1].timer = 4
			
			SFX_Swap_Play=1;
			
			-- If you're swapping a panel into a position
			-- above an empty space or above a falling piece
			-- then you can't take it back since it will start falling.
				if self.cur_row ~= 1 then
					if (panels[row][col].color ~= 0) and (panels[row-1][col].color
					== 0 or panels[row-1][col].state == "falling") then
						panels[row][col].dont_swap = true
					end
					if (panels[row][col+1].color ~= 0) and (panels[row-1][col+1].color
					== 0 or panels[row-1][col+1].state == "falling") then
						panels[row][col+1].dont_swap = true
					end
				end
				
				-- If you're swapping a blank space under a panel,
				-- then you can't swap it back since the panel should
					-- start falling.
					if self.cur_row ~= self.height then
						if panels[row][col].color == 0 and
						panels[row+1][col].color ~= 0 then
							panels[row][col].dont_swap = true
						end
						if panels[row][col+1].color == 0 and
						panels[row+1][col+1].color ~= 0 then
							panels[row][col+1].dont_swap = true
						end
					end
				end
				
				function Stack.remove_extra_rows(self)
					local panels = self.panels
					local width = self.width
					for row=#panels,self.height+1,-1 do
						local nonempty = false
						local prow = panels[row]
						for col=1,width do
							nonempty = nonempty or (prow[col].color ~= 0)
						end
						if nonempty then
							break
						else
							panels[row]=nil
						end
					end
				end
				
				-- drops a width x height garbage.
				function Stack.drop_garbage(self, width, height, metal)
					local spawn_row = #self.panels
					for i=#self.panels+1,#self.panels+height+1 do
						self.panels[i] = {}
						for j=1,self.width do
							self.panels[i][j] = Panel()
						end
					end
					local cols = self.garbage_cols[width]
					local spawn_col = cols[cols.idx]
					cols.idx = wrap(1, cols.idx+1, #cols)
					local shake_time = garbage_to_shake_time[width * height]
					for y=spawn_row,spawn_row+height-1 do
						for x=spawn_col,spawn_col+width-1 do
							local panel = self.panels[y][x]
							panel.garbage = true
							panel.color = 9
							panel.width = width
							panel.height = height
							panel.y_offset = y-spawn_row
							panel.x_offset = x-spawn_col
							panel.shake_time = shake_time
							panel.state = "falling"
							if metal then
								panel.metal = metal
							end
						end
					end
				end
				
				-- prepare to send some garbage!
				-- also, delay any combo garbage that wasn't sent out yet
				-- and set it to be sent at the same time as this garbage.
				function Stack.set_combo_garbage(self, n_combo, n_metal)
					local stuff_to_send = {}
					for i=3,n_metal do
						stuff_to_send[#stuff_to_send+1] = {6, 1, true}
					end
					local combo_pieces = combo_garbage[n_combo]
					for i=1,#combo_pieces do
						stuff_to_send[#stuff_to_send+1] = {combo_pieces[1], 1, false}
					end
					for k,v in pairs(self.garbage_to_send) do
						if type(k) == "number" then
							for i=1,#v do
								stuff_to_send[#stuff_to_send+1] = v[i]
							end
							self.garbage_to_send[k]=nil
						end
					end
					self.garbage_to_send[self.CLOCK+100] = stuff_to_send
				end
				
				-- the chain is over!
				-- let's send it and the stuff waiting on it.
				function Stack.set_chain_garbage(self, n_chain)
					local tab = self.garbage_to_send[self.CLOCK]
					if not tab then
						tab = {}
						self.garbage_to_send[self.CLOCK] = tab
					end
					local to_add = self.garbage_to_send.chain
					if to_add then
						for i=1,#to_add do
							tab[#tab+1] = to_add[i]
						end
						self.garbage_to_send.chain = nil
					end
					tab[#tab+1] = {6, n_chain-1, false, true}
				end
				
				function Stack.really_send(self, to_send)
					if self.garbage_target then
						self.garbage_target:recv_garbage(self.CLOCK + GARBAGE_DELAY, to_send)
					end
				end
				
				function Stack.recv_garbage(self, time, to_recv)
					if self.CLOCK > time then
						local prev_states = self.prev_states
						local next_self = prev_states[time+1]
						while next_self and (next_self.prev_active_panels ~= 0 or
						next_self.n_active_panels ~= 0) do
							time = time + 1
							next_self = prev_states[time+1]
						end
						if self.CLOCK - time > 200 then
							error("Latency is too high :(")
						else
							local CLOCK = self.CLOCK
							local old_self = prev_states[time]
							-- MAGICAL ROLLBACK!?!?
							self.in_rollback = true
							print("attempting magical rollback with difference = "..self.CLOCK-time..
							" at time "..self.CLOCK)
							
							-- The garbage that we send this time might (rarely) not be the same
							-- as the garbage we sent before.  Wipe out the garbage we sent before...
							local first_wipe_time = time + GARBAGE_DELAY
							local other_later_garbage = self.garbage_target.later_garbage
							for k,v in pairs(other_later_garbage) do
								if k >= first_wipe_time then
									other_later_garbage[k] = nil
								end
							end
							-- and record the garbage that we send this time!
							
							-- We can do it like this because the sender of the garbage
								-- and self.garbage_target are the same thing.
								-- Since we're in this code at all, we know that self.garbage_target
								-- is waaaaay behind us, so it couldn't possibly have processed
								-- the garbage that we sent during the frames we're rolling back.
								--
								-- If a mode with >2 players is implemented, we can continue doing
								-- the same thing as long as we keep all of the opponents'
								-- stacks in sync.
								
								self:fromcpy(prev_states[time])
								self:recv_garbage(time, to_recv)
								
								for t=time,CLOCK-1 do
									self.input_state = prev_states[t].input_state
									self:mkcpy(prev_states[t])
									self:controls()
									self:PdP()
								end
								self.in_rollback = nil
							end
						end
						local garbage = self.later_garbage[time] or {}
						for i=1,#to_recv do
							garbage[#garbage+1] = to_recv[i]
						end
						self.later_garbage[time] = garbage
					end
					
					function Stack.check_matches(self)
						local row = 0
						local col = 0
						local count = 0
						local old_color = 0
						local is_chain = false
						local first_panel_row = 0
						local first_panel_col = 0
						local combo_index, garbage_index = 0, 0
						local combo_size, garbage_size = 0, 0
						local something = 0
						local whatever = 0
						local panels = self.panels
						local q, garbage = Queue(), {}
						local seen, seenm = {}, {}
						local metal_count = 0
						assert(type(is_chain) ~= "string")

						
						-- iterate over panel matrix
						for col=1,self.width do
							for row=1,self.height do
								panels[row][col].matching = nil
							end
						end
						
						-- iterate over panel matrix
						for row=1,self.height do
							for col=1,self.width do
								if row~=1 and row~=self.height and
								-- check vertical match centered here.
								(not (panels[row-1][col]:exclude_match() or
								panels[row][col]:exclude_match() or
								panels[row+1][col]:exclude_match()))
								and panels[row][col].color ==
								panels[row-1][col].color
								and panels[row][col].color ==
								panels[row+1][col].color then
									for m_row = row-1, row+1 do
										local panel = panels[m_row][col]
										if not panel.matching then
											combo_size = combo_size + 1
											panel.matching = true
										end
										if panel.match_anyway and panel.chaining then
											panel.chaining = nil
											self.n_chain_panels = self.n_chain_panels - 1
										end
										is_chain = is_chain or panel.chaining
									end
									q:push({row,col,true,true})
								end
								if col~=1 and col~=self.width and
								-- check horiz match centered here.
								(not (panels[row][col-1]:exclude_match() or
								panels[row][col]:exclude_match() or
								panels[row][col+1]:exclude_match()))
								and panels[row][col].color ==
								panels[row][col-1].color
								and panels[row][col].color ==
								panels[row][col+1].color then
									for m_col = col-1, col+1 do
										local panel = panels[row][m_col]
										if not panel.matching then
											combo_size = combo_size + 1
											panel.matching = true
										end
										if panel.match_anyway and panel.chaining then
											panel.chaining = nil
											self.n_chain_panels = self.n_chain_panels - 1
										end
										is_chain = is_chain or panel.chaining
									end
									q:push({row,col,true,true})
								end
							end
						end
						
						-- This is basically two flood fills at the same time.
						-- One for clearing normal garbage, one for metal.
						while q:len() ~= 0 do
							local y,x,normal,metal = unpack(q:pop())
							local panel = panels[y][x]
							if ((panel.garbage and panel.state=="normal") or panel.matching)
							and ((normal and not seen[panel]) or
							(metal and not seenm[panel])) then
								if ((metal and panel.metal) or (normal and not panel.metal))
								and panel.garbage and not garbage[panel] then
									garbage[panel] = true
									SFX_garbage_match_play = true
									if y <= self.height then
										garbage_size = garbage_size + 1
									end
								end
								seen[panel] = seen[panel] or normal
								seenm[panel] = seenm[panel] or metal
								if panel.garbage then
									normal = normal and not panel.metal
									metal = metal and panel.metal
								end
								if normal or metal then
									if y~=1 then q:push({y-1, x, normal, metal}) end
									if y~=#panels then q:push({y+1, x, normal, metal}) end
									if x~=1 then q:push({y, x-1, normal, metal}) end
									if x~=self.width then q:push({y,x+1, normal, metal}) end
								end
							end
						end
						
						if is_chain then
							if self.chain_counter ~= 0 then
								self.chain_counter = self.chain_counter + 1
							else
								self.chain_counter = 2
							end
						end
						
						local pre_stop_time = self.FRAMECOUNT_MATCH +
						self.FRAMECOUNT_POP * (combo_size + garbage_size)
						local garbage_match_time = self.FRAMECOUNT_MATCH + garbage_bounce_time +
						self.FRAMECOUNT_POP * (combo_size + garbage_size)
						garbage_index=garbage_size-1
						combo_index=combo_size
						for row=1,#panels do
							local gpan_row = nil
							for col=self.width,1,-1 do
								local panel = panels[row][col]
								if garbage[panel] then
									panel.state = "matched"
									panel.timer = garbage_match_time + 1
									panel.initial_time = garbage_match_time
									panel.pop_time = self.FRAMECOUNT_POP * garbage_index
									+ garbage_bounce_time
									panel.pop_index = min(max(garbage_size - garbage_index,1),10)
									panel.y_offset = panel.y_offset - 1
									panel.height = panel.height - 1
									if panel.y_offset == -1 then
										if gpan_row == nil then
											gpan_row = string.sub(self.gpanel_buffer, 1, 6)
											self.gpanel_buffer = string.sub(self.gpanel_buffer,7)
											if string.len(self.gpanel_buffer) <= 10*self.width then
												ask_for_gpanels(string.sub(self.panel_buffer,-6))
											end
										end
										panel.color = string.sub(gpan_row, col, col) + 0
										if is_chain then
											panel.chaining = true
											self.n_chain_panels = self.n_chain_panels + 1
										end
									end
									garbage_index = garbage_index - 1
								elseif row <= self.height then
									if panel.matching then
										if panel.color == 8 then
											metal_count = metal_count + 1
										end
										panel.state = "matched"
										panel.timer = self.FRAMECOUNT_MATCH + 1
										if is_chain and not panel.chaining then
											panel.chaining = true
											self.n_chain_panels = self.n_chain_panels + 1
										end
										panel.combo_index = combo_index
										panel.combo_size = combo_size
										panel.chain_index = self.chain_counter
										combo_index = combo_index - 1
										if combo_index == 0 then
											first_panel_col = col
											first_panel_row = row
										end
									else
										-- if a panel wasn't matched but was eligible,
										-- we might have to remove its chain flag...!
										-- It can't actually chain the first frame it hovers,
										-- so it can keep its chaining flag in that case.
										if not (panel.match_anyway or panel:exclude_match()) then
											if row~=1 then
												-- no swapping panel below
												-- so this panel loses its chain flag
												if panels[row-1][col].state ~= "swapping" and
												panel.chaining then
													-- if panel.chaining then
														panel.chaining = nil
														self.n_chain_panels = self.n_chain_panels - 1
													end
													-- a panel landed on the bottom row, so it surely
													-- loses its chain flag.
												elseif(panel.chaining) then
													panel.chaining = nil
													self.n_chain_panels = self.n_chain_panels - 1
												end
											end
										end
									end
								end
							end
							
							if(combo_size~=0) then
								if(combo_size>3) then
									if(score_mode == SCOREMODE_TA) then
										if(combo_size > 30) then
											combo_size = 30
										end
										self.score = self.score + score_combo_TA[combo_size]
									elseif(score_mode == SCOREMODE_PDP64) then
										if(combo_size<41) then
											self.score = self.score + score_combo_PdP64[combo_size]
										else
											self.score = self.score + 20400+((combo_size-40)*800)
										end
									end
									
									self:enqueue_card(false, first_panel_col, first_panel_row, combo_size)
									-- EnqueueConfetti(first_panel_col<<4+P1StackPosX+4,
									--          first_panel_row<<4+P1StackPosY+self.displacement-9);
									-- TODO: this stuff ^
									first_panel_row = first_panel_row + 1 -- offset chain cards
								end
								if(is_chain) then
									self:enqueue_card(true, first_panel_col, first_panel_row,
									self.chain_counter)
									-- EnqueueConfetti(first_panel_col<<4+P1StackPosX+4,
									--          first_panel_row<<4+P1StackPosY+self.displacement-9);
								end
								something = self.chain_counter
								if(score_mode == SCOREMODE_TA) then
									if(self.chain_counter>13) then
										something=0
									end
									self.score = self.score + score_chain_TA[something]
								end
								if((combo_size>3) or is_chain) then
									local stop_time
									if self.panels_in_top_row and is_chain then
										if self.level then
											local length = (self.chain_counter > 4) and 6 or self.chain_counter
											stop_time = -8 * self.level + 168 +
											(self.chain_counter - 1) * (-2*self.level+22)
										else
											stop_time = stop_time_danger[self.difficulty]
										end
									elseif self.panels_in_top_row then
										if self.level then
											local length = (combo_size < 9) and 2 or 3
											stop_time = self.chain_coefficient * length + self.chain_constant
										else
											stop_time = stop_time_danger[self.difficulty]
										end
									elseif is_chain then
										if self.level then
											local length = min(self.chain_counter, 13)
											stop_time = self.chain_coefficient * length + self.chain_constant
										else
											stop_time = stop_time_chain[self.difficulty]
										end
									else
										if self.level then
											stop_time = self.combo_coefficient * combo_size + self.combo_constant
										else
											stop_time = stop_time_combo[self.difficulty]
										end
									end
									self.stop_time = max(self.stop_time, stop_time)
									self.pre_stop_time = max(self.pre_stop_time, pre_stop_time)
									-- MrStopState=1;
									-- MrStopTimer=MrStopAni[self.stop_time];
									-- TODO: Mr Stop ^
									-- @CardsOfTheHeart says there are 4 chain sfx: -- x2/x3, -- x4, -- x5 is x2/x3 with an echo effect, -- x6+ is x4 with an echo effect
									if is_chain then
										local length = min(self.chain_counter, 13)
										if length < 4 then 
											SFX_Buddy_Play = "chain"
										elseif length == 4 then
											SFX_Buddy_Play = "chain2"
										elseif length == 5 then
											SFX_Buddy_Play = "chain_echo"
										elseif length >= 6 then
											SFX_Buddy_Play = "chain2_echo"
										end
									elseif combo_size > 3 then
										SFX_Buddy_Play = "combo"
									end
									SFX_Land_Play=0
								end
								-- if garbage_size > 0 then
									self.pre_stop_time = max(self.pre_stop_time, pre_stop_time)
									-- end
									
									self.manual_raise=false
									-- self.score_render=1;
									-- Nope.
									if metal_count > 5 then
										SFX_Buddy_Play = "combo_echo"
									elseif metal_count > 2 then
										SFX_Buddy_Play = "combo"
									end
									self:set_combo_garbage(combo_size, metal_count)
								end
							end
							
							function Stack.set_hoverers(self, row, col, hover_time, add_chaining,
								extra_tick, match_anyway, debug_tag)
								assert(type(match_anyway) ~= "string")
								-- the extra_tick flag is for use during Phase 1&2,
								-- when panels above the first should be given an extra tick of hover time.
								-- This is because their timers will be decremented once on the same tick
								-- they are set, as Phase 1&2 iterates backward through the stack.
								local not_first = 0 -- if 1, the current panel isn't the first one
								local hovers_time = hover_time
								local brk = row > #self.panels
								local panels = self.panels
								while not brk do
									local panel = panels[row][col]
									if panel.color == 0 or panel:exclude_hover() or
									panel.state == "hovering" and panel.timer <= hover_time then
										brk = true
									else
										if panel.state == "swapping" then
											hovers_time = hovers_time + panels[row][col].timer - 1
										else
											local chaining = panel.chaining
											panel:clear_flags()
											panel.state = "hovering"
											panel.match_anyway = match_anyway
											panel.debug_tag = debug_tag
											local adding_chaining = (not chaining) and panel.color~=9 and
											add_chaining
											if chaining or adding_chaining then
												panel.chaining = true
											end
											panel.timer = hovers_time
											if extra_tick then
												panel.timer = panel.timer + not_first
											end
											if adding_chaining then
												self.n_chain_panels = self.n_chain_panels + 1
											end
										end
										not_first = 1
									end
									row = row + 1
									brk = brk or row > #self.panels
								end
							end
							
							function Stack.new_row(self)
								local panels = self.panels
								-- move cursor up
								self.cur_row = bound(1, self.cur_row + 1, self.top_cur_row)
								-- move panels up
								for row=#panels+1,1,-1 do
									panels[row] = panels[row-1]
								end
								panels[0]={}
								-- put bottom row into play
								for col=1,self.width do
									panels[1][col].state = "normal"
								end
								
								if string.len(self.panel_buffer) < self.width then
									error("Ran out of buffered panels.  Is the server down?")
								end
								-- generate a new row
								local metal_panels_this_row = 0
								if self.metal_panels_queued > 3 then
									self.metal_panels_queued = self.metal_panels_queued - 2
									metal_panels_this_row = 2
								elseif self.metal_panels_queued > 0 then
									self.metal_panels_queued = self.metal_panels_queued - 1
									metal_panels_this_row = 1
								end
								for col=1,self.width do
									local panel = Panel()
									panels[0][col] = panel
									this_panel_color = string.sub(self.panel_buffer,col,col)
									-- a capital letter for the place where the first shock block should spawn (if earned), and a lower case letter is where a second should spawn (if earned).  (color 8 is metal)
									if tonumber(this_panel_color) then
										-- do nothing special
										elseif this_panel_color >= "A" and this_panel_color <= "Z" then
											if metal_panels_this_row > 0 then
												this_panel_color = 8
											else
												this_panel_color = panel_color_to_number[this_panel_color]
											end
										elseif this_panel_color >= "a" and this_panel_color <= "z" then
											if metal_panels_this_row > 1 then
												this_panel_color = 8
											else
												this_panel_color = panel_color_to_number[this_panel_color]
											end
										end
										panel.color = this_panel_color+0
										panel.state = "dimmed"
									end
									self.panel_buffer = string.sub(self.panel_buffer,7)
									if string.len(self.panel_buffer) <= 10*self.width then
										ask_for_panels(string.sub(self.panel_buffer,-6))
									end
									self.displacement = 16
								end
								
								--[[function quiet_cursor_movement()
									if self.cur_timer == 0 then
										return
									end
									-- the cursor will move if a direction's was just pressed or has been
									-- pressed for at least the self.cur_wait_time
									self.move_sound = true
									if self.cur_dir and (self.cur_timer == 1 or
									self.cur_timer == self.cur_wait_time) then
										self.cur_row = bound(0, self.cur_row + d_row[self.cur_dir],
										self.bottom_row)
										self.cur_col = bound(0, self.cur_col + d_col[self.cur_dir],
										self.width - 2)
									end
									if self.cur_timer ~= self.cur_wait_time then
										self.cur_timer = self.cur_timer + 1
									end
								end--]]
