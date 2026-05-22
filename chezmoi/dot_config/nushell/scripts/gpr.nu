# gpr: fetch + soft-reset to fork point from detected base (origin/HEAD → main → master)
export def gpr [
  base?: string,         # optional explicit base, e.g., origin/release/1.2
  --no-forkpoint (-n),   # disable --fork-point heuristic
  --preview (-p),        # show commits & diffstat that would be squashed
  --dry-run (-d)         # only preview; don't reset
] {
  # Ensure we're in a git repo (do NOT run this at load time)
  if ( ^git rev-parse --git-dir | complete ).exit_code != 0 {
    error make { msg: "Not inside a git repository." }
  }

  ^git fetch -p origin | ignore

  # Resolve base: origin/HEAD → origin/main → origin/master
  mut b = ($base | default "")
  if $b == "" {
    let head = ( ^git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | str trim )
    if $head != "" {
      $b = $head
    } else if ( ^git rev-parse -q --verify origin/main   2>/dev/null | complete ).exit_code == 0 {
      $b = "origin/main"
    } else if ( ^git rev-parse -q --verify origin/master 2>/dev/null | complete ).exit_code == 0 {
      $b = "origin/master"
    } else {
      error make { msg: "No base found (set origin/HEAD or ensure origin/main|origin/master exists)" }
    }
  }

  # Fork point (prefer --fork-point unless disabled)
  mut fork = ""
  if (not $no_forkpoint) {
    let fp = ( ^git merge-base --fork-point $b HEAD 2>/dev/null | str trim )
    if $fp != "" { $fork = $fp }
  }
  if $fork == "" { $fork = ( ^git merge-base $b HEAD | str trim ) }
  if $fork == "" { error make { msg: $"Couldn't compute merge-base from ($b)" } }

  if $preview or $dry_run {
    print $"Base: ($b)\nFork: ($fork)\n"
    print "Commits to squash:"; ^git log --oneline $"($fork)..HEAD"
    print "\nDiffstat:"; ^git diff --stat $"($fork)..HEAD"
  }
  if $dry_run { return }

  ^git reset --soft $fork
}
