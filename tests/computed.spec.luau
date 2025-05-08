local signals = require("../src")

local computed = signals.computed
local signal = signals.signal

local function getFunctionName()
	return debug.info(2, "n")
end

local function shouldPropagateThroughComputed()
	local src, setSrc = signal(0)
	local c1 = computed(function()
		return src() % 2
	end)
	local c2 = computed(function()
		return c1()
	end)
	local c3 = computed(function()
		return c2()
	end)

	c3()
	setSrc(1)
	c2()
	setSrc(3)

	assert(c3() == 1, getFunctionName())
end

local function shouldPropagateThroughChainedComputations()
	local src, setSrc = signal(0)
	local a = computed(function()
		return src()
	end)

	local b = computed(function()
		return a() % 2
	end)

	local c = computed(function()
		return src()
	end)

	local d = computed(function()
		return b() + c()
	end)

	assert(d() == 0, getFunctionName())
	setSrc(2)
	assert(d() == 2, getFunctionName())
end

local function shouldHandleIndirectDirtyFlagUpdate()
	local a, setA = signal(false)
	local b = computed(function()
		return a()
	end)
	local c = computed(function()
		b()
		return 0
	end)
	local d = computed(function()
		c()
		return b()
	end)

	assert(d() == false, getFunctionName())
	setA(true)
	assert(d() == true, getFunctionName())
end

local function shouldNotUpdateIfSignalValueReverted()
	local times = 0

	local src, setSrc = signal(0)
	local c1 = computed(function()
		times += 1
		return src()
	end)
	c1()
	assert(times == 1, getFunctionName())
	setSrc(1)
	setSrc(0)
	c1()
	assert(times == 1, getFunctionName())
end

shouldPropagateThroughComputed()
shouldPropagateThroughChainedComputations()
shouldHandleIndirectDirtyFlagUpdate()
shouldNotUpdateIfSignalValueReverted()

return {}
