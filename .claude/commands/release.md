Bump the plugin version, commit, and push.

1. Read `.claude-plugin/plugin.json` and extract the current version
2. Increment the minor version by 1 (e.g. 1.9.0 → 1.10.0). If the user provided an argument (e.g. `/release 2.0.0`), use that version instead.
3. Update the `version` field in `.claude-plugin/plugin.json`
4. Commit: `chore: bump plugin version to <new-version>`
5. Push to origin
6. Report the new version to the user
