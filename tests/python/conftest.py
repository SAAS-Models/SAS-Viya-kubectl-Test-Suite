"""
pytest configuration for kubectl tests
"""

import pytest
import os
import yaml
from pathlib import Path
import sys

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib" / "python"))

from kubectl_client import KubectlClient


def pytest_addoption(parser):
    """Add command line options"""
    parser.addoption(
        "--namespace",
        action="store",
        default="sas-viya",
        help="Kubernetes namespace"
    )
    parser.addoption(
        "--environment",
        action="store",
        default="dev",
        help="Environment to test (dev/staging/prod)"
    )
    parser.addoption(
        "--use-bastion",
        action="store_true",
        default=False,
        help="Use bastion host for connection"
    )
    parser.addoption(
        "--context",
        action="store",
        default=None,
        help="kubectl context to use"
    )


@pytest.fixture(scope="session")
def test_config(request):
    """Load test configuration"""
    env = request.config.getoption("--environment")
    config_path = Path(__file__).parent.parent.parent / "config" / "environments" / f"{env}.yaml"
    
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    config['namespace'] = request.config.getoption("--namespace")
    config['use_bastion'] = request.config.getoption("--use-bastion")
    config['context'] = request.config.getoption("--context")
    
    return config


@pytest.fixture(scope="session")
def kubectl_client(test_config):
    """Create kubectl client"""
    return KubectlClient(
        namespace=test_config['namespace'],
        context=test_config.get('context')
    )


@pytest.fixture
def sas_components(test_config):
    """Get expected SAS components from config"""
    return test_config.get('sas_components', {})


@pytest.fixture(autouse=True)
def test_metadata(request, record_property):
    """Add metadata to test results"""
    if hasattr(request.config, '_metadata'):
        request.config._metadata['namespace'] = request.config.getoption("--namespace")
        request.config._metadata['environment'] = request.config.getoption("--environment")


@pytest.fixture
def namespace(test_config):
    """Get namespace from config"""
    return test_config['namespace']
