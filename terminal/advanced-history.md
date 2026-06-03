Atuin (Indestructible Shell History)

You are inevitably going to craft massive AWS CLI filters or complex awk and sed one-liners. When you need them three weeks later, pressing Ctrl+R to blindly reverse-search your history is painful.

Atuin replaces your default shell history with an intelligent, searchable SQLite database. When you press Ctrl+R, it opens a full-screen fzf-style fuzzy search menu of every command you have ever typed, complete with execution time and the directory you ran it in.

```bash
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
```
