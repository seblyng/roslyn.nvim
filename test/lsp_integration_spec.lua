local helpers = require("test.helpers")
local system = helpers.fn.system
local create_file = helpers.create_file
local create_sln_file = helpers.create_sln_file
local create_slnf_file = helpers.create_slnf_file
local scratch = helpers.scratch
local setup = helpers.setup
local get_mock_server_notifications = helpers.get_mock_server_notifications
local open_file_and_wait_for_lsp = helpers.open_file_and_wait_for_lsp
local get_lsp_clients = helpers.get_lsp_clients
local get_selected_solution = helpers.get_selected_solution
local choose_solution_once = helpers.choose_solution_once
local wait = helpers.wait

---Converts a file path to a file:// URI
---@param path string
---@return string
local function to_uri(path)
    return "file://" .. path
end

helpers.env()

describe("LSP integration with mock server", function()
    after_each(function()
        helpers.exec_lua(function()
            require("test.mock_server").reset()
        end)
        system({ "rm", "-rf", scratch })
    end)

    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
        helpers.use_test_server()
    end)

    it("starts LSP client with correct root_dir for single solution", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        open_file_and_wait_for_lsp("Bar/Program.cs")

        -- Give the server a moment to write the log
        wait(100)

        local clients = get_lsp_clients()
        assert.are_equal(1, #clients)
        assert.are_equal(scratch, clients[1].root_dir)

        local notifications = get_mock_server_notifications()
        assert.are_equal(1, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
        assert.are_equal(to_uri(vim.fs.joinpath(scratch, "Foo.sln")), notifications[1].params.solution)
    end)

    it("sends project/open when no solution exists", function()
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        open_file_and_wait_for_lsp("Bar/Program.cs")

        wait(100)

        local notifications = get_mock_server_notifications()
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
        open_file_and_wait_for_lsp("Bar/Program.cs")

        local clients_after_first = get_lsp_clients()
        assert.are_equal(1, #clients_after_first)

        -- Open second file in same solution
        open_file_and_wait_for_lsp("Baz/Other.cs")

        -- Should still be only 1 client and same client
        local clients_after_second = get_lsp_clients()
        assert.are_equal(1, #clients_after_second)
        assert.are_equal(clients_after_first[1].id, clients_after_second[1].id)

        -- Should only have sent solution/open once
        wait(100)
        local notifications = get_mock_server_notifications()
        assert.are_equal(1, #notifications)
    end)

    it("stores selected solution in global variable", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        open_file_and_wait_for_lsp("Bar/Program.cs")

        local selected = get_selected_solution()
        assert.are_equal(vim.fs.joinpath(scratch, "Foo.sln"), selected)
    end)

    it("finds solution with broad_search enabled", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_sln_file("src/Bar/Bar.sln", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })

        open_file_and_wait_for_lsp("src/Foo/Program.cs")

        local clients = get_lsp_clients()
        assert.are_equal(1, #clients)
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Bar"), clients[1].root_dir)

        wait(100)
        local notifications = get_mock_server_notifications()
        assert.are_equal(1, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
    end)

    it("finds slnf file and sends solution/open", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_slnf_file("src/Bar/Bar.slnf", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })

        open_file_and_wait_for_lsp("src/Foo/Program.cs")

        local clients = get_lsp_clients()
        assert.are_equal(1, #clients)
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Bar"), clients[1].root_dir)

        wait(100)
        local notifications = get_mock_server_notifications()
        assert.are_equal(1, #notifications)
        assert.are_equal("solution/open", notifications[1].method)
        assert.are_equal(to_uri(vim.fs.joinpath(scratch, "src", "Bar", "Bar.slnf")), notifications[1].params.solution)
    end)

    it("uses choose_target to select solution when multiple exist", function()
        setup({ choose_target = "Bar.sln" })

        create_file("src/Program.cs")
        create_file("src/Foo.csproj")
        create_sln_file("Foo.sln", { { name = "Foo", path = "src/Foo.csproj" } })
        create_sln_file("Bar.sln", { { name = "Foo", path = "src/Foo.csproj" } })

        open_file_and_wait_for_lsp("src/Program.cs")

        local clients = get_lsp_clients()
        assert.are_equal(1, #clients)

        wait(100)
        local notifications = get_mock_server_notifications()
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
        open_file_and_wait_for_lsp("Bar/Program.cs", 1000)

        -- Client starts but with nil root_dir, so no solution/open is sent
        wait(100)
        local notifications = get_mock_server_notifications()
        assert.are_equal(0, #notifications)

        -- root_dir should be nil
        assert.is_nil(get_lsp_clients()[1].root_dir)
    end)

    it("starts separate clients for different solutions", function()
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
        open_file_and_wait_for_lsp("ProjectA/Program.cs")
        local clients1 = get_lsp_clients()
        assert.are_equal(1, #clients1)
        assert.are_equal(vim.fs.joinpath(scratch, "ProjectA"), clients1[1].root_dir)

        -- Open file from second project
        open_file_and_wait_for_lsp("ProjectB/Other.cs")

        -- Wait specifically for 2 clients to be running
        local has_two = helpers.wait_for_client_count(2, 5000)
        assert.is_true(has_two)

        local clients2 = get_lsp_clients()
        assert.are_equal(2, #clients2)

        local root_dirs = vim.tbl_map(function(c)
            return c.root_dir
        end, clients2)

        assert.is_true(vim.tbl_contains(root_dirs, vim.fs.joinpath(scratch, "ProjectA")))
        assert.is_true(vim.tbl_contains(root_dirs, vim.fs.joinpath(scratch, "ProjectB")))
    end)

    it("falls back to project/open when csproj not in any solution", function()
        setup({ broad_search = true })

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

        open_file_and_wait_for_lsp("src/Foo/Program.cs")

        -- Should fall back to the csproj directory as root
        local clients = get_lsp_clients()
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Foo"), clients[1].root_dir)

        wait(100)
        local notifications = get_mock_server_notifications()
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

        open_file_and_wait_for_lsp("src/Foo/Program.cs")

        -- Without broad_search, sibling solution is not found
        -- Should fall back to csproj
        local clients = get_lsp_clients()
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Foo"), clients[1].root_dir)

        wait(100)
        local notifications = get_mock_server_notifications()
        assert.are_equal(1, #notifications)
        assert.are_equal("project/open", notifications[1].method)
    end)

    it("ignores solutions in bin, obj and .git directories with broad_search", function()
        setup({ broad_search = true })

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

        open_file_and_wait_for_lsp("src/Foo/Program.cs")

        -- Solutions in bin/obj/.git should be ignored, fall back to csproj
        local clients = get_lsp_clients()
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Foo"), clients[1].root_dir)

        wait(100)
        local notifications = get_mock_server_notifications()
        assert.are_equal(1, #notifications)
        assert.are_equal("project/open", notifications[1].method)
    end)

    it("reuses correct instance when working with multiple projects", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Test.cs")
        create_file("src/Foo/Foo.csproj")

        create_file("src/Bar/Program.cs")
        create_file("src/Bar/Test.cs")
        create_file("src/Bar/Bar.csproj")

        create_sln_file("src/Bar/Bar.sln", { { name = "Bar", path = [[Bar.csproj]] } })
        create_sln_file("src/Foo/Foo.sln", { { name = "Foo", path = [[Foo.csproj]] } })

        local bufnr1 = open_file_and_wait_for_lsp("src/Foo/Program.cs")
        local bufnr2 = open_file_and_wait_for_lsp("src/Bar/Program.cs")

        local bufnr3 = open_file_and_wait_for_lsp("src/Foo/Test.cs")
        local bufnr4 = open_file_and_wait_for_lsp("src/Bar/Test.cs")

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

        wait(100)
        local notifications = get_mock_server_notifications()
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
        setup({ broad_search = true })

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

        choose_solution_once("Foo.sln")
        local bufnr1 = open_file_and_wait_for_lsp("src/Foo/Program.cs")

        choose_solution_once("Bar.sln")
        local bufnr2 = open_file_and_wait_for_lsp("src/Bar/Program.cs")

        local bufnr3 = open_file_and_wait_for_lsp("src/Bar/Test.cs")

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
        setup({ broad_search = true })

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

        choose_solution_once("Root.sln")
        open_file_and_wait_for_lsp("src/Bar/Program.cs")

        choose_solution_once("Foo.sln")
        open_file_and_wait_for_lsp("src/Foo/Program.cs")

        choose_solution_once("Bar.sln")
        open_file_and_wait_for_lsp("src/Bar/Hello.cs")

        local clients = get_lsp_clients()
        assert.are_equal(3, #clients)

        -- Last attached solution is Bar, and we have two instances that we can possibly reuse
        -- So we cannot know for sure
        local bufnr4 = open_file_and_wait_for_lsp("src/Foo/Test.cs")

        local client = get_lsp_clients(bufnr4)
        assert.is_nil(client[1].root_dir)

        wait(100)
        local notifications = get_mock_server_notifications()
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
