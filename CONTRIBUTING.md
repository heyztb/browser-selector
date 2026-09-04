# Contributing

Contributions that keep Browser Selector focused, native, offline, and dependency-free are welcome.

Before opening a pull request, run:

```sh
swift test
./scripts/build-app.sh release native
./scripts/verify-app.sh
```

Changes to discovery or launching should include unit tests with injected filesystem, workspace, or process boundaries. Do not add network access, analytics, or URL retention.
