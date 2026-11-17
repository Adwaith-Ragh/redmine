#!/usr/bin/env python3
"""
Comprehensive verification script for Redmine server & Finance Mailer compatibility.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Add netops-finance-mailer to python path
repo_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(repo_root / "netops-finance-mailer"))

from app.config import settings
from app.redmine import Redmine, RedmineError, analyze_approval

# Set integration settings
settings.redmine_url = os.getenv("REDMINE_URL", "http://localhost:3005")
settings.redmine_api_key = os.getenv("REDMINE_API_KEY", "fedcba9876543210fedcba9876543210fedcba98")
settings.approved_cf_id = os.getenv("APPROVED_CF_ID", "7")
settings.approver_cf_id = os.getenv("APPROVER_CF_ID", "6")
settings.approved_values = [v.lower() for v in os.getenv("APPROVED_VALUES", "Yes,1,true").split(",")]
settings.approved_filter_value = os.getenv("APPROVED_FILTER_VALUE", "Yes")
settings.redmine_project = os.getenv("REDMINE_PROJECT", "netops-support")
settings.redmine_tracker_ids = os.getenv("REDMINE_TRACKER_IDS", "12")


def main():
    print("=" * 60)
    print("REDMINE SERVER & FINANCE MAILER COMPATIBILITY VERIFICATION")
    print(f"URL: {settings.redmine_url}")
    print(f"API Key: {settings.redmine_api_key[:6]}...{settings.redmine_api_key[-4:]}")
    print("=" * 60)

    client = Redmine()
    passed_tests = 0
    total_tests = 0

    def assert_check(description: str, condition: bool, details: str = ""):
        nonlocal passed_tests, total_tests
        total_tests += 1
        if condition:
            print(f"  [PASS] {description}")
            passed_tests += 1
        else:
            print(f"  [FAIL] {description} - {details}")

    # 1. Server & API Auth Check
    print("\n1. Redmine Connectivity & API Authentication")
    try:
        user_data = client._get("/users/current.json")
        user = user_data.get("user", {})
        assert_check("API responds to /users/current.json", True)
        assert_check("API User is authenticated", user.get("login") in ("api-service", "admin"), f"Got login: {user.get('login')}")
    except Exception as ex:
        assert_check("API responds to /users/current.json", False, str(ex))

    # 2. Trackers and Custom Fields Check
    print("\n2. Redmine Schema Configuration")
    try:
        trackers_data = client._get("/trackers.json")
        trackers = {t["id"]: t["name"] for t in trackers_data.get("trackers", [])}
        assert_check("Tracker 12 exists with name 'License Request'", trackers.get(12) == "License Request", f"Found: {trackers}")

        cfs_data = client._get("/custom_fields.json")
        cfs = {cf["id"]: cf["name"] for cf in cfs_data.get("custom_fields", [])}
        expected_cfs = {
            1: "Business Line",
            2: "Name of the License",
            3: "Purpose",
            4: "Name of the Project",
            5: "Duration",
            6: "BL Head/Project Manager",
            7: "Approved",
            8: "Billing Type",
            9: "Finance Notified",
        }
        for cf_id, cf_name in expected_cfs.items():
            assert_check(f"Custom Field {cf_id} ('{cf_name}') exists", cfs.get(cf_id) == cf_name, f"Got: {cfs.get(cf_id)}")
    except Exception as ex:
        assert_check("Schema configuration check", False, str(ex))

    # 3. User & Requester Email Check
    print("\n3. Users & Email Resolution")
    try:
        mail = client.get_user_mail(10)
        assert_check("Requester user 10 email is sweetlin.p@tarento.com", mail == "sweetlin.p@tarento.com", f"Got: {mail}")
    except Exception as ex:
        assert_check("Email resolution check", False, str(ex))

    # 4. Ticket 23593: Approved, valid approval history
    print("\n4. Ticket 23593: Approved, valid approval history")
    try:
        issue = client.get_issue(23593)
        assert_check("Ticket 23593 found", issue.get("id") == 23593)
        assert_check("Ticket 23593 tracker is License Request (12)", (issue.get("tracker") or {}).get("id") == 12)
        assert_check("Ticket 23593 author is Sweetlin Panjikaran (10)", (issue.get("author") or {}).get("id") == 10)
        assert_check("Ticket 23593 has attachment", len(issue.get("attachments", [])) >= 1)

        analysis = analyze_approval(issue)
        assert_check("Ticket 23593 is_approved == True", analysis["is_approved"] is True)
        assert_check("Ticket 23593 self_approved is not True", analysis.get("self_approved") is not True)
        assert_check("Ticket 23593 last_approval approver is Imran Ulla", (analysis.get("last_approval") or {}).get("user") == "Imran Ulla")
        assert_check("Ticket 23593 expected_approver is Imran Ulla", analysis.get("expected_approver") == "Imran Ulla")
        assert_check("Ticket 23593 has zero warnings", len(analysis.get("warnings", [])) == 0, f"Warnings: {analysis.get('warnings')}")
        assert_check("Ticket 23593 has approval comments", len(analysis.get("approval_comments", [])) >= 1)
        print("  -> Verdict: Approval verified (valid approval history)")
    except Exception as ex:
        assert_check("Ticket 23593 check", False, str(ex))

    # 5. Ticket 23594: Self-approved
    print("\n5. Ticket 23594: Self-approved")
    try:
        issue = client.get_issue(23594)
        assert_check("Ticket 23594 found", issue.get("id") == 23594)

        analysis = analyze_approval(issue)
        assert_check("Ticket 23594 is_approved == True", analysis["is_approved"] is True)
        assert_check("Ticket 23594 self_approved == True", analysis.get("self_approved") is True)
        assert_check("Ticket 23594 flags self-approval warning", any("Self-approval" in w for w in analysis.get("warnings", [])), f"Warnings: {analysis.get('warnings')}")
        assert_check("Ticket 23594 flags approver mismatch warning", any("does not match" in w for w in analysis.get("warnings", [])), f"Warnings: {analysis.get('warnings')}")
        print("  -> Verdict: Approved, with warnings (self-approval detected)")
    except Exception as ex:
        assert_check("Ticket 23594 check", False, str(ex))

    # 6. Ticket 23595: Not approved
    print("\n6. Ticket 23595: Not approved")
    try:
        issue = client.get_issue(23595)
        assert_check("Ticket 23595 found", issue.get("id") == 23595)

        analysis = analyze_approval(issue)
        assert_check("Ticket 23595 is_approved == False", analysis["is_approved"] is False)
        assert_check("Ticket 23595 flags 'not approved' warning", any("not approved" in w for w in analysis.get("warnings", [])), f"Warnings: {analysis.get('warnings')}")
        print("  -> Verdict: Not approved")
    except Exception as ex:
        assert_check("Ticket 23595 check", False, str(ex))

    # 7. Dashboard Filtering Check
    print("\n7. Issue Listing & Approved Filtering")
    try:
        all_issues = client.list_issues(status="open", only_approved=False)
        approved_issues = client.list_issues(status="open", only_approved=True)

        all_ids = [i["id"] for i in all_issues.get("issues", [])]
        approved_ids = [i["id"] for i in approved_issues.get("issues", [])]

        assert_check("All issues contains 23593, 23594, 23595", all(x in all_ids for x in [23593, 23594, 23595]), f"Got: {all_ids}")
        assert_check("Approved filter includes 23593 and 23594", 23593 in approved_ids and 23594 in approved_ids, f"Got: {approved_ids}")
        assert_check("Approved filter excludes unapproved 23595", 23595 not in approved_ids, f"Got: {approved_ids}")
    except Exception as ex:
        assert_check("Listing and filtering check", False, str(ex))

    # 8. Note addition check
    print("\n8. Issue Notes & Updates")
    try:
        client.add_note(23593, "Verification test note from verify_redmine.py")
        updated_issue = client.get_issue(23593)
        notes = [j.get("notes") for j in updated_issue.get("journals", [])]
        assert_check("Successfully added note to Ticket 23593", any("Verification test note" in n for n in notes if n))
    except Exception as ex:
        assert_check("Issue note addition check", False, str(ex))

    print("\n" + "=" * 60)
    print(f"VERIFICATION SUMMARY: {passed_tests} / {total_tests} checks passed.")
    print("=" * 60)

    if passed_tests == total_tests:
        print("\nALL CHECKS PASSED SUCCESSFULLY!\n")
        sys.exit(0)
    else:
        print(f"\n{total_tests - passed_tests} CHECK(S) FAILED!\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
