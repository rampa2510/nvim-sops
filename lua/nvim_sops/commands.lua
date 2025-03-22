local debug = require("nvim_sops.utils").debug
local sops = require("nvim_sops.sops")

local M = {}

M.file_encrypt = function()
	local input_file = vim.fn.expand("%:p")
	local dir = vim.fn.expand("%:p:h")
	local filename = vim.fn.expand("%:t")

	print("Starting encryption process")
	print("Full path: " .. input_file)
	print("Directory: " .. dir)
	print("Filename: " .. filename)

	-- Check if this is a decrypted file
	if string.find(filename, "^%.decrypted~") then
		print("File identified as decrypted file")

		-- Get the original filename by removing the .decrypted~ prefix
		local original_filename = string.sub(filename, 12)
		local original_file = dir .. "/" .. original_filename

		print("Original filename: " .. original_filename)
		print("Full original path: " .. original_file)

		-- Try a direct approach - don't encrypt in place, encrypt to a new file
		local binary = vim.g.nvim_sops_bin_path
		print("Using binary: " .. binary)

		local sops_options = sops.get_sops_general_options()

		print("SOPS environment variables:")
		local env_vars = ""
		for key, value in pairs(sops_options.sopsGeneralEnvVars) do
			print("  " .. key .. " = " .. value)
			env_vars = env_vars .. key .. "=" .. value .. " "
		end

		-- Make sure the buffer is saved before encryption
		vim.cmd("write")
		print("Buffer saved")

		-- Look for .sops.yaml in the directory or parent directories
		local config_option = ""
		local sops_config = dir .. "/.sops.yaml"

		if vim.fn.filereadable(sops_config) == 1 then
			print("Found .sops.yaml at: " .. sops_config)
			config_option = "--config " .. vim.fn.shellescape(sops_config) .. " "
		else
			print("Looking for .sops.yaml in parent directories")
			local current_dir = dir
			while current_dir ~= "/" do
				local parent_config = current_dir .. "/.sops.yaml"
				if vim.fn.filereadable(parent_config) == 1 then
					print("Found .sops.yaml at: " .. parent_config)
					config_option = "--config " .. vim.fn.shellescape(parent_config) .. " "
					break
				end
				current_dir = vim.fn.fnamemodify(current_dir, ":h")
			end
		end

		if config_option == "" then
			print("WARNING: No .sops.yaml found")
		end

		-- Encrypt directly to the destination file
		local cmd = string.format(
			"%s%s %s--encrypt --output %s %s",
			env_vars,
			binary,
			config_option,
			vim.fn.shellescape(original_file),
			vim.fn.shellescape(input_file)
		)

		print("Encrypt command: " .. cmd)
		local result = vim.fn.system(cmd)
		print("Command result: " .. (result or "empty"))
		print("Exit code: " .. vim.v.shell_error)

		if vim.v.shell_error ~= 0 then
			print("ERROR: Encryption failed")
			vim.notify("Error encrypting file: " .. input_file .. "\nError: " .. result, vim.log.levels.ERROR)
			return
		end

		print("Encryption succeeded")

		-- Check if the output file exists and has content
		if vim.fn.filereadable(original_file) == 1 then
			local size = vim.fn.getfsize(original_file)
			print("Output file size: " .. size)

			if size > 0 then
				-- Open the encrypted file
				vim.cmd("edit " .. vim.fn.fnameescape(original_file))
				vim.notify("File encrypted successfully", vim.log.levels.INFO)
			else
				print("ERROR: Output file is empty")
				vim.notify("Encrypted file is empty", vim.log.levels.ERROR)
				return
			end
		else
			print("ERROR: Output file does not exist")
			vim.notify("Failed to create encrypted file", vim.log.levels.ERROR)
			return
		end
	else
		print("ERROR: Not a decrypted file")
		vim.notify(
			"This doesn't appear to be a decrypted file. Only .decrypted~ files can be encrypted.",
			vim.log.levels.ERROR
		)
	end
end

M.file_decrypt = function()
	local input_file = vim.fn.expand("%:p")
	local dir = vim.fn.expand("%:p:h")
	local filename = vim.fn.expand("%:t")
	local output_file = dir .. "/.decrypted~" .. filename

	-- Ensure we can write to the output location
	local test_file = io.open(output_file, "w")
	if test_file then
		test_file:close()
		os.remove(output_file)
	else
		vim.notify("Cannot write to output location: " .. output_file, vim.log.levels.ERROR)
		return
	end

	local binary = vim.g.nvim_sops_bin_path
	local sops_options = sops.get_sops_general_options()

	local env_vars = ""
	for key, value in pairs(sops_options.sopsGeneralEnvVars) do
		env_vars = env_vars .. key .. "=" .. value .. " "
	end

	-- Execute sops command with shell redirection
	local cmd = string.format(
		"%s%s --decrypt %s > %s 2>&1",
		env_vars,
		binary,
		vim.fn.shellescape(input_file),
		vim.fn.shellescape(output_file)
	)

	local result = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		vim.notify("Error decrypting file: " .. input_file, vim.log.levels.ERROR)
		return
	end

	-- Check if the output file exists and has content
	if vim.fn.filereadable(output_file) == 1 and vim.fn.getfsize(output_file) > 0 then
		-- Open the decrypted file in a new buffer
		vim.cmd("edit " .. vim.fn.fnameescape(output_file))
	else
		vim.notify("Failed to create decrypted file", vim.log.levels.ERROR)
		return
	end

	debug("Decrypted " .. input_file .. " to " .. output_file)
end

return M
