local M = {}

function M.find_razor_extension_path()
    local mason_path = M.get_mason_path()
    local mason_packages = vim.fs.joinpath(mason_path, "packages")

    local stable_path = vim.fs.joinpath(mason_packages, "roslyn", "libexec", ".razorExtension")
    if vim.fn.isdirectory(stable_path) == 1 then
        return stable_path
    end

    -- TODO: Once the .razorExtension moves to the stable roslyn package, remove this
    local unstable_path = vim.fs.joinpath(mason_packages, "roslyn-unstable", "libexec", ".razorExtension")
    if vim.fn.isdirectory(unstable_path) == 1 then
        return unstable_path
    end

    return nil
end

function M.get_mason_path()
    -- Fallback in case mason is lazy loaded or MASON env var is just not set
    local expanded_mason = vim.fn.expand("$MASON")
    return expanded_mason == "$MASON" and vim.fs.joinpath(vim.fn.stdpath("data"), "mason") or expanded_mason
end

return M
