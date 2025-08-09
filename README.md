# roslyn.nvim

This is an actively maintained & upgraded [fork](https://github.com/jmederosalvarado/roslyn.nvim) that interacts with the improved & open-source C# [Roslyn](https://github.com/dotnet/roslyn) language server, meant to replace the old and discontinued OmniSharp. This language server is currently used in the [Visual Studio Code C# Extension](https://github.com/dotnet/vscode-csharp), which is shipped with the standard C# Dev Kit.

## IMPORTANT

This plugin does not provide Razor support.

Check out https://github.com/tris203/rzls.nvim if you are using Razor.

## ⚡️ Requirements

- Neovim >= 0.11.0
- Roslyn language server downloaded locally
- .NET SDK installed and `dotnet` command available

## Difference to nvim-lspconfig

`roslyn` is now a part of [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig), but it does not implement all things that are implemented here. This plugin
tries to keep things minimal but still implement some things that is not suited for [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig).
A couple of additional things this plugin implements

- Support for multiple solutions
- Broad root_dir detection support. Meaning it will search for solutions upward in parent directories if `broad_search` option is set
- Support for source generated files
- Support for `Fix all`, `Nested code actions` and `Complex edit`.
- `Roslyn target` command to switch between multiple solutions

## Demo

https://github.com/user-attachments/assets/a749f6c7-fc87-440c-912d-666d86453bc5

## 📦 Installation

<details>
  <summary>Mason</summary>
  
  `roslyn` is not in the mason core registry, so a custom registry is used.
  This registry provides two binaries
  - `roslyn` (To be used with this repo)
  - `rzls` (To be used with [rzls.nvim](https://github.com/tris203/rzls.nvim))

You need to set up the custom registry like this

```lua
require("mason").setup({
    registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
    },
})
```

You can then install it with `:MasonInstall roslyn` or through the popup menu by running `:Mason`. It is not available through [mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim) and the `:LspInstall` interface
When installing the server through mason, the cmd is automatically added to the LSP config, so no need to add it manually

The stable version of `roslyn` is provided through `roslyn` in the mason registry. This is the same version as in vscode.
If you want the bleeding edge features, you can choose `roslyn-unstable`. Be aware of breaking changes if you choose this version

**NOTE**

There's currently an open [pull request](https://github.com/mason-org/mason-registry/pull/6330) to add the Roslyn server to [mason](https://github.com/williamboman/mason.nvim), which would greatly improve the experience. If you are interested in this, please react to the original comment, but don't spam the thread with unnecessary comments.

</details>

<details>
  <summary>Manually</summary>

NOTE: The manual installation instructions are the same for this plugin and for nvim-lspconfig.
The following instructions are copied from [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#roslyn_ls).
If the installation instructions are not up-to-date or not clear, please first send a PR to `nvim-lspconfig` with improvements so that we can align the installation instructions.

To install the server, compile from source or download as nuget package.
Go to `https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl/NuGet/Microsoft.CodeAnalysis.LanguageServer.<platform>/overview`
replace `<platform>` with one of the following `linux-x64`, `osx-x64`, `win-x64`, `neutral` (for more info on the download location see https://github.com/dotnet/roslyn/issues/71474#issuecomment-2177303207).
Download and extract it (nuget's are zip files).

- if you chose `neutral` nuget version, then you have to change the `cmd` like so:

```lua
cmd = {
    "dotnet",
    "<my_folder>/Microsoft.CodeAnalysis.LanguageServer.dll",
    "--logLevel", -- this property is required by the server
    "Information",
    "--extensionLogDirectory", -- this property is required by the server
    fs.joinpath(uv.os_tmpdir(), "roslyn_ls/logs"),
    "--stdio",
}
```

where `<my_folder>` has to be the folder you extracted the nuget package to.

- for all other platforms put the extracted folder to neovim's PATH (`vim.env.PATH`)

</details>

> [!TIP]  
> For server compatibility check the [roslyn repo](https://github.com/dotnet/roslyn/blob/main/docs/wiki/NuGet-packages.md#versioning)

**Install the plugin with your preferred package manager:**

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
    "seblyng/roslyn.nvim",
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {
        -- your configuration comes here; leave empty for default settings
    },
}
```

## ⚙️ Configuration

The plugin comes with the following defaults:

```lua
opts = {
    -- "auto" | "roslyn" | "off"
    --
    -- - "auto": Does nothing for filewatching, leaving everything as default
    -- - "roslyn": Turns off neovim filewatching which will make roslyn do the filewatching
    -- - "off": Hack to turn off all filewatching. (Can be used if you notice performance issues)
    filewatching = "auto",

    -- Optional function that takes an array of targets as the only argument. Return the target you
    -- want to use. If it returns `nil`, then it falls back to guessing the target like normal
    -- Example:
    --
    -- choose_target = function(target)
    --     return vim.iter(target):find(function(item)
    --         if string.match(item, "Foo.sln") then
    --             return item
    --         end
    --     end)
    -- end
    choose_target = nil,

    -- Optional function that takes the selected target as the only argument.
    -- Returns a boolean of whether it should be ignored to attach to or not
    --
    -- I am for example using this to disable a solution with a lot of .NET Framework code on mac
    -- Example:
    --
    -- ignore_target = function(target)
    --     return string.match(target, "Foo.sln") ~= nil
    -- end
    ignore_target = nil,

    -- Whether or not to look for solution files in the child of the (root).
    -- Set this to true if you have some projects that are not a child of the
    -- directory with the solution file
    broad_search = false,

    -- Whether or not to lock the solution target after the first attach.
    -- This will always attach to the target in `vim.g.roslyn_nvim_selected_solution`.
    -- NOTE: You can use `:Roslyn target` to change the target
    lock_target = false,
}
```

To configure language server specific settings sent to the server, you can use the `vim.lsp.config` interface with `roslyn` as the name of the server.

## Example

```lua
vim.lsp.config("roslyn", {
    on_attach = function()
        print("This will run when the server attaches!")
    end,
    settings = {
        ["csharp|inlay_hints"] = {
            csharp_enable_inlay_hints_for_implicit_object_creation = true,
            csharp_enable_inlay_hints_for_implicit_variable_types = true,
        },
        ["csharp|code_lens"] = {
            dotnet_enable_references_code_lens = true,
        },
    },
})
```

Some tips and tricks that may be useful, but not in the scope of this plugin,
are documented in the [wiki](https://github.com/seblyng/roslyn.nvim/wiki).

> [!NOTE]  
> These settings are not guaranteed to be up-to-date and new ones can appear in the future. Aditionally, not not all settings are shown here, but only the most relevant ones for Neovim. For a full list, visit [this](https://github.com/dotnet/vscode-csharp/blob/main/test/lsptoolshost/unitTests/configurationMiddleware.test.ts) unit test from the vscode extension and look especially for the ones which **don't** have `vsCodeConfiguration: null`.

### Background Analysis

`csharp|background_analysis`

These settings control the scope of background diagnostics.

- `background_analysis.dotnet_analyzer_diagnostics_scope`  
  Scope of the background analysis for .NET analyzer diagnostics.  
  Expected values: `openFiles`, `fullSolution`, `none`

- `background_analysis.dotnet_compiler_diagnostics_scope`  
  Scope of the background analysis for .NET compiler diagnostics.  
  Expected values: `openFiles`, `fullSolution`, `none`

### Code Lens

`csharp|code_lens`

These settings control the LSP code lens.

- `dotnet_enable_references_code_lens`  
  Enable code lens references.  
  Expected values: `true`, `false`

- `dotnet_enable_tests_code_lens`  
  Enable tests code lens.  
  Expected values: `true`, `false`

> [!TIP]
> You must refresh the code lens yourself. Check `:h vim.lsp.codelens.refresh()` and the example autocmd.

### Completions

`csharp|completion`

These settings control how the completions behave.

- `dotnet_provide_regex_completions`  
  Show regular expressions in completion list.  
  Expected values: `true`, `false`

- `dotnet_show_completion_items_from_unimported_namespaces`  
  Enables support for showing unimported types and unimported extension methods in completion lists.  
  Expected values: `true`, `false`

- `dotnet_show_name_completion_suggestions`  
  Perform automatic object name completion for the members that you have recently selected.  
  Expected values: `true`, `false`

### Inlay hints

`csharp|inlay_hints`

These settings control what inlay hints should be displayed.

- `csharp_enable_inlay_hints_for_implicit_object_creation`  
  Show hints for implicit object creation.  
  Expected values: `true`, `false`

- `csharp_enable_inlay_hints_for_implicit_variable_types`  
  Show hints for variables with inferred types.  
  Expected values: `true`, `false`

- `csharp_enable_inlay_hints_for_lambda_parameter_types`  
  Show hints for lambda parameter types.  
  Expected values: `true`, `false`

- `csharp_enable_inlay_hints_for_types`  
  Display inline type hints.  
  Expected values: `true`, `false`

- `dotnet_enable_inlay_hints_for_indexer_parameters`  
  Show hints for indexers.  
  Expected values: `true`, `false`

- `dotnet_enable_inlay_hints_for_literal_parameters`  
  Show hints for literals.  
  Expected values: `true`, `false`

- `dotnet_enable_inlay_hints_for_object_creation_parameters`  
  Show hints for 'new' expressions.  
  Expected values: `true`, `false`

- `dotnet_enable_inlay_hints_for_other_parameters`  
  Show hints for everything else.  
  Expected values: `true`, `false`

- `dotnet_enable_inlay_hints_for_parameters`  
  Display inline parameter name hints.  
  Expected values: `true`, `false`

- `dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix`  
  Suppress hints when parameter names differ only by suffix.  
  Expected values: `true`, `false`

- `dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name`  
  Suppress hints when argument matches parameter name.  
  Expected values: `true`, `false`

- `dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent`  
  Suppress hints when parameter name matches the method's intent.  
  Expected values: `true`, `false`

> [!TIP]
> These won't have any effect if you don't enable inlay hints in your config. Check `:h vim.lsp.inlay_hint.enable()`.

### Symbol search

`csharp|symbol_search`

This setting controls how the language server should search for symbols.

- `dotnet_search_reference_assemblies`  
  Search symbols in reference assemblies.  
  Expected values: `true`, `false`

### Formatting

`csharp|formatting`

This setting controls how the language server should format code.

- `dotnet_organize_imports_on_format`  
  Sort using directives on format alphabetically.  
  Expected values: `true`, `false`

## 📚 Commands

- `:Roslyn restart` restarts the server
- `:Roslyn start` starts the server
- `:Roslyn stop` stops the server
- `:Roslyn target` chooses a solution if there are multiple to chose from

## 🚀 Other usage

- If you have multiple solutions, this plugin tries to guess which one to use. You can change the target with the `:Roslyn target` command.
- The current solution is always stored in `vim.g.roslyn_nvim_selected_solution`. You can use this, for example, to display the current solution in your statusline.
