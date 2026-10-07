#!/usr/bin/env python3
"""Generate a static inventory file for EC2 instances by Name tag.

This script queries AWS EC2 for instances tagged with project=capstone-project and
writes their private IPs into ansible/inventory/hosts.ini. The grouping is based
on each instance Name tag so that Jenkins master, Jenkins agents, SonarQube,
Maven/Trivy, and app servers are discovered automatically.
"""

import os
from collections import defaultdict
from pathlib import Path

import boto3

REGION = os.getenv("AWS_REGION", "us-east-1")
PROJECT_TAG = os.getenv("PROJECT_TAG", "capstone-project")
OUT_FILE = Path(__file__).resolve().parent / "inventory" / "hosts.ini"


def group_for_name(instance_name: str) -> str:
    name = instance_name.lower()
    if "jenkins-master" in name:
        return "jenkins_master"
    if "jenkins-worker" in name:
        return "jenkins_agents"
    if "sonarqube" in name:
        return "sonarqube"
    if "maven-trivy" in name or "maven" in name or "trivy" in name:
        return "build_tools"
    if "app" in name or "capstone-app" in name:
        return "app_servers"
    return "misc"


def main() -> None:
    client = boto3.client("ec2", region_name=REGION)
    response = client.describe_instances(
        Filters=[
            {"Name": "tag:project", "Values": [PROJECT_TAG]},
            {"Name": "instance-state-name", "Values": ["running", "pending"]},
        ]
    )

    grouped = defaultdict(list)
    for reservation in response.get("Reservations", []):
        for instance in reservation.get("Instances", []):
            private_ip = instance.get("PrivateIpAddress")
            if not private_ip:
                continue
            tags = {tag.get("Key"): tag.get("Value") for tag in instance.get("Tags", [])}
            host_name = tags.get("Name", instance.get("InstanceId"))
            grouped[group_for_name(host_name)].append(private_ip)

    lines = [
        "[all:vars]",
        "ansible_user=ec2-user",
        "ansible_ssh_private_key_file=~/.ssh/capstone-key.pem",
        "",
    ]

    for group_name in [
        "jenkins_master",
        "jenkins_agents",
        "sonarqube",
        "build_tools",
        "app_servers",
        "misc",
    ]:
        members = sorted(set(grouped.get(group_name, [])))
        if not members:
            continue
        lines.append(f"[{group_name}]")
        lines.extend(members)
        lines.append("")

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")
    print(f"Inventory refreshed: {OUT_FILE}")
    for group_name in [
        "jenkins_master",
        "jenkins_agents",
        "sonarqube",
        "build_tools",
        "app_servers",
    ]:
        members = sorted(set(grouped.get(group_name, [])))
        if members:
            print(f"{group_name}: {', '.join(members)}")


if __name__ == "__main__":
    main()
