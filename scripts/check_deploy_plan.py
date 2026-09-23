"""Reject destructive release plans without printing plan values or secrets."""
import json
import sys


def check(plan):
    if not isinstance(plan, dict) or not isinstance(plan.get("resource_changes"), list):
        raise ValueError("Terraform plan must contain a resource changes list.")
    if plan.get("errored") or plan.get("complete") is False:
        raise ValueError("Terraform plan is errored or incomplete.")
    for resource in plan["resource_changes"]:
        change = resource["change"]
        if "delete" in change["actions"]:
            raise ValueError("Release plan deletes or replaces resources; review and apply infrastructure changes separately.")
        if resource.get("type") == "aws_iam_role" and change.get("before"):
            before = change["before"].get("permissions_boundary")
            after = (change.get("after") or {}).get("permissions_boundary")
            unknown = change.get("after_unknown", {}).get("permissions_boundary", False)
            if before != after or unknown:
                raise ValueError("Release plan changes an IAM permissions boundary; verify deployment variables.")


if __name__ == "__main__":
    try:
        check(json.load(sys.stdin))
    except (ValueError, KeyError, TypeError, AttributeError):
        sys.exit("Deployment plan rejected. Review deletions, replacements, IAM boundaries, and plan completeness locally before retrying.")
    print("Deployment plan passed deletion, replacement, and IAM boundary checks.")
