# Vegent Identity Deployment Guide

Release contract: 1.1. Layout updated: 2026-11-03.

Deploy one Lambda service and one MySQL database. The owner configures the AWS account, networking, private API Gateway, database instance and access permissions. Development source, reference material and test records are stored separately in `/Users/weizhang/Desktop/VegentSupport/`.

## 1. Deployment files

```text
VegentUpstream/
  DEPLOYMENT_GUIDE.md
  Lambda/
    vegent-identity.zip
    manifest.json
  MySQL/
    schema.sql
    operator-tools.zip
  TeamWork/                         existing folder, preserved in place
```

| File | Purpose |
| --- | --- |
| `Lambda/vegent-identity.zip` | Upload this ZIP as the single Lambda service. Dependencies, public RDS CA bundle and application code are already included. |
| `Lambda/manifest.json` | Candidate artifact checksum, CA checksum and security-policy metadata. |
| `MySQL/schema.sql` | Canonical schema for review: seven tables inside one database. The migrations in the operator bundle apply this schema. |
| `MySQL/operator-tools.zip` | Operator-only migration, seed and recovery tooling, required Python source, locked dependencies and CA bundle. Extract on an approved operator machine. Do not upload this bundle as a Lambda. |
| `TeamWork/` | Separate existing work, retained unchanged. It is not included in the Lambda ZIP. |

The Lambda ZIP was moved without rebuilding. Its SHA256 is:

```text
f650db857cf6b234ba8a6c6f43f85ee5674f9fb992da2b3493a394735e9b74d7
```

Verify with `shasum -a 256 Lambda/vegent-identity.zip` from this deployment directory. The operator archive contains no installed environment, test data, passwords, operational proofs or reference checkout.

## 2. Current validation status

The source passed 40 local tests against isolated MySQL 8.4.13, plus lint, formatting, English/branding and package checks. Two clean builds produced the same Lambda ZIP checksum. These results are preserved in the supporting-files directory.

This is an **unqualified deployment candidate**. Bcrypt cost12 is an explicit candidate value. Production acceptance still requires the owner's exact-engine checks, VPN/IAM/Secrets/TLS validation and a real 1,024 MB Lambda performance run. The extra local AMD64 Lambda-image import check was blocked because Docker did not start the test container. Do not interpret local tests or the folder cleanup as AWS acceptance.

## 3. MySQL requirements

Create the database instance and an empty `vegent_identity` database in the owner's environment. The exact engine version, instance class, support policy, backup settings and network configuration are owner decisions. MySQL 8.4.13 was used only for local tests; this guide does not select the production version.

Required database behavior:

- InnoDB, enforced CHECK constraints, generated indexed columns and foreign keys.
- `utf8mb4` with `utf8mb4_unicode_ci` defaults; email/hash columns retain their schema-specific binary collations.
- UTC session time zone and verified TLS hostname/CA identity.
- A dedicated application user and separate controlled operator credentials. Lambda never receives master/DDL credentials.
- Application access to mutable identity tables, with only SELECT/INSERT access on `audit_logs`. Runtime must not alter tables or update/delete audit history.

The seven tables are `users`, `teams`, `team_members`, `invitations`, `audit_logs`, `refresh_tokens` and `system_configs`. Alembic additionally maintains its own migration-version record.

Validate the exact schema on an approved isolated database of the selected engine before pilot migration. For an existing-user import, review normalized-email duplicates/nulls and preserve the original IDs. Import requires explicit `VEGENT_APPROVE_EXISTING_USERS_IMPORT=true`; it never merges accounts or overwrites a conflicting identity.

## 4. Run migrations and seed as operator jobs

Extract `MySQL/operator-tools.zip` into a separate, approved operator working directory. Python3.12 and `uv` are required. Run the following from the extracted directory:

```bash
uv sync --locked
```

Provide `VEGENT_OPERATOR_ADAPTER=module:factory` in the controlled operator process. The factory returns a trusted context with these methods:

- `verify_approval(approval_id, operation, target_email)`: attest the actual approval, operator identity, exact target database and expiry.
- `open_session()`: return a SQLAlchemy Session context using approved operator credentials and network access.
- `deliver_unlock_proof(target_email, token, expires_at)`: deliver a recovery proof through the approved trusted channel, without printing or logging it.

The adapter and credentials are supplied by the owner's execution environment. The bundle intentionally does not invent a company approval mechanism or a production database connection. The exact interface is in `scripts/seed_admin.py`; migrations load the same adapter without importing the application. The approval record includes approval_id, operation, operator_user_id, operator_principal, database_identity, target_email and expires_at. Migration approval uses operation `migrate`.

Set the nonsecret migration approval identifier and run:

```bash
uv run alembic -c migrations/alembic.ini upgrade head
```

`VEGENT_MIGRATION_APPROVAL` must contain the approved identifier. Run one migration job at a time; the runner acquires an exclusive MySQL lease. Migrations never run during Lambda import or cold start. Do not also execute `schema.sql` against the same database: it is the review/reference representation of the schema applied by these migrations.

After approved schema/network checks, seed the initial identity:

```bash
uv run python -m scripts.seed_admin seed --approval-id <approved-seed-id>
```

Seed creates only `wei.zhang11@verizon.com` / `wei.zhang11`, root Team `Verizon`, its self-invited Team Admin membership, one-time bootstrap state and audit provenance. It stores an unusable password hash, not a shared password. Repeating seed validates state and never reopens completed bootstrap or reactivates an account.

Seed/recovery scripts and operator credentials do not run inside the Lambda deployment. Complete operator operations with time-bound grants and revoke them after use.

## 5. Configure the main secret

Create or populate the owner-managed Secrets Manager secret `vegent/identity`. Do not put actual values in this guide, code, logs, manifests, Lambda plaintext environment variables or handoff tickets.

| Secret field | Required value |
| --- | --- |
| `SECRET_KEY` | Independently generated signing key, at least32 random bytes. |
| `ALGORITHM` | `HS256`. |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `60`. |
| `REFRESH_TOKEN_EXPIRE_DAYS` | `30`. |
| `DATABASE_HOST` | Actual private RDS endpoint hostname used for TLS verification. |
| `DATABASE_PORT` | `3306`. |
| `DATABASE_NAME` | `vegent_identity`. |
| `DATABASE_USER` | Dedicated least-privilege application user. |
| `DATABASE_PASSWORD` | Dedicated application credential, never the RDS master credential. |
| `INVITE_TOKEN_PEPPER` | Independently generated value, at least32 random bytes. |
| `UNLOCK_TOKEN_PEPPER` | Independently generated value, at least32 random bytes. |

The Lambda role needs GetSecretValue on this exact secret, the applicable KMS decrypt permission if required, restricted log-write permissions and the documented VPC ENI permissions. Configure these in the owner's account. Runtime secret retrieval and RDS access must remain private. Verify the selected RDS CA against the bundle digest in `Lambda/manifest.json` before acceptance.

## 6. Configure the single Lambda

| Setting | Value |
| --- | --- |
| Function name | `vegent-identity` |
| Deployment artifact | `Lambda/vegent-identity.zip` |
| Runtime | Python3.12 / Amazon Linux2023 |
| Architecture | x86_64 |
| Handler | `lambda_handler.handler` |
| Memory |1,024 MB |
| Timeout |15 seconds |
| Reserved concurrency |20 initially, subject to measured database capacity |
| Ingress | Private API Gateway Lambda proxy integration; no Function URL |

Owner-provided nonsecret runtime inputs:

| Input | Meaning |
| --- | --- |
| `VEGENT_IDENTITY_SECRET_ID` | `vegent/identity` or its exact ARN. |
| `AWS_REGION` | Supplied automatically by the Lambda runtime; use the matching SDK region in operator processes. |
| `VEGENT_API_ID` | Expected private API ID for bootstrap context validation. |
| `VEGENT_API_STAGE` | Expected private API stage. |
| `VEGENT_BOOTSTRAP_ROLE_ARN` | Exact IAM ARN for role `vegent-identity-bootstrap-admin`, required while setup is enabled. |
| `VEGENT_BOOTSTRAP_ENABLED` | `true` only during controlled initial setup; disable afterward. |

Do not deploy the operator ZIP, virtual environment, source checkout, tests or supporting-files directory as another Lambda. Runtime already includes its dependencies and public CA bundle.

## 7. Configure API routes

Use the owner's private REST API and Lambda proxy integration. Route paths below are application paths; the owner chooses the private base URL and stage. Configure Gateway authorization `AWS_IAM` for setup only. Other routes use Gateway `NONE` so the Lambda can validate Bearer tokens or authentication proofs; they remain private-network-only.

Disable API response caching, request-body execution tracing and public alternate ingress. Scope Lambda invocation to the approved API/stage. Verify actual VPN/DNS/private connectivity separately.

| Method | Application path | Application authorization |
| --- | --- | --- |
| POST | `/api/auth/account-status` | Private network; rate-limited password/invitation/unlock/refresh proof as applicable |
| POST | `/api/auth/register-by-invite` | Private network; rate-limited password/invitation/unlock/refresh proof as applicable |
| POST | `/api/auth/login` | Private network; rate-limited password/invitation/unlock/refresh proof as applicable |
| POST | `/api/auth/refresh` | Private network; rate-limited password/invitation/unlock/refresh proof as applicable |
| POST | `/api/auth/complete-registration-after-unlock` | Private network; rate-limited password/invitation/unlock/refresh proof as applicable |
| POST | `/api/auth/logout` | Bearer; current account and applicable Team membership/global role |
| POST | `/api/auth/admin-password/setup` | Approved IAM principal; no Bearer token |
| GET | `/api/me` | Bearer; current account and applicable Team membership/global role |
| PUT | `/api/me` | Bearer; current account and applicable Team membership/global role |
| GET | `/api/teams` | Bearer; current account and applicable Team membership/global role |
| POST | `/api/teams` | Bearer; System Admin |
| GET | `/api/teams/{team_id}` | Bearer; current account and applicable Team membership/global role |
| PUT | `/api/teams/{team_id}` | Bearer; System Admin or Team Admin of that Team |
| POST | `/api/teams/{team_id}/deactivate` | Bearer; System Admin |
| GET | `/api/teams/{team_id}/members` | Bearer; current account and applicable Team membership/global role |
| GET | `/api/teams/{team_id}/members/history` | Bearer; System Admin or Team Admin of that Team |
| GET | `/api/teams/{team_id}/invitations` | Bearer; System Admin or Team Admin of that Team |
| POST | `/api/teams/{team_id}/invitations` | Bearer; System Admin or Team Admin of that Team |
| POST | `/api/teams/{team_id}/invitations/accept` | Bearer plus matching-email invitation proof |
| POST | `/api/teams/{team_id}/invitations/{invitation_id}/revoke` | Bearer; System Admin or Team Admin of that Team |
| POST | `/api/teams/{team_id}/invitations/{invitation_id}/resend` | Bearer; System Admin or Team Admin of that Team |
| PUT | `/api/teams/{team_id}/members/{member_id}/role` | Bearer; System Admin or Team Admin of that Team |
| DELETE | `/api/teams/{team_id}/members/{member_id}` | Bearer; System Admin or Team Admin of that Team |
| GET | `/api/admin/users` | Bearer; System Admin |
| GET | `/api/admin/users/{user_id}` | Bearer; System Admin |
| PUT | `/api/admin/users/{user_id}` | Bearer; System Admin |
| PUT | `/api/admin/users/{user_id}/role` | Bearer; System Admin |
| POST | `/api/admin/users/{user_id}/deactivate` | Bearer; System Admin |
| POST | `/api/admin/users/{user_id}/unlock-registration` | Bearer; System Admin or qualifying directly inviting Team Admin |
| GET | `/api/health` | Private network readiness check |

## 8. Bootstrap and verify

1. Confirm the exact-engine isolated migration checks, secret permissions, database TLS and private health checks pass.
2. From the approved VPN, verify `GET /api/health` succeeds; verify off-VPN and disallowed-endpoint calls cannot invoke the service.
3. Temporarily enable setup. The approved principal assumes `vegent-identity-bootstrap-admin` and sends the initial password through a SigV4-signed setup request over the private API. No Bearer token is required. Do not place the password in shell history or logs.
4. Verify unsigned/wrong-IAM setup is denied; approved setup succeeds once; a second approved setup attempt returns409 with no password/state change.
5. Disable the setup Gateway method and `VEGENT_BOOTSTRAP_ENABLED`. The database completed flag remains the final lock, including after seed reruns.
6. Verify normal Wei login, profile, admin list, Team creation and invitation registration. A new Team has zero members until invitations are accepted; the creator is not automatically enrolled.
7. Invite/register a second independent person and promote them through `PUT /api/admin/users/{user_id}/role`. Verify their new login and admin access before pilot reliance. Never seed a second password.
8. Qualify the exact artifact on the owner's1,024 MB Lambda, including cold/warm latency, concurrency/database connections, failure handling and actual log redaction. Keep acceptance evidence outside the tested ZIP.

Invitation/registration accepts only normalized `@verizon.com` addresses. Passwords require12 characters and at most72 UTF-8 bytes without truncation. Access lifetime is60 minutes, refresh30 days, invitation30 days and unlock24 hours. Ordinary Team members do not receive pending-invitation counts. Logout revokes the supplied refresh token; account-wide lifecycle changes invalidate sessions through token versions.

## 9. Recovery and rollback

Normal password loss is handled by another System Admin's audited unlock action. If both administrators are lost, use the reviewed operator recovery procedure, actual approval verification and secure proof delivery:

```bash
uv run python -m scripts.seed_admin recover-admin --approval-id <approved-recovery-id> --operator-user-id <verified-operator-user-id> --email <verified-company-email>
```

Run only in the extracted operator environment with its trusted adapter. Never reopen bootstrap, reset its completed flag or assign a shared password. Reestablish two independent administrators before resuming reliance.

Rollback selects the last verified compatible Lambda/Gateway version and retains additive schema/history. For the first deployment, disable cloud identity and preserve local work. The owner controls database backups/restores; a restore must not silently revive old sessions/proofs. Inspect state and invalidate credentials before reopening.

## 10. Supporting files

All nondeployment files were moved to `/Users/weizhang/Desktop/VegentSupport/`:

| Folder | Contents |
| --- | --- |
| `identity-development/` | Complete service development source, tests, build tooling, dependency lock and original validation records. |
| `reference-checkout/` | Original reference repository and Git metadata, preserved together. |
| `design-and-review/` | Historical request and approved design. |
| `working-files/` | Intermediate work and the original development virtual environment. |

`MOVE_MANIFEST.json` in that supporting directory records paths, checksums and integrity verification. `TeamWork/` stayed in its original location and its contents were checked byte-for-byte. No owner AWS resources or database state were changed during this reorganization.
