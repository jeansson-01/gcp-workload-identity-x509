#!/bin/bash
# Add your custom values to the following required variables
export BILLING_ACCOUNT_ID="" # Only required if crating a new project
export PROJECT_ID="my-wif-demo-project"
export PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value core/project) --format=value\(projectNumber\))
export ZONE="us-central1-f"
export VPC="my-local-vpc"
export SUBNET="my-central1-subnet"
export VM_NAME="wlif-x509-demo-${RANDOM}"
export GCS_BUCKET="gs://my-wlif-example-bucket"
export WORKLOAD_POOL="x509-pool-082725-${RANDOM}"
export WORKLOAD_PROVIDER="local-demo-ca"
export ROOT_CA_NAME="root"
export SUB_CA_NAME="int"
export CLIENT_NAME="my-awesome-app"

# Validate Project
echo -e "Validating Project ${PROJECT_ID}...\n"
if ! gcloud projects describe ${PROJECT_ID} >/dev/null 2>&1; then
  echo -e "Project ${PROJECT_ID} does not exist. Creating it now..."
  gcloud projects create ${PROJECT_ID}
  # IMPORTANT: Replace 'BILLING_ACCOUNT_ID' with your actual billing account ID.
  gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT_ID}
fi

# Validate VPC
echo -e "Validating VPC ${VPC}...\n"
if ! gcloud compute networks describe ${VPC} --project=${PROJECT_ID} >/dev/null 2>&1; then
  echo -e "VPC ${VPC} not found. Creating it now..."
  gcloud compute networks create ${VPC} --project=${PROJECT_ID} --subnet-mode=custom
fi

# Validate Subnet
echo -e "Validating Subnet ${SUBNET}...\n"
REGION=${ZONE%-*} # Extract region from ZONE
if ! gcloud compute networks subnets describe ${SUBNET} --project=${PROJECT_ID} --region=${REGION} >/dev/null 2>&1; then
  echo -e "Subnet ${SUBNET} not found. Creating it now..."
  gcloud compute networks subnets create ${SUBNET} --project=${PROJECT_ID} --network=${VPC} --range=192.168.200.0/24 --region=${REGION}
fi

# Create test VM to mimic remote workload
echo -e "Creating VM ${VM_NAME} running without a service account to mimic a remote workload...\n"
gcloud compute instances create ${VM_NAME} --project=${PROJECT_ID} --zone=${ZONE} --machine-type=e2-small --network-interface=stack-type=IPV4_ONLY,subnet=${SUBNET},no-address --metadata=enable-osconfig=TRUE,enable-oslogin=true --maintenance-policy=MIGRATE --provisioning-model=STANDARD --no-service-account --no-scopes --create-disk=auto-delete=yes,boot=yes,device-name=wlif-x509-demo,image=projects/debian-cloud/global/images/debian-12-bookworm-v20250812,mode=rw,size=10,type=pd-balanced --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring

# Give the VM time to boot
echo -e "\nWaiting for VM to boot...\n"
sleep 30

# Remote configuration of demo VM via SSH
echo -e "Configuring test VM as a Certificate Authority and Client...\n"
gcloud compute ssh ${VM_NAME} --project=${PROJECT_ID} --zone=us-central1-f --command="bash -s" << EOF
# Create an openssl config for signing certificates
cat > example.cnf << INNER_EOF
[req]
distinguished_name = empty_distinguished_name
[empty_distinguished_name]
# Kept empty to allow setting via -subj command-line argument.
[ca_exts]
basicConstraints=critical,CA:TRUE
keyUsage=keyCertSign
extendedKeyUsage=clientAuth
[leaf_exts]
keyUsage=critical,Digital Signature, Key Encipherment
basicConstraints=critical, CA:FALSE
INNER_EOF

# Create a Root CA certificate
openssl req -x509 \
    -new -sha256 -newkey rsa:2048 -nodes \
    -days 3650 -subj "/CN=${ROOT_CA_NAME}" \
    -config example.cnf \
    -extensions ca_exts \
    -keyout root.key -out root.cert

# Create the signing request for the intermediate certificate
openssl req \
    -new -sha256 -newkey rsa:2048 -nodes \
    -subj "/CN=${SUB_CA_NAME}" \
    -config example.cnf \
    -extensions ca_exts \
    -keyout int.key -out int.req

# Create the intermediate certificate
openssl x509 -req \
    -CAkey root.key -CA root.cert \
    -set_serial 1 \
    -days 3650 \
    -extfile example.cnf \
    -extensions ca_exts \
    -in int.req -out int.cert

# Create the signing request for leaf certificate
openssl req -new -sha256 -newkey rsa:2048 -nodes \
    -subj "/CN=${CLIENT_NAME}" \
    -config example.cnf \
    -extensions leaf_exts \
    -keyout ${CLIENT_NAME}.key -out ${CLIENT_NAME}.req

# Create the client/leaf certificate issued by the intermediate
openssl x509 -req \
    -CAkey int.key -CA int.cert \
    -set_serial 1 -days 3650 \
    -extfile example.cnf \
    -extensions leaf_exts \
    -in ${CLIENT_NAME}.req -out ${CLIENT_NAME}.cert
EOF

# Create the Trust Store config file using the certificates created above
echo -e "\n\nCreating Trust Store config file on the VM...\n"
gcloud compute ssh ${VM_NAME} --project=${PROJECT_ID} --zone=${ZONE} --command="bash -s" << 'EOF'
# Save certifictes as one line strings
export ROOT_CERT=$(cat root.cert | sed 's/^[ ]*//g' | sed -z '$ s/\n$//' | tr '\n' $ | sed 's/\$/\\n/g')
export INTERMEDIATE_CERT=$(cat int.cert | sed 's/^[ ]*//g' | sed -z '$ s/\n$//' | tr '\n' $ | sed 's/\$/\\n/g')

# Create the Trust store config file
cat << INNER_EOF > trust_store.yaml
trustStore:
  trustAnchors:
  - pemCertificate: "${ROOT_CERT}"
  intermediateCas:
  - pemCertificate: "${INTERMEDIATE_CERT}"
INNER_EOF
EOF

# Copy the trust_config fromt the VM to the local machine. Its required to create the Workload Identity Pool Provider
echo -e "\n\nCopying trust store from VM...\n"
gcloud compute scp ${VM_NAME}:~/trust_store.yaml cloud_config/trust_store.yaml --project=${PROJECT_ID} --zone=${ZONE}
echo -e "\nTrust Store config file:\n"
cat cloud_config/trust_store.yaml

# Create the Workload Identity Pool
echo -e "\nCreating Workload Identity Pool ${WORKLOAD_POOL}...\n"
gcloud iam workload-identity-pools create ${WORKLOAD_POOL} \
    --location="global" \
    --description="Demo pool for x509 based federation" \
    --display-name="${WORKLOAD_POOL}" \
    --project=${PROJECT_ID}

# Create the Workload Identity Pool Provider
echo -e "\nCreating Workload Identity Pool Provider ${WORKLOAD_PROVIDER} using the trust store file...\n"
gcloud iam workload-identity-pools providers create-x509 ${WORKLOAD_PROVIDER} \
    --location=global \
    --workload-identity-pool="${WORKLOAD_POOL}" \
    --trust-store-config-path="cloud_config/trust_store.yaml" \
    --attribute-mapping="google.subject=assertion.subject.dn.cn" \
    --project=${PROJECT_ID}

# Validate Storage Bucket
if ! gcloud storage buckets describe ${GCS_BUCKET} --project=${PROJECT_ID} >/dev/null 2>&1; then
  echo -e "GCS Bucket ${GCS_BUCKET} not found. Creating it now..."
  gcloud storage buckets create ${GCS_BUCKET} --location=${REGION} --project=${PROJECT_ID}
fi

# Grant WLIF principal access to GCS Bucket
echo -e "\nGranting Workload identity principal access to GCS Bucket...\n"
gcloud storage buckets add-iam-policy-binding ${GCS_BUCKET} \
    --role=roles/storage.objectViewer \
    --member="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_POOL}/subject/${CLIENT_NAME}" \
    --project=${PROJECT_ID}

# Create the required client credentials config files
echo -e "\nCreating Workload identity credential configuration files...\n"
gcloud iam workload-identity-pools create-cred-config \
  projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_POOL}/providers/${WORKLOAD_PROVIDER} \
    --credential-cert-path=${CLIENT_NAME}.cert \
    --credential-cert-private-key-path=${CLIENT_NAME}.key \
    --credential-cert-trust-chain-path=int.cert \
    --credential-cert-configuration-output-file=cert-config.json \
    --output-file=client_config/wlif-x509-config.json
mv cert-config.json client_config/cert-config.json
echo -e "\nWorkload identity credential configuration files:\n"
cat client_config/wlif-x509-config.json
echo -e "\n\n"
cat client_config/cert-config.json

# Copy the WLIF credentials config file to the VM
echo -e "\nCopying credential configuration to VM...\n"
gcloud compute scp client_config/wlif-x509-config.json client_config/cert-config.json client_config/client_REST_token_exchange_example.sh ${VM_NAME}:~/ --project=${PROJECT_ID} --zone=${ZONE}

# Remote commands to test Authentication and bucket access test using WLIF x509 credentials from the VM via SSH
echo -e "\nTesting gcloud auth on VM...\n\n"
gcloud compute ssh ${VM_NAME} --project=${PROJECT_ID} --zone=us-central1-f --command="bash -i -s" << 'EOF'
echo -e "\nAuthenticating using: gcloud auth login --cred-file=wlif-x509-config.json to authenticate with GCP using x509 certificate...\n" 
gcloud auth login --cred-file=wlif-x509-config.json
echo -e "Attempting to list objects in GCS Bucket using federated credentials...\n\n\n"
gcloud storage ls gs://my-workload-id-federation-example-bucket
EOF

echo -e "\n\n\n*** This concludes the demo of x509 based AuthN/Z to GCP ***\n"
echo -e ">>> If you would like to test REST based Authentication, SSH into your VM, edit CLIENT_NAME variable in the ~/client_REST_token_exchange_example.sh file and run file. If you have successfully configured your environment you will get an access token back <<< \n"