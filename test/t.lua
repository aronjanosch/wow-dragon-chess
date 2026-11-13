-- Tiny test helper: T.ok / T.eq record results, T.done() prints the summary and
-- exits non-zero on failure. Only failures print the word F-A-I-L (checks.sh greps it).
local T = { passed = 0, failed = 0, name = "test" }

function T.start(name) T.name = name end

function T.ok(cond, msg)
	if cond then
		T.passed = T.passed + 1
	else
		T.failed = T.failed + 1
		print("FAIL " .. T.name .. ": " .. tostring(msg))
	end
	return cond
end

function T.eq(a, b, msg)
	return T.ok(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- Run fn, recording an error as a failure.
function T.case(label, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then T.ok(false, label .. ": " .. tostring(err)) end
end

function T.done()
	if T.failed == 0 then
		print(("PASS %s (%d checks, %s)"):format(T.name, T.passed, jit and "luajit" or _VERSION))
		os.exit(0)
	end
	print(("FAIL %s: %d of %d checks failed"):format(T.name, T.failed, T.failed + T.passed))
	os.exit(1)
end

return T
