# Workload Identity Federation with X.509 Certificates Demo

This repository contains a demonstration of how to configure and use Google Cloud's Workload Identity Federation to authenticate an external workload using a self-signed X.509 certificate.

The `wlif-x509-demo-setup.sh` script automates the entire process, from setting up the necessary Google Cloud infrastructure to creating a simulated external workload and testing the authentication.

## How it Works

The script performs the following actions:

1.  **Infrastructure Setup**: Creates a new Google Cloud project (if it doesn't exist), a VPC, and a subnet.
2.  **Simulated Workload**: Provisions a Google Compute Engine (GCE) VM without a service account. This VM simulates an on-premises or other cloud workload that needs to access Google Cloud resources.
3.  **Certificate Authority (CA) & Certificates**: On the GCE VM, it generates a self-signed root CA, an intermediate CA, and a client leaf certificate using `openssl`.
4.  **Workload Identity Federation Setup**:
    *   Creates a Workload Identity Pool in your Google Cloud project.
    *   Creates an X.509 Workload Identity Pool Provider, configured to trust the generated root CA.
    *   It maps the Common Name (`CN`) from the client certificate's subject to the `google.subject` attribute for the federated identity.
5.  **Permissions**: Creates a GCS bucket and grants the federated identity (`principal://...`) permission to view objects within it (`roles/storage.objectViewer`).
6.  **Authentication Test**:
    *   Generates the necessary credential configuration files.
    *   Copies these files to the simulated workload (the GCE VM).
    *   On the VM, it uses `gcloud auth login` with the generated configuration to authenticate using the X.509 certificate.
    *   Finally, it attempts to list the contents of the GCS bucket to verify that the authentication and authorization were successful.

## Prerequisites

1.  **Google Cloud SDK**: You must have the `gcloud` command-line tool installed and authenticated. You can find installation instructions [here](https://cloud.google.com/sdk/docs/install).
2.  **Billing Account**: You need a valid Google Cloud Billing Account ID.

## Running the Demo

1.  **Clone the repository or download the files.**

2.  **Configure the setup script.** Open the `wlif-x509-demo-setup.sh` file in a text editor.

3.  **IMPORTANT**: You **must** update the `BILLING_ACCOUNT_ID` variable with your own billing account ID.

    ```bash
    export BILLING_ACCOUNT_ID="012345-67890A-BCDEF1" # <-- REPLACE WITH YOUR ID
    ```

    You can also customize other variables like `PROJECT_ID`, `ZONE`, etc., if you wish.

4.  **Execute the script.** Run the following command from your terminal:

    ```bash
    bash wlif-x509-demo-setup.sh
    ```

The script will now run and print its progress to the console. It can take several minutes to complete as it provisions cloud resources.

## What to Expect

The script will output the steps it is taking. If successful, the final part of the output will show the script authenticating from the demo VM and successfully listing the contents of the GCS bucket, similar to this:

```
Authenticating using: gcloud auth login --cred-file=wlif-x509-config.json to authenticate with GCP using x509 certificate...

Your credentials are now active.
You can run `gcloud auth list` to see your active account.

Attempting to list objects in GCS Bucket using federated credentials...



*** This concludes the demo of x509 based AuthN/Z to GCP ***

>>> If you would like to test REST based Authentication, SSH into your VM, edit CLIENT_NAME variable in the ~/client_REST_token_exchange_example.sh file and run file. If you have successfully configured your environment you will get an access token back <<<
```

## Cleanup

To remove all the resources created by this demo, you can simply delete the Google Cloud project that was created.

```bash
gcloud projects delete your_project_id --quiet # Your custom PROJECT_ID
```
