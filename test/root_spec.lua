local helpers = require("test.helpers")
local clear = helpers.clear
local system = helpers.fn.system
local create_file = helpers.create_file
local get_root_dir = helpers.get_root_dir
local setup = helpers.setup
local scratch = helpers.scratch

helpers.env()

describe("root_dir tests", function()
    after_each(function()
        system({ "rm", "-rf", scratch })
    end)
    before_each(function()
        clear()
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
    end)

    it("requires a project file", function()
        create_file("Program.cs")
        create_file("Foo.sln")

        local root_dir = get_root_dir("Program.cs")
        assert.is_nil(root_dir)
    end)

    it("finds a root_dir of project file", function()
        create_file("Program.cs")
        create_file("Foo.csproj")

        local root_dir = get_root_dir("Program.cs")

        assert.are_same(scratch, root_dir)
    end)

    it("finds root_dir of sln file", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar.sln")

        local root_dir = get_root_dir("src/Foo/Program.cs")

        assert.are_same(vim.fs.joinpath(scratch, "src"), root_dir)
    end)

    it("requires a project file with broad search", function()
        setup({ broad_search = true })

        create_file("Program.cs")
        create_file("Foo.sln")

        local root_dir = get_root_dir("Program.cs")

        assert.is_nil(root_dir)
    end)

    it("finds no root_dir with broad search, multiple sln", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.sln")
        create_file("src/Baz.sln")

        local root_dir = get_root_dir("src/Foo/Program.cs")

        assert.is_nil(root_dir)
    end)

    it("finds root of sln file with broad search and no solution in git root", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.sln")

        local root_dir = get_root_dir("src/Foo/Program.cs")

        assert.are_same(vim.fs.joinpath(scratch, "src", "Bar"), root_dir)
    end)

    it("finds a slnf file with broad search and no solution in git root", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.slnf")

        local root_dir = get_root_dir("src/Foo/Program.cs")

        assert.are_same(vim.fs.joinpath(scratch, "src", "Bar"), root_dir)
    end)
end)
