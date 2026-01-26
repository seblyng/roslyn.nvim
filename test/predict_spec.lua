local helpers = require("test.utils.helpers")
local system = helpers.fn.system
local create_file = helpers.create_file
local create_sln_file = helpers.create_sln_file
local scratch = helpers.scratch

helpers.env()

describe("predicts", function()
    after_each(function()
        system({ "rm", "-rf", scratch })
    end)
    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
    end)

    it("predicts target if project file in solution", function()
        create_file("Program.cs")
        create_file("Foo.csproj")
        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        local targets = {
            vim.fs.joinpath(scratch, "Foo.sln"),
        }

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Program.cs"))
        local target = helpers.exec_lua(function(targets0)
            local bufnr = vim.api.nvim_get_current_buf()
            return require("roslyn.sln.utils").predict_target(bufnr, targets0)
        end, targets)
        assert.are_same(vim.fs.joinpath(scratch, "Foo.sln"), target)
    end)

    it("predicts nil if project file is not in solution", function()
        create_file("Program.cs")
        create_file("Bar.csproj")
        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        local targets = {
            vim.fs.joinpath(scratch, "Foo.sln"),
        }

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Program.cs"))
        local target = helpers.exec_lua(function(targets0)
            local bufnr = vim.api.nvim_get_current_buf()
            return require("roslyn.sln.utils").predict_target(bufnr, targets0)
        end, targets)
        assert.is_nil(target)
    end)

    it("predicts from multiple if project file is not in solution", function()
        create_file("Program.cs")
        create_file("Bar.csproj")

        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        create_sln_file("FooBar.sln", {
            { name = "Foo", path = "Bar.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        local targets = {
            vim.fs.joinpath(scratch, "Foo.sln"),
            vim.fs.joinpath(scratch, "FooBar.sln"),
        }

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Program.cs"))
        local target = helpers.exec_lua(function(targets0)
            local bufnr = vim.api.nvim_get_current_buf()
            return require("roslyn.sln.utils").predict_target(bufnr, targets0)
        end, targets)
        assert.are_same(vim.fs.joinpath(scratch, "FooBar.sln"), target)
    end)

    it("predicts nil if multiple solutions have same project file in solution", function()
        create_file("Program.cs")
        create_file("Bar.csproj")

        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Bar.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        create_sln_file("FooBar.sln", {
            { name = "Foo", path = "Bar.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        local targets = {
            vim.fs.joinpath(scratch, "Foo.sln"),
            vim.fs.joinpath(scratch, "FooBar.sln"),
        }

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Program.cs"))
        local target = helpers.exec_lua(function(targets0)
            local bufnr = vim.api.nvim_get_current_buf()
            return require("roslyn.sln.utils").predict_target(bufnr, targets0)
        end, targets)
        assert.is_nil(target)
    end)

    it("can ignore target with config method", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({
                ignore_target = function(sln)
                    return string.match(sln, "Foo.sln") ~= nil
                end,
            })
        end)

        create_file("Program.cs")
        create_file("Bar.csproj")

        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Bar.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        create_sln_file("FooBar.sln", {
            { name = "Foo", path = "Bar.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        local targets = {
            vim.fs.joinpath(scratch, "Foo.sln"),
            vim.fs.joinpath(scratch, "FooBar.sln"),
        }

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Program.cs"))
        local target = helpers.exec_lua(function(targets0)
            local bufnr = vim.api.nvim_get_current_buf()
            return require("roslyn.sln.utils").predict_target(bufnr, targets0)
        end, targets)
        assert.are_same(vim.fs.joinpath(scratch, "FooBar.sln"), target)
    end)

    it("can choose target with config method", function()
        helpers.exec_lua(function()
            require("roslyn.config").setup({
                choose_target = function(targets)
                    return vim.iter(targets):find(function(item)
                        return string.match(item, "Foo.sln")
                    end)
                end,
            })
        end)

        create_file("Program.cs")
        create_file("Bar.csproj")

        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Bar.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        create_sln_file("FooBar.sln", {
            { name = "Foo", path = "Bar.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
        })

        local targets = {
            vim.fs.joinpath(scratch, "Foo.sln"),
            vim.fs.joinpath(scratch, "FooBar.sln"),
        }

        helpers.api.nvim_command("edit " .. vim.fs.joinpath(scratch, "Program.cs"))
        local target = helpers.exec_lua(function(targets0)
            local bufnr = vim.api.nvim_get_current_buf()
            return require("roslyn.sln.utils").predict_target(bufnr, targets0)
        end, targets)
        assert.are_same(vim.fs.joinpath(scratch, "Foo.sln"), target)
    end)
end)
