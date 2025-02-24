local helpers = require("test.helpers")
local clear = helpers.clear
local system = helpers.fn.system
local create_sln_file = helpers.create_sln_file
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
end)
