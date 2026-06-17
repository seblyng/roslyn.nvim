local helpers = require("test.utils.helpers")
local system = helpers.fn.system
local create_file = helpers.create_file
local create_sln_file = helpers.create_sln_file
local scratch = helpers.scratch

helpers.env()

describe("target resolution", function()
    after_each(function()
        system({ "rm", "-rf", scratch })
    end)

    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
    end)

    it("resolves a matching solution target", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("solution", decision.kind)
        assert.are_equal(scratch, decision.root_dir)
        assert.are_equal(vim.fs.joinpath(scratch, "Foo.sln"), decision.target)
    end)

    it("resolves a project target when no solution exists", function()
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("project", decision.kind)
        assert.are_equal(vim.fs.joinpath(scratch, "Bar"), decision.root_dir)
        assert.are_same({ vim.fs.joinpath(scratch, "Bar", "Bar.csproj") }, decision.projects)
    end)

    it("resolves an ambiguous target when multiple matching solutions exist", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_sln_file("Baz.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("ambiguous", decision.kind)
        assert.are_equal(2, #decision.targets)
    end)

    it("does not fall back to project target for ambiguous matching solutions", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_sln_file("Baz.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("ambiguous", decision.kind)
        assert.is_nil(decision.root_dir)
        assert.is_nil(decision.projects)
    end)

    it("reuses an existing client root for ambiguous matching solutions", function()
        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_sln_file("Baz.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function(scratch0)
            local get_clients = vim.lsp.get_clients
            vim.lsp.get_clients = function(opts)
                if opts and opts.name == "roslyn" then
                    return { { id = 10 } }
                end

                return get_clients(opts)
            end

            require("roslyn.store").set(10, vim.fs.joinpath(scratch0, "Baz.sln"))

            local ok, result = pcall(function()
                return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
            end)
            vim.lsp.get_clients = get_clients

            if not ok then
                error(result)
            end

            return result
        end, scratch)

        assert.are_equal("solution", decision.kind)
        assert.are_equal(scratch, decision.root_dir)
        assert.are_equal(vim.fs.joinpath(scratch, "Baz.sln"), decision.target)
    end)

    it("uses choose_target to resolve matching solutions", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({
                choose_target = function(targets)
                    return vim.iter(targets):find(function(item)
                        return string.match(item, "Baz.sln")
                    end)
                end,
            })
        end)

        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_sln_file("Baz.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("solution", decision.kind)
        assert.are_equal(vim.fs.joinpath(scratch, "Baz.sln"), decision.target)
    end)

    it("uses ignore_target during full target resolution", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({
                ignore_target = function(target)
                    return string.match(target, "Foo.sln") ~= nil
                end,
            })
        end)

        create_sln_file("Foo.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_sln_file("Baz.sln", { { name = "Bar", path = "Bar/Bar.csproj" } })
        create_file("Bar/Bar.csproj")
        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("solution", decision.kind)
        assert.are_equal(vim.fs.joinpath(scratch, "Baz.sln"), decision.target)
    end)

    it("uses broad search during full target resolution", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({ broad_search = true })
        end)

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_sln_file("src/Bar/Bar.sln", {
            { name = "Foo", path = [[..\Foo\Foo.csproj]] },
        })

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "src", "Foo", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("solution", decision.kind)
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Bar"), decision.root_dir)
        assert.are_equal(vim.fs.joinpath(scratch, "src", "Bar", "Bar.sln"), decision.target)
    end)

    it("uses a locked selected solution", function()
        helpers.exec_lua(function(scratch0)
            require("roslyn.config").setup({ lock_target = true })
            require("roslyn.store").set_selected_target(vim.fs.joinpath(scratch0, "Foo.sln"))
        end, scratch)

        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("solution", decision.kind)
        assert.are_equal(scratch, decision.root_dir)
        assert.are_equal(vim.fs.joinpath(scratch, "Foo.sln"), decision.target)
    end)

    it("falls back to the selected target when root has no target files", function()
        helpers.exec_lua(function(scratch0)
            require("roslyn.store").set_selected_target(vim.fs.joinpath(scratch0, "Selected.sln"))
        end, scratch)

        create_file("Bar/Program.cs")

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Bar", "Program.cs"))
        local decision = helpers.exec_lua(function()
            return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
        end)

        assert.are_equal("solution", decision.kind)
        assert.are_equal(scratch, decision.root_dir)
        assert.are_equal(vim.fs.joinpath(scratch, "Selected.sln"), decision.target)
    end)

    it("does not remember source-generated root reuse as a startup target", function()
        local consumed = helpers.exec_lua(function()
            local target = require("roslyn.target")
            target.remember({ kind = "reuse", root_dir = "/tmp/existing-root" })
            return target.consume("/tmp/existing-root")
        end)

        assert.is_nil(consumed)
    end)

    it("reuses an existing client root for source-generated buffers", function()
        local decision = helpers.exec_lua(function()
            vim.api.nvim_buf_set_name(0, "roslyn-source-generated://metadata/Program.cs")

            local get_clients = vim.lsp.get_clients
            vim.lsp.get_clients = function(opts)
                if opts and opts.name == "roslyn" then
                    return { { config = { root_dir = "/tmp/existing-root" } } }
                end

                return get_clients(opts)
            end

            local ok, result = pcall(function()
                return require("roslyn.target").resolve(vim.api.nvim_get_current_buf())
            end)
            vim.lsp.get_clients = get_clients

            if not ok then
                error(result)
            end

            return result
        end)

        assert.are_equal("reuse", decision.kind)
        assert.are_equal("/tmp/existing-root", decision.root_dir)
    end)
end)
