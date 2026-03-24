#!/usr/bin/env python3
"""
SmartFreight ECS Deploy Script
================================
Registers a new ECS task definition revision and updates the service.
Used by Jenkins Stage 8 / Spinnaker bake stage as an alternative to
CLI-only approaches.

Usage:
    python3 ecs-deploy.py \\
        --service shipment-service \\
        --environment dev \\
        --image-uri 123456789.dkr.ecr.us-east-1.amazonaws.com/smartfreight/shipment-service:abc1234 \\
        [--region us-east-1] \\
        [--dry-run]
"""
import argparse
import json
import sys
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ─── Service configurations ─────────────────────────────────────────────────
SERVICES = {
    "shipment-service":      {"port": 8080, "cpu": {"dev": 256, "test": 512, "prod": 1024}},
    "carrier-service":       {"port": 8081, "cpu": {"dev": 256, "test": 512, "prod": 1024}},
    "invoice-service":       {"port": 8082, "cpu": {"dev": 256, "test": 512, "prod": 1024}},
    "document-service":      {"port": 8083, "cpu": {"dev": 256, "test": 512, "prod": 512}},
    "notification-service":  {"port": 8084, "cpu": {"dev": 256, "test": 512, "prod": 512}},
    "analytics-service":     {"port": 8085, "cpu": {"dev": 256, "test": 512, "prod": 1024}},
}

CPU_TO_MEMORY = {256: 512, 512: 1024, 1024: 2048, 2048: 4096}


def get_current_task_definition(ecs_client, family: str) -> dict:
    """Fetch the current (latest) task definition for a family."""
    try:
        response = ecs_client.describe_task_definition(taskDefinition=family)
        return response["taskDefinition"]
    except ClientError as e:
        if e.response["Error"]["Code"] == "ClientException":
            print(f"No existing task definition for family: {family}")
            return None
        raise


def register_new_task_definition(
    ecs_client,
    current_td: dict,
    new_image_uri: str,
    service_name: str,
    environment: str,
) -> dict:
    """Clone the current task definition with a new image URI."""
    service_cfg = SERVICES[service_name]
    cpu = service_cfg["cpu"].get(environment, 256)
    memory = CPU_TO_MEMORY.get(cpu, 512)

    # Build container definition
    container_def = {
        "name": service_name,
        "image": new_image_uri,
        "cpu": cpu,
        "memory": memory,
        "essential": True,
        "portMappings": [
            {"containerPort": service_cfg["port"], "protocol": "tcp"}
        ],
        "environment": [
            {"name": "SPRING_PROFILES_ACTIVE", "value": environment},
            {"name": "ENVIRONMENT", "value": environment},
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": f"/smartfreight/{environment}/{service_name}",
                "awslogs-region": ecs_client.meta.region_name,
                "awslogs-stream-prefix": service_name,
            },
        },
        "healthCheck": {
            "command": [
                "CMD-SHELL",
                f"curl -sf http://localhost:{service_cfg['port']}/actuator/health || exit 1",
            ],
            "interval": 30,
            "timeout": 10,
            "retries": 3,
            "startPeriod": 60,
        },
    }

    # If we have a current task def, carry over secrets and env vars
    if current_td:
        for existing_container in current_td.get("containerDefinitions", []):
            if existing_container.get("name") == service_name:
                # Preserve secrets (Secrets Manager references)
                if "secrets" in existing_container:
                    container_def["secrets"] = existing_container["secrets"]
                # Merge existing environment vars (keep, but new image overrides image only)
                existing_env = {e["name"]: e["value"] for e in existing_container.get("environment", [])}
                merged = {**existing_env, **{e["name"]: e["value"] for e in container_def["environment"]}}
                container_def["environment"] = [{"name": k, "value": v} for k, v in merged.items()]
                break

    # Build the new task definition registration request
    family = f"{service_name}-{environment}"
    register_kwargs = {
        "family": family,
        "networkMode": "awsvpc",
        "requiresCompatibilities": ["FARGATE"],
        "cpu": str(cpu),
        "memory": str(memory),
        "containerDefinitions": [container_def],
    }

    # Preserve execution and task roles from current definition
    if current_td:
        if "executionRoleArn" in current_td:
            register_kwargs["executionRoleArn"] = current_td["executionRoleArn"]
        if "taskRoleArn" in current_td:
            register_kwargs["taskRoleArn"] = current_td["taskRoleArn"]

    response = ecs_client.register_task_definition(**register_kwargs)
    return response["taskDefinition"]


def update_ecs_service(
    ecs_client,
    cluster: str,
    service_name: str,
    environment: str,
    task_def_arn: str,
    dry_run: bool,
) -> None:
    """Update the ECS service to use the new task definition."""
    ecs_service_name = f"{service_name}-{environment}"

    if dry_run:
        print(f"[DRY RUN] Would update service {ecs_service_name} in cluster {cluster}")
        print(f"[DRY RUN]   taskDefinition: {task_def_arn}")
        return

    ecs_client.update_service(
        cluster=cluster,
        service=ecs_service_name,
        taskDefinition=task_def_arn,
        deploymentConfiguration={
            "deploymentCircuitBreaker": {"enable": True, "rollback": True},
            "maximumPercent": 200,
            "minimumHealthyPercent": 100,
        },
    )
    print(f"Updated service: {ecs_service_name} → {task_def_arn}")

    # Wait for stability
    print("Waiting for service to stabilize (up to 10 minutes)...")
    waiter = ecs_client.get_waiter("services_stable")
    waiter.wait(
        cluster=cluster,
        services=[ecs_service_name],
        WaiterConfig={"Delay": 15, "MaxAttempts": 40},
    )
    print(f"✓ Service stable: {ecs_service_name}")


def main():
    parser = argparse.ArgumentParser(description="SmartFreight ECS Deploy")
    parser.add_argument("--service", required=True, choices=list(SERVICES.keys()))
    parser.add_argument("--environment", required=True, choices=["dev", "test", "prod"])
    parser.add_argument("--image-uri", required=True, help="Full ECR image URI with tag")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without executing")
    args = parser.parse_args()

    cluster = f"smartfreight-{args.environment}"
    family = f"{args.service}-{args.environment}"

    print(f"SmartFreight ECS Deploy")
    print(f"  Service:     {args.service}")
    print(f"  Environment: {args.environment}")
    print(f"  Image:       {args.image_uri}")
    print(f"  Cluster:     {cluster}")
    print(f"  Dry run:     {args.dry_run}")
    print()

    ecs = boto3.client("ecs", region_name=args.region)

    # 1. Get current task definition
    current_td = get_current_task_definition(ecs, family)

    # 2. Register new task definition revision
    if args.dry_run:
        print(f"[DRY RUN] Would register new task definition for family: {family}")
        print(f"[DRY RUN]   image: {args.image_uri}")
        new_td = {"taskDefinitionArn": f"arn:aws:ecs:{args.region}:000000000000:task-definition/{family}:999"}
    else:
        print(f"Registering new task definition for family: {family}")
        new_td = register_new_task_definition(ecs, current_td, args.image_uri, args.service, args.environment)
        print(f"Registered: {new_td['taskDefinitionArn']} (revision {new_td['revision']})")

    # 3. Update ECS service
    update_ecs_service(ecs, cluster, args.service, args.environment, new_td["taskDefinitionArn"], args.dry_run)

    if not args.dry_run:
        print()
        print(f"✓ Deployment complete: {args.service} → {args.environment}")
        print(f"  Task definition: {new_td['taskDefinitionArn']}")
        print(f"  Image: {args.image_uri}")
        print(f"  Deployed at: {datetime.now(timezone.utc).isoformat()}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAborted by user.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
