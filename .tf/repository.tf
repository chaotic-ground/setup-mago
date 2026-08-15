import {
  id = "setup-mago"
  to = github_repository.this
}
resource "github_repository" "this" {
  # Only the squash message and title are set. Merge commits are off, and GitHub does not keep a
  # title or message for a merge method the repository does not allow -- an apply wrote them, a
  # fresh read gave the defaults back, and every run from an empty state planned to write them
  # again, which is drift nobody can clear.
  allow_auto_merge            = true
  allow_merge_commit          = false
  allow_rebase_merge          = false
  allow_squash_merge          = true
  allow_update_branch         = true
  archived                    = false
  archive_on_destroy          = true
  auto_init                   = false
  delete_branch_on_merge      = true
  description                 = "Install the mago PHP toolchain in GitHub Actions."
  has_discussions             = false
  has_issues                  = true
  has_projects                = false
  has_wiki                    = false
  name                        = "setup-mago"
  squash_merge_commit_message = "PR_BODY"
  squash_merge_commit_title   = "PR_TITLE"
  topics                      = ["github-actions", "mago", "php", "static-analysis"]
  visibility                  = "public"
  web_commit_signoff_required = false

  dynamic "security_and_analysis" {
    for_each = var.github_actions ? [] : [true]
    content {
      secret_scanning {
        status = "enabled"
      }
      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Cannot be imported
      archive_on_destroy,
      # Not a repository setting at all -- a deprecated provider flag about how to read one --
      # so an imported resource never carries it and every plan would show it being set.
      ignore_vulnerability_alerts_during_read,
    ]
  }
}
