local helpers = require("test.helpers")
local clear = helpers.clear
local system = helpers.fn.system
local create_sln_file = helpers.create_sln_file
local create_slnf_file = helpers.create_slnf_file
local create_slnx_file = helpers.create_slnx_file
local api_projects = helpers.api_projects
local scratch = helpers.scratch

helpers.env()

describe("api", function()
    after_each(function()
        system({ "rm", "-rf", scratch })
    end)
    before_each(function()
        clear()
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
    end)

    it("finds projects in solution", function()
        create_sln_file("Foo.sln", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
            { name = "Bar", path = [[..\..\Bar.csproj]] },
        })

        local projects = api_projects("Foo.sln")
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

        local projects = api_projects("Foo.slnf")
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

        local projects = api_projects("Foo.slnx")
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

        local _, err = pcall(api_projects, "Foo.slna")
        assert.is_not_nil(string.find(err, "Unknown extension `slna` for solution"))
    end)

    it("error on invalid solution name", function()
        create_sln_file(".sln", {
            { name = "Foo", path = "Foo.csproj" },
            { name = "Baz", path = [[Foo\Bar\Baz.csproj]] },
            { name = "Bar", path = [[..\..\Bar.csproj]] },
        })

        local _, err = pcall(api_projects, ".sln")
        assert.is_not_nil(string.find(err, "Extension not found for"))
    end)

    it("returns empty if file does not exist", function()
        local projects = api_projects("Foo.sln")
        assert.are_same({}, projects)
    end)
end)
