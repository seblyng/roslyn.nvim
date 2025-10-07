local helpers = require("test.helpers")
local clear = helpers.clear
local system = helpers.fn.system
local create_file = helpers.create_file
local get_root_dir = helpers.get_root_dir
local find_solutions = helpers.find_solutions
local find_solutions_broad = helpers.find_solutions_broad
local create_sln_file = helpers.create_sln_file
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

    it("finds root_dir if already attached to solution previously", function()
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

        local solutions = find_solutions_broad("Program.cs")

        -- Multiple solutions, no solution found because we haven't attached
        -- to a solution previously
        local root_dir = get_root_dir("Program.cs", solutions)
        assert.is_nil(root_dir)

        -- Already called `get_root_dir` once and "attached" to a solution.
        -- Simulate that we have already attached to `solutions[1]`, and
        -- assert that we select that if it is a part of the available solutions
        -- and provided
        root_dir = get_root_dir("Program.cs", solutions, solutions[1])
        assert.are_same(vim.fs.dirname(solutions[1]), root_dir)

        -- If the "attached" solution doesn't exist for the given file `Program.cs`
        -- we cannot use it's directory as a root dir.
        root_dir = get_root_dir("Program.cs", solutions, "NotExisting.sln")
        assert.is_nil(root_dir)
    end)

    it("finds root https://github.com/seblyng/roslyn.nvim/issues/241#issuecomment-3369301395", function()
        system({ "rmdir", vim.fs.joinpath(scratch, ".git") })

        create_file("src/Foo/Program.cs")
        create_file("src/Foo/Foo.csproj")
        create_file("src/Bar/Program.cs")
        create_file("src/Bar/Bar.csproj")

        create_sln_file("src/Bar/Bar.sln", {
            { name = "Bar", path = [[Bar.csproj]] },
        })

        create_sln_file("src/solution.sln", {
            { name = "Bar", path = [[Bar\Bar.csproj]] },
            { name = "Foo", path = [[Foo\Foo.csproj]] },
        })

        local solutions = find_solutions_broad("src/Bar/Program.cs")
        local root_dir = get_root_dir("src/Bar/Program.cs", solutions)

        assert.are_same({
            vim.fs.joinpath(scratch, "src", "solution.sln"),
            vim.fs.joinpath(scratch, "src", "Bar", "Bar.sln"),
        }, solutions)

        -- The root dir is nil because we cannot determine what the root directory should be
        assert.is_nil(root_dir)
    end)
end)
