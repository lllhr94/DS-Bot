# Clio

A personal agent that lives on your iPhone. Companions (旅伴) talk to the model you bring a key for, use tools on the phone, and keep everything in the app's own files.

- `AgentKit/` — the engine: model providers, the agent loop, tools. Pure Swift, with tests.
- `App/` — the SwiftUI app. The Xcode project is generated from `App/project.yml` with XcodeGen.
- `docs/PLAN.md` — where the plan and the execution handbook live.

## Build

There is no local build setup. GitHub Actions (`.github/workflows/build.yml`) tests the engine, builds an unsigned IPA and publishes it to the `latest` release. Sign it on the phone.

## License

GPL-3.0. See `LICENSE`.
