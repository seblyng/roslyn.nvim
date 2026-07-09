local helpers = require("test.utils.helpers")
local system = helpers.fn.system
local create_file = helpers.create_file
local create_sln_file = helpers.create_sln_file
local command = helpers.api.nvim_command
local create_slnf_file = helpers.create_slnf_file
local scratch = helpers.scratch

---Converts a file path to a file:// URI
---@param path string
---@return string
local function to_uri(path)
    return "file://" .. path
end

local function get_lsp_clients(bufnr)
    return helpers.exec_lua(function(bufnr0)
        return vim.tbl_map(function(client)
            local attached = vim.tbl_map(function(buf)
                return buf
            end, vim.tbl_keys(client.attached_buffers))

            return { id = client.id, root_dir = client.root_dir, attached_buffers = attached }
        end, vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr0 }))
    end, bufnr)
end

helpers.env()

describe("LSP integration with mock server", function()
    after_each(function()
        helpers.exec_lua(function()
            require("test.utils.mock_server").reset()
        end)
        system({ "rm", "-rf", scratch })
    end)

    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
        helpers.exec_lua(function()
            local cwd = vim.uv.cwd()
            local lsp_config = dofile(vim.fs.joinpath(cwd, "lsp", "roslyn.lua"))

            lsp_config.cmd = require("test.utils.mock_server").server

            vim.lsp.config["roslyn"] = lsp_config
            vim.lsp.enable("roslyn")
            dofile(vim.fs.joinpath(cwd, "plugin", "roslyn.lua"))
        end)
    end)

    it("starts LSP client with correct root_dir for single solution", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        command("edit " .. vim.fs.joinpath(helpers.scratch, "Bar", "Program.cs"))
        local clients = helpers.exec_lua(function()
            return vim.tbl_map(function(client)
                return { id = client.id, root_dir = client.root_dir }
            end, vim.lsp.get_clients({ name = "roslyn", bufnr = vim.api.nvim_get_current_buf() }))
        end)

        assert.are_equal(1, #clients)
        assert.are_equal(scratch, clients[1].root_dir)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
        assert.are_equal(to_uri(vim.fs.joinpath(scratch, "Foo.sln")), notifications[1].params.solution)
    end)

    it("sends project/open when no solution exists", function()
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        command("edit " .. vim.fs.joinpath(helpers.scratch, "Bar", "Program.cs"))

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("project/open", notifications[1].method)
    end)

    it("reuses same client when opening another file in same solution", function()
        create_sln_file("Foo.sln", {
            { name = "Bar", path = "Bar/Bar.csproj" },
            { name = "Baz", path = "Baz/Baz.csproj" },
        })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")
        create_file("Baz/Baz.csproj")
        create_file("Baz/Other.cs")

        -- Open first file
        command("edit " .. vim.fs.joinpath(helpers.scratch, "Bar", "Program.cs"))

        local clients_after_first = helpers.exec_lua(function()
            return vim.tbl_map(function(client)
                return { id = client.id, root_dir = client.root_dir }
            end, vim.lsp.get_clients({ name = "roslyn", bufnr = vim.api.nvim_get_current_buf() }))
        end)
        assert.are_equal(1, #clients_after_first)

        -- Open second file in same solution
        command("edit " .. vim.fs.joinpath(helpers.scratch, "Baz", "Other.cs"))

        -- Should still be only 1 client and same client
        local clients_after_second = helpers.exec_lua(function()
            return vim.tbl_map(function(client)
                return { id = client.id, root_dir = client.root_dir }
            end, vim.lsp.get_clients({ name = "roslyn", bufnr = vim.api.nvim_get_current_buf() }))
        end)
        assert.are_equal(1, #clients_after_second)
        assert.are_equal(clients_after_first[1].id, clients_after_second[1].id)

        -- Should only have sent solution/open once
        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
    end)

    it("stores selected solution in global variable", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        command("edit " .. vim.fs.joinpath(helpers.scratch, "Bar", "Program.cs"))

        local selected = helpers.exec_lua(function()
            return vim.g.roslyn_nvim_selected_solution
        end)
        assert.are_equal(vim.fs.joinpath(scratch, "Foo.sln"), selected)
    end)

    it("change global variable if lock_target is false", function()
        create_sln_file("Foo.sln", { { name = "Foo", path = "Foo/Foo.csproj" } })
        create_file("Foo/Foo.csproj")
        create_file("Foo/Program.cs")
        create_file("Foo/Test.cs")

        command("edit " .. vim.fs.joinpath(helpers.scratch, "Foo", "Program.cs"))

        local selected = helpers.exec_lua(function()
            return vim.g.roslyn_nvim_selected_solution
        end)
        assert.are_equal(vim.fs.joinpath(scratch, "Foo.sln"), selected)

        helpers.exec_lua(function()
            vim.g.roslyn_nvim_selected_solution = "Locked.sln"
        end)

        command("edit " .. vim.fs.joinpath(helpers.scratch, "Foo", "Test.cs"))

        -- Switching back should update the global variable since lock_target is false
        command("edit " .. vim.fs.joinpath(helpers.scratch, "Foo", "Program.cs"))

        selected = helpers.exec_lua(function()
            return vim.g.roslyn_nvim_selected_solution
        end)
        assert.are_equal(vim.fs.joinpath(scratch, "Foo.sln"), selected)
    end)

    it("does not change global variable if lock_target is true", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ lock_target = true })
        end)

        create_sln_file("Foo.sln", { { name = "Foo", path = "Foo/Foo.csproj" } })
        create_file("Foo/Foo.csproj")
        create_file("Foo/Program.cs")
        create_file("Foo/Test.cs")

        command("edit " .. vim.fs.joinpath(helpers.scratch, "Foo", "Program.cs"))

        local selected = helpers.exec_lua(function()
            return vim.g.roslyn_nvim_selected_solution
        end)
        assert.are_equal(vim.fs.joinpath(scratch, "Foo.sln"), selected)

        helpers.exec_lua(function()
            vim.g.roslyn_nvim_selected_solution = "Locked.sln"
        end)

        command("edit " .. vim.fs.joinpath(helpers.scratch, "Foo", "Test.cs"))

        -- Switching back to the open buffer should not change the globally selected solution when having lock_target enabled
        command("edit " .. vim.fs.joinpath(helpers.scratch, "Foo", "Program.cs"))

        selected = helpers.exec_lua(function()
            return vim.g.roslyn_nvim_selected_solution
        end)
        assert.are_equal("Locked.sln", selected)
    end)

    it("finds solution with broad_search enabled", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_sln_file("src/Bar/Bar.sln", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))

        local clients = get_lsp_clients()
        assert.are_equal(1, #clients)
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Bar"), clients[1].root_dir)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
    end)

    it("finds slnf file and sends solution/open", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_slnf_file("src/Bar/Bar.slnf", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))

        local clients = get_lsp_clients()
        assert.are_equal(1, #clients)
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Bar"), clients[1].root_dir)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
        assert.are_equal(to_uri(vim.fs.joinpath(scratch, "src", "Bar", "Bar.slnf")), notifications[1].params.solution)
    end)

    it("uses choose_target to select solution when multiple exist", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({
                choose_target = function(targets)
                    return vim.iter(targets):find(function(item)
                        return string.match(item, "Bar.sln")
                    end)
                end,
            })
        end)

        create_file("src/Program.cs")
        create_file("src/Foo.csproj")
        create_sln_file("Foo.sln", { { name = "Foo", path = "src/Foo.csproj" } })
        create_sln_file("Bar.sln", { { name = "Foo", path = "src/Foo.csproj" } })

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Program.cs"))

        local clients = get_lsp_clients()
        assert.are_equal(1, #clients)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
        assert.are_equal(to_uri(vim.fs.joinpath(scratch, "Bar.sln")), notifications[1].params.solution)
    end)

    it("has nil root_dir when multiple solutions and no choose_target", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_sln_file("Baz.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        -- LSP will start but root_dir should be nil (ambiguous case)
        command("edit " .. vim.fs.joinpath(helpers.scratch, "Bar", "Program.cs"))

        -- Client starts but with nil root_dir, so no solution/open is sent
        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(0, #notifications)

        assert.is_nil(get_lsp_clients()[1].root_dir)
    end)

    it("starts separate instances for different solutions", function()
        -- Remove the parent .git so each project has its own git root
        system({ "rm", "-rf", vim.fs.joinpath(scratch, ".git") })

        -- Create two separate solution structures with their own .git dirs
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, "ProjectA", ".git") })
        create_sln_file("ProjectA/A.sln", { { name = "A", path = "A.csproj" } })
        create_file("ProjectA/A.csproj")
        create_file("ProjectA/Program.cs")

        system({ "mkdir", "-p", vim.fs.joinpath(scratch, "ProjectB", ".git") })
        create_sln_file("ProjectB/B.sln", { { name = "B", path = "B.csproj" } })
        create_file("ProjectB/B.csproj")
        create_file("ProjectB/Other.cs")

        -- Open file from first project
        command("edit " .. vim.fs.joinpath(helpers.scratch, "ProjectA", "Program.cs"))
        local clients1 = get_lsp_clients()
        assert.are_equal(1, #clients1)
        assert.are_equal(vim.fs.joinpath(scratch, "ProjectA"), clients1[1].root_dir)

        -- Open file from second project
        command("edit " .. vim.fs.joinpath(helpers.scratch, "ProjectB", "Program.cs"))

        local clients2 = get_lsp_clients()
        assert.are_equal(2, #clients2)

        local root_dirs = vim.tbl_map(function(c)
            return c.root_dir
        end, clients2)

        assert.is_true(vim.tbl_contains(root_dirs, vim.fs.joinpath(scratch, "ProjectA")))
        assert.is_true(vim.tbl_contains(root_dirs, vim.fs.joinpath(scratch, "ProjectB")))
    end)

    it("falls back to project/open when csproj not in any solution", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        -- Create a CS file with csproj that is NOT included in any solution
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")

        -- Create multiple solutions that reference a DIFFERENT csproj
        create_sln_file("src/Bar/Bar.sln", {
            { name = "Other", path = [[..\Other\Other.csproj]] },
        })
        create_sln_file("src/Baz.sln", {
            { name = "Other", path = [[Other\Other.csproj]] },
        })

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))

        -- Should fall back to the csproj directory as root
        local clients = get_lsp_clients()
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Foo"), clients[1].root_dir)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("project/open", notifications[1].method)
    end)

    it("does not find solutions in sibling directories without broad_search", function()
        -- broad_search is false by default
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        -- Solution is in a sibling directory, not an ancestor
        create_sln_file("src/Bar/Bar.sln", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))

        -- Without broad_search, sibling solution is not found
        -- Should fall back to csproj
        local clients = get_lsp_clients()
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Foo"), clients[1].root_dir)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("project/open", notifications[1].method)
    end)

    it("ignores solutions in bin, obj and .git directories with broad_search", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")

        -- Create solutions in directories that should be ignored
        create_sln_file("src/bin/Bad.sln", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })
        create_sln_file("src/obj/Bad.sln", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })
        create_sln_file("src/.git/Bad.sln", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))

        -- Solutions in bin/obj/.git should be ignored, fall back to csproj
        local clients = get_lsp_clients()
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Foo"), clients[1].root_dir)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(1, #notifications)
        assert.are_equal("project/open", notifications[1].method)
    end)

    it("reuses correct instance when working with multiple projects", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Test.cs")
        create_file("src/Foo/Foo.csproj")

        create_file("src/Bar/Program.cs")
        create_file("src/Bar/Test.cs")
        create_file("src/Bar/Bar.csproj")

        create_sln_file("src/Bar/Bar.sln", { { name = "Bar", path = [[Bar.csproj]] } })
        create_sln_file("src/Foo/Foo.sln", { { name = "Foo", path = [[Foo.csproj]] } })

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))
        local bufnr1 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Bar", "Program.cs"))
        local bufnr2 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Test.cs"))
        local bufnr3 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Bar", "Test.cs"))
        local bufnr4 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        local clients = get_lsp_clients()
        assert.are_equal(2, #clients)

        local foo_clients = get_lsp_clients(bufnr1)
        assert.are_equal(1, #foo_clients)

        assert.is_true(vim.list_contains(foo_clients[1].attached_buffers, bufnr1))
        assert.is_true(vim.list_contains(foo_clients[1].attached_buffers, bufnr3))

        local bar_clients = get_lsp_clients(bufnr2)
        assert.are_equal(1, #bar_clients)

        assert.is_true(vim.list_contains(bar_clients[1].attached_buffers, bufnr2))
        assert.is_true(vim.list_contains(bar_clients[1].attached_buffers, bufnr4))

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(2, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
        assert.are_equal("solution/open", notifications[2].method)

        local solutions = {
            notifications[1].params.solution,
            notifications[2].params.solution,
        }
        assert.is_true(vim.tbl_contains(solutions, to_uri(vim.fs.joinpath(scratch, "src", "Foo", "Foo.sln"))))
        assert.is_true(vim.tbl_contains(solutions, to_uri(vim.fs.joinpath(scratch, "src", "Bar", "Bar.sln"))))
    end)

    it("reuses instance if possible", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        create_sln_file("src/Root.sln", {
            { name = "Bar", path = [[Bar\Bar.csproj]] },
            { name = "Foo", path = [[Foo\Foo.csproj]] },
        })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Test.cs")
        create_file("src/Foo/Foo.csproj")

        create_file("src/Bar/Program.cs")
        create_file("src/Bar/Test.cs")
        create_file("src/Bar/Bar.csproj")

        create_sln_file("src/Bar/Bar.sln", { { name = "Bar", path = [[Bar.csproj]] } })
        create_sln_file("src/Foo/Foo.sln", { { name = "Foo", path = [[Foo.csproj]] } })

        helpers.exec_lua(function()
            local config = require("roslyn.config")
            local current = config.get()

            current.choose_target = function(targets)
                current.choose_target = nil

                return vim.iter(targets):find(function(item)
                    return string.match(item, "Foo.sln")
                end)
            end
        end)
        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))
        local bufnr1 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        helpers.exec_lua(function()
            local config = require("roslyn.config")
            local current = config.get()

            current.choose_target = function(targets)
                current.choose_target = nil

                return vim.iter(targets):find(function(item)
                    return string.match(item, "Bar.sln")
                end)
            end
        end)
        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Bar", "Program.cs"))
        local bufnr2 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Bar", "Test.cs"))
        local bufnr3 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        local foo_clients = get_lsp_clients(bufnr1)
        local foo_attached_buffers = foo_clients[1].attached_buffers

        assert.are_equal(1, #foo_attached_buffers)
        assert.is_true(vim.list_contains(foo_attached_buffers, bufnr1))

        local bar_clients = get_lsp_clients(bufnr2)
        local bar_attached_buffers = bar_clients[1].attached_buffers

        assert.are_equal(2, #bar_attached_buffers)
        assert.is_true(vim.list_contains(bar_attached_buffers, bufnr2))
        assert.is_true(vim.list_contains(bar_attached_buffers, bufnr3))
    end)

    it("cannot determine which instance to reuse", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        create_sln_file("src/Root.sln", {
            { name = "Bar", path = [[Bar\Bar.csproj]] },
            { name = "Foo", path = [[Foo\Foo.csproj]] },
        })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Test.cs")
        create_file("src/Foo/Hello.cs")
        create_file("src/Foo/Foo.csproj")

        create_file("src/Bar/Program.cs")
        create_file("src/Bar/Test.cs")
        create_file("src/Bar/Hello.cs")
        create_file("src/Bar/Bar.csproj")

        create_sln_file("src/Bar/Bar.sln", { { name = "Bar", path = [[Bar.csproj]] } })
        create_sln_file("src/Foo/Foo.sln", { { name = "Foo", path = [[Foo.csproj]] } })

        helpers.exec_lua(function()
            local config = require("roslyn.config")
            local current = config.get()

            current.choose_target = function(targets)
                current.choose_target = nil

                return vim.iter(targets):find(function(item)
                    return string.match(item, "Root.sln")
                end)
            end
        end)
        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Bar", "Program.cs"))

        helpers.exec_lua(function()
            local config = require("roslyn.config")
            local current = config.get()

            current.choose_target = function(targets)
                current.choose_target = nil

                return vim.iter(targets):find(function(item)
                    return string.match(item, "Foo.sln")
                end)
            end
        end)
        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Program.cs"))

        helpers.exec_lua(function()
            local config = require("roslyn.config")
            local current = config.get()

            current.choose_target = function(targets)
                current.choose_target = nil

                return vim.iter(targets):find(function(item)
                    return string.match(item, "Bar.sln")
                end)
            end
        end)
        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Bar", "Hello.cs"))

        local clients = get_lsp_clients()
        assert.are_equal(3, #clients)

        -- Last attached solution is Bar, and we have two instances that we can possibly reuse
        -- So we cannot know for sure
        command("edit " .. vim.fs.joinpath(helpers.scratch, "src", "Foo", "Test.cs"))
        local bufnr4 = helpers.exec_lua(function()
            return vim.api.nvim_get_current_buf()
        end)

        local client = get_lsp_clients(bufnr4)
        assert.is_nil(client[1].root_dir)

        local notifications = helpers.exec_lua(function()
            return require("test.utils.mock_server").notifications
        end)
        assert.are_equal(3, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
        assert.are_equal("solution/open", notifications[2].method)
        assert.are_equal("solution/open", notifications[3].method)

        local solutions = {
            notifications[1].params.solution,
            notifications[2].params.solution,
            notifications[3].params.solution,
        }
        assert.is_true(vim.tbl_contains(solutions, to_uri(vim.fs.joinpath(scratch, "src", "Foo", "Foo.sln"))))
        assert.is_true(vim.tbl_contains(solutions, to_uri(vim.fs.joinpath(scratch, "src", "Bar", "Bar.sln"))))
        assert.is_true(vim.tbl_contains(solutions, to_uri(vim.fs.joinpath(scratch, "src", "Root.sln"))))
    end)
end)
