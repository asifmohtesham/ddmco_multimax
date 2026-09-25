# Worktree & Smoke Test Workflow

When developing features, deploying, or testing implementations in a side-by-side worktree for the `ddmco_multimax` project:

1. **Base Branch**: Always use the `release/play-store` branch as the base branch for ANY implementation or worktree smoke test.
2. **Smoke Test Instructions**: Always provide precise steps to the user to perform the smoke test after deploying a debug build. These steps must include:
   - How to identify and launch the specific test app (e.g., verifying the app label or launcher icon).
   - Verifying the app successfully boots past the splash screen.
   - Detailing the exact user interactions needed to verify the feature being tested.
   - Describing the expected behavior or outcome of those interactions.
