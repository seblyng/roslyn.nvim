local helpers = require("test.helpers")
local clear = helpers.clear
local system = helpers.fn.system
local create_file = helpers.create_file
local find_solutions = helpers.find_solutions
local find_solutions_broad = helpers.find_solutions_broad
local scratch = helpers.scratch

helpers.env()

describe("find_solution tests", function()
    after_each(function()
        system({ "rm", "-rf", scratch })
    end)
    before_each(function()
        clear()
        system({ "mkdir", "-p", vim.fs.joinpath(scratch, ".git") })
    end)

    it("finds solutions", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Foo.sln")

        local solutions = find_solutions("src/Foo/Program.cs")
        assert.are_same({ vim.fs.joinpath(scratch, "src", "Foo.sln") }, solutions)
    end)

    it("ignores broad solutions with regular", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Bar/Foo.sln")

        local solutions = find_solutions("src/Foo/Program.cs")
        assert.are_same({}, solutions)
    end)

    it("finds solutions broad", function()
        create_file("src/Foo/Program.cs")
        create_file("src/Bar/Foo.sln")
        create_file("src/Baz/Foo.sln")

        local solutions = find_solutions_broad("src/Foo/Program.cs")
        assert.are_same({
            vim.fs.joinpath(scratch, "src", "Bar", "Foo.sln"),
            vim.fs.joinpath(scratch, "src", "Baz", "Foo.sln"),
        }, solutions)
    end)

    it("ignores bin, obj and .git directories", function()
        create_file("src/Foo/Program.cs")
        create_file("src/bin/Foo.sln")
        create_file("src/obj/Foo.sln")
        create_file("src/.git/Foo.sln")

        local solutions = find_solutions_broad("src/Foo/Program.cs")

        assert.are_same({}, solutions)
    end)
end)
