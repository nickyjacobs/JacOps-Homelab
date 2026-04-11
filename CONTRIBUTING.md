# Contributing

Thanks for stopping by. This repository is primarily a personal homelab runbook and portfolio, not an open source project with feature requests. That said, corrections, suggestions and questions are welcome.

## What this repository is

- A living documentation of how I designed and built my homelab
- A portfolio piece that shows my approach to network security, segmentation and remote access
- A runbook I can use to rebuild or extend the setup

## What this repository is not

- A product or a service
- A supported tool that I will patch on demand
- A place to request new features unrelated to my own homelab

## Ways to contribute

**Corrections and improvements to the documentation.** If you spot a typo, an inaccurate claim, a broken link, or an explanation that could be clearer, open an issue or a pull request. Small targeted PRs are easier to review than large rewrites.

**Questions about the setup.** If something is unclear and you think the documentation could explain it better, open an issue with the question. I will try to answer and update the docs in one go.

**Security reports.** If you find a real security issue in anything documented here (a misconfiguration, a leaked value that should have been redacted, a pattern that could compromise the setup), please follow the instructions in [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Opening a pull request

Keep changes focused. One logical change per PR makes review easier. If you want to fix three unrelated typos in three different files, three small PRs are better than one large one.

For documentation changes, both the English file and the Dutch translation (`.nl.md`) should stay in sync. If you only speak one of the two languages and update one file, mention it in the PR and I will keep the other side consistent.

For workflow or configuration changes, explain the reasoning in the PR description. "Why" matters more than "what" when reviewing infrastructure code.

## Style

The writing style across the repository is direct and concrete. Claims are backed by reasoning or data, not marketing language. If a decision involved a trade-off, the trade-off is documented. If something was hard to debug, the lesson is written down.

For Dutch text, avoid stock AI phrasing (`cruciaal`, `naadloos`, `baanbrekend`, `holistische aanpak`, and similar) and stay close to how someone would actually explain the topic out loud.

## Code of conduct

Be polite. Disagreements are fine when the argument is about the content. Personal attacks or harassment are not.

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
