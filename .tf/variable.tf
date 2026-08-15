variable "github_actions" {
  type    = bool
  default = false
}

# A ruleset can only be imported by its numeric ID, which does not exist until the ruleset does.
# Leave this unset for the first apply, then set the default to the ID the apply printed so later
# runs import the ruleset instead of planning a second one.
variable "ruleset_id" {
  type    = string
  default = null
}
