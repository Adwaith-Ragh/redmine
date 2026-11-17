# Local Redmine Server for NetOps Finance Mailer

A Docker-based local Redmine instance running Redmine 6 on PostgreSQL 16, pre-configured with the exact trackers, issue statuses, custom field definitions, users, and workflows expected by the **NetOps Finance Mailer**.

---

## 1. Quick Start

### Start Containers
From the workspace root or inside the `redmine/` folder:

```bash
cd /home/adwaithraghna/Desktop/merger/redmine
docker compose up -d
```
*(Or from the workspace root: `docker compose up -d`)*

### One-Time Initialization & Seeding
Once the containers are up, run the initialization command:

```bash
./init-redmine.sh
```

Alternatively, you can run the Rails runner command directly:
```bash
docker compose exec -T redmine bin/rails runner /seed.rb
```

This one-time command idempotently:
1. Enables the Redmine REST web service (`rest_api_enabled = 1`).
2. Configures standard issue statuses (1: New, 2: In Progress, 3: Resolved, 4: Feedback, 5: Closed, 6: Rejected).
3. Creates **Tracker 12** (`License Request`, default status `In Progress`) with workflow transitions across roles.
4. Creates all **Custom Fields (IDs 1–9)** with their exact IDs, formats, options, and tracker bindings.
5. Seeds all integration users, roles, memberships, and pre-generated API access keys.
6. Seeds **Ticket 23593** (Approved, valid approval history, attachment), **Ticket 23594** (Self-approved), and **Ticket 23595** (Not approved).
7. Resets database sequences so future records increment smoothly.

---

## 2. Server & Service Configuration

| Service | Container Name | Image | Port | Volumes | Restart Policy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Redmine** | `redmine-app` | `redmine:6` | `http://localhost:3005` | `redmine-files` | `unless-stopped` |
| **PostgreSQL** | `redmine-db` | `postgres:16` | Internal: 5432 | `redmine-db-data` | `unless-stopped` |

- **Data Persistence**:
  - PostgreSQL database storage is persisted in Docker named volume `redmine-db-data`.
  - Redmine uploaded attachments are persisted in Docker named volume `redmine-files`.

---

## 3. Credentials & API Keys

### Administrator Account
- **Web UI URL**: [http://localhost:3005](http://localhost:3005)
- **Username**: `admin`
- **Password**: `AdminPassword123!`
- **Admin API Key**: `9f8e7d6c5b4a3928170f1e2d3c4b5a69788796a5`

### Dedicated Integration API User
- **Username**: `api-service`
- **Password**: `ApiServicePassword123!`
- **API Key**: `fedcba9876543210fedcba9876543210fedcba98`
- **Role**: Administrator / NetOps Manager (can read users' email addresses and update tickets).

### Seeded Users
| ID | Login | Name | Email | Role |
| :--- | :--- | :--- | :--- | :--- |
| **10** | `sweetlin` | Sweetlin Panjikaran | `sweetlin.p@tarento.com` | Requester / Project Member |
| **20** | `vishwanath` | Vishwanath Ashi | `vishwanath.a@tarento.com` | Project Member |
| **30** | `imran` | Imran Ulla | `imran.u@tarento.com` | BL Head / Approver |
| **40** | `api-service` | API Service | `api-service@tarento.com` | Administrator (Integration) |

---

## 4. Finance Mailer Compatibility

### Custom Fields
| ID | Name | Format | Possible Values / Default |
| :--- | :--- | :--- | :--- |
| **1** | Business Line | List | `Buy`, `Sell`, `Corporate`, `Internal` |
| **2** | Name of the License | String | — |
| **3** | Purpose | Text | — |
| **4** | Name of the Project | String | — |
| **5** | Duration | String | — |
| **6** | BL Head/Project Manager | String | Matches approver name (e.g. `Imran Ulla`) |
| **7** | Approved | List | `No`, `Yes` (Default: `No`) |
| **8** | Billing Type | List | `Cost to Business Line`, `Cost to Project`, `Overhead` |
| **9** | Finance Notified | Bool | `0`, `1` (Default: `0`) |

### Finance Mailer Environment Variables (`.env`)
To connect the Finance Mailer to this local Redmine server, configure `netops-finance-mailer/.env`:

```env
REDMINE_URL=http://localhost:3005
REDMINE_API_KEY=fedcba9876543210fedcba9876543210fedcba98
REDMINE_VERIFY_SSL=false
REDMINE_PROJECT=netops-support
REDMINE_TRACKER_IDS=12
APPROVED_CF_ID=7
APPROVED_VALUES=Yes,1,true
APPROVED_FILTER_VALUE=Yes
APPROVER_CF_ID=6
FINANCE_NOTIFIED_CF_ID=9
FINANCE_NOTIFIED_VALUE=1
STATUS_AFTER_SEND_ID=2
```

---

## 5. Seeded Test Tickets

### Ticket 23593: Approved (Valid Approval History)
- **Tracker**: `License Request` (#12)
- **Status**: `In Progress` (#2)
- **Requester**: Sweetlin Panjikaran (#10)
- **BL Head/Project Manager**: `Imran Ulla`
- **Approved**: `Yes`
- **Journals**:
  1. Vishwanath Ashi: *"Kindly obtain approval from @Imran Baig"*
  2. Imran Ulla: *"Approved."* + Custom Field #7 changed from `No` to `Yes`.
- **Attachment**: `claude_subscription_quote.pdf`
- **Finance Mailer Verdict**: **`Approval verified`** (0 warnings, approved by authorized BL Head).

### Ticket 23594: Self-Approved
- **Tracker**: `License Request` (#12)
- **Status**: `In Progress` (#2)
- **Requester**: Sweetlin Panjikaran (#10)
- **BL Head/Project Manager**: `Imran Ulla`
- **Approved**: `Yes`
- **Journals**:
  1. Sweetlin Panjikaran (requester herself): Custom Field #7 changed from `No` to `Yes`.
- **Finance Mailer Verdict**: **`Approved, with warnings`** (Warns: *Self-approval: the requester set Approved=Yes* and *Approver does not match BL Head/Project Manager*).

### Ticket 23595: Not Approved
- **Tracker**: `License Request` (#12)
- **Status**: `In Progress` (#2)
- **Requester**: Sweetlin Panjikaran (#10)
- **BL Head/Project Manager**: `Imran Ulla`
- **Approved**: `No`
- **Journals**: None
- **Finance Mailer Verdict**: **`Not approved`** (Field 'Approved' is currently 'No').

---

## 6. Verification

Run the automated verification suite to validate all 35 integrity checks:

```bash
python3 verify_redmine.py
```

This verifies:
1. HTTP connectivity on `http://localhost:3005`.
2. REST API authentication.
3. Tracker 12, Project 1, and Custom Fields 1–9 existence.
4. Requester email resolution (`sweetlin.p@tarento.com`).
5. Attachment downloading.
6. Approval analyzer verification for all 3 seeded tickets.
7. Issue filtering (`only_approved=True` vs `only_approved=False`).
8. Adding notes to issues via the API.

---

## 7. Isolation

This setup is completely self-contained in `redmine/` and operates on port `3005`.
- **IT Dashboard**: Not modified, runs independently on ports `8888` / `3001`.
- **No Shared Volumes/Databases**: Uses dedicated `redmine-db-data` and `redmine-files` volumes.
