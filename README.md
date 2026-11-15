# HERNESS

HERNESS is a minimal agent harness with just the essentials. Its small footprint makes it easy to extend with the features you want when building your own harness.

It is also interface-agnostic, so you can easily add a terminal UI (TUI) or graphical UI (GUI).

## BUILT-IN TOOLS

| Name | Description |
| --- | --- |
| `read` | Reads a file and returns its contents (up to 1 MiB). |
| `create` | Creates a new file with the specified content. Fails if the file already exists. |
| `write` | Replaces the entire contents of an existing file. Fails if the file does not exist. |
| `ask` | Asks the user a question and returns the answer. |
| `list` | Lists the entries of a directory, including hidden ones. |
| `diff` | Compares two files and returns a unified diff. |
