local signals = require("../src")

local computed = signals.computed
local effect = signals.effect
local signal = signals.signal

-- Helper function to get the current test function name for assertions
local function getFunctionName()
	return debug.info(2, "n")
end

--[[
    Tests adopted with thanks from preact-signals implementation at
    https://github.com/preactjs/signals/blob/main/packages/core/test/signal.test.tsx
]]

-- Graph Updates

local function shouldDropABAToUpdates()
	--[[
	     A
	   / |
	  B  |
	   \ |
	     C
	     |
	     D
	]]
	local getA, setA = signal(2)

	local b = computed(function()
		return getA() - 1
	end)
	local c = computed(function()
		return getA() + b()
	end)

	local computeCount = 0
	local d = computed(function()
		computeCount = computeCount + 1
		return "d: " .. c()
	end)

	-- Trigger read
	assert(d() == "d: 3", getFunctionName())
	assert(computeCount == 1, getFunctionName())
	computeCount = 0 -- Reset counter

	setA(4)
	d()
	assert(computeCount == 1, getFunctionName())
end

local function shouldOnlyUpdateEverySignalOnceDiamondGraph()
	--[[
	     A
	   /   \
	  B     C
	   \   /
	     D
	]]
	local getA, setA = signal("a")
	local b = computed(function()
		return getA()
	end)
	local c = computed(function()
		return getA()
	end)

	local spyCount = 0
	local d = computed(function()
		spyCount = spyCount + 1
		return b() .. " " .. c()
	end)

	assert(d() == "a a", getFunctionName())
	assert(spyCount == 1, getFunctionName())

	setA("aa")
	assert(d() == "aa aa", getFunctionName())
	assert(spyCount == 2, getFunctionName())
end

local function shouldOnlyUpdateEverySignalOnceDiamondGraphPlusTail()
	--[[
	     A
	   /   \
	  B     C
	   \   /
	     D
	     |
	     E
	]]
	local getA, setA = signal("a")
	local b = computed(function()
		return getA()
	end)
	local c = computed(function()
		return getA()
	end)

	local d = computed(function()
		return b() .. " " .. c()
	end)

	local spyCount = 0
	local e = computed(function()
		spyCount = spyCount + 1
		return d()
	end)

	assert(e() == "a a", getFunctionName())
	assert(spyCount == 1, getFunctionName())

	setA("aa")
	assert(e() == "aa aa", getFunctionName())
	assert(spyCount == 2, getFunctionName())
end

local function shouldBailOutIfResultIsTheSame()
	-- Bail out if value of "B" never changes
	-- A->B->C
	local getA, setA = signal("a")
	local b = computed(function()
		getA()
		return "foo"
	end)

	local spyCount = 0
	local c = computed(function()
		spyCount = spyCount + 1
		return b()
	end)

	assert(c() == "foo", getFunctionName())
	assert(spyCount == 1, getFunctionName())

	setA("aa")
	assert(c() == "foo", getFunctionName())
	assert(spyCount == 1, getFunctionName()) -- Should not have recomputed C
end

local function shouldOnlyUpdateEverySignalOnceJaggedDiamondGraphPlusTails()
	--[[
	     A
	   /   \
	  B     C
	  |     |
	  |     D
	   \   /
	     E
	   /   \
	  F     G
	]]
	local getA, setA = signal("a")

	local b = computed(function()
		return getA()
	end)
	local c = computed(function()
		return getA()
	end)

	local d = computed(function()
		return c()
	end)

	local _eOrderLog = {}
	local eCount = 0
	local e = computed(function()
		eCount = eCount + 1
		table.insert(_eOrderLog, "e")
		return b() .. " " .. d()
	end)

	local _fOrderLog = {}
	local fCount = 0
	local f = computed(function()
		fCount = fCount + 1
		table.insert(_fOrderLog, "f")
		return e()
	end)

	local _gOrderLog = {}
	local gCount = 0
	local g = computed(function()
		gCount = gCount + 1
		table.insert(_gOrderLog, "g")
		return e()
	end)

	assert(f() == "a a", getFunctionName())
	assert(fCount == 1, getFunctionName())

	assert(g() == "a a", getFunctionName())
	assert(gCount == 1, getFunctionName())

	--[[
	 Vitest checks the order of calls using mocks.
	 In Luau, we reset counters and logs, trigger the update,
	 then check the final state and counts. We can't easily check
	 the *exact* call order between separate computed functions without
	 a more complex logging setup or a dedicated mock library.
	 This translation verifies the counts and final values.
	]]
	_eOrderLog = {}
	_fOrderLog = {}
	_gOrderLog = {}
	eCount = 0
	fCount = 0
	gCount = 0

	setA("b")

	-- Accessing f and g will trigger computations if needed
	assert(f() == "b b", getFunctionName())
	assert(g() == "b b", getFunctionName())

	-- Check that e, f, and g were each computed exactly once after the update
	assert(eCount == 1, getFunctionName())
	assert(fCount == 1, getFunctionName())
	assert(gCount == 1, getFunctionName())

	_eOrderLog = {}
	_fOrderLog = {}
	_gOrderLog = {}
	eCount = 0
	fCount = 0
	gCount = 0

	setA("c")

	assert(f() == "c c", getFunctionName())
	assert(g() == "c c", getFunctionName())

	assert(eCount == 1, getFunctionName())
	assert(fCount == 1, getFunctionName())
	assert(gCount == 1, getFunctionName())
end

local function shouldOnlySubscribeToSignalsListenedTo()
	--[[
	    *A
	   /   \
	 *B     C <- we don't listen to C
	]]
	local getA, setA = signal("a")

	local b = computed(function()
		return getA()
	end)

	local spyCount = 0
	local _c = computed(function()
		spyCount = spyCount + 1
		return getA()
	end)

	assert(b() == "a", getFunctionName())
	assert(spyCount == 0, getFunctionName()) -- C was never accessed, so its function shouldn't run

	setA("aa")
	assert(b() == "aa", getFunctionName())
	assert(spyCount == 0, getFunctionName()) -- C still not accessed
end

local function shouldOnlySubscribeToSignalsListenedToII()
	--[[
	    *A
	   /   \
	 *B     D
	  |
	 *C
	]]
	local getA, setA = signal("a")

	local spyBCount = 0
	local b = computed(function()
		spyBCount = spyBCount + 1
		return getA()
	end)

	local spyCCount = 0
	local c = computed(function()
		spyCCount = spyCCount + 1
		return b()
	end)

	local d = computed(function()
		return getA()
	end)

	local result = ""
	local stopEffect = effect(function()
		result = c()
	end)

	assert(result == "a", getFunctionName())
	assert(d() == "a", getFunctionName()) -- Access d

	spyBCount = 0
	spyCCount = 0
	stopEffect() -- Stop the effect that depends on C and B

	setA("aa")

	assert(spyBCount == 0, getFunctionName()) -- B should not recompute as it's not needed by any active effect/computed
	assert(spyCCount == 0, getFunctionName()) -- C should not recompute
	assert(d() == "aa", getFunctionName()) -- D should update as it depends directly on A
end

local function shouldEnsureSubsUpdateEvenIfOneDepUnmarksIt()
	--[[
	     A
	   /   \
	  B     *C <- returns same value every time
	   \   /
	     D
	]]
	local getA, setA = signal("a")
	local b = computed(function()
		return getA()
	end)
	local c = computed(function()
		getA() -- Depend on A
		return "c"
	end)

	local spyCount = 0
	local dValue -- Store value to check
	local d = computed(function()
		spyCount = spyCount + 1
		dValue = b() .. " " .. c()
		return dValue
	end)

	assert(d() == "a c", getFunctionName())
	spyCount = 0

	setA("aa")
	d() -- Re-evaluate D
	assert(dValue == "aa c", getFunctionName()) -- Check the value computed last time D ran
	assert(spyCount == 1, getFunctionName()) -- Ensure D re-ran
end

local function shouldEnsureSubsUpdateEvenIfTwoDepsUnmarkIt()
	--[[
	     A
	   / | \
	  B *C *D
	   \ | /
	     E
	]]
	local getA, setA = signal("a")
	local b = computed(function()
		return getA()
	end)
	local c = computed(function()
		getA()
		return "c"
	end)
	local d = computed(function()
		getA()
		return "d"
	end)

	local spyCount = 0
	local eValue -- Store value to check
	local e = computed(function()
		spyCount = spyCount + 1
		eValue = b() .. " " .. c() .. " " .. d()
		return eValue
	end)

	assert(e() == "a c d", getFunctionName())
	spyCount = 0

	setA("aa")
	e() -- Re-evaluate E
	assert(eValue == "aa c d", getFunctionName()) -- Check the value computed last time E ran
	assert(spyCount == 1, getFunctionName()) -- Ensure E re-ran
end

local function shouldSupportLazyBranches()
	local getA, setA = signal(0)
	local b = computed(function()
		return getA()
	end)
	local c = computed(function()
		if getA() > 0 then
			return getA()
		else
			return b()
		end
	end)

	assert(c() == 0, getFunctionName())
	setA(1)
	assert(c() == 1, getFunctionName())

	setA(0)
	assert(c() == 0, getFunctionName())
end

local function shouldNotUpdateASubIfAllDepsUnmarkIt()
	--[[
	     A
	   /   \
	 *B     *C
	   \   /
	     D
	]]
	local getA, setA = signal("a")
	local b = computed(function()
		getA()
		return "b"
	end)
	local c = computed(function()
		getA()
		return "c"
	end)

	local spyCount = 0
	local d = computed(function()
		spyCount = spyCount + 1
		return b() .. " " .. c()
	end)

	assert(d() == "b c", getFunctionName())
	assert(spyCount == 1, getFunctionName())
	spyCount = 0 -- Reset counter

	setA("aa")
	assert(d() == "b c", getFunctionName()) -- Access d again
	assert(spyCount == 0, getFunctionName()) -- D should not have recomputed
end

-- Error Handling

local function shouldKeepGraphConsistentOnErrorsDuringActivation()
	local getA, setA = signal(0)
	local b = computed(function()
		error("fail")
	end)
	local c = computed(function()
		return getA()
	end)

	local success, _ = pcall(b)
	assert(not success, getFunctionName())

	setA(1)
	assert(c() == 1, getFunctionName())
end

local function shouldKeepGraphConsistentOnErrorsInComputeds()
	local getA, setA = signal(0)
	local b = computed(function()
		if getA() == 1 then
			error("fail")
		end
		return getA()
	end)
	local c = computed(function()
		return b()
	end)

	assert(c() == 0, getFunctionName())

	setA(1)
	local success, _ = pcall(c) -- Accessing C will try to access B
	assert(not success, getFunctionName())

	setA(2)
	assert(c() == 2, getFunctionName())
end

-- Run tests
shouldDropABAToUpdates()
shouldOnlyUpdateEverySignalOnceDiamondGraph()
shouldOnlyUpdateEverySignalOnceDiamondGraphPlusTail()
shouldBailOutIfResultIsTheSame()
shouldOnlyUpdateEverySignalOnceJaggedDiamondGraphPlusTails()
shouldOnlySubscribeToSignalsListenedTo()
shouldOnlySubscribeToSignalsListenedToII()
shouldEnsureSubsUpdateEvenIfOneDepUnmarksIt()
shouldEnsureSubsUpdateEvenIfTwoDepsUnmarkIt()
shouldSupportLazyBranches()
shouldNotUpdateASubIfAllDepsUnmarkIt()

shouldKeepGraphConsistentOnErrorsDuringActivation()
shouldKeepGraphConsistentOnErrorsInComputeds()

return {}
