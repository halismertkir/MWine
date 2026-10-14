# Security and repository data

Report a suspected vulnerability privately to **contact@halismertkir.com**.
Do not include active API keys, account passwords or access tokens in an issue.
Use redacted examples and describe the affected version and reproduction steps.

MWine does not need a user-supplied API key. Mac Steam handles the user's Steam
login. Runtime and Valve payloads are fetched from their upstream sources,
with pinned hashes checked by the installers.

Downloaded runtimes, Steam client/account files, games, prefixes, save backups,
private diagnostic logs and captures are excluded from version control. Only
source, documentation, public configuration, synthetic fixtures and reviewed
README graphics are intended for publication. The UI screenshot contains the
MWine window with demonstration library entries; no account or desktop capture
is included.

The repository is public and is not anonymous: its GitHub owner, commit author
names and the deliberately public contact address can be visible. Older commits
use a GitHub noreply email; new commits use the published contact address.
Example user names in historical synthetic fixtures are not account exports.

Maintainers should run `./scripts/check-secrets` before publishing. The checker
uses Gitleaks on all reachable Git history and the staged source snapshot, with
redacted output. It does not upload repository content to a scanning service.
A passing scan reports no detected secret patterns; it cannot prove the absence
of every possible credential format.
