#!/bin/bash

# Script to safely block/unblock users from SessionBase API
# Usage: ./block-user.sh <user_id> [unblock]

set -e

USER_ID="$1"
ACTION="${2:-block}"
STACK_NAME="BackendStack"

# Function name patterns that need user blocking
FUNCTION_PATTERNS=(
    "createSession"
    "updateSessionMetadata"
    "deleteSession"
    "listSessions"
)

if [ -z "$USER_ID" ]; then
    echo "Usage: $0 <user_id> [unblock]"
    echo "Examples:"
    echo "  $0 user123           # Block user123"
    echo "  $0 user123 unblock   # Unblock user123"
    exit 1
fi

echo "🔍 Finding Lambda functions and getting current blocked users list..."

# Find actual function names (CDK adds random suffixes)
ACTUAL_FUNCTIONS=()
for pattern in "${FUNCTION_PATTERNS[@]}"; do
    FUNC_NAME=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, '$pattern')].FunctionName" \
        --output text)
    if [ -n "$FUNC_NAME" ]; then
        ACTUAL_FUNCTIONS+=("$FUNC_NAME")
        echo "📍 Found function: $FUNC_NAME"
    else
        echo "⚠️  Warning: No function found matching pattern '$pattern'"
    fi
done

if [ ${#ACTUAL_FUNCTIONS[@]} -eq 0 ]; then
    echo "❌ No Lambda functions found. Make sure your CDK stack is deployed."
    exit 1
fi

# Get current BLOCKED_USER_IDS from first function
CURRENT_BLOCKED=$(aws lambda get-function-configuration \
    --function-name "${ACTUAL_FUNCTIONS[0]}" \
    --query 'Environment.Variables.BLOCKED_USER_IDS' \
    --output text 2>/dev/null || echo "None")

if [ "$CURRENT_BLOCKED" = "None" ] || [ "$CURRENT_BLOCKED" = "null" ]; then
    CURRENT_BLOCKED=""
fi

echo "📋 Current blocked users: ${CURRENT_BLOCKED:-"(none)"}"

# Update blocked users list
if [ "$ACTION" = "unblock" ]; then
    echo "🔓 Unblocking user: $USER_ID"
    # Remove user from comma-separated list (handle all edge cases)
    if [ "$CURRENT_BLOCKED" = "$USER_ID" ]; then
        # Only user in the list
        NEW_BLOCKED=""
    else
        # Multiple users - remove this one
        NEW_BLOCKED=$(echo "$CURRENT_BLOCKED" | sed "s/^$USER_ID,//g" | sed "s/,$USER_ID$//g" | sed "s/,$USER_ID,/,/g")
    fi
else
    echo "🚫 Blocking user: $USER_ID"
    # Add user to comma-separated list (avoid duplicates)
    if echo "$CURRENT_BLOCKED" | grep -q "$USER_ID"; then
        echo "⚠️  User $USER_ID is already blocked"
        NEW_BLOCKED="$CURRENT_BLOCKED"
    else
        if [ -z "$CURRENT_BLOCKED" ]; then
            NEW_BLOCKED="$USER_ID"
        else
            NEW_BLOCKED="$CURRENT_BLOCKED,$USER_ID"
        fi
    fi
fi

echo "📝 New blocked users list: ${NEW_BLOCKED:-"(none)"}"

# Update each function
for FUNCTION_NAME in "${ACTUAL_FUNCTIONS[@]}"; do
    echo "🔄 Updating function: $FUNCTION_NAME"
    
    # Get current environment variables
    CURRENT_ENV=$(aws lambda get-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --query 'Environment.Variables' \
        --output json)
    
    # Update BLOCKED_USER_IDS and create new environment variables
    NEW_ENV=$(echo "$CURRENT_ENV" | jq --arg blocked "$NEW_BLOCKED" '.BLOCKED_USER_IDS = $blocked')
    
    # Write the complete environment structure to temp file
    TEMP_FILE=$(mktemp)
    echo "{\"Variables\": $NEW_ENV}" > "$TEMP_FILE"
    
    # Apply the updated environment variables
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment file://"$TEMP_FILE" > /dev/null
    
    # Clean up temp file
    rm "$TEMP_FILE"
    
    echo "✅ Updated $FUNCTION_NAME"
done

echo ""
if [ "$ACTION" = "unblock" ]; then
    echo "🎉 User $USER_ID has been unblocked and can now access the API"
    if [ -z "$NEW_BLOCKED" ]; then
        echo ""
        echo "📝 To persist this change for future deployments, update your .env file:"
        echo "   # Remove or comment out BLOCKED_USER_IDS line in ../backend/.env"
        echo "   sed -i '' '/^BLOCKED_USER_IDS=/d' ../backend/.env"
    else
        echo ""
        echo "📝 To persist this change for future deployments, update your .env file:"
        echo "   echo 'BLOCKED_USER_IDS=$NEW_BLOCKED' >> ../backend/.env"
    fi
else
    echo "🔒 User $USER_ID has been blocked from:"
    echo "   - Creating sessions (uploads)"
    echo "   - Updating session metadata" 
    echo "   - Deleting sessions"
    echo "   - Listing sessions"
    echo ""
    echo "📝 To persist this block for future deployments, run:"
    echo "   echo 'BLOCKED_USER_IDS=$NEW_BLOCKED' >> ../backend/.env"
    echo ""
    echo "To unblock: $0 $USER_ID unblock"
fi