# Worker: <任务标题>

Repository: <repo-root>
Base commit: <sha>. Do not commit.

## Write scope (ONLY these files)

- <file 1>
- <file 2>
- <new test/file>

Do NOT edit: <shared hot files, Cargo.toml, docs, Electron, other crates, etc.>
If a shared change is truly required, report it instead of editing.

## Read first

- <file>
- <file>
- <existing tests>

## Goal

<一句话说明交付什么，为什么需要。>

## Requirements

1. <明确行为>
2. <边界/错误处理>
3. <兼容性/权限/取消>
4. <不要扩大 scope>

## Tests

- <test case 1>
- <test case 2>
- <failure/edge case>

## Acceptance

```bash
<targeted test>
<full crate/package test>
<clippy/fmt/typecheck/build>
```

Do not commit. Report:

- changed files
- public API / behavior changes
- test counts/results
- remaining gaps or shared-file needs
