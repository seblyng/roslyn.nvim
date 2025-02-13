local helpers = require("test.helpers")
local clear = helpers.clear
local system = helpers.fn.system
local create_file = helpers.create_file
local get_root = helpers.get_root
local setup = helpers.setup
local scratch = helpers.scratch

helpers.env()

describe("root tests", function()
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

        local root = get_root("Program.cs")

        assert.is_nil(root.projects)
        assert.are_same({}, root.solution_filters)
        assert.are_same({}, root.solutions)
    end)

    it("finds a project file", function()
        create_file("Program.cs")
        create_file("Foo.csproj")

        local root = get_root("Program.cs")

        assert.are_same({ vim.fs.joinpath(scratch, "Foo.csproj") }, root.projects.files)
        assert.are_same({}, root.solution_filters)
        assert.are_same({}, root.solutions)
    end)

    it("finds a sln file", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar.sln")

        local root = get_root("src/Foo/Program.cs")

        assert.are_same({ vim.fs.joinpath(scratch, "src/Foo/Foo.csproj") }, root.projects.files)
        assert.are_same({ vim.fs.joinpath(scratch, "src/Bar.sln") }, root.solutions)

        assert.are_same({}, root.solution_filters)
    end)

    it("requires a project file with broad search", function()
        setup({ broad_search = true })

        create_file("Program.cs")
        create_file("Foo.sln")

        local root = get_root("Program.cs")

        assert.are_same({}, root.solution_filters)
        assert.are_same({}, root.solutions)
        assert.is_nil(root.projects)
    end)

    it("finds a sln file with broad search and one solution in git root", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.sln")
        create_file("src/Baz.sln")

        local root = get_root("src/Foo/Program.cs")

        assert.are_same({ vim.fs.joinpath(scratch, "src/Foo/Foo.csproj") }, root.projects.files)
        assert.are_same({
            vim.fs.joinpath(scratch, "src/Baz.sln"),
            vim.fs.joinpath(scratch, "src/Bar/Bar.sln"),
        }, root.solutions)

        assert.are_same({}, root.solution_filters)
    end)

    it("finds a sln file with broad search and no solution in git root", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.sln")

        local root = get_root("src/Foo/Program.cs")

        assert.are_same({ vim.fs.joinpath(scratch, "src/Foo/Foo.csproj") }, root.projects.files)
        assert.are_same({ vim.fs.joinpath(scratch, "src/Bar/Bar.sln") }, root.solutions)

        assert.are_same({}, root.solution_filters)
    end)

    it("finds a slnf file with broad search and no solution in git root", function()
        setup({ broad_search = true })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.slnf")

        local root = get_root("src/Foo/Program.cs")

        assert.are_same({ vim.fs.joinpath(scratch, "src/Foo/Foo.csproj") }, root.projects.files)
        assert.are_same({ vim.fs.joinpath(scratch, "src/Bar/Bar.slnf") }, root.solution_filters)
    end)
end)
