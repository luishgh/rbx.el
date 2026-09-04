# rbx VS Code Extension - Features

A comprehensive list of all features present in the rbx VS Code extension for creating and managing competitive programming problems.

## Installation

- Sideloaded `.vsix` that matches your rbx CLI version
- Works with Cursor, Windsurf, and VSCodium
- Remote installation support (SSH, devcontainers)
- Updates via `rbx vscode install` command

## The Run View

- Live solution, group, and testcase tracking as `rbx run` executes
- Three separate status indicators per solution:
  - Name display (colored according to declaration)
  - Chip showing actual run verdict with icons
  - Gutter indicator (tick for pass, red triangle for miss, yellow for warnings)
- Summary statistics per solution and group:
  - Verdict display
  - Points earned
  - Max time and memory across testcases
  - Running progress indicator (e.g., "12/40")
- Contest support with problem dropdown
  - Problems named by contest letter and color
  - Auto-follows running problem with `rbx contest each run`
- Contest variant support
  - One block per variant with variant ID heading
  - Separate divisions displayed distinctly

## Opening Testcases

- Dual editor panes for input and output
- Diff view comparing actual vs. expected output
- Testcase information card showing:
  - Checker's own message (wrapped and complete)
  - Test origin (generator call, script, or copied testcase)
  - Links to source files
- Output view channel selector:
  - Output vs. expected answer comparison
  - Standard error (stderr) display
  - Run log for the testcase
- Sticky channel selection when navigating
- Persistent pane layout (drag-to-reorder, persistent positioning)

## Compilation Findings

- Dedicated **Compilation Findings** panel
- One row per solution with compilation status
- Color-coded indicators:
  - Red badge for failed compilations
  - Yellow badge for warnings
- Expandable rows showing:
  - Individual warnings with line numbers
  - Warning flags (e.g., `-Wshadow`)
  - Clickable links to source locations
- Full compiler output display for failed compiles

## Browsing the Testset

- **Tests view** listing:
  - Test groups
  - Individual testcases
  - Origin of each test
- Testcase selection opens:
  - Input file display
  - Expected answer display
  - Validator information
  - Generator information

### Constraint Coverage

- Visualization of validator bounds
- Shows which bounds the testset hits
- Identifies which bounds no test touches

### Testset Statistics

- Size and count information
- Group-by-group breakdown
- Visual representation in sidebar panel

## Visualizations

- Visualization gallery for packages with visualizers
- Multiple picture types per testcase:
  - Input visualization
  - Answer visualization (from expected answer)
  - Gallery view of entire group
- Image rendering in editor tabs
- Interactive HTML visualizations in VS Code's browser
- Constraint coverage visualization

## Variables in Statements

- Inline expansion of `\VAR{...}` references in `.tex` statement files
- Real-time variable value display via inlay hints
- Filter support for variable expressions:
  - `sci` (scientific notation)
  - `rsci` (reverse scientific notation)
  - Jinja2 builtins (`upper`, `round(2)`, etc.)
- Test group variable references:
  - Named group variable access
  - Resolved variable sets with group overrides
  - Shorthand and bracket notation support
- Plain text rendering of mathematical expressions:
  - Superscript digits
  - `×` for multiplication
- Smart hint placement:
  - Only for explicitly named groups
  - No hints for dynamic loops or undefined variables
  - No hints for problem/contest scoped variables
  - No hints for half-typed pipelines or typos

## Finding rbx

- Automatic `rbx` binary detection via `PATH`
- Login shell fallback for hidden paths
- Manual executable configuration via `rbx.executable` setting
- Per-folder setting support for multi-version workspaces
- Graceful degradation (views work without `rbx` binary for file reading)

## Settings

Configurable settings with defaults:

| Setting | Default | Purpose |
|---------|---------|---------|
| `rbx.compilationDiagnostics` | `true` | Report compiler warnings and failures in Problems panel |
| `rbx.statementVarHints` | `true` | Show variable expansion next to `\VAR{...}` references |
| `rbx.executable` | *(empty)* | Manual path to `rbx` binary when auto-detection fails |
| `rbx.solutionLabel` | `trimmed` | Solution path display mode: `full`, `trimmed`, or `basename` |
| `rbx.testcaseLayout` | `below` | Initial placement of second testcase pane: `below` or `beside` |

## General Features

- No automatic building or running (execution stays in terminal)
- Reads files from the same package as CLI
- Integration with VS Code's built-in diff tool
- Integration with VS Code's Problems panel
- Inlay hints using VS Code's native hint system
- Workspace support for multiple packages/versions
- Responsive to `rbx run` and `rbx build` outputs
- Support for both single problems and contests
