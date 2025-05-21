local signals = require("../src")

local computed = signals.computed
local effect = signals.effect
local effectScope = signals.effectScope
local endBatch = signals.endBatch
local setCurrentSub = signals.setCurrentSub
local signal = signals.signal
local startBatch = signals.startBatch

local function getFunctionName()
	return debug.info(2, "n")
end

local function shouldClearSubscriptionsWhenUntrackedByAllSubscribers()
	local bRunTimes = 0

	local getA, setA = signal(1)
	local b = computed(function()
		bRunTimes = bRunTimes + 1
		return getA() * 2
	end)
	local stopEffect = effect(function()
		b()
	end)

	assert(bRunTimes == 1, getFunctionName())
	setA(2)
	assert(bRunTimes == 2, getFunctionName())
	stopEffect()
	setA(3)
	assert(bRunTimes == 2, getFunctionName())
end

local function shouldNotRunUntrackedInnerEffect()
	local getA, setA = signal(3)
	local b = computed(function()
		return getA() > 0
	end)

	effect(function()
		if b() then
			effect(function()
				if getA() == 0 then
					error("bad")
				end
			end)
		end
	end)

	setA(2)
	setA(1)
	setA(0)
end

local function shouldRunOuterEffectFirst()
	local getA, setA = signal(1)
	local getB, setB = signal(1)

	effect(function()
		if getA() ~= 0 then
			effect(function()
				getB()
				if getA() == 0 then
					error("bad")
				end
			end)
		end
	end)

	startBatch()
	setB(0)
	setA(0)
	endBatch()
end

local function shouldNotTriggerInnerEffectWhenResolveMaybeDirty()
	local getA, setA = signal(0)
	local b = computed(function()
		return getA() % 2
	end)

	local innerTriggerTimes = 0

	effect(function()
		effect(function()
			b()
			innerTriggerTimes = innerTriggerTimes + 1
			if innerTriggerTimes >= 2 then
				error("bad")
			end
		end)
	end)

	setA(2)
end

local function shouldTriggerInnerEffectsInSequence()
	local getA, setA = signal(0)
	local getB, setB = signal(0)
	local c = computed(function()
		return getA() - getB()
	end)
	local order = {}

	effect(function()
		c()

		effect(function()
			table.insert(order, "first inner")
			getA()
		end)

		effect(function()
			table.insert(order, "last inner")
			getA()
			getB()
		end)
	end)

	order = {}

	startBatch()
	setB(1)
	setA(1)
	endBatch()

	assert(order[1] == "first inner" and order[2] == "last inner" and #order == 2, getFunctionName())
end

local function shouldTriggerInnerEffectsInSequenceInEffectScope()
	local getA, setA = signal(0)
	local getB, setB = signal(0)
	local order = {}

	effectScope(function()
		effect(function()
			table.insert(order, "first inner")
			getA()
		end)

		effect(function()
			table.insert(order, "last inner")
			getA()
			getB()
		end)
	end)

	order = {}

	startBatch()
	setB(1)
	setA(1)
	endBatch()

	assert(order[1] == "first inner" and order[2] == "last inner" and #order == 2, getFunctionName())
end

local function shouldCustomEffectSupportBatch()
	local function batchEffect(fn)
		return effect(function()
			startBatch()
			local results = { pcall(fn) }
			endBatch()
			if not results[1] then
				error(results[2])
			end
			-- Note: Returning values from pcall result table if needed
			return table.unpack(results, 2)
		end)
	end

	local logs = {}
	local getA = signal(0)
	local getB, setB = signal(0)

	local aa = computed(function()
		table.insert(logs, "aa-0")
		if getA() == 0 then
			setB(1)
		end
		table.insert(logs, "aa-1")
		return nil
	end)

	local bb = computed(function()
		table.insert(logs, "bb")
		return getB()
	end)

	batchEffect(function()
		bb()
	end)
	batchEffect(function()
		aa()
	end)

	assert(
		logs[1] == "bb" and logs[2] == "aa-0" and logs[3] == "aa-1" and logs[4] == "bb" and #logs == 4,
		getFunctionName()
	)
end

local function shouldDuplicateSubscribersDoNotAffectTheNotifyOrder()
	local getSrc1, setSrc1 = signal(0)
	local getSrc2, setSrc2 = signal(0)
	local order = {}

	effect(function()
		table.insert(order, "a")
		local currentSub = setCurrentSub(nil)
		local isOne = getSrc2() == 1
		setCurrentSub(currentSub)
		if isOne then
			getSrc1()
		end
		getSrc2()
		getSrc1()
	end)
	effect(function()
		table.insert(order, "b")
		getSrc1()
	end)
	setSrc2(1) -- src1.subs: a -> b -> a

	order = {}
	setSrc1(getSrc1() + 1)

	assert(order[1] == "a" and order[2] == "b" and #order == 2, getFunctionName())
end

local function shouldHandleSideEffectWithInnerEffects()
	local getA, setA = signal(0)
	local getB, setB = signal(0)
	local order = {}

	effect(function()
		effect(function()
			getA()
			table.insert(order, "a")
		end)
		effect(function()
			getB()
			table.insert(order, "b")
		end)
		assert(order[1] == "a" and order[2] == "b" and #order == 2, getFunctionName())

		order = {}
		setB(1)
		setA(1)
		assert(order[1] == "b" and order[2] == "a" and #order == 2, getFunctionName())
	end)
end

local function shouldHandleFlagsAreIndirectlyUpdatedDuringCheckDirty()
	local getA, setA = signal(false)
	local b = computed(function()
		return getA()
	end)
	local c = computed(function()
		b()
		return 0
	end)
	local d = computed(function()
		c()
		return b()
	end)

	local triggers = 0

	effect(function()
		d()
		triggers = triggers + 1
	end)
	assert(triggers == 1, getFunctionName())
	setA(true)
	assert(triggers == 2, getFunctionName())
end

shouldClearSubscriptionsWhenUntrackedByAllSubscribers()
shouldNotRunUntrackedInnerEffect()
shouldRunOuterEffectFirst()
shouldNotTriggerInnerEffectWhenResolveMaybeDirty()
shouldTriggerInnerEffectsInSequence()
shouldTriggerInnerEffectsInSequenceInEffectScope()
shouldCustomEffectSupportBatch()
shouldDuplicateSubscribersDoNotAffectTheNotifyOrder()
shouldHandleSideEffectWithInnerEffects()
shouldHandleFlagsAreIndirectlyUpdatedDuringCheckDirty()

return {}
