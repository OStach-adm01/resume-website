import unittest

from check_deploy_plan import check


class DeployPlanTests(unittest.TestCase):
    def plan(self, actions, before=None, after=None, unknown=None):
        return {"resource_changes": [{"type": "aws_iam_role", "change": {
            "actions": actions, "before": before, "after": after,
            "after_unknown": unknown or {},
        }}]}

    def test_allows_creation_and_ordinary_update(self):
        check(self.plan(["create"], after={"permissions_boundary": "expected"}))
        check(self.plan(["update"], {"permissions_boundary": "expected", "tags": {}},
                        {"permissions_boundary": "expected", "tags": {"x": "y"}}))

    def test_rejects_deletion_and_both_replacement_orders(self):
        for actions in (["delete"], ["delete", "create"], ["create", "delete"]):
            with self.subTest(actions=actions), self.assertRaises(ValueError):
                check(self.plan(actions))

    def test_rejects_boundary_change_removal_and_unknown(self):
        for after, unknown in (({"permissions_boundary": "wrong"}, {}), ({}, {}),
                               ({"permissions_boundary": "expected"}, {"permissions_boundary": True})):
            with self.subTest(after=after, unknown=unknown), self.assertRaises(ValueError):
                check(self.plan(["update"], {"permissions_boundary": "expected"}, after, unknown))

    def test_rejects_failed_or_partial_plan(self):
        for plan in ({"errored": True, "resource_changes": []}, {"complete": False, "resource_changes": []}):
            with self.assertRaises(ValueError):
                check(plan)

    def test_rejects_missing_plan_structure(self):
        for plan in ({}, [], {"resource_changes": None}):
            with self.assertRaises(ValueError):
                check(plan)


if __name__ == "__main__":
    unittest.main()
