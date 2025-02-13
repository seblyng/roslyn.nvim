local helpers = require("nvim-test.helpers")
local my_helpers = require("test.helpers")
local clear = helpers.clear
local command = helpers.api.nvim_command
local system = helpers.fn.system

helpers.env()

local scratch = my_helpers.abspath("FooRoslynTest")

---@param path string
---@return string
local function create_file(path)
    local dir = path:match("(.+)/[^/]+$")
    system({ "mkdir", "-p", vim.fs.joinpath(scratch, dir) })
    local f = assert(io.open(vim.fs.joinpath(scratch, path), "w"))
    f:write("")
    f:close()
    return path
end

local function get_root(file_path)
    command("edit " .. vim.fs.joinpath(scratch, file_path))

    return helpers.exec_lua(function(path)
        package.path = path
        local bufnr = vim.api.nvim_get_current_buf()
        return require("roslyn.sln.utils").root(bufnr)
    end, package.path)
end

local function setup(config)
    return helpers.exec_lua(function(path, config0)
        package.path = path
        return require("roslyn.init").setup(config0)
    end, package.path, config)
end

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
