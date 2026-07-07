# roslyn.nvim

This is an actively maintained & upgraded [fork](https://github.com/jmederosalvarado/roslyn.nvim) that interacts with the improved & open-source C# [Roslyn](https://github.com/dotnet/roslyn) language server, meant to replace the old and discontinued OmniSharp. This language server is currently used in the [Visual Studio Code C# Extension](https://github.com/dotnet/vscode-csharp), which is shipped with the standard C# Dev Kit.

## Razor/CSHTML Support

This plugin has recently added support for Razor/CSHTML files. This enabled
razor support using co-hosting and superceeds the old
[rzls.nvim](https://github.com/tris203/rzls.nvim).

If you previoulsy used `rzls.nvim`, please uninstall it and the `rzls` language
server.

## ⚡️ Requirements

- Neovim >= 0.12.0
- Roslyn language server downloaded locally
- .NET SDK installed and `dotnet` command available

## Difference to nvim-lspconfig

`roslyn` is now a part of [nvim-lspconfig], but it does not implement all things that are implemented here.  
This plugin tries to keep things minimal but still implement some things that is not suited for [nvim-lspconfig].  
A couple of additional things this plugin implements

- Support for multiple solutions
- Broad root_dir detection support. Meaning it will search for solutions upward in parent directories if `broad_search` option is set
- Support for source generated files
- `Roslyn target` command to switch between multiple solutions

## Demo

https://github.com/user-attachments/assets/a749f6c7-fc87-440c-912d-666d86453bc5

## 📦 Installation

<details>
  <summary>Mason (recommended)</summary>

You can install with `MasonInstall roslyn-language-server`. Note that this is installing it from [nuget.org] which is not necessarily up to date with the same version used in vscode.

For the time being, I would recommend using a custom registry to get a more up to date version.
For this, you need to use a custom mason registry and set it up like this.

```lua
require("mason").setup({
    registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
    },
})
```

This registry provides two versions:
- `roslyn` (same version as in vscode)
- `roslyn-nightly` (bleeding edge features with potentially breaking changes)

</details>

<details>
  <summary>Manually</summary>

  `roslyn-language-server` supports razor since version `5.8.0-1.26262.10`.
  This allows installation of the lsp as a [dotnet tool](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools).

  This dotnet tool exists at two places:
  * [nuget.org], which is not updated that often.
  * [Azure Devops feed], where updates happen multiple times a day.

  It is highly recommended to use the [Azure DevOps feed].

  > [!IMPORTANT]  
  > The version used in vscode can be extracted [here](https://github.com/dotnet/vscode-csharp/blob/main/package.json#L43).  
  > The extension uses the [Azure Devops feed] as well.

  ```bash
  # Installing the tool using the more recent Azure Devops feed
  # This will take few seconds so please be patient
  dotnet tool install -g roslyn-language-server --prerelease --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
    You can invoke the tool using the following command: roslyn-language-server
    Tool 'roslyn-language-server' (version '5.8.0-1.26263.4') was successfully installed.

  # Installing the tool from nuget.org
  # !! Any version before 5.8.0-1.26262.10 will not support razor/blazor !!
  dotnet tool install -g roslyn-language-server --prerelease
    You can invoke the tool using the following command: roslyn-language-server
    Tool 'roslyn-language-server' (version '5.8.0-1.26262.10') was successfully installed.

  # Updating works the same way as installing ( by replacing "install" with "update")
  dotnet tool update -g roslyn-language-server --prerelease --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
  ```
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

To pass custom Roslyn extensions, override the server command and include one
`--extension=/path/to/extension.dll` argument per extension.

```lua
vim.lsp.config("roslyn", {
    cmd = {
        "roslyn-language-server",
        "--stdio",
        "--extension=/path/to/Roslynator.dll",
    },
})
```

Some tips and tricks that may be useful, but not in the scope of this plugin,
are documented in the [wiki](https://github.com/seblyng/roslyn.nvim/wiki).

> [!NOTE]  
> These settings are not guaranteed to be up-to-date and new ones can appear in the future. Aditionally, not all settings are shown here, but only the most relevant ones for Neovim. For a full list, visit [this](https://github.com/dotnet/vscode-csharp/blob/main/test/lsptoolshost/unitTests/configurationMiddleware.test.ts) unit test from the vscode extension and look especially for the ones which **don't** have `vsCodeConfiguration: null`.

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

- `:Roslyn target` chooses a solution if there are multiple to chose from

## 🚀 Other usage

- If you have multiple solutions, this plugin tries to guess which one to use. You can change the target with the `:Roslyn target` command.
- The current solution is always stored in `vim.g.roslyn_nvim_selected_solution`. You can use this, for example, to display the current solution in your statusline.

[nuget.org]: https://www.nuget.org/packages/roslyn-language-server
[nvim-lspconfig]: https://github.com/neovim/nvim-lspconfig
[Azure Devops feed]: https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl/NuGet/roslyn-language-server.linux-x64
