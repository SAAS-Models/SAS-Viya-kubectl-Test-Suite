"""
Test Kubernetes deployments for SAS Viya
"""

import pytest
import time


class TestDeployments:
    """Test SAS Viya deployments"""
    
    @pytest.mark.critical
    def test_namespace_exists(self, kubectl_client, namespace):
        """Test if namespace exists"""
        success, stdout, _ = kubectl_client.execute(["get", "namespace", namespace])
        assert success, f"Namespace {namespace} does not exist"
    
    @pytest.mark.critical
    def test_cas_controller_deployment(self, kubectl_client):
        """Test CAS controller deployment"""
        deployments = kubectl_client.get_deployments()
        cas_deployments = [d for d in deployments 
                          if 'cas' in d.get('metadata', {}).get('name', '').lower()]
        
        assert len(cas_deployments) > 0, "No CAS deployments found"
        
        for deployment in cas_deployments:
            name = deployment['metadata']['name']
            ready_replicas = deployment.get('status', {}).get('readyReplicas', 0)
            desired_replicas = deployment.get('spec', {}).get('replicas', 1)
            
            assert ready_replicas == desired_replicas, \
                f"Deployment {name}: {ready_replicas}/{desired_replicas} replicas ready"
    
    @pytest.mark.critical
    def test_core_microservices(self, kubectl_client, sas_components):
        """Test core microservices are deployed"""
        deployments = kubectl_client.get_deployments()
        deployment_names = [d['metadata']['name'] for d in deployments]
        
        required_services = sas_components.get('microservices', [])
        missing_services = []
        
        for service in required_services:
            found = any(service in name for name in deployment_names)
            if not found:
                missing_services.append(service)
        
        assert len(missing_services) == 0, \
            f"Missing microservices: {', '.join(missing_services)}"
    
    @pytest.mark.infrastructure
    def test_statefulsets(self, kubectl_client, sas_components):
        """Test statefulsets (databases, etc.)"""
        statefulsets = kubectl_client.get_statefulsets()
        
        # Check PostgreSQL
        if sas_components.get('databases', {}).get('postgres', {}).get('enabled'):
            postgres_sts = [s for s in statefulsets 
                          if 'postgres' in s['metadata']['name'].lower()]
            assert len(postgres_sts) > 0, "PostgreSQL StatefulSet not found"
            
            for sts in postgres_sts:
                ready_replicas = sts.get('status', {}).get('readyReplicas', 0)
                desired_replicas = sts.get('spec', {}).get('replicas', 1)
                assert ready_replicas == desired_replicas, \
                    f"PostgreSQL not fully ready: {ready_replicas}/{desired_replicas}"
    
    @pytest.mark.slow
    def test_deployment_rollout_status(self, kubectl_client):
        """Check if all deployments have successfully rolled out"""
        deployments = kubectl_client.get_deployments()
        failed_rollouts = []
        
        for deployment in deployments:
            name = deployment['metadata']['name']
            conditions = deployment.get('status', {}).get('conditions', [])
            
            # Check for Progressing condition
            progressing = next((c for c in conditions if c['type'] == 'Progressing'), None)
            if progressing and progressing.get('status') != 'True':
                failed_rollouts.append(f"{name}: {progressing.get('message', 'Unknown error')}")
            
            # Check for Available condition
            available = next((c for c in conditions if c['type'] == 'Available'), None)
            if available and available.get('status') != 'True':
                failed_rollouts.append(f"{name}: Not available")
        
        assert len(failed_rollouts) == 0, \
            f"Failed rollouts:\n" + "\n".join(failed_rollouts)
    
    @pytest.mark.resources
    def test_deployment_resource_limits(self, kubectl_client):
        """Check if deployments have resource limits set"""
        deployments = kubectl_client.get_deployments()
        missing_limits = []
        
        for deployment in deployments:
            name = deployment['metadata']['name']
            containers = deployment.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
            
            for container in containers:
                resources = container.get('resources', {})
                if not resources.get('limits'):
                    missing_limits.append(f"{name}/{container['name']}")
        
        # Warning only, not failing
        if missing_limits:
            pytest.skip(f"Containers without resource limits: {', '.join(missing_limits[:5])}")
    
    @pytest.mark.replicas
    def test_deployment_replicas(self, kubectl_client):
        """Test if critical deployments have multiple replicas"""
        deployments = kubectl_client.get_deployments()
        
        # Critical services that should have multiple replicas in production
        critical_services = ['sas-logon', 'sas-identities', 'sas-authorization']
        single_replica_critical = []
        
        for deployment in deployments:
            name = deployment['metadata']['name']
            replicas = deployment.get('spec', {}).get('replicas', 1)
            
            for critical in critical_services:
                if critical in name.lower() and replicas < 2:
                    single_replica_critical.append(f"{name}: {replicas} replica(s)")
        
        if single_replica_critical:
            pytest.skip(f"Critical services with single replica: {', '.join(single_replica_critical)}")
