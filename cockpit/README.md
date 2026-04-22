![Cockpit Banner](assets/banner.png)

## Cockpit installer behavior

`cockpit/bin/cockpit.sh` is AXIOM stage 1 provisioning.

- It emits explicit log lines before sudo, package-manager, and network-heavy operations.
- Long-running actions are intentionally visible so operator state is clear.
- Failures in apt/pkg/gh/node setup are surfaced as hard errors.

`cockpit/bin/blux10k.sh` is AXIOM stage 2 gating.

- It verifies blux10k readiness and version requirements.
- It only runs installers when `--noninteractive` support is explicitly detectable.
- If noninteractive safety cannot be guaranteed, it intentionally stops stage 2, prints exact manual commands, and does not claim stage success.
