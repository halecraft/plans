import { defineConfig, parsers } from "@halecraft/verify"

/**
 * This package is bash behind a Node shim, so the usual `types` task has nothing to check — the
 * implementation language has no compiler. `shell` stands in its place: shellcheck at `style`
 * severity is the only static analysis this code gets, and it is the closest thing to a type error
 * a shell script can be told about.
 *
 * The two `surface` checks guard claims that are otherwise pure convention, and that no test would
 * fail on. Both have already-known failure modes: a dispatch entry with no script is a crash on a
 * path the smoke test may not cover, and a runtime directory missing from `files` breaks only for
 * whoever installs the package — never for anyone running from a checkout.
 *
 * `logic` reports last because a broken script or a miswired CLI makes the smoke test fail as a
 * consequence, and a cascade of failures hides the one that matters.
 */
export default defineConfig({
  tasks: [
    {
      key: "format",
      run: "biome check .",
      fix: "biome check --write .",
      parser: parsers.biome,
    },
    {
      /**
       * `-x` follows the `. common.sh` in each entry script, so the shared helpers are analysed in
       * the context that actually uses them. Without it every sourced value reads as unused.
       */
      key: "shell",
      run: "shellcheck -x -S style libexec/*.sh test/*.sh",
      reportingDependsOn: [],
    },
    {
      key: "cli-surface",
      run: "node scripts/verify-cli-surface.mjs",
      reportingDependsOn: ["format"],
    },
    {
      key: "packaged-files",
      run: "node scripts/verify-packaged-files.mjs",
      reportingDependsOn: ["format"],
    },
    {
      key: "logic",
      run: "bash test/smoke.sh",
      reportingDependsOn: ["format", "shell", "cli-surface"],
    },
  ],
  env: {
    NO_COLOR: "1",
  },
})
