local helpers = require("test.helpers")
local system = helpers.fn.system
local create_file = helpers.create_file
local create_sln_file = helpers.create_sln_file
local predict_target = helpers.predict_target
local scratch = helpers.scratch
local setup = helpers.setup

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

        local target = predict_target("Program.cs", targets)
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

        local target = predict_target("Program.cs", targets)
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

        local target = predict_target("Program.cs", targets)
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

        local target = predict_target("Program.cs", targets)
        assert.is_nil(target)
    end)

    it("can ignore target with config method", function()
        setup({ ignore_target = "Foo.sln" })

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

        local target = predict_target("Program.cs", targets)
        assert.are_same(vim.fs.joinpath(scratch, "FooBar.sln"), target)
    end)

    it("can choose target with config method", function()
        setup({ choose_target = "Foo.sln" })

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

        local target = predict_target("Program.cs", targets)
        assert.are_same(vim.fs.joinpath(scratch, "Foo.sln"), target)
    end)
end)
