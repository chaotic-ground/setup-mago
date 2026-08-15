# A ruleset can be imported by its numeric ID and no other way, and state is not kept between
# runs, so the ID is written down here. Recreating the ruleset gives it a new one.
import {
  id = "setup-mago:20882589"
  to = github_repository_ruleset.default
}
resource "github_repository_ruleset" "default" {
  name        = "default"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = "active"

  # Declare bypass actors only on local PAT runs; they're admin-only and unreadable by CI's token.
  dynamic "bypass_actors" {
    for_each = var.github_actions ? [] : [
      { actor_id = 5, actor_type = "RepositoryRole" }, # Repository admin
      { actor_id = 17810468, actor_type = "Team" },    # chaotic-ground/publishers
    ]
    content {
      actor_id    = bypass_actors.value.actor_id
      actor_type  = bypass_actors.value.actor_type
      bypass_mode = "always"
    }
  }

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    # Protect default branch: block deletion and force-pushes, and require a PR for every change.
    deletion         = true
    non_fast_forward = true
    update           = false

    # Squash is the only allowed merge method, so linear history need not be required separately.
    required_linear_history = false
    required_signatures     = false

    pull_request {
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_approving_review_count   = 0
      required_review_thread_resolution = false
    }

    # Required: the lint jobs, semantic-pull-request, and every job that installs the action on a
    # real runner (integration_id 15368 = GitHub Actions app).
    required_status_checks {
      do_not_enforce_on_create             = false
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = [
          "checksum",
          "detect",
          "install (macos-latest)",
          "install (ubuntu-24.04-arm)",
          "install (ubuntu-latest)",
          "install (windows-latest)",
          "latest",
          "rumdl",
          "semantic-pull-request",
          "shellcheck",
          "typos",
          "version (macos-latest)",
          "version (ubuntu-latest)",
          "version (windows-latest)",
          "yamllint",
          "zizmor",
        ]
        content {
          context        = required_check.value
          integration_id = 15368
        }
      }
    }
  }
}
