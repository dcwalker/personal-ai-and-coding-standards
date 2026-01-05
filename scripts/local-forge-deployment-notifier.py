#!/usr/bin/env python3

"""
Local Deployment Notifier for Atlassian Compass

A portable script that sends deployment events to Compass during local Forge deployments.
Automatically creates event sources, tracks deployment state transitions (IN_PROGRESS → SUCCESSFUL/FAILED),
and uses GitHub commit URLs for meaningful, clickable deployment links.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SETUP INSTRUCTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. PREREQUISITES:
   - Forge CLI authenticated: `forge login`
   - catalog-info.yaml with metadata.name field
   - Component exists in Compass
   - Python 3.6+ with requests and pyyaml packages

2. REQUIRED ENVIRONMENT VARIABLES:
   export ATLASSIAN_USER_EMAIL="your.email@company.com"
   export ATLASSIAN_USER_API_KEY="your-atlassian-api-token"
   
   Get API token from: https://id.atlassian.com/manage-profile/security/api-tokens

3. OPTIONAL: Add GitHub repo to catalog-info.yaml for commit URLs:
   metadata:
     annotations:
       github.com/project-slug: org/repo-name

4. PACKAGE.JSON INTEGRATION:
   Add these scripts to your package.json:
   
   "scripts": {
     "deploy": "yarn build && python3 local_deployment_notifier.py",
     "deploy:dev": "yarn build && python3 local_deployment_notifier.py development",
     "deploy:staging": "yarn build && python3 local_deployment_notifier.py staging",
     "deploy:production": "yarn build && python3 local_deployment_notifier.py production"
   }

5. USAGE:
   yarn deploy:dev          # Deploy to development
   yarn deploy:staging      # Deploy to staging
   yarn deploy:production   # Deploy to production
   
   Or run directly with Python (not recommended):
   python3 local_deployment_notifier.py development --dry-run
   
   The script automatically:
   - Builds your Forge app (yarn build)
   - Sends IN_PROGRESS event to Compass
   - Runs forge deploy
   - Sends SUCCESSFUL/FAILED event based on result
   - Shows deployment events in Compass timeline with GitHub commit links

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HOW IT WORKS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DEPLOYMENT FLOW:
  1. Loads component info from catalog-info.yaml
  2. Discovers all Forge installations via `forge install list`
  3. Verifies component exists in each Compass installation
  4. Sends IN_PROGRESS event to all installations
  5. Runs `forge deploy` command
  6. Sends SUCCESSFUL or FAILED event based on deployment result

AUTOMATIC EVENT SOURCE CREATION:
  - If event source doesn't exist (404 error), automatically creates it via GraphQL API
  - Creates event source with type DEPLOYMENT and externalEventSourceId = component slug
  - Attaches event source to component
  - Retries sending the event
  - Fails deployment if automatic creation fails

STATE TRANSITIONS:
  - Each deployment gets a unique deployment run ID (deploy-{timestamp})
  - Both IN_PROGRESS and SUCCESSFUL/FAILED events use same:
    * pipelineId (deployment run ID)
    * url (GitHub commit URL or localhost URL)
    * startedAt timestamp
  - This makes them appear as a single deployment in Compass timeline, not separate events
  - Sequence numbers increase (IN_PROGRESS < SUCCESSFUL) for proper ordering

GITHUB COMMIT URLS:
  - Extracts github.com/project-slug from catalog-info.yaml
  - Uses full git commit hash to generate GitHub commit URL
  - Example: https://github.com/org/repo/commit/{full-hash}
  - Falls back to localhost URL if GitHub info unavailable
  - Provides clickable links to exact deployed code in Compass timeline

PAYLOAD STRUCTURE (Key fields for Compass to recognize state transitions):
  {
    "cloudId": "...",
    "event": {
      "deployment": {
        "updateSequenceNumber": 1234567890123,  # Timestamp in ms, increases with each event
        "displayName": "component-name deployment",
        "description": "Branch: main, Hash: abc123, Env: dev, User: ...",
        "url": "https://github.com/org/repo/commit/{hash}",  # Same for both events
        "externalEventSourceId": "component-slug",  # Component identifier
        "deploymentProperties": {
          "sequenceNumber": 1234567890123,  # Same as updateSequenceNumber
          "state": "IN_PROGRESS" | "SUCCESSFUL" | "FAILED",
          "pipeline": {
            "pipelineId": "deploy-1234567890123",  # Unique per deployment, same for both events
            "url": "https://github.com/org/repo/commit/{hash}",  # Same as deployment.url
            "displayName": "Local Forge Deployment - abc123"
          },
          "environment": {
            "displayName": "development",
            "environmentId": "DEVELOPMENT",
            "category": "DEVELOPMENT"  # PRODUCTION | STAGING | TESTING | DEVELOPMENT | UNMAPPED
          },
          "startedAt": "2025-11-05T00:00:00Z",  # Same for both events
          "completedAt": "2025-11-05T00:01:00Z"  # Only in final state
        }
      }
    }
  }

ERROR HANDLING:
  - Validates authentication credentials before deployment
  - Sends FAILED events to successful installations if any installation fails during IN_PROGRESS
  - Shows detailed error messages with request/response details
  - Fails deployment if automatic event source creation fails
  - Graceful fallback for missing GitHub info or git commands

INSTALLATION DISCOVERY:
  - Uses `forge install list --json` to find all installations
  - Gets cloud IDs from /_edge/tenant_info endpoint
  - Queries Compass GraphQL API to verify component exists
  - Processes all installations regardless of Forge environment
  - Deployment environment metadata preserved in event payload

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

404 EVENT_SOURCE_NOT_FOUND:
  Script will automatically create the event source and retry. If that fails, deployment
  will abort with an error message.

Events appear as separate entries instead of state transitions:
  This should not happen - each deployment generates a unique pipelineId and uses the
  same URL for both IN_PROGRESS and SUCCESSFUL events. Check that both events show
  the same pipelineId in dry-run output.

Authentication errors:
  Verify ATLASSIAN_USER_EMAIL and ATLASSIAN_USER_API_KEY are set correctly.
  Generate new token at: https://id.atlassian.com/manage-profile/security/api-tokens

Component not found:
  Ensure component with matching slug exists in Compass installation.
  Component slug must match metadata.name in catalog-info.yaml.

Git commands fail:
  Script gracefully handles missing git info, falling back to 'unknown' for hash/branch.
  GitHub URLs will use localhost fallback if git is unavailable.
"""

import requests
import json
import os
import subprocess
import sys
import argparse
import yaml
import time
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime, timezone

# Configuration
ATLASSIAN_USER_EMAIL = os.environ.get("ATLASSIAN_USER_EMAIL")
ATLASSIAN_USER_API_KEY = os.environ.get("ATLASSIAN_USER_API_KEY")

HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json",
}

VALID_ENVIRONMENT_TYPES = [
    'PRODUCTION',
    'STAGING', 
    'TESTING',
    'DEVELOPMENT',
    'UNMAPPED'
]

class LocalDeploymentNotifier:
    def __init__(self, environment: str, dry_run: bool = False):
        self.environment = environment
        self.environment_type = self.validate_and_map_environment(environment)
        self.dry_run = dry_run
        self.component_slug = ""
        self.github_repo = None  # Will be loaded from catalog-info.yaml
        self.installations: List[Dict[str, str]] = []
        # Generate unique deployment run ID for this deployment
        # This ensures IN_PROGRESS and SUCCESSFUL/FAILED events are recognized as the same deployment
        self.deployment_run_id = f"deploy-{int(datetime.now(timezone.utc).timestamp() * 1000)}"
        self.deployment_start_time = datetime.now(timezone.utc).isoformat()
        
    def validate_and_map_environment(self, user_input: str) -> str:
        """Validate and map environment input to standard environment type"""
        normalized_input = user_input.upper()
        if normalized_input in VALID_ENVIRONMENT_TYPES:
            return normalized_input
        return 'UNMAPPED'
    
    def get_cloud_id(self, site_url: str) -> Optional[str]:
        """Get cloud ID from Atlassian site URL"""
        print(f"Attempting to retrieve Cloud ID for {site_url}...")
        
        if not site_url.startswith("https://"):
            site_url = "https://" + site_url
        if not site_url.endswith("/"):
            site_url = site_url + "/"
            
        tenant_info_url = f"{site_url}_edge/tenant_info"
        
        try:
            response = requests.get(tenant_info_url, timeout=10)
            response.raise_for_status()
            tenant_data = response.json()
            cloud_id = tenant_data.get("cloudId")
            
            if cloud_id:
                print(f"Successfully retrieved Cloud ID: {cloud_id}")
                return cloud_id
            else:
                print(f"Error: Could not retrieve cloudId from {tenant_info_url}")
                return None
                
        except requests.exceptions.RequestException as e:
            print(f"Error fetching Cloud ID from {tenant_info_url}: {e}")
            return None
        except json.JSONDecodeError:
            print(f"Error: Invalid JSON response from {tenant_info_url}")
            return None
    
    def run_command(self, command: List[str]) -> Tuple[bool, str, str]:
        """Run shell command and return success, stdout, stderr"""
        try:
            result = subprocess.run(
                command, 
                capture_output=True, 
                text=True, 
                check=False
            )
            return result.returncode == 0, result.stdout.strip(), result.stderr.strip()
        except Exception as e:
            return False, "", str(e)
    
    def get_git_info(self) -> Dict[str, str]:
        """Get git branch and commit hash"""
        success, hash_output, _ = self.run_command(['git', 'rev-parse', '--short', 'HEAD'])
        git_hash = hash_output if success else 'unknown'
        
        success, branch_output, _ = self.run_command(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
        branch = branch_output if success else 'unknown'
        
        return {'hash': git_hash, 'branch': branch}
    
    def get_forge_info(self) -> Dict[str, str]:
        """Get forge user information"""
        success, output, error = self.run_command(['forge', 'whoami'])
        
        if not success:
            raise Exception(
                'Failed to execute "forge whoami". Please ensure Forge CLI is installed and run "forge login" to authenticate.'
            )
        
        user = ""
        account_id = ""
        
        for line in output.split('\n'):
            if line.startswith('Logged in as:'):
                user = line.replace('Logged in as:', '').strip()
            elif line.startswith('Logged in as '):
                user = line.replace('Logged in as ', '').strip()
            elif line.startswith('Account ID:'):
                account_id = line.replace('Account ID:', '').strip()
        
        if not user or not account_id:
            raise Exception(
                'Unable to get valid user information from Forge CLI. '
                'Please run "forge login" to authenticate with Atlassian Forge.'
            )
        
        return {'user': user, 'account_id': account_id}
    
    def get_all_installations(self) -> List[Dict[str, str]]:
        """Get all forge installations (regardless of environment)"""
        success, output, error = self.run_command(['forge', 'install', 'list', '--json'])
        
        if not success:
            print(f"Failed to get forge installations: {error}")
            return []
        
        try:
            installations = json.loads(output)
        except json.JSONDecodeError:
            print(f"Failed to parse forge installations JSON: {output}")
            return []
        
        # Get all installations, not just matching environment
        # The deployment environment will be preserved in the notification payload
        result = []
        for install in installations:
            cloud_id = self.get_cloud_id(install['site'])
            if cloud_id:
                result.append({
                    'site_url': install['site'], 
                    'cloud_id': cloud_id,
                    'forge_environment': install.get('environment', 'unknown')
                })
        
        return result
    
    def get_uncommitted_files(self) -> List[str]:
        """Get list of uncommitted files from git"""
        success, output, _ = self.run_command(['git', 'status', '--porcelain'])
        
        if not success:
            return []
        
        return [
            line[3:] for line in output.split('\n') 
            if line.strip()
        ]
    
    def make_graphql_request(self, endpoint_url: str, query: str, variables: Optional[Dict] = None) -> Optional[Dict]:
        """Make GraphQL request to Compass API"""
        payload = {"query": query}
        if variables:
            payload["variables"] = variables
        
        auth = (ATLASSIAN_USER_EMAIL, ATLASSIAN_USER_API_KEY)
        
        try:
            response = requests.post(
                endpoint_url, 
                headers=HEADERS, 
                auth=auth, 
                json=payload, 
                timeout=30
            )
            response.raise_for_status()
            data = response.json()
            
            if "errors" in data and data["errors"]:
                print(f"GraphQL API returned errors:")
                for error in data["errors"]:
                    print(f"  - {error.get('message', 'Unknown error')}")
            
            return data
            
        except requests.exceptions.RequestException as e:
            print(f"Request to {endpoint_url} failed: {e}")
            return None
        except json.JSONDecodeError as e:
            print(f"Failed to decode JSON response: {e}")
            return None
    
    def search_component_by_slug(self, slug: str, cloud_id: str, site_url: str) -> Optional[str]:
        """Search for component by slug and return component ID"""
        graphql_endpoint = f"https://{site_url}/gateway/api/graphql"
        
        query = """
        query getComponentsByReferences($references: [ComponentReferenceInput!]!) {
          compass {
            componentsByReferences(references: $references) {
              __typename
              ... on CompassComponent {
                id
                name
                typeId
                slug
              }
            }
          }
        }
        """
        
        variables = {
            "references": [
                {
                    "slug": {
                        "slug": slug,
                        "cloudId": cloud_id
                    }
                }
            ]
        }
        
        response = self.make_graphql_request(graphql_endpoint, query, variables)
        
        if not response or not response.get("data"):
            return None
        
        components = response.get("data", {}).get("compass", {}).get("componentsByReferences", [])
        
        if not components:
            print(f"❌ No component found with slug '{slug}'")
            return None
        
        # Should only be one component since we're querying by specific slug
        component = components[0]
        
        if component.get("__typename") == "CompassComponent":
            component_id = component.get("id")
            print(f"✅ Found component '{slug}' with ID: {component_id}")
            return component_id
        else:
            print(f"❌ Component query returned unexpected type: {component.get('__typename')}")
            return None
    
    def create_and_attach_event_source(self, cloud_id: str, component_id: str, site_url: str, external_source_id: str) -> bool:
        """Create and attach a deployment event source for the component
        
        This creates an event source in Compass via GraphQL API and attaches it to the component.
        Returns True if successful, False otherwise.
        """
        graphql_endpoint = f"https://{site_url}/gateway/api/graphql"
        
        # Step 1: Create the event source
        print(f"   📝 Creating deployment event source '{external_source_id}'...")
        
        create_mutation = """
        mutation createEventSource($input: CreateEventSourceInput!) {
          compass {
            createEventSource(input: $input) {
              success
              eventSource {
                id
              }
              errors {
                message
              }
            }
          }
        }
        """
        
        create_variables = {
            "input": {
                "cloudId": cloud_id,
                "eventType": "DEPLOYMENT",
                "externalEventSourceId": external_source_id
            }
        }
        
        create_response = self.make_graphql_request(graphql_endpoint, create_mutation, create_variables)
        
        if not create_response or not create_response.get("data"):
            print(f"   ❌ Failed to create event source - no response data")
            return False
        
        result = create_response.get("data", {}).get("compass", {}).get("createEventSource", {})
        
        if result.get("errors"):
            print(f"   ❌ Errors creating event source:")
            for error in result["errors"]:
                print(f"      - {error.get('message')}")
            return False
        
        if not result.get("success") or not result.get("eventSource"):
            print(f"   ❌ Failed to create event source")
            return False
        
        event_source_id = result["eventSource"]["id"]
        print(f"   ✅ Created event source: {event_source_id}")
        
        # Step 2: Attach the event source to the component
        print(f"   🔗 Attaching event source to component...")
        
        attach_mutation = """
        mutation attachEventSource($input: AttachEventSourceInput!) {
          compass {
            attachEventSource(input: $input) {
              success
              errors {
                message
              }
            }
          }
        }
        """
        
        attach_variables = {
            "input": {
                "eventSourceId": event_source_id,
                "componentId": component_id
            }
        }
        
        attach_response = self.make_graphql_request(graphql_endpoint, attach_mutation, attach_variables)
        
        if not attach_response or not attach_response.get("data"):
            print(f"   ❌ Failed to attach event source - no response data")
            return False
        
        attach_result = attach_response.get("data", {}).get("compass", {}).get("attachEventSource", {})
        
        if attach_result.get("errors"):
            print(f"   ❌ Errors attaching event source:")
            for error in attach_result["errors"]:
                print(f"      - {error.get('message')}")
            return False
        
        if not attach_result.get("success"):
            print(f"   ❌ Failed to attach event source")
            return False
        
        print(f"   ✅ Event source attached successfully!")
        return True
    
    def load_catalog_info(self) -> Tuple[str, Optional[str]]:
        """Load component name and GitHub repo from catalog-info.yaml
        
        Returns:
            Tuple of (component_name, github_repo_slug)
            github_repo_slug will be None if not found in annotations
        """
        catalog_path = os.path.join(os.getcwd(), 'catalog-info.yaml')
        
        if not os.path.exists(catalog_path):
            raise Exception('catalog-info.yaml not found')
        
        with open(catalog_path, 'r') as f:
            catalog_content = f.read()
        
        catalog_docs = list(yaml.safe_load_all(catalog_content))
        
        # Find the Component document
        for doc in catalog_docs:
            if (doc and isinstance(doc, dict) and 
                'metadata' in doc and 
                'name' in doc['metadata']):
                
                component_name = doc['metadata']['name']
                
                # Try to extract GitHub repo from annotations
                github_repo = None
                if 'annotations' in doc['metadata']:
                    annotations = doc['metadata']['annotations']
                    # Check for github.com/project-slug annotation
                    if 'github.com/project-slug' in annotations:
                        github_repo = annotations['github.com/project-slug']
                        print(f"📦 GitHub repository: {github_repo}")
                
                return component_name, github_repo
        
        raise Exception('No component metadata found in catalog-info.yaml')
    
    def initialize_installations(self) -> None:
        """Initialize installations and verify components exist
        
        Note: Event sources are created automatically when sending events if they don't exist.
        This method only verifies that components exist in Compass installations.
        """
        installations = self.get_all_installations()
        
        if not installations:
            print(f"⚠️  No forge installations found. "
                  "Deployment will proceed without sending notifications.")
            self.installations = []
            return
        
        self.installations = []
        
        for installation in installations:
            site_url = installation['site_url']
            cloud_id = installation['cloud_id']
            
            # Clean up site URL for GraphQL endpoint
            if site_url.startswith('https://'):
                site_url = site_url[8:]  # Remove https://
            if site_url.endswith('/'):
                site_url = site_url[:-1]  # Remove trailing slash
            
            try:
                component_id = self.search_component_by_slug(
                    self.component_slug, 
                    cloud_id, 
                    site_url
                )
                
                if not component_id:
                    print(f"⚠️  Component '{self.component_slug}' not found in {installation['site_url']}")
                    continue
                
                print(f"✅ Component '{self.component_slug}' found in {installation['site_url']}")
                
                # Store installation info
                # Event source existence will be checked when sending events
                self.installations.append({
                    'site_url': installation['site_url'],
                    'cloud_id': cloud_id,
                    'component_id': component_id
                })
                    
            except Exception as e:
                print(f"❌ Failed to verify component in {installation['site_url']}: {e}")
                continue
        
        # If installations were found but none could be verified, fail
        if installations and not self.installations:
            raise Exception(
                f"Found {len(installations)} forge installation(s), "
                f"but component '{self.component_slug}' could not be verified in any of them. "
                "Cannot proceed with deployment as notifications cannot be sent to existing installations."
            )
    
    def create_compass_url(self, site_url: str) -> str:
        """Create Compass component URL for the given site"""
        # Clean up the site URL
        clean_site = site_url
        if clean_site.startswith('https://'):
            clean_site = clean_site[8:]
        if clean_site.endswith('/'):
            clean_site = clean_site[:-1]
        
        return f"https://{clean_site}/compass/component/{self.component_slug}"
    
    def create_deployment_description(self) -> str:
        """Create deployment description with git and forge info"""
        git_info = self.get_git_info()
        forge_info = self.get_forge_info()
        uncommitted_files = self.get_uncommitted_files()
        
        description = (
            f"Branch: {git_info['branch']}\n"
            f"Commit: {git_info['hash']}\n"
            f"Forge User: {forge_info['user']}"
        )
        
        if uncommitted_files:
            files_str = '\n  - '.join(uncommitted_files)
            description += f"\nUncommitted files:\n  - {files_str}"
        
        # Truncate if too long
        max_length = 255
        if len(description) > max_length:
            description = description[:max_length - 3] + '...'
        
        return description
    
    def create_deployment_url(self, git_info: Dict[str, str]) -> str:
        """Create deployment URL - uses GitHub commit URL if available, otherwise localhost
        
        Returns:
            GitHub commit URL like: https://github.com/procore/atlassian-compass-admin-tools/commit/b4188335
            Or falls back to: https://localhost/atlassian-compass-admin-tools/deploy-{id}
        """
        if self.github_repo and git_info.get('hash') != 'unknown':
            # Get full commit hash for GitHub URL
            success, full_hash, _ = self.run_command(['git', 'rev-parse', 'HEAD'])
            commit_hash = full_hash if success else git_info['hash']
            return f"https://github.com/{self.github_repo}/commit/{commit_hash}"
        else:
            # Fallback to localhost URL
            return f"https://localhost/{self.component_slug}/{self.deployment_run_id}"
    
    def create_event_payload(self, installation: Dict[str, str], state: str, 
                           description: str, git_info: Dict[str, str]) -> Dict:
        """Create Compass deployment event payload
        
        Note: The payload structure follows the Compass REST API format.
        Events for the same deployment run use the same pipelineId and URL so Compass
        recognizes them as state transitions of a single deployment rather than separate events.
        
        The URL will be a GitHub commit URL if available, providing a clickable link to the
        exact code that was deployed.
        """
        now = datetime.now(timezone.utc).isoformat()
        # Use timestamp in milliseconds for sequence numbers to ensure proper ordering
        # Each state transition gets a new sequence number (IN_PROGRESS < SUCCESSFUL/FAILED)
        sequence_number = int(datetime.now(timezone.utc).timestamp() * 1000)
        
        # Generate deployment URL - uses GitHub commit URL if available
        deployment_url = self.create_deployment_url(git_info)
        
        # Build deployment properties, omitting None values
        deployment_properties = {
            "sequenceNumber": sequence_number,
            "state": state,
            "pipeline": {
                # Use deployment run ID to link IN_PROGRESS and SUCCESSFUL/FAILED events
                "pipelineId": f"{self.deployment_run_id}",
                # Use same URL for both events so Compass links them together
                "url": deployment_url,
                "displayName": f"Local Forge Deployment - {git_info['hash']}"
            },
            "environment": {
                "displayName": self.environment,
                "environmentId": self.environment_type,
                "category": self.environment_type
            }
        }
        
        # Use deployment start time for IN_PROGRESS, current time for completions
        # This ensures timeline shows accurate deployment duration
        if state == 'IN_PROGRESS':
            deployment_properties["startedAt"] = self.deployment_start_time
        else:
            deployment_properties["completedAt"] = now
            # Also include startedAt for completed deployments to show full lifecycle
            deployment_properties["startedAt"] = self.deployment_start_time
        
        return {
            "cloudId": installation['cloud_id'],
            # Note: componentId removed - events are matched via externalEventSourceId
            "event": {
                "deployment": {
                    "updateSequenceNumber": sequence_number,
                    "displayName": f"{self.component_slug} deployment",
                    "description": description,
                    # Use same deployment URL for event-level URL
                    "url": deployment_url,
                    "lastUpdated": now,
                    # Use component slug as externalEventSourceId for stable identification
                    # This should match the external event source configured in Compass
                    "externalEventSourceId": self.component_slug,
                    "deploymentProperties": deployment_properties
                }
            }
        }
    
    def send_deployment_event(self, state: str) -> None:
        """Send deployment event to all installations"""
        if not self.installations:
            print("ℹ️  No installations available - skipping deployment event notifications")
            return
        
        # Validate authentication credentials
        if not ATLASSIAN_USER_EMAIL or not ATLASSIAN_USER_API_KEY:
            print("❌ Missing authentication credentials:")
            print(f"   ATLASSIAN_USER_EMAIL: {'✓' if ATLASSIAN_USER_EMAIL else '❌ NOT SET'}")
            print(f"   ATLASSIAN_USER_API_KEY: {'✓' if ATLASSIAN_USER_API_KEY else '❌ NOT SET'}")
            raise Exception("Missing required environment variables for API authentication")
        
        print(f"🔐 Using authentication:")
        print(f"   Email: {ATLASSIAN_USER_EMAIL}")
        # Don't log API key value to avoid security issues - just confirm it's set
        print(f"   API Key: {'✓ SET' if ATLASSIAN_USER_API_KEY else '❌ NOT SET'}")
        
        description = self.create_deployment_description()
        git_info = self.get_git_info()
        
        if self.dry_run:
            print(f"🔍 DRY RUN: Would send {state} event to {len(self.installations)} installation(s)")
            for installation in self.installations:
                payload = self.create_event_payload(installation, state, description, git_info)
                print(f"  - {installation['site_url']}: {json.dumps(payload, indent=2)}")
            return
        
        if state == 'IN_PROGRESS':
            self.send_in_progress_notifications(description, git_info)
        else:
            self.send_final_notifications(state, description, git_info)
    
    def send_in_progress_notifications(self, description: str, git_info: Dict[str, str]) -> None:
        """Send IN_PROGRESS notifications - must all succeed"""
        successful_installations = []
        failures = []
        needs_setup = []
        
        for installation in self.installations:
            try:
                payload = self.create_event_payload(installation, 'IN_PROGRESS', description, git_info)
                
                print(f"📡 Sending IN_PROGRESS to {installation['site_url']}")
                
                response = requests.post(
                    'https://api.atlassian.com/compass/v1/events',
                    headers=HEADERS,
                    auth=(ATLASSIAN_USER_EMAIL, ATLASSIAN_USER_API_KEY),
                    json=payload,
                    timeout=30
                )
                
                if response.status_code == 404:
                    # Event source not found - try to create it automatically
                    try:
                        response_data = response.json()
                        if any(err.get('type') == 'CREATE_EVENT_SOURCE_NOT_FOUND' 
                               for err in response_data.get('errors', [])):
                            print(f"⚠️  Event source not found - attempting automatic creation...")
                            
                            # Extract site_url without https:// and trailing /
                            clean_site = installation['site_url'].replace('https://', '').replace('/', '')
                            
                            # Try to create and attach the event source
                            if self.create_and_attach_event_source(
                                installation['cloud_id'],
                                installation['component_id'],
                                clean_site,
                                self.component_slug
                            ):
                                # Success! Retry sending the event
                                print(f"   🔄 Retrying event submission...")
                                retry_response = requests.post(
                                    'https://api.atlassian.com/compass/v1/events',
                                    headers=HEADERS,
                                    auth=(ATLASSIAN_USER_EMAIL, ATLASSIAN_USER_API_KEY),
                                    json=payload,
                                    timeout=30
                                )
                                
                                if retry_response.status_code in [200, 202]:
                                    successful_installations.append(installation)
                                    print(f"✅ IN_PROGRESS event sent to {installation['site_url']}")
                                    continue
                                else:
                                    print(f"   ❌ Retry failed with status {retry_response.status_code}")
                            
                            # If we get here, automatic creation failed
                            needs_setup.append(installation)
                            continue
                    except Exception as create_error:
                        print(f"   ❌ Failed to auto-create event source: {create_error}")
                        needs_setup.append(installation)
                        continue
                
                if response.status_code not in [200, 202]:
                    print(f"   Request URL: https://api.atlassian.com/compass/v1/events")
                    print(f"   Request payload: {json.dumps(payload, indent=2)}")
                    print(f"   Response status: {response.status_code}")
                    print(f"   Response headers: {dict(response.headers)}")
                    
                    try:
                        response_data = response.json()
                        print(f"   Response body: {json.dumps(response_data, indent=2)}")
                    except:
                        print(f"   Response body (raw): {response.text}")
                    
                    raise Exception(f"HTTP {response.status_code}: {response.text}")
                
                successful_installations.append(installation)
                print(f"✅ IN_PROGRESS event sent to {installation['site_url']}")
                
            except Exception as e:
                failures.append({'site_url': installation['site_url'], 'error': str(e)})
                print(f"❌ Failed to send IN_PROGRESS event to {installation['site_url']}: {e}")
        
        # Fail if automatic event source creation failed
        if needs_setup:
            failed_sites = [installation['site_url'] for installation in needs_setup]
            raise Exception(
                f"Event source creation failed for {len(needs_setup)} installation(s): {', '.join(failed_sites)}. "
                f"Automatic event source creation was attempted but failed."
            )
        
        # If any failed for other reasons, send FAILED to successful ones and abort
        if failures:
            print(f"❌ {len(failures)} notification(s) failed. "
                  f"Sending FAILED events to {len(successful_installations)} successful installation(s) and aborting.")
            
            for installation in successful_installations:
                try:
                    payload = self.create_event_payload(installation, 'FAILED', description, git_info)
                    
                    print(f"📡 Sending FAILED (cleanup) to {installation['site_url']}")
                    
                    response = requests.post(
                        'https://api.atlassian.com/compass/v1/events',
                        headers=HEADERS,
                        auth=(ATLASSIAN_USER_EMAIL, ATLASSIAN_USER_API_KEY),
                        json=payload,
                        timeout=30
                    )
                    
                    if response.status_code not in [200, 202]:
                        print(f"   Request payload: {json.dumps(payload, indent=2)}")
                        print(f"   Response status: {response.status_code}")
                        try:
                            response_data = response.json()
                            print(f"   Response body: {json.dumps(response_data, indent=2)}")
                        except:
                            print(f"   Response body (raw): {response.text}")
                    
                    compass_url = self.create_compass_url(installation['site_url'])
                    print(f"✅ FAILED event sent to {installation['site_url']}")
                    print(f"   🔗 View component: {compass_url}")
                    
                except Exception as e:
                    print(f"❌ Failed to send FAILED event to {installation['site_url']}: {e}")
            
            failed_sites = [f['site_url'] for f in failures]
            raise Exception(f"Deployment aborted: Failed to send notifications to {len(failures)} installation(s): {', '.join(failed_sites)}")
        
        print(f"✅ All {len(successful_installations)} IN_PROGRESS notifications sent successfully")
    
    def send_final_notifications(self, state: str, description: str, git_info: Dict[str, str]) -> None:
        """Send final notifications (best effort)"""
        for installation in self.installations:
            try:
                payload = self.create_event_payload(installation, state, description, git_info)
                
                print(f"📡 Sending {state} to {installation['site_url']}")
                
                response = requests.post(
                    'https://api.atlassian.com/compass/v1/events',
                    headers=HEADERS,
                    auth=(ATLASSIAN_USER_EMAIL, ATLASSIAN_USER_API_KEY),
                    json=payload,
                    timeout=30
                )
                
                if response.status_code not in [200, 202]:
                    print(f"   Request URL: https://api.atlassian.com/compass/v1/events")
                    print(f"   Request payload: {json.dumps(payload, indent=2)}")
                    print(f"   Response status: {response.status_code}")
                    print(f"   Response headers: {dict(response.headers)}")
                    
                    try:
                        response_data = response.json()
                        print(f"   Response body: {json.dumps(response_data, indent=2)}")
                    except:
                        print(f"   Response body (raw): {response.text}")
                    
                    raise Exception(f"HTTP {response.status_code}: {response.text}")
                
                # For final notifications, also show the Compass component URL
                if state in ['SUCCESSFUL', 'FAILED']:
                    compass_url = self.create_compass_url(installation['site_url'])
                    print(f"✅ {state} event sent to {installation['site_url']}")
                    print(f"   🔗 View component: {compass_url}")
                else:
                    print(f"✅ {state} event sent to {installation['site_url']}")
                
            except Exception as e:
                print(f"❌ Failed to send {state} event to {installation['site_url']}: {e}")
                # Don't fail deployment for final notification failures
    
    def run_forge_deploy(self) -> None:
        """Run forge deploy command"""
        if self.dry_run:
            print("🔍 DRY RUN: Would run 'forge deploy'")
            return
        
        print("🚀 Running forge deploy...")
        success, stdout, stderr = self.run_command(['forge', 'deploy'])
        
        if stdout:
            print(stdout)
        if stderr:
            print(stderr, file=sys.stderr)
        
        if not success:
            raise Exception("forge deploy command failed")
    
    def deploy(self) -> None:
        """Main deployment process"""
        in_progress_sent = False
        deployment_succeeded = False
        
        try:
            # Initialize
            self.component_slug, self.github_repo = self.load_catalog_info()
            print(f"Component: {self.component_slug}")
            print(f"Environment: {self.environment} ({self.environment_type})")
            
            if self.dry_run:
                print("🔍 DRY RUN MODE - No actual deployment or API calls will be made")
            
            self.initialize_installations()
            
            # Send IN_PROGRESS
            print("📡 Sending IN_PROGRESS notifications...")
            self.send_deployment_event('IN_PROGRESS')
            in_progress_sent = True
            
            # Run deployment
            self.run_forge_deploy()
            deployment_succeeded = True
            
            # Send SUCCESS
            print("📡 Sending SUCCESS notifications...")
            self.send_deployment_event('SUCCESSFUL')
            print("✅ Deployment completed successfully!")
            print()
            print("📍 Compass Component Links:")
            for installation in self.installations:
                compass_url = self.create_compass_url(installation['site_url'])
                print(f"   🔗 {installation['site_url']}: {compass_url}")
            
        except Exception as e:
            print(f"❌ Deployment failed: {e}")
            
            # Only send FAILED if IN_PROGRESS was sent and deployment actually failed
            if in_progress_sent and not deployment_succeeded:
                try:
                    print("📡 Sending FAILED notifications...")
                    self.send_deployment_event('FAILED')
                except Exception as failed_error:
                    print(f"❌ Failed to send FAILED notifications: {failed_error}")
            elif in_progress_sent and deployment_succeeded:
                print("❌ Deployment succeeded but failed to send SUCCESS notifications. Not sending FAILED notifications.")
            
            sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Send deployment notifications to Atlassian Compass during forge deployments"
    )
    parser.add_argument(
        "environment", 
        help="Deployment environment (development, staging, production, etc.)"
    )
    parser.add_argument(
        "--dry-run", 
        action="store_true",
        help="Show what would be done without making actual API calls or running deployment"
    )
    
    args = parser.parse_args()
    
    # Validate environment variables
    if not ATLASSIAN_USER_EMAIL or not ATLASSIAN_USER_API_KEY:
        print("❌ Error: ATLASSIAN_USER_EMAIL and ATLASSIAN_USER_API_KEY environment variables are required.")
        print("   Please set these variables with your Atlassian account email and API token.")
        print("   See: https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/")
        sys.exit(1)
    
    notifier = LocalDeploymentNotifier(args.environment, args.dry_run)
    notifier.deploy()


if __name__ == "__main__":
    main() 