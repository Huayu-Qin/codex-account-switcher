## 中文

- 修复重新登录另一个 Codex 账号后仍沿用旧账号标记的问题。macOS 和 Windows 现在以本机当前登录凭证为准，自动选中对应账号并同步其凭证快照，无需手动登记。
- 新的本机登录账号会自动保存，退出登录后清除当前账号标记。同邮箱的不同工作区保持独立；无法读取的凭证会显示错误。
- macOS 的账号确认提示和“管理账号”按钮现在显示在同一行。

## English

- Fix stale active-account selection after signing in to a different Codex account. Both macOS and Windows now follow the current local credentials, select the matching account, and sync its saved credentials without manual registration.
- Newly discovered local accounts are saved automatically, and signing out clears the active selection. Workspaces sharing an email remain separate; unreadable credentials produce a visible error.
- Keep the macOS account-confirmation warning and Manage Accounts button on one line.
