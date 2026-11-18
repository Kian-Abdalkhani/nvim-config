local M = {}

local function warn(message)
	vim.notify(message, vim.log.levels.WARN, { title = "Swift" })
end

local function query(argv, root, done)
	local function on_exit(result)
		if result.code ~= 0 then
			local message = vim.trim(result.stderr or "")
			warn(message ~= "" and message or table.concat(argv, " ") .. " failed")
			return
		end
		done(vim.trim(result.stdout))
	end
	local started, err = pcall(vim.system, argv, { cwd = root, text = true }, vim.schedule_wrap(on_exit))
	if not started then
		warn(tostring(err))
	end
end

local function terminal(argv, root, interactive, on_success)
	vim.cmd("botright 12new")
	local job = vim.fn.jobstart(argv, {
		term = true,
		cwd = root,
		on_exit = on_success and function(_, code)
			if code == 0 then
				vim.schedule(on_success)
			end
		end or nil,
	})
	if job <= 0 then
		warn("Could not start " .. argv[1])
	elseif interactive then
		vim.cmd.startinsert()
	end
end

local function with_product(root, requested, done)
	query({ "swift", "package", "describe", "--type", "json" }, root, function(output)
		local ok, package_info = pcall(vim.json.decode, output)
		if not ok or type(package_info) ~= "table" or type(package_info.products) ~= "table" then
			warn("SwiftPM returned an invalid package description for " .. root)
			return
		end
		-- SwiftPM includes implicitly generated executable products in this list.
		local products = {}
		for _, product in ipairs(package_info.products) do
			if type(product.type) == "table" and product.type.executable ~= nil then
				table.insert(products, product.name)
			end
		end
		table.sort(products)
		if #products == 0 then
			warn("This package has no executable products. Use :SwiftTest to run its tests.")
		elseif requested ~= "" then
			if vim.list_contains(products, requested) then
				done(requested)
			else
				warn(("Unknown executable %s. Available products: %s"):format(requested, table.concat(products, ", ")))
			end
		elseif #products == 1 then
			done(products[1])
		else
			vim.ui.select(products, { prompt = "Swift executable product" }, function(product)
				if product then
					done(product)
				end
			end)
		end
	end)
end

local function debug_product(root, product)
	terminal({ "swift", "build", "-c", "debug", "--product", product }, root, false, function()
		query({ "swift", "build", "-c", "debug", "--show-bin-path" }, root, function(path)
			local filename = vim.fn.has("win32") == 1 and product .. ".exe" or product
			local program = vim.fs.joinpath(path, filename)
			if vim.fn.executable(program) ~= 1 then
				warn("SwiftPM did not produce an executable at " .. program)
				return
			end
			require("dap").run({
				type = "swift-lldb",
				request = "launch",
				name = "SwiftPM: " .. product,
				cwd = root,
				program = program,
			})
		end)
	end)
end

function M.execute(command, argument)
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" or vim.bo.buftype ~= "" then
		warn("Save this Swift file first.")
		return
	end
	if vim.fn.executable("swift") ~= 1 then
		warn("The swift command is missing from PATH.")
		return
	end
	local root = vim.fs.root(file, function(name)
		return name == "Package.swift" or name:match("%.xcodeproj$") or name:match("%.xcworkspace$")
	end)
	if root and not vim.uv.fs_stat(vim.fs.joinpath(root, "Package.swift")) then
		warn("Use :XcodebuildSetup or :XcodebuildPicker for this Xcode project.")
		return
	end
	if not root then
		if command ~= "SwiftRun" or argument ~= "" then
			warn("This command requires a Swift package. Use :SwiftRun to run a standalone file.")
		elseif vim.bo.modified or vim.fn.filereadable(file) ~= 1 then
			warn("Save this Swift file before running it.")
		else
			terminal({ "swift", file }, vim.fs.dirname(file), true)
		end
	elseif command == "SwiftBuild" then
		terminal({ "swift", "build" }, root)
	elseif command == "SwiftTest" then
		local argv = { "swift", "test" }
		if argument ~= "" then
			vim.list_extend(argv, { "--filter", argument })
		end
		terminal(argv, root)
	else
		with_product(root, argument, function(product)
			if command == "SwiftDebug" then
				debug_product(root, product)
			else
				terminal({ "swift", "run", product }, root, true)
			end
		end)
	end
end

return M
