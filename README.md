# roslyn.nvim

This is an actively maintained & upgraded [fork](https://github.com/jmederosalvarado/roslyn.nvim) that interacts with the improved & open-source C# [Roslyn](https://github.com/dotnet/roslyn) language server, meant to replace the old and discontinued OmniSharp. This language server is currently used in the [Visual Studio Code C# Extension](https://github.com/dotnet/vscode-csharp), which is shipped with the standard C# Dev Kit.

This standalone plugin was necessary because Roslyn uses a [non-standard](https://github.com/dotnet/roslyn/issues/72871) method of initializing communication with the client and requires additional custom integrations, unlike typical LSP setups in Neovim.

## ⚡️ Requirements

- Neovim >= 0.10.0
- Roslyn language server downloaded locally
- .NET SDK installed and `dotnet` command available

## Demo

https://github.com/user-attachments/assets/a749f6c7-fc87-440c-912d-666d86453bc5

## 📦 Installation

<details>
  <summary>Mason</summary>
  
  `roslyn` is not in the mason core registry, so a custom registry is used. This is automatically setup if you have mason installed.
  This registry provides two binaries
  - `roslyn` (To be used with this repo)
  - `rzls` (To be used with [rzls.nvim](https://github.com/tris203/rzls.nvim))

**IMPORTANT**

If you are setting up mason with custom registries, make sure that you are either setting it up before `roslyn.nvim` is setup, or also include `github:Crashdummyy/mason-registry` in your `registries` config

**NOTE**

There's currently an open [pull request](https://github.com/mason-org/mason-registry/pull/6330) to add the Roslyn server to [mason](https://github.com/williamboman/mason.nvim), which would greatly improve the experience. If you are interested in this, please react to the original comment, but don't spam the thread with unnecessary comments.

</details>

<details>
  <summary>Manually</summary>
  
  1. Navigate to [this feed](https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl), search for `Microsoft.CodeAnalysis.LanguageServer` and download the version matching your OS and architecture.
     > For nix users, install [roslyn-ls](https://search.nixos.org/packages?channel=unstable&show=roslyn-ls) and then you can config this plugin right away.
  2. Unzip the downloaded `.nupkg` and copy the contents of `<zip root>/content/LanguageServer/<yourArch>` inside:
     - **Linux**: `~/.local/share/nvim/roslyn`
     - **Windows**: `%LOCALAPPDATA%\nvim-data\roslyn`
       > **_TIP:_** You can also specify a custom path to the roslyn folder in the setup function.
  3. Check if it's working by running `dotnet Microsoft.CodeAnalysis.LanguageServer.dll --version` in the `roslyn` directory.

</details>

> [!TIP]  
> For server compatibility check the [roslyn repo](https://github.com/dotnet/roslyn/blob/main/docs/wiki/NuGet-packages.md#versioning)

**Install the plugin with your preferred package manager:**

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "seblj/roslyn.nvim",
    ft = "cs",
    opts = {
        -- your configuration comes here; leave empty for default settings
    }
}
```

## ⚙️ Configuration

The plugin comes with the following defaults:

```lua
{
    config = {
        -- Here you can pass in any options that that you would like to pass to `vim.lsp.start`.
        -- Use `:h vim.lsp.ClientConfig` to see all possible options.
        -- The only options that are overwritten and won't have any effect by setting here:
        --     - `name`
        --     - `cmd`
        --     - `root_dir`
    },

    --[[
    -- if you installed `roslyn-ls` by nix, use the following:
      exe = 'Microsoft.CodeAnalysis.LanguageServer',
    ]]
    exe = {
        "dotnet",
        vim.fs.joinpath(vim.fn.stdpath("data"), "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll"),
    },
    args = {
        "--logLevel=Information", "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path())
    },
  --[[
  -- args can be used to pass additional flags to the language server
    ]]

    -- NOTE: Set `filewatching` to false if you experience performance problems.
    -- Defaults to true, since turning it off is a hack.
    -- If you notice that the server is _super_ slow, it is probably because of file watching
    -- Neovim becomes super unresponsive on some large codebases, because it schedules the file watching on the event loop.
    -- This issue goes away by disabling this capability, but roslyn will fallback to its own file watching,
    -- which can make the server super slow to initialize.
    -- Setting this option to false will indicate to the server that neovim will do the file watching.
    -- However, in `hacks.lua` I will also just don't start off any watchers, which seems to make the server
    -- a lot faster to initialize.
    filewatching = true,

    -- Optional function that takes an array of solutions as the only argument. Return the solution you
    -- want to use. If it returns `nil`, then it falls back to guessing the solution like normal
    -- Example:
    --
    -- choose_sln = function(sln)
    --     return vim.iter(sln):find(function(item)
    --         if string.match(item, "Foo.sln") then
    --             return item
    --         end
    --     end)
    -- end
    choose_sln = nil,

    -- Optional function that takes the selected solution as the only argument.
    -- Returns a boolean of whether it should be ignored to attach to or not
    --
    -- I am for example using this to disable a solution with a lot of .NET Framework code on mac
    -- Example:
    --
    -- ignore_sln = function(sln)
    --     return string.match(sln, "Foo.sln") ~= nil
    -- end
    ignore_sln = nil,
})
```

To configure language server specific settings sent to the server, you can modify the `config.settings` map.

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

Example:

```lua
opts = {
    config = {
        settings = {
            ["csharp|inlay_hints"] = {
                csharp_enable_inlay_hints_for_implicit_object_creation = true,
                csharp_enable_inlay_hints_for_implicit_variable_types = true,
                csharp_enable_inlay_hints_for_lambda_parameter_types = true,
                csharp_enable_inlay_hints_for_types = true,
                dotnet_enable_inlay_hints_for_indexer_parameters = true,
                dotnet_enable_inlay_hints_for_literal_parameters = true,
                dotnet_enable_inlay_hints_for_object_creation_parameters = true,
                dotnet_enable_inlay_hints_for_other_parameters = true,
                dotnet_enable_inlay_hints_for_parameters = true,
                dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
                dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
                dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
            },
            ["csharp|code_lens"] = {
                dotnet_enable_references_code_lens = true,
            },
        },
    },
}
```

## 📚 Commands

- `:Roslyn restart` restarts the server
- `:Roslyn stop` stops the server
- `:Roslyn target` chooses a solution if there are multiple to chose from

## 🚀 Other usage

- If you have multiple solutions, this plugin tries to guess which one to use. You can change the target with the `:Roslyn target` command.
- The current solution is always stored in `vim.g.roslyn_nvim_selected_solution`. You can use this, for example, to display the current solution in your statusline.
