#!/bin/bash
# REST based token exchange (run from local machine)
export CLIENT_NAME="example" # REPLACE WITH YOUR CLIENT NAME
export LEAF_CERT=$(openssl x509 -in ${CLIENT_NAME}.cert -out ${CLIENT_NAME}.der -outform DER && cat ${CLIENT_NAME}.der | openssl enc -base64 -A)
export INTERMEDIATE_CERT=$(openssl x509 -in int.cert -out int.der -outform DER && cat int.der | openssl enc -base64 -A)
export TRUST_CHAIN="[\\\"${LEAF_CERT}\\\", \\\"${INTERMEDIATE_CERT}\\\"]"

curl --key ${CLIENT_NAME}.key \
--cert ${CLIENT_NAME}.cert \
--request POST 'https://sts.mtls.googleapis.com/v1/token' \
--header "Content-Type: application/json" \
--data-raw "{
    \"subject_token_type\": \"urn:ietf:params:oauth:token-type:mtls\",
    \"grant_type\": \"urn:ietf:params:oauth:grant-type:token-exchange\",
    \"audience\": \"//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_POOL}/providers/${WORKLOAD_PROVIDER}\",
    \"requested_token_type\": \"urn:ietf:params:oauth:token-type:access_token\",
    \"scope\": \"https://www.googleapis.com/auth/cloud-platform\",
    \"subject_token\": \"${SUBJECT_TOKEN_STRING}\"
}"
