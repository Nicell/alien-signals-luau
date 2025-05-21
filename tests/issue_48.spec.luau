local signals = require("../src")

local computed = signals.computed
local effect = signals.effect
local setCurrentSub = signals.setCurrentSub
local signal = signals.signal

local function untracked<T>(callback: () -> T): T
	local currentSub = setCurrentSub(nil)
	local success, result = pcall(callback)
	setCurrentSub(currentSub)
	if not success then
		error(result)
	end
	return result
end

type ReactionOptions<T> = {
	fireImmediately: boolean?,
	equals: ((a: T, b: T) -> boolean)?,
	onError: (error: unknown) -> ()?,
	scheduler: (fn: () -> ()) -> ()?,
	once: boolean?,
}

local function reaction<T>(
	dataFn: () -> T,
	effectFn: (newValue: T, oldValue: T?) -> (),
	optionsParam: ReactionOptions<T>?
): () -> ()
	local options: ReactionOptions<T> = optionsParam or {}
	local scheduler = options.scheduler or function(fn: () -> ())
		fn()
	end
	local equals = options.equals or function(a: T, b: T)
		return a == b
	end
	local onError = options.onError
	local once = options.once or false
	local fireImmediately = options.fireImmediately or false

	local prevValue
	local version = 0
	local disposeInnerEffect

	local tracked = computed(function()
		local success, resultOrError = pcall(dataFn)
		if not success then
			untracked(function()
				if onError then
					onError(resultOrError)
				end
				return nil
			end)
			return prevValue
		end
		return resultOrError
	end)

	local disposeOuterEffect = effect(function()
		local current = tracked()
		if not fireImmediately and version == 0 then
			prevValue = current
		end
		version += 1
		if equals(current, prevValue) then
			return
		end
		local oldValue = prevValue
		prevValue = current
		untracked(function()
			scheduler(function()
				local success, err: any = pcall(effectFn, current, oldValue)
				if not success then
					if onError then
						onError(err)
					end
				end
				if once then
					if disposeInnerEffect then
						-- selene: allow(if_same_then_else)
						if fireImmediately and version > 1 then
							disposeInnerEffect()
						elseif not fireImmediately and version > 0 then
							disposeInnerEffect()
						end
					end
				end
			end)
			return nil
		end)
	end)

	disposeInnerEffect = disposeOuterEffect
	return disposeOuterEffect
end

local function issue48()
	local source, setSource = signal(0)
	local disposeInner

	reaction(function()
		return source()
	end, function(val)
		if val == 1 then
			disposeInner = reaction(function()
				return source()
			end, function() end)
		elseif val == 2 then
			disposeInner()
		end
	end)

	setSource(1)
	setSource(2)
	setSource(3)
end

issue48()

return {}
