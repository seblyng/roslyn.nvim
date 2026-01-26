local helpers = require("test.utils.helpers")
local system = helpers.fn.system
local create_sln_file = helpers.create_sln_file
local create_slnf_file = helpers.create_slnf_file
local create_slnx_file = helpers.create_slnx_file
local scratch = helpers.scratch

helpers.env()

describe("api", function()
    after_each(function()
        system({ "rm", "-rf", scratch })
    end)
    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
    end)

    it("finds projects in solution", function()
        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
            { name = "Bar", path = [[..\..\Bar.csproj]] },
        })

        local sln = vim.fs.joinpath(scratch, "Foo.sln")
        local projects = helpers.exec_lua(function(target0)
            return require("roslyn.sln.api").projects(target0)
        end, sln)
        assert.are_same({
            vim.fs.joinpath(scratch, "Foo.csproj"),
            vim.fs.joinpath(scratch, [[Foo/Bar/Baz.csproj]]),
            vim.fs.normalize(vim.fs.joinpath(scratch, [[../../Bar.csproj]])),
        }, projects)
    end)

    it("finds projects in solution filter file", function()
        create_slnf_file("Foo.slnf", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
            { name = "Bar", path = [[..\..\Bar.csproj]] },
        })

        local sln = vim.fs.joinpath(scratch, "Foo.slnf")
        local projects = helpers.exec_lua(function(target0)
            return require("roslyn.sln.api").projects(target0)
        end, sln)
        assert.are_same({
            vim.fs.joinpath(scratch, "Foo.csproj"),
            vim.fs.joinpath(scratch, [[Foo/Bar/Baz.csproj]]),
            vim.fs.normalize(vim.fs.joinpath(scratch, [[../../Bar.csproj]])),
        }, projects)
    end)

    it("finds projects in solution filter file", function()
        create_slnx_file("Foo.slnx", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
            { name = "Bar", path = [[..\..\Bar.csproj]] },
        })

        local sln = vim.fs.joinpath(scratch, "Foo.slnx")
        local projects = helpers.exec_lua(function(target0)
            return require("roslyn.sln.api").projects(target0)
        end, sln)
        assert.are_same({
            vim.fs.joinpath(scratch, "Foo.csproj"),
            vim.fs.joinpath(scratch, [[Foo/Bar/Baz.csproj]]),
            vim.fs.normalize(vim.fs.joinpath(scratch, [[../../Bar.csproj]])),
        }, projects)
    end)

    it("error on unsupported extension", function()
        create_slnx_file("Foo.slna", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
            { name = "Bar", path = [[..\..\Bar.csproj]] },
        })

        local sln = vim.fs.joinpath(scratch, "Foo.slna")
        local _, err = pcall(function()
            helpers.exec_lua(function(target0)
                return require("roslyn.sln.api").projects(target0)
            end, sln)
        end)
        assert.is_not_nil(string.find(err, "Unknown extension `slna` for solution"))
    end)

    it("error on invalid solution name", function()
        create_sln_file(".sln", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
            { name = "Bar", path = [[..\..\Bar.csproj]] },
        })

        local sln = vim.fs.joinpath(scratch, ".sln")
        local _, err = pcall(function()
            helpers.exec_lua(function(target0)
                return require("roslyn.sln.api").projects(target0)
            end, sln)
        end)
        assert.is_not_nil(string.find(err, "Unknown extension `` for solution"))
    end)

    it("returns empty if file does not exist", function()
        local sln = vim.fs.joinpath(scratch, "Foo.sln")
        local projects = helpers.exec_lua(function(target0)
            return require("roslyn.sln.api").projects(target0)
        end, sln)
        assert.are_same({}, projects)
    end)
end)
