# rbx for Emacs

`rbx` for Emacs brings the run and testset inspection workflow of the official
[`rbx` VS Code extension](https://rbx.rsalesc.dev/tools/vscode/) into Emacs 30.

The package is terminal-first: run `rbx build` or `rbx run` yourself, then use
Emacs to inspect the artifacts.  It never invokes `rbx` on your behalf.

This package is under active initial development.  Installation and usage
instructions will be added with the first working release.

## Development

The package requires Emacs 30.1 or newer plus `transient`, `magit-section`, and
`yaml`.  Run the complete local check suite with:

```sh
make check
```

See [AGENTS.md](AGENTS.md) for architecture and contribution conventions.

