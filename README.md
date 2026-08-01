# imap-scrub-docker

Runs [imap-scrub](https://github.com/mixeme/imap-scrub) (the actively
maintained fork of [axllent/imap-scrub](https://github.com/axllent/imap-scrub))
as a weekly scheduled job on AWS, packaged as a Docker image.

```
EventBridge Scheduler ──▶ ECS Fargate task ──▶ your IMAP server
        (weekly)             │        │
                             │        └─ config (incl. password) from Secrets Manager
                             ├─ image from ECR
                             └─ output to CloudWatch Logs
```

The container entrypoint writes the `IMAP_SCRUB_CONFIG` environment variable
(injected by ECS from Secrets Manager) to a config file, then runs
`imap-scrub <args> <config>`. Without `IMAP_SCRUB_CONFIG` set it expects a
config mounted at `/config/imap-scrub.yml` (override with
`IMAP_SCRUB_CONFIG_PATH`), which is handy for local use.

## Local usage

```sh
docker build -t imap-scrub .

# Dry run (no -y): shows what the rules would do
docker run --rm -v "$PWD/imap-scrub.yml:/config/imap-scrub.yml:ro" imap-scrub

# List mailboxes, to help write rules
docker run --rm -v "$PWD/imap-scrub.yml:/config/imap-scrub.yml:ro" imap-scrub -m

# Actually do it
docker run --rm -v "$PWD/imap-scrub.yml:/config/imap-scrub.yml:ro" imap-scrub -y
```

Start from [`imap-scrub.example.yml`](imap-scrub.example.yml); all options are
documented [upstream](https://github.com/mixeme/imap-scrub#all-yaml-config-options).
Note that imap-scrub only supports username/password logins — for Gmail that
means an [app password](https://myaccount.google.com/apppasswords) (requires
2-step verification).

## AWS setup

Prerequisites: Terraform >= 1.10, Docker (with buildx), and the AWS CLI
authenticated against your account (`AWS_REGION` set or a default region
configured).

**1. Create the infrastructure** (ECR repo, ECS cluster + task definition,
Secrets Manager secret, weekly schedule, IAM roles, log group):

```sh
scripts/bootstrap-state.sh   # one time: state bucket + terraform init
cd terraform
terraform apply
```

Terraform state is kept in a private, versioned S3 bucket — never in the
repo, since state can expose infrastructure details and this repo is public.
The bootstrap script creates the bucket (default
`imap-scrub-tfstate-<account-id>`), writes the gitignored
`terraform/backend.hcl`, and runs `terraform init` against it.

By default the task runs in the account's default VPC with a public IP
(Fargate needs a route to the internet to pull the image and reach your IMAP
server). See [`variables.tf`](terraform/variables.tf) for overrides — schedule,
timezone, VPC/subnets, CPU/memory, and `container_command` (set it to `[]` to
make the scheduled job a dry run while testing).

**2. Store your config** in the secret the task reads:

```sh
cp imap-scrub.example.yml imap-scrub.yml   # ...then edit it
scripts/push-config.sh
```

The script first validates the file by having imap-scrub itself parse and
print it (via the Docker image), then pushes it to the `imap-scrub/config`
secret with `aws secretsmanager put-secret-value`. Re-run it any time the
config changes — the next run picks it up automatically. (`imap-scrub.yml`
is gitignored so the password can't end up in the repo.)

**3. Build and push the image:**

```sh
scripts/build-and-push.sh
```

Images are built for `linux/arm64` to match the task definition's default
`ARM64` architecture (cheaper on Fargate). If you switch the
`cpu_architecture` variable to `X86_64`, push with `PLATFORM=linux/amd64`.

**4. Test it** without waiting for Sunday:

```sh
scripts/run-now.sh      # dry run: logs what the rules would do, changes nothing
scripts/run-now.sh -y   # the real thing
aws logs tail /ecs/imap-scrub --follow
```

After that, the job runs weekly (default: Sunday 06:00 UTC — tune with the
`schedule_expression` and `schedule_timezone` variables).

### Notes

- The whole YAML config lives in Secrets Manager because it contains the IMAP
  password; nothing sensitive is stored in Terraform state except the secret's
  ARN. Rotate the mailbox password by putting a new secret value — no
  redeploy needed.
- Fargate storage is ephemeral, so the `save_attachments` action would save
  files that vanish when the task exits. Stick to `remove_attachments` /
  `delete` rules in the scheduled job, or run `save_attachments` locally
  first.
- To upgrade imap-scrub, bump `IMAP_SCRUB_VERSION` in the [Dockerfile](Dockerfile)
  along with the two `IMAP_SCRUB_SHA256_*` checksums (`shasum -a 256` the new
  release tarballs), then re-run `scripts/build-and-push.sh` — the schedule
  picks up `:latest` on the next run.
- The `export_mailbox` action writes mbox files locally, so like
  `save_attachments` it only makes sense outside the ephemeral Fargate task.

### Cost

Roughly **$1/month** (us-east-1 ballpark): the Secrets Manager secret is
$0.40/month, weekly Fargate task runs on the smallest ARM size cost a few
cents, and ECR storage, CloudWatch logs, and the Terraform state bucket add
pennies. Everything is serverless — nothing runs (or bills) between
scheduled runs.

### Teardown

```sh
cd terraform
terraform destroy
```

This removes everything, including the ECR repository and its images
(`force_delete` is set). The secret is scheduled for deletion with Secrets
Manager's default 30-day recovery window rather than destroyed immediately.
The state bucket is not managed by Terraform; once you're fully done, remove
it with `aws s3 rb s3://imap-scrub-tfstate-<account-id> --force`.

## License

[MIT](LICENSE). imap-scrub itself is
[MIT-licensed](https://github.com/mixeme/imap-scrub/blob/develop/LICENSE) by
its own authors.
