-- Requires SwiftPM and Neovim. Run from the configuration root:
-- nvim --headless -u NONE -i NONE -l tests/swift_packages.lua
local repository = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(repository)
vim.opt.rtp:append(repository .. "/after")
vim.cmd("filetype plugin on")
local root = vim.fn.tempname() .. " swift packages"
vim.fn.mkdir(root, "p")
root = vim.fs.normalize(assert(vim.uv.fs_realpath(root)))
local pkg = root .. "/App/Nested"
local file = pkg .. "/Sources/First/main.swift"
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	assert(vim.fn.writefile(lines, path) == 0)
end
local function edit(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
end
local messages, launches = {}, {}
vim.notify = function(message)
	messages[#messages + 1] = message
end
package.loaded.dap = {
	run = function(config)
		launches[#launches + 1] = config
	end,
}
local function wait(label, predicate)
	assert(vim.wait(90000, predicate, 20), label .. " | " .. table.concat(messages, "\n"))
end
local function ends_with_message(cmd, fragment)
	local index = #messages
	vim.cmd(cmd)
	wait(cmd, function()
		return #messages > index and messages[#messages]:find(fragment, 1, true)
	end)
end
local function terminal(cmd, input)
	local source = vim.api.nvim_get_current_win()
	vim.cmd(cmd)
	wait(cmd .. " should open a terminal", function()
		return vim.bo.buftype == "terminal"
	end)
	local job = vim.b.terminal_job_id
	if input then
		vim.api.nvim_chan_send(job, input .. "\n")
	end
	wait(cmd .. " should finish", function()
		return vim.fn.jobwait({ job }, 0)[1] ~= -1
	end)
	local output = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	vim.cmd("bwipeout!")
	vim.api.nvim_set_current_win(source)
	return output
end

local ok, err = xpcall(function()
	vim.fn.mkdir(root .. "/App/Demo.xcodeproj", "p")
	write(root .. "/App/Package.swift", { "// deliberately invalid outer package" })
	local nested_app = root .. "/App/Examples/Demo"
	vim.fn.mkdir(nested_app .. "/Demo.xcodeproj", "p")
	local nested_view = nested_app .. "/Views/Main.swift"
	write(nested_view, { "import SwiftUI" })
	edit(nested_view)
	vim.cmd.SwiftBuild()
	assert(vim.bo.buftype ~= "terminal", "An embedded Xcode app must not build the enclosing Swift package")
	assert(messages[#messages]:find(":XcodebuildSetup", 1, true), "Direct the nested app to Xcode tools")
	write(pkg .. "/Package.swift", {
		"// swift-tools-version: 6.0",
		"import PackageDescription",
		'let package = Package(name: "Nested", products: [.executable(name: "Explicit", targets: ["First"])],',
		'  targets: [.executableTarget(name: "First"), .executableTarget(name: "Inferred"),',
		'  .testTarget(name: "Tests")])',
	})
	write(file, { 'print("received-" + (readLine() ?? "no input"))' })
	write(pkg .. "/Sources/Inferred/main.swift", { 'print("implicit executable")' })
	write(pkg .. "/Tests/Tests/Example.swift", {
		"import Testing",
		"struct Example {",
		"  @Test func testSelected() {",
		'    print("selected test ran")',
		"#if canImport(XCTest)",
		'    print("XCTest available")',
		"#endif",
		"  }",
		'  @Test func testOther() { print("other test ran") }',
		"}",
		"#if canImport(XCTest)",
		"import XCTest",
		"final class LegacySuite: XCTestCase {",
		'  func testXCTest() { print("XCTest fixture ran") }',
		"}",
		"#endif",
	})
	edit(file)
	assert(vim.fn.exists(":SwiftBuild") == 2, "Swift buffers should expose :SwiftBuild")
	local build = terminal("SwiftBuild")
	assert(build:find("Build complete", 1, true), build)
	-- Package commands also work when there is an Xcode project beside the manifest.
	vim.fn.mkdir(pkg .. "/Legacy.xcodeproj", "p")
	assert(terminal("SwiftRun Explicit", "hello"):find("received-hello", 1, true), "Run forwards terminal input")
	local choices
	vim.ui.select = function(items, _, choose)
		choices = items
		choose("Inferred")
	end
	assert(terminal("SwiftRun"):find("implicit executable", 1, true), "Selected product should run")
	assert(vim.deep_equal(choices, { "Explicit", "Inferred" }), vim.inspect(choices))
	ends_with_message("SwiftRun First", "First")
	local all = terminal("SwiftTest")
	assert(all:find("selected test ran", 1, true) and all:find("other test ran", 1, true), all)
	local output = terminal("SwiftTest testSelected")
	assert(output:find("selected test ran", 1, true) and not output:find("other test ran", 1, true), output)
	assert(not output:find("XCTest fixture ran", 1, true), output)
	if all:find("XCTest available", 1, true) then
		assert(all:find("XCTest fixture ran", 1, true), all)
		local xctest = terminal("SwiftTest LegacySuite.testXCTest")
		assert(xctest:find("XCTest fixture ran", 1, true), xctest)
		assert(not xctest:find("selected test ran", 1, true) and not xctest:find("other test ran", 1, true), xctest)
		print("Full and filtered XCTest and Swift Testing suites passed")
	end
	terminal("SwiftDebug Explicit")
	wait("Debug configuration", function()
		return launches[1]
	end)
	local launch = launches[1]
	assert(launch.type == "swift-lldb" and launch.request == "launch" and launch.cwd == pkg, vim.inspect(launch))
	local expected_name = vim.fn.has("win32") == 1 and "Explicit.exe" or "Explicit"
	assert(vim.fs.basename(launch.program) == expected_name, launch.program)
	assert(vim.fn.filereadable(launch.program) == 1 and vim.fn.executable(launch.program) == 1, launch.program)
	write(file, { "missingSwiftSymbol()" })
	assert(terminal("SwiftDebug Explicit"):find("missingSwiftSymbol", 1, true), "Compiler error should remain visible")
	assert(#launches == 1, "Broken build must not launch its stale binary")

	local library = root .. "/Library"
	write(library .. "/Package.swift", {
		"// swift-tools-version: 6.0",
		"import PackageDescription",
		'let package = Package(name: "Lib", targets: [.target(name: "Lib")])',
	})
	write(library .. "/Sources/Lib/Library.swift", { "public struct Value {}" })
	edit(library .. "/Sources/Lib/Library.swift")
	ends_with_message("SwiftRun", ":SwiftTest")
	ends_with_message("SwiftDebug", ":SwiftTest")
	local script = root .. "/scratch script.swift"
	write(script, { 'print("standalone output")' })
	edit(script)
	assert(terminal("SwiftRun"):find("standalone output", 1, true), "Standalone run should use the saved file")

	local view = root .. "/Mobile/Sources/View.swift"
	vim.fn.mkdir(root .. "/Mobile/Mobile.xcworkspace", "p")
	write(view, { "import SwiftUI" })
	edit(view)
	ends_with_message("SwiftRun", "Xcode")
	vim.bo.filetype = "text"
	assert(vim.fn.exists(":SwiftRun") == 0, "Swift commands should leave the buffer with the filetype")
end, debug.traceback)
vim.fn.delete(root, "rf")
assert(ok, err)
print("Swift package command checks passed")
