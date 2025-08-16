# SessionBase Operational Scripts

## User Management

### block-user.sh

Safely block or unblock users from the SessionBase API.

**Usage:**
```bash
# Block a user
./block-user.sh user123

# Unblock a user  
./block-user.sh user123 unblock
```

**What it does:**
- Safely preserves all existing environment variables
- Updates all authenticated Lambda functions:
  - `createSession` (prevents uploads)
  - `updateSessionMetadata` 
  - `deleteSession`
  - `listSessions`
- Manages comma-separated list of blocked user IDs
- Avoids duplicates when blocking
- Properly removes users when unblocking

**Emergency Response:**
```bash
# Block abusive user immediately
./block-user.sh abusive_user_id

# Multiple users
./block-user.sh user1 && ./block-user.sh user2

# Unblock when issue resolved
./block-user.sh abusive_user_id unblock
```

**Prerequisites:**
- AWS CLI configured with appropriate permissions
- `jq` installed for JSON processing
- SessionBase backend deployed with stack name `BackendStack`

**Permissions needed:**
- `lambda:GetFunctionConfiguration`
- `lambda:UpdateFunctionConfiguration`

**⚠️ Important: CDK Deployment Warning**
This script directly modifies Lambda environment variables. If you deploy the CDK stack after blocking users, it will reset the blocked users list to empty.

**Before CDK deployment:**
1. Check current blocked users: `aws lambda get-function-configuration --function-name BackendStack-createSession --query 'Environment.Variables.BLOCKED_USER_IDS'`
2. If users are blocked, add them to your `.env` file in the backend directory:
   ```bash
   echo "BLOCKED_USER_IDS=user1,user2" >> ../backend/.env
   ```
3. Then deploy: `cd ../backend && cdk deploy`

**Emergency workflow:**
1. User starts abusing API → `./block-user.sh bad_user`
2. Issue resolved → `./block-user.sh bad_user unblock`
3. Before next deployment → Check and preserve blocked users list