# roslyn.nvim

This is an lsp client that interacts with the improved & open-source C# [Roslyn](https://github.com/dotnet/roslyn) language server, used by Visual studio code.
## ⚡️ Requirements

- Neovim >= 0.10.0
- Roslyn language server downloaded locally
- .NET SDK installed and `dotnet` command available

## 📦 Installation

**Install the Roslyn language server:**

1. Navigate to [this feed](https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl), search for `Microsoft.CodeAnalysis.LanguageServer` and download the version matching your OS and architecture.
2. Unzip the downloaded `.nupkg` and copy the contents of `<zip root>/content/LanguageServer/<yourArch>` inside:
    - **Linux**: `~/.local/share/nvim/roslyn`
    - **Windows**: `%LOCALAPPDATA%\nvim-data\roslyn`
   > **_TIP:_** You can also specify a custom path to the roslyn folder in the setup function.
3. Check if it's working by running `dotnet Microsoft.CodeAnalysis.LanguageServer.dll --version` in the `roslyn` directory.

> [!NOTE]  
> There's currently an open [pull request](https://github.com/mason-org/mason-registry/pull/6330) to add the Roslyn server to [mason](https://github.com/williamboman/mason.nvim).

##Focus of this plugin:
The goal of this plugin is use the power of Roslyin lsp in neovim, for do this it's gonna integrate different event, line: wordspace/didChangeWatchedFiles ,ecc
The features are now avalaible beyond the classic lsp feature(go to definition,action,reference,rename ecc) are:
    -it has an api to AUTO update the csproj when create a file() `	require("roslyn.csprojManager").add_element(<path to update>)`,(it calls the did_change_watched_file)
    -it has a api to launch the event did_change_watched_file, `function M.did_change_watched_file(uriFile,client,type)`, to informa the server that something has been changed
The features that i wanna insert:
    -api to remove the file from csproj
    -integration with  nvim-tree.lua
    
**Install the plugin with your preferred package manager:**
```lua
{
    "Wordluc/roslyn_ls.nvim",
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

    exe = {
        "dotnet",
        vim.fs.joinpath(vim.fn.stdpath("data"), "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll"),
    },

    -- NOTE: Set `filewatching` to false if you experience performance problems.
    -- filewatching=true -> the server will wach the file, this could bring performance problem
    -- filewatching=false -> the client will wach the file
    filewatching = true,

    --this takes a function, with list of string(different .sln) and return a string(the actual sln that will be loaded in lsp)
    --function(slns string []) string

    choose_sln = nil,
})
```
To configure language server specific settings sent to the server, you can modify the `config.settings` map. 

###Optional Settings

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
                dotnet_enable_inlay_hints_for_parameters = true,
            },
            ["csharp|code_lens"] = {
                dotnet_enable_references_code_lens = true,
            },
        }
    }
}
```

## 🚀 Other usage

  - If you have multiple solutions, this plugin tries to guess which one to use. You can change the target with the `:CSTarget` command.
  - The current solution is always stored in `vim.g.roslyn_nvim_selected_solution`. You can use this, for example, to display the current solution in your statusline.
