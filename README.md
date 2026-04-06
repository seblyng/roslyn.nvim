# roslyn.nvim

This is an actively maintained & upgraded [fork][original_roslyn_nvim] that interacts with the improved & open-source C#
[Roslyn][roslyn] language server, meant to replace the old and discontinued OmniSharp. This language server is currently
used in the [Visual Studio Code C# Extension][vscode_csharp], which is shipped with the standard C# Dev Kit.

## Razor/CSHTML Support

This plugin has recently added support for Razor/CSHTML files. This enabled razor support using co-hosting and
supersedes the old [rzls.nvim][rzls_nvim].

If you previously used `rzls.nvim`, please uninstall it and the `rzls` language server.

## ⚡️ Requirements

- Neovim >= 0.11.0
- Roslyn language server downloaded locally
- .NET SDK installed and `dotnet` command available

## Difference to nvim-lspconfig

`roslyn` is now a part of [nvim-lspconfig][nvim_lsp_config], but it does not implement all things that are implemented
here. This plugin tries to keep things minimal but still implement some things that are not suited for
[nvim-lspconfig][nvim_lsp_config]. A couple of additional things this plugin implements:

- Support for multiple solutions
- Broad root\_dir detection support. Meaning it will search for solutions upward in parent directories if `broad_search` option is set
- Support for source generated files
- Support for `Fix all`, `Nested code actions` and `Complex edit`
- `Roslyn target` command to switch between multiple solutions

## Demo

https://github.com/user-attachments/assets/a749f6c7-fc87-440c-912d-666d86453bc5

## 📦 Installation

<details>
  <summary>Mason</summary>
  
  `roslyn` is not in the mason core registry, so a custom registry is used.
  This registry provides two binaries
  - `roslyn` (To be used with this repo)
    - This has the `.razorExtensions` folder included for Razor/CSHTML support

You need to set up the custom registry like this

```lua
require("mason").setup({
    registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
    },
})
```

You can then install it with `:MasonInstall roslyn` or through the popup menu by running `:Mason`. It is not available
through [mason-lspconfig.nvim][mason_lspconfig] and the `:LspInstall` interface. When installing the server through
mason, the cmd is automatically added to the LSP config, so no need to add it manually.

The stable version of `roslyn` is provided through `roslyn` in the mason registry. This is the same version as in
vscode. If you want the bleeding edge features, you can choose `roslyn-unstable`. Be aware of breaking changes if you
choose this version.

**NOTE**

There's currently an open [pull request][mason_pr] to add the Roslyn server to [mason][mason_nvim], which would greatly
improve the experience. If you are interested in this, please react to the original comment, but don't spam the thread
with unnecessary comments.

</details>

<details>
  <summary>Manually</summary>

NOTE: The manual installation instructions are the same for this plugin and for nvim-lspconfig.
The following instructions are copied from [nvim-lspconfig][roslyn_ls_installation_instructions].
If the installation instructions are not up-to-date or not clear, please first send a PR to `nvim-lspconfig` with
improvements so that we can align the installation instructions.

To install the server, compile from source or download as nuget package.
Go to `https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl/NuGet/Microsoft.CodeAnalysis.LanguageServer.<platform>/overview`
replace `<platform>` with one of the following `linux-x64`, `osx-x64`, `win-x64`, `neutral` (for more info on the
download location see https://github.com/dotnet/roslyn/issues/71474#issuecomment-2177303207).
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

For the full list of `Microsoft.CodeAnalysis.LanguageServer.dll` CLI options you
can just run it without any options `dotnet <my_folder>/Microsoft.CodeAnalysis.LanguageServer.dll`
(or you can check the [official repository][roslyn_ls_cli_options]).
The following options are most likely available for your Roslyn LS version:

```
Option '--logLevel' is required.
Option '--extensionLogDirectory' is required.

Description:

Usage:
  Microsoft.CodeAnalysis.LanguageServer [options]

Options:
  --logLevel <Critical|Debug|Error|Information|None|Trace|Warning> (REQUIRED)  The minimum log verbosity.
  --extensionLogDirectory <extensionLogDirectory> (REQUIRED)                   The directory where we should write log files to
  --stdio                                                                      Use stdio for communication with the client.
  -?, -h, --help                                                               Show help and usage information
  --version                                                                    Show version information
```

</details>

> [!TIP]  
> For server compatibility check the [roslyn repo][roslyn_versioning]

**Install the plugin with your preferred package manager:**

### [lazy.nvim][lazy_nvim]

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

    -- If the plugin should silence notifications about initialization
    silent = false,
}
```

To configure language server specific settings sent to the server, you can use the `vim.lsp.config` interface with
`roslyn` as the name of the server.

## Example

The settings in the example below are verbose. You are expected to only copy the ones that you need.
Omitting any of these settings has no effect on the Roslyn LS (it will use the default).
Using a setting that is not available for your Roslyn LS version also has no effect.

> [!NOTE]
> These settings are not guaranteed to be up-to-date and new ones can appear in the future. Additionally, not all
> settings are shown here. For an up-to-date full list, check the official Roslyn repository at this file:
> [DidChangeConfigurationNotificationHandlerTest.cs][roslyn_ls_settings].
>
> You can also get these settings from [VSCode's Roslyn LS][vscode_roslyn_ls_settings].

```lua
vim.lsp.config("roslyn", {
    on_attach = function()
        print("This will run when the server attaches!")
    end,

    -- These settings are fetched from the official Roslyn LS repository at:
    -- roslyn/src/LanguageServer/ProtocolUnitTests/Configuration/DidChangeConfigurationNotificationHandlerTest.cs
    -- The expected values for these settings can be figured out by searching the Roslyn repository for their names.
    settings = {

      -- These settings control the scope of background diagnostics.
      ['csharp|background_analysis'] = {

        -- Option to configure background analysis scope for the current user.
        -- Note: setting this to "fullSolution" may result in significant -- performance degradation, see:
        -- https://github.com/dotnet/vscode-csharp/issues/8145#issuecomment-2784568100
        ---@type "openFiles" | "fullSolution" | "none"
        dotnet_analyzer_diagnostics_scope = 'openFiles',

        -- Option to configure compiler diagnostics scope for the current user.
        -- Note: setting this to "fullSolution" may result in significant performance degradation, see:
        -- https://github.com/dotnet/vscode-csharp/issues/8145#issuecomment-2784568100
        ---@type "openFiles" | "fullSolution" | "none"
        dotnet_compiler_diagnostics_scope = 'openFiles',
      },

      -- These settings control what inlay hints should be displayed.
      -- These won't have any effect if you don't enable inlay hints in your config.
      -- Check `:h vim.lsp.inlay_hint.enable()`.
      ['csharp|inlay_hints'] = {

        -- Whether to display inline parameter name hints.  
        ---@type boolean
        dotnet_enable_inlay_hints_for_parameters = true,

        -- Whether to show hints for literals.  
        ---@type boolean
        dotnet_enable_inlay_hints_for_literal_parameters = true,

        -- Whether to show hints for indexers.  
        ---@type boolean
        dotnet_enable_inlay_hints_for_indexer_parameters = true,

        -- Whethet to show hints for 'new' expressions.  
        ---@type boolean
        dotnet_enable_inlay_hints_for_object_creation_parameters = true,

        -- Whethet to show hints for everything else.  
        ---@type boolean
        dotnet_enable_inlay_hints_for_other_parameters = true,

        -- Whether to suppress hints when parameter names differ only by suffix.  
        ---@type boolean
        dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,

        -- Whether to suppress hints when parameter name matches the method's intent.  
        ---@type boolean
        dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,

        -- Whether to suppress hints when argument matches parameter name.  
        ---@type boolean
        dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,

        -- Whether to display inline type hints.  
        ---@type boolean
        csharp_enable_inlay_hints_for_types = true,

        -- Whether to show hints for variables with inferred types.  
        ---@type boolean
        csharp_enable_inlay_hints_for_implicit_variable_types = true,

        -- Whether to show hints for lambda parameter types.  
        ---@type boolean
        csharp_enable_inlay_hints_for_lambda_parameter_types = true,

        -- Whether to show hints for implicit object creation.  
        ---@type boolean
        csharp_enable_inlay_hints_for_implicit_object_creation = true,

        ---@type boolean
        csharp_enable_inlay_hints_for_collection_expressions = true,
      },

      -- These settings control how the language server should search for symbols.
      ['csharp|symbol_search'] = {

        -- Whether to search symbols in reference assemblies.  
        ---@type boolean
        dotnet_search_reference_assemblies = true,
      },

      -- These settings control how the completions behave.
      ['csharp|completion'] = {

        -- Whethet to perform automatic object name completion for the members
        -- that you have recently selected.  
        ---@type boolean
        dotnet_show_name_completion_suggestions = true,

        -- Whether to show regular expressions in completion list.  
        ---@type boolean
        dotnet_provide_regex_completions = true,

        -- Whether to show completion items from namespaces that are not imported.
        -- For example, if this is set to false, and you don't have the namespace
        -- `System.Net.Sockets` imported, then when you type "Sock" you will not
        -- get completion for `Socket` or other items in that namespace.
        ---@type boolean
        dotnet_show_completion_items_from_unimported_namespaces = true,

        ---@type boolean
        dotnet_trigger_completion_in_argument_lists = true,
      },

      -- These settings control the LSP code lens.
      -- Note: You must refresh the code lens yourself.
      -- Check `:h vim.lsp.codelens.refresh()` and the example autocmd.
      ['csharp|code_lens'] = {

        -- Whether to enable code lens references.  
        ---@type boolean
        dotnet_enable_references_code_lens = true,

        -- Whether to enable tests code lens.  
        ---@type boolean
        dotnet_enable_tests_code_lens = true,
      },
      
      ['csharp|projects'] = {

        -- A folder to log binlogs to when running design-time builds.
        ---@type string?
        dotnet_binary_log_path = nil,

        -- Whether or not automatic nuget restore is enabled.
        ---@type boolean
        dotnet_enable_automatic_restore = true,

        -- Whether to use the new 'dotnet run app.cs' (file-based programs)
        -- experience.
        ---@type boolean
        dotnet_enable_file_based_programs = true,

        -- Whether to use the new 'dotnet run app.cs' (file-based programs)
        -- experience in files where the editor is unable to determine with
        -- certainty whether the file is a file-based program.
        ---@type boolean
        dotnet_enable_file_based_programs_when_ambiguous = true,
      },

      ['csharp|navigation'] = {

        ---@type boolean
        dotnet_navigate_to_decompiled_sources = true,

        ---@type boolean
        dotnet_navigate_to_source_link_and_embedded_sources = true,
      },

      ['csharp|highlighting'] = {

        ---@type boolean
        dotnet_highlight_related_json_components = true,

        ---@type boolean
        dotnet_highlight_related_regex_components = true,
      },

      ['csharp|formatting'] = {

        -- Whether to sort using directives on format alphabetically.  
        ---@type boolean
        dotnet_organize_imports_on_format = true,
      },
    },
})
```

Some tips and tricks that may be useful, but not in the scope of this plugin,
are documented in the [wiki][wiki].

## 📚 Commands

- `:Roslyn restart` restarts the server
- `:Roslyn start` starts the server
- `:Roslyn stop` stops the server
- `:Roslyn target` chooses a solution if there are multiple to chose from

## 🚀 Other usage

- If you have multiple solutions, this plugin tries to guess which one to use. You can change the target with the
`:Roslyn target` command.
- The current solution is always stored in `vim.g.roslyn_nvim_selected_solution`. You can use this, for example, to
display the current solution in your statusline.

[rzls_nvim]: https://github.com/tris203/rzls.nvim
[nvim_lsp_config]: https://github.com/neovim/nvim-lspconfig
[mason_pr]: https://github.com/mason-org/mason-registry/pull/6330
[mason_nvim]: https://github.com/williamboman/mason.nvim
[original_roslyn_nvim]: https://github.com/jmederosalvarado/roslyn.nvim
[vscode_csharp]: https://github.com/dotnet/vscode-csharp
[roslyn]: https://github.com/dotnet/roslyn 
[roslyn_versioning]: https://github.com/dotnet/roslyn/blob/main/docs/wiki/NuGet-packages.md#versioning
[lazy_nvim]: https://github.com/folke/lazy.nvim
[mason_lspconfig]: https://github.com/williamboman/mason-lspconfig.nvim
[roslyn_ls_installation_instructions]: https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#roslyn_ls
[roslyn_ls_cli_options]: https://github.com/dotnet/roslyn/blob/main/src/LanguageServer/Microsoft.CodeAnalysis.LanguageServer/Program.cs#L187-L284 
[roslyn_ls_settings]: https://github.com/dotnet/roslyn/blob/main/src/LanguageServer/ProtocolUnitTests/Configuration/DidChangeConfigurationNotificationHandlerTest.cs#L114-L153
[vscode_roslyn_ls_settings]: https://github.com/dotnet/vscode-csharp/blob/main/test/lsptoolshost/unitTests/configurationMiddleware.test.ts#L12-L275
[wiki]: https://github.com/seblyng/roslyn.nvim/wiki
