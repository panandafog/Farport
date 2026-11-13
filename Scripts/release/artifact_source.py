"""Only restore binaries from this protected release workflow, never a PR run."""
import json
import os
import re
import pathlib
import urllib.request

from .asc import NoRedirect
from .metadata import NeedsAction, ReleaseError


def validate_run(run, repository, branch):
    if (run.get("repository", {}).get("full_name") != repository
            or run.get("head_repository", {}).get("full_name") != repository
            or run.get("head_branch") not in {branch, "dev"}
            or run.get("event") != "workflow_dispatch"
            or run.get("path", "").split("@", 1)[0] != ".github/workflows/app-store-release.yml"
            or run.get("status") != "completed"
            or not re.fullmatch(r"[0-9a-f]{40}", run.get("head_sha", ""))):
        raise ReleaseError("Artifact source must be a completed manual release run of this repository's default branch, not a fork/PR/other workflow.")


def main():
    run_id = os.environ.get("ARTIFACT_RUN_ID", "")
    if not re.fullmatch(r"[0-9]+", run_id):
        raise NeedsAction("upload mode requires a numeric artifact_run_id from a previous full release run.")
    repository = os.environ["GITHUB_REPOSITORY"]
    request = urllib.request.Request(f"https://api.github.com/repos/{repository}/actions/runs/{run_id}",
        headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"], "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
            run = json.load(response)
        validate_run(run, repository, os.environ["RELEASE_DEFAULT_BRANCH"])
    except OSError:
        raise ReleaseError("Cannot verify the signed artifact's GitHub run provenance. Nothing was downloaded or uploaded.") from None
    source = dict(repository=repository, sha=run["head_sha"], runId=str(run["id"]),
                  workflow=".github/workflows/app-store-release.yml")
    target = pathlib.Path("Build/Release") / os.environ["RELEASE_PLATFORM"] / "artifact-source.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(source))
    print("Signed artifact source verified: trusted manual release run and commit SHA.")


if __name__ == "__main__":
    main()
