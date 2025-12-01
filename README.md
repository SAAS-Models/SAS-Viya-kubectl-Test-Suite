# SAS Viya kubectl Test Suite

Comprehensive testing framework for SAS Viya 4 deployed on AWS Kubernetes (EKS) accessed through bastion host.

## Features

- 🔧 kubectl-based validation tests
- 🔐 Bastion host SSH tunnel support
- 🐍 Python and Bash test implementations
- 📊 HTML and JSON reporting
- 🔄 CI/CD integration (Jenkins, GitLab, GitHub Actions)
- 🐳 Docker containerized testing
- 📈 Continuous monitoring capabilities
- 🚀 Parallel test execution support

## Quick Start

### Prerequisites

- kubectl installed
- Python 3.8+
- SSH access to bastion host
- Kubernetes cluster access credentials

### Installation

```bash
# Clone repository
git clone https://github.com/your-org/sas-viya-kubectl-tests.git
cd sas-viya-kubectl-tests

# Install dependencies
make install

# Setup environment
make setup ENVIRONMENT=dev
```

### Running Tests

```bash
# Run smoke tests
make test TEST_TYPE=smoke

# Run full validation
make test TEST_TYPE=full

# Run specific component tests
./tests/kubectl/components/test_cas_server.sh

# Run Python tests
make test-python

# Start monitoring
make monitor
```

## Project Structure

```
├── config/          # Environment configurations
├── scripts/         # Setup and utility scripts
├── tests/           # Test implementations
│   ├── kubectl/     # Bash-based kubectl tests
│   ├── python/      # Python test suite
│   └── scenarios/   # End-to-end test scenarios
├── lib/            # Shared libraries
├── reports/        # Test reports
├── ci/             # CI/CD configurations
└── docker/         # Container definitions
```

## Configuration

Edit environment configurations in `config/environments/`:

```yaml
environment:
  name: dev
bastion:
  host: bastion.example.com
  user: ec2-user
  key_path: ~/.ssh/bastion.pem
kubernetes:
  cluster_name: sas-viya-cluster
  namespace: sas-viya
```

## CI/CD Integration

### Jenkins
```groovy
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                sh 'make test TEST_TYPE=full'
            }
        }
    }
}
```

### GitLab CI
```yaml
test:
  script:
    - make test TEST_TYPE=smoke
  artifacts:
    reports:
      junit: reports/junit.xml
```

## Reporting

Generate test reports:

```bash
# HTML report
make report REPORT_FORMAT=html

# View reports
open reports/test_report.html
```

## Docker Usage

```bash
# Build image
make docker-build

# Run tests in container
docker-compose up

# View reports
docker-compose --profile reports up
```

## Contributing

1. Fork the repository
2. Create feature branch
3. Add tests for new features
4. Submit pull request

## License

MIT

## Support

For issues and questions, please open a GitHub issue.
