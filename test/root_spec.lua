local helpers = require("test.helpers")
local clear = helpers.clear
local system = helpers.fn.system
local create_file = helpers.create_file
local get_root_dir = helpers.get_root_dir
local find_solutions = helpers.find_solutions
local find_solutions_broad = helpers.find_solutions_broad
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

    it("finds a root_dir of project file", function()
        create_file("Program.cs")
        create_file("Foo.csproj")

        local solutions = find_solutions("Program.cs")
        local root_dir = get_root_dir("Program.cs", solutions)

        assert.are_same(scratch, root_dir)
    end)

    it("finds root_dir of sln file", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar.sln")

        local solutions = find_solutions("src/Foo/Program.cs")
        local root_dir = get_root_dir("src/Foo/Program.cs", solutions)

        assert.are_same(vim.fs.joinpath(scratch, "src"), root_dir)
    end)

    it("fallback to csproj, multiple solutions, cs file not related to solution", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.sln")
        create_file("src/Baz.sln")

        local solutions = find_solutions_broad("src/Foo/Program.cs")
        local root_dir = get_root_dir("src/Foo/Program.cs", solutions)

        assert.are_same(vim.fs.joinpath(scratch, "src", "Foo"), root_dir)
    end)

    it("finds root of sln file with broad search and no solution in git root", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.sln")

        local solutions = find_solutions_broad("src/Foo/Program.cs")
        local root_dir = get_root_dir("src/Foo/Program.cs", solutions)

        assert.are_same(vim.fs.joinpath(scratch, "src", "Bar"), root_dir)
    end)

    it("finds a slnf file with broad search and no solution in git root", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Bar.slnf")

        local solutions = find_solutions_broad("src/Foo/Program.cs")
        local root_dir = get_root_dir("src/Foo/Program.cs", solutions)

        assert.are_same(vim.fs.joinpath(scratch, "src", "Bar"), root_dir)
    end)
end)
