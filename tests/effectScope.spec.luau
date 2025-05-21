local signals = require("../src")

local effect = signals.effect
local effectScope = signals.effectScope
local signal = signals.signal

local function getFunctionName()
	return debug.info(2, "n")
end

local function shouldNotTriggerAfterStop()
	local getCount, setCount = signal(1)

	local triggers = 0
	local _effect1

	local stopScope = effectScope(function()
		_effect1 = effect(function()
			triggers += 1
			getCount()
		end)
		assert(triggers == 1, getFunctionName())

		setCount(2)
		assert(triggers == 2, getFunctionName())
	end)

	setCount(3)
	assert(triggers == 3, getFunctionName())
	stopScope()
	setCount(4)
	assert(triggers == 3, getFunctionName())
end

local function shouldDisposeInnerEffectsIfCreatedInEffect()
	local source, setSource = signal(1)

	local triggers = 0

	effect(function()
		local dispose = effectScope(function()
			effect(function()
				source()
				triggers += 1
			end)
		end)
		assert(triggers == 1, getFunctionName())

		setSource(2)
		assert(triggers == 2, getFunctionName())
		dispose()
		setSource(3)
		assert(triggers == 2, getFunctionName())
	end)
end

shouldNotTriggerAfterStop()
shouldDisposeInnerEffectsIfCreatedInEffect()

return {}
