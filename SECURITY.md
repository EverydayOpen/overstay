# Security

Please report vulnerabilities privately: this repository's **Security** tab › **Report a vulnerability**. Don't open a public issue.

- **Supported version:** the latest release, the one the website's download page links to.
- **Response:** an acknowledgement within 7 days, and a fix or a plan within 30 days after that.
- **In scope:** the Overstay app, the website, and this repository's GitHub Actions workflows.
- **Especially welcome:** any way to make Overstay signal a process it should not, such as a pid that was reused between
  the scan and the stop, a process of another user, one of Overstay's own ancestors, or an item on the protected list;
  any way to make it write, move or delete a file; and any path by which a command-line argument, an environment value
  or a secret could reach the activity log, the clipboard, a share card or the diagnostics text.
- **Not a vulnerability:** a detection rule that lists something you still need (a false positive). Use the "Report a
  false positive" issue form for that, and never paste secrets into it.

Overstay makes no network connections and asks for no permission, so a report about it "phoning home" or needing
elevated rights would itself be a bug worth reporting.
